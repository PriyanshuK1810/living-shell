pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — state directory owner (PRD 35).
// Every JSON store persists under ~/.local/share/voidshell/. This service
// creates the directory once and tells consumers when it is safe to read
// or write, so no module races a missing path on first launch.
Singleton {
    id: root

    readonly property string home: {
        const h = Quickshell.env("HOME");
        if (h !== undefined && h !== null && h !== "") {
            return h;
        }
        const tmp = Quickshell.env("TMPDIR");
        return tmp !== undefined && tmp !== null && tmp !== "" ? tmp : "/tmp";
    }

    readonly property string dir: root.home + "/.local/share/voidshell"

    // Flip to true once the directory exists (or already did).
    property bool ready: false

    Process {
        id: mkdir
        command: ["mkdir", "-p", root.dir]
        running: true
        onExited: exitCode => {
            root.ready = exitCode === 0;
            if (exitCode !== 0) {
                console.warn("[voidshell] could not create state directory:", root.dir);
            }
        }
    }

    // Absolute path for a file inside the state directory.
    function path(name) {
        return root.dir + "/" + name;
    }
}
