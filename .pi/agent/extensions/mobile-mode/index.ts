/**
 * Mobile Mode Extension
 *
 * For using pi from a phone (Termius over SSH, usually inside tmux) where
 * typing is painful. When mobile mode is active:
 *
 *  - The model is told the screen is tiny (~42 cols) and to keep output short.
 *  - The `ask_user` tool is enabled. Whenever the model needs input (or is done
 *    and you'd pick a next step) it calls ask_user with ALL open questions at
 *    once, each with a few anticipated short answers. You tap (or press 1-9)
 *    an answer per question, optionally type a custom one, review, and send -
 *    all answers go back together in one reply.
 *  - Fallback: if the model ends its turn with plain text anyway, a picker is
 *    generated from the last message by a quick model call (autoSuggest).
 *  - Esc in any picker turns the partial answers into an editable draft in
 *    the normal editor.
 *
 * Detection ("auto"): terminal narrower than `maxWidth` columns, or - inside
 * tmux - the most recently active client of this session is that narrow.
 *
 * Commands:
 *   /mobile                 show status
 *   /mobile on|off|auto     force on / off / auto-detect (persisted)
 *   /mobile demo            open a sample picker (UI test, no model call)
 *   /reply                  build a tap-reply picker for the last message now
 *
 * Config: ~/.pi/agent/mobile-mode.json
 *   { "mode": "auto", "maxWidth": 80, "autoSuggest": true,
 *     "suggestModel": "anthropic/claude-sonnet-5-5", "autoSendSingle": false }
 */

import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { UserMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { BorderedLoader, getAgentDir } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { answerText, hasAnswer, type MQuestion, MobilePicker, type PickerResult } from "./picker.ts";

const CONFIG_FILE = join(getAgentDir(), "mobile-mode.json");
const TOOL = "ask_user";
const STATUS_KEY = "mobile-mode";

type Config = {
	mode: "auto" | "on" | "off";
	maxWidth: number;
	autoSuggest: boolean;
	suggestModel?: string;
	autoSendSingle: boolean;
};

const DEFAULTS: Config = { mode: "auto", maxWidth: 80, autoSuggest: true, autoSendSingle: false };

function loadConfig(): Config {
	try {
		return { ...DEFAULTS, ...(JSON.parse(readFileSync(CONFIG_FILE, "utf8")) as Partial<Config>) };
	} catch {
		return { ...DEFAULTS };
	}
}

const PROMPT_SECTION = `The user is on a PHONE right now (Termius over SSH/tmux, ~42 columns x ~18 rows). Typing is very hard for them; tapping is easy.

Output style:
- Be brief. Short paragraphs and short bullets. Lead with the outcome.
- No tables, no wide ASCII diagrams, no long lines of code. Show only the essential lines of code/diffs; summarize the rest.

Asking the user (IMPORTANT):
- Never end your turn with questions in plain text. Whenever you need input, a decision, or a confirmation - and also when you are finished and the user would choose what to do next - call the \`${TOOL}\` tool as your very LAST action, alone (no other tool calls in that message).
- Put ALL open questions into ONE \`${TOOL}\` call; the user answers them together and you get all answers at once. Do not ask one question after another.
- Write your explanation/context in your normal message text BEFORE the tool call. Keep each question itself short (<= 80 chars) and self-contained.
- Give each question 2-5 anticipated answers, most likely/recommended first, each as short as possible (ideally <= 25 chars, e.g. "Yes, deploy", "No", "Only staging"). A free-text option is always added automatically - never add "Other".
- Use multi: true only when several options can sensibly be combined.
- If the user dismisses the picker, stop and wait for their typed message.`;

const QuestionSchema = Type.Object({
	header: Type.Optional(Type.String({ description: "1-2 word label shown as title, e.g. 'DB', 'Deploy', 'Next'" })),
	question: Type.String({ description: "Short, self-contained question (<= 80 chars)" }),
	options: Type.Array(Type.String({ description: "Short anticipated answer (ideally <= 25 chars)" }), {
		minItems: 1,
		maxItems: 6,
		description: "2-5 likely answers, most likely first. Free text is added automatically.",
	}),
	multi: Type.Optional(Type.Boolean({ description: "Allow selecting several options (default false)" })),
});

const AskParams = Type.Object({
	questions: Type.Array(QuestionSchema, {
		minItems: 1,
		maxItems: 8,
		description: "ALL open questions for the user, answered together in one go",
	}),
});

type AskDetails = { questions: MQuestion[]; result?: PickerResult; reason?: string };

function formatAnswers(questions: MQuestion[], r: PickerResult): string {
	const lines = questions.map((q, i) => {
		const a = r.answers[i];
		const typed = a?.custom?.trim() ? " (typed)" : "";
		return `${i + 1}. ${q.question}\n   → ${answerText(q, a)}${hasAnswer(a) ? typed : ""}`;
	});
	if (r.note) lines.push(`Note: ${r.note}`);
	return lines.join("\n");
}

/** Partial answers as a plain-text draft for the normal editor. */
function draftText(questions: MQuestion[], r: PickerResult): string {
	const lines: string[] = [];
	questions.forEach((q, i) => {
		if (hasAnswer(r.answers[i])) lines.push(`${questions.length > 1 ? `${i + 1}. ` : ""}${answerText(q, r.answers[i])}`);
		else if (questions.length > 1) lines.push(`${i + 1}. `);
	});
	if (r.note) lines.push(r.note);
	return lines.some((l) => /\S/.test(l.replace(/^\d+\.\s*/, ""))) ? lines.join("\n") : "";
}

function lastAssistant(ctx: ExtensionContext): { text: string; stopReason?: string; askedViaTool: boolean } | undefined {
	// stopReason/askedViaTool from the newest assistant message; text from the newest one that has text.
	const branch = ctx.sessionManager.getBranch();
	let result: { text: string; stopReason?: string; askedViaTool: boolean } | undefined;
	for (let i = branch.length - 1; i >= 0; i--) {
		const e = branch[i] as { type: string; message?: { role: string; content: unknown; stopReason?: string } };
		if (e.type !== "message") continue;
		if (e.message?.role === "user" && result) break; // don't reach into earlier exchanges
		if (e.message?.role !== "assistant") continue;
		const content = Array.isArray(e.message.content) ? (e.message.content as { type: string; text?: string; name?: string }[]) : [];
		const text = content
			.filter((c) => c.type === "text" && c.text)
			.map((c) => c.text!)
			.join("\n")
			.trim();
		if (!result) {
			const askedViaTool = content.some((c) => c.type === "toolCall" && c.name === TOOL);
			result = { text, stopReason: e.message.stopReason, askedViaTool };
		}
		if (text) {
			result.text = text;
			return result;
		}
	}
	return result;
}

function lastUserText(ctx: ExtensionContext): string {
	const branch = ctx.sessionManager.getBranch();
	for (let i = branch.length - 1; i >= 0; i--) {
		const e = branch[i] as { type: string; message?: { role: string; content: unknown } };
		if (e.type !== "message" || e.message?.role !== "user") continue;
		const c = e.message.content;
		if (typeof c === "string") return c;
		if (Array.isArray(c)) return c.filter((p) => p?.type === "text").map((p) => p.text).join("\n");
	}
	return "";
}

const SUGGEST_PROMPT = `You help a user on a phone reply to an AI coding assistant with minimal typing.
Read the assistant's last message. Find every question / decision / confirmation the assistant expects from the user (explicit or implicit), in order. If there is none, create exactly one question "What next?" (header "Next") with the most likely next instructions.
For each question give 2-5 short anticipated replies (ideally <= 25 chars), most likely first. Do not include "Other". Keep each question <= 80 chars.
Output ONLY JSON, no prose, no code fence:
{"questions":[{"header":"1-2 words","question":"...","options":["..."],"multi":false}]}`;

export default function mobileMode(pi: ExtensionAPI) {
	let config = loadConfig();
	let active = false;
	let pickerOpen = false;
	let lastCtx: ExtensionContext | undefined;
	let onResize: (() => void) | undefined;

	const persist = () => {
		try {
			writeFileSync(CONFIG_FILE, `${JSON.stringify(config, null, 2)}\n`);
		} catch {
			// non-fatal
		}
	};

	function narrowTmuxClient(): boolean {
		if (!process.env.TMUX || !process.env.TMUX_PANE) return false;
		try {
			const r = spawnSync("tmux", ["list-clients", "-t", process.env.TMUX_PANE, "-F", "#{client_activity} #{client_width}"], {
				encoding: "utf8",
				timeout: 500,
			});
			if (r.status !== 0 || !r.stdout) return false;
			const clients = r.stdout
				.trim()
				.split("\n")
				.map((l) => l.split(" ").map(Number))
				.filter(([a, w]) => Number.isFinite(a) && Number.isFinite(w))
				.sort((x, y) => y[0] - x[0]);
			return clients.length > 0 && clients[0][1] < config.maxWidth;
		} catch {
			return false;
		}
	}

	function detect(ctx: ExtensionContext): boolean {
		if (ctx.mode !== "tui" || !ctx.hasUI) return false;
		if (config.mode === "on") return true;
		if (config.mode === "off") return false;
		const cols = process.stdout.columns ?? 999;
		return cols < config.maxWidth || narrowTmuxClient();
	}

	function apply(ctx: ExtensionContext): void {
		lastCtx = ctx;
		active = detect(ctx);
		const tools = pi.getActiveTools() as string[];
		const has = tools.includes(TOOL);
		if (active && !has) pi.setActiveTools([...tools, TOOL]);
		if (!active && has) pi.setActiveTools(tools.filter((t) => t !== TOOL));
		if (ctx.hasUI) {
			const label = config.mode === "auto" ? "📱" : `📱${config.mode}`;
			ctx.ui.setStatus(STATUS_KEY, active ? ctx.ui.theme.fg("accent", label) : undefined);
		}
	}

	async function showPicker(ctx: ExtensionContext, questions: MQuestion[], signal?: AbortSignal): Promise<PickerResult> {
		pickerOpen = true;
		try {
			return await ctx.ui.custom<PickerResult>((tui, theme, _kb, done) => {
				let finished = false;
				const finish = (r: PickerResult) => {
					if (finished) return;
					finished = true;
					done(r);
				};
				const picker = new MobilePicker(tui, theme as never, questions, finish, {
					autoSendSingle: config.autoSendSingle,
				});
				signal?.addEventListener("abort", () => finish({ action: "dismiss", answers: [] }), { once: true });
				return picker;
			});
		} finally {
			pickerOpen = false;
		}
	}

	function normalize(raw: unknown): MQuestion[] {
		const list = (raw as { questions?: unknown })?.questions;
		if (!Array.isArray(list)) return [];
		return list
			.map((q) => q as Partial<MQuestion>)
			.filter((q) => typeof q.question === "string" && Array.isArray(q.options))
			.map((q) => ({
				header: typeof q.header === "string" ? q.header : undefined,
				question: q.question!.trim(),
				options: q.options!.map(String).map((s) => s.trim()).filter(Boolean).slice(0, 6),
				multi: q.multi === true,
			}))
			.slice(0, 8);
	}

	/** Fallback: derive questions + options from the last assistant text, show picker, send reply. */
	async function suggestAndPick(ctx: ExtensionContext, assistantText: string): Promise<void> {
		let model = ctx.model;
		if (config.suggestModel) {
			const [provider, ...rest] = config.suggestModel.split("/");
			model = ctx.modelRegistry.find(provider, rest.join("/")) ?? model;
		}
		if (!model) return;
		pickerOpen = true;
		let questions: MQuestion[] | null;
		try {
			questions = await ctx.ui.custom<MQuestion[] | null>((tui, theme, _kb, done) => {
				const loader = new BorderedLoader(tui, theme, "📱 reply options…");
				loader.onAbort = () => done(null);
				const user = lastUserText(ctx).slice(-1500);
				const msg: UserMessage = {
					role: "user",
					content: [
						{
							type: "text",
							text: `${user ? `<user_previous_message>\n${user}\n</user_previous_message>\n\n` : ""}<assistant_last_message>\n${assistantText.slice(-6000)}\n</assistant_last_message>`,
						},
					],
					timestamp: Date.now(),
				};
				ctx.modelRegistry
					.complete(model!, { systemPrompt: SUGGEST_PROMPT, messages: [msg] }, { signal: loader.signal })
					.then((res) => {
						if (res.stopReason === "aborted") return done(null);
						const text = res.content
							.filter((c): c is { type: "text"; text: string } => c.type === "text")
							.map((c) => c.text)
							.join("\n");
						const json = /\{[\s\S]*\}/.exec(text)?.[0];
						done(json ? normalize(JSON.parse(json)) : null);
					})
					.catch(() => done(null));
				return loader;
			});
		} finally {
			pickerOpen = false;
		}
		if (!questions || questions.length === 0) return;
		const r = await showPicker(ctx, questions);
		if (r.action === "send") {
			pi.sendUserMessage(formatAnswers(questions, r));
		} else {
			const draft = draftText(questions, r);
			if (draft) ctx.ui.setEditorText(draft);
		}
	}

	// ------------------------------------------------------------------ tool

	pi.registerTool({
		name: TOOL,
		label: "Ask user",
		description:
			"Ask the user (who is on a phone) ALL open questions at once as tappable multiple choice. " +
			"Each question gets 2-5 short anticipated answers; free text is always available. " +
			"Returns all answers together. Call it alone, as the last action of your message.",
		parameters: AskParams,
		executionMode: "sequential",

		async execute(_id, params, signal, _onUpdate, ctx) {
			const questions = normalize(params);
			if (ctx.mode !== "tui" || !ctx.hasUI) {
				return {
					content: [{ type: "text", text: "No interactive UI. Ask the questions in plain text instead." }],
					details: { questions, reason: "no-ui" } as AskDetails,
				};
			}
			if (questions.length === 0) throw new Error("No valid questions given");

			const first = questions[0];
			pi.events.emit("mobile-mode:waiting", {
				title: "pi needs your answer",
				message: questions.length > 1 ? `${questions.length} questions: ${first.question}` : first.question,
			});
			let r: PickerResult;
			try {
				r = await showPicker(ctx, questions, signal);
			} finally {
				pi.events.emit("mobile-mode:answered", {});
			}

			if (r.action === "dismiss") {
				const draft = draftText(questions, r);
				if (draft && !signal?.aborted) ctx.ui.setEditorText(draft);
				return {
					content: [
						{
							type: "text",
							text: "The user dismissed the picker and will type a reply. Stop now and wait for their message.",
						},
					],
					details: { questions, result: r } as AskDetails,
					terminate: true,
				};
			}
			return {
				content: [{ type: "text", text: `User answers:\n${formatAnswers(questions, r)}` }],
				details: { questions, result: r } as AskDetails,
			};
		},

		renderCall(args, theme) {
			const qs = ((args as { questions?: MQuestion[] }).questions ?? []).filter(Boolean);
			let text = theme.fg("toolTitle", theme.bold("ask_user "));
			text += theme.fg("muted", `${qs.length} question${qs.length === 1 ? "" : "s"}`);
			for (const [i, q] of qs.entries()) text += `\n${theme.fg("dim", `${i + 1}.`)} ${q.question ?? ""}`;
			return new Text(text, 0, 0);
		},

		renderResult(result, _opts, theme) {
			const d = result.details as AskDetails | undefined;
			if (!d?.result) {
				const c = result.content?.[0];
				return new Text(c?.type === "text" ? c.text : "", 0, 0);
			}
			if (d.result.action === "dismiss") return new Text(theme.fg("warning", "Dismissed - typing reply"), 0, 0);
			const lines = d.questions.map((q, i) => {
				const a = d.result!.answers[i];
				const ok = hasAnswer(a);
				return `${theme.fg(ok ? "success" : "warning", ok ? "✓" : "–")} ${theme.fg("accent", q.header ?? `${i + 1}`)}: ${answerText(q, a)}`;
			});
			if (d.result.note) lines.push(`${theme.fg("muted", "Note:")} ${d.result.note}`);
			return new Text(lines.join("\n"), 0, 0);
		},
	});

	// ---------------------------------------------------------------- events

	pi.on("session_start", (_e, ctx) => {
		config = loadConfig();
		apply(ctx);
		if (ctx.mode === "tui" && !onResize) {
			onResize = () => {
				if (lastCtx) {
					try {
						apply(lastCtx);
					} catch {
						// stale ctx
					}
				}
			};
			process.stdout.on("resize", onResize);
		}
	});

	pi.on("session_shutdown", () => {
		if (onResize) process.stdout.off("resize", onResize);
		onResize = undefined;
		lastCtx = undefined;
	});

	pi.on("before_agent_start", (event, ctx) => {
		apply(ctx);
		const sections = event.systemPromptOptions.sections as Record<string, string | undefined>;
		if (active) sections.mobile_mode = PROMPT_SECTION;
		else delete sections.mobile_mode;
	});

	pi.on("agent_settled", (event, ctx) => {
		apply(ctx);
		if (!active || !config.autoSuggest || pickerOpen) return;
		if ((event as { aborted?: boolean }).aborted) return;
		const last = lastAssistant(ctx);
		if (!last || last.askedViaTool || last.stopReason !== "stop" || !last.text) return;
		// Let pi finish settling before taking over the editor area.
		setTimeout(() => {
			if (pickerOpen || !ctx.isIdle()) return;
			void suggestAndPick(ctx, last.text).catch((err) => ctx.ui.notify(`mobile: ${(err as Error).message}`, "error"));
		}, 50);
	});

	// --------------------------------------------------------------- commands

	pi.registerCommand("mobile", {
		description: "Mobile mode (/mobile [on|off|auto|demo])",
		handler: async (args, ctx) => {
			const arg = (args ?? "").trim().toLowerCase();
			if (arg === "on" || arg === "off" || arg === "auto") {
				config.mode = arg;
				persist();
			} else if (arg === "demo") {
				const qs: MQuestion[] = [
					{ header: "DB", question: "Which database should the service use?", options: ["Postgres", "SQLite", "Keep current"] },
					{ header: "Deploy", question: "Deploy to production after tests pass?", options: ["Yes", "Staging only", "No"] },
					{ header: "Fixes", question: "Which follow-ups should I do?", options: ["Add tests", "Update docs", "Refactor"], multi: true },
				];
				const r = await showPicker(ctx, qs);
				ctx.ui.notify(r.action === "send" ? formatAnswers(qs, r) : `dismissed; draft:\n${draftText(qs, r)}`, "info");
				return;
			}
			apply(ctx);
			const cols = process.stdout.columns ?? 0;
			ctx.ui.notify(`Mobile mode: ${active ? "ON" : "off"} (setting: ${config.mode}, ${cols} cols, threshold ${config.maxWidth})`, "info");
		},
	});

	pi.registerCommand("reply", {
		description: "Tap-reply options for the last assistant message",
		handler: async (_args, ctx) => {
			if (ctx.mode !== "tui") return;
			const last = lastAssistant(ctx);
			if (!last?.text) {
				ctx.ui.notify("No assistant message to reply to", "warning");
				return;
			}
			await suggestAndPick(ctx, last.text);
		},
	});
}
