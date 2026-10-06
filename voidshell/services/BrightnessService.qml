pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — backlight brightness (PRD 34.7). Availability is probed
// once at startup; desktops without a backlight report unavailable and
// the quick-settings slider disables itself with an explanation.
// Reads/writes go through brightnessctl (udev-permitted on this system);
// no subprocess runs per frame.
Singleton {
    id: root

    property bool available: false
    property real level: 0
    property string deviceName: ""
    readonly property int percent: Math.round(root.level * 100)

    // While a panel is open we re-probe occasionally so external changes
    // (Fn keys) stay in sync. Idle shells do no work.
    property bool active: false

    // Debounced write target; -1 means nothing pending.
    property int requestedPercent: -1

    Process {
        id: probe
        command: ["sh", "-c", "command -v brightnessctl >/dev/null 2>&1 || exit 4; brightnessctl -m 2>/dev/null | head -n 1"]
        stdout: StdioCollector {
            id: probeOut
        }
        onExited: exitCode => root.parseProbe(exitCode, probeOut.text)
    }

    Process {
        id: setter
        stdout: StdioCollector {
            id: setterOut
        }
        onExited: () => {
            setter.running = false;
            if (root.requestedPercent >= 0) {
                root.applyPending();
            } else {
                root.probeNow();
            }
        }
    }

    Timer {
        id: debounce
        interval: 90
        onTriggered: root.applyPending()
    }

    Timer {
        interval: 1500
        repeat: true
        running: root.active && root.available
        onTriggered: root.probeNow()
    }

    onActiveChanged: {
        if (root.active) {
            root.probeNow();
        }
    }

    // One probe at startup so `available`/`level` are real before the
    // quick-settings panel is ever opened (no "No backlight" flash).
    Component.onCompleted: probeNow()

    function probeNow() {
        if (!probe.running) {
            probe.running = true;
        }
    }

    function parseProbe(exitCode, output) {
        if (exitCode !== 0) {
            root.available = false;
            return;
        }
        const line = String(output || "").split("\n")[0];
        const parts = line.split(",");
        // Machine-readable form: device,class,current,percent,max
        if (parts.length < 5) {
            root.available = false;
            return;
        }
        const current = Number(parts[2]);
        const maximum = Number(parts[4]);
        if (!(maximum > 0) || !(current >= 0)) {
            root.available = false;
            return;
        }
        root.available = true;
        root.deviceName = parts[0];
        root.level = Math.max(0, Math.min(1, current / maximum));
    }

    function applyPending() {
        if (root.requestedPercent < 0) {
            return;
        }
        if (setter.running) {
            return; // onExited re-applies the newest request
        }
        const pct = root.requestedPercent;
        root.requestedPercent = -1;
        setter.command = ["brightnessctl", "-q", "set", pct + "%"];
        setter.running = true;
    }

    function setLevel(v) {
        if (!root.available) {
            return;
        }
        const pct = Math.round(Math.max(0, Math.min(1, v)) * 100);
        if (pct === root.percent && root.requestedPercent < 0) {
            return;
        }
        // Optimistic update; the probe after the write confirms reality.
        root.level = pct / 100;
        root.requestedPercent = pct;
        debounce.restart();
    }
}
