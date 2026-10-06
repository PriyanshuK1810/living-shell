pragma Singleton

import QtQuick
import Quickshell

// VOID SHELL — preview capture coordinator (Shadow Spaces plan §5).
//
// The overview shows real window previews: each one is a Wayland
// screencopy session bound to a Hyprland toplevel. Sessions are cheap
// but not free, so the shell never streams every window at once —
// previews *request* a live slot here and the controller grants at most
// `ManagerSettings.livePreviewBudget` of them at a time:
//
//   granted   → ScreencopyView.live = true, the preview streams.
//   not granted → the preview keeps the single frame its session
//                 captured when it was created (a "last still", held in
//                 memory by the screencopy swapchain — never written to
//               disk, never re-requested on a timer).
//
// Grants are recomputed only when a request is added or removed: there
// is no polling, no timer and no per-frame work in this file. Priority
// decides who keeps a slot when there are more previews than slots —
// the expanded view first, then the focused workspace's card, then the
// rest in card order (§5). Each preview releases its own request when
// it is destroyed, so a closed overview leaves nothing behind.
Singleton {
    id: root

    readonly property int budget: Math.max(0, ManagerSettings.livePreviewBudget)

    // Requested slots: { id, priority, seq }. Reassigned (never mutated)
    // so every binding on `requests` re-evaluates on change.
    property var requests: []
    property int nextSeq: 0

    // Ids currently holding a slot, in grant order.
    readonly property var liveIds: {
        const arr = root.requests.slice();
        arr.sort((a, b) => (a.priority - b.priority) || (a.seq - b.seq));
        const out = [];
        const n = Math.min(root.budget, arr.length);
        for (let i = 0; i < n; i++) {
            out.push(arr[i].id);
        }
        return out;
    }

    function requestLive(id, priority) {
        const key = String(id);
        if (key === "") {
            return;
        }
        const p = (typeof priority === "number" && isFinite(priority)) ? Math.round(priority) : 50;
        const next = root.requests.slice();
        for (let i = 0; i < next.length; i++) {
            if (next[i].id === key) {
                if (next[i].priority !== p) {
                    next[i] = { id: key, priority: p, seq: next[i].seq };
                    root.requests = next;
                }
                return;
            }
        }
        root.nextSeq = root.nextSeq + 1;
        next.push({ id: key, priority: p, seq: root.nextSeq });
        root.requests = next;
    }

    function releaseLive(id) {
        const key = String(id);
        const next = root.requests.filter(r => r.id !== key);
        if (next.length !== root.requests.length) {
            root.requests = next;
        }
    }

    function isLive(id) {
        return root.liveIds.indexOf(String(id)) !== -1;
    }

    // Belt-and-braces reset for the overview closing (every preview also
    // releases itself on destruction, so this is normally a no-op).
    // Also the lock path (plan §18 / acceptance N): locking closes every
    // interactive surface, and this drops any capture request that was
    // still held between surfaces — no still survives a lock.
    function clear() {
        if (root.requests.length !== 0) {
            const n = root.requests.length;
            root.requests = [];
            console.log("[voidshell] preview: released " + n + " capture request(s)");
        }
    }

    Connections {
        target: PopupManager
        function onLockedChanged() {
            if (PopupManager.locked) {
                root.clear();
            }
        }
    }
}
