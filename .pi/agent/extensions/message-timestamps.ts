/**
 * Message Timestamps Extension
 *
 * Shows a timestamp next to (above) each user and assistant message in the
 * interactive transcript. Display-only: it hooks the Markdown transformer, so
 * model context and the session file are never modified.
 *
 * Usage:
 *   /msg-times            - toggle timestamps
 *   /msg-times on|off     - set explicitly
 *   pi --msg-times ...    - start with timestamps enabled
 *
 * The preference persists in ~/.pi/agent/message-timestamps.json.
 *
 * Notes / limitations:
 * - Timestamps appear on user messages and assistant text blocks (thinking
 *   blocks, tool calls, and custom messages are not stamped).
 * - Assistant messages show the time the response started; resumed sessions
 *   show the persisted completion time.
 * - Time is formatted as HH:MM:SS for today, "Mon D HH:MM:SS" for older days.
 * - The transcript caches rendered Markdown, so the /msg-times toggle applies
 *   to existing messages by forcing one full re-render (TUI mode only).
 * - If two messages contain identical text, both show the later timestamp
 *   (matching is by content, since the transformer only receives the text).
 * - Messages whose text is rewritten by another Markdown transformer (e.g.
 *   mermaid rendering) may not match and will show no timestamp.
 */

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { Component } from "@earendil-works/pi-tui";
import type { ExtensionAPI, ExtensionContext, MarkdownTransformContext } from "@earendil-works/pi-coding-agent";
import { getAgentDir } from "@earendil-works/pi-coding-agent";

const STATE_FILE = join(getAgentDir(), "message-timestamps.json");

type TextBlock = { type: string; text?: string };

/** Mirror of interactive-mode's getUserMessageText(): join text blocks, untrimmed. */
function userMessageKey(content: unknown): string | undefined {
	if (typeof content === "string") return content || undefined;
	if (!Array.isArray(content)) return undefined;
	const parts: string[] = [];
	for (const block of content) {
		if (block && (block as TextBlock).type === "text") parts.push((block as TextBlock).text ?? "");
	}
	if (parts.length === 0) return undefined;
	const joined = parts.join("");
	return joined || undefined;
}

/** Mirror of the assistant component: each non-empty text block, trimmed. */
function assistantTextKeys(content: unknown): string[] {
	if (!Array.isArray(content)) return [];
	const keys: string[] = [];
	for (const block of content) {
		if (block && (block as TextBlock).type === "text" && typeof (block as TextBlock).text === "string") {
			const text = (block as TextBlock).text as string;
			if (text.trim()) keys.push(text.trim());
		}
	}
	return keys;
}

function formatStamp(ts: number): string {
	const d = new Date(ts);
	const now = new Date();
	const pad = (n: number) => String(n).padStart(2, "0");
	const time = `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
	if (d.toDateString() === now.toDateString()) return time;
	const date = d.toLocaleDateString(undefined, { month: "short", day: "numeric" });
	return `${date} ${time}`;
}

export default function (pi: ExtensionAPI) {
	let enabled = false;
	try {
		enabled = (JSON.parse(readFileSync(STATE_FILE, "utf8")) as { enabled?: unknown })?.enabled === true;
	} catch {
		enabled = false;
	}

	/** Finalized message text -> timestamp (ms). */
	const times = new Map<string, number>();
	/** Partial text of the in-flight assistant message -> stream start time. */
	const live = new Map<string, number>();
	let activeStart = 0;

	const persist = () => {
		try {
			writeFileSync(STATE_FILE, `${JSON.stringify({ enabled }, null, 2)}\n`);
		} catch {
			// Non-fatal: preference just won't persist.
		}
	};

	/**
	 * Display-only hook: runs on every render of user/assistant Markdown.
	 * Prepend a time header when the message text is in the timestamp map.
	 */
	pi.registerMarkdownTransformer((markdown: string, context: MarkdownTransformContext): string => {
		if (!enabled) return markdown;
		if (context.messageType === "assistant-thinking") return markdown;
		if (!markdown || !markdown.trim()) return markdown;

		let ts = times.get(markdown);

		// While streaming, the rendered text can lag (or lead) the last
		// message_update event, so fall back to prefix matching.
		if (ts === undefined && context.isStreaming && markdown.length >= 12) {
			for (const [key, start] of live) {
				if (key.length < 12) continue;
				if (key.startsWith(markdown) || markdown.startsWith(key)) {
					ts = start;
					break;
				}
			}
		}

		if (ts === undefined) return markdown;
		return `**${formatStamp(ts)}**\n\n${markdown}`;
	});

	// Seed the map for resumed sessions (fires for startup/resume/new/fork/reload).
	pi.on("session_start", (_event, ctx: ExtensionContext) => {
		const flag = pi.getFlag("msg-times");
		if (typeof flag === "boolean") enabled = flag;

		times.clear();
		live.clear();
		activeStart = 0;

		try {
			for (const entry of ctx.sessionManager.getBranch()) {
				if (entry.type !== "message") continue;
				const message = entry.message;
				const ts = message.timestamp || Date.parse(entry.timestamp) || 0;
				if (message.role === "user") {
					const key = userMessageKey(message.content);
					if (key) times.set(key, ts);
				} else if (message.role === "assistant") {
					for (const key of assistantTextKeys(message.content)) times.set(key, ts);
				}
			}
		} catch {
			// Seeding is best-effort; live events still work.
		}
	});

	pi.on("message_start", (event) => {
		const message = event.message;
		if (message.role === "user") {
			const key = userMessageKey(message.content);
			if (key) times.set(key, message.timestamp || Date.now());
		} else if (message.role === "assistant") {
			activeStart = message.timestamp || Date.now();
			live.clear();
			for (const key of assistantTextKeys(message.content)) live.set(key, activeStart);
		}
	});

	pi.on("message_update", (event) => {
		const message = event.message;
		if (message.role !== "assistant") return;
		if (!activeStart) activeStart = Date.now();
		for (const key of assistantTextKeys(message.content)) live.set(key, activeStart);
	});

	pi.on("message_end", (event) => {
		const message = event.message;
		if (message.role === "assistant") {
			const ts = activeStart || message.timestamp || Date.now();
			for (const key of assistantTextKeys(message.content)) times.set(key, ts);
			live.clear();
			activeStart = 0;
		} else if (message.role === "user") {
			const key = userMessageKey(message.content);
			if (key) times.set(key, message.timestamp || Date.now());
		}
	});

	pi.registerFlag("msg-times", {
		description: "Show timestamps next to user and assistant messages",
		type: "boolean",
	});

	/**
	 * Force the transcript to re-render so the toggle applies to existing
	 * messages, not only new ones (Markdown components cache their lines).
	 * A zero-line custom component that closes itself immediately; the TUI is
	 * never actually replaced.
	 */
	async function refreshTranscript(ctx: ExtensionContext): Promise<void> {
		if (ctx.mode !== "tui" || !ctx.hasUI) return;
		try {
			await ctx.ui.custom<unknown>((tui, _theme, _keybindings, done) => {
				tui.invalidate();
				tui.requestRender();
				done(undefined);
				return {
					render: () => [],
					invalidate: () => {},
				} as Component;
			});
		} catch {
			// Refresh is cosmetic; ignore failures (e.g. RPC mode).
		}
	}

	pi.registerCommand("msg-times", {
		description: "Toggle timestamps next to messages (/msg-times [on|off])",
		handler: async (args, ctx) => {
			const arg = (args ?? "").trim().toLowerCase();
			if (arg === "on") enabled = true;
			else if (arg === "off") enabled = false;
			else enabled = !enabled;
			persist();
			await refreshTranscript(ctx);
			if (ctx.hasUI) ctx.ui.notify(`Message timestamps ${enabled ? "enabled" : "disabled"}`);
		},
	});
}
