/**
 * ntfy Notify Extension
 *
 * Sends a push notification via ntfy when the agent has finished
 * (`agent_settled`) and you have NOT seen the result within N seconds
 * (default 60). At most one notification per finished run.
 *
 * "Seen" means any of these happened after the run finished:
 * - the pi terminal gained focus (focus-in report; kitty + tmux pane/window)
 * - the terminal was focused and you did something: keypress, mouse, scroll
 *   in pi, or moved the mouse cursor anywhere (Hyprland `hyprctl cursorpos`)
 * - you submitted a prompt / a new run started
 * Terminal focused but no activity for N seconds => you're away => notify.
 * Terminal unfocused (other window/tmux pane) => notify after N seconds.
 *
 * Only active in interactive TUI mode (never in print/json/rpc, so
 * subagents don't spam you).
 *
 * Credentials/host are read from ~/.config/ntfy/client.yml
 * (default-host / default-user / default-password or default-token).
 * Optional overrides in ~/.pi/agent/ntfy-notify.json:
 *   { "enabled": true, "topic": "general", "host": "https://ntfy.sautter.dev",
 *     "delaySeconds": 60, "priority": 3 }
 *
 * Command:
 *   /ntfy             - show status
 *   /ntfy on|off      - enable / disable (persisted)
 *   /ntfy test        - send a test notification now
 */

import { execFile } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { getAgentDir } from "@earendil-works/pi-coding-agent";

const CONFIG_FILE = join(getAgentDir(), "ntfy-notify.json");
const NTFY_CLIENT_FILE = join(homedir(), ".config", "ntfy", "client.yml");

type Config = {
	enabled: boolean;
	topic: string;
	host?: string;
	delaySeconds: number;
	priority: number;
};

type Auth = { host?: string; user?: string; password?: string; token?: string };

function loadConfig(): Config {
	const defaults: Config = { enabled: true, topic: "general", delaySeconds: 60, priority: 3 };
	try {
		return { ...defaults, ...(JSON.parse(readFileSync(CONFIG_FILE, "utf8")) as Partial<Config>) };
	} catch {
		return defaults;
	}
}

/** Minimal parse of the top-level default-* keys in ntfy's client.yml. */
function loadNtfyAuth(): Auth {
	const auth: Auth = {};
	try {
		for (const line of readFileSync(NTFY_CLIENT_FILE, "utf8").split("\n")) {
			const m = /^default-(host|user|password|token):\s*(.*?)\s*$/.exec(line);
			if (!m) continue;
			const value = m[2].replace(/^(["'])(.*)\1$/, "$2");
			auth[m[1] as keyof Auth] = value;
		}
	} catch {
		// No client config: send unauthenticated.
	}
	return auth;
}

const FOCUS_IN = "\x1b[I";
const FOCUS_OUT = "\x1b[O";

/** Strip focus and terminal reports (color scheme, DA, cursor pos); what's left is user input. */
function stripReports(data: string): string {
	return data
		.split(FOCUS_IN)
		.join("")
		.split(FOCUS_OUT)
		.join("")
		.replace(/\x1b\[\?[\d;]*[nc]/g, "")
		.replace(/\x1b\[\d+;\d+R/g, "")
		.replace(/\x1b\][^\x07\x1b]*(\x07|\x1b\\)/g, "");
}

function cursorPos(): Promise<string | undefined> {
	if (!process.env.HYPRLAND_INSTANCE_SIGNATURE) return Promise.resolve(undefined);
	return new Promise((resolve) => {
		execFile("hyprctl", ["cursorpos"], { timeout: 2000 }, (err, stdout) => {
			resolve(err ? undefined : stdout.trim());
		});
	});
}

function lastAssistantText(ctx: ExtensionContext): string {
	try {
		const branch = ctx.sessionManager.getBranch();
		for (let i = branch.length - 1; i >= 0; i--) {
			const entry = branch[i];
			if (entry.type !== "message" || entry.message.role !== "assistant") continue;
			const content = entry.message.content as unknown;
			if (typeof content === "string") return content;
			if (Array.isArray(content)) {
				const text = content
					.filter((b) => b && b.type === "text" && typeof b.text === "string")
					.map((b) => b.text as string)
					.join("\n")
					.trim();
				if (text) return text;
			}
		}
	} catch {
		// best effort
	}
	return "";
}

export default function (pi: ExtensionAPI) {
	let config = loadConfig();
	let timer: ReturnType<typeof setTimeout> | undefined;
	let pending: { ctx: ExtensionContext; aborted: boolean; title?: string; message?: string } | undefined;
	let unsubscribeInput: (() => void) | undefined;
	let sessionCtx: ExtensionContext | undefined;
	let pollTimer: ReturnType<typeof setInterval> | undefined;
	/** Terminal focus as reported by focus-in/out events; assume focused until told otherwise. */
	let focused = true;

	const cancel = () => {
		if (timer) clearTimeout(timer);
		if (pollTimer) clearInterval(pollTimer);
		timer = undefined;
		pollTimer = undefined;
		pending = undefined;
	};

	/**
	 * Raw stdin tap (pi's own viewport listener swallows focus reports before
	 * extension input listeners see them, so listen on the stream directly).
	 */
	const onStdin = (chunk: Buffer | string) => {
		const data = typeof chunk === "string" ? chunk : chunk.toString("utf8");
		const lastIn = data.lastIndexOf(FOCUS_IN);
		const lastOut = data.lastIndexOf(FOCUS_OUT);
		if (lastIn > lastOut) {
			focused = true;
			if (pending) cancel(); // you switched to pi: seen
		} else if (lastOut > lastIn) {
			focused = false;
		}
		if (stripReports(data).length > 0) {
			focused = true; // input only arrives while focused
			if (pending) cancel(); // key/mouse/scroll in pi: seen
		}
	};

	const detachStdin = () => {
		process.stdin.off("data", onStdin);
	};

	const persist = () => {
		try {
			writeFileSync(CONFIG_FILE, `${JSON.stringify(config, null, 2)}\n`);
		} catch {
			// non-fatal
		}
	};

	async function send(title: string, message: string, tags: string[] = []): Promise<void> {
		const auth = loadNtfyAuth();
		const host = (config.host ?? auth.host ?? "https://ntfy.sh").replace(/\/+$/, "");
		const headers: Record<string, string> = { "Content-Type": "application/json" };
		if (auth.token) headers.Authorization = `Bearer ${auth.token}`;
		else if (auth.user && auth.password)
			headers.Authorization = `Basic ${Buffer.from(`${auth.user}:${auth.password}`).toString("base64")}`;

		// JSON publishing avoids header-encoding issues with non-ASCII titles.
		const res = await fetch(host, {
			method: "POST",
			headers,
			body: JSON.stringify({ topic: config.topic, title, message, tags, priority: config.priority }),
			signal: AbortSignal.timeout(10_000),
		});
		if (!res.ok) throw new Error(`ntfy HTTP ${res.status}: ${(await res.text()).slice(0, 200)}`);
	}

	function buildMessage(ctx: ExtensionContext, aborted: boolean): { title: string; message: string } {
		const name = pi.getSessionName?.() || basename(ctx.cwd) || ctx.cwd;
		const title = `pi ${aborted ? "stopped" : "finished"}: ${name}`;
		let text = lastAssistantText(ctx).replace(/\s+/g, " ").trim();
		if (text.length > 300) text = `${text.slice(0, 297)}...`;
		return { title, message: text || "Waiting for your input." };
	}

	const arm = () => {
		if (!pending) return;
		if (timer) clearTimeout(timer);
		if (pollTimer) clearInterval(pollTimer);
		pollTimer = undefined;

		// Terminal focused but maybe nobody at the desk: any mouse movement
		// (Hyprland) while pi is focused counts as "seen".
		if (process.env.HYPRLAND_INSTANCE_SIGNATURE) {
			const armed = pending;
			void cursorPos().then((start) => {
				if (start === undefined || pending !== armed) return;
				pollTimer = setInterval(async () => {
					if (!focused || pending !== armed) return;
					const now = await cursorPos();
					if (now !== undefined && now !== start && focused && pending === armed) cancel();
				}, 3000);
			});
		}

		timer = setTimeout(async () => {
			const p = pending;
			cancel();
			if (!p || !config.enabled) return;
			const built = buildMessage(p.ctx, p.aborted);
			const title = p.title ?? built.title;
			const message = p.message ?? built.message;
			try {
				await send(title, message, ["robot"]);
			} catch (err) {
				try {
					p.ctx.ui.notify(`ntfy notification failed: ${(err as Error).message}`, "error");
				} catch {
					// context may be stale
				}
			}
		}, config.delaySeconds * 1000);
	};

	pi.on("session_start", (_event, ctx) => {
		cancel();
		unsubscribeInput?.();
		unsubscribeInput = undefined;
		config = loadConfig();
		sessionCtx = undefined;
		if (ctx.mode !== "tui" || !ctx.hasUI) return;
		sessionCtx = ctx;
		focused = true;
		// Make sure focus reporting is on (pi enables it with mouse support; idempotent).
		if (process.stdout.isTTY) process.stdout.write("\x1b[?1004h");
		detachStdin();
		process.stdin.on("data", onStdin);
		unsubscribeInput = () => {
			detachStdin();
			if (process.stdout.isTTY) process.stdout.write("\x1b[?1004l");
		};
	});

	pi.on("agent_settled", (event, ctx) => {
		cancel();
		if (!config.enabled || ctx.mode !== "tui" || !ctx.hasUI) return;
		// Aborted runs are usually you pressing Esc - you're obviously present.
		if ((event as { aborted?: boolean }).aborted) return;
		pending = { ctx, aborted: false };
		arm();
	});

	// You answered / something new started: no notification needed.
	pi.on("input", () => {
		cancel();
	});
	pi.on("agent_start", () => {
		cancel();
	});

	// mobile-mode: the ask_user picker blocks mid-run (no agent_settled), so it
	// announces itself here. Same idle countdown, cancelled once answered.
	pi.events.on("mobile-mode:waiting", (data) => {
		if (!config.enabled || !sessionCtx) return;
		const d = (data ?? {}) as { title?: string; message?: string };
		pending = { ctx: sessionCtx, aborted: false, title: d.title, message: d.message };
		arm();
	});
	pi.events.on("mobile-mode:answered", () => {
		cancel();
	});

	pi.on("session_shutdown", () => {
		sessionCtx = undefined;
		cancel();
		unsubscribeInput?.();
		unsubscribeInput = undefined;
	});

	pi.registerCommand("ntfy", {
		description: "ntfy idle notifications (/ntfy [on|off|test])",
		handler: async (args, ctx) => {
			const arg = (args ?? "").trim().toLowerCase();
			if (arg === "on" || arg === "off") {
				config.enabled = arg === "on";
				persist();
				if (!config.enabled) cancel();
			} else if (arg === "test") {
				try {
					await send("pi: test notification", `ntfy works (${basename(ctx.cwd)})`, ["test_tube"]);
					ctx.ui.notify(`Test notification sent to topic "${config.topic}"`);
				} catch (err) {
					ctx.ui.notify(`ntfy test failed: ${(err as Error).message}`, "error");
				}
				return;
			}
			const host = config.host ?? loadNtfyAuth().host ?? "https://ntfy.sh";
			ctx.ui.notify(
				`ntfy notifications ${config.enabled ? "enabled" : "disabled"} - ${host}/${config.topic}, after ${config.delaySeconds}s unseen (terminal ${focused ? "focused" : "unfocused"})`,
			);
		},
	});
}
