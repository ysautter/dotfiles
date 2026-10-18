pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Quick-question chat with the pi agent, via `pi --mode rpc`.
// One long-lived pi process (started on first use), no tools, no session file.
// The chosen model + thinking level are remembered in
// ~/.local/state/quickshell/.../pi.json.
Singleton {
    id: root

    // ---- public state --------------------------------------------------------
    property bool open: false
    readonly property bool running: proc.running
    property bool ready: false
    property bool streaming: false
    property string notice: ""                  // last extension notification / error

    property var models: []                     // [{provider, id, name, reasoning, enabled}]
    property var enabledModels: []              // "provider/id" from pi settings
    property string provider: saved.provider
    property string modelId: saved.modelId
    readonly property string modelName: (models.find(m => m.provider === provider && m.id === modelId)?.name) ?? modelId
    property string thinking: saved.thinking
    property var levels: ["off"]

    // chat: role ("user" | "assistant"), text, thinking, error
    readonly property ListModel messages: ListModel {}

    readonly property string systemPrompt:
        "You answer quick questions in a small popup on the user's Linux desktop " +
        "(Arch Linux, Hyprland). Be concise and direct; use short Markdown " +
        "(lists, `code`, fenced code blocks) when it helps. No preamble."

    // ---- public API ------------------------------------------------------------
    function toggle() { open ? hide() : show(); }
    function show() {
        open = true;
        if (!proc.running) start();
    }
    function hide() { open = false; }

    function send(text) {
        text = text.trim();
        if (text === "") return;
        if (!proc.running) start();
        messages.append({ role: "user", text: text, thinking: "", error: "" });
        messages.append({ role: "assistant", text: "", thinking: "", error: "" });
        streaming = true;
        notice = "";
        write({ type: "prompt", message: text });
    }

    function abort() { if (streaming) write({ type: "abort" }); }

    function newChat() {
        abort();
        messages.clear();
        streaming = false;
        notice = "";
        write({ type: "new_session" });
        // new_session resets model + thinking to pi's defaults: re-apply ours
        applyModel();
    }

    function setModel(provider, id) {
        root.provider = provider;
        root.modelId = id;
        saved.provider = provider;
        saved.modelId = id;
        applyModel();
    }

    function setThinking(level) {
        root.thinking = level;
        saved.thinking = level;
        write({ type: "set_thinking_level", level: level });
    }

    function cycleThinking() {
        const i = levels.indexOf(thinking);
        setThinking(levels[(i + 1) % levels.length]);
    }

    // ---- internals ---------------------------------------------------------------
    function start() {
        ready = false;
        proc.running = true;
    }

    function write(obj) {
        if (proc.running) proc.write(JSON.stringify(obj) + "\n");
    }

    property int _reqId: 0
    function request(obj) {
        obj.id = "qs-" + (++_reqId);
        write(obj);
        return obj.id;
    }

    function applyModel() {
        request({ type: "set_model", provider: provider, modelId: modelId });
        // thinking level + available levels are sent once set_model is confirmed
    }

    function lastAssistant() {
        for (let i = messages.count - 1; i >= 0; i--)
            if (messages.get(i).role === "assistant") return i;
        return -1;
    }

    function handle(ev) {
        switch (ev.type) {
        case "response":
            if (!ev.success) {
                notice = `${ev.command}: ${ev.error}`;
                if (ev.command === "prompt") streaming = false;
                return;
            }
            if (ev.command === "get_available_models") {
                const enabled = root.enabledModels;
                models = ev.data.models.map(m => ({
                    provider: m.provider, id: m.id, name: m.name || m.id,
                    reasoning: !!m.reasoning,
                    enabled: enabled.includes(`${m.provider}/${m.id}`)
                })).sort((a, b) => (b.enabled - a.enabled) || a.provider.localeCompare(b.provider) || a.id.localeCompare(b.id));
            } else if (ev.command === "set_model") {
                write({ type: "set_thinking_level", level: thinking });
                request({ type: "get_available_thinking_levels" });
                ready = true;
            } else if (ev.command === "get_available_thinking_levels") {
                levels = ev.data.levels;
                if (!levels.includes(thinking)) setThinking(levels[0]);
            }
            return;

        case "thinking_level_changed":
            root.thinking = ev.level;
            return;

        case "message_update": {
            const u = ev.assistantMessageEvent;
            const i = lastAssistant();
            if (i < 0) return;
            if (u.type === "text_delta")
                messages.setProperty(i, "text", messages.get(i).text + u.delta);
            else if (u.type === "thinking_delta")
                messages.setProperty(i, "thinking", messages.get(i).thinking + u.delta);
            return;
        }

        case "message_end":
            if (ev.message?.role === "assistant" && ev.message.stopReason === "error") {
                const i = lastAssistant();
                let err = ev.message.errorMessage || "error";
                try { err = JSON.parse(err.replace(/^\d+\s*/, "")).error.message; } catch (e) {}
                if (i >= 0) messages.setProperty(i, "error", err);
            }
            return;

        case "agent_settled":
            streaming = false;
            if (ev.aborted) {
                const i = lastAssistant();
                if (i >= 0 && messages.get(i).text === "") messages.setProperty(i, "error", "stopped");
            }
            return;

        case "extension_ui_request":
            if (["select", "confirm", "input", "editor"].includes(ev.method))
                write({ type: "extension_ui_response", id: ev.id, cancelled: true });
            else if (ev.method === "notify" && ev.message)
                notice = ev.message.replace(/^\[[^\]]+\]\s*/, "").split("\n")[0];
            return;
        }
    }

    // read enabledModels from pi's settings for the model picker
    FileView {
        path: Quickshell.env("HOME") + "/.pi/agent/settings.json"
        onLoaded: {
            try { root.enabledModels = JSON.parse(text()).enabledModels ?? []; } catch (e) {}
        }
    }

    FileView {
        id: savedFile
        path: Quickshell.statePath("pi.json")
        watchChanges: false
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter(); }

        JsonAdapter {
            id: saved
            property string provider: "anthropic"
            property string modelId: "claude-sonnet-5-5"
            property string thinking: "off"
        }
    }

    Process {
        id: proc
        command: ["pi", "--mode", "rpc", "--no-session", "--no-tools",
            "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-mcp",
            "--append-system-prompt", root.systemPrompt]
        workingDirectory: Quickshell.env("HOME")
        stdinEnabled: true

        stdout: SplitParser {
            onRead: line => {
                try { root.handle(JSON.parse(line)); } catch (e) {}
            }
        }

        onStarted: {
            root.request({ type: "get_available_models" });
            root.applyModel();
        }
        onExited: (code, status) => {
            root.ready = false;
            root.streaming = false;
            if (code !== 0) root.notice = `pi exited (${code})`;
        }
    }

    IpcHandler {
        target: "pi"
        function toggle(): void { root.toggle(); }
        function open(): void { root.show(); }
        function close(): void { root.hide(); }
        function ask(question: string): void { root.show(); root.send(question); }
    }
}
