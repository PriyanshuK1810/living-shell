pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — active keyboard layout (PRD 17.5, 25).
// One owner for `hyprctl devices` keymap parsing: quick settings reads it
// from the advanced section and the lock screen shows it as a language chip.
// The probe only runs when a view asks (PRD 36) — never on a timer.
Singleton {
    id: root

    property string layout: ""
    property bool probed: false

    readonly property bool available: root.layout !== ""

    Process {
        id: probe
        command: ["hyprctl", "devices"]
        running: false
        stdout: StdioCollector {
            id: probeOut
            onStreamFinished: root.parse(probeOut.text)
        }
        onExited: root.probed = true
    }

    function refresh() {
        if (!probe.running) {
            probe.running = true;
        }
    }

    function parse(content) {
        const lines = String(content).split("\n");
        let fallback = "";
        let main = "";
        for (let i = 0; i < lines.length; i++) {
            const m = lines[i].match(/active keymap:\s*(.+)/);
            if (m && fallback === "") {
                fallback = m[1].trim();
            }
        }
        // Pair each "main: yes" flag with the nearest keymap above it: the
        // keymap line precedes the flag inside each keyboard block.
        for (let i = 0; i < lines.length; i++) {
            if (lines[i].indexOf("main: yes") !== -1) {
                for (let j = i - 1; j >= 0; j--) {
                    const km = lines[j].match(/active keymap:\s*(.+)/);
                    if (km) {
                        main = km[1].trim();
                        break;
                    }
                }
            }
        }
        root.layout = main !== "" ? main : fallback;
    }
}
