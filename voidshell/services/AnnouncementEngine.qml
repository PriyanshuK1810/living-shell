pragma Singleton

import Quickshell
import QtQuick

// VOID SHELL — Living State Island announcement engine (MASTER PROMPT §7).
//
// A *provider* reports state; an *activity* continues; this file decides
// what (if anything) the clock briefly shows and for how long, and
// keeps a bounded queue behind it. Nothing here owns long-lived state:
// an announcement expiring never completes, cancels or hides an
// underlying activity (§7 D).
//
// Rules implemented:
//   priorities      P0 critical … P4 ambient (P4 never interrupts);
//   durations       per category from IslandSettings (control 1.2 s,
//                   track/device 3 s, notification/job/timer 4 s,
//                   workspace 0.8 s — §9 defaults);
//   coalescing      same `key` replaces the queued/presented event and
//                   restarts its dwell, so hammering a volume key shows
//                   one event ending on the final value;
//   queueing        bounded by settings.queueLimit; expired low-priority
//                   events are discarded first, newest relevant wins;
//   suppression     DND, per-feature policy, fullscreen and lock;
//   warm-up         nothing announced before the providers have settled,
//                   so a shell restart never replays a backlog;
//   protection      an event never preempts while the user is interacting.
Singleton {
    id: root

    // Currently presented event or null. `presentedAt` is epoch ms.
    property var current: null
    property var pending: []
    property int serial: 0
    property bool settled: false
    property int droppedCount: 0

    // One-time warm-up gate: providers publish only after this, and any
    // stray early event is dropped rather than replayed (§7 startup).
    Timer {
        interval: 2500
        repeat: false
        running: true
        onTriggered: root.settled = true
    }

    readonly property bool busy: root.current !== null

    // --- policy gates ----------------------------------------------------
    function featureAllows(feature, priority) {
        if (!IslandSettings.enabled) {
            return false;
        }
        const policy = IslandSettings.announcePolicy(feature);
        if (policy === "none") {
            return false;
        }
        if (policy === "important") {
            return priority <= 1;
        }
        return true;
    }

    function fullscreenActive() {
        const ws = HyprlandService.focusedWorkspace;
        return ws !== null && ws !== undefined && ws.hasFullscreen === true;
    }

    // Under "quiet" (default) a fullscreen window suppresses ordinary
    // automatic expansions; "critical" still lets P0 through, "show"
    // presents everything. Explicit user invocation is never blocked.
    function fullscreenAllows(priority) {
        if (!root.fullscreenActive()) {
            return true;
        }
        const mode = IslandSettings.fullscreenPolicy;
        if (mode === "show") {
            return true;
        }
        if (mode === "critical") {
            return priority <= 0;
        }
        return false;
    }

    // DND suppresses ordinary presentation but never a verified privacy
    // or critical condition (§13 F13).
    function dndAllows(category, priority) {
        if (!IslandSettings.dndSuppress || !NotificationService.dnd) {
            return true;
        }
        if (priority <= 1) {
            return true;
        }
        return category !== "notification";
    }

    function durationFor(ev) {
        if (typeof ev.duration === "number" && isFinite(ev.duration) && ev.duration >= 200) {
            return Math.min(20000, Math.round(ev.duration));
        }
        switch (ev.category) {
        case "control": return IslandSettings.durationControl;
        case "track": return IslandSettings.durationTrack;
        case "device": return IslandSettings.durationDevice;
        case "notification": return IslandSettings.durationNotification;
        case "job": return IslandSettings.durationJob;
        case "timer": return IslandSettings.durationTimer;
        case "workspace": return IslandSettings.durationWorkspace;
        default: return IslandSettings.durationDevice;
        }
    }

    // --- entry point -----------------------------------------------------
    // ev: { key, priority, category, feature, title, subtitle, icon, tone,
    //       duration, target, activityKey, dismissible }
    function announce(ev) {
        if (ev === null || ev === undefined || typeof ev !== "object") {
            return false;
        }
        if (!root.settled) {
            root.droppedCount = root.droppedCount + 1;
            return false;
        }
        const priority = (typeof ev.priority === "number" && isFinite(ev.priority))
            ? Math.max(0, Math.min(4, Math.round(ev.priority)))
            : 3;
        const feature = typeof ev.feature === "string" ? ev.feature : "";
        const category = typeof ev.category === "string" ? ev.category : "generic";

        if (priority >= 4) {
            // Ambient only: providers surface this through activity/ambient
            // state instead of interrupting the clock.
            return false;
        }
        if (!root.featureAllows(feature, priority)) {
            return false;
        }
        if (!root.dndAllows(category, priority)) {
            return false;
        }
        if (!root.fullscreenAllows(priority)) {
            return false;
        }

        const title = String(ev.title === undefined ? "" : ev.title).trim();
        if (title === "") {
            return false;
        }

        const key = typeof ev.key === "string" && ev.key !== "" ? ev.key : "";
        const item = {
            id: "ann-" + (root.serial + 1),
            key: key,
            priority: priority,
            category: category,
            feature: feature,
            title: title.slice(0, 96),
            subtitle: String(ev.subtitle === undefined ? "" : ev.subtitle).slice(0, 96),
            icon: typeof ev.icon === "number" ? ev.icon : 0,
            tone: (ev.tone === "warning" || ev.tone === "danger" || ev.tone === "accent" || ev.tone === "success") ? ev.tone : "info",
            target: typeof ev.target === "string" ? ev.target : "",
            activityKey: typeof ev.activityKey === "string" ? ev.activityKey : "",
            duration: root.durationFor({ category: category, duration: ev.duration }),
            dismissible: ev.dismissible !== false,
            at: Date.now()
        };

        // Interaction protection (§7): while the user is driving a
        // control, an ordinary event waits its turn instead of swapping
        // the content under the pointer. P0 conditions may still replace,
        // but only their compact warning region is added (IslandController
        // handles that), never the control being used.
        if (IslandController.interacting && priority > 0) {
            root.enqueue(item, true);
            return true;
        }

        // Coalesce: a repeated key replaces whatever is presented/queued
        // for that key and restarts the dwell — the final value wins.
        if (key !== "") {
            if (root.current !== null && root.current.key === key) {
                item.id = root.current.id;
                root.current = item;
                root.restartDwell(item.duration);
                return true;
            }
            const replaced = root.dropKey(key);
            if (replaced) {
                item.id = "ann-" + (root.serial + 1);
            }
        }

        root.serial = root.serial + 1;
        item.id = "ann-" + root.serial;

        if (root.current === null) {
            root.present(item);
        } else {
            // A higher priority event preempts an ordinary one; an equal
            // or lower one queues behind it.
            if (item.priority < root.current.priority) {
                root.enqueue(root.current, false);
                root.present(item);
            } else {
                root.enqueue(item, false);
            }
        }
        return true;
    }

    function enqueue(item, front) {
        const list = root.pending.slice();
        if (front) {
            list.unshift(item);
        } else {
            list.push(item);
        }
        root.pending = root.trim(list);
    }

    function dropKey(key) {
        if (key === "") {
            return false;
        }
        let found = false;
        const kept = [];
        for (let i = 0; i < root.pending.length; i++) {
            if (root.pending[i].key === key) {
                found = true;
            } else {
                kept.push(root.pending[i]);
            }
        }
        root.pending = kept;
        return found;
    }

    // Bounded queue: expired lowest-priority entries go first, then the
    // lowest-priority entry overall. Activities are never dropped here.
    function trim(list) {
        const limit = Math.max(4, IslandSettings.queueLimit);
        let out = list.slice();
        const now = Date.now();
        out = out.filter(e => now - e.at < Math.max(8000, e.duration * 3));
        while (out.length > limit) {
            let idx = 0;
            for (let i = 1; i < out.length; i++) {
                if (out[i].priority > out[idx].priority) {
                    idx = i;
                }
            }
            out.splice(idx, 1);
            root.droppedCount = root.droppedCount + 1;
        }
        return out;
    }

    function present(item) {
        root.current = item;
        root.restartDwell(item.duration);
    }

    function restartDwell(ms) {
        dwellTimer.stop();
        dwellTimer.interval = Math.max(400, ms);
        dwellTimer.start();
    }

    Timer {
        id: dwellTimer
        repeat: false
        onTriggered: root.advance()
    }

    function advance() {
        root.current = null;
        if (root.pending.length === 0) {
            return;
        }
        let idx = 0;
        for (let i = 1; i < root.pending.length; i++) {
            if (root.pending[i].priority < root.pending[idx].priority) {
                idx = i;
            }
        }
        const next = root.pending[idx];
        root.pending = root.pending.filter((e, i) => i !== idx);
        root.present(next);
    }

    // Explicit dismissal (§17 dismissPresentation) — clears the *display*
    // only. The underlying system condition is untouched.
    function dismiss(id) {
        if (id !== undefined && root.current !== null && root.current.id !== id) {
            root.pending = root.pending.filter(e => e.id !== id);
            return;
        }
        dwellTimer.stop();
        root.current = null;
        root.advance();
    }

    function dismissAll() {
        dwellTimer.stop();
        root.current = null;
        root.pending = [];
    }

    // Called when an interactive surface takes over or the session locks.
    function suspendPresentations() {
        dwellTimer.stop();
        root.current = null;
    }

    // Called when the user finishes interacting: lets one queued ordinary
    // event start presenting if the clock is otherwise idle.
    function flushIfIdle() {
        if (root.current === null && root.pending.length > 0) {
            root.advance();
        }
    }
}
