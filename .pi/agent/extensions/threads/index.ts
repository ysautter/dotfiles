/**
 * Threads Extension - logical conversation threads + open-items tracker
 *
 * Problem: one session often spawns several side questions. Forking/cloning
 * duplicates the session; instead this keeps ONE linear session but tags every
 * exchange with a logical thread, so follow-ups land "under" their thread.
 *
 * Features
 *  - `thread` tool: the model opens/switches/resolves threads and maintains
 *    per-thread items (goals, tasks, questions). Batched ops = one call.
 *  - Widget above the editor: all threads, active one highlighted, open items.
 *  - The model starts each part of a reply with a `[[#n]]` marker; the text is
 *    split at markers and filed under thread n. Markers render as dividers
 *    "⤷ #2 · Title" (display-only, via Markdown transformer).
 *  - Address a thread yourself: start your message with "#2 " (thread must
 *    exist), or pick one with /thread. The model is told which thread you mean.
 *  - /threads: browser; Enter shows a thread's conversation grouped on its own
 *    (all its follow-ups, in order), "r" = reply in that thread.
 *
 * State is snapshotted into tool-result details / custom entries, so it is
 * branch-aware (/tree navigation restores the right state).
 *
 * Commands:
 *   /threads                 browse threads + view a thread's conversation
 *   /thread [n|new <title>]  set the thread your next message goes to
 *   /board  (Alt+T)      all open threads on one screen, a reply box per thread,
 *                        Enter sends all replies as ONE message ("#n " sections)
 *   /thread-widget [full|compact|off]   (also Alt+H cycles; persisted in threads.json)
 */

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { StringEnum } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext, MarkdownTransformContext, Theme } from "@earendil-works/pi-coding-agent";
import { getAgentDir, getMarkdownTheme } from "@earendil-works/pi-coding-agent";
import { type Component, Editor, Key, Markdown, matchesKey, truncateToWidth } from "@earendil-works/pi-tui";
import { Type } from "typebox";

// ---------------------------------------------------------------- types

type ItemKind = "goal" | "task" | "question";
type ThreadStatus = "open" | "parked" | "resolved";

interface Item {
	id: string; // "<thread>.<n>"
	text: string;
	kind: ItemKind;
	done: boolean;
	dropped?: boolean;
}

interface Thread {
	id: number;
	title: string;
	parent?: number;
	status: ThreadStatus;
	note?: string;
	/** The user's question/request that started this thread (verbatim excerpt). */
	question?: string;
	items: Item[];
	nextItem: number;
}

interface State {
	threads: Thread[];
	active?: number;
	nextId: number;
}

interface ToolDetails {
	state: State;
	log: string[];
	errors: string[];
	ops: Op[];
}

interface Op {
	op: string;
	thread?: number;
	title?: string;
	parent?: number;
	text?: string;
	kind?: ItemKind;
	item?: string;
	items?: string[];
	note?: string;
	question?: string;
	activate?: boolean;
}

const STATE_ENTRY = "threads-state";
const CONTEXT_MSG = "threads-context";
const TOOL = "thread";

const emptyState = (): State => ({ threads: [], nextId: 1 });
const clone = (s: State): State => JSON.parse(JSON.stringify(s));

// ---------------------------------------------------------------- helpers

function textOf(content: unknown): string {
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	return content
		.filter((b) => b && (b as { type: string }).type === "text")
		.map((b) => (b as { text?: string }).text ?? "")
		.join("");
}

function assistantTexts(content: unknown): string[] {
	if (!Array.isArray(content)) return [];
	return content
		.filter((b) => b && (b as { type: string }).type === "text" && typeof (b as { text?: string }).text === "string")
		.map((b) => ((b as { text: string }).text as string).trim())
		.filter(Boolean);
}

const openItems = (t: Thread) => t.items.filter((i) => !i.done && !i.dropped);
const liveItems = (t: Thread) => t.items.filter((i) => !i.dropped);
const kindIcon = (k: ItemKind) => (k === "goal" ? "◎" : k === "question" ? "?" : "☐");

/** Threads ordered as a tree (parent before children), with depth. */
function treeOrder(state: State): { t: Thread; depth: number }[] {
	const out: { t: Thread; depth: number }[] = [];
	const ids = new Set(state.threads.map((t) => t.id));
	const visit = (parent: number | undefined, depth: number) => {
		for (const t of state.threads) {
			const p = t.parent !== undefined && ids.has(t.parent) ? t.parent : undefined;
			if (p === parent) {
				out.push({ t, depth });
				visit(t.id, depth + 1);
			}
		}
	};
	visit(undefined, 0);
	return out;
}

/** Compact plain-text state for the model. */
function stateForModel(state: State): string {
	if (state.threads.length === 0) return "(no threads yet)";
	const lines: string[] = [];
	for (const { t, depth } of treeOrder(state)) {
		if (t.status === "resolved" && t.id !== state.active) {
			lines.push(`${"  ".repeat(depth)}#${t.id} [resolved] ${t.title}`);
			continue;
		}
		const mark = t.id === state.active ? " (ACTIVE)" : "";
		lines.push(`${"  ".repeat(depth)}#${t.id} [${t.status}]${mark} ${t.title}`);
		for (const i of liveItems(t)) {
			lines.push(`${"  ".repeat(depth)}  ${i.done ? "[x]" : "[ ]"} ${i.id} (${i.kind}) ${i.text}`);
		}
	}
	return lines.join("\n");
}

// ---------------------------------------------------------------- op engine

function applyOps(input: State, ops: Op[]): { state: State; log: string[]; errors: string[] } {
	const state = clone(input);
	const log: string[] = [];
	const errors: string[] = [];
	const find = (id: number | undefined) => state.threads.find((t) => t.id === (id ?? state.active));
	const findItem = (ref: string | undefined) => {
		if (!ref) return undefined;
		const tid = Number(ref.split(".")[0]);
		const t = state.threads.find((x) => x.id === tid);
		return t ? { t, i: t.items.find((x) => x.id === ref) } : undefined;
	};
	const addItem = (t: Thread, text: string, kind: ItemKind = "task") => {
		const item: Item = { id: `${t.id}.${t.nextItem++}`, text, kind, done: false };
		t.items.push(item);
		return item;
	};

	for (const o of ops) {
		switch (o.op) {
			case "open": {
				if (!o.title) {
					errors.push("open: title required");
					break;
				}
				const t: Thread = {
					id: state.nextId++,
					title: o.title,
					parent: o.parent,
					question: o.question,
					status: "open",
					items: [],
					nextItem: 1,
				};
				state.threads.push(t);
				for (const text of o.items ?? []) addItem(t, text, o.kind);
				if (o.activate !== false || state.active === undefined) state.active = t.id;
				log.push(`opened #${t.id} ${t.title}${state.active === t.id ? " (active)" : ""}`);
				break;
			}
			case "switch": {
				const t = find(o.thread);
				if (!t || o.thread === undefined) {
					errors.push(`switch: thread #${o.thread} not found`);
					break;
				}
				if (t.status !== "open") t.status = "open";
				state.active = t.id;
				log.push(`active → #${t.id} ${t.title}`);
				break;
			}
			case "add": {
				const t = find(o.thread);
				if (!t) {
					errors.push(`add: thread #${o.thread ?? state.active} not found`);
					break;
				}
				const texts = [...(o.text ? [o.text] : []), ...(o.items ?? [])];
				if (texts.length === 0) errors.push("add: text or items required");
				for (const text of texts) log.push(`added ${addItem(t, text, o.kind).id} ${text}`);
				break;
			}
			case "done":
			case "undo":
			case "drop": {
				const refs = [...(o.item ? [o.item] : []), ...(o.items ?? [])];
				if (refs.length === 0) errors.push(`${o.op}: item required`);
				for (const ref of refs) {
					const hit = findItem(ref);
					if (!hit?.i) {
						errors.push(`${o.op}: item ${ref} not found`);
						continue;
					}
					if (o.op === "done") hit.i.done = true;
					if (o.op === "undo") (hit.i.done = false), (hit.i.dropped = false);
					if (o.op === "drop") hit.i.dropped = true;
					log.push(`${o.op} ${ref}`);
				}
				break;
			}
			case "resolve":
			case "park":
			case "reopen": {
				const t = find(o.thread);
				if (!t) {
					errors.push(`${o.op}: thread #${o.thread ?? state.active} not found`);
					break;
				}
				t.status = o.op === "resolve" ? "resolved" : o.op === "park" ? "parked" : "open";
				if (o.note) t.note = o.note;
				// resolve/park deliberately keep the active thread: only switch/open/reopen move it,
				// so text written next is still attributed to the thread it is about.
				if (o.op === "reopen") state.active = t.id;
				log.push(`${o.op} #${t.id}${o.note ? ` (${o.note})` : ""}`);
				break;
			}
			case "rename": {
				const t = find(o.thread);
				if (!t || !o.title) {
					errors.push("rename: thread + title required");
					break;
				}
				t.title = o.title;
				log.push(`renamed #${t.id} → ${o.title}`);
				break;
			}
			case "list":
				break;
			default:
				errors.push(`unknown op ${o.op}`);
		}
	}
	return { state, log, errors };
}

// ---------------------------------------------------------------- replay / attribution

interface Segment {
	thread: number; // 0 = no thread
	role: "user" | "assistant";
	text: string;
	/** Duplicate of a multi-thread user prompt; excluded from transcript dividers. */
	copy?: boolean;
	/** Assistant text in a message that also calls tools (progress note, not the final reply). */
	interim?: boolean;
}

/** `[[#n]]` at the start of a line: the following text belongs to thread n. */
const MARKER_RE = /^[ \t]*\[\[#(\d+)\]\][ \t]*\n?/gm;

/** Split assistant text at thread markers. Text before the first marker belongs to `cursor`. */
function splitByMarkers(
	text: string,
	cursor: number,
	valid: (id: number) => boolean,
): { parts: { thread: number; text: string; marked: boolean }[]; cursor: number } {
	const parts: { thread: number; text: string; marked: boolean }[] = [];
	let last = 0;
	let thread = cursor;
	let marked = false;
	for (const m of text.matchAll(MARKER_RE)) {
		const id = Number(m[1]);
		if (!valid(id)) continue;
		const chunk = text.slice(last, m.index).trim();
		if (chunk) parts.push({ thread, text: chunk, marked });
		thread = id;
		marked = true;
		last = (m.index ?? 0) + m[0].length;
	}
	const rest = text.slice(last).trim();
	if (rest) parts.push({ thread, text: rest, marked });
	return { parts, cursor: thread };
}

/** `id` if that thread is open, else the active thread if open, else its open parent, else the latest open thread. */
function openFallback(state: State, id: number): number {
	const byId = (x: number | undefined) => state.threads.find((t) => t.id === x);
	const isOpen = (x: number | undefined) => byId(x)?.status === "open";
	if (isOpen(id)) return id;
	if (isOpen(state.active)) return state.active!;
	let p = byId(id)?.parent;
	while (p !== undefined) {
		if (isOpen(p)) return p;
		p = byId(p)?.parent;
	}
	return [...state.threads].reverse().find((t) => t.status === "open")?.id ?? 0;
}

/** `#n ` at the start of a line in a USER message: the following lines are meant for thread n. */
const USER_MARKER_RE = /^#(\d+)[ \t]+/gm;

/** Split a user message into per-thread sections. Unmarked text (preamble) has thread undefined. */
function splitUser(text: string, valid: (id: number) => boolean): { parts: { thread?: number; text: string }[]; ids: number[] } {
	const parts: { thread?: number; text: string }[] = [];
	const ids: number[] = [];
	let last = 0;
	let thread: number | undefined;
	for (const m of text.matchAll(USER_MARKER_RE)) {
		const id = Number(m[1]);
		if (!valid(id)) continue;
		const chunk = text.slice(last, m.index).trim();
		if (chunk) parts.push({ thread, text: chunk });
		thread = id;
		if (!ids.includes(id)) ids.push(id);
		last = (m.index ?? 0) + m[0].length;
	}
	const rest = text.slice(last).trim();
	if (rest) parts.push({ thread, text: rest });
	return { parts, ids };
}

interface Replay {
	state: State;
	segments: Segment[];
	/** Thread of the latest assistant text (markers move it). */
	cursor: number;
	/** Rendered-markdown key -> thread for dividers on unmarked blocks / user messages. */
	tags: Map<string, number>;
}

/** Walk the active branch: final state + every user/assistant text attributed to a thread. */
function replay(ctx: ExtensionContext): Replay {
	let state = emptyState();
	const segments: Segment[] = [];
	const tags = new Map<string, number>();
	let pendingUser: Segment | undefined;
	/** Threads the latest user message has been attributed to (it may span several). */
	let userThreads = new Set<number>();
	let cursor = 0;
	/** Thread of the last thing shown in the transcript (for dividers). */
	let prev = 0;
	const valid = (id: number) => state.threads.some((t) => t.id === id);

	for (const entry of ctx.sessionManager.getBranch() as any[]) {
		if (entry.type === "custom" && entry.customType === STATE_ENTRY && entry.data?.threads) {
			state = clone(entry.data as State);
			cursor = state.active ?? 0;
			continue;
		}
		if (entry.type !== "message") continue;
		const msg = entry.message;
		if (msg.role === "toolResult" && msg.toolName === TOOL && msg.details?.state) {
			state = clone(msg.details.state as State);
			cursor = state.active ?? 0;
		} else if (msg.role === "user") {
			const text = textOf(msg.content);
			if (!text.trim()) continue;
			const split = splitUser(text, valid);
			userThreads = new Set();
			pendingUser = undefined;
			// a new message never continues in a resolved/parked thread
			cursor = openFallback(state, cursor);
			if (split.ids.length === 0) {
				// Attributed to whatever thread(s) the answer after it lands in.
				pendingUser = { thread: cursor, role: "user", text };
				segments.push(pendingUser);
			} else {
				// "#n " sections go straight to their threads; general text (outside any section)
				// is shown in front of each addressed thread's section.
				const general = split.parts.filter((p) => p.thread === undefined).map((p) => p.text).join("\n\n");
				for (const p of split.parts) {
					if (p.thread === undefined) continue;
					if (general && !userThreads.has(p.thread))
						segments.push({ thread: p.thread, role: "user", text: general, copy: true });
					segments.push({ thread: p.thread, role: "user", text: p.text });
					userThreads.add(p.thread);
				}
				prev = split.ids[split.ids.length - 1];
			}
		} else if (msg.role === "assistant") {
			const interim = Array.isArray(msg.content) && msg.content.some((b: any) => b?.type === "toolCall");
			for (const block of assistantTexts(msg.content)) {
				const split = splitByMarkers(block, cursor, valid);
				cursor = split.cursor;
				split.parts.forEach((p, idx) => {
					if (pendingUser && !userThreads.has(p.thread)) {
						if (userThreads.size === 0) {
							pendingUser.thread = p.thread;
							if (p.thread && p.thread !== prev) tags.set(pendingUser.text, p.thread);
							prev = p.thread;
						}
						// same prompt answered in another thread too: show it there as well (view only)
						else segments.push({ thread: p.thread, role: "user", text: pendingUser.text, copy: true });
						userThreads.add(p.thread);
					}
					if (idx === 0 && !p.marked && p.thread && p.thread !== prev) tags.set(block, p.thread);
					prev = p.thread;
					segments.push({ thread: p.thread, role: "assistant", text: p.text, interim });
				});
			}
		}
	}
	return { state, segments, cursor, tags };
}

// ---------------------------------------------------------------- extension

type WidgetMode = "full" | "compact" | "off";

export default function threadsExtension(pi: ExtensionAPI) {
	let state: State = emptyState();
	let segments: Segment[] = [];
	// widget mode is a user preference: persisted across sessions/restarts
	const PREFS_FILE = join(getAgentDir(), "threads.json");
	let widgetMode: WidgetMode = "full";
	try {
		const m = JSON.parse(readFileSync(PREFS_FILE, "utf8"))?.widgetMode;
		if (["full", "compact", "off"].includes(m)) widgetMode = m;
	} catch {
		/* defaults */
	}
	const setWidgetMode = (m: WidgetMode, ctx: ExtensionContext) => {
		widgetMode = m;
		try {
			writeFileSync(PREFS_FILE, `${JSON.stringify({ widgetMode }, null, 2)}\n`);
		} catch {
			/* non-fatal */
		}
		updateWidget(ctx);
		if (ctx.hasUI) ctx.ui.notify(`Thread widget: ${m}`, "info");
	};
	/** Threads the user explicitly addressed in the upcoming prompt ("#n " sections). */
	let addressed: number[] = [];
	/** Serialized state last shown to the model (avoid re-injecting unchanged state). */
	let lastInjected = "";
	/** Markdown text -> thread id for a divider (only where the thread changes). */
	let tags = new Map<string, number>();
	/** Thread the latest assistant text belongs to (markers move it). */
	let cursor = 0;

	const titleOf = (id: number) => state.threads.find((t) => t.id === id)?.title ?? "";
	const label = (id: number) => (id ? `⤷ #${id} · ${titleOf(id)}` : "");

	/** Re-read everything from the branch. Returns true if markers moved the active thread. */
	function rebuild(ctx: ExtensionContext): boolean {
		const r = replay(ctx);
		state = r.state;
		segments = r.segments;
		tags = r.tags;
		cursor = r.cursor;
		let moved = false;
		// A `[[#n]]` marker in the latest reply makes n the active thread.
		if (cursor && cursor !== state.active && state.threads.some((t) => t.id === cursor && t.status === "open")) {
			state.active = cursor;
			moved = true;
		}
		// never leave a resolved/parked thread active once the turn is over
		const fb = openFallback(state, state.active ?? 0);
		if (state.active !== undefined && fb !== state.active) {
			state.active = fb || undefined;
			moved = true;
		}
		lastInjected = recomputeLastInjected(ctx);
		updateWidget(ctx);
		return moved;
	}

	/** Find the last state snapshot shown to the model so resumes don't re-inject needlessly. */
	function recomputeLastInjected(ctx: ExtensionContext): string {
		for (const entry of [...(ctx.sessionManager.getBranch() as any[])].reverse()) {
			if (entry.type === "message" && entry.message?.role === "toolResult" && entry.message.toolName === TOOL)
				return stateForModel(entry.message.details?.state ?? emptyState());
			if (entry.type === "custom_message" && entry.customType === CONTEXT_MSG) return entry.details?.snapshot ?? "";
		}
		return "";
	}

	function persist() {
		pi.appendEntry<State>(STATE_ENTRY, clone(state));
	}

	// ------------------------------------------------------------ widget

	function widgetLines(theme: Theme, width: number): string[] {
		if (state.threads.length === 0) return [];
		const open = state.threads.filter((t) => t.status !== "resolved");
		const allItems = state.threads.flatMap(liveItems);
		const doneCount = allItems.filter((i) => i.done).length;
		const head =
			theme.fg("accent", theme.bold("Threads")) +
			theme.fg("muted", ` · ${open.length} open · ${doneCount}/${allItems.length} items done`) +
			theme.fg("dim", "  (Alt+T board \u00b7 Alt+H hide \u00b7 /threads)");

		if (widgetMode === "compact") {
			const active = state.threads.find((t) => t.id === state.active);
			const act = active
				? theme.fg("accent", ` ▸ #${active.id} ${active.title}`) +
					theme.fg("muted", ` [${openItems(active).length} open]`)
				: "";
			return [truncateToWidth(head + act, width)];
		}

		const lines = [head];
		const MAX = 14;
		const resolved = state.threads.filter((t) => t.status === "resolved" && t.id !== state.active);
		for (const { t, depth } of treeOrder(state)) {
			if (t.status === "resolved" && t.id !== state.active) continue;
			const isActive = t.id === state.active;
			const items = liveItems(t);
			const done = items.filter((i) => i.done).length;
			const indent = "  ".repeat(depth);
			const marker = isActive ? theme.fg("accent", "▸ ") : "  ";
			const title = isActive ? theme.fg("accent", theme.bold(`#${t.id} ${t.title}`)) : `#${t.id} ${t.title}`;
			const status =
				t.status === "parked"
					? theme.fg("warning", " ⏸ parked")
					: t.status === "resolved"
						? theme.fg("success", " ✓ resolved")
						: "";
			const count = items.length ? theme.fg(done === items.length ? "success" : "muted", ` ${done}/${items.length}`) : "";
			lines.push(`${indent}${marker}${title}${count}${status}`);
			// open items: all for the active thread, first 2 for others
			const show = openItems(t);
			const limit = isActive ? show.length : 2;
			for (const i of show.slice(0, limit)) {
				lines.push(`${indent}    ${theme.fg("muted", kindIcon(i.kind))} ${theme.fg("dim", i.id)} ${i.text}`);
			}
			if (show.length > limit) lines.push(`${indent}    ${theme.fg("dim", `… ${show.length - limit} more`)}`);
		}
		if (resolved.length) {
			lines.push(
				theme.fg("success", "  ✓ ") +
					theme.fg("dim", resolved.map((t) => `#${t.id} ${t.title}`).join(" · ")),
			);
		}
		const out = lines.length > MAX ? [...lines.slice(0, MAX - 1), theme.fg("dim", `  … (${lines.length - MAX + 1} more lines – /threads)`)] : lines;
		return out.map((l) => truncateToWidth(l, width));
	}

	function updateWidget(ctx: ExtensionContext) {
		if (!ctx.hasUI) return;
		if (widgetMode === "off" || state.threads.length === 0) {
			ctx.ui.setWidget("threads", undefined);
		} else {
			ctx.ui.setWidget("threads", (_tui, theme) => ({
				render: (width: number) => widgetLines(theme, Math.max(10, width - 2)).map((l) => ` ${l}`),
				invalidate: () => {},
			}));
		}
		const active = state.threads.find((t) => t.id === state.active);
		ctx.ui.setStatus(
			"threads",
			addressed.length
				? ctx.ui.theme.fg("warning", `→ ${addressed.map((id) => `#${id}`).join(",")}`)
				: active && widgetMode === "off"
					? ctx.ui.theme.fg("accent", `#${active.id}`)
					: undefined,
		);
	}

	// ------------------------------------------------------------ transcript dividers

	pi.registerMarkdownTransformer((markdown: string, context: MarkdownTransformContext): string => {
		if (context.messageType === "assistant-thinking" || !markdown.trim()) return markdown;
		const tag = tags.get(markdown) ?? tags.get(markdown.trim());
		let out = markdown;
		if (context.messageType === "user") {
			out = out.replace(USER_MARKER_RE, (whole, id: string) =>
				state.threads.some((t) => t.id === Number(id)) ? `\n*${label(Number(id))}*\n\n` : whole,
			);
		}
		if (context.messageType === "assistant") {
			out = out.replace(MARKER_RE, (whole, id: string) =>
				state.threads.some((t) => t.id === Number(id)) ? `\n*${label(Number(id))}*\n\n` : whole,
			);
		}
		return tag ? `*${label(tag)}*\n\n${out}` : out;
	});

	async function refreshTranscript(ctx: ExtensionContext) {
		if (ctx.mode !== "tui" || !ctx.hasUI) return;
		try {
			await ctx.ui.custom<unknown>((tui, _theme, _kb, done) => {
				tui.invalidate();
				tui.requestRender();
				done(undefined);
				return { render: () => [], invalidate: () => {} } as Component;
			});
		} catch {
			/* cosmetic */
		}
	}

	// ------------------------------------------------------------ lifecycle

	pi.on("session_start", async (_e, ctx) => rebuild(ctx));
	pi.on("session_tree", async (_e, ctx) => {
		rebuild(ctx);
		await refreshTranscript(ctx);
	});
	pi.on("agent_settled", async (_e, ctx) => {
		const before = JSON.stringify([...tags]);
		if (rebuild(ctx)) persist(); // markers moved the active thread
		if (JSON.stringify([...tags]) !== before) await refreshTranscript(ctx);
	});

	// Lines starting with "#n " address thread n; one message may address several threads.
	pi.on("input", async (event, ctx) => {
		if (event.source === "extension") return { action: "continue" };
		addressFrom(event.text, ctx);
		return { action: "continue" };
	});

	/** Mark the threads addressed by "#n " lines of an outgoing user message. */
	function addressFrom(text: string, ctx: ExtensionContext) {
		const { ids } = splitUser(text, (id) => state.threads.some((t) => t.id === id));
		if (ids.length) {
			addressed = ids;
			const before = JSON.stringify(state);
			// reopen addressed threads; the first one becomes active
			const ops: Op[] = ids
				.filter((id) => state.threads.find((t) => t.id === id)?.status !== "open")
				.map((id) => ({ op: "reopen", thread: id }));
			ops.push({ op: "switch", thread: ids[0] });
			state = applyOps(state, ops).state;
			if (JSON.stringify(state) !== before) persist();
			updateWidget(ctx);
		}
	}

	pi.on("before_agent_start", async (event, ctx) => {
		if (event.messageType !== "user") return;
		const snapshot = stateForModel(state);
		const targets = addressed;
		addressed = [];
		updateWidget(ctx);
		if (targets.length === 0 && (snapshot === lastInjected || state.threads.length === 0)) return;
		lastInjected = snapshot;
		const lines = ["[threads] Current conversation threads:", snapshot];
		if (targets.length) {
			const list = targets.map((id) => `#${id} (${titleOf(id)})`).join(", ");
			lines.push(
				`The user's message addresses ${targets.length > 1 ? "several threads" : "thread"}: ${list}. ` +
					`Lines after "#n " belong to thread n; text before the first "#n " is general. ` +
					`Answer every addressed thread in ONE reply, each in its own [[#n]] section, in the same order.`,
			);
		}
		return {
			message: {
				customType: CONTEXT_MSG,
				content: lines.join("\n"),
				display: false,
				details: { snapshot },
			},
		};
	});

	// ------------------------------------------------------------ tool

	const OpSchema = Type.Object({
		op: StringEnum(["open", "switch", "add", "done", "undo", "drop", "resolve", "park", "reopen", "rename", "list"] as const),
		thread: Type.Optional(Type.Number({ description: "Thread id (defaults to the active thread where sensible)" })),
		question: Type.Optional(
			Type.String({ description: "open: the user's question/request that starts this thread, quoted (short excerpt)" }),
		),
		title: Type.Optional(Type.String({ description: "Thread title (open, rename) – short, 2-6 words" })),
		parent: Type.Optional(Type.Number({ description: "Parent thread id when this thread branches off another (open)" })),
		activate: Type.Optional(Type.Boolean({ description: "open: make it the active thread (default true)" })),
		text: Type.Optional(Type.String({ description: "Item text (add)" })),
		items: Type.Optional(
			Type.Array(Type.String(), { description: "Item texts (open/add) or item ids like '2.1' (done/undo/drop)" }),
		),
		item: Type.Optional(Type.String({ description: "Item id like '2.1' (done/undo/drop)" })),
		kind: Type.Optional(StringEnum(["goal", "task", "question"] as const, { description: "Item kind, default task" })),
		note: Type.Optional(Type.String({ description: "Outcome / reason (resolve, park)" })),
	});

	pi.registerTool({
		name: TOOL,
		label: "Thread",
		description:
			"Organize this conversation into logical threads (topics/questions) and track their goals, tasks and open questions. " +
			"Pass several ops at once. Ops: open{title,question?,parent?,items?,kind?,activate?} (creates; activates unless activate:false), switch{thread}, " +
			"add{thread?,text|items,kind?}, done|undo|drop{item|items}, resolve|park|reopen{thread,note?}, rename{thread,title}, list.",
		promptSnippet: "Track conversation threads (topics) and their open goals/tasks/questions",
		promptGuidelines: [
			"Keep the conversation organized with the `thread` tool. On the first substantive request, open a thread for the main goal with its goals/tasks as items.",
			"When a new, distinct question or side topic comes up (one that may get follow-ups), open a new thread for it (with `parent` if it branches off another) instead of mixing it into the current one. Do not open threads for trivial one-line clarifications. Pass `question` with a short quote of the user's request that started the thread.",
			"Once threads exist, start every visible reply (and every part of a reply that belongs to a different thread) with a marker line `[[#n]]` naming the thread it belongs to. The UI renders the marker as a divider and files the text under that thread; the last marker also makes that thread active. A reply covering several threads = several marked sections, e.g. `[[#2]]` answer to the side question, then `[[#1]]` continuation of the main task. Text without a marker belongs to the currently active thread.",
			"Never tick or resolve a question without also answering it visibly in a marked section of your reply (the user cannot see your thinking or tool arguments).",
			"Keep items current: add newly discovered tasks/questions, mark items done as you complete them, resolve a thread (short note) when its goal is reached, park threads the user defers. Do the `thread` bookkeeping (open/done/resolve) BEFORE writing the visible reply, and write the reply as your final message with no tool call after it \u2013 text followed by a tool call in the same message can end up hidden from the user.",
			"Batch thread ops into a single `thread` call where possible, and call it in parallel with other tools rather than as a separate step when you can.",
			"A hidden [threads] message shows the current thread state; lines starting with '#<n> ' in a user message are addressed to thread n (one message can address several threads; answer each in its own [[#n]] section of a single reply).",
		],
		parameters: Type.Object({ ops: Type.Array(OpSchema, { minItems: 1 }) }),

		async execute(_id, params, _signal, _onUpdate, ctx) {
			const ops = params.ops as Op[];
			// markers written earlier in this turn may have moved the active thread
			const cur = replay(ctx).cursor;
			if (cur && state.threads.some((t) => t.id === cur)) state.active = cur;
			const r = applyOps(state, ops);
			// atomic: on any error nothing is applied, so the model can't half-apply a batch
			if (r.errors.length) {
				r.log.length = 0;
				r.errors.push("No ops were applied (batch is atomic). Fix and retry.");
			} else state = r.state;
			updateWidget(ctx);
			const text = [
				...r.log,
				...r.errors.map((e) => `ERROR: ${e}`),
				"",
				"State:",
				stateForModel(state),
			].join("\n");
			lastInjected = stateForModel(state);
			return {
				content: [{ type: "text", text }],
				details: { state: clone(state), log: r.log, errors: r.errors, ops } satisfies ToolDetails,
				isError: r.errors.length > 0,
			};
		},

		renderCall(args, theme) {
			const ops = ((args as { ops?: Op[] }).ops ?? []) as Op[];
			const parts = ops.map((o) => {
				switch (o.op) {
					case "open":
						return theme.fg("accent", `+ ${o.title ?? ""}`);
					case "switch":
						return theme.fg("accent", `⤷ #${o.thread}${o.thread ? ` ${titleOf(o.thread)}` : ""}`);
					case "done":
						return theme.fg("success", `✓ ${[o.item, ...(o.items ?? [])].filter(Boolean).join(",")}`);
					case "add":
						return theme.fg("muted", `+item ${[o.text, ...(o.items ?? [])].filter(Boolean).length}`);
					default:
						return theme.fg("muted", `${o.op}${o.thread ? ` #${o.thread}` : ""}${o.item ? ` ${o.item}` : ""}`);
				}
			});
			return { render: (w: number) => [truncateToWidth(theme.fg("toolTitle", theme.bold("thread ")) + parts.join(theme.fg("dim", " · ")), w)], invalidate: () => {} };
		},

		renderResult(result, { expanded }, theme) {
			const d = result.details as ToolDetails | undefined;
			const lines: string[] = [];
			if (d) {
				for (const l of d.log) lines.push(theme.fg("muted", l));
				for (const e of d.errors) lines.push(theme.fg("error", e));
				const active = d.state.threads.find((t) => t.id === d.state.active);
				if (active) lines.push(theme.fg("accent", `▸ active: #${active.id} ${active.title}`));
				if (expanded) lines.push("", ...stateForModel(d.state).split("\n").map((l) => theme.fg("dim", l)));
			}
			return { render: (w: number) => lines.map((l) => truncateToWidth(l, w)), invalidate: () => {} };
		},
	});

	// ------------------------------------------------------------ commands

	pi.registerCommand("thread", {
		description: "Choose the thread your next message goes to (/thread [n | new <title>])",
		handler: async (args, ctx) => {
			const a = (args ?? "").trim();
			let id: number | undefined;
			if (/^\d+$/.test(a)) id = Number(a);
			else if (/^new\s+/i.test(a)) {
				const r = applyOps(state, [{ op: "open", title: a.replace(/^new\s+/i, "") }]);
				state = r.state;
				id = state.active;
				persist();
			} else if (ctx.hasUI) {
				const opts = treeOrder(state).map(({ t, depth }) => `${"  ".repeat(depth)}#${t.id} ${t.title}${t.status !== "open" ? ` (${t.status})` : ""}`);
				opts.push("+ new thread…");
				const choice = await ctx.ui.select("Reply in which thread?", opts);
				if (!choice) return;
				if (choice.startsWith("+")) {
					const title = await ctx.ui.input("New thread title", "");
					if (!title?.trim()) return;
					state = applyOps(state, [{ op: "open", title: title.trim() }]).state;
					id = state.active;
					persist();
				} else id = Number(/#(\d+)/.exec(choice)?.[1]);
			}
			const t = state.threads.find((x) => x.id === id);
			if (!t) {
				ctx.ui.notify(`Thread ${a} not found`, "error");
				return;
			}
			if (state.active !== t.id || t.status !== "open") {
				state = applyOps(state, [{ op: "switch", thread: t.id }]).state;
				persist();
			}
			addressed = [t.id];
			updateWidget(ctx);
			ctx.ui.notify(`Next message goes to #${t.id} ${t.title}`, "info");
		},
	});

	pi.registerCommand("thread-widget", {
		description: "Thread widget: full | compact | off (no arg cycles)",
		handler: async (args, ctx) => {
			const a = (args ?? "").trim() as WidgetMode;
			setWidgetMode(["full", "compact", "off"].includes(a) ? a : cycle(widgetMode), ctx);
		},
	});

	const cycle = (m: WidgetMode): WidgetMode => (m === "full" ? "compact" : m === "compact" ? "off" : "full");
	pi.registerShortcut(Key.alt("h"), {
		description: "Thread widget: cycle full / compact / off",
		handler: async (ctx) => setWidgetMode(cycle(widgetMode), ctx),
	});

	pi.registerShortcut(Key.alt("t"), {
		description: "Open the thread board (all threads + one reply box per thread)",
		handler: async (ctx) => openBoard(ctx),
	});

	pi.registerCommand("board", {
		description: "Thread board: latest answer of every open thread + a reply box per thread; Enter sends all as ONE message",
		handler: async (_args, ctx) => openBoard(ctx),
	});

	// ------------------------------------------------------------ board

	/** Unsent drafts per thread (0 = "to all"); kept when the board is closed with Esc. */
	const drafts = new Map<number, string>();
	let boardOpen = false;

	/** Latest exchange of a thread: the last user part(s) and the assistant text after them. */
	function latestExchange(id: number): { asked: string[]; answer: string[] } {
		const segs = segments.filter((s) => s.thread === id);
		let i = segs.length - 1;
		const trailing: Segment[] = [];
		while (i >= 0 && segs[i].role === "assistant") trailing.unshift(segs[i--]);
		// prefer the final reply; fall back to the last progress note while a turn is still running
		// progress notes ("Let me check\u2026") are short; long text before a tool call is real content
		const finals = trailing.filter((s) => !s.interim || s.text.length > 200 || s.text.split("\n").length >= 4);
		const answer = (finals.length ? finals : trailing.slice(-1)).map((s) => s.text);
		const asked: string[] = [];
		while (i >= 0 && segs[i].role === "user") asked.unshift(segs[i--].text);
		return { asked, answer };
	}

	async function openBoard(ctx: ExtensionContext) {
		if (ctx.mode !== "tui" || !ctx.hasUI) {
			ctx.ui.notify("The thread board needs interactive mode", "error");
			return;
		}
		if (boardOpen) return;
		rebuild(ctx);
		// open threads + any thread answered in the latest reply (even if already resolved)
		let lastUser = -1;
		segments.forEach((s, i) => {
			if (s.role === "user" && !s.copy) lastUser = i;
		});
		let start = lastUser;
		while (start > 0 && segments[start - 1].role === "user" && !segments[start - 1].copy) start--;
		const recent = new Set(segments.slice(Math.max(0, start)).map((s) => s.thread));
		const ids = treeOrder(state)
			.filter(({ t }) => t.status !== "resolved" || t.id === state.active || recent.has(t.id))
			.map(({ t }) => t.id);
		if (ids.length === 0) {
			ctx.ui.notify("No open threads yet", "info");
			return;
		}
		boardOpen = true;
		try {
			const message = await ctx.ui.custom<string | undefined>((tui, theme, kb, done) =>
				createBoard(tui, theme, kb, done, [0, ...ids]),
			);
			if (!message) return;
			addressFrom(message, ctx);
			if (ctx.isIdle()) pi.sendUserMessage(message);
			else {
				pi.sendUserMessage(message, { deliverAs: "followUp" });
				ctx.ui.notify("Queued as follow-up (agent is busy)", "info");
			}
		} finally {
			boardOpen = false;
		}
	}

	function createBoard(
		tui: any,
		theme: Theme,
		kb: any,
		done: (v: string | undefined) => void,
		ids: number[], // 0 = "to all threads"
	) {
		const editorTheme = {
			borderColor: (s: string) => theme.fg("borderMuted", s),
			selectList: {
				selectedPrefix: (s: string) => theme.fg("accent", s),
				selectedText: (s: string) => theme.fg("accent", s),
				description: (s: string) => theme.fg("muted", s),
				scrollInfo: (s: string) => theme.fg("muted", s),
				noMatch: (s: string) => theme.fg("muted", s),
			},
		};
		const editors = new Map<number, Editor>();
		for (const id of ids) {
			const ed = new Editor(tui, editorTheme as any, { paddingX: 1 });
			ed.setText(drafts.get(id) ?? "");
			editors.set(id, ed);
		}
		// start in the first thread box (or the active thread)
		let focus = Math.max(1, ids.indexOf(state.active ?? -1));
		if (focus >= ids.length) focus = 0;
		let expandAll = false;
		let scrollTop = 0;
		let followFocus = true;
		let focused = false;
		const mdCache = new Map<string, string[]>();
		const md = (key: string, text: string, width: number) => {
			const k = `${width}:${key}`;
			let lines = mdCache.get(k);
			if (!lines) {
				lines = new Markdown(text, 2, 0, getMarkdownTheme()).render(width);
				mdCache.set(k, lines);
			}
			return lines;
		};
		const saveDrafts = () => {
			for (const [id, ed] of editors) {
				const text = ed.getExpandedText?.() ?? ed.getText();
				if (text.trim()) drafts.set(id, text);
				else drafts.delete(id);
			}
		};
		const compose = (): string => {
			const parts: string[] = [];
			const general = (editors.get(0)?.getExpandedText?.() ?? editors.get(0)?.getText() ?? "").trim();
			if (general) parts.push(general);
			for (const id of ids) {
				if (!id) continue;
				const ed = editors.get(id)!;
				const text = (ed.getExpandedText?.() ?? ed.getText()).trim();
				if (text) parts.push(`#${id} ${text}`);
			}
			return parts.join("\n");
		};
		/** Scroll offset inside the focused thread's answer, and its last measured geometry. */
		let ansTop = 0;
		let ansView = 0;
		let ansLen = 0;
		const FOOTER_LINES = 2;
		const boardHeight = () => Math.max(10, (process.stdout.rows || 40) - FOOTER_LINES - 9);
		const setFocus = (i: number) => {
			focus = (i + ids.length) % ids.length;
			followFocus = true;
			ansTop = 0;
		};
		const scrollAnswer = (delta: number) => {
			ansTop = Math.max(0, Math.min(ansTop + delta, Math.max(0, ansLen - ansView)));
			followFocus = true;
		};

		return {
			get focused() {
				return focused;
			},
			set focused(v: boolean) {
				focused = v;
			},
			render(width: number): string[] {
				const out: string[] = [];
				let focusStart = 0;
				let focusEditorEnd = 0;
				const h = boardHeight();
				const rule = (label: string, active: boolean) => {
					const text = ` ${label} `;
					const line = `\u2500\u2500${text}${"\u2500".repeat(Math.max(0, width - text.length - 2))}`;
					return truncateToWidth(active ? theme.fg("accent", theme.bold(line)) : theme.fg("borderMuted", line), width);
				};
				ids.forEach((id, idx) => {
					const isFocus = idx === focus;
					const ed = editors.get(id)!;
					ed.focused = focused && isFocus;
					if (isFocus) focusStart = out.length;
					if (id === 0) {
						out.push(rule("To all threads (optional)", isFocus));
					} else {
						const t = state.threads.find((x) => x.id === id)!;
						const items = liveItems(t);
						const doneN = items.filter((i) => i.done).length;
						const status = t.status === "open" ? "" : ` (${t.status})`;
						const count = items.length ? `  ${doneN}/${items.length}` : "";
						out.push("", rule(`#${t.id} ${t.title}${status}${count}`, isFocus));
						const { asked, answer } = latestExchange(id);
						for (const a of asked) {
							const first = a.split("\n").slice(0, 2).join(" \u21b5 ");
							out.push(truncateToWidth(theme.fg("dim", `  You: ${first}`), width));
						}
						const open = openItems(t);
						if (answer.length === 0) {
							out.push(theme.fg("dim", "  (no answer in this thread yet)"));
						} else {
							const lines = md(`${id}:${answer.join("\n\n")}`, answer.join("\n\n"), width);
							if (isFocus) {
								// own viewport: header + answer window + open items + reply box always fit on screen
								const edLen = ed.render(width).length;
								const fixed = 2 + asked.length + (open.length ? 1 : 0) + edLen + 1;
								ansView = Math.max(4, h - fixed);
								ansLen = lines.length;
								if (lines.length <= ansView) {
									ansTop = 0;
									out.push(...lines);
								} else {
									ansTop = Math.max(0, Math.min(ansTop, lines.length - ansView));
									out.push(...lines.slice(ansTop, ansTop + ansView));
									const end = Math.min(lines.length, ansTop + ansView);
									const where = end >= lines.length ? "end" : `${lines.length - end} more below`;
									out.push(
										theme.fg(
											"warning",
											`  \u2195 lines ${ansTop + 1}-${end} of ${lines.length} (${where}) \u00b7 Ctrl+U/Ctrl+D half page \u00b7 Shift+\u2191/\u2193 line`,
										),
									);
								}
							} else {
								const limit = expandAll ? lines.length : 6;
								out.push(...lines.slice(0, limit));
								if (lines.length > limit)
									out.push(theme.fg("dim", `  \u2026 ${lines.length - limit} more lines (Tab here to read all)`));
							}
						}
						if (open.length)
							out.push(
								truncateToWidth(
									theme.fg("muted", `  open: `) + open.map((i) => `${kindIcon(i.kind)} ${i.text}`).join(theme.fg("dim", " \u00b7 ")),
									width,
								),
							);
					}
					const edLines = ed.render(width);
					const hasText = ed.getText().trim().length > 0;
					if (isFocus || hasText || id !== 0) {
						if (!isFocus && !hasText) out.push(theme.fg("dim", `  \u21b3 reply to ${id ? `#${id}` : "all"}\u2026`));
						else out.push(...edLines);
					}
					if (isFocus) focusEditorEnd = out.length;
				});

				const footer = [
					theme.fg("borderMuted", "\u2500".repeat(width)),
					truncateToWidth(
						theme.fg(
							"dim",
							" Tab/Shift+Tab next/prev thread \u00b7 Ctrl+U/D scroll answer \u00b7 Enter send ALL replies as one message \u00b7 Shift+Enter newline \u00b7 Ctrl+O expand others \u00b7 Esc close (drafts kept)",
						),
						width,
					),
				];
				const maxTop = Math.max(0, out.length - h);
				if (followFocus) {
					// show the focused block from its header, but always keep its reply box visible
					scrollTop = Math.min(focusStart, Math.max(0, focusEditorEnd - h));
				}
				scrollTop = Math.max(0, Math.min(scrollTop, maxTop));
				const view = out.slice(scrollTop, scrollTop + h);
				const more = out.length > h ? theme.fg("dim", ` ${scrollTop + 1}-${Math.min(out.length, scrollTop + h)}/${out.length}`) : "";
				return [
					truncateToWidth(theme.fg("accent", theme.bold(" Thread board")) + more, width),
					...view.map((l) => truncateToWidth(l, width)),
					...footer,
				];
			},
			handleInput(data: string) {
				const ed = editors.get(ids[focus])!;
				if (kb.matches(data, "tui.select.cancel") || matchesKey(data, Key.alt("t"))) {
					saveDrafts();
					return done(undefined);
				}
				if (matchesKey(data, Key.tab)) setFocus(focus + 1);
				else if (matchesKey(data, Key.shift("tab"))) setFocus(focus - 1);
				else if (matchesKey(data, Key.ctrl("o"))) expandAll = !expandAll;
				// (PgUp/PgDn never reach extension components: pi uses them for the transcript)
				else if (matchesKey(data, Key.ctrl("u"))) scrollAnswer(-Math.max(1, Math.floor(ansView / 2)));
				else if (matchesKey(data, Key.ctrl("d"))) scrollAnswer(Math.max(1, Math.floor(ansView / 2)));
				else if (matchesKey(data, Key.shift("up")) || (matchesKey(data, Key.up) && !ed.getText())) scrollAnswer(-1);
				else if (matchesKey(data, Key.shift("down")) || (matchesKey(data, Key.down) && !ed.getText())) scrollAnswer(1);
				else if (kb.matches(data, "tui.input.submit") || data === "\r") {
					const message = compose();
					if (!message) return; // nothing typed yet
					drafts.clear();
					return done(message);
				} else {
					ed.handleInput(data);
					followFocus = true;
				}
				tui.requestRender();
			},
			invalidate() {
				mdCache.clear();
				for (const ed of editors.values()) ed.invalidate?.();
			},
		};
	}

	pi.registerCommand("threads", {
		description: "Browse threads; Enter = view thread conversation, r = reply in thread, x = resolve, p = park",
		handler: async (_args, ctx) => {
			if (ctx.mode !== "tui") {
				ctx.ui.notify(stateForModel(state), "info");
				return;
			}
			rebuild(ctx);
			if (state.threads.length === 0 && segments.length === 0) {
				ctx.ui.notify("No threads yet", "info");
				return;
			}
			while (true) {
				const action = await browse(ctx);
				if (!action) return;
				if (action.kind === "view") {
					const reply = await viewThread(ctx, action.id);
					if (reply && action.id) return setReply(ctx, action.id);
					continue;
				}
				if (action.kind === "reply") return setReply(ctx, action.id);
				const op = action.kind === "resolve" ? "resolve" : action.kind === "park" ? "park" : "reopen";
				state = applyOps(state, [{ op, thread: action.id }]).state;
				persist();
				updateWidget(ctx);
			}
		},
	});

	function setReply(ctx: ExtensionContext, id: number) {
		if (state.active !== id || state.threads.find((t) => t.id === id)?.status !== "open") {
			state = applyOps(state, [{ op: "switch", thread: id }]).state;
			persist();
		}
		addressed = [id];
		updateWidget(ctx);
		ctx.ui.notify(`Next message goes to #${id} ${titleOf(id)}`, "info");
	}

	type BrowseAction = { kind: "view" | "reply" | "resolve" | "park" | "reopen"; id: number };

	function browse(ctx: ExtensionContext): Promise<BrowseAction | undefined> {
		const rows = treeOrder(state);
		const hasUnthreaded = segments.some((s) => s.thread === 0);
		const entries: { id: number; depth: number }[] = [
			...rows.map(({ t, depth }) => ({ id: t.id, depth })),
			...(hasUnthreaded ? [{ id: 0, depth: 0 }] : []),
		];
		let sel = Math.max(0, entries.findIndex((e) => e.id === state.active));
		return ctx.ui.custom<BrowseAction | undefined>((tui, theme, kb, done) => ({
			render(width: number) {
				const out: string[] = [theme.fg("accent", theme.bold(" Threads")), ""];
				entries.forEach((e, idx) => {
					const t = state.threads.find((x) => x.id === e.id);
					const count = segments.filter((s) => s.thread === e.id).length;
					const cursor = idx === sel ? theme.fg("accent", "› ") : "  ";
					if (!t) {
						out.push(`${cursor}${theme.fg("dim", `(unthreaded) · ${count} msgs`)}`);
						return;
					}
					const icon = t.status === "resolved" ? theme.fg("success", "✓") : t.status === "parked" ? theme.fg("warning", "⏸") : t.id === state.active ? theme.fg("accent", "▸") : "○";
					const items = liveItems(t);
					const done_ = items.filter((i) => i.done).length;
					const title = idx === sel ? theme.bold(`#${t.id} ${t.title}`) : `#${t.id} ${t.title}`;
					out.push(`${cursor}${"  ".repeat(e.depth)}${icon} ${title}${theme.fg("muted", `  ${done_}/${items.length} items · ${count} msgs`)}`);
					if (idx === sel) {
						for (const i of items) {
							const mark = i.done ? theme.fg("success", "✓") : theme.fg("muted", kindIcon(i.kind));
							out.push(`    ${"  ".repeat(e.depth)}${mark} ${theme.fg("dim", i.id)} ${i.done ? theme.fg("dim", i.text) : i.text}`);
						}
						if (t.note) out.push(`    ${"  ".repeat(e.depth)}${theme.fg("dim", `note: ${t.note}`)}`);
					}
				});
				out.push("", theme.fg("dim", " ↑↓ move · Enter view conversation · r reply here · x resolve · p park · o reopen · Esc close"));
				return out.map((l) => truncateToWidth(l, width));
			},
			handleInput(data: string) {
				const cur = entries[sel];
				if (kb.matches(data, "tui.select.up")) sel = (sel - 1 + entries.length) % entries.length;
				else if (kb.matches(data, "tui.select.down")) sel = (sel + 1) % entries.length;
				else if (kb.matches(data, "tui.select.confirm")) return done(cur && { kind: "view", id: cur.id });
				else if (kb.matches(data, "tui.select.cancel")) return done(undefined);
				else if (cur?.id && data === "r") return done({ kind: "reply", id: cur.id });
				else if (cur?.id && data === "x") return done({ kind: "resolve", id: cur.id });
				else if (cur?.id && data === "p") return done({ kind: "park", id: cur.id });
				else if (cur?.id && data === "o") return done({ kind: "reopen", id: cur.id });
				else return;
				tui.requestRender();
			},
			invalidate() {},
		}));
	}

	/** Full-screen view of one thread's conversation. Resolves true if user pressed "r". */
	function viewThread(ctx: ExtensionContext, id: number): Promise<boolean> {
		const t = state.threads.find((x) => x.id === id);
		const md: string[] = [];
		md.push(`# ${t ? `#${t.id} ${t.title}` : "Unthreaded messages"}`);
		if (t) {
			const parent = t.parent !== undefined ? state.threads.find((x) => x.id === t.parent) : undefined;
			if (parent) md.push(`*branched from #${parent.id} ${parent.title}*`);
			const items = liveItems(t);
			if (items.length) md.push(items.map((i) => `- [${i.done ? "x" : " "}] \`${i.id}\` ${i.text}${i.kind !== "task" ? ` *(${i.kind})*` : ""}`).join("\n"));
			if (t.question) md.push(`> **Question:** ${t.question}`);
			if (t.note) md.push(`*Note: ${t.note}*`);
		}
		const segs = segments.filter((s) => s.thread === id);
		if (segs.length === 0)
			md.push(
				t
					? "*No visible answer has been written in this thread yet. Press `r` and ask again to get one.*"
					: "*No unthreaded messages.*",
			);
		for (const s of segs) {
			md.push("---", s.role === "user" ? `**You:**\n\n${s.text}` : `**Assistant:**\n\n${s.text}`);
		}
		const source = md.join("\n\n");

		return ctx.ui.custom<boolean>((tui, theme, kb, done) => {
			const mdc = new Markdown(source, 1, 0, getMarkdownTheme());
			let cachedW = -1;
			let all: string[] = [];
			let top = -1; // -1 = scroll to end on first render
			const height = () => Math.max(5, (process.stdout.rows || 30) - 6);
			return {
				render(width: number) {
					if (width !== cachedW) {
						all = mdc.render(width);
						cachedW = width;
					}
					const h = height();
					const maxTop = Math.max(0, all.length - h);
					if (top < 0 || top > maxTop) top = top < 0 ? maxTop : maxTop;
					const view = all.slice(top, top + h);
					const pos = all.length > h ? ` ${top + 1}-${Math.min(all.length, top + h)}/${all.length}` : "";
					return [
						theme.fg("borderMuted", "─".repeat(width)),
						...view,
						theme.fg("borderMuted", "─".repeat(width)),
						truncateToWidth(theme.fg("dim", ` ↑↓/PgUp/PgDn/Home/End scroll · r reply in this thread · Esc back${pos}`), width),
					];
				},
				handleInput(data: string) {
					const h = height();
					if (matchesKey(data, Key.escape) || data === "q") return done(false);
					if (data === "r") return done(true);
					if (kb.matches(data, "tui.select.up") || data === "k") top = Math.max(0, top - 1);
					else if (kb.matches(data, "tui.select.down") || data === "j") top += 1;
					else if (matchesKey(data, Key.pageUp) || data === "b") top = Math.max(0, top - h);
					else if (matchesKey(data, Key.pageDown) || data === " ") top += h;
					else if (matchesKey(data, Key.home) || data === "g") top = 0;
					else if (matchesKey(data, Key.end) || data === "G") top = Number.MAX_SAFE_INTEGER;
					else return;
					tui.requestRender();
				},
				invalidate() {
					cachedW = -1;
					mdc.invalidate();
				},
			};
		});
	}
}
