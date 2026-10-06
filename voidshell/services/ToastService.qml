pragma Singleton

import Quickshell
import QtQuick

// VOID SHELL — toast bus (PRD 15.3, 26).
// One queue feeds the bottom-right toast layer: notification arrivals and
// system confirmations (screenshot saved, recording saved) all publish
// here, so the toast surface has a single owner and the top bar never
// changes shape to announce anything.
Singleton {
    id: root

    // { id, title, body, icon, tone, at }
    property var current: null
    property int serial: 0
    property int shownCount: 0

    // tone: "info" | "success" | "danger"
    function push(title, body, icon, tone) {
        root.serial = root.serial + 1;
        root.current = {
            id: root.serial,
            title: String(title || ""),
            body: String(body || ""),
            icon: String(icon || ""),
            tone: String(tone || "info"),
            at: Date.now()
        };
        root.shownCount = root.shownCount + 1;
    }

    function dismiss() {
        root.current = null;
    }
}
