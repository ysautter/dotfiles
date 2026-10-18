import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import QtQuick
import qs.config
import qs.components
import qs.services

// Lock screen (ext-session-lock) authenticating via PAM (/etc/pam.d/hyprlock).
//   qs ipc call lock lock      lock now
//   qs ipc call lock preview   show what it looks like (normal window, Esc closes)
// If quickshell crashes while locked, Hyprland allows a new lock client
// (misc:allow_session_lock_restore in hypr/quickshell.conf): run `hyprlock`
// from a TTY (Ctrl+Alt+F3) to unlock.
Scope {
    id: root

    property string password: ""
    property string error: ""
    property bool busy: pam.active
    property string wallpaper: ""
    property bool previewOpen: false
    signal failed()

    function lock() {
        if (sessionLock.locked) return;
        password = "";
        error = "";
        wallProc.running = true;
        sessionLock.locked = true;
    }

    function submit() {
        if (password === "" || pam.active) return;
        error = "";
        pam.start();
    }

    Component.onCompleted: Session.lockHandler = lock

    Process {
        id: wallProc
        command: ["sh", "-c", "awww query 2>/dev/null | sed -n 's/.*image: //p' | head -1"]
        stdout: StdioCollector { onStreamFinished: root.wallpaper = text.trim() }
    }

    PamContext {
        id: pam
        config: "hyprlock"
        onResponseRequiredChanged: {
            if (responseRequired) respond(root.password);
        }
        onCompleted: result => {
            if (result === PamResult.Success) {
                sessionLock.locked = false;
                root.password = "";
                root.error = "";
            } else {
                root.password = "";
                root.error = result === PamResult.MaxTries ? "Too many attempts" : "Wrong password";
                root.failed();
            }
        }
        onError: err => {
            root.password = "";
            root.error = "PAM error: " + PamError.toString(err);
            root.failed();
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: false

        WlSessionLockSurface {
            color: Colors.background
            LockContent { lock: root }
        }
    }

    // ---- harmless preview: a normal overlay window, no session lock ---------------
    LazyLoader {
        active: root.previewOpen
        PanelWindow {
            screen: HyprState.focusedScreen
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"
            LockContent {
                lock: root
                preview: true
                focus: true
                Keys.onPressed: root.previewOpen = false
                MouseArea { anchors.fill: parent; onClicked: root.previewOpen = false }
            }
        }
    }

    IpcHandler {
        target: "lock"
        function lock(): void { root.lock(); }
        function preview(): void {
            if (!root.previewOpen) wallProc.running = true;
            root.previewOpen = !root.previewOpen;
        }
    }

    // ---- idle: lock after N minutes (presentation mode inhibits this) -----------------
    IdleMonitor {
        enabled: Theme.idleLockMinutes > 0 && !sessionLock.locked
        timeout: Theme.idleLockMinutes * 60
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) root.lock()
    }
}
