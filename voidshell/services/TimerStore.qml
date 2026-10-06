pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — named timers + stopwatch (MASTER PROMPT §16 F16).
//
// The focus/break countdown is *not* reimplemented here: FocusTimer is
// the existing Productivity timer and stays the single source for it
// (§16 "Reuse the existing Productivity timer if present"). This store
// adds what it does not have — several named countdowns and a stopwatch
// — and mirrors every one of them into ActivityStore so the clock, the
// Mini Island and the activity stack all read the same object.
//
// Time source:
//   * countdowns are duration-based and stored as an absolute end time,
//     so suspended time counts (§16 "default countdown behavior includes
//     suspended time") and a paused timer keeps its remaining seconds;
//   * a wall-clock step is detected per tick (> 2 s in one second) and
//     the end time is re-anchored, so moving the clock forward or back
//     cannot silently skip or duplicate a completion;
//   * the stopwatch accumulates from real timestamps, so pausing costs
//     nothing and restarting continues exactly where it stopped.
//
// State is persisted (`island-timers.json`) with an `announced` flag, so
// a restart reconciles instead of announcing a completion twice.
Singleton {
    id: root

    property var timers: []
    property bool loaded: false

    // Stopwatch.
    property bool swRunning: false
    property real swAccumulatedMs: 0
    property real swStartedAt: 0
    property var swLaps: []
    property bool swRunningConfirmed: false

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    readonly property real now: clock.date.getTime()

    readonly property real swElapsedMs: root.swRunning
        ? root.swAccumulatedMs + Math.max(0, root.now - root.swStartedAt)
        : root.swAccumulatedMs

    readonly property string swLabel: root.fmt(root.swElapsedMs)

    readonly property int count: root.timers.length

    function fmt(ms) {
        const total = Math.max(0, Math.floor(ms / 1000));
        const h = Math.floor(total / 3600);
        const m = Math.floor((total % 3600) / 60);
        const s = total % 60;
        const pad = n => (n < 10 ? "0" + n : String(n));
        return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : pad(m) + ":" + pad(s);
    }

    // --- countdown bookkeeping -------------------------------------------
    function remainingOf(t) {
        if (!t.running) {
            return Math.max(0, t.heldSeconds);
        }
        return Math.max(0, Math.round((t.endsAt - root.now) / 1000));
    }

    function progressOf(t) {
        if (t.durationSeconds <= 0) {
            return 0;
        }
        return Math.max(0, Math.min(1, 1 - root.remainingOf(t) / t.durationSeconds));
    }

    // Wall-clock guard: one tick must move the countdown by ~1 s. A jump
    // larger than 2 s means the clock changed, so re-anchor the end time
    // around the remaining duration we had.
    property real lastTickAt: 0
    property real lastRemaining: -1

    onNowChanged: {
        if (root.lastTickAt === 0) {
            root.lastTickAt = root.now;
            return;
        }
        const wallStep = Math.abs(root.now - root.lastTickAt);
        root.lastTickAt = root.now;
        if (wallStep <= 2000) {
            root.reconcile();
            return;
        }
        root.reanchor();
        root.reconcile();
    }

    function reanchor() {
        const list = root.timers.slice();
        let changed = false;
        for (let i = 0; i < list.length; i++) {
            const t = list[i];
            if (!t.running) {
                continue;
            }
            const held = root.lastRemaining >= 0 ? root.lastRemaining : t.heldSeconds;
            list[i] = Object.assign({}, t, {
                endsAt: root.now + Math.max(0, held) * 1000
            });
            changed = true;
        }
        if (changed) {
            root.timers = list;
            root.save();
        }
    }

    // Runs every second: publishes/finishes activities exactly on the
    // completion edge, once.
    function reconcile() {
        if (root.timers.length === 0) {
            return;
        }
        const list = root.timers.slice();
        let changed = false;
        for (let i = 0; i < list.length; i++) {
            const t = list[i];
            const remaining = root.remainingOf(t);
            root.lastRemaining = remaining;
            if (t.running && remaining === 0) {
                list[i] = Object.assign({}, t, {
                    running: false,
                    heldSeconds: 0,
                    endsAt: 0,
                    completed: t.completed + 1,
                    announced: t.announced
                });
                changed = true;
                if (!t.announced) {
                    list[i].announced = true;
                    root.completeTimer(list[i]);
                }
            }
        }
        if (changed) {
            root.timers = list;
            root.save();
        }
    }

    function completeTimer(t) {
        ActivityStore.finish({
            sourceId: "voidshell",
            activityId: "timer-" + t.id,
            sequence: Date.now(),
            activityType: "timer",
            state: "success",
            title: t.label + " complete",
            subtitle: root.fmt(t.durationSeconds * 1000),
            iconReference: "0xF017",
            progressMode: "none",
            dashboardTarget: "productivity"
        });
        AnnouncementEngine.announce({
            key: "timer",
            priority: 1,
            category: "timer",
            feature: "timers",
            title: t.label + " complete",
            subtitle: root.fmt(t.durationSeconds * 1000),
            icon: 0xF017,
            tone: "success",
            target: "dashboard:productivity"
        });
    }

    function nextId() {
        let n = 1;
        const used = {};
        for (let i = 0; i < root.timers.length; i++) {
            used[root.timers[i].id] = true;
        }
        while (used["t" + n] !== undefined) {
            n = n + 1;
        }
        return "t" + n;
    }

    function addTimer(label, totalSeconds) {
        const secs = Math.max(1, Math.min(86400, Math.round(totalSeconds)));
        const id = root.nextId();
        const t = {
            id: id,
            label: String(label || "Timer").slice(0, 40),
            durationSeconds: secs,
            endsAt: 0,
            heldSeconds: secs,
            running: false,
            completed: 0,
            announced: false,
            createdAt: Date.now()
        };
        root.timers = root.timers.concat([t]);
        root.save();
        root.syncActivity(t);
        return id;
    }

    function removeTimer(id) {
        root.timers = root.timers.filter(t => t.id !== id);
        root.save();
        ActivityStore.remove("timers/timer-" + id);
    }

    function byId(id) {
        for (let i = 0; i < root.timers.length; i++) {
            if (root.timers[i].id === id) {
                return root.timers[i];
            }
        }
        return null;
    }

    function mutate(id, fn) {
        const list = root.timers.slice();
        let changed = false;
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === id) {
                list[i] = fn(Object.assign({}, list[i]));
                changed = true;
            }
        }
        if (changed) {
            root.timers = list;
            root.save();
            const t = root.byId(id);
            if (t !== null) {
                root.syncActivity(t);
            }
        }
    }

    function startTimer(id) {
        root.mutate(id, t => {
            if (t.running) {
                return t;
            }
            const held = t.heldSeconds > 0 ? t.heldSeconds : t.durationSeconds;
            t.heldSeconds = held;
            t.endsAt = Date.now() + held * 1000;
            t.running = true;
            t.announced = false;
            return t;
        });
    }

    function pauseTimer(id) {
        root.mutate(id, t => {
            if (!t.running) {
                return t;
            }
            t.heldSeconds = root.remainingOf(t);
            t.running = false;
            t.endsAt = 0;
            return t;
        });
    }

    function resetTimer(id) {
        root.mutate(id, t => {
            t.running = false;
            t.endsAt = 0;
            t.heldSeconds = t.durationSeconds;
            t.announced = false;
            return t;
        });
    }

    function finishTimer(id) {
        const before = root.byId(id);
        if (before === null || before.announced) {
            root.mutate(id, t => {
                t.running = false;
                t.endsAt = 0;
                t.heldSeconds = 0;
                return t;
            });
            return;
        }
        root.mutate(id, t => {
            t.running = false;
            t.endsAt = 0;
            t.heldSeconds = 0;
            t.announced = true;
            return t;
        });
        const after = root.byId(id);
        if (after !== null) {
            root.completeTimer(after);
        }
    }

    function toggleTimer(id) {
        const t = root.byId(id);
        if (t === null) {
            return;
        }
        if (t.running) {
            root.pauseTimer(id);
        } else {
            root.startTimer(id);
        }
    }

    // --- stopwatch --------------------------------------------------------
    function swStart() {
        if (root.swRunning) {
            return;
        }
        root.swStartedAt = Date.now();
        root.swRunning = true;
        root.syncStopwatch();
        root.save();
    }

    function swStop() {
        if (!root.swRunning) {
            return;
        }
        root.swAccumulatedMs = root.swElapsedMs;
        root.swRunning = false;
        root.swStartedAt = 0;
        root.syncStopwatch();
        root.save();
    }

    function swToggle() {
        if (root.swRunning) {
            root.swStop();
        } else {
            root.swStart();
        }
    }

    // Reset is confirmed by the caller when the stopwatch is running
    // (§16 "Confirm resetting an actively running stopwatch").
    function swReset() {
        root.swRunning = false;
        root.swStartedAt = 0;
        root.swAccumulatedMs = 0;
        root.swLaps = [];
        root.syncStopwatch();
        root.save();
    }

    function swLap() {
        if (!root.swRunning) {
            return;
        }
        const total = root.swElapsedMs;
        const prev = root.swLaps.length > 0 ? root.swLaps[root.swLaps.length - 1].total : 0;
        root.swLaps = root.swLaps.concat([{ total: total, split: total - prev }]);
        root.save();
    }

    // --- activity mirroring ----------------------------------------------
    // Every surface shows the same object: the clock's ambient line, the
    // Mini Island card and the activity stack all read these activities,
    // and the live label comes from this store so no per-second writes
    // are needed (§19 "prefer events over frequent polling").
    function syncFocusActivity() {
        const active = FocusTimer.running;
        const remaining = FocusTimer.remaining;
        if (!active && remaining <= 0 && FocusTimer.completedSessions === 0) {
            return;
        }
        ActivityStore.publish({
            sourceId: "voidshell",
            activityId: "focus",
            sequence: Date.now(),
            activityType: "timer",
            state: active ? "working" : "paused",
            title: FocusTimer.mode === "focus" ? "Focus" : "Break",
            subtitle: FocusTimer.remainingLabel,
            iconReference: "0xF017",
            progressMode: "determinate",
            progressValue: Math.max(0, Math.min(100, FocusTimer.progress * 100)),
            estimatedRemainingSeconds: remaining,
            dashboardTarget: "productivity",
            registeredActions: [
                { id: "toggle", label: active ? "Pause" : "Resume", route: "dashboard:productivity" },
                { id: "open", label: "View details", route: "dashboard:productivity" }
            ]
        });
    }

    function syncActivity(t) {
        const remaining = root.remainingOf(t);
        ActivityStore.publish({
            sourceId: "voidshell",
            activityId: "timer-" + t.id,
            sequence: Date.now(),
            activityType: "timer",
            state: t.running ? "working" : "paused",
            title: t.label,
            subtitle: root.fmt(remaining * 1000) + " left",
            iconReference: "0xF017",
            progressMode: "determinate",
            progressValue: root.progressOf(t) * 100,
            estimatedRemainingSeconds: remaining,
            dashboardTarget: "productivity",
            registeredActions: [
                { id: "open", label: "View details", route: "dashboard:productivity" }
            ]
        });
    }

    function syncStopwatch() {
        if (!root.swRunning && root.swAccumulatedMs === 0) {
            ActivityStore.remove("timers/stopwatch");
            return;
        }
        ActivityStore.publish({
            sourceId: "voidshell",
            activityId: "stopwatch",
            sequence: Date.now(),
            activityType: "stopwatch",
            state: root.swRunning ? "working" : "paused",
            title: "Stopwatch",
            subtitle: root.swLabel,
            iconReference: "0xF017",
            progressMode: "none",
            dashboardTarget: "productivity"
        });
    }

    // Live label for a mirrored activity — used by the clock and the
    // stack instead of writing a new activity every second.
    function labelFor(key) {
        if (key === "voidshell/focus") {
            return FocusTimer.modeLabel + " " + FocusTimer.remainingLabel;
        }
        if (key === "voidshell/stopwatch") {
            return "Stopwatch " + root.swLabel;
        }
        if (key.indexOf("voidshell/timer-") === 0) {
            const t = root.byId(key.slice("voidshell/timer-".length));
            if (t !== null) {
                return t.label + " " + root.fmt(root.remainingOf(t) * 1000);
            }
        }
        return "";
    }

    function timerOf(key) {
        if (key.indexOf("voidshell/timer-") === 0) {
            return root.byId(key.slice("voidshell/timer-".length));
        }
        return null;
    }

    // --- persistence ------------------------------------------------------
    FileView {
        id: file
        path: StorageService.ready ? StorageService.path("island-timers.json") : ""
        printErrors: false
        onLoaded: root.load(file.text())
        onLoadFailed: root.load("")
    }

    property bool loading: false

    function load(content) {
        root.loading = true;
        root.loaded = true;
        if (!content || content.trim() === "") {
            root.timers = [];
            return;
        }
        try {
            const data = JSON.parse(content);
            if (data !== null && typeof data === "object" && Array.isArray(data.timers)) {
                root.timers = data.timers.filter(t => t && typeof t.id === "string").map(t => ({
                    id: String(t.id).slice(0, 16),
                    label: String(t.label || "Timer").slice(0, 40),
                    durationSeconds: Math.max(1, Math.min(86400, Math.round(Number(t.durationSeconds) || 60))),
                    endsAt: Number(t.endsAt) || 0,
                    heldSeconds: Math.max(0, Math.round(Number(t.heldSeconds) || 0)),
                    running: t.running === true,
                    completed: Math.max(0, Math.round(Number(t.completed) || 0)),
                    announced: t.announced === true,
                    createdAt: Number(t.createdAt) || Date.now()
                }));
                root.swAccumulatedMs = Math.max(0, Number(data.swAccumulatedMs) || 0);
                root.swLaps = Array.isArray(data.swLaps) ? data.swLaps.slice(-20) : [];
                // A stopwatch measures real elapsed time, so a run that was
                // live when the shell stopped resumes from its own start
                // timestamp — downtime counts, exactly like suspend time.
                root.swRunning = data.swRunning === true;
                root.swStartedAt = root.swRunning ? Math.max(0, Number(data.swStartedAt) || Date.now()) : 0;
                // A countdown whose end time passed while the shell was
                // down is reconciled here and never re-announced
                // (`announced` was persisted with it).
                root.reconcile();
            } else {
                root.timers = [];
            }
        } catch (e) {
            console.warn("[voidshell] island-timers.json malformed, starting empty:", e);
            root.timers = [];
        }
        for (let i = 0; i < root.timers.length; i++) {
            root.syncActivity(root.timers[i]);
        }
        if (root.swAccumulatedMs > 0) {
            root.syncStopwatch();
        }
        root.loading = false;
    }

    function save() {
        if (!StorageService.ready || !root.loaded || root.loading) {
            return;
        }
        file.setText(JSON.stringify({
            version: 1,
            timers: root.timers,
            swAccumulatedMs: root.swAccumulatedMs,
            swRunning: root.swRunning,
            swStartedAt: root.swStartedAt,
            swLaps: root.swLaps
        }));
    }
}
