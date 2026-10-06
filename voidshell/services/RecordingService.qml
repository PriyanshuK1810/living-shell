pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// VOID SHELL — screen recording (PRD 26.2): start/stop, elapsed time,
// output path and a completion toast. The backend (wf-recorder) is
// detected at startup; without it `available` is false and every entry
// point reports that honestly instead of pretending to record.
// Stop uses SIGINT so the encoder finalizes the file cleanly.
Singleton {
    id: root

    readonly property string home: {
        const h = Quickshell.env("HOME");
        return h !== undefined && h !== null && h !== "" ? h : "/tmp";
    }
    readonly property string dir: root.home + "/Videos"

    property bool available: false
    property string backend: ""
    property bool recording: false
    property string state: "idle" // idle | starting | recording | error
    property string outputPath: ""
    property string lastOutput: ""
    property string lastError: ""
    property int completedCount: 0
    property real startedAt: 0
    property real elapsedSeconds: 0

    readonly property string elapsedLabel: {
        const total = Math.floor(root.elapsedSeconds);
        const hours = Math.floor(total / 3600);
        const minutes = Math.floor((total % 3600) / 60);
        const seconds = total % 60;
        const pad = n => (n < 10 ? "0" + n : String(n));
        if (hours > 0) {
            return hours + ":" + pad(minutes) + ":" + pad(seconds);
        }
        return minutes + ":" + pad(seconds);
    }

    Process {
        id: detect
        command: ["sh", "-c", "command -v wf-recorder || true"]
        running: true
        stdout: StdioCollector {
            id: detectOut
        }
        onExited: () => {
            const path = detectOut.text.trim();
            if (path !== "") {
                root.backend = path;
                root.available = true;
            }
        }
    }

    Process {
        id: mkdir
        command: ["mkdir", "-p", root.dir]
        running: true
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.recording
        onTriggered: root.elapsedSeconds = (Date.now() - root.startedAt) / 1000
    }

    Process {
        id: recorder
        stdout: StdioCollector {
            id: recorderOut
        }
        stderr: StdioCollector {
            id: recorderErr
        }
        onExited: exitCode => {
            recorder.running = false;
            root.finish(exitCode, recorderErr.text);
        }
    }

    Process {
        id: slurpProc
        stdout: StdioCollector {
            id: slurpOut
        }
        onExited: exitCode => {
            slurpProc.running = false;
            if (exitCode === 0) {
                const geometry = slurpOut.text.trim();
                if (geometry !== "") {
                    root.launch(["-g", geometry]);
                }
            }
        }
    }

    function timestamp() {
        return Qt.formatDateTime(new Date(), "yyyyMMdd-hhmmss");
    }

    // mode: "full" | "output" | "region"
    function start(mode) {
        if (!root.available || root.recording) {
            if (!root.available) {
                ToastService.push("Screen recording unavailable", "wf-recorder is not installed", "", "danger");
            }
            return false;
        }
        if (mode === "region") {
            state = "starting";
            slurpProc.running = true;
            return true;
        }
        const args = [];
        if (mode === "output") {
            const monitor = Hyprland.focusedMonitor !== null ? Hyprland.focusedMonitor.name : "";
            if (monitor !== "") {
                args.push("-o", monitor);
            }
        }
        return root.launch(args);
    }

    function launch(extraArgs) {
        if (!root.available || root.recording) {
            return false;
        }
        const path = root.dir + "/voidshell-" + root.timestamp() + ".mp4";
        const cmd = [root.backend, "-f", path];
        for (let i = 0; i < extraArgs.length; i++) {
            cmd.push(extraArgs[i]);
        }
        root.outputPath = path;
        root.lastError = "";
        root.startedAt = Date.now();
        root.elapsedSeconds = 0;
        root.recording = true;
        root.state = "recording";
        recorder.command = cmd;
        recorder.running = true;
        return true;
    }

    function stop() {
        if (!root.recording) {
            return false;
        }
        // SIGINT lets wf-recorder finalize the container.
        recorder.signal(2);
        return true;
    }

    function toggle(mode) {
        if (root.recording) {
            return root.stop();
        }
        return root.start(mode);
    }

    function finish(exitCode, stderrText) {
        const wasRecording = root.recording;
        root.recording = false;
        root.elapsedSeconds = 0;
        if (!wasRecording) {
            return;
        }
        if (exitCode === 0) {
            root.state = "idle";
            root.lastOutput = root.outputPath;
            root.completedCount = root.completedCount + 1;
            ToastService.push("Recording saved", root.outputPath, "", "success");
            return;
        }
        root.state = "error";
        const detail = String(stderrText || "").trim().split("\n")[0];
        root.lastError = detail !== "" ? detail : ("wf-recorder exited with " + exitCode);
        ToastService.push("Recording stopped", root.lastError, "", "danger");
    }
}
