/**
 * Threads Extension - logical conversation threads + open-items tracker
 *
 * Problem: one session often spawns several side questions. Forking/cloning
 * duplicates the session; instead this keeps ONE linear session but tags every
 * exchange with a logical thread, so follow-ups land "under" their thread.
 *
 * Model (v2)
 *  - Session GOAL (one line, always visible) + optional NEXT step: the anchor.
 *  - Threads are OPEN POINTS: questions the model asked the user (with prepared
 *    answers) or side discussions. They close with a one-line decision, which
 *    forms the decision log. No task lists (legacy items are shown read-only).
 *  - Unanswered questions are auto-parked after AUTO_PARK user messages.
 *
 * Features
 *  - `thread` tool: goal/next/ask/open/switch/resolve/park/reopen/rename. Batched ops = one call.
 *  - Alt+Q (/answer): answer open questions by picking prepared answers; the
 *    answers land in the editor as "4. …" lines for review, Enter sends.
 *  - User messages: lines starting with "#4 ", "4. ", "4) " or "4: " (also after "; ")
 *    address thread 4.
 *  - Widget above the editor: goal, open points, recent decisions.
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
 *   /thread-columns [on|off]  replies covering 2+ threads are shown side by side (one column
 *                        per thread, your answer to it on top); the sequential text is hidden
 */

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { execFile } from "node:child_process";
import { StringEnum } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext, MarkdownTransformContext, Theme } from "@earendil-works/pi-coding-agent";
import { getAgentDir, getMarkdownTheme } from "@earendil-works/pi-coding-agent";
import {
	type Component,
	Editor,
	Key,
	Markdown,
	matchesKey,
	truncateToWidth,
	visibleWidth,
	wrapTextWithAnsi,
} from "@earendil-works/pi-tui";
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
	/** Open question to the user (set via `ask`); answered via picker or "n. …". */
	prompt?: string;
	/** Prepared answers for `prompt`. */
	options?: string[];
	/** Index into options of the recommended answer. */
	recommended?: number;
	/** User messages since this question was last asked/answered (auto-park). */
	idle?: number;
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
	/** What this session is about (one line). */
	goal?: string;
	/** Short 1-3 word label of the goal (used as tmux session name). */
	short?: string;
	/** Optional single next step. */
	next?: string;
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
	prompt?: string;
	options?: string[];
	recommended?: number;
}

/** Unanswered questions are parked after this many user messages that don't touch them. */
const AUTO_PARK = 3;

const STATE_ENTRY = "threads-state";
/** TUI-only card that shows a multi-thread reply as side-by-side columns. */
const COLUMNS_ENTRY = "threads-columns";
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
const TMUX_STOPWORDS = new Set("a an the and or of for to in on at with by from into make add set fix get use build create implement update improve so that it its this my our also can be is are should".split(" "));

/** Short tmux-safe slug: lowercase, no '.'/':', max 3 words / 24 chars. Long goals lose filler words. */
function tmuxSlug(s: string): string {
	let words = s.toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g, "").split(/[^a-z0-9]+/).filter(Boolean);
	if (words.length > 3) {
		const core = words.filter((w) => !TMUX_STOPWORDS.has(w));
		if (core.length) words = core;
	}
	let out = "";
	for (const w of words.slice(0, 3)) {
		const next = out ? `${out}-${w}` : w;
		if (next.length > 24) break;
		out = next;
	}
	return out || words[0]?.slice(0, 24) || "";
}

function tmux(args: string[]): Promise<string> {
	return new Promise((resolve, reject) =>
		execFile("tmux", args, { timeout: 3000 }, (err, stdout) => (err ? reject(err) : resolve(stdout))),
	);
}

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

/** Open threads that currently carry a question for the user. */
const questionsOf = (state: State) => state.threads.filter((t) => t.status === "open" && t.prompt);

/** Compact plain-text state for the model. */
function stateForModel(state: State): string {
	const lines: string[] = [];
	lines.push(`Goal: ${state.goal ?? "(not set)"}`);
	if (state.next) lines.push(`Next: ${state.next}`);
	if (state.threads.length === 0) {
		lines.push("(no open points)");
		return lines.join("\n");
	}
	for (const { t, depth } of treeOrder(state)) {
		const pad = "  ".repeat(depth);
		if (t.status === "resolved") {
			lines.push(`${pad}#${t.id} [decided] ${t.title}${t.note ? ` → ${t.note}` : ""}`);
			continue;
		}
		const mark = t.id === state.active ? " (ACTIVE)" : "";
		lines.push(`${pad}#${t.id} [${t.status}]${mark} ${t.title}${t.note && t.status === "parked" ? ` (${t.note})` : ""}`);
		if (t.prompt && t.status === "open") {
			const opts = (t.options ?? []).map((o, i) => (i === t.recommended ? `${o} (recommended)` : o));
			lines.push(`${pad}  Q: ${t.prompt}${opts.length ? ` | options: ${opts.join(" / ")}` : ""}`);
		}
		for (const i of openItems(t)) lines.push(`${pad}  (legacy item) ${i.text}`);
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
				if (o.activate !== false || state.active === undefined) state.active = t.id;
				log.push(`opened #${t.id} ${t.title}${state.active === t.id ? " (active)" : ""}`);
				break;
			}
			case "goal":
			case "next": {
				const v = o.text?.trim() || undefined;
				if (o.op === "goal" && !v) {
					errors.push("goal: text required");
					break;
				}
				state[o.op] = v;
				if (o.op === "goal") state.short = o.title?.trim() || undefined;
				log.push(`${o.op}: ${v ?? "(cleared)"}${o.op === "goal" && state.short ? ` [${state.short}]` : ""}`);
				break;
			}
			case "ask": {
				if (!o.prompt) {
					errors.push("ask: prompt required");
					break;
				}
				let t: Thread | undefined;
				if (o.thread !== undefined) {
					t = state.threads.find((x) => x.id === o.thread);
					if (!t) {
						errors.push(`ask: thread #${o.thread} not found`);
						break;
					}
					if (o.title) t.title = o.title;
				} else {
					if (!o.title) {
						errors.push("ask: title required for a new question");
						break;
					}
					t = { id: state.nextId++, title: o.title, parent: o.parent, status: "open", items: [], nextItem: 1 };
					state.threads.push(t);
				}
				t.status = "open";
				t.prompt = o.prompt;
				t.options = (o.options ?? []).map((x) => x.trim()).filter(Boolean).slice(0, 6);
				t.recommended =
					o.recommended !== undefined && o.recommended >= 0 && o.recommended < t.options.length ? o.recommended : undefined;
				t.idle = 0;
				t.note = undefined;
				log.push(`asked #${t.id} ${t.prompt}`);
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
				t.idle = 0;
				// a decided question no longer waits for an answer
				if (o.op === "resolve") t.prompt = undefined;
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

/**
 * In a USER message, `#n `, `n. `, `n) ` or `n: ` at the start of a line (or after "; ")
 * means the following text is meant for thread n. The numeric forms only count for
 * threads that are not decided yet, so ordinary numbered lists stay untouched.
 */
const USER_MARKER_RE = /(?:^|(?<=;))[ \t]*(?:#(\d+)[ \t]+|(\d+)[.):][ \t]+)/gm;

/** Split a user message into per-thread sections. Unmarked text (preamble) has thread undefined. */
function splitUser(
	text: string,
	valid: (id: number, hash: boolean) => boolean,
): { parts: { thread?: number; text: string }[]; ids: number[] } {
	const parts: { thread?: number; text: string }[] = [];
	const ids: number[] = [];
	let last = 0;
	let thread: number | undefined;
	const clean = (s: string) => s.trim().replace(/;\s*$/, "").trim();
	for (const m of text.matchAll(USER_MARKER_RE)) {
		const id = Number(m[1] ?? m[2]);
		if (!valid(id, m[1] !== undefined)) continue;
		const chunk = clean(text.slice(last, m.index));
		if (chunk) parts.push({ thread, text: chunk });
		thread = id;
		if (!ids.includes(id)) ids.push(id);
		last = (m.index ?? 0) + m[0].length;
	}
	const rest = clean(text.slice(last));
	if (rest) parts.push({ thread, text: rest });
	return { parts, ids };
}

/** May a user line address thread `id`? `#n` works for any thread, `n.` only for undecided ones. */
function addressable(state: State, id: number, hash: boolean): boolean {
	const t = state.threads.find((x) => x.id === id);
	return !!t && (hash || t.status !== "resolved");
}

interface Replay {
	state: State;
	segments: Segment[];
	/** Thread of the latest assistant text (markers move it). */
	cursor: number;
	/** Rendered-markdown key -> thread for dividers on unmarked blocks / user messages. */
	tags: Map<string, number>;
	/** Per-thread parts of the latest user message (thread undefined = general text). */
	lastUser: { thread?: number; text: string }[];
	/** Assistant text blocks already shown as a column card (hidden in the transcript). */
	collapsed: Set<string>;
}

interface CardColumn {
	id: number;
	title: string;
	status: ThreadStatus;
	waiting: boolean;
	/** What the user wrote to this thread in the prompt this reply answers. */
	user: string[];
	text: string;
}

interface ColumnCard {
	/** Unaddressed user text (shown full width above the columns). */
	user?: string;
	/** Reply text before the first marker (full width). */
	preamble?: string;
	columns: CardColumn[];
	/** Assistant text blocks this card replaces in the transcript. */
	blocks: string[];
}

/** Walk the active branch: final state + every user/assistant text attributed to a thread. */
function replay(ctx: ExtensionContext): Replay {
	let state = emptyState();
	const segments: Segment[] = [];
	const tags = new Map<string, number>();
	const collapsed = new Set<string>();
	let lastUser: { thread?: number; text: string }[] = [];
	let pendingUser: Segment | undefined;
	/** Threads the latest user message has been attributed to (it may span several). */
	let userThreads = new Set<number>();
	let cursor = 0;
	/** Thread of the last thing shown in the transcript (for dividers). */
	let prev = 0;
	const valid = (id: number) => state.threads.some((t) => t.id === id);
	const userValid = (id: number, hash: boolean) => addressable(state, id, hash);

	for (const entry of ctx.sessionManager.getBranch() as any[]) {
		if (entry.type === "custom" && entry.customType === STATE_ENTRY && entry.data?.threads) {
			state = clone(entry.data as State);
			cursor = state.active ?? 0;
			continue;
		}
		if (entry.type === "custom" && entry.customType === COLUMNS_ENTRY && Array.isArray(entry.data?.blocks)) {
			for (const b of entry.data.blocks as string[]) collapsed.add(b.trim());
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
			const split = splitUser(text, userValid);
			lastUser = split.ids.length ? split.parts : [{ text: text.trim() }];
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
	return { state, segments, cursor, tags, lastUser, collapsed };
}

/**
 * If the reply to the latest user message covers 2+ threads (via [[#n]] markers),
 * build a column card for it. Undefined if not applicable or already built.
 */
function buildCard(ctx: ExtensionContext, r: Replay): ColumnCard | undefined {
	const branch = ctx.sessionManager.getBranch() as any[];
	let u = -1;
	branch.forEach((e, i) => {
		if (e.type === "message" && e.message?.role === "user" && textOf(e.message.content).trim()) u = i;
	});
	if (u < 0) return undefined;
	const after = branch.slice(u + 1);
	if (after.some((e) => e.type === "custom" && e.customType === COLUMNS_ENTRY)) return undefined;
	// only the final reply text (messages without tool calls), not progress notes
	const blocks = after
		.filter((e) => e.type === "message" && e.message?.role === "assistant")
		.filter((e) => !(Array.isArray(e.message.content) && e.message.content.some((b: any) => b?.type === "toolCall")))
		.flatMap((e) => assistantTexts(e.message.content));
	if (blocks.length === 0) return undefined;
	const valid = (id: number) => r.state.threads.some((t) => t.id === id);
	const byThread = new Map<number, string[]>();
	const preamble: string[] = [];
	let cur = 0;
	for (const block of blocks) {
		const split = splitByMarkers(block, cur, valid);
		cur = split.cursor;
		for (const p of split.parts) {
			if (!p.thread) preamble.push(p.text);
			else byThread.set(p.thread, [...(byThread.get(p.thread) ?? []), p.text]);
		}
	}
	if (byThread.size < 2) return undefined;
	// stable order (by thread id) so a thread keeps its column position across turns
	const columns: CardColumn[] = [...byThread.keys()]
		.sort((a, b) => a - b)
		.map((id) => {
			const t = r.state.threads.find((x) => x.id === id)!;
			return {
				id,
				title: t.title,
				status: t.status,
				waiting: t.status === "open" && !!t.prompt,
				user: r.lastUser.filter((p) => p.thread === id).map((p) => p.text),
				text: byThread.get(id)!.join("\n\n"),
			};
		});
	const general = r.lastUser.filter((p) => p.thread === undefined).map((p) => p.text).join("\n\n").trim();
	return {
		user: general || undefined,
		preamble: preamble.join("\n\n").trim() || undefined,
		columns,
		blocks: blocks.map((b) => b.trim()),
	};
}

const MIN_COL = 36;
const SEP = " │ ";

/** Render a column card: general text full width, then threads side by side (grid on narrow terminals). */
function renderCard(card: ColumnCard, width: number, theme: Theme, expanded: boolean): string[] {
	const out: string[] = [];
	const w = Math.max(20, width - 1);
	const pad = (l: string, cw: number) => {
		const s = truncateToWidth(l, cw);
		return s + " ".repeat(Math.max(0, cw - visibleWidth(s)));
	};
	const you = (text: string, cw: number, max: number) => {
		const lines = wrapTextWithAnsi(`You: ${text.replace(/\s*\n\s*/g, " ↵ ")}`, cw);
		const shown = expanded ? lines : lines.slice(0, max);
		const res = shown.map((l) => theme.fg("muted", l));
		if (shown.length < lines.length) res[res.length - 1] = theme.fg("muted", `${truncateToWidth(shown[shown.length - 1], cw - 2)} …`);
		return res;
	};
	const md = (text: string, cw: number) => new Markdown(text, 0, 0, getMarkdownTheme()).render(cw);

	if (card.user) out.push(...you(card.user, w, 3));
	if (card.preamble) out.push(...md(card.preamble, w));
	if (out.length) out.push("");

	const n = card.columns.length;
	const perRow = Math.max(1, Math.min(n, Math.floor((w + SEP.length) / (MIN_COL + SEP.length))));
	const cw = Math.floor((w - SEP.length * (perRow - 1)) / perRow);
	const sep = theme.fg("borderMuted", SEP);
	for (let r = 0; r < n; r += perRow) {
		if (r) out.push("");
		const cols = card.columns.slice(r, r + perRow).map((c) => {
			const icon =
				c.status === "resolved" ? theme.fg("success", "✓ ") : c.status === "parked" ? theme.fg("dim", "⏸ ") : c.waiting ? theme.fg("warning", "? ") : theme.fg("accent", "● ");
			const lines = [icon + theme.fg("accent", theme.bold(`#${c.id} ${c.title}`)), theme.fg("borderMuted", "─".repeat(cw))];
			for (const u of c.user) lines.push(...you(u, cw, 4));
			if (c.user.length) lines.push("");
			lines.push(...md(c.text, cw));
			return lines;
		});
		const h = Math.max(...cols.map((c) => c.length));
		for (let i = 0; i < h; i++) out.push(cols.map((c) => pad(c[i] ?? "", cw)).join(sep).replace(/\s+$/, ""));
	}
	return out.map((l) => truncateToWidth(` ${l}`, width));
}

// ---------------------------------------------------------------- extension

type WidgetMode = "full" | "compact" | "off";

export default function threadsExtension(pi: ExtensionAPI) {
	let state: State = emptyState();
	let segments: Segment[] = [];
	// widget mode is a user preference: persisted across sessions/restarts
	const PREFS_FILE = join(getAgentDir(), "threads.json");
	let widgetMode: WidgetMode = "full";
	/** Show multi-thread replies side by side (column cards). */
	let columnsOn = true;
	try {
		const p = JSON.parse(readFileSync(PREFS_FILE, "utf8"));
		if (["full", "compact", "off"].includes(p?.widgetMode)) widgetMode = p.widgetMode;
		if (typeof p?.columns === "boolean") columnsOn = p.columns;
	} catch {
		/* defaults */
	}
	const savePrefs = () => {
		try {
			writeFileSync(PREFS_FILE, `${JSON.stringify({ widgetMode, columns: columnsOn }, null, 2)}\n`);
		} catch {
			/* non-fatal */
		}
	};
	const setWidgetMode = (m: WidgetMode, ctx: ExtensionContext) => {
		widgetMode = m;
		savePrefs();
		updateWidget(ctx);
		if (ctx.hasUI) ctx.ui.notify(`Thread widget: ${m}`, "info");
	};
	/** Threads the user explicitly addressed in the upcoming prompt ("#n " sections). */
	let addressed: number[] = [];
	/** Serialized state last shown to the model (avoid re-injecting unchanged state). */
	let lastInjected = "";
	/** Markdown text -> thread id for a divider (only where the thread changes). */
	let tags = new Map<string, number>();
	/** Assistant blocks replaced by a column card. */
	let collapsed = new Set<string>();
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
		collapsed = r.collapsed;
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

	/**
	 * Mirror the goal into the pi session name (selector, footer, terminal title).
	 * Only overwrites a name we set ourselves (unset or equal to the previous goal),
	 * so a manual `/name` always wins.
	 */
	function syncSessionName(prevGoal?: string) {
		const goal = state.goal?.replace(/\s+/g, " ").trim();
		if (!goal) return;
		try {
			const current = pi.getSessionName()?.trim();
			if (current === goal) return;
			if (!current || (prevGoal && current === prevGoal.replace(/\s+/g, " ").trim())) pi.setSessionName(goal);
		} catch {
			/* naming is cosmetic */
		}
	}

	/** tmux name we derived from the previous goal in this process (to recognise our own names). */
	let lastTmuxBase: string | undefined;

	/**
	 * Rename the tmux session this pi runs in to a short slug of the goal.
	 * Only replaces tmux default names (numbers) or names we set ourselves; manual names win.
	 */
	async function syncTmuxName(prev?: { goal?: string; short?: string }) {
		if (!process.env.TMUX || !state.goal) return;
		const base = tmuxSlug(state.short || state.goal);
		if (!base) return;
		const ours = new Set([lastTmuxBase, prev?.goal ? tmuxSlug(prev.short || prev.goal) : undefined].filter(Boolean));
		const pane = process.env.TMUX_PANE ? ["-t", process.env.TMUX_PANE] : [];
		try {
			const current = (await tmux(["display-message", "-p", ...pane, "#S"])).trim();
			const currentBase = current.replace(/-\d+$/, "");
			if (currentBase === base) return;
			// @pi_autoname: session created by tmux-pick/agents switcher, named after its folder until pi knows the goal
			const auto = (await tmux(["show-options", "-qv", ...pane, "@pi_autoname"]).catch(() => "")).trim() === "1";
			if (!auto && !/^\d+$/.test(current) && !ours.has(currentBase)) return; // user-chosen name
			const taken = new Set((await tmux(["list-sessions", "-F", "#S"])).split("\n").map((s) => s.trim()));
			let name = base;
			for (let i = 2; taken.has(name); i++) name = `${base}-${i}`;
			await tmux(["rename-session", "-t", current, name]);
			lastTmuxBase = base;
			// from now on `ours` recognises our name; a later manual rename wins again
			if (auto) await tmux(["set-option", "-u", ...pane, "@pi_autoname"]).catch(() => {});
		} catch {
			/* not in tmux / tmux missing: cosmetic */
		}
	}

	// ------------------------------------------------------------ widget

	function widgetLines(theme: Theme, width: number): string[] {
		if (!state.goal && state.threads.length === 0) return [];
		const open = state.threads.filter((t) => t.status === "open");
		const waiting = questionsOf(state);
		const goal =
			theme.fg("accent", theme.bold("◎ ")) +
			(state.goal ? theme.bold(state.goal) : theme.fg("dim", "(no goal yet)")) +
			(state.next ? theme.fg("muted", `  · next: ${state.next}`) : "");
		const hint = waiting.length
			? theme.fg("warning", `${waiting.length} question${waiting.length > 1 ? "s" : ""} waiting`) +
				theme.fg("dim", " · Alt+Q answer")
			: "";

		if (widgetMode === "compact") {
			const extra = [open.length ? theme.fg("muted", `${open.length} open`) : "", hint].filter(Boolean);
			return [truncateToWidth(goal + (extra.length ? theme.fg("dim", "  · ") + extra.join(theme.fg("dim", " · ")) : ""), width)];
		}

		const lines = [goal];
		const MAX = 12;
		for (const { t, depth } of treeOrder(state)) {
			if (t.status === "resolved") continue;
			const indent = `  ${"  ".repeat(depth)}`;
			const isActive = t.id === state.active && open.length > 1;
			if (t.status === "parked") {
				lines.push(theme.fg("dim", `${indent}⏸ #${t.id} ${t.title}`));
				continue;
			}
			const icon = t.prompt ? theme.fg("warning", "?") : isActive ? theme.fg("accent", "▸") : theme.fg("muted", "●");
			const title = isActive ? theme.fg("accent", theme.bold(`#${t.id} ${t.title}`)) : theme.bold(`#${t.id} ${t.title}`);
			const sub = t.prompt ? theme.fg("muted", ` — ${t.prompt}`) : "";
			lines.push(`${indent}${icon} ${title}${sub}`);
			for (const i of openItems(t).slice(0, 2)) lines.push(theme.fg("dim", `${indent}    · ${i.text}`));
		}
		const decided = state.threads.filter((t) => t.status === "resolved");
		for (const t of decided.slice(-3)) {
			lines.push(
				`  ${theme.fg("success", "✓")} ${theme.fg("dim", `#${t.id} ${t.title}`)}${t.note ? theme.fg("muted", ` → ${t.note}`) : ""}`,
			);
		}
		if (decided.length > 3) lines.push(theme.fg("dim", `  … ${decided.length - 3} earlier decisions (/threads)`));
		if (hint) lines.push(`  ${hint}`);
		const out = lines.length > MAX ? [...lines.slice(0, MAX - 1), theme.fg("dim", `  … (${lines.length - MAX + 1} more lines – /threads)`)] : lines;
		return out.map((l) => truncateToWidth(l, width));
	}

	function updateWidget(ctx: ExtensionContext) {
		// for the agents-hub extension (tmux @pi_goal / @pi_questions -> picker, quickshell)
		pi.events.emit("threads:state", { goal: state.goal, short: state.short, questions: questionsOf(state).length });
		if (!ctx.hasUI) return;
		if (widgetMode === "off" || (state.threads.length === 0 && !state.goal)) {
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
				: widgetMode === "off" && questionsOf(state).length
					? ctx.ui.theme.fg("warning", `? ${questionsOf(state).length} (Alt+Q)`)
					: active && widgetMode === "off"
						? ctx.ui.theme.fg("accent", `#${active.id}`)
						: undefined,
		);
	}

	// ------------------------------------------------------------ transcript dividers

	pi.registerMarkdownTransformer((markdown: string, context: MarkdownTransformContext): string => {
		if (context.messageType === "assistant-thinking" || !markdown.trim()) return markdown;
		// shown side by side in the column card right below this message
		if (context.messageType === "assistant" && columnsOn && !context.isStreaming && collapsed.has(markdown.trim())) return "";
		const tag = tags.get(markdown) ?? tags.get(markdown.trim());
		let out = markdown;
		if (context.messageType === "user") {
			// only the explicit "#n " form becomes a divider; "4. answer" reads fine as is
			out = out.replace(USER_MARKER_RE, (whole, id: string | undefined) =>
				id && state.threads.some((t) => t.id === Number(id)) ? `\n*${label(Number(id))}*\n\n` : whole,
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

	pi.on("session_start", async (_e, ctx) => {
		rebuild(ctx);
		syncSessionName(); // name older sessions that have a goal but no name
		void syncTmuxName();
	});
	pi.on("session_tree", async (_e, ctx) => {
		rebuild(ctx);
		await refreshTranscript(ctx);
	});
	pi.on("agent_settled", async (_e, ctx) => {
		const before = JSON.stringify([...tags]);
		if (rebuild(ctx)) persist(); // markers moved the active thread
		let carded = false;
		if (columnsOn) {
			const card = buildCard(ctx, replay(ctx));
			if (card) {
				pi.appendEntry<ColumnCard>(COLUMNS_ENTRY, card);
				for (const b of card.blocks) collapsed.add(b);
				carded = true;
			}
		}
		if (carded || JSON.stringify([...tags]) !== before) await refreshTranscript(ctx);
	});

	// ------------------------------------------------------------ column cards

	pi.registerEntryRenderer<ColumnCard>(COLUMNS_ENTRY, (entry, { expanded }, theme) => {
		const card = entry.data;
		let key = "";
		let lines: string[] = [];
		return {
			render(width: number) {
				if (!columnsOn || !card?.columns?.length) return [];
				const k = `${width}:${expanded}`;
				if (k !== key) {
					lines = renderCard(card, width, theme, expanded);
					key = k;
				}
				return lines;
			},
			invalidate() {
				key = "";
			},
		};
	});

	pi.registerCommand("thread-columns", {
		description: "Show multi-thread replies side by side: on | off (no arg toggles)",
		handler: async (args, ctx) => {
			const a = (args ?? "").trim();
			columnsOn = a === "on" ? true : a === "off" ? false : !columnsOn;
			savePrefs();
			await refreshTranscript(ctx);
			ctx.ui.notify(`Thread columns: ${columnsOn ? "on" : "off"}`, "info");
		},
	});

	// Lines starting with "#n " address thread n; one message may address several threads.
	pi.on("input", async (event, ctx) => {
		if (event.source === "extension") return { action: "continue" };
		addressFrom(event.text, ctx);
		return { action: "continue" };
	});

	/** Mark the threads addressed by "#n " lines of an outgoing user message. */
	function addressFrom(text: string, ctx: ExtensionContext) {
		const { ids } = splitUser(text, (id, hash) => addressable(state, id, hash));
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
		const targets = addressed;
		addressed = [];
		// auto-park questions the user keeps not answering
		const parked: number[] = [];
		if (questionsOf(state).length) {
			const next = clone(state);
			for (const t of questionsOf(next)) {
				if (targets.includes(t.id)) t.idle = 0;
				else if ((t.idle = (t.idle ?? 0) + 1) >= AUTO_PARK) {
					t.status = "parked";
					t.note = "auto-parked: not answered";
					t.idle = 0;
					parked.push(t.id);
				}
			}
			if (parked.includes(next.active ?? -1)) next.active = openFallback(next, 0) || undefined;
			state = next;
			persist();
		}
		const snapshot = stateForModel(state);
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
		op: StringEnum(["goal", "next", "ask", "open", "switch", "resolve", "park", "reopen", "rename", "list"] as const),
		thread: Type.Optional(
			Type.Number({ description: "Thread id (ask: update this existing question instead of creating one; others: defaults to active)" }),
		),
		title: Type.Optional(
			Type.String({ description: "Short label, 2-5 words (ask, open, rename); goal: 1-3 word short name, e.g. 'tmux autoname'" }),
		),
		text: Type.Optional(Type.String({ description: "goal / next: one line (next: empty clears it)" })),
		prompt: Type.Optional(Type.String({ description: "ask: the question to the user, one sentence" })),
		options: Type.Optional(
			Type.Array(Type.String(), { description: "ask: 2-4 prepared answers, short and concrete (the user can always type their own)" }),
		),
		recommended: Type.Optional(Type.Number({ description: "ask: index into options of your recommendation" })),
		question: Type.Optional(Type.String({ description: "open: short quote of what started this side discussion" })),
		parent: Type.Optional(Type.Number({ description: "ask/open: thread this one branches off" })),
		activate: Type.Optional(Type.Boolean({ description: "open: make it the active thread (default true)" })),
		note: Type.Optional(Type.String({ description: "resolve: the decision/outcome in ≤12 words; park: reason" })),
	});

	pi.registerTool({
		name: TOOL,
		label: "Thread",
		description:
			"Keep the session anchored: its goal, the questions you are waiting on the user for (with prepared answers), side discussions, and the decisions made. " +
			"Pass several ops at once. Ops: goal{text}, next{text}, ask{title,prompt,options,recommended?,parent?} (new question) / ask{thread,prompt,options,...} (follow-up, same number), " +
			"open{title,question?,parent?,activate?} (side discussion), switch{thread}, resolve{thread,note=decision}, park{thread,note?}, reopen{thread}, rename{thread,title}, list.",
		promptSnippet: "Session goal, questions to the user with prepared answers, side discussions, decision log",
		promptGuidelines: [
			"`thread` tool – GOAL: on the first substantive request set `goal` (one line: what this session is about) and pass `title` with a 1-3 word short name for it (used as tmux session name). Change it only if the user clearly pivots. Optionally keep ONE `next` step. There are no task lists: never track your own work steps here.",
			"`thread` tool – QUESTIONS: whenever you need the user to decide or answer something, register each question with `ask` (title 2-5 words, one-sentence prompt, 2-4 short concrete options, `recommended` = your pick). In the visible reply, list them with their thread number, e.g. `**#4 Ban duration** – How long …? (recommended: 1 h)`. The user answers with lines like `4. 1 hour` / `#4 …`, or via an answer picker. Don't `ask` rhetorical or trivial yes/no confirmations.",
			"`thread` tool – FOLLOW-UPS & CLOSING: when an answer leads to a follow-up question on the same point, `ask{thread:n,…}` again (same number). As soon as a point is settled, `resolve{thread:n, note}` with the decision in ≤12 words (e.g. \"1 h ban, IPv6 included\") – these notes are the session's decision log. Unanswered questions are auto-parked after a few user messages; re-`ask` them only if still relevant.",
			"`thread` tool – SIDE DISCUSSIONS: `open` a thread only when a distinct topic branches off while other work is unfinished. Never open a thread for the main line of work itself. Resolve it with a short outcome note when done.",
			"Markers: only when your reply covers 2+ threads (e.g. the user answered #4 and #6), start each part with a marker line `[[#n]]`; text after it is filed under thread n. With a single topic, write no markers. Such replies are shown to the user as side-by-side columns (one per thread, with the user's own answer on top), so keep each section compact and self-contained and don't repeat the user's answer.",
			"Do `thread` ops BEFORE writing the visible reply and batch them into one call (parallel with other tools when possible); write the reply as your final message with no tool call after it. Skip the tool entirely when nothing changed. Never resolve a question without answering/confirming it visibly in the reply.",
			"A hidden [threads] message shows the current state (goal, open points, decisions). User lines starting with `#n `, `n. `, `n) ` or `n: ` address thread n; answer each addressed thread (in its own [[#n]] section if there are several).",
		],
		parameters: Type.Object({ ops: Type.Array(OpSchema, { minItems: 1 }) }),

		async execute(_id, params, _signal, _onUpdate, ctx) {
			const ops = params.ops as Op[];
			// markers written earlier in this turn may have moved the active thread
			const cur = replay(ctx).cursor;
			if (cur && state.threads.some((t) => t.id === cur)) state.active = cur;
			const prevGoal = state.goal;
			const prevShort = state.short;
			const r = applyOps(state, ops);
			// atomic: on any error nothing is applied, so the model can't half-apply a batch
			if (r.errors.length) {
				r.log.length = 0;
				r.errors.push("No ops were applied (batch is atomic). Fix and retry.");
			} else {
				state = r.state;
				if (state.goal !== prevGoal) syncSessionName(prevGoal);
				if (state.goal !== prevGoal || state.short !== prevShort) void syncTmuxName({ goal: prevGoal, short: prevShort });
			}
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
			// Header is a short summary; the result lists what changed in words.
			const count = (p: (o: Op) => boolean) => ops.filter(p).length;
			const asks = count((o) => o.op === "ask");
			const decided = count((o) => o.op === "resolve");
			const parts = [
				count((o) => o.op === "goal") ? "goal" : "",
				asks ? `${asks} question${asks > 1 ? "s" : ""}` : "",
				decided ? `${decided} decided` : "",
				count((o) => o.op === "open") ? "side topic" : "",
			].filter(Boolean);
			const summary = parts.length ? theme.fg("muted", parts.join(" · ")) : "";
			return { render: (w: number) => [truncateToWidth(theme.fg("toolTitle", theme.bold("thread ")) + summary, w)], invalidate: () => {} };
		},

		renderResult(result, { expanded }, theme) {
			const d = result.details as ToolDetails | undefined;
			const lines: string[] = [];
			if (d) {
				const s = d.state;
				const item = (ref: string) => s.threads.flatMap((t) => t.items).find((i) => i.id === ref);
				const thr = (id?: number) => s.threads.find((t) => t.id === (id ?? s.active));
				if (!d.errors.length) {
					let movedActive = false;
					for (const o of d.ops ?? []) {
						const refs = [...(o.item ? [o.item] : []), ...(o.items ?? [])];
						switch (o.op) {
							case "goal":
								lines.push(theme.fg("accent", "◎ goal: ") + (o.text ?? ""));
								break;
							case "next":
								lines.push(theme.fg("muted", `→ next: ${o.text?.trim() || "(cleared)"}`));
								break;
							case "ask": {
								const t =
									o.thread !== undefined ? thr(o.thread) : [...s.threads].reverse().find((x) => x.title === o.title);
								lines.push(
									theme.fg("warning", `? #${t?.id ?? "?"} `) + theme.bold(t?.title ?? o.title ?? "") + theme.fg("muted", ` — ${o.prompt ?? ""}`),
								);
								const opts = (o.options ?? []).map((x, i) => (i === o.recommended ? theme.fg("success", `${x} ★`) : x));
								if (opts.length) lines.push(`    ${opts.join(theme.fg("dim", " · "))}`);
								break;
							}
							case "open": {
								lines.push(theme.fg("accent", `+ side topic: ${o.title ?? ""}`));
								for (const t of o.items ?? []) lines.push(theme.fg("muted", `    ☐ ${t}`));
								if (o.activate !== false) movedActive = true;
								break;
							}
							case "add":
								for (const t of [...(o.text ? [o.text] : []), ...(o.items ?? [])])
									lines.push(theme.fg("muted", `☐ ${t}`));
								break;
							case "done":
								for (const r of refs) lines.push(theme.fg("success", "✓ ") + (item(r)?.text ?? r));
								break;
							case "undo":
								for (const r of refs) lines.push(theme.fg("warning", "↺ ") + (item(r)?.text ?? r));
								break;
							case "drop":
								for (const r of refs) lines.push(theme.fg("dim", `✗ ${item(r)?.text ?? r}`));
								break;
							case "resolve":
							case "park":
							case "reopen": {
								const verb = o.op === "resolve" ? "✓" : o.op === "park" ? "⏸ parked" : "↺ reopened";
								const col = o.op === "resolve" ? "success" : "warning";
								const t = thr(o.thread);
								lines.push(
									theme.fg(col, `${verb} `) +
										(t ? `#${t.id} ${t.title}` : "") +
										(o.note ? theme.fg(o.op === "resolve" ? "text" : "dim", ` → ${o.note}`) : ""),
								);
								if (o.op === "reopen") movedActive = true;
								break;
							}
							case "rename":
								lines.push(theme.fg("muted", `renamed → ${o.title ?? ""}`));
								break;
							case "switch":
								movedActive = true;
								break;
						}
					}
					const active = thr(s.active);
					if (movedActive && active) lines.push(theme.fg("accent", `▸ now in: ${active.title}`));
				}
				for (const e of d.errors) lines.push(theme.fg("error", e));
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
						if (t.prompt && t.status === "open")
							out.push(
								truncateToWidth(
									theme.fg("warning", "  ? ") + t.prompt + theme.fg("dim", (t.options ?? []).length ? `  (${t.options!.join(" / ")})` : ""),
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

	// ------------------------------------------------------------ answer picker

	/** Picked/typed answers not yet put into the editor (kept when the picker is closed with Esc). */
	const pickerDrafts = new Map<number, string>();
	let pickerOpen = false;

	pi.registerShortcut(Key.alt("q"), {
		description: "Answer open questions by picking prepared answers",
		handler: async (ctx) => openPicker(ctx),
	});

	pi.registerCommand("answer", {
		description: "Answer open questions by picking prepared answers (also Alt+Q)",
		handler: async (_args, ctx) => openPicker(ctx),
	});

	async function openPicker(ctx: ExtensionContext) {
		if (ctx.mode !== "tui" || !ctx.hasUI) {
			ctx.ui.notify("The answer picker needs interactive mode", "error");
			return;
		}
		if (pickerOpen) return;
		const qs = questionsOf(state);
		if (qs.length === 0) {
			ctx.ui.notify("No open questions", "info");
			return;
		}
		pickerOpen = true;
		try {
			const answers = await ctx.ui.custom<Map<number, string> | undefined>((tui, theme, _kb, done) =>
				createPicker(tui, theme, done, qs),
			);
			if (!answers || answers.size === 0) return;
			const lines = qs.filter((q) => answers.has(q.id)).map((q) => `${q.id}. ${answers.get(q.id)}`);
			for (const q of qs) pickerDrafts.delete(q.id);
			const existing = (ctx.ui as any).getEditorText?.() as string | undefined;
			ctx.ui.setEditorText([existing?.trim(), ...lines].filter(Boolean).join("\n"));
			ctx.ui.notify("Answers are in the editor – edit if needed, Enter sends", "info");
		} finally {
			pickerOpen = false;
		}
	}

	function createPicker(tui: any, theme: Theme, done: (v: Map<number, string> | undefined) => void, qs: Thread[]) {
		const answers = new Map<number, string>();
		for (const q of qs) if (pickerDrafts.has(q.id)) answers.set(q.id, pickerDrafts.get(q.id)!);
		const single = qs.length === 1;
		const tabs = single ? 1 : qs.length + 1; // last tab = submit
		let tab = Math.max(0, qs.findIndex((q) => !answers.has(q.id)));
		let typing = false;
		const editor = new Editor(tui, {
			borderColor: (s: string) => theme.fg("accent", s),
			selectList: {
				selectedPrefix: (s: string) => theme.fg("accent", s),
				selectedText: (s: string) => theme.fg("accent", s),
				description: (s: string) => theme.fg("muted", s),
				scrollInfo: (s: string) => theme.fg("dim", s),
				noMatch: (s: string) => theme.fg("warning", s),
			},
		} as any);
		type Row = { label: string; kind: "option" | "own" | "skip" };
		const rows = (q: Thread): Row[] => [
			...(q.options ?? []).map((o, i) => ({ label: i === q.recommended ? `${o}  ★ recommended` : o, kind: "option" as const })),
			{ label: "✎ Type my own answer…", kind: "own" },
			{ label: "↷ Skip for now", kind: "skip" },
		];
		/** Default cursor: previous answer, else the recommendation, else the first option. */
		const defaultRow = (q: Thread) => {
			const a = answers.get(q.id);
			const prev = a !== undefined ? (q.options ?? []).indexOf(a) : -1;
			if (prev >= 0) return prev;
			if (a !== undefined) return (q.options ?? []).length; // own answer
			return q.recommended ?? 0;
		};
		let row = qs[tab] ? defaultRow(qs[tab]) : 0;
		const go = (t: number) => {
			tab = (t + tabs) % tabs;
			if (qs[tab]) row = defaultRow(qs[tab]);
			typing = false;
		};
		const finish = () => done(new Map(answers));
		const advance = () => {
			if (single) return finish();
			const nextOpen = qs.findIndex((q, i) => i > tab && !answers.has(q.id));
			go(nextOpen >= 0 ? nextOpen : qs.length);
		};
		const save = () => {
			pickerDrafts.clear();
			for (const [k, v] of answers) pickerDrafts.set(k, v);
		};
		editor.onSubmit = (value: string) => {
			const q = qs[tab];
			if (!q) return;
			if (value.trim()) answers.set(q.id, value.trim());
			typing = false;
			editor.setText("");
			advance();
			tui.requestRender();
		};

		return {
			render(width: number): string[] {
				const out: string[] = [theme.fg("accent", "─".repeat(width))];
				const wrap = (prefix: string, text: string) => {
					const w = Math.max(10, width - visibleWidth(prefix));
					wrapTextWithAnsi(text, w).forEach((l, i) => out.push(`${i ? " ".repeat(visibleWidth(prefix)) : prefix}${l}`));
				};
				if (state.goal) out.push(truncateToWidth(theme.fg("dim", ` ◎ ${state.goal}`), width));
				if (!single) {
					const bar = qs.map((q, i) => {
						const text = ` ${answers.has(q.id) ? "■" : "□"} #${q.id} ${q.title} `;
						return i === tab ? theme.bg("selectedBg", theme.fg("text", text)) : theme.fg(answers.has(q.id) ? "success" : "muted", text);
					});
					const sub = " ✓ Done ";
					bar.push(tab === qs.length ? theme.bg("selectedBg", theme.fg("text", sub)) : theme.fg(answers.size ? "success" : "dim", sub));
					wrap(" ", bar.join(" "));
				}
				out.push("");
				const q = qs[tab];
				if (!q) {
					wrap(" ", theme.fg("accent", theme.bold("Your answers")));
					for (const x of qs) {
						const a = answers.get(x.id);
						wrap("   ", `${theme.fg("muted", `${x.id}. ${x.title}: `)}${a ?? theme.fg("dim", "(skipped – stays open)")}`);
					}
					out.push("");
					wrap(" ", answers.size ? theme.fg("success", "Enter: put answers into the editor") : theme.fg("warning", "Nothing answered yet"));
				} else {
					wrap(" ", theme.bold(q.prompt ?? ""));
					out.push("");
					rows(q).forEach((r, i) => {
						const sel = i === row;
						const picked = r.kind === "option" && answers.get(q.id) === q.options?.[i];
						const color = sel ? "accent" : r.kind === "option" ? "text" : "muted";
						wrap(sel ? theme.fg("accent", " > ") : "   ", theme.fg(color, `${r.kind === "option" ? `${i + 1}. ` : ""}${r.label}${picked ? " ✓" : ""}`));
					});
					const own = answers.get(q.id);
					if (own && !(q.options ?? []).includes(own)) wrap("     ", theme.fg("success", `your answer: ${own}`));
					editor.focused = typing;
					if (typing) {
						out.push("");
						for (const l of editor.render(Math.max(10, width - 2))) out.push(` ${l}`);
					}
				}
				out.push("");
				const help = typing
					? "Enter save · Shift+Enter newline · Esc back to options"
					: `↑↓ choose · 1-9 pick · Enter select${single ? "" : " · Tab/←→ question"} · Esc close (answers kept)`;
				wrap(" ", theme.fg("dim", help));
				out.push(theme.fg("accent", "─".repeat(width)));
				return out.map((l) => truncateToWidth(l, width));
			},
			handleInput(data: string) {
				if (typing) {
					if (matchesKey(data, Key.escape)) {
						typing = false;
						editor.setText("");
					} else editor.handleInput(data);
					return tui.requestRender();
				}
				if (matchesKey(data, Key.escape) || matchesKey(data, Key.alt("q"))) {
					save();
					return done(undefined);
				}
				if (!single && (matchesKey(data, Key.tab) || matchesKey(data, Key.right))) go(tab + 1);
				else if (!single && (matchesKey(data, Key.shift("tab")) || matchesKey(data, Key.left))) go(tab - 1);
				else if (!qs[tab]) {
					if (matchesKey(data, Key.enter) && answers.size) return finish();
					return;
				} else {
					const q = qs[tab];
					const rs = rows(q);
					const pick = (i: number) => {
						const r = rs[i];
						row = i;
						if (r.kind === "own") {
							typing = true;
							const prev = answers.get(q.id);
							editor.setText(prev && !(q.options ?? []).includes(prev) ? prev : "");
							return;
						}
						if (r.kind === "skip") answers.delete(q.id);
						else answers.set(q.id, q.options![i]);
						if (single && r.kind === "skip") {
							save();
							return done(undefined);
						}
						advance();
					};
					if (matchesKey(data, Key.up)) row = (row - 1 + rs.length) % rs.length;
					else if (matchesKey(data, Key.down)) row = (row + 1) % rs.length;
					else if (matchesKey(data, Key.enter)) pick(row);
					else if (/^[1-9]$/.test(data) && Number(data) <= (q.options ?? []).length) pick(Number(data) - 1);
					else return;
				}
				tui.requestRender();
			},
			invalidate() {
				editor.invalidate?.();
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
