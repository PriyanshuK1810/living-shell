pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — "keep the screen awake" control (MASTER PROMPT F19).
//
// Runs one `systemd-inhibit --what=idle` holder while it is on and kills
// it again when it is off: the inhibitor is the real state, so the shell
// never claims wakefulness it is not holding. The child dies with the
// shell, so a crashed or restarted shell can never leave an orphan
// inhibitor behind (§12 no stray daemons).
//
// No package is required beyond systemd itself; when the binary is absent
// every entry point reports unavailable instead of pretending.
Singleton {
    id: root

    property bool available: false
    property bool active: false
    property string reason: ""
    property real startedAt: 0
    property string lastError: ""

    property real now: Date.now()
    readonly property int elapsedSeconds: root.active ? Math.floor((root.now - root.startedAt) / 1000) : 0
    readonly property string elapsedLabel: {
        const total = root.elapsedSeconds;
        const h = Math.floor(total / 3600);
        const m = Math.floor((total % 3600) / 60);
        const pad = n => (n < 10 ? "0" + n : String(n));
        return h > 0 ? (h + ":" + pad(m)) : (m + "m");
    }

    Component.onCompleted: detect.running = true

    Process {
        id: detect
        command: ["sh", "-c", "command -v systemd-inhibit"]
        running: false
        onExited: exitCode => {
            detect.running = false;
            root.available = exitCode === 0;
        }
    }

    Process {
        id: holder
        stderr: StdioCollector {
            id: holderErr
        }
        onExited: exitCode => {
            // Any exit while we believed we were holding it is a release
            // we did not ask for — report it, never keep a stale "on".
            if (root.active) {
                root.active = false;
                root.reason = "";
                if (exitCode !== 0) {
                    root.lastError = String(holderErr.text || "").trim().split("\n")[0];
                    ToastService.push("Keep awake stopped", root.lastError, "", "danger");
                }
            }
            holder.running = false;
        }
    }

    Timer {
        interval: 15000
        repeat: true
        running: root.active
        onTriggered: root.now = Date.now()
    }

    function start(why) {
        if (!root.available || root.active) {
            if (!root.available) {
                ToastService.push("Keep awake unavailable", "systemd-inhibit is not installed", "", "danger");
            }
            return false;
        }
        const label = String(why === undefined || why === null ? "" : why).trim().slice(0, 60);
        root.lastError = "";
        holder.command = ["systemd-inhibit",
            "--what=idle",
            "--who=VOID SHELL",
            "--why=" + (label !== "" ? label : "Island keep-awake"),
            "sleep", "infinity"];
        holder.running = true;
        root.active = true;
        root.reason = label !== "" ? label : "Island keep-awake";
        root.startedAt = Date.now();
        AnnouncementEngine.announce({
            key: "keepAwake",
            priority: 1,
            category: "control",
            feature: "keepAwake",
            title: "Keeping the screen awake",
            subtitle: root.reason,
            icon: 0xF017,
            tone: "accent"
        });
        return true;
    }

    function stop() {
        if (!root.active) {
            return false;
        }
        holder.signal(15); // SIGTERM: systemd-inhibit exits with its child
        root.active = false;
        root.reason = "";
        AnnouncementEngine.announce({
            key: "keepAwake",
            priority: 1,
            category: "control",
            feature: "keepAwake",
            title: "Screen may sleep again",
            subtitle: "",
            icon: 0xF017,
            tone: "info"
        });
        return true;
    }

    function toggle(why) {
        if (root.active) {
            return root.stop();
        }
        return root.start(why);
    }
}
