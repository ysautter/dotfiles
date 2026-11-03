import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd
import QtQuick
import qs.config
import qs.components

// greetd login screen: the lock screen look (components/LockContent.qml)
// authenticating via greetd. Installed to /etc/greetd/quickshell by
// greeter/install.sh and started by /etc/greetd/hyprland.conf.
//   Up/Down or click on the user    switch user
//   click on the session            switch session (/usr/share/wayland-sessions)
// Wallpaper + colours per user come from /var/lib/qs-greeter/<user>
// (written by scripts/greeter-sync.sh in the user's session).
// QS_GREETER_DEMO=1: no greetd, any password is "wrong" (for testing the look).
ShellRoot {
    id: root

    readonly property string stateDir: Quickshell.env("QS_GREETER_STATE") || "/var/cache/qs-greeter"
    readonly property string syncDir: Quickshell.env("QS_GREETER_SYNC") || "/var/lib/qs-greeter"
    readonly property bool demo: Quickshell.env("QS_GREETER_DEMO") === "1"

    // ---- interface used by LockContent ----------------------------------------------
    property string password: ""
    property string error: ""
    property bool busy: false
    readonly property string wallpaper: user ? syncDir + "/" + user.name + "/wallpaper" : ""
    signal failed()

    // ---- users and sessions ----------------------------------------------------------
    property var users: []        // [{ name, shell }]
    property int userIdx: 0
    property var sessions: []     // [{ name, exec }]
    property int sessionIdx: 0
    readonly property var user: users[userIdx] ?? null
    readonly property var session: sessions[sessionIdx] ?? null
    property var last: ({})       // { user, session } of the last login

    onUserChanged: if (user) Colors.dir = syncDir + "/" + user.name

    function cycleUser(step) {
        if (users.length < 2 || busy) return;
        userIdx = (userIdx + step + users.length) % users.length;
        password = "";
        error = "";
    }
    function cycleSession() {
        if (sessions.length < 2 || busy) return;
        sessionIdx = (sessionIdx + 1) % sessions.length;
    }

    function pickDefaults() {
        const u = users.findIndex(x => x.name === last.user);
        if (u >= 0) userIdx = u;
        let s = sessions.findIndex(x => x.name === last.session);
        if (s < 0) s = sessions.findIndex(x => x.exec.indexOf("start-hyprland") >= 0);
        if (s < 0) s = sessions.findIndex(x => x.name === "Hyprland");
        sessionIdx = Math.max(0, s);
    }

    function submit() {
        if (busy || !user || !session) return;
        error = "";
        if (demo) { password = ""; error = "Demo mode"; failed(); return; }
        busy = true;
        Greetd.createSession(user.name);
    }

    // /etc/passwd: real users (uid 1000-59999 with a login shell)
    FileView {
        path: "/etc/passwd"
        onLoaded: {
            const out = [];
            for (const line of text().split("\n")) {
                const f = line.split(":");
                const uid = parseInt(f[2]);
                if (f.length < 7 || uid < 1000 || uid >= 60000 || /(nologin|false)$/.test(f[6])) continue;
                out.push({ name: f[0], shell: f[6] || "/bin/sh" });
            }
            root.users = out;
            root.pickDefaults();
        }
    }

    // wayland session files: "Name<TAB>Exec" (hidden ones skipped)
    Process {
        running: true
        command: ["sh", "-c", "for f in /usr/share/wayland-sessions/*.desktop; do "
            + "awk -F= '/^\\[/{s=($0==\"[Desktop Entry]\")} s&&/^Name=/&&!n{n=$2} s&&/^Exec=/&&!e{sub(/^Exec=/,\"\");e=$0} "
            + "s&&/^(Hidden|NoDisplay)=true/{h=1} END{if(n&&e&&!h)print n\"\\t\"e}' \"$f\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.sessions = text.trim().split("\n").filter(l => l.indexOf("\t") > 0).map(l => {
                    const p = l.split("\t");
                    return { name: p[0], exec: p[1].replace(/ %[a-zA-Z]/g, "") };
                });
                root.pickDefaults();
            }
        }
    }

    FileView {
        id: lastFile
        path: root.stateDir + "/last.json"
        onLoaded: {
            try { root.last = JSON.parse(text()); } catch (e) { root.last = {}; }
            root.pickDefaults();
        }
    }

    Connections {
        target: Greetd
        enabled: !root.demo

        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) Greetd.respond(root.password);
            else if (error) root.error = message;
        }
        function onAuthFailure(message) {
            root.busy = false;
            root.password = "";
            root.error = "Wrong password";
            root.failed();
        }
        function onError(error) {
            root.busy = false;
            root.password = "";
            root.error = "greetd: " + error;
            Greetd.cancelSession();
            root.failed();
        }
        function onReadyToLaunch() {
            lastFile.setText(JSON.stringify({ user: root.user.name, session: root.session.name }));
            // login shell like a TTY login (PATH etc. from /etc/zprofile, /etc/profile).
            // greetd joins the list with spaces and runs it via `sh -c`, so the
            // -c argument must be quoted as one shell word.
            const cmd = "exec " + root.session.exec;
            Greetd.launch([root.user.shell, "-l", "-c", "'" + cmd.replace(/'/g, "'\\''") + "'"],
                          ["XDG_SESSION_TYPE=wayland"], true);
        }
    }

    // ---- windows: full screen on the primary monitor, clock only on the others -----
    readonly property string primary: {
        const host = hostFile.text().trim().split(".")[0].toLowerCase();
        const names = Quickshell.screens.map(s => s.name);
        for (const o of Theme.primaryOutputs[host] ?? [])
            if (names.includes(o)) return o;
        let best = null;
        for (const s of Quickshell.screens)
            if (!best || s.width > best.width) best = s;
        return best?.name ?? "";
    }
    FileView { id: hostFile; path: "/etc/hostname"; blockLoading: true }

    component BottomText: Text {
        color: Colors.fg
        font.family: Theme.iconFont
        font.pixelSize: Theme.fontSize
        property bool clickable: true
        signal clicked()
        MouseArea {
            anchors.fill: parent
            anchors.margins: -Theme.s(6)
            enabled: parent.clickable
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: win
            required property var modelData
            readonly property bool isPrimary: modelData.name === root.primary
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "qs-greeter"
            WlrLayershell.keyboardFocus: isPrimary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: Colors.background

            LockContent {
                lock: root
                showInput: win.isPrimary
                userName: root.user?.name ?? ""
                userSelectable: root.users.length > 1
                onCycleUser: step => root.cycleUser(step)
                extras: [
                    BottomText {
                        text: "\uf108  " + (root.session?.name ?? "no session")
                        clickable: root.sessions.length > 1
                        onClicked: root.cycleSession()
                    },
                    BottomText {
                        text: "\uf2f1"
                        onClicked: Quickshell.execDetached(["systemctl", "reboot"])
                    },
                    BottomText {
                        text: "\uf011"
                        onClicked: Quickshell.execDetached(["systemctl", "poweroff"])
                    }
                ]
            }
        }
    }
}
