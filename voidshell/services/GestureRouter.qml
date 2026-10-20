pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — GestureRouter (Workbench plan §gesture).
//
// Compositor side (hypr/.config/hypr/config/gestures.lua) owns the raw
// touchpad streams through `hl.gesture` live handlers: it accumulates
// deltas, applies the thresholds this service publishes (`config` IPC),
// and forwards only *committed* intents here — one shell command per
// commit, never a per-frame stream. This side owns arbitration:
//
//   priority: lock > active shell drag > native workspace gesture
//             > overview > workbench > project/dashboard
//
//  * lock: PopupManager.locked refuses everything (the lock surface
//    owns the screen).
//  * shell drag: while WorkbenchController reports a pin drag in
//    progress, surface intents retarget to "close subviews first" and
//    the drag finishes untouched.
//  * native workspace swipe never reaches the shell (the compositor
//    runs it as `action="workspace"` with the stock animation) — its
//    only shell-side effect is closing Workbench previews/menus, which
//    the Lua side fires as the `dismiss` intent at gesture start.
//  * one owner at a time: an intent that opens a major goes through
//    SurfaceCoordinator.request(), which closes the incompatible ones
//    atomically.
//  * cooldown + retarget: a repeat inside WorkbenchSettings.cooldown
//    replaces a not-yet-delivered intent (last write wins) instead of
//    queueing, so a rapid double-swipe never replays.
Singleton {
    id: root

    // Last delivered intents for the QA gate / diagnostics.
    property string lastIntent: ""
    property int lastCommitAt: 0
    property int commitCount: 0
    property int retargetCount: 0

    // Queued-but-not-delivered intent (retarget window = cooldown).
    property string pendingIntent: ""
    property int pendingAt: 0

    readonly property bool locked: PopupManager.locked
    readonly property bool shellDragActive: WorkbenchController.dragging

    // Intents the compositor may forward (documented contract with
    // gestures.lua — unknown names are refused and logged).
    readonly property var intents: [
        "overview",           // 3-finger up  → workspace overview
        "workbench",          // 3-finger down → reveal dock
        "workbenchKeyboard",  // 3-finger down, continued → keyboard mode
        "workbenchHide",      // reversed after reveal → hide dock
        "dismiss",            // any gesture start → close subviews/tooltips
        "stageNext",          // 4-finger right → next project (power)
        "stagePrev",          // 4-finger left  → prev project (power)
        "dashboard"           // 4-finger up → dashboard (power, FS-suppressed)
    ]

    // --- entry point (IPC target "gesture") ------------------------------
    // qs -c voidshell ipc call gesture commit overview
    function commit(intent) {
        const name = String(intent === undefined || intent === null ? "" : intent);
        if (root.intents.indexOf(name) === -1) {
            // Validation, not a fault: an unknown intent is refused
            // quietly (log, not warn) — the refusal itself is the
            // documented behaviour, and the gate greps this line.
            console.log("[voidshell] gesture: refused unknown intent '" + name + "'");
            return false;
        }
        const now = Date.now();
        if (root.locked) {
            console.log("[voidshell] gesture: locked, dropping " + name);
            return false;
        }
        // Retarget instead of queue: inside the cooldown a repeat
        // replaces the pending intent (last write wins) and is only
        // delivered when the window elapses.
        if (root.pendingIntent !== "" && (now - root.pendingAt) < WorkbenchSettings.cooldown) {
            root.pendingIntent = name;
            root.pendingAt = now;
            root.retargetCount = root.retargetCount + 1;
            deliverTimer.restart();
            return true;
        }
        root.pendingIntent = name;
        root.pendingAt = now;
        deliverTimer.restart();
        if (WorkbenchSettings.cooldown <= 0) {
            root.deliverNow();
        }
        return true;
    }

    function deliverNow() {
        const name = root.pendingIntent;
        if (name === "") {
            return;
        }
        root.pendingIntent = "";
        deliverTimer.stop();
        root.lastIntent = name;
        root.lastCommitAt = Date.now();
        root.commitCount = root.commitCount + 1;
        root.route(name);
    }

    Timer {
        id: deliverTimer
        interval: Math.max(0, WorkbenchSettings.cooldown)
        repeat: false
        onTriggered: root.deliverNow()
    }

    // --- arbitration + routing -------------------------------------------
    function route(name) {
        if (name === "dismiss") {
            // Gesture start: previews, menus and tooltips step out of the
            // way of the native workspace swipe. The resting dock stays.
            if (SurfaceCoordinator.workbenchBusy) {
                SurfaceCoordinator.closeAll("");
            }
            return;
        }
        if (name === "overview") {
            if (!allowedFullscreen("overview")) {
                return;
            }
            // Shell drag retargets: close subviews, then open.
            SurfaceCoordinator.request("WorkspaceOverview");
            PopupManager.toggle("overview", undefined, undefined, "explicit");
            return;
        }
        if (name === "workbench" || name === "workbenchKeyboard") {
            if (!allowedFullscreen("workbench")) {
                return;
            }
            if (root.shellDragActive) {
                SurfaceCoordinator.closeAll("");
                return;
            }
            if (PopupManager.activePopup !== "none" || PopupManager.islandOpen) {
                SurfaceCoordinator.closeAll("");
            }
            if (name === "workbenchKeyboard") {
                WorkbenchController.revealKeyboard();
            } else {
                WorkbenchController.reveal("gesture");
            }
            return;
        }
        if (name === "workbenchHide") {
            WorkbenchController.hide("gesture");
            return;
        }
        if (name === "stageNext" || name === "stagePrev") {
            // Only meaningful with the Stage shelf's model: without it
            // there is no project concept to navigate, so the intent is
            // refused rather than faked.
            if (!ManagerSettings.managerEnabled || !ManagerSettings.shelfEnabled) {
                console.log("[voidshell] gesture: stage intent ignored (shelf disabled)");
                return;
            }
            root.stepProject(name === "stageNext" ? 1 : -1);
            return;
        }
        if (name === "dashboard") {
            if (!allowedFullscreen("dashboard")) {
                return;
            }
            SurfaceCoordinator.request("Dashboard");
            PopupManager.toggle("dashboard", undefined, undefined, "explicit");
            return;
        }
    }

    // Fullscreen policy per surface (WorkbenchSettings.gestureAllowFullscreen).
    function allowedFullscreen(surface) {
        const fs = HyprlandService.focusedWorkspace !== null
            && HyprlandService.focusedWorkspace.hasFullscreen === true;
        if (!fs) {
            return true;
        }
        const policy = WorkbenchSettings.gestureAllowFullscreen;
        return policy !== null && policy[surface] === true;
    }

    // Project step: the Stage shelf's model *is* the list of occupied
    // workspaces, so 4-finger L/R walks that list in the model's own
    // order (never a shell-side sort). Wraps at both ends; with fewer
    // than two occupied workspaces there is nothing to step to.
    function stepProject(dir) {
        const focus = HyprlandService.focusedWorkspace;
        if (focus === null) {
            return false;
        }
        const list = [];
        const all = HyprlandService.eligibleWorkspaces;
        for (let i = 0; i < all.length; i++) {
            if (HyprlandService.windowCountOf(all[i]) > 0) {
                list.push(all[i]);
            }
        }
        if (list.length < 2) {
            return false;
        }
        let idx = -1;
        for (let j = 0; j < list.length; j++) {
            if (list[j].id === focus.id) {
                idx = j;
                break;
            }
        }
        if (idx === -1) {
            // Focused workspace is empty (desktop): step to the nearest
            // occupied one in the requested direction.
            idx = dir > 0 ? -1 : 0;
        }
        const next = ((idx + dir) % list.length + list.length) % list.length;
        HyprlandService.goToWorkspace(String(list[next].name));
        return true;
    }

    // --- IPC surface ------------------------------------------------------
    // The Lua gesture config reads thresholds here, so one JSON edit in
    // WorkbenchSettings retunes both sides.
    IpcHandler {
        target: "gesture"

        function commit(intent: string): bool {
            return root.commit(intent);
        }

        // JSON blob: profile + thresholds + fullscreen policy.
        function config(): string {
            return WorkbenchSettings.configBlob();
        }

        // Diagnostics for the gate: last intent, counters, current major.
        function state(): string {
            return JSON.stringify({
                lastIntent: root.lastIntent,
                commits: root.commitCount,
                retargets: root.retargetCount,
                cooldown: WorkbenchSettings.cooldown,
                locked: PopupManager.locked,
                drag: WorkbenchController.dragging,
                major: SurfaceCoordinator.active
            });
        }

        function ping(): string {
            return "pong";
        }
    }
}
