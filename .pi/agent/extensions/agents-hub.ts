/**
 * agents-hub: publish this pi's state as tmux session options, so the session
 * picker (~/.local/bin/tmux-pick) and quickshell (services/Agents.qml) can show
 * real state instead of guessing from pane activity.
 *
 * Session options (on the tmux session this pi runs in):
 *   @agent         1                    session hosts an agent (stays after pi exits)
 *   @pi_state      working|waiting|asking   (unset when pi is not running)
 *   @pi_since      epoch seconds of the last state change
 *   @pi_goal       session goal (threads extension / pi session name)
 *   @pi_questions  open questions from the threads extension
 *   @pi_session_file  pi session file (pi-sessions marks history entries that are open)
 *
 * No-op outside tmux and in non-TUI modes (rpc/print).
 */

import { execFile, execFileSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

type PiState = "working" | "waiting" | "asking";

export default function (pi: ExtensionAPI) {
	let enabled = false;
	let state: PiState = "waiting";
	let goal = "";
	let questions = 0;
	let queue: Promise<unknown> = Promise.resolve();

	const pane = () => (process.env.TMUX_PANE ? ["-t", process.env.TMUX_PANE] : []);

	function tmux(args: string[]): Promise<void> {
		return new Promise((resolve) => execFile("tmux", args, { timeout: 3000 }, () => resolve()));
	}

	/** set (or unset with value undefined) several options in one tmux call, serialised */
	function setOpts(opts: Record<string, string | undefined>) {
		if (!enabled) return;
		const args: string[] = [];
		for (const [k, v] of Object.entries(opts)) {
			if (args.length) args.push(";");
			args.push("set-option", "-q", ...(v === undefined ? ["-u"] : []), ...pane(), k, ...(v === undefined ? [] : [v]));
		}
		queue = queue.then(() => tmux(args));
	}

	function setState(s: PiState) {
		if (s === state && enabled) return;
		state = s;
		setOpts({ "@pi_state": s, "@pi_since": String(Math.floor(Date.now() / 1000)) });
	}

	function syncGoal(g?: string, q?: number) {
		const ng = (g ?? goal).replace(/\s+/g, " ").trim();
		const nq = q ?? questions;
		if (ng === goal && nq === questions) return;
		goal = ng;
		questions = nq;
		setOpts({ "@pi_goal": goal || undefined, "@pi_questions": String(questions) });
	}

	pi.on("session_start", (_e, ctx) => {
		enabled = !!process.env.TMUX && ctx.mode === "tui";
		if (!enabled) return;
		goal = "";
		questions = -1; // force the first write
		state = "waiting";
		let file: string | undefined;
		try {
			file = ctx.sessionManager.getSessionFile() ?? undefined;
		} catch {
			/* in-memory session */
		}
		setOpts({
			"@agent": "1",
			"@pi_state": "waiting",
			"@pi_since": String(Math.floor(Date.now() / 1000)),
			"@pi_session_file": file,
		});
		let name = "";
		try {
			name = pi.getSessionName() ?? "";
		} catch {
			/* older pi */
		}
		syncGoal(name, 0);
	});

	pi.events.on("threads:state", (data) => {
		const d = (data ?? {}) as { goal?: string; questions?: number };
		syncGoal(d.goal ?? goal, d.questions ?? 0);
	});

	pi.on("agent_start", () => setState("working"));
	pi.on("agent_settled", () => setState("waiting"));

	// mobile-mode's ask_user picker blocks mid-run
	pi.events.on("mobile-mode:waiting", () => setState("asking"));
	pi.events.on("mobile-mode:answered", () => setState("working"));

	pi.on("session_shutdown", () => {
		if (!enabled) return;
		// pi exits (or replaces the runtime -> session_start sets it again): keep @agent
		const args = ["set-option", "-qu", ...pane(), "@pi_state", ";", "set-option", "-q", ...pane(), "@pi_since",
			String(Math.floor(Date.now() / 1000))];
		enabled = false;
		// sync: the process may exit right after this handler
		try {
			execFileSync("tmux", args, { timeout: 2000, stdio: "ignore" });
		} catch {
			/* cosmetic */
		}
	});
}
