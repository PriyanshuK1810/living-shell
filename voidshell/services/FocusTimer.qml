pragma Singleton

import Quickshell
import QtQuick

// VOID SHELL — focus/break timer (PRD 22.5).
// A shell singleton so a session keeps counting while the dashboard is
// closed; the clock is derived from timestamps against SystemClock rather
// than a 1 Hz counter, so a stuttering event loop cannot drift the
// countdown. Completion publishes a toast (the shell owns no second
// notification database).
Singleton {
    id: root

    property string mode: "focus" // focus | break
    property bool running: false
    property int focusMinutes: 25
    property int breakMinutes: 5
    property int completedSessions: 0

    // Epoch ms when the current run ends; 0 while paused/idle.
    property real endsAt: 0
    // Remaining seconds while paused (source of truth when not running).
    property int heldSeconds: 0

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    readonly property int totalSeconds: (root.mode === "focus" ? root.focusMinutes : root.breakMinutes) * 60

    readonly property int remaining: {
        if (root.running && root.endsAt > 0) {
            return Math.max(0, Math.ceil((root.endsAt - clock.date.getTime()) / 1000));
        }
        return Math.max(0, root.heldSeconds);
    }

    readonly property real progress: root.totalSeconds > 0 ? 1 - root.remaining / root.totalSeconds : 0

    readonly property string remainingLabel: {
        const s = root.remaining;
        const mm = Math.floor(s / 60);
        const ss = s % 60;
        return (mm < 10 ? "0" : "") + mm + ":" + (ss < 10 ? "0" : "") + ss;
    }

    readonly property string modeLabel: root.mode === "focus" ? "Focus" : "Break"
    readonly property string sessionLabel: root.mode === "focus" ? "Session " + (root.completedSessions + 1) : "Break"

    // Completion edge: fires once when a running countdown reaches zero.
    onRemainingChanged: {
        if (root.running && root.remaining === 0) {
            const finished = root.mode;
            root.running = false;
            root.endsAt = 0;
            root.heldSeconds = 0;
            if (finished === "focus") {
                root.completedSessions = root.completedSessions + 1;
                ToastService.push("Focus session complete", root.focusMinutes + " minutes of focus finished. Take a break.", "", "success");
                root.mode = "break";
                root.heldSeconds = root.breakMinutes * 60;
            } else {
                ToastService.push("Break finished", "Back to focus when you are ready.", "", "info");
                root.mode = "focus";
                root.heldSeconds = root.focusMinutes * 60;
            }
        }
    }

    function start() {
        if (root.running || root.totalSeconds <= 0) {
            return;
        }
        const secs = root.heldSeconds > 0 ? root.heldSeconds : root.totalSeconds;
        root.endsAt = clock.date.getTime() + secs * 1000;
        root.running = true;
    }

    function pause() {
        if (!root.running) {
            return;
        }
        root.heldSeconds = root.remaining;
        root.running = false;
        root.endsAt = 0;
    }

    function toggleRunning() {
        if (root.running) {
            root.pause();
        } else {
            root.start();
        }
    }

    function reset() {
        root.running = false;
        root.endsAt = 0;
        root.heldSeconds = 0;
    }

    // +/- step on the active mode's duration (5 minute steps, min 5).
    function adjustFocus(deltaMinutes) {
        const next = Math.max(5, Math.min(120, root.focusMinutes + deltaMinutes));
        root.focusMinutes = next;
        if (root.mode === "focus" && !root.running) {
            root.heldSeconds = next * 60;
        }
    }

    function adjustBreak(deltaMinutes) {
        const next = Math.max(1, Math.min(60, root.breakMinutes + deltaMinutes));
        root.breakMinutes = next;
        if (root.mode === "break" && !root.running) {
            root.heldSeconds = next * 60;
        }
    }

    function setMode(nextMode) {
        if (nextMode !== "focus" && nextMode !== "break") {
            return;
        }
        root.reset();
        root.mode = nextMode;
        root.heldSeconds = nextMode === "focus" ? root.focusMinutes * 60 : root.breakMinutes * 60;
    }
}
