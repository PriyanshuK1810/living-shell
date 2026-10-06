pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// VOID SHELL — screenshots (PRD 26.1): full screen, active output and
// region selection through grim/slurp, saved to ~/Pictures/Screenshots,
// optionally copied to the clipboard, confirmed by a toast. If the
// backend is missing the service reports unavailable instead of failing
// silently.
Singleton {
    id: root

    readonly property string home: {
        const h = Quickshell.env("HOME");
        return h !== undefined && h !== null && h !== "" ? h : "/tmp";
    }
    readonly property string dir: root.home + "/Pictures/Screenshots"

    property bool available: false
    property bool busy: false
    property string lastPath: ""
    property string lastError: ""
    property int savedCount: 0
    property bool copyToClipboard: true

    Process {
        id: detect
        command: ["sh", "-c", "command -v grim >/dev/null 2>&1 && command -v slurp >/dev/null 2>&1"]
        running: true
        onExited: exitCode => root.available = exitCode === 0
    }

    Process {
        id: mkdir
        command: ["mkdir", "-p", root.dir]
        running: true
    }

    Process {
        id: shot
        stdout: StdioCollector {
            id: shotOut
        }
        onExited: exitCode => {
            shot.running = false;
            root.busy = false;
            root.handleResult(exitCode, shotOut.text);
        }
    }

    Process {
        id: clipboard
    }

    function timestamp() {
        return Qt.formatDateTime(new Date(), "yyyyMMdd-hhmmss");
    }

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'";
    }

    // mode: "full" | "output" | "region"
    function capture(mode) {
        if (!root.available || root.busy) {
            return false;
        }
        const path = root.dir + "/voidshell-" + root.timestamp() + ".png";
        root.busy = true;
        root.lastError = "";
        if (mode === "region") {
            // slurp runs first; a cancelled selection exits 3 and is not an error.
            shot.command = ["sh", "-c", 'geom=$(slurp) || exit 3; grim -g "$geom" ' + root.shellQuote(path) + ' || exit 4; echo ' + root.shellQuote(path)];
        } else if (mode === "output") {
            const monitor = Hyprland.focusedMonitor !== null ? Hyprland.focusedMonitor.name : "";
            if (monitor === "") {
                root.busy = false;
                return false;
            }
            shot.command = ["sh", "-c", "grim -o " + root.shellQuote(monitor) + " " + root.shellQuote(path) + " || exit 4; echo " + root.shellQuote(path)];
        } else {
            shot.command = ["sh", "-c", "grim " + root.shellQuote(path) + " || exit 4; echo " + root.shellQuote(path)];
        }
        shot.running = true;
        return true;
    }

    function handleResult(exitCode, output) {
        if (exitCode === 3) {
            // User cancelled region selection.
            return;
        }
        if (exitCode !== 0) {
            root.lastError = "Screenshot failed (grim exit " + exitCode + ")";
            ToastService.push("Screenshot failed", root.lastError, "", "danger");
            return;
        }
        const path = String(output || "").trim().split("\n")[0];
        if (path === "") {
            root.lastError = "Screenshot produced no file";
            ToastService.push("Screenshot failed", root.lastError, "", "danger");
            return;
        }
        root.lastPath = path;
        root.savedCount = root.savedCount + 1;
        if (root.copyToClipboard) {
            clipboard.command = ["sh", "-c", "wl-copy < " + root.shellQuote(path)];
            clipboard.startDetached();
        }
        ToastService.push("Screenshot saved", path, "", "success");
    }
}
