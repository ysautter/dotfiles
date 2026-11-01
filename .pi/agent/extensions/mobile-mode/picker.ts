/**
 * Tap/keyboard friendly multi-question picker for narrow (phone) terminals.
 *
 * - One page per question, plus a review page (when >1 question).
 * - Tap an option (mouse click, fullscreen TUI) or press its digit 1-9.
 * - "✎ Type answer…" opens an inline editor for a custom reply.
 * - Nothing is sent until "✓ Send" - all answers go out together.
 * - Esc dismisses (caller turns partial answers into an editable draft).
 */

import { Editor, type EditorTheme, Key, matchesKey, truncateToWidth, visibleWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";

export interface MQuestion {
	id?: string;
	header?: string;
	question: string;
	options: string[];
	multi?: boolean;
}

export interface MAnswer {
	selected: number[];
	custom?: string;
}

export interface PickerResult {
	action: "send" | "dismiss";
	answers: MAnswer[];
	note?: string;
}

// Minimal structural theme type (the real Theme is passed in by ctx.ui.custom).
export interface ThemeLike {
	fg(color: string, text: string): string;
	bg(color: string, text: string): string;
	bold(text: string): string;
}

type Seg = { x0: number; x1: number; run: () => void };

/** A keyboard-focusable thing on the current page. */
type Item =
	| { kind: "option"; index: number }
	| { kind: "custom" }
	| { kind: "next" }
	| { kind: "goto"; page: number }
	| { kind: "note" }
	| { kind: "send" };

export function hasAnswer(a: MAnswer | undefined): boolean {
	return !!a && (a.selected.length > 0 || !!a.custom?.trim());
}

export function answerText(q: MQuestion, a: MAnswer | undefined): string {
	if (!hasAnswer(a)) return "(no answer)";
	const parts = a!.selected.map((i) => q.options[i]).filter(Boolean);
	if (a!.custom?.trim()) parts.push(a!.custom.trim());
	return parts.join("; ");
}

export class MobilePicker {
	private _focused = false;
	get focused(): boolean {
		return this._focused;
	}
	set focused(v: boolean) {
		this._focused = v;
		this.editor.focused = v && !!this.editing;
		this.cache = undefined;
	}

	private page = 0;
	private cursor = 0;
	private answers: MAnswer[];
	private note = "";
	private editing: null | { kind: "custom"; q: number } | { kind: "note" } = null;
	private editor: Editor;
	private rows: Seg[][] = [];
	private cache?: { width: number; lines: string[] };
	private readonly multiPage: boolean;

	constructor(
		private tui: { requestRender(): void },
		private theme: ThemeLike,
		private questions: MQuestion[],
		private done: (r: PickerResult) => void,
		private opts: { title?: string; autoSendSingle?: boolean } = {},
	) {
		this.answers = questions.map(() => ({ selected: [] }));
		this.multiPage = questions.length > 1;
		const editorTheme: EditorTheme = {
			borderColor: (s) => theme.fg("accent", s),
			selectList: {
				selectedPrefix: (t) => theme.fg("accent", t),
				selectedText: (t) => theme.fg("accent", t),
				description: (t) => theme.fg("muted", t),
				scrollInfo: (t) => theme.fg("dim", t),
				noMatch: (t) => theme.fg("warning", t),
			},
		};
		this.editor = new Editor(tui as never, editorTheme);
		this.editor.onSubmit = (value: string) => this.saveEdit(value);
	}

	// ---------------------------------------------------------------- state

	private get reviewPage(): number {
		return this.questions.length; // only meaningful when multiPage
	}

	private onReview(): boolean {
		return this.multiPage && this.page === this.reviewPage;
	}

	private refresh(): void {
		this.cache = undefined;
		this.tui.requestRender();
	}

	invalidate(): void {
		this.cache = undefined;
	}

	private items(): Item[] {
		if (this.onReview()) {
			return [
				...this.questions.map((_, i) => ({ kind: "goto", page: i }) as Item),
				{ kind: "note" },
				{ kind: "send" },
			];
		}
		const q = this.questions[this.page];
		const list: Item[] = q.options.map((_, index) => ({ kind: "option", index }) as Item);
		list.push({ kind: "custom" });
		if (this.multiPage || q.multi || !this.opts.autoSendSingle) list.push({ kind: "next" });
		return list;
	}

	private goPage(p: number): void {
		const last = this.multiPage ? this.reviewPage : 0;
		this.page = Math.max(0, Math.min(last, p));
		this.cursor = this.onReview() ? this.items().length - 1 : this.defaultCursor();
		this.refresh();
	}

	private defaultCursor(): number {
		const a = this.answers[this.page];
		return a?.selected.length ? a.selected[0] : 0;
	}

	private finish(action: PickerResult["action"]): void {
		this.done({ action, answers: this.answers, note: this.note.trim() || undefined });
	}

	/** After answering the current (single-select) question. */
	private advance(): void {
		if (!this.multiPage) {
			if (this.opts.autoSendSingle) return this.finish("send");
			this.cursor = this.items().length - 1; // jump to "Send"
			return this.refresh();
		}
		const n = this.questions.length;
		for (let k = 1; k <= n; k++) {
			const i = (this.page + k) % n;
			if (i > this.page && !hasAnswer(this.answers[i])) return this.goPage(i);
		}
		// wrap-around: any unanswered earlier question? still go to review, user decides
		this.goPage(this.reviewPage);
	}

	private pickOption(index: number, viaDigit = false): void {
		const q = this.questions[this.page];
		if (!q || index < 0 || index >= q.options.length) return;
		const a = this.answers[this.page];
		this.cursor = index;
		if (q.multi) {
			a.selected = a.selected.includes(index) ? a.selected.filter((i) => i !== index) : [...a.selected, index].sort();
			// digits toggle; then Enter should proceed, not re-toggle
			if (viaDigit) this.cursor = this.items().findIndex((it) => it.kind === "next");
			return this.refresh();
		}
		a.selected = [index];
		a.custom = undefined;
		this.advance();
	}

	private startEdit(target: { kind: "custom"; q: number } | { kind: "note" }): void {
		this.editing = target;
		this.editor.setText(target.kind === "note" ? this.note : (this.answers[target.q].custom ?? ""));
		this.editor.focused = this.focused;
		this.refresh();
	}

	private cancelEdit(): void {
		this.editing = null;
		this.editor.setText("");
		this.refresh();
	}

	private saveEdit(value: string): void {
		const target = this.editing;
		if (!target) return;
		const text = value.trim();
		this.editing = null;
		this.editor.setText("");
		if (target.kind === "note") {
			this.note = text;
			return this.refresh();
		}
		const q = this.questions[target.q];
		const a = this.answers[target.q];
		a.custom = text || undefined;
		if (!q.multi && text) a.selected = [];
		if (text && !q.multi) return this.advance();
		this.refresh();
	}

	private activate(item: Item | undefined): void {
		if (!item) return;
		switch (item.kind) {
			case "option":
				return this.pickOption(item.index);
			case "custom":
				return this.startEdit({ kind: "custom", q: this.page });
			case "next":
				if (!this.multiPage) return this.finish("send");
				return this.goPage(this.page + 1);
			case "goto":
				return this.goPage(item.page);
			case "note":
				return this.startEdit({ kind: "note" });
			case "send":
				return this.finish("send");
		}
	}

	// ---------------------------------------------------------------- input

	handleInput(data: string): void {
		if (this.editing) {
			if (matchesKey(data, Key.escape)) return this.cancelEdit();
			this.editor.handleInput(data);
			return this.refresh();
		}
		const items = this.items();

		if (matchesKey(data, Key.escape)) return this.finish("dismiss");
		if (matchesKey(data, Key.up)) {
			this.cursor = (this.cursor - 1 + items.length) % items.length;
			return this.refresh();
		}
		if (matchesKey(data, Key.down)) {
			this.cursor = (this.cursor + 1) % items.length;
			return this.refresh();
		}
		if (this.multiPage && (matchesKey(data, Key.right) || matchesKey(data, Key.tab))) return this.goPage(this.page + 1);
		if (this.multiPage && (matchesKey(data, Key.left) || matchesKey(data, Key.shift("tab")))) return this.goPage(this.page - 1);
		if (matchesKey(data, Key.enter)) return this.activate(items[this.cursor]);

		if (/^[1-9]$/.test(data)) {
			const n = Number(data) - 1;
			if (this.onReview()) return n < this.questions.length ? this.goPage(n) : undefined;
			return this.pickOption(n, true);
		}
		if (data === "0" || data === "e" || data === "t") {
			return this.onReview() ? this.startEdit({ kind: "note" }) : this.startEdit({ kind: "custom", q: this.page });
		}
		if (data === "s" && (this.multiPage || this.questions[0]?.multi)) return this.finish("send");
	}

	handleMouse(event: { type: string; button?: string; x: number; y: number }): { handled: boolean } | undefined {
		const segs = this.rows[event.y];
		if (!segs || segs.length === 0) return undefined;
		if (event.type === "press") return { handled: true };
		if (event.type !== "click" || (event.button && event.button !== "left")) return undefined;
		const seg = segs.find((s) => event.x >= s.x0 && event.x < s.x1) ?? (segs.length === 1 ? segs[0] : undefined);
		if (!seg) return { handled: true };
		seg.run();
		return { handled: true };
	}

	// ---------------------------------------------------------------- render

	render(width: number): string[] {
		if (this.cache && this.cache.width === width) return this.cache.lines;
		this.editor.focused = this.focused && !!this.editing;
		const w = Math.max(10, width);
		const t = this.theme;
		const lines: string[] = [];
		const rows: Seg[][] = [];
		const push = (line: string, segs?: Seg[]) => {
			rows[lines.length] = segs ?? [];
			lines.push(truncateToWidth(line, w));
		};
		const pushWrapped = (text: string, color: string, indent = 0, segs?: Seg[]) => {
			const pad = " ".repeat(indent);
			for (const l of wrapTextWithAnsi(text, Math.max(1, w - indent))) push(pad + t.fg(color, l), segs);
		};
		const fullRow = (run: () => void): Seg[] => [{ x0: 0, x1: w, run }];

		// ── header
		const total = this.questions.length;
		let title: string;
		if (this.onReview()) title = "Review";
		else {
			const q = this.questions[this.page];
			title = this.multiPage ? `${this.page + 1}/${total}${q.header ? ` ${q.header}` : ""}` : (q.header ?? this.opts.title ?? "Reply");
		}
		let dots = "";
		if (this.multiPage) {
			dots = this.questions
				.map((_, i) => {
					const ch = i === this.page ? "◆" : hasAnswer(this.answers[i]) ? "●" : "○";
					return t.fg(hasAnswer(this.answers[i]) ? "success" : i === this.page ? "accent" : "dim", ch);
				})
				.join("");
		}
		const headLeft = `${t.fg("accent", "━ ")}${t.fg("accent", t.bold(title))} `;
		const used = visibleWidth(headLeft) + (dots ? visibleWidth(dots) + 2 : 0);
		push(`${headLeft}${t.fg("accent", "━".repeat(Math.max(1, w - used)))}${dots ? ` ${dots} ` : ""}`);

		// ── body
		if (this.editing) {
			const label =
				this.editing.kind === "note" ? "Note (sent with all answers):" : this.questions[this.editing.q].question;
			pushWrapped(label, "text");
			for (const l of this.editor.render(w)) push(l);
			const save = " ✓ Save ";
			const back = " ✗ Back ";
			const x1 = visibleWidth(save);
			push(`${t.bg("selectedBg", t.fg("success", save))}  ${t.fg("muted", back)}`, [
				{ x0: 0, x1, run: () => this.saveEdit(this.editor.getText()) },
				{ x0: x1 + 2, x1: x1 + 2 + visibleWidth(back), run: () => this.cancelEdit() },
			]);
			push(t.fg("dim", "⏎ save · esc back"));
		} else if (this.onReview()) {
			const items = this.items();
			this.questions.forEach((q, i) => {
				const a = this.answers[i];
				const sel = this.cursor === i;
				const label = q.header || truncateToWidth(q.question, 18);
				const val = hasAnswer(a) ? answerText(q, a) : "— tap to answer";
				const text = `${i + 1} ${label}: ${val}`;
				const wrapped = wrapTextWithAnsi(text, w - 2);
				wrapped.forEach((l, j) => {
					const color = hasAnswer(a) ? "text" : "warning";
					const body = (j === 0 ? (sel ? "› " : "  ") : "  ") + l;
					push(sel ? t.bg("selectedBg", t.fg(color, padTo(body, w))) : t.fg(color, body), fullRow(() => this.goPage(i)));
				});
			});
			const noteSel = items[this.cursor]?.kind === "note";
			const noteText = `${noteSel ? "› " : "  "}✎ ${this.note ? `Note: ${this.note}` : "Add note…"}`;
			for (const l of wrapTextWithAnsi(noteText, w))
				push(noteSel ? t.bg("selectedBg", t.fg("muted", padTo(l, w))) : t.fg("muted", l), fullRow(() => this.startEdit({ kind: "note" })));
			this.renderNav(push, w);
		} else {
			const q = this.questions[this.page];
			const a = this.answers[this.page];
			pushWrapped(t.bold(q.question), "text");
			q.options.forEach((opt, i) => {
				const isSel = a.selected.includes(i);
				const mark = q.multi ? (isSel ? "■" : "□") : isSel ? "●" : "○";
				const cur = this.cursor === i;
				const text = `${mark} ${i + 1} ${opt}`;
				const color = isSel ? "success" : "text";
				wrapTextWithAnsi(text, w - 1).forEach((l, j) => {
					const body = ` ${j === 0 ? l : `    ${l}`}`;
					push(cur ? t.bg("selectedBg", t.fg(color, padTo(body, w))) : t.fg(color, body), fullRow(() => this.pickOption(i)));
				});
			});
			const ci = q.options.length;
			const cur = this.cursor === ci;
			const ctext = a.custom ? `✎ “${a.custom}”` : "✎ Type answer…";
			wrapTextWithAnsi(` ${ctext}`, w).forEach((l) => {
				const color = a.custom ? "success" : "muted";
				push(cur ? t.bg("selectedBg", t.fg(color, padTo(l, w))) : t.fg(color, l), fullRow(() => this.startEdit({ kind: "custom", q: this.page })));
			});
			this.renderNav(push, w);
		}

		this.rows = rows;
		this.cache = { width, lines };
		return lines;
	}

	/** Bottom row: ‹ Back | Next › / Review › | ✓ Send (each separately tappable). */
	private renderNav(push: (line: string, segs?: Seg[]) => void, w: number): void {
		const t = this.theme;
		const items = this.items();
		const curItem = items[this.cursor];
		const parts: { text: string; color: string; run: () => void; hot?: boolean }[] = [];
		const answered = this.answers.filter(hasAnswer).length;
		const total = this.questions.length;

		if (this.multiPage && this.page > 0) parts.push({ text: " ‹ Back ", color: "muted", run: () => this.goPage(this.page - 1) });
		if (this.multiPage && !this.onReview()) {
			const isLast = this.page === total - 1;
			parts.push({
				text: isLast ? " Review › " : " Next › ",
				color: "accent",
				run: () => this.goPage(this.page + 1),
				hot: curItem?.kind === "next",
			});
		}
		const showSend = this.onReview() || (!this.multiPage && items.some((i) => i.kind === "next"));
		if (showSend) {
			const label = this.multiPage ? ` ✓ Send ${answered}/${total} ` : " ✓ Send ";
			parts.push({
				text: label,
				color: answered === total ? "success" : "warning",
				run: () => this.finish("send"),
				hot: curItem?.kind === "send" || (!this.multiPage && curItem?.kind === "next"),
			});
		}
		if (parts.length === 0) {
			push(this.theme.fg("dim", "1-9 pick · esc = type freely"));
			return;
		}
		let line = "";
		let x = 0;
		const segs: Seg[] = [];
		for (const p of parts) {
			const styled = p.hot ? t.bg("selectedBg", t.fg(p.color, t.bold(p.text))) : t.fg(p.color, p.text);
			const wdt = visibleWidth(p.text);
			segs.push({ x0: x, x1: x + wdt, run: p.run });
			line += `${styled} `;
			x += wdt + 1;
		}
		push(line, segs);
		const hint = this.onReview() ? "⏎/s send · 1-9 edit · esc draft" : "1-9 pick · 0 type · ←→ · esc draft";
		if (visibleWidth(hint) <= w) push(t.fg("dim", hint));
	}
}

function padTo(s: string, w: number): string {
	const v = visibleWidth(s);
	return v >= w ? s : s + " ".repeat(w - v);
}
