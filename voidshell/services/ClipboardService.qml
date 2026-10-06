pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — clipboard history for the Island (MASTER PROMPT F24).
//
// Adapter only: the history already exists on this machine, collected by
// the autostarted `wl-paste --watch cliphist store` line in hyprland.lua.
// This file reads it (cliphist list), copies one entry back (decode |
// wl-copy) and deletes entries the user drops. It never invents content
// and never announces a clipboard value — announce policy for `clipboard`
// defaults to "none", and even when enabled only the *fact* of a change
// is announceable, never the text (§13 privacy).
//
// Every id crossing into a command is validated as digits first, so no
// clipboard content can ever become part of a command line.
Singleton {
    id: root

    property bool available: false
    property bool loaded: false
    property var entries: []
    property string lastError: ""
    property int serial: 0

    readonly property int count: root.entries.length

    Component.onCompleted: root.probe()

    function probe() {
        detect.running = true;
    }

    Process {
        id: detect
        command: ["sh", "-c", "command -v cliphist && command -v wl-copy"]
        running: false
        onExited: exitCode => {
            detect.running = false;
            root.available = exitCode === 0;
            if (root.available) {
                root.refresh();
            } else {
                root.entries = [];
                root.loaded = true;
            }
        }
    }

    Process {
        id: lister
        stdout: StdioCollector {
            id: listOut
        }
        stderr: StdioCollector {
            id: listErr
        }
        onExited: exitCode => {
            lister.running = false;
            if (exitCode !== 0) {
                // An empty history is a normal exit; only a real failure
                // is reported, and never as a success.
                root.lastError = String(listErr.text || "").trim().split("\n")[0];
                root.loaded = true;
                root.serial = root.serial + 1;
                return;
            }
            root.parse(listOut.text);
        }
    }

    function refresh() {
        if (!root.available || lister.running) {
            return false;
        }
        lister.command = ["cliphist", "list"];
        lister.running = true;
        return true;
    }

    // Newest first, bounded by the configured retention, one preview line
    // per entry with control characters stripped (a clipboard value must
    // never be able to reshape the row it is rendered in).
    function parse(text) {
        const limit = Math.max(5, IslandSettings.clipboardMaxEntries);
        const raw = String(text || "").split("\n");
        const out = [];
        for (let i = 0; i < raw.length && out.length < limit; i++) {
            const line = raw[i];
            if (line.trim() === "") {
                continue;
            }
            const tab = line.indexOf("\t");
            const id = (tab === -1 ? line : line.slice(0, tab)).trim();
            if (!/^[0-9]+$/.test(id)) {
                continue;
            }
            let preview = tab === -1 ? "" : line.slice(tab + 1);
            preview = preview.replace(/[\u0000-\u001f\u007f]/g, " ").trim();
            out.push({ id: id, preview: preview.slice(0, 200) });
        }
        // cliphist list is oldest-first; the island shows the newest first.
        out.reverse();
        root.entries = out;
        root.loaded = true;
        root.lastError = "";
        root.serial = root.serial + 1;
    }

    Process {
        id: copier
        stderr: StdioCollector {
            id: copyErr
        }
        onExited: exitCode => {
            copier.running = false;
            if (exitCode === 0) {
                root.lastError = "";
                AnnouncementEngine.announce({
                    key: "clipboard",
                    priority: 3,
                    category: "control",
                    feature: "clipboard",
                    title: "Copied to clipboard",
                    subtitle: "",
                    icon: 0xF00C,
                    tone: "success"
                });
            } else {
                root.lastError = String(copyErr.text || "").trim().split("\n")[0];
            }
        }
    }

    function copyId(id) {
        const sid = String(id === undefined ? "" : id).trim();
        if (!root.available || !/^[0-9]+$/.test(sid)) {
            return false;
        }
        if (copier.running) {
            return false;
        }
        // The validated numeric id is the only value interpolated, and it
        // is fed on stdin so it never reaches a shell as syntax.
        copier.command = ["sh", "-c",
            "cliphist decode \"$(printf '%s' \"" + sid + "\")\" | wl-copy"];
        copier.running = true;
        return true;
    }

    Process {
        id: deleter
        onExited: exitCode => {
            deleter.running = false;
            if (exitCode === 0) {
                root.refresh();
            }
        }
    }

    function deleteId(id) {
        const sid = String(id === undefined ? "" : id).trim();
        if (!root.available || !/^[0-9]+$/.test(sid)) {
            return false;
        }
        if (deleter.running) {
            return false;
        }
        deleter.command = ["sh", "-c", "printf '%s\\n' \"" + sid + "\" | cliphist delete"];
        deleter.running = true;
        return true;
    }

    Process {
        id: clearer
        onExited: exitCode => {
            clearer.running = false;
            if (exitCode === 0) {
                root.entries = [];
                root.serial = root.serial + 1;
                AnnouncementEngine.announce({
                    key: "clipboard",
                    priority: 3,
                    category: "control",
                    feature: "clipboard",
                    title: "Clipboard history cleared",
                    subtitle: "",
                    icon: 0xF00D,
                    tone: "info"
                });
            }
        }
    }

    function clear() {
        if (!root.available || clearer.running) {
            return false;
        }
        clearer.command = ["cliphist", "wipe"];
        clearer.running = true;
        return true;
    }
}
