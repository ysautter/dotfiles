/**
 * Subagent Tool - Delegate tasks to specialized agents
 *
 * Spawns a separate `pi` process for each subagent invocation,
 * giving it an isolated context window.
 *
 * Supports three modes:
 *   - Single: { agent: "name", task: "..." }
 *   - Parallel: { tasks: [{ agent: "name", task: "..." }, ...] }
 *   - Chain: { chain: [{ agent: "name", task: "... {previous} ..." }, ...] }
 *
 * Runs subagents in RPC mode: events stream over stdout, and stdin stays open so the user
 * can take control from the `/subagents` live viewer (steer, follow-up, abort, hold).
 */

import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { AgentToolResult, ThinkingLevel } from "@earendil-works/pi-agent-core";
import type { Message } from "@earendil-works/pi-ai";
import { StringEnum } from "@earendil-works/pi-ai";
import {
	CONFIG_DIR_NAME,
	type ExtensionAPI,
	getAgentDir,
	getMarkdownTheme,
	withFileMutationQueue,
} from "@earendil-works/pi-coding-agent";
import type { Theme } from "@earendil-works/pi-coding-agent";
import type { Component, TUI } from "@earendil-works/pi-tui";
import {
	Container,
	Input,
	Key,
	Markdown,
	matchesKey,
	Spacer,
	Text,
	truncateToWidth,
	visibleWidth,
} from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { type AgentConfig, type AgentScope, discoverAgents } from "./agents.ts";

const MAX_PARALLEL_TASKS = 8;
const MAX_CONCURRENCY = 4;
const COLLAPSED_ITEM_COUNT = 10;
const PER_TASK_OUTPUT_CAP = 50 * 1024;
const RESULT_PREVIEW_LINES = 15;
const SUBAGENT_SESSION_DIR = path.join(getAgentDir(), "subagent-sessions");

function shortenHome(p: string): string {
	const home = os.homedir();
	return p.startsWith(home) ? `~${p.slice(home.length)}` : p;
}

function sessionNote(results: SingleResult[]): string {
	let note = "";
	const label = (r: SingleResult) => `${r.agent}${r.step ? ` (step ${r.step})` : ""}`;
	const steered = results.filter((r) => r.interventions?.length);
	if (steered.length) {
		const lines = steered.map(
			(r) => `- ${label(r)}:\n${r.interventions!.map((m) => `  > ${m.replace(/\n/g, "\n    ")}`).join("\n")}`,
		);
		note += `\n\n[The user took control of a subagent and sent it these messages; its output reflects them]\n${lines.join("\n")}`;
	}
	const lines = results.filter((r) => r.sessionFile).map((r) => `- ${label(r)}: ${r.sessionFile}`);
	if (lines.length) note += `\n\n[Subagent session transcripts]\n${lines.join("\n")}`;
	return note;
}

function formatTokens(count: number): string {
	if (count < 1000) return count.toString();
	if (count < 10000) return `${(count / 1000).toFixed(1)}k`;
	if (count < 1000000) return `${Math.round(count / 1000)}k`;
	return `${(count / 1000000).toFixed(1)}M`;
}

function formatUsageStats(
	usage: {
		input: number;
		output: number;
		cacheRead: number;
		cacheWrite: number;
		cost: number;
		contextTokens?: number;
		turns?: number;
	},
	model?: string,
): string {
	const parts: string[] = [];
	if (usage.turns) parts.push(`${usage.turns} turn${usage.turns > 1 ? "s" : ""}`);
	if (usage.input) parts.push(`↑${formatTokens(usage.input)}`);
	if (usage.output) parts.push(`↓${formatTokens(usage.output)}`);
	if (usage.cacheRead) parts.push(`R${formatTokens(usage.cacheRead)}`);
	if (usage.cacheWrite) parts.push(`W${formatTokens(usage.cacheWrite)}`);
	if (usage.cost) parts.push(`$${usage.cost.toFixed(4)}`);
	if (usage.contextTokens && usage.contextTokens > 0) {
		parts.push(`ctx:${formatTokens(usage.contextTokens)}`);
	}
	if (model) parts.push(model);
	return parts.join(" ");
}

function formatToolCall(
	toolName: string,
	args: Record<string, unknown>,
	themeFg: (color: any, text: string) => string,
	full = false,
): string {
	const shortenPath = (p: string) => {
		const home = os.homedir();
		return p.startsWith(home) ? `~${p.slice(home.length)}` : p;
	};

	switch (toolName) {
		case "bash": {
			const command = (args.command as string) || "...";
			const preview = !full && command.length > 60 ? `${command.slice(0, 60)}...` : command;
			return themeFg("muted", "$ ") + themeFg("toolOutput", preview);
		}
		case "read": {
			const rawPath = (args.file_path || args.path || "...") as string;
			const filePath = shortenPath(rawPath);
			const offset = args.offset as number | undefined;
			const limit = args.limit as number | undefined;
			let text = themeFg("accent", filePath);
			if (offset !== undefined || limit !== undefined) {
				const startLine = offset ?? 1;
				const endLine = limit !== undefined ? startLine + limit - 1 : "";
				text += themeFg("warning", `:${startLine}${endLine ? `-${endLine}` : ""}`);
			}
			return themeFg("muted", "read ") + text;
		}
		case "write": {
			const rawPath = (args.file_path || args.path || "...") as string;
			const filePath = shortenPath(rawPath);
			const content = (args.content || "") as string;
			const lines = content.split("\n").length;
			let text = themeFg("muted", "write ") + themeFg("accent", filePath);
			if (lines > 1) text += themeFg("dim", ` (${lines} lines)`);
			return text;
		}
		case "edit": {
			const rawPath = (args.file_path || args.path || "...") as string;
			return themeFg("muted", "edit ") + themeFg("accent", shortenPath(rawPath));
		}
		case "ls": {
			const rawPath = (args.path || ".") as string;
			return themeFg("muted", "ls ") + themeFg("accent", shortenPath(rawPath));
		}
		case "find": {
			const pattern = (args.pattern || "*") as string;
			const rawPath = (args.path || ".") as string;
			return themeFg("muted", "find ") + themeFg("accent", pattern) + themeFg("dim", ` in ${shortenPath(rawPath)}`);
		}
		case "grep": {
			const pattern = (args.pattern || "") as string;
			const rawPath = (args.path || ".") as string;
			return (
				themeFg("muted", "grep ") +
				themeFg("accent", `/${pattern}/`) +
				themeFg("dim", ` in ${shortenPath(rawPath)}`)
			);
		}
		default: {
			const argsStr = JSON.stringify(args);
			const preview = !full && argsStr.length > 50 ? `${argsStr.slice(0, 50)}...` : argsStr;
			return themeFg("accent", toolName) + themeFg("dim", ` ${preview}`);
		}
	}
}

interface UsageStats {
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
	cost: number;
	contextTokens: number;
	turns: number;
}

interface SingleResult {
	agent: string;
	agentSource: "user" | "project" | "unknown";
	task: string;
	exitCode: number;
	messages: Message[];
	stderr: string;
	usage: UsageStats;
	model?: string;
	stopReason?: string;
	errorMessage?: string;
	step?: number;
	sessionId?: string;
	sessionFile?: string;
	/** Messages the user sent to the subagent via the live viewer */
	interventions?: string[];
}

interface SubagentDetails {
	mode: "single" | "parallel" | "chain";
	agentScope: AgentScope;
	projectAgentsDir: string | null;
	results: SingleResult[];
}

function getFinalOutput(messages: Message[]): string {
	for (let i = messages.length - 1; i >= 0; i--) {
		const msg = messages[i];
		if (msg.role === "assistant") {
			for (const part of msg.content) {
				if (part.type === "text") return part.text;
			}
		}
	}
	return "";
}

function isFailedResult(result: SingleResult): boolean {
	return result.exitCode !== 0 || result.stopReason === "error" || result.stopReason === "aborted";
}

function getResultOutput(result: SingleResult): string {
	if (isFailedResult(result)) {
		return result.errorMessage || result.stderr || getFinalOutput(result.messages) || "(no output)";
	}
	return getFinalOutput(result.messages) || "(no output)";
}

function truncateParallelOutput(output: string): string {
	const byteLength = Buffer.byteLength(output, "utf8");
	if (byteLength <= PER_TASK_OUTPUT_CAP) return output;

	let truncated = output.slice(0, PER_TASK_OUTPUT_CAP);
	while (Buffer.byteLength(truncated, "utf8") > PER_TASK_OUTPUT_CAP) {
		truncated = truncated.slice(0, -1);
	}
	return `${truncated}\n\n[Output truncated: ${byteLength - Buffer.byteLength(truncated, "utf8")} bytes omitted. Full output preserved in tool details.]`;
}

type DisplayItem =
	| { type: "text"; text: string }
	| { type: "thinking"; text: string }
	| { type: "toolCall"; name: string; args: Record<string, any> }
	| { type: "toolResult"; name: string; text: string; isError: boolean }
	| { type: "user"; text: string };

function getDisplayItems(messages: Message[]): DisplayItem[] {
	const items: DisplayItem[] = [];
	let seenTask = false;
	for (const msg of messages) {
		if (msg.role === "user") {
			// The first user message is the delegated task itself; later ones are user interventions.
			if (!seenTask) {
				seenTask = true;
				continue;
			}
			const c = msg.content as unknown;
			const text =
				typeof c === "string"
					? c
					: Array.isArray(c)
						? c
								.filter((p: any) => p?.type === "text")
								.map((p: any) => p.text)
								.join("\n")
						: "";
			if (text.trim()) items.push({ type: "user", text });
		} else if (msg.role === "assistant") {
			for (const part of msg.content) {
				if (part.type === "text") items.push({ type: "text", text: part.text });
				else if (part.type === "thinking") {
					if (part.thinking?.trim()) items.push({ type: "thinking", text: part.thinking });
				} else if (part.type === "toolCall") items.push({ type: "toolCall", name: part.name, args: part.arguments });
			}
		} else if (msg.role === "toolResult") {
			const text = msg.content
				.filter((c) => c.type === "text")
				.map((c) => (c as { text: string }).text)
				.join("\n");
			items.push({ type: "toolResult", name: msg.toolName, text, isError: msg.isError });
		}
	}
	return items;
}

async function mapWithConcurrencyLimit<TIn, TOut>(
	items: TIn[],
	concurrency: number,
	fn: (item: TIn, index: number) => Promise<TOut>,
): Promise<TOut[]> {
	if (items.length === 0) return [];
	const limit = Math.max(1, Math.min(concurrency, items.length));
	const results: TOut[] = new Array(items.length);
	let nextIndex = 0;
	const workers = new Array(limit).fill(null).map(async () => {
		while (true) {
			const current = nextIndex++;
			if (current >= items.length) return;
			results[current] = await fn(items[current], current);
		}
	});
	await Promise.all(workers);
	return results;
}

async function writePromptToTempFile(agentName: string, prompt: string): Promise<{ dir: string; filePath: string }> {
	const tmpDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "pi-subagent-"));
	const safeName = agentName.replace(/[^\w.-]+/g, "_");
	const filePath = path.join(tmpDir, `prompt-${safeName}.md`);
	await withFileMutationQueue(filePath, async () => {
		await fs.promises.writeFile(filePath, prompt, { encoding: "utf-8", mode: 0o600 });
	});
	return { dir: tmpDir, filePath };
}

function getPiInvocation(args: string[]): { command: string; args: string[] } {
	const currentScript = process.argv[1];
	const isBunVirtualScript = currentScript?.startsWith("/$bunfs/root/");
	if (currentScript && !isBunVirtualScript && fs.existsSync(currentScript)) {
		return { command: process.execPath, args: [currentScript, ...args] };
	}

	const execName = path.basename(process.execPath).toLowerCase();
	const isGenericRuntime = /^(node|bun)(\.exe)?$/.test(execName);
	if (!isGenericRuntime) {
		return { command: process.execPath, args };
	}

	return { command: "pi", args };
}

type OnUpdateCallback = (partial: AgentToolResult<SubagentDetails>) => void;

interface DispatchDefaults {
	model?: string;
	thinkingLevel?: ThinkingLevel;
	parentSessionFile?: string;
	/** Parent UI, used to answer extension dialogs (confirm/select/...) raised inside the subagent */
	ui?: any;
}

// Survives extension runtime replacement on session switch (module may be re-imported).
const pendingSwitch: { value?: { file: string; provider: string; model: string } } = ((
	globalThis as any
).__piSubagentPendingSwitch ??= {});

// ---------------------------------------------------------------------------
// Live run registry: lets /subagents show running subagents in an overlay
// ---------------------------------------------------------------------------

interface PartialPart {
	kind: "thinking" | "text" | "toolCall";
	text: string;
	name?: string;
}

interface LiveRun {
	id: number;
	result: SingleResult;
	startedAt: number;
	endedAt?: number;
	done: boolean;
	/** Streaming content of the in-progress assistant message, keyed by content index */
	partial: Map<number, PartialPart>;
	runningTool?: { name: string; args: Record<string, unknown> };
	listeners: Set<() => void>;
	/** Handle for steering the subagent process (RPC mode) */
	control?: RunControl;
}

interface RunControl {
	/** Agent is working (between agent_start and agent_settled) */
	streaming: boolean;
	/** Keep the subagent alive after it settles so the user can keep talking to it */
	held: boolean;
	/** Process has exited; no more input possible */
	exited: boolean;
	queue: { steering: string[]; followUp: string[] };
	/** Steer / queue a follow-up while working, or start a new turn when idle. Takes control (holds). */
	send(message: string, mode: "steer" | "followUp"): boolean;
	/** Abort the current turn. Takes control (holds). */
	abort(): boolean;
	/** Releasing a settled run hands its result back to the parent agent. */
	setHeld(held: boolean): void;
}

const MAX_LIVE_RUNS = 30;
const liveState: { runs: LiveRun[]; nextId: number } = ((globalThis as any).__piSubagentLive ??= {
	runs: [],
	nextId: 1,
});

function registerLiveRun(result: SingleResult): LiveRun {
	const run: LiveRun = {
		id: liveState.nextId++,
		result,
		startedAt: Date.now(),
		done: false,
		partial: new Map(),
		listeners: new Set(),
	};
	liveState.runs.push(run);
	while (liveState.runs.length > MAX_LIVE_RUNS) {
		const idx = liveState.runs.findIndex((r) => r.done);
		if (idx === -1) break;
		liveState.runs.splice(idx, 1);
	}
	return run;
}

function notifyLive(run: LiveRun) {
	for (const l of run.listeners) {
		try {
			l();
		} catch {
			/* ignore */
		}
	}
}

function formatDuration(ms: number): string {
	const s = Math.floor(ms / 1000);
	return s < 60 ? `${s}s` : `${Math.floor(s / 60)}m${String(s % 60).padStart(2, "0")}s`;
}

/**
 * Overlay that follows a (running or finished) subagent live and lets the user take control of it:
 * steer it, queue follow-ups, abort the current turn, and keep it alive (hold) to keep chatting
 * before its result is handed back to the parent agent.
 */
class LiveRunViewer implements Component {
	focused = false;
	private typing = false;
	private flash?: string;
	private readonly input: Input;
	private scroll = 0;
	private follow = true;
	private viewH = 10;
	private bodyLen = 0;
	private cache?: { width: number; count: number; lines: string[] };
	private readonly listener = () => this.tui.requestRender();
	private timer?: ReturnType<typeof setInterval>;

	constructor(
		private tui: TUI,
		private theme: Theme,
		private run: LiveRun,
		private close: () => void,
	) {
		run.listeners.add(this.listener);
		// Tick the elapsed-time display while running
		if (!run.done) this.timer = setInterval(() => this.tui.requestRender(), 1000);
		this.input = new Input({ prompt: theme.fg("accent", "\u203a ") });
	}

	private get control(): RunControl | undefined {
		const c = this.run.control;
		return c && !c.exited && !this.run.done ? c : undefined;
	}

	private submit(mode: "steer" | "followUp") {
		const text = this.input.getValue().trim();
		if (!text) return;
		const c = this.control;
		if (!c) {
			this.flash = "Subagent has finished \u2014 switch into its session with /subagents when idle";
			return;
		}
		const verb = !c.streaming ? "sent" : mode === "followUp" ? "queued as follow-up" : "queued as steering";
		if (c.send(text, mode)) {
			this.input.setValue("");
			this.follow = true;
			this.flash = `Message ${verb} \u00b7 holding session (Esc to hand back when done)`;
		}
	}

	private renderText(text: string, width: number): string[] {
		return new Text(text, 0, 0).render(width);
	}

	/** Markdown styled like pi's own transcript (thinking: thinkingText + italic). */
	private renderMd(text: string, width: number, thinking = false): string[] {
		const th = this.theme;
		const style = thinking ? { color: (t: string) => th.fg("thinkingText", t), italic: true } : undefined;
		return new Markdown(text, 0, 0, getMarkdownTheme(), style).render(width);
	}

	private finalizedLines(width: number): string[] {
		const msgs = this.run.result.messages;
		if (this.cache && this.cache.width === width && this.cache.count === msgs.length) return this.cache.lines;
		const th = this.theme;
		const mdTheme = getMarkdownTheme();
		const lines: string[] = [];
		for (const item of getDisplayItems(msgs)) {
			if (item.type === "user") {
				lines.push("", ...this.renderText(th.fg("accent", "\u203a you: ") + item.text.trim(), width), "");
			} else if (item.type === "thinking") {
				lines.push(...this.renderMd(item.text.trim(), width, true));
			} else if (item.type === "text") {
				if (!item.text.trim()) continue;
				lines.push("", ...new Markdown(item.text.trim(), 0, 0, mdTheme).render(width), "");
			} else if (item.type === "toolCall") {
				lines.push(
					...this.renderText(
						th.fg("muted", "\u2192 ") + formatToolCall(item.name, item.args, th.fg.bind(th), true),
						width,
					),
				);
			} else if (item.type === "toolResult") {
				const out = item.text.replace(/\s+$/, "").split("\n");
				if (out.length === 1 && !out[0]) continue;
				const max = 30;
				const color = item.isError ? "error" : "toolOutput";
				for (const l of out.slice(0, max)) lines.push(...this.renderText(th.fg(color, `  ${l}`), width));
				if (out.length > max) lines.push(th.fg("muted", `  \u2026 ${out.length - max} more lines`));
			}
		}
		this.cache = { width, count: msgs.length, lines };
		return lines;
	}

	private bodyLines(width: number): string[] {
		const th = this.theme;
		const lines = [...this.finalizedLines(width)];
		const sorted = [...this.run.partial.entries()].sort((a, b) => a[0] - b[0]).map(([, p]) => p);
		// Hide empty parts except the last (actively streaming) one; only the last part shows a cursor
		const parts = sorted.filter((p, i) => p.text.trim() || p.kind === "toolCall" || i === sorted.length - 1);
		for (const [i, p] of parts.entries()) {
			const cursor = i === parts.length - 1 ? th.fg("accent", "\u258d") : "";
			if (p.kind === "thinking" || p.kind === "text") {
				const md = this.renderMd(p.text, width, p.kind === "thinking");
				if (md.length === 0) md.push("");
				if (cursor) md[md.length - 1] += cursor;
				if (p.kind === "text") lines.push("");
				lines.push(...md);
			}
			else {
				const args = p.text.length > 300 ? `${p.text.slice(0, 300)}\u2026` : p.text;
				lines.push(...this.renderText(`${th.fg("muted", "\u2192 ")}${th.fg("accent", p.name ?? "tool")} ${th.fg("dim", args)}${cursor}`, width));
			}
		}
		if (this.run.runningTool) {
			const t = this.run.runningTool;
			lines.push(
				...this.renderText(
					th.fg("warning", "\u23f3 ") + formatToolCall(t.name, t.args, th.fg.bind(th), true),
					width,
				),
			);
		}
		const c = this.control;
		if (c && !c.streaming) {
			lines.push("", th.fg("accent", "\u23f8 Subagent is idle and held \u2014 type a message, or Esc to hand its result back"));
		} else if (!this.run.done && parts.length === 0 && !this.run.runningTool) {
			lines.push(th.fg("muted", "\u2026 waiting for model"));
		}
		if (c) {
			for (const s of c.queue.steering) lines.push(...this.renderText(th.fg("dim", `\u21b3 steer (pending): ${s}`), width));
			for (const s of c.queue.followUp)
				lines.push(...this.renderText(th.fg("dim", `\u21b3 follow-up (pending): ${s}`), width));
		}
		return lines;
	}

	render(width: number): string[] {
		const th = this.theme;
		const innerW = Math.max(10, width - 2);
		const height = Math.max(10, Math.floor(this.tui.terminal.rows * 0.9) - 1);
		const r = this.run.result;

		const c = this.control;
		if (!c) this.typing = false;
		const status = this.run.done
			? isFailedResult(r)
				? th.fg("error", "\u2717 failed")
				: th.fg("success", "\u2713 done")
			: c && !c.streaming
				? th.fg("accent", "\u23f8 idle")
				: th.fg("warning", "\u23f3 running");
		const held = c?.held ? th.fg("accent", " \u00b7 held by you") : "";
		const elapsed = formatDuration((this.run.endedAt ?? Date.now()) - this.run.startedAt);
		const usage = formatUsageStats(r.usage);
		const header: string[] = [
			` ${status}${held} ${th.fg("muted", elapsed)}  ${th.fg("dim", usage)}`,
			...new Text(th.fg("dim", `Task: ${r.task.replace(/\s+/g, " ").trim()}`), 1, 0).render(innerW).slice(0, 2),
			th.fg("border", "\u2500".repeat(innerW)),
		];
		const following = this.follow ? " \u00b7 following" : "";
		let hint: string;
		if (this.typing) {
			hint = c?.streaming
				? " Enter steer \u00b7 Alt+Enter follow-up \u00b7 PgUp/PgDn scroll \u00b7 Esc stop typing"
				: " Enter send \u00b7 PgUp/PgDn scroll \u00b7 Esc stop typing";
		} else if (c) {
			const close = c.held ? "Esc/q close & hand back" : "Esc/q close";
			hint = ` i type \u00b7 x abort turn \u00b7 h ${c.held ? "release" : "hold"} \u00b7 \u2191\u2193/jk \u00b7 ^U/^D \u00b7 g/G \u00b7 ${close}${following}`;
		} else {
			hint = ` \u2191\u2193/jk \u00b7 ^U/^D half page \u00b7 PgUp/PgDn \u00b7 g/G top/bottom \u00b7 Esc/q close${following}`;
		}
		const footer = [th.fg("border", "\u2500".repeat(innerW))];
		if (this.flash) footer.push(th.fg("warning", ` ${this.flash}`));
		if (c) {
			if (this.typing) {
				this.input.focused = this.focused;
				footer.push(this.input.render(innerW)[0] ?? "");
			} else {
				const draft = this.input.getValue();
				footer.push(
					th.fg("accent", "\u203a ") +
						th.fg("dim", draft ? draft : "press i to message this subagent"),
				);
			}
		}
		footer.push(th.fg("muted", hint));

		const body = this.bodyLines(innerW);
		this.bodyLen = body.length;
		this.viewH = Math.max(3, height - 2 - header.length - footer.length);
		const maxScroll = Math.max(0, body.length - this.viewH);
		if (this.follow) this.scroll = maxScroll;
		this.scroll = Math.min(Math.max(0, this.scroll), maxScroll);
		const visible = body.slice(this.scroll, this.scroll + this.viewH);
		while (visible.length < this.viewH) visible.push("");

		const title = ` ${r.agent}${r.step ? ` (step ${r.step})` : ""} \u00b7 ${r.model ?? "?"} `;
		const titleStr = truncateToWidth(title, innerW);
		const fill = Math.max(0, innerW - visibleWidth(titleStr));
		const out: string[] = [
			th.fg("border", "\u256d\u2500") + th.fg("accent", titleStr) + th.fg("border", `${"\u2500".repeat(Math.max(0, fill - 1))}\u256e`),
		];
		const pos = body.length > this.viewH ? ` ${this.scroll + 1}-${this.scroll + visible.length}/${body.length}` : "";
		footer[footer.length - 1] += th.fg("dim", pos);
		for (const line of [...header, ...visible, ...footer]) {
			out.push(th.fg("border", "\u2502") + truncateToWidth(line, innerW, "\u2026", true) + th.fg("border", "\u2502"));
		}
		out.push(th.fg("border", `\u2570${"\u2500".repeat(innerW)}\u256f`));
		return out;
	}

	handleInput(data: string): void {
		const maxScroll = Math.max(0, this.bodyLen - this.viewH);
		const move = (delta: number) => {
			this.scroll = Math.min(Math.max(0, this.scroll + delta), maxScroll);
			this.follow = this.scroll >= maxScroll;
		};
		const c = this.control;
		this.flash = undefined;

		if (this.typing) {
			if (matchesKey(data, "escape")) this.typing = false;
			else if (matchesKey(data, "alt+enter")) this.submit("followUp");
			else if (matchesKey(data, "enter")) this.submit("steer");
			else if (matchesKey(data, Key.pageUp)) move(-(this.viewH - 1));
			else if (matchesKey(data, Key.pageDown)) move(this.viewH - 1);
			else if (matchesKey(data, "ctrl+c")) {
				if (this.input.getValue()) this.input.setValue("");
				else this.typing = false;
			} else this.input.handleInput(data);
			this.tui.requestRender();
			return;
		}

		if (matchesKey(data, Key.escape) || data === "q" || matchesKey(data, "ctrl+c")) {
			// Leaving the viewer hands control back: a held, idle subagent returns its result to the parent.
			if (c?.held) c.setHeld(false);
			this.dispose();
			this.close();
			return;
		}
		if (data === "i" || data === "a" || matchesKey(data, "enter") || matchesKey(data, "tab")) {
			if (c) {
				this.typing = true;
				this.follow = true;
			} else this.flash = "Subagent has finished \u2014 switch into its session with /subagents when idle";
		} else if (data === "x") {
			if (c?.abort()) this.flash = "Abort sent \u00b7 holding session \u2014 type to redirect it, Esc to hand back";
			else this.flash = c ? "Nothing to abort (subagent is idle)" : "Subagent has finished";
		} else if (data === "h") {
			if (c) {
				c.setHeld(!c.held);
				this.flash = c.held
					? "Holding: the subagent will wait for you after it finishes"
					: "Released: the result goes back to the parent once the subagent finishes";
			} else this.flash = "Subagent has finished";
		} else if (matchesKey(data, Key.up) || data === "k") move(-1);
		else if (matchesKey(data, Key.down) || data === "j") move(1);
		else if (matchesKey(data, "ctrl+u")) move(-Math.max(1, Math.floor(this.viewH / 2)));
		else if (matchesKey(data, "ctrl+d")) move(Math.max(1, Math.floor(this.viewH / 2)));
		else if (matchesKey(data, Key.pageUp) || matchesKey(data, "ctrl+b") || data === "b") move(-(this.viewH - 1));
		else if (matchesKey(data, Key.pageDown) || matchesKey(data, "ctrl+f") || data === " ") move(this.viewH - 1);
		else if (matchesKey(data, Key.home) || data === "g") {
			this.scroll = 0;
			this.follow = maxScroll === 0;
		} else if (matchesKey(data, Key.end) || data === "G") {
			this.follow = true;
		} else return;
		this.tui.requestRender();
	}

	invalidate(): void {
		this.cache = undefined;
	}

	dispose(): void {
		this.run.listeners.delete(this.listener);
		if (this.timer) clearInterval(this.timer);
		this.timer = undefined;
	}
}

async function showLiveViewer(ctx: any): Promise<void> {
	if (!ctx.hasUI || ctx.mode !== "tui") {
		ctx.ui?.notify?.("The live subagent viewer requires the interactive TUI.", "warning");
		return;
	}
	// Running first (newest first), then recently finished
	const runs = [...liveState.runs].reverse().sort((a, b) => Number(a.done) - Number(b.done));
	if (runs.length === 0) {
		ctx.ui.notify("No subagents have run in this pi process yet.", "info");
		return;
	}

	let run: LiveRun | undefined;
	const running = runs.filter((r) => !r.done);
	if (running.length === 1) {
		run = running[0];
	} else {
		const options = runs.map((lr, i) => {
			const r = lr.result;
			const icon = !lr.done
				? lr.control && !lr.control.streaming
					? "\u23f8"
					: "\u23f3"
				: isFailedResult(r)
					? "\u2717"
					: "\u2713";
			const model = r.model ? r.model.split("/").pop() : "?";
			const task = r.task.replace(/\s+/g, " ").trim();
			const preview = task.length > 70 ? `${task.slice(0, 70)}\u2026` : task;
			const step = r.step ? ` (step ${r.step})` : "";
			return `${i + 1}. ${icon} ${r.agent}${step} \u00b7 ${model} \u00b7 ${preview}`;
		});
		const choice = await ctx.ui.select("Subagents \u2014 live view & control", options);
		if (choice === undefined) return;
		run = runs[options.indexOf(choice)];
	}
	if (!run) return;

	const selected = run;
	await ctx.ui.custom(
		(tui: TUI, theme: Theme, _kb: unknown, done: (v: undefined) => void) =>
			new LiveRunViewer(tui, theme, selected, () => done(undefined)),
		{
			overlay: true,
			overlayOptions: { anchor: "center", width: "92%", maxHeight: "90%" },
		},
	);
}

/** Provider/model of the last assistant message in a session file (used to restore the model on switch). */
function lastAssistantModel(sessionFile: string): { provider: string; model: string } | undefined {
	try {
		const lines = fs.readFileSync(sessionFile, "utf-8").split("\n");
		for (let i = lines.length - 1; i >= 0; i--) {
			if (!lines[i].includes('"assistant"')) continue;
			const e = JSON.parse(lines[i]);
			const m = e?.type === "message" ? e.message : undefined;
			if (m?.role === "assistant" && m.provider && m.model) return { provider: m.provider, model: m.model };
		}
	} catch {
		/* ignore */
	}
	return undefined;
}

/** Record the dispatching session in the subagent session header so /subagents can navigate back. */
function linkParentSession(sessionFile: string, parentSessionFile: string | undefined) {
	if (!parentSessionFile) return;
	try {
		const content = fs.readFileSync(sessionFile, "utf-8");
		const nl = content.indexOf("\n");
		const header = JSON.parse(nl === -1 ? content : content.slice(0, nl));
		if (header.type !== "session" || header.parentSession) return;
		header.parentSession = parentSessionFile;
		fs.writeFileSync(sessionFile, JSON.stringify(header) + (nl === -1 ? "\n" : content.slice(nl)));
	} catch {
		/* ignore */
	}
}

async function runSingleAgent(
	defaultCwd: string,
	dispatchDefaults: DispatchDefaults,
	agents: AgentConfig[],
	agentName: string,
	task: string,
	cwd: string | undefined,
	step: number | undefined,
	signal: AbortSignal | undefined,
	onUpdate: OnUpdateCallback | undefined,
	makeDetails: (results: SingleResult[]) => SubagentDetails,
): Promise<SingleResult> {
	const agent = agents.find((a) => a.name === agentName);

	if (!agent) {
		const available = agents.map((a) => `"${a.name}"`).join(", ") || "none";
		return {
			agent: agentName,
			agentSource: "unknown",
			task,
			exitCode: 1,
			messages: [],
			stderr: `Unknown agent: "${agentName}". Available agents: ${available}.`,
			usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, contextTokens: 0, turns: 0 },
			step,
		};
	}

	fs.mkdirSync(SUBAGENT_SESSION_DIR, { recursive: true });
	// RPC mode keeps the subagent controllable over stdin (steer / follow-up / abort) from the live viewer.
	const args: string[] = ["--mode", "rpc", "--session-dir", SUBAGENT_SESSION_DIR];
	const inheritsDispatchConfig = !agent.model;
	const model = agent.model ?? dispatchDefaults.model;
	if (model) args.push("--model", model);
	if (inheritsDispatchConfig && dispatchDefaults.thinkingLevel) {
		args.push("--thinking", dispatchDefaults.thinkingLevel);
	}
	if (agent.tools && agent.tools.length > 0) args.push("--tools", agent.tools.join(","));

	let tmpPromptDir: string | null = null;
	let tmpPromptPath: string | null = null;

	const currentResult: SingleResult = {
		agent: agentName,
		agentSource: agent.source,
		task,
		exitCode: 0,
		messages: [],
		stderr: "",
		usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, contextTokens: 0, turns: 0 },
		model,
		step,
	};

	const live = registerLiveRun(currentResult);

	const emitUpdate = () => {
		notifyLive(live);
		if (onUpdate) {
			onUpdate({
				content: [{ type: "text", text: getFinalOutput(currentResult.messages) || "(running...)" }],
				details: makeDetails([currentResult]),
			});
		}
	};

	try {
		if (agent.systemPrompt.trim()) {
			const tmp = await writePromptToTempFile(agent.name, agent.systemPrompt);
			tmpPromptDir = tmp.dir;
			tmpPromptPath = tmp.filePath;
			args.push("--append-system-prompt", tmpPromptPath);
		}

		let wasAborted = false;

		const exitCode = await new Promise<number>((resolve) => {
			const invocation = getPiInvocation(args);
			const proc = spawn(invocation.command, invocation.args, {
				cwd: cwd ?? defaultCwd,
				shell: false,
				stdio: ["pipe", "pipe", "pipe"],
			});
			let buffer = "";
			let settled = false;
			let stdinClosed = false;
			let reportedSessionFile: string | undefined;

			const write = (cmd: Record<string, unknown>): boolean => {
				if (stdinClosed || !proc.stdin.writable) return false;
				proc.stdin.write(`${JSON.stringify(cmd)}\n`);
				return true;
			};
			/** Closing stdin asks pi for an orderly shutdown; the result is returned when the process exits. */
			const endInput = () => {
				if (stdinClosed) return;
				stdinClosed = true;
				proc.stdin.end();
			};
			proc.stdin.on("error", () => {
				stdinClosed = true;
			});

			const control: RunControl = {
				streaming: true,
				held: false,
				exited: false,
				queue: { steering: [], followUp: [] },
				send(message, mode) {
					if (stdinClosed) return false;
					control.held = true;
					(currentResult.interventions ??= []).push(message);
					if (control.streaming) {
						write({ type: mode === "followUp" ? "follow_up" : "steer", message });
					} else {
						settled = false;
						control.streaming = true;
						write({ type: "prompt", message });
					}
					notifyLive(live);
					return true;
				},
				abort() {
					if (stdinClosed || !control.streaming) return false;
					control.held = true;
					write({ type: "abort" });
					notifyLive(live);
					return true;
				},
				setHeld(held) {
					control.held = held;
					maybeFinish();
					notifyLive(live);
				},
			};
			live.control = control;

			const maybeFinish = () => {
				if (settled && !control.held) endInput();
			};

			const toTexts = (v: unknown): string[] =>
				Array.isArray(v) ? v.map((x: any) => (typeof x === "string" ? x : (x?.text ?? JSON.stringify(x)))) : [];

			/** Forward blocking extension dialogs raised inside the subagent to the parent UI (or cancel them). */
			const handleUiRequest = async (req: any) => {
				if (!["select", "confirm", "input", "editor"].includes(req.method)) return; // fire-and-forget
				const respond = (payload: Record<string, unknown>) =>
					write({ type: "extension_ui_response", id: req.id, ...payload });
				const ui = dispatchDefaults.ui;
				if (!ui) return respond({ cancelled: true });
				const title = `[subagent ${agentName}] ${req.title ?? ""}`;
				const opts = req.timeout ? { timeout: req.timeout } : undefined;
				try {
					if (req.method === "confirm") {
						respond({ confirmed: Boolean(await ui.confirm(title, req.message ?? "", opts)) });
						return;
					}
					let value: string | undefined;
					if (req.method === "select") value = await ui.select(title, req.options ?? [], opts);
					else if (req.method === "input") value = await ui.input(title, req.placeholder);
					else value = await ui.editor(title, req.prefill);
					respond(value === undefined ? { cancelled: true } : { value });
				} catch {
					respond({ cancelled: true });
				}
			};

			const processLine = (line: string) => {
				if (!line.trim()) return;
				let event: any;
				try {
					event = JSON.parse(line);
				} catch {
					return;
				}

				// RPC protocol records
				if (event.type === "response") {
					if (event.id === "state" && event.success) {
						currentResult.sessionId = event.data?.sessionId;
						reportedSessionFile = event.data?.sessionFile;
					} else if (event.command === "prompt" && !event.success) {
						currentResult.stopReason = "error";
						currentResult.errorMessage = event.error ?? "Prompt rejected by subagent";
						settled = true;
						control.streaming = false;
						emitUpdate();
						maybeFinish();
					}
					return;
				}
				if (event.type === "extension_ui_request") {
					void handleUiRequest(event);
					return;
				}
				if (event.type === "extension_error") {
					currentResult.stderr += `[extension ${event.extensionPath}] ${event.event}: ${event.error}\n`;
					return;
				}
				if (event.type === "agent_start") {
					control.streaming = true;
					settled = false;
					return;
				}
				if (event.type === "agent_settled") {
					control.streaming = false;
					settled = true;
					live.partial.clear();
					live.runningTool = undefined;
					notifyLive(live);
					maybeFinish();
					return;
				}
				if (event.type === "queue_update") {
					control.queue = { steering: toTexts(event.steering), followUp: toTexts(event.followUp) };
					notifyLive(live);
					return;
				}

				// Live streaming state for the /subagents overlay
				if (event.type === "message_start" && event.message?.role === "assistant") {
					live.partial.clear();
				} else if (event.type === "message_update" && event.assistantMessageEvent) {
					const a = event.assistantMessageEvent;
					const idx = a.contentIndex ?? 0;
					if (a.type === "thinking_start") live.partial.set(idx, { kind: "thinking", text: "" });
					else if (a.type === "text_start") live.partial.set(idx, { kind: "text", text: "" });
					else if (a.type === "toolcall_start")
						live.partial.set(idx, { kind: "toolCall", text: "", name: a.toolName });
					else if (a.type === "thinking_delta" || a.type === "text_delta" || a.type === "toolcall_delta") {
						const p = live.partial.get(idx);
						if (p) p.text += a.delta ?? "";
					}
					if (live.listeners.size) notifyLive(live);
				} else if (event.type === "tool_execution_start") {
					live.runningTool = { name: event.toolName, args: event.args ?? {} };
					notifyLive(live);
				} else if (event.type === "tool_execution_end") {
					live.runningTool = undefined;
				}

				if (event.type === "message_end" && event.message) {
					const msg = event.message as Message;
					if (msg.role === "assistant") live.partial.clear();
					currentResult.messages.push(msg);

					if (msg.role === "assistant") {
						currentResult.usage.turns++;
						const usage = msg.usage;
						if (usage) {
							currentResult.usage.input += usage.input || 0;
							currentResult.usage.output += usage.output || 0;
							currentResult.usage.cacheRead += usage.cacheRead || 0;
							currentResult.usage.cacheWrite += usage.cacheWrite || 0;
							currentResult.usage.cost += usage.cost?.total || 0;
							currentResult.usage.contextTokens = usage.totalTokens || 0;
						}
						if (!currentResult.model && msg.model) currentResult.model = msg.model;
						if (msg.stopReason) currentResult.stopReason = msg.stopReason;
						// Cleared on success so a user-steered recovery doesn't keep a stale error
						currentResult.errorMessage = msg.errorMessage;
					}
					emitUpdate();
				}
			};

			proc.stdout.on("data", (data) => {
				buffer += data.toString();
				const lines = buffer.split("\n");
				buffer = lines.pop() || "";
				for (const line of lines) processLine(line);
			});

			proc.stderr.on("data", (data) => {
				currentResult.stderr += data.toString();
			});

			proc.on("close", (code) => {
				if (buffer.trim()) processLine(buffer);
				control.exited = true;
				stdinClosed = true;
				let file = reportedSessionFile && fs.existsSync(reportedSessionFile) ? reportedSessionFile : undefined;
				if (!file && currentResult.sessionId) {
					try {
						const f = fs
							.readdirSync(SUBAGENT_SESSION_DIR)
							.find((n) => n.endsWith(`_${currentResult.sessionId}.jsonl`));
						if (f) file = path.join(SUBAGENT_SESSION_DIR, f);
					} catch {
						/* ignore */
					}
				}
				if (file) {
					currentResult.sessionFile = file;
					linkParentSession(file, dispatchDefaults.parentSessionFile);
				}
				resolve(code ?? 0);
			});

			proc.on("error", (err) => {
				control.exited = true;
				stdinClosed = true;
				currentResult.stderr += String(err);
				resolve(1);
			});

			// Kick off: learn the session file, then send the task.
			write({ id: "state", type: "get_state" });
			write({ id: "task", type: "prompt", message: `Task: ${task}` });

			if (signal) {
				const killProc = () => {
					wasAborted = true;
					endInput();
					proc.kill("SIGTERM");
					setTimeout(() => {
						if (proc.exitCode === null && proc.signalCode === null) proc.kill("SIGKILL");
					}, 5000);
				};
				if (signal.aborted) killProc();
				else signal.addEventListener("abort", killProc, { once: true });
			}
		});

		currentResult.exitCode = exitCode;
		if (wasAborted) throw new Error("Subagent was aborted");
		return currentResult;
	} finally {
		live.done = true;
		live.endedAt = Date.now();
		live.partial.clear();
		live.runningTool = undefined;
		notifyLive(live);
		if (tmpPromptPath)
			try {
				fs.unlinkSync(tmpPromptPath);
			} catch {
				/* ignore */
			}
		if (tmpPromptDir)
			try {
				fs.rmdirSync(tmpPromptDir);
			} catch {
				/* ignore */
			}
	}
}

const TaskItem = Type.Object({
	agent: Type.String({ description: "Name of the agent to invoke" }),
	task: Type.String({ description: "Task to delegate to the agent" }),
	cwd: Type.Optional(Type.String({ description: "Working directory for the agent process" })),
});

const ChainItem = Type.Object({
	agent: Type.String({ description: "Name of the agent to invoke" }),
	task: Type.String({ description: "Task with optional {previous} placeholder for prior output" }),
	cwd: Type.Optional(Type.String({ description: "Working directory for the agent process" })),
});

const AgentScopeSchema = StringEnum(["user", "project", "both"] as const, {
	description: 'Which agent directories to use. Default: "user". Use "both" to include project-local agents.',
	default: "user",
});

const SubagentParams = Type.Object({
	agent: Type.Optional(Type.String({ description: "Name of the agent to invoke (for single mode)" })),
	task: Type.Optional(Type.String({ description: "Task to delegate (for single mode)" })),
	tasks: Type.Optional(Type.Array(TaskItem, { description: "Array of {agent, task} for parallel execution" })),
	chain: Type.Optional(Type.Array(ChainItem, { description: "Array of {agent, task} for sequential execution" })),
	agentScope: Type.Optional(AgentScopeSchema),
	confirmProjectAgents: Type.Optional(
		Type.Boolean({ description: "Prompt before running project-local agents. Default: true.", default: true }),
	),
	cwd: Type.Optional(Type.String({ description: "Working directory for the agent process (single mode)" })),
});

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "subagent",
		label: "Subagent",
		description: [
			"Delegate tasks to specialized subagents with isolated context.",
			"Modes: single (agent + task), parallel (tasks array), chain (sequential with {previous} placeholder).",
			`Default agent scope is "user" (from ${path.join(getAgentDir(), "agents")}).`,
			`To enable project-local agents in ${CONFIG_DIR_NAME}/agents, set agentScope: "both" (or "project").`,
		].join(" "),
		parameters: SubagentParams,

		async execute(_toolCallId, params, signal, onUpdate, ctx) {
			const agentScope: AgentScope = params.agentScope ?? "user";
			const dispatchDefaults: DispatchDefaults = {
				model: ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : undefined,
				thinkingLevel: ctx.thinkingLevel,
				parentSessionFile: ctx.sessionManager.getSessionFile() ?? undefined,
				ui: ctx.hasUI ? ctx.ui : undefined,
			};
			const discovery = discoverAgents(ctx.cwd, agentScope);
			const agents = discovery.agents;
			const confirmProjectAgents = params.confirmProjectAgents ?? true;

			const hasChain = (params.chain?.length ?? 0) > 0;
			const hasTasks = (params.tasks?.length ?? 0) > 0;
			const hasSingle = Boolean(params.agent && params.task);
			const modeCount = Number(hasChain) + Number(hasTasks) + Number(hasSingle);

			const makeDetails =
				(mode: "single" | "parallel" | "chain") =>
				(results: SingleResult[]): SubagentDetails => ({
					mode,
					agentScope,
					projectAgentsDir: discovery.projectAgentsDir,
					results,
				});

			if (modeCount !== 1) {
				const available = agents.map((a) => `${a.name} (${a.source})`).join(", ") || "none";
				return {
					content: [
						{
							type: "text",
							text: `Invalid parameters. Provide exactly one mode.\nAvailable agents: ${available}`,
						},
					],
					details: makeDetails("single")([]),
				};
			}

			if (
				(agentScope === "project" || agentScope === "both") &&
				confirmProjectAgents &&
				ctx.hasUI &&
				!ctx.isProjectTrusted()
			) {
				const requestedAgentNames = new Set<string>();
				if (params.chain) for (const step of params.chain) requestedAgentNames.add(step.agent);
				if (params.tasks) for (const t of params.tasks) requestedAgentNames.add(t.agent);
				if (params.agent) requestedAgentNames.add(params.agent);

				const projectAgentsRequested = Array.from(requestedAgentNames)
					.map((name) => agents.find((a) => a.name === name))
					.filter((a): a is AgentConfig => a?.source === "project");

				if (projectAgentsRequested.length > 0) {
					const names = projectAgentsRequested.map((a) => a.name).join(", ");
					const dir = discovery.projectAgentsDir ?? "(unknown)";
					const ok = await ctx.ui.confirm(
						"Run project-local agents?",
						`Agents: ${names}\nSource: ${dir}\n\nProject agents are repo-controlled. Only continue for trusted repositories.`,
					);
					if (!ok)
						return {
							content: [{ type: "text", text: "Canceled: project-local agents not approved." }],
							details: makeDetails(hasChain ? "chain" : hasTasks ? "parallel" : "single")([]),
						};
				}
			}

			if (params.chain && params.chain.length > 0) {
				const results: SingleResult[] = [];
				let previousOutput = "";

				for (let i = 0; i < params.chain.length; i++) {
					const step = params.chain[i];
					const taskWithContext = step.task.replace(/\{previous\}/g, previousOutput);

					// Create update callback that includes all previous results
					const chainUpdate: OnUpdateCallback | undefined = onUpdate
						? (partial) => {
								// Combine completed results with current streaming result
								const currentResult = partial.details?.results[0];
								if (currentResult) {
									const allResults = [...results, currentResult];
									onUpdate({
										content: partial.content,
										details: makeDetails("chain")(allResults),
									});
								}
							}
						: undefined;

					const result = await runSingleAgent(
						ctx.cwd,
						dispatchDefaults,
						agents,
						step.agent,
						taskWithContext,
						step.cwd,
						i + 1,
						signal,
						chainUpdate,
						makeDetails("chain"),
					);
					results.push(result);

					const isError = isFailedResult(result);
					if (isError) {
						const errorMsg = getResultOutput(result);
						return {
							content: [
							{
								type: "text",
								text: `Chain stopped at step ${i + 1} (${step.agent}): ${errorMsg}${sessionNote(results)}`,
							},
						],
							details: makeDetails("chain")(results),
							isError: true,
						};
					}
					previousOutput = getFinalOutput(result.messages);
				}
				return {
					content: [
						{
							type: "text",
							text: (getFinalOutput(results[results.length - 1].messages) || "(no output)") + sessionNote(results),
						},
					],
					details: makeDetails("chain")(results),
				};
			}

			if (params.tasks && params.tasks.length > 0) {
				if (params.tasks.length > MAX_PARALLEL_TASKS)
					return {
						content: [
							{
								type: "text",
								text: `Too many parallel tasks (${params.tasks.length}). Max is ${MAX_PARALLEL_TASKS}.`,
							},
						],
						details: makeDetails("parallel")([]),
					};

				// Track all results for streaming updates
				const allResults: SingleResult[] = new Array(params.tasks.length);

				// Initialize placeholder results
				for (let i = 0; i < params.tasks.length; i++) {
					allResults[i] = {
						agent: params.tasks[i].agent,
						agentSource: "unknown",
						task: params.tasks[i].task,
						exitCode: -1, // -1 = still running
						messages: [],
						stderr: "",
						usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, contextTokens: 0, turns: 0 },
					};
				}

				const emitParallelUpdate = () => {
					if (onUpdate) {
						const running = allResults.filter((r) => r.exitCode === -1).length;
						const done = allResults.filter((r) => r.exitCode !== -1).length;
						onUpdate({
							content: [
								{ type: "text", text: `Parallel: ${done}/${allResults.length} done, ${running} running...` },
							],
							details: makeDetails("parallel")([...allResults]),
						});
					}
				};

				const results = await mapWithConcurrencyLimit(params.tasks, MAX_CONCURRENCY, async (t, index) => {
					const result = await runSingleAgent(
						ctx.cwd,
						dispatchDefaults,
						agents,
						t.agent,
						t.task,
						t.cwd,
						undefined,
						signal,
						// Per-task update callback
						(partial) => {
							if (partial.details?.results[0]) {
								allResults[index] = partial.details.results[0];
								emitParallelUpdate();
							}
						},
						makeDetails("parallel"),
					);
					allResults[index] = result;
					emitParallelUpdate();
					return result;
				});

				const successCount = results.filter((r) => !isFailedResult(r)).length;
				const summaries = results.map((r) => {
					const output = truncateParallelOutput(getResultOutput(r));
					const status = isFailedResult(r)
						? `failed${r.stopReason && r.stopReason !== "end" ? ` (${r.stopReason})` : ""}`
						: "completed";
					return `### [${r.agent}] ${status}\n\n${output}`;
				});
				return {
					content: [
						{
							type: "text",
							text: `Parallel: ${successCount}/${results.length} succeeded\n\n${summaries.join("\n\n---\n\n")}${sessionNote(results)}`,
						},
					],
					details: makeDetails("parallel")(results),
				};
			}

			if (params.agent && params.task) {
				const result = await runSingleAgent(
					ctx.cwd,
					dispatchDefaults,
					agents,
					params.agent,
					params.task,
					params.cwd,
					undefined,
					signal,
					onUpdate,
					makeDetails("single"),
				);
				const isError = isFailedResult(result);
				if (isError) {
					const errorMsg = getResultOutput(result);
					return {
						content: [
							{ type: "text", text: `Agent ${result.stopReason || "failed"}: ${errorMsg}${sessionNote([result])}` },
						],
						details: makeDetails("single")([result]),
						isError: true,
					};
				}
				return {
					content: [
						{ type: "text", text: (getFinalOutput(result.messages) || "(no output)") + sessionNote([result]) },
					],
					details: makeDetails("single")([result]),
				};
			}

			const available = agents.map((a) => `${a.name} (${a.source})`).join(", ") || "none";
			return {
				content: [{ type: "text", text: `Invalid parameters. Available agents: ${available}` }],
				details: makeDetails("single")([]),
			};
		},

		renderCall(args, theme, _context) {
			const scope: AgentScope = args.agentScope ?? "user";
			if (args.chain && args.chain.length > 0) {
				let text =
					theme.fg("toolTitle", theme.bold("subagent ")) +
					theme.fg("accent", `chain (${args.chain.length} steps)`) +
					theme.fg("muted", ` [${scope}]`);
				for (let i = 0; i < Math.min(args.chain.length, 3); i++) {
					const step = args.chain[i];
					// Clean up {previous} placeholder for display
					const cleanTask = step.task.replace(/\{previous\}/g, "").trim();
					const preview = cleanTask.length > 40 ? `${cleanTask.slice(0, 40)}...` : cleanTask;
					text +=
						"\n  " +
						theme.fg("muted", `${i + 1}.`) +
						" " +
						theme.fg("accent", step.agent) +
						theme.fg("dim", ` ${preview}`);
				}
				if (args.chain.length > 3) text += `\n  ${theme.fg("muted", `... +${args.chain.length - 3} more`)}`;
				return new Text(text, 0, 0);
			}
			if (args.tasks && args.tasks.length > 0) {
				let text =
					theme.fg("toolTitle", theme.bold("subagent ")) +
					theme.fg("accent", `parallel (${args.tasks.length} tasks)`) +
					theme.fg("muted", ` [${scope}]`);
				for (const t of args.tasks.slice(0, 3)) {
					const preview = t.task.length > 40 ? `${t.task.slice(0, 40)}...` : t.task;
					text += `\n  ${theme.fg("accent", t.agent)}${theme.fg("dim", ` ${preview}`)}`;
				}
				if (args.tasks.length > 3) text += `\n  ${theme.fg("muted", `... +${args.tasks.length - 3} more`)}`;
				return new Text(text, 0, 0);
			}
			const agentName = args.agent || "...";
			const preview = args.task ? (args.task.length > 60 ? `${args.task.slice(0, 60)}...` : args.task) : "...";
			let text =
				theme.fg("toolTitle", theme.bold("subagent ")) +
				theme.fg("accent", agentName) +
				theme.fg("muted", ` [${scope}]`);
			text += `\n  ${theme.fg("dim", preview)}`;
			return new Text(text, 0, 0);
		},

		renderResult(result, { expanded }, theme, _context) {
			const details = result.details as SubagentDetails | undefined;
			if (!details || details.results.length === 0) {
				const text = result.content[0];
				return new Text(text?.type === "text" ? text.text : "(no output)", 0, 0);
			}

			const mdTheme = getMarkdownTheme();

			// Full timeline for expanded view: thinking, text, tool calls (untruncated), tool result previews
			const addTimeline = (container: Container, r: SingleResult) => {
				const items = getDisplayItems(r.messages);
				if (items.length === 0) {
					container.addChild(
						new Text(theme.fg("muted", r.exitCode === -1 ? "(running...)" : "(no output)"), 0, 0),
					);
				}
				for (const item of items) {
					if (item.type === "user") {
						container.addChild(new Text(theme.fg("accent", "\u203a you: ") + item.text.trim(), 0, 0));
					} else if (item.type === "thinking") {
						container.addChild(
							new Markdown(item.text.trim(), 0, 0, mdTheme, {
								color: (t: string) => theme.fg("thinkingText", t),
								italic: true,
							}),
						);
					} else if (item.type === "text") {
						if (!item.text.trim()) continue;
						container.addChild(new Spacer(1));
						container.addChild(new Markdown(item.text.trim(), 0, 0, mdTheme));
						container.addChild(new Spacer(1));
					} else if (item.type === "toolCall") {
						container.addChild(
							new Text(
								theme.fg("muted", "→ ") + formatToolCall(item.name, item.args, theme.fg.bind(theme), true),
								0,
								0,
							),
						);
					} else if (item.type === "toolResult") {
						const lines = item.text.replace(/\s+$/, "").split("\n");
						if (lines.length === 1 && !lines[0]) continue;
						const shown = lines.slice(0, RESULT_PREVIEW_LINES).map((l) => `  ${l}`);
						let t = theme.fg(item.isError ? "error" : "dim", shown.join("\n"));
						if (lines.length > RESULT_PREVIEW_LINES)
							t += `\n${theme.fg("muted", `  … ${lines.length - RESULT_PREVIEW_LINES} more lines (see session transcript)`)}`;
						container.addChild(new Text(t, 0, 0));
					}
				}
				if (r.sessionFile) {
					container.addChild(new Text(theme.fg("muted", `session: ${shortenHome(r.sessionFile)}`), 0, 0));
				}
			};

			const renderDisplayItems = (allItems: DisplayItem[], limit?: number) => {
				const items = allItems.filter((i) => i.type !== "toolResult");
				const toShow = limit ? items.slice(-limit) : items;
				const skipped = limit && items.length > limit ? items.length - limit : 0;
				let text = "";
				if (skipped > 0) text += theme.fg("muted", `... ${skipped} earlier items\n`);
				for (const item of toShow) {
					if (item.type === "user") {
						const firstLine = item.text.trim().split("\n")[0];
						text += `${theme.fg("accent", "\u203a you: ")}${theme.fg("toolOutput", firstLine)}\n`;
					} else if (item.type === "text") {
						const preview = expanded ? item.text : item.text.split("\n").slice(0, 3).join("\n");
						text += `${theme.fg("toolOutput", preview)}\n`;
					} else if (item.type === "thinking") {
						const firstLine = item.text.trim().split("\n")[0];
						const preview = firstLine.length > 100 ? `${firstLine.slice(0, 100)}…` : firstLine;
						text += `${theme.fg("thinkingText", `💭 ${preview}`)}\n`;
					} else if (item.type === "toolCall") {
						text += `${theme.fg("muted", "→ ") + formatToolCall(item.name, item.args, theme.fg.bind(theme))}\n`;
					}
				}
				return text.trimEnd();
			};

			if (details.mode === "single" && details.results.length === 1) {
				const r = details.results[0];
				const isError = isFailedResult(r);
				const icon = isError ? theme.fg("error", "✗") : theme.fg("success", "✓");
				const displayItems = getDisplayItems(r.messages);

				if (expanded) {
					const container = new Container();
					let header = `${icon} ${theme.fg("toolTitle", theme.bold(r.agent))}${theme.fg("muted", ` (${r.agentSource})`)}`;
					if (isError && r.stopReason) header += ` ${theme.fg("error", `[${r.stopReason}]`)}`;
					container.addChild(new Text(header, 0, 0));
					if (isError && r.errorMessage)
						container.addChild(new Text(theme.fg("error", `Error: ${r.errorMessage}`), 0, 0));
					container.addChild(new Spacer(1));
					container.addChild(new Text(theme.fg("muted", "─── Task ───"), 0, 0));
					container.addChild(new Text(theme.fg("dim", r.task), 0, 0));
					container.addChild(new Spacer(1));
					container.addChild(new Text(theme.fg("muted", "─── Output ───"), 0, 0));
					addTimeline(container, r);
					const usageStr = formatUsageStats(r.usage, r.model);
					if (usageStr) {
						container.addChild(new Spacer(1));
						container.addChild(new Text(theme.fg("dim", usageStr), 0, 0));
					}
					return container;
				}

				let text = `${icon} ${theme.fg("toolTitle", theme.bold(r.agent))}${theme.fg("muted", ` (${r.agentSource})`)}`;
				if (isError && r.stopReason) text += ` ${theme.fg("error", `[${r.stopReason}]`)}`;
				if (isError && r.errorMessage) text += `\n${theme.fg("error", `Error: ${r.errorMessage}`)}`;
				else if (displayItems.length === 0) text += `\n${theme.fg("muted", "(no output)")}`;
				else {
					text += `\n${renderDisplayItems(displayItems, COLLAPSED_ITEM_COUNT)}`;
					if (displayItems.length > COLLAPSED_ITEM_COUNT) text += `\n${theme.fg("muted", "(Ctrl+O to expand)")}`;
				}
				const usageStr = formatUsageStats(r.usage, r.model);
				if (usageStr) text += `\n${theme.fg("dim", usageStr)}`;
				return new Text(text, 0, 0);
			}

			const aggregateUsage = (results: SingleResult[]) => {
				const total = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, turns: 0 };
				for (const r of results) {
					total.input += r.usage.input;
					total.output += r.usage.output;
					total.cacheRead += r.usage.cacheRead;
					total.cacheWrite += r.usage.cacheWrite;
					total.cost += r.usage.cost;
					total.turns += r.usage.turns;
				}
				return total;
			};

			if (details.mode === "chain") {
				const successCount = details.results.filter((r) => r.exitCode === 0).length;
				const icon = successCount === details.results.length ? theme.fg("success", "✓") : theme.fg("error", "✗");

				if (expanded) {
					const container = new Container();
					container.addChild(
						new Text(
							icon +
								" " +
								theme.fg("toolTitle", theme.bold("chain ")) +
								theme.fg("accent", `${successCount}/${details.results.length} steps`),
							0,
							0,
						),
					);

					for (const r of details.results) {
						const rIcon = r.exitCode === 0 ? theme.fg("success", "✓") : theme.fg("error", "✗");
						container.addChild(new Spacer(1));
						container.addChild(
							new Text(
								`${theme.fg("muted", `─── Step ${r.step}: `) + theme.fg("accent", r.agent)} ${rIcon}`,
								0,
								0,
							),
						);
						container.addChild(new Text(theme.fg("muted", "Task: ") + theme.fg("dim", r.task), 0, 0));
						container.addChild(new Spacer(1));
						addTimeline(container, r);

						const stepUsage = formatUsageStats(r.usage, r.model);
						if (stepUsage) container.addChild(new Text(theme.fg("dim", stepUsage), 0, 0));
					}

					const usageStr = formatUsageStats(aggregateUsage(details.results));
					if (usageStr) {
						container.addChild(new Spacer(1));
						container.addChild(new Text(theme.fg("dim", `Total: ${usageStr}`), 0, 0));
					}
					return container;
				}

				// Collapsed view
				let text =
					icon +
					" " +
					theme.fg("toolTitle", theme.bold("chain ")) +
					theme.fg("accent", `${successCount}/${details.results.length} steps`);
				for (const r of details.results) {
					const rIcon = r.exitCode === 0 ? theme.fg("success", "✓") : theme.fg("error", "✗");
					const displayItems = getDisplayItems(r.messages);
					text += `\n\n${theme.fg("muted", `─── Step ${r.step}: `)}${theme.fg("accent", r.agent)} ${rIcon}`;
					if (displayItems.length === 0) text += `\n${theme.fg("muted", "(no output)")}`;
					else text += `\n${renderDisplayItems(displayItems, 5)}`;
				}
				const usageStr = formatUsageStats(aggregateUsage(details.results));
				if (usageStr) text += `\n\n${theme.fg("dim", `Total: ${usageStr}`)}`;
				text += `\n${theme.fg("muted", "(Ctrl+O to expand)")}`;
				return new Text(text, 0, 0);
			}

			if (details.mode === "parallel") {
				const running = details.results.filter((r) => r.exitCode === -1).length;
				const successCount = details.results.filter((r) => r.exitCode !== -1 && !isFailedResult(r)).length;
				const failCount = details.results.filter((r) => r.exitCode !== -1 && isFailedResult(r)).length;
				const isRunning = running > 0;
				const icon = isRunning
					? theme.fg("warning", "⏳")
					: failCount > 0
						? theme.fg("warning", "◐")
						: theme.fg("success", "✓");
				const status = isRunning
					? `${successCount + failCount}/${details.results.length} done, ${running} running`
					: `${successCount}/${details.results.length} tasks`;

				if (expanded) {
					const container = new Container();
					container.addChild(
						new Text(
							`${icon} ${theme.fg("toolTitle", theme.bold("parallel "))}${theme.fg("accent", status)}`,
							0,
							0,
						),
					);

					for (const r of details.results) {
						const rIcon = isFailedResult(r) ? theme.fg("error", "✗") : theme.fg("success", "✓");
						container.addChild(new Spacer(1));
						container.addChild(
							new Text(`${theme.fg("muted", "─── ") + theme.fg("accent", r.agent)} ${rIcon}`, 0, 0),
						);
						container.addChild(new Text(theme.fg("muted", "Task: ") + theme.fg("dim", r.task), 0, 0));
						container.addChild(new Spacer(1));
						addTimeline(container, r);

						const taskUsage = formatUsageStats(r.usage, r.model);
						if (taskUsage) container.addChild(new Text(theme.fg("dim", taskUsage), 0, 0));
					}

					const usageStr = formatUsageStats(aggregateUsage(details.results));
					if (usageStr) {
						container.addChild(new Spacer(1));
						container.addChild(new Text(theme.fg("dim", `Total: ${usageStr}`), 0, 0));
					}
					return container;
				}

				// Collapsed view (or still running)
				let text = `${icon} ${theme.fg("toolTitle", theme.bold("parallel "))}${theme.fg("accent", status)}`;
				for (const r of details.results) {
					const rIcon =
						r.exitCode === -1
							? theme.fg("warning", "⏳")
							: isFailedResult(r)
								? theme.fg("error", "✗")
								: theme.fg("success", "✓");
					const displayItems = getDisplayItems(r.messages);
					text += `\n\n${theme.fg("muted", "─── ")}${theme.fg("accent", r.agent)} ${rIcon}`;
					if (displayItems.length === 0)
						text += `\n${theme.fg("muted", r.exitCode === -1 ? "(running...)" : "(no output)")}`;
					else text += `\n${renderDisplayItems(displayItems, 5)}`;
				}
				if (!isRunning) {
					const usageStr = formatUsageStats(aggregateUsage(details.results));
					if (usageStr) text += `\n\n${theme.fg("dim", `Total: ${usageStr}`)}`;
				}
				if (!expanded) text += `\n${theme.fg("muted", "(Ctrl+O to expand)")}`;
				return new Text(text, 0, 0);
			}

			const text = result.content[0];
			return new Text(text?.type === "text" ? text.text : "(no output)", 0, 0);
		},
	});

	pi.on("session_start", async (_event, ctx) => {
		const pending = pendingSwitch.value;
		if (!pending || pending.file !== ctx.sessionManager.getSessionFile()) return;
		pendingSwitch.value = undefined;
		const model = ctx.modelRegistry.find(pending.provider, pending.model);
		if (model && (await pi.setModel(model))) {
			if (ctx.hasUI) ctx.ui.notify(`Model: ${pending.provider}/${pending.model}`, "info");
		} else if (ctx.hasUI) {
			ctx.ui.notify(`Could not restore model ${pending.provider}/${pending.model}`, "warning");
		}
	});

	pi.registerCommand("subagents", {
		description:
			"Watch & control running subagents (while busy: steer, follow-up, abort, hold), or switch into a subagent's session (when idle; `/subagents back` returns)",
		handler: async (args, ctx) => {
			if (!ctx.isIdle() || args?.trim() === "live") {
				await showLiveViewer(ctx);
				return;
			}

			const currentFile = ctx.sessionManager.getSessionFile();
			const header = ctx.sessionManager.getHeader() as { parentSession?: string } | undefined;
			const parent =
				currentFile && path.dirname(currentFile) === SUBAGENT_SESSION_DIR ? header?.parentSession : undefined;

			const switchTo = async (file: string) => {
				if (!fs.existsSync(file)) {
					ctx.ui.notify(`Session file not found: ${file}`, "error");
					return;
				}
				// ctx is stale after a successful switch; do not use it afterwards.
				// The model is applied by the fresh runtime's session_start handler (captured `pi` goes stale).
				const last = lastAssistantModel(file);
				pendingSwitch.value = last ? { file, ...last } : undefined;
				const res = await ctx.switchSession(file);
				if (res?.cancelled) pendingSwitch.value = undefined;
			};

			if (args?.trim() === "back") {
				if (parent) await switchTo(parent);
				else ctx.ui.notify("This is not a subagent session (no parent to return to).", "info");
				return;
			}

			// Collect subagent runs recorded in this conversation branch, newest first
			const runs: SingleResult[] = [];
			for (const entry of ctx.sessionManager.getBranch() as any[]) {
				const msg = entry?.type === "message" ? entry.message : undefined;
				if (msg?.role !== "toolResult" || msg.toolName !== "subagent") continue;
				const details = msg.details as SubagentDetails | undefined;
				for (const r of details?.results ?? []) if (r.sessionFile) runs.push(r);
			}
			runs.reverse();

			const options: string[] = [];
			const targets: string[] = [];
			if (parent) {
				options.push("\u21a9  Back to parent session");
				targets.push(parent);
			}
			runs.slice(0, 50).forEach((r, i) => {
				const icon = isFailedResult(r) ? "\u2717" : "\u2713";
				const model = r.model ? r.model.split("/").pop() : "?";
				const task = r.task.replace(/\s+/g, " ").trim();
				const preview = task.length > 80 ? `${task.slice(0, 80)}\u2026` : task;
				const step = r.step ? ` (step ${r.step})` : "";
				options.push(`${i + 1}. ${icon} ${r.agent}${step} \u00b7 ${model} \u00b7 ${preview}`);
				targets.push(r.sessionFile as string);
			});

			if (options.length === 0) {
				ctx.ui.notify("No subagent sessions in this conversation yet.", "info");
				return;
			}

			const choice = await ctx.ui.select("Subagent sessions", options);
			if (choice === undefined) return;
			const idx = options.indexOf(choice);
			if (idx >= 0) await switchTo(targets[idx]);
		},
	});
}
