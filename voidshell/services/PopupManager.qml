pragma Singleton

import Quickshell
import Quickshell.Io

// VOID SHELL — centralized popup state machine.
// Single source of truth: modules never keep their own open/closed booleans,
// they bind to PopupManager.activePopup. One primary popup is visible at a
// time; opening another closes the previous one.
//
// Screen/source retention: open()/toggle() record which screen and which
// source item requested the popup so panels can place themselves on the
// appropriate monitor in later phases. Retention survives closeAll() as
// last-known placement.
// Escape: panels call escape() from their Escape key handler (a service
// singleton owns no window and cannot grab keys itself).
Singleton {
    id: root

    readonly property var popups: ["launcher", "media", "quickSettings", "notifications", "power", "dashboard", "taskManager", "overview", "lock"]

    // Observable state. "none" when no popup is open.
    property string activePopup: "none"

    // The lock surface owns the screen while it is up: no other panel may
    // open over it, and Escape does not dismiss it (PRD 25 — only a
    // successful authentication unlocks).
    readonly property bool locked: root.activePopup === "lock"

    // Last-known placement (retained across closeAll for later reuse).
    property var activeScreen: null
    property var sourceItem: null

    // How the active popup was invoked: "explicit" for every deliberate
    // opener (keybind, bar, right-click, launcher action) and "reveal"
    // for the dwell-at-edge opener planned for a later phase. The
    // overview reads it against ManagerSettings.fullscreenPolicy
    // (§3 "explicit-only") before it is allowed to cover a fullscreen
    // window. Retained across closeAll like the placement.
    property string openReason: "explicit"

    // --- Living State Island surface (MASTER PROMPT §6/§7) ---------------
    // The Mini Island and the activity stack are *interactive shell
    // surfaces* too, so they live in the same one-primary-at-a-time
    // state machine as the popup panels — they are just tracked
    // separately because they are anchored to the clock rather than to a
    // bar region, and because a transient announcement changes only the
    // clock's content and must never count as "a surface is open".
    //   islandMode: "none" | "context" | "stack"
    property string islandMode: "none"
    // Screen the *invoking clock* lives on: an open interactive popup is
    // never moved because focus changed (§20).
    property var islandScreen: null

    readonly property bool islandOpen: root.islandMode !== "none"

    // First configured screen, used when no bar control has reported one
    // yet (e.g. a popup opened from a keybind instead of the bar).
    readonly property var fallbackScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

    function isPopup(name) {
        return root.popups.indexOf(name) !== -1;
    }

    function isOpen(name) {
        return root.activePopup === name;
    }

    // Returns true when the request changed state or reaffirmed it.
    function open(name, screen, source, reason) {
        if (!root.isPopup(name)) {
            return false;
        }
        if (root.locked && name !== "lock") {
            return false;
        }
        if (screen !== undefined) {
            root.activeScreen = screen;
        }
        if (source !== undefined) {
            root.sourceItem = source;
        }
        root.openReason = (reason === undefined || reason === null || reason === "") ? "explicit" : String(reason);
        // Opening a primary popup closes the Island (§7 mutual exclusion).
        root.islandMode = "none";
        root.activePopup = name;
        return true;
    }

    // Open the Island's interactive surface. `mode` is "context" (one
    // activity's card) or "stack" (pinned + ongoing activities).
    // Returns false while locked: the lock surface owns the screen.
    function openIsland(mode, screen, source) {
        if (root.locked || (mode !== "context" && mode !== "stack")) {
            return false;
        }
        if (screen !== undefined && screen !== null) {
            root.islandScreen = screen;
        }
        if (source !== undefined && source !== null) {
            root.sourceItem = source;
        }
        // An interactive Island closes conflicting expanded controls but
        // never another Island card the user is already using.
        root.activePopup = "none";
        root.islandMode = mode;
        return true;
    }

    function closeIsland() {
        if (root.islandMode !== "none") {
            root.islandMode = "none";
        }
    }

    function toggle(name, screen, source, reason) {
        if (!root.isPopup(name)) {
            return false;
        }
        if (root.activePopup === name) {
            // The lock surface can only be dismissed by authenticating.
            if (root.locked) {
                return false;
            }
            root.closeAll();
            return true;
        }
        return root.open(name, screen, source, reason);
    }

    function close(name) {
        if (name === undefined || root.activePopup === name) {
            root.closeAll();
        }
    }

    function closeAll() {
        root.activePopup = "none";
        root.islandMode = "none";
    }

    // Panels wire their Escape key handler to this. Named handleEscape
    // because `escape` collides with the JavaScript global.
    function handleEscape() {
        if (root.locked) {
            return;
        }
        // The Island surface is the topmost transient view when it is
        // open, so it goes first (§6: Escape closes the topmost view).
        if (root.islandMode !== "none") {
            root.islandMode = "none";
            return;
        }
        root.closeAll();
    }

    // --- IPC surface for keybinds (hyprland.lua): ------------------------
    //   qs -c voidshell ipc call <popup> toggle
    // One target per popup so binds read naturally; every target routes
    // through this state machine, preserving the one-primary-popup rule.
    // The lock target opens but can never dismiss (toggle() refuses while
    // locked), matching PRD §25 — only authentication unlocks.
    IpcHandler {
        target: "launcher"
        function toggle() {
            root.toggle("launcher");
        }
    }

    IpcHandler {
        target: "calendar"

        function toggle() {
            // The standalone calendar popup is gone: the calendar lives
            // inside the dashboard's Overview tab, so this target opens
            // the dashboard there.
            root.toggle("dashboard");
        }
    }

    IpcHandler {
        target: "media"
        function toggle() {
            root.toggle("media");
        }
    }

    IpcHandler {
        target: "quickSettings"
        function toggle() {
            root.toggle("quickSettings");
        }
    }

    IpcHandler {
        target: "notifications"
        function toggle() {
            root.toggle("notifications");
        }
    }

    IpcHandler {
        target: "power"
        function toggle() {
            root.toggle("power");
        }
    }

    IpcHandler {
        target: "dashboard"
        function toggle() {
            root.toggle("dashboard");
        }
    }

    IpcHandler {
        target: "taskManager"
        function toggle() {
            root.toggle("taskManager");
        }
    }

    IpcHandler {
        target: "overview"
        function toggle() {
            root.toggle("overview");
        }
    }

    IpcHandler {
        target: "lock"
        function toggle() {
            root.toggle("lock");
        }
    }

    // Living State Island (MASTER PROMPT §6): `island toggle` opens the
    // activity stack and closes it again, `island stack` opens it
    // explicitly. Both route through the same state machine, so opening
    // it closes every conflicting expanded control and opening a popup
    // closes it — one primary surface at a time holds over IPC too.
    IpcHandler {
        target: "island"

        function toggle() {
            if (root.islandMode !== "none") {
                root.closeIsland();
            } else {
                root.openIsland("stack");
            }
        }

        function stack() {
            root.openIsland("stack");
        }

        // Open one activity's contextual card by its namespaced key
        // (`sourceId/activityId`). Used by binds and by the test gates;
        // an unknown key simply shows an empty card, never a stale one.
        function context(key: string): bool {
            return IslandController.openContext("activity", key, undefined, undefined);
        }

        function close() {
            root.closeIsland();
        }

        // Select one block of the stack's segmented body (`acts`,
        // `ctrl`, `timers`, `presets`, `clip`). Returns false for
        // anything outside that list and leaves the selection alone.
        function section(key: string): bool {
            if (root.islandMode !== "stack") {
                root.openIsland("stack");
            }
            return IslandController.setSection(key);
        }

        // Diagnostics for the settings surface and for the test gates:
        // the live capability matrix (availability vocabulary from §21),
        // returned as JSON. Read-only — it never mutates state.
        function diagnostics(): string {
            const rows = IslandSettings.diagnostics();
            const out = [];
            for (let i = 0; i < rows.length; i++) {
                out.push(rows[i].id + "=" + rows[i].state + (rows[i].enabled ? "" : "(disabled)"));
            }
            return JSON.stringify({
                enabled: IslandSettings.enabled,
                animation: IslandSettings.effectiveAnimation,
                privacy: IslandSettings.privacy,
                queueLimit: IslandSettings.queueLimit,
                activities: ActivityStore.count,
                announcements: AnnouncementEngine.serial,
                dropped: AnnouncementEngine.droppedCount,
                providers: out
            });
        }
    }
}
