pragma Singleton

import Quickshell
import QtQuick

// VOID SHELL — Living State Island controller (MASTER PROMPT §6).
//
// Owns *presentation*, not data: which shape the clock is drawing right
// now, which contextual card is open, whether the user is mid-interaction,
// and which persistent warnings stay on screen. Data lives in the
// existing providers, in ActivityStore and in AnnouncementEngine.
//
// The clock's allocated rectangle is never touched by anything in here —
// the controller only swaps content inside it (§4).
//
//   clockState : idle | ambient | event | hidden   (§5 states A/B/C/G)
//   liveCountdown : the running countdown the pill keeps in view in real
//                    time (soonest-ending timer or focus session) — the
//                    view never counts on its own
//   surface    : none | context | stack            (§5 states D/E)
//
// Surface ownership is delegated to PopupManager — the shell's existing
// one-primary-surface state machine — so the Island cannot become a
// second, competing coordinator.
Singleton {
    id: root

    // --- interaction protection (§7) -------------------------------------
    // True while a pointer button is down or a field has focus inside an
    // Island surface. While true, ordinary announcements queue instead of
    // swapping content, and the activity order is frozen so no row can
    // slide out from under the pointer.
    property bool interacting: false

    // --- contextual surface ---------------------------------------------
    property string contextKind: ""
    property string contextKey: ""
    property int contextSerial: 0

    // --- stack body selection (§5 E) ------------------------------------
    // Which segmented block the activity stack is showing. Kept here so
    // the state machine — not the view — decides what a session shows,
    // and so `island section` over IPC can only ever move between the
    // five real blocks (allowlisted, never a free-form path).
    property string stackSection: "acts"

    readonly property var stackSections: ["acts", "ctrl", "timers", "presets", "clip"]

    // --- hover preview (opt-in, read-only) ------------------------------
    property bool hoverPreviewActive: false
    property bool remapGuard: false

    // --- persistent warnings (P0 / verified critical conditions) ---------
    // An announcement is temporary; a *condition* is not. Providers raise
    // a warning on the real condition and clear it when the condition
    // ends — acknowledging the display never clears the condition.
    property var warnings: []

    // --- privacy / capture state (§5 State B, F22/F23) -------------------
    // Set only from verified provider state, never inferred from a music
    // badge or an open permission.
    property bool recordingActive: false
    property bool captureActive: false
    property bool streamingActive: false

    readonly property bool privacyActive: root.recordingActive || root.captureActive || root.streamingActive
    readonly property string privacyLabel: {
        const parts = [];
        if (root.recordingActive) {
            parts.push("REC");
        }
        if (root.streamingActive) {
            parts.push("LIVE");
        }
        if (root.captureActive) {
            parts.push("MIC");
        }
        return parts.join("+");
    }

    // --- derived presentation -------------------------------------------
    readonly property bool enabled: IslandSettings.enabled
    readonly property var announcement: AnnouncementEngine.current
    readonly property bool surfaceOpen: PopupManager.islandMode !== "none"

    readonly property string warningLabel: {
        if (root.warnings.length === 0) {
            return "";
        }
        if (root.warnings.length === 1) {
            return root.warnings[0].title;
        }
        return root.warnings.length + " alerts";
    }

    // The single compact indicator on the clock's second line (§5 B):
    // pinned activity > any activity > DND > warning. Privacy is NOT
    // here — it has its own reserved region so a media badge can never
    // hide a verified recording (§5 B).
    readonly property string ambientLabel: {
        if (!root.enabled) {
            return "";
        }
        const act = ActivityStore.ambient;
        if (act !== null && act !== undefined) {
            return root.activityLabel(act);
        }
        if (IslandSettings.featureOn("dnd") && NotificationService.dnd) {
            return "Do not disturb";
        }
        if (root.warningLabel !== "") {
            return root.warningLabel;
        }
        return "";
    }

    function activityLabel(act) {
        if (!act) {
            return "";
        }
        const kind = String(act.activityType);
        if (kind === "timer" || kind === "stopwatch") {
            const remaining = act.progressMode === "determinate" && act.estimatedRemainingSeconds > 0
                ? ActivityStore.fmtDuration(act.estimatedRemainingSeconds)
                : ActivityStore.elapsedLabel(act);
            return act.title + (remaining !== "" ? " " + remaining : "");
        }
        if (act.progressMode === "determinate") {
            return act.title + " " + Math.round(act.progressValue) + "%";
        }
        if (act.state === "waiting" || act.state === "blocked") {
            return act.title + " · needs you";
        }
        if (act.state === "unknown") {
            return act.title + " · stale";
        }
        return act.title;
    }

    // --- live countdown (the pill keeps a running timer in view) --------
    // The soonest-ending countdown that is actually running, recomputed
    // from that timer's own end time on every clock tick, so the pill
    // reads the exact remaining time for as long as the timer runs — a
    // live state, not the one-shot completion announcement. Paused
    // timers are not real-time and are left to the ambient line.
    // Gated by the same feature flags as the timer announcements
    // (`timers` for countdowns, `timer` for a focus session).
    readonly property var liveCountdown: {
        if (!root.enabled || PopupManager.locked) {
            return null;
        }
        let best = null;
        if (IslandSettings.featureOn("timers")) {
            const list = TimerStore.timers;
            for (let i = 0; i < list.length; i++) {
                const t = list[i];
                if (!t.running) {
                    continue;
                }
                const rem = TimerStore.remainingOf(t);
                if (rem > 0 && (best === null || rem < best.seconds)) {
                    best = { label: String(t.label), seconds: rem };
                }
            }
        }
        if (IslandSettings.featureOn("timer") && FocusTimer.running) {
            const rem = FocusTimer.remaining;
            if (rem > 0 && (best === null || rem < best.seconds)) {
                best = { label: FocusTimer.modeLabel, seconds: rem };
            }
        }
        return best;
    }

    // Padded by TimerStore.fmt, so the pill's line never changes width
    // as the seconds tick down.
    readonly property string countdownText: root.liveCountdown === null ? "" : TimerStore.fmt(root.liveCountdown.seconds * 1000);
    readonly property string countdownName: root.liveCountdown === null ? "" : root.liveCountdown.label;

    readonly property string clockState: {
        if (!root.enabled || PopupManager.locked) {
            return "hidden";
        }
        if (root.announcement !== null) {
            return "event";
        }
        if (root.ambientLabel !== "" || root.privacyActive) {
            return "ambient";
        }
        return "idle";
    }

    // --- surface control -------------------------------------------------
    function openContext(kind, key, screen, source) {
        if (!root.enabled || PopupManager.locked) {
            return false;
        }
        root.contextKind = String(kind || "");
        root.contextKey = String(key || "");
        root.contextSerial = root.contextSerial + 1;
        root.hoverPreviewActive = false;
        PopupManager.openIsland("context", screen, source);
        return true;
    }

    function openStack(screen, source) {
        if (!root.enabled || PopupManager.locked) {
            return false;
        }
        root.hoverPreviewActive = false;
        // Re-opening on the clipboard block must re-read the history:
        // the block refreshes on selection change, and the selection is
        // remembered between openings.
        if (root.stackSection === "clip") {
            ClipboardService.refresh();
        }
        PopupManager.openIsland("stack", screen, source);
        return true;
    }

    // Move the stack between its five blocks. Allowlisted: only real
    // section ids are ever accepted, anything else is reported false and
    // leaves the current selection untouched.
    function setSection(key) {
        const id = String(key || "");
        if (root.stackSections.indexOf(id) < 0) {
            return false;
        }
        if (root.stackSection !== id) {
            root.stackSection = id;
            if (id === "clip") {
                ClipboardService.refresh();
            }
        }
        return true;
    }

    function close() {
        root.hoverPreviewActive = false;
        PopupManager.closeIsland();
    }

    // Escape closes the topmost transient view (§6): the Island surface
    // first, then any popup underneath it.
    function handleEscape() {
        if (root.interacting) {
            endInteraction();
        }
        if (PopupManager.islandMode !== "none") {
            PopupManager.closeIsland();
            return;
        }
        PopupManager.handleEscape();
    }

    // --- interaction protection -----------------------------------------
    function beginInteraction() {
        if (!root.interacting) {
            root.interacting = true;
            ActivityStore.freeze();
        }
    }

    function endInteraction() {
        if (root.interacting) {
            root.interacting = false;
            ActivityStore.thaw();
            // Flush one queued ordinary event so the clock resumes its
            // normal policy the moment the user lets go.
            AnnouncementEngine.flushIfIdle();
        }
    }

    // --- hover preview (opt-in) -----------------------------------------
    property bool hoverPending: false

    function hoverEntered(screen, source) {
        if (!IslandSettings.hoverPreview || !root.enabled || PopupManager.locked) {
            return;
        }
        if (PopupManager.islandMode !== "none") {
            return;
        }
        root.hoverPending = true;
        hoverDwell.restart();
    }

    function hoverLeft() {
        root.hoverPending = false;
        hoverDwell.stop();
        if (root.hoverPreviewActive) {
            root.hoverPreviewActive = false;
            PopupManager.closeIsland();
        }
    }

    Timer {
        id: hoverDwell
        interval: Math.max(100, IslandSettings.hoverDelayMs)
        repeat: false
        onTriggered: {
            if (!root.hoverPending) {
                return;
            }
            root.hoverPreviewActive = true;
            PopupManager.openIsland("stack", PopupManager.activeScreen, PopupManager.sourceItem);
        }
    }

    // Read-only until deliberately engaged: engaging unmaps and remaps
    // the surface so the keyboard-interactivity change is applied by a
    // fresh layer-shell configure, never toggled under a live surface.
    function engage(screen, source) {
        hoverDwell.stop();
        root.hoverPending = false;
        const wasPreview = root.hoverPreviewActive;
        root.hoverPreviewActive = false;
        if (wasPreview) {
            root.remapGuard = true;
            remapTimer.restart();
        }
        PopupManager.openIsland(root.contextKind !== "" ? "context" : "stack", screen, source);
    }

    Timer {
        id: remapTimer
        interval: 32
        repeat: false
        onTriggered: root.remapGuard = false
    }

    // --- warnings --------------------------------------------------------
    function raiseWarning(id, title, detail, tone) {
        const wid = String(id);
        const list = root.warnings.slice();
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === wid) {
                list[i] = { id: wid, title: String(title), detail: String(detail || ""), tone: String(tone || "danger") };
                root.warnings = list;
                return;
            }
        }
        list.push({ id: wid, title: String(title), detail: String(detail || ""), tone: String(tone || "danger") });
        root.warnings = list;
    }

    function clearWarning(id) {
        const wid = String(id);
        const list = root.warnings.filter(w => w.id !== wid);
        if (list.length !== root.warnings.length) {
            root.warnings = list;
        }
    }

    function acknowledgeWarnings() {
        // Hides the *display*; providers keep reporting the condition, so
        // a warning only returns if the provider raises it again.
        root.warnings = [];
    }

    // --- lifecycle -------------------------------------------------------
    // Lock: close interactive surfaces, clear drafts/previews, stop
    // captures (§20). Nothing sensitive may survive into a lock screen.
    function onSessionLocked() {
        root.hoverPreviewActive = false;
        root.hoverPending = false;
        hoverDwell.stop();
        root.contextKind = "";
        root.contextKey = "";
        AnnouncementEngine.suspendPresentations();
        PopupManager.closeIsland();
        PreviewController.clear();
    }

    Connections {
        target: PopupManager
        function onLockedChanged() {
            if (PopupManager.locked) {
                root.onSessionLocked();
            }
        }
        // Opening any other primary surface closes the Island (§7).
        function onActivePopupChanged() {
            if (PopupManager.activePopup !== "none" && PopupManager.islandMode !== "none") {
                PopupManager.closeIsland();
            }
        }
    }
}
