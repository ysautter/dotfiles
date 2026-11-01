/**
 * Anthropic Accounts Extension
 *
 * Switch between several Claude subscriptions (OAuth logins) that all use the
 * built-in `anthropic` provider, so @gotgenes/pi-anthropic-auth keeps shaping
 * every request. The active login lives in ~/.pi/agent/auth.json (where pi
 * refreshes it); inactive logins are parked in
 * ~/.pi/agent/anthropic-accounts.json (mode 600, contains secrets).
 *
 * Setup (once per subscription):
 *   /login anthropic                      - log in with subscription A
 *   /anthropic-account save personal      - remember it as "personal"
 *   /login anthropic                      - log in with subscription B
 *   /anthropic-account save work          - remember it as "work"
 *
 * Usage:
 *   alt+a                                 - cycle to the next account
 *   /anthropic-account                    - pick an account from a list
 *   /anthropic-account <name> [--force]   - switch to <name>
 *   /anthropic-account list               - list accounts
 *   /anthropic-account remove <name>      - forget an account
 *
 * The footer shows the active account. Note: auth.json is shared, so a switch
 * applies to all running pi instances (others update their footer on the next
 * turn).
 */

import { chmodSync, existsSync, mkdirSync, readFileSync, rmdirSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { getAgentDir } from "@earendil-works/pi-coding-agent";
import { Key } from "@earendil-works/pi-tui";

const PROVIDER = "anthropic";
const SHORTCUT = Key.alt("a");
const STATUS_KEY = "anthropic-account";
const AUTH_FILE = join(getAgentDir(), "auth.json");
const STORE_FILE = join(getAgentDir(), "anthropic-accounts.json");
const PROFILE_URL = "https://api.anthropic.com/api/oauth/profile";

type Credential = { type: string; [k: string]: unknown };
type Account = { credential: Credential; email?: string };
type Store = { active?: string; accounts: Record<string, Account> };

// ---------- files ----------

function readJson<T>(path: string, fallback: T): T {
	try {
		return JSON.parse(readFileSync(path, "utf-8").replace(/^\uFEFF/, "")) as T;
	} catch {
		return fallback;
	}
}

function writeSecret(path: string, data: unknown): void {
	writeFileSync(path, JSON.stringify(data, null, 2), { encoding: "utf-8", mode: 0o600 });
	chmodSync(path, 0o600);
}

function loadStore(): Store {
	const s = readJson<Store>(STORE_FILE, { accounts: {} });
	if (!s.accounts || typeof s.accounts !== "object") s.accounts = {};
	return s;
}

/** Lock compatible with pi's proper-lockfile usage on auth.json (`auth.json.lock` dir). */
async function withAuthLock<T>(fn: () => T): Promise<T> {
	const lock = `${AUTH_FILE}.lock`;
	const deadline = Date.now() + 5000;
	for (;;) {
		try {
			mkdirSync(lock);
			break;
		} catch (e) {
			if ((e as NodeJS.ErrnoException).code !== "EEXIST") throw e;
			try {
				if (Date.now() - statSync(lock).mtimeMs > 30000) {
					rmdirSync(lock);
					continue;
				}
			} catch {}
			if (Date.now() > deadline) throw new Error("auth.json is locked (timeout)");
			await new Promise((r) => setTimeout(r, 50));
		}
	}
	try {
		return fn();
	} finally {
		try {
			rmdirSync(lock);
		} catch {}
	}
}

// ---------- helpers ----------

function isOAuth(c: unknown): c is Credential {
	return !!c && typeof c === "object" && (c as Credential).type === "oauth";
}

async function currentEmail(ctx: ExtensionContext): Promise<string | undefined> {
	// Pi refreshes an expiring token before returning it.
	const token = await ctx.modelRegistry.getApiKeyForProvider(PROVIDER);
	if (!token?.startsWith("sk-ant-oat")) throw new Error("no Anthropic OAuth login in auth.json");
	const res = await fetch(PROFILE_URL, {
		headers: { Authorization: `Bearer ${token}`, "anthropic-beta": "oauth-2025-04-20" },
		signal: AbortSignal.timeout(5000),
	});
	if (!res.ok) throw new Error(`profile lookup failed: HTTP ${res.status}`);
	const body = (await res.json()) as { account?: { email?: unknown } };
	return typeof body.account?.email === "string" ? body.account.email : undefined;
}

function updateStatus(ctx: ExtensionContext): void {
	if (!ctx.hasUI) return;
	const store = loadStore();
	const names = Object.keys(store.accounts);
	if (names.length === 0 || !store.active) {
		ctx.ui.setStatus(STATUS_KEY, undefined);
		return;
	}
	const t = ctx.ui.theme;
	const onAnthropic = ctx.model?.provider === PROVIDER;
	const label = `claude:${store.active}`;
	ctx.ui.setStatus(STATUS_KEY, onAnthropic ? t.fg("accent", `◆ ${label}`) : t.fg("dim", `◇ ${label}`));
}

// ---------- operations ----------

async function save(name: string, ctx: ExtensionContext): Promise<void> {
	const auth = readJson<Record<string, unknown>>(AUTH_FILE, {});
	if (!isOAuth(auth[PROVIDER])) throw new Error("no Anthropic OAuth login in auth.json – run /login anthropic first");
	let email: string | undefined;
	try {
		email = await currentEmail(ctx);
	} catch (e) {
		ctx.ui.notify(`Could not verify account email (${(e as Error).message}); saving anyway`, "warning");
	}
	const store = loadStore();
	const dup = Object.entries(store.accounts).find(([n, a]) => n !== name && email && a.email === email);
	if (dup) throw new Error(`this login (${email}) is already saved as "${dup[0]}"`);
	// Re-read after the (possibly refreshing) profile lookup.
	const fresh = readJson<Record<string, unknown>>(AUTH_FILE, {})[PROVIDER];
	store.accounts[name] = { credential: (isOAuth(fresh) ? fresh : auth[PROVIDER]) as Credential, email };
	store.active = name;
	writeSecret(STORE_FILE, store);
	ctx.ui.notify(`Saved Anthropic account "${name}"${email ? ` (${email})` : ""} – now active`, "info");
}

async function switchTo(target: string, ctx: ExtensionContext, force = false): Promise<void> {
	const store = loadStore();
	const account = store.accounts[target];
	if (!account) throw new Error(`unknown account "${target}" (known: ${Object.keys(store.accounts).join(", ") || "none"})`);
	if (store.active === target) {
		ctx.ui.notify(`Anthropic account "${target}" is already active`, "info");
		return;
	}
	const from = store.active;

	// Guard: make sure auth.json really holds the active account before parking it,
	// otherwise a fresh /login would be filed under the wrong name.
	if (from && store.accounts[from]?.email && !force) {
		let email: string | undefined;
		try {
			email = await currentEmail(ctx);
		} catch (e) {
			throw new Error(`${(e as Error).message} – use "/anthropic-account ${target} --force" to switch anyway`);
		}
		if (email && email !== store.accounts[from].email) {
			throw new Error(
				`auth.json holds ${email}, not "${from}" (${store.accounts[from].email}). ` +
					`Save it first with /anthropic-account save <name>, or use --force (discards it).`,
			);
		}
	}

	await withAuthLock(() => {
		const auth = readJson<Record<string, unknown>>(AUTH_FILE, {});
		if (from && store.accounts[from] && isOAuth(auth[PROVIDER]) && !force) {
			store.accounts[from].credential = auth[PROVIDER] as Credential;
		}
		auth[PROVIDER] = account.credential;
		writeSecret(AUTH_FILE, auth);
		store.active = target;
		writeSecret(STORE_FILE, store);
	});
	ctx.ui.notify(`Anthropic account: ${target}${account.email ? ` (${account.email})` : ""}`, "info");
}

async function cycle(ctx: ExtensionContext): Promise<void> {
	const store = loadStore();
	const names = Object.keys(store.accounts);
	if (names.length < 2) {
		ctx.ui.notify("Need at least two saved accounts – see /anthropic-account save <name>", "warning");
		return;
	}
	const next = names[(names.indexOf(store.active ?? "") + 1) % names.length];
	await switchTo(next, ctx);
}

// ---------- extension ----------

export default function (pi: ExtensionAPI) {
	const run = async (ctx: ExtensionContext, fn: () => Promise<void>) => {
		try {
			await fn();
		} catch (e) {
			ctx.ui.notify(`anthropic-account: ${(e as Error).message}`, "error");
		}
		updateStatus(ctx);
	};

	pi.registerShortcut(SHORTCUT, {
		description: "Cycle Anthropic subscription account",
		handler: async (ctx) => run(ctx, () => cycle(ctx)),
	});

	pi.registerCommand("anthropic-account", {
		description: "Switch/save Anthropic subscription accounts (save <name> | remove <name> | list | <name>)",
		getArgumentCompletions: (prefix) => {
			const opts = ["save", "remove", "list", ...Object.keys(loadStore().accounts)];
			const m = opts.filter((o) => o.startsWith(prefix));
			return m.length ? m.map((o) => ({ value: o, label: o })) : null;
		},
		handler: async (args, ctx) =>
			run(ctx, async () => {
				const parts = (args ?? "").trim().split(/\s+/).filter(Boolean);
				const force = parts.includes("--force");
				const [cmd, name] = parts.filter((p) => p !== "--force");
				const store = loadStore();

				if (!cmd) {
					const names = Object.keys(store.accounts);
					if (names.length === 0) throw new Error("no accounts saved – use /anthropic-account save <name>");
					const items = names.map((n) => `${n === store.active ? "● " : "  "}${n}${store.accounts[n].email ? `  (${store.accounts[n].email})` : ""}`);
					const picked = await ctx.ui.select("Anthropic account", items);
					if (picked) await switchTo(names[items.indexOf(picked)], ctx);
				} else if (cmd === "save") {
					if (!name || !/^[\w.-]+$/.test(name)) throw new Error("usage: /anthropic-account save <name> (letters, digits, . _ -)");
					await save(name, ctx);
				} else if (cmd === "remove") {
					if (!name || !store.accounts[name]) throw new Error(`unknown account "${name ?? ""}"`);
					delete store.accounts[name];
					if (store.active === name) store.active = undefined;
					writeSecret(STORE_FILE, store);
					ctx.ui.notify(`Removed Anthropic account "${name}" (auth.json unchanged)`, "info");
				} else if (cmd === "list") {
					const lines = Object.entries(store.accounts).map(
						([n, a]) => `${n === store.active ? "●" : " "} ${n}${a.email ? `  ${a.email}` : ""}`,
					);
					ctx.ui.notify(lines.length ? lines.join("\n") : "no accounts saved", "info");
				} else {
					await switchTo(cmd, ctx, force);
				}
			}),
	});

	pi.on("session_start", async (_e, ctx) => updateStatus(ctx));
	pi.on("model_select", async (_e, ctx) => updateStatus(ctx));
	pi.on("turn_start", async (_e, ctx) => updateStatus(ctx));

	if (!existsSync(STORE_FILE)) return;
	try {
		chmodSync(STORE_FILE, 0o600);
	} catch {}
}
