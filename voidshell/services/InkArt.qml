pragma Singleton

import QtQuick

// VOID SHELL — session-random ink artwork for the popup panels.
// Fisher-Yates shuffle of the five bundled dashboard assets at shell
// start, dealt round-robin over the panel keys: every surface gets its
// own image (the first five distinct), the mapping stays stable for
// the whole session and re-rolls whenever the shell restarts.
// The dashboard is not in the pool — its five cards keep their
// hand-curated framing (OverviewTab textureFocusX/Y/zoom).
QtObject {
    readonly property var pool: [
        Qt.resolvedUrl("../assets/dashboard/ink-1.jpg"),
        Qt.resolvedUrl("../assets/dashboard/ink-2.jpg"),
        Qt.resolvedUrl("../assets/dashboard/ink-3.jpg"),
        Qt.resolvedUrl("../assets/dashboard/ink-4.jpg"),
        Qt.resolvedUrl("../assets/dashboard/ink-5.jpg")
    ]

    readonly property var keys: [
        "quickSettings", "launcher", "notifications", "media",
        "power", "taskManager", "overview", "wifiDialog", "deviceMenu"
    ]

    readonly property var assigned: {
        const order = [0, 1, 2, 3, 4];
        for (let i = order.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            const t = order[i];
            order[i] = order[j];
            order[j] = t;
        }
        const map = {};
        for (let i = 0; i < keys.length; i++)
            map[keys[i]] = pool[order[i % order.length]];
        return map;
    }

    // Artwork for a panel key; unknown keys fall back to pool[0].
    function sourceFor(key) {
        return assigned[key] || pool[0];
    }
}
