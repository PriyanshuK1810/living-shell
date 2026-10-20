pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — WorkbenchController (Workbench plan §architecture).
//
// The dock's state machine. Windows, models and coordination all live
// elsewhere (the dock surface reads this, ApplicationStore feeds it,
// SurfaceCoordinator owns the subviews) — this service only decides:
//
//   * is the dock up right now?  (visibility modes, hover/engage decay,
//     gesture holds, fullscreen and lock policy, dodge geometry)
//   * what may the pointer/keyboard do with it?  (slot activation policy,
//     preview/menu opens, drag reorder with atomic persist + revert)
//   * keyboard mode (Super+Shift+Space / 3-finger-down continued)
//
// Visibility modes (WorkbenchSettings.visibility):
//   alwaysVisible  — up unless locked/disabled (games still cover it).
//   autoHide       — default; edge zone reveals it, it stays while
//                    engaged, retreats hideDelay after the pointer
//                    leaves everything.
//   manual         — no edge zone: shortcut/gesture/IPC only; the same
//                    engage-and-retreat rule once it is up.
//   dodgeWindows   — up unless a window covers its strip (fullscreen or
//                    a bottom-spanning layout window); an explicit
//                    reveal still wins.
//
// In *every* mode a fullscreen window suppresses the resting dock (the
// compositor gives the screen to the game) while a deliberate reveal —
// shortcut or gesture, both explicit — still shows it (plan §fullscreen).
Singleton {
    id: root

    // --- state -----------------------------------------------------------
    // held: an explicit reveal (edge dwell, gesture, IPC, shortcut). It
    // decays through hideTimer whenever nothing engages the dock.
    property bool held: false
    property string revealSource: ""
    property bool keyboardMode: false
    property int keyboardIndex: 0
    property bool dragging: false
    property string dragKey: ""
    property string dropKey: ""

    // Pointer bookkeeping (views report in; the controller never polls).
    property bool dockHovered: false
    property bool overlayHovered: false
    property bool edgeHover: false
    // A subview opened by pointer means the pointer exists; IPC-opened
    // subviews (QA) must not be reaped by a leave timer that never had a
    // pointer to leave with.
    property bool pointerSeen: false

    // Reported by the dock window so `dodgeWindows` can test real
    // geometry (global coordinates on the dock's monitor).
    property var stripRect: null

    readonly property bool enabled: WorkbenchSettings.enabled
    readonly property bool locked: PopupManager.locked
    readonly property bool fullscreen: DesktopNavigationStore.fullscreenHere
    readonly property string mode: WorkbenchSettings.visibility

    readonly property bool previewOpen: SurfaceCoordinator.workbenchSurface === "WorkbenchPreview"
    readonly property bool menuOpen: SurfaceCoordinator.workbenchSurface === "WorkbenchActionMenu"
    readonly property bool surfaceOpen: root.previewOpen || root.menuOpen
    readonly property bool engaged: root.keyboardMode || root.surfaceOpen || root.dragging

    // Explicit reveal — wins over fullscreen/dodge (it was asked for).
    readonly property bool forced: root.held || root.engaged

    readonly property bool shown: {
        if (!root.enabled || root.locked) {
            return false;
        }
        if (root.forced) {
            return true;
        }
        if (root.fullscreen) {
            return false;
        }
        if (root.mode === "alwaysVisible") {
            return true;
        }
        if (root.mode === "dodgeWindows") {
            return !root.covered;
        }
        if (root.mode === "manual") {
            return false;
        }
        // autoHide: the resting dock is only up while the pointer is on
        // it (having reached it through the edge zone, a gesture or a
        // reveal that is still inside its hold window).
        return root.dockHovered;
    }

    // --- dodgeWindows: does a window cover the dock's strip? -------------
    // Fullscreen always covers. Otherwise every window on the focused
    // workspace is checked against the reported strip rect: covering at
    // least three quarters of it counts (a half-tiled neighbour leaves
    // the strip usable and must not blink the dock away).
    readonly property bool covered: {
        DesktopNavigationStore.serial;
        if (root.fullscreen) {
            return true;
        }
        const rect = root.stripRect;
        if (rect === null || rect === undefined || rect.width <= 0) {
            return false;
        }
        const ws = DesktopNavigationStore.focusedWorkspace;
        if (ws === null) {
            return false;
        }
        const list = HyprlandService.windowsOf(ws);
        const area = rect.width * rect.height;
        for (let i = 0; i < list.length; i++) {
            const ipc = list[i].lastIpcObject;
            if (!ipc || !ipc.at || !ipc.size || ipc.at.length !== 2 || ipc.size.length !== 2) {
                continue;
            }
            const x0 = Math.max(rect.x, Number(ipc.at[0]));
            const y0 = Math.max(rect.y, Number(ipc.at[1]));
            const x1 = Math.min(rect.x + rect.width, Number(ipc.at[0]) + Number(ipc.size[0]));
            const y1 = Math.min(rect.y + rect.height, Number(ipc.at[1]) + Number(ipc.size[1]));
            if (x1 > x0 && y1 > y0 && ((x1 - x0) * (y1 - y0)) / area >= 0.75) {
                return true;
            }
        }
        return false;
    }

    // Edge zone exists only for the auto-hide mode, only while hidden,
    // and never over a fullscreen window (plan §fullscreen: no auto
    // reveal where a game owns the screen).
    readonly property bool edgeZone: root.enabled && !root.locked && !root.shown
        && root.mode === "autoHide" && !root.fullscreen && !root.keyboardMode

    // --- reveal / hide ---------------------------------------------------
    function reveal(source) {
        if (!root.enabled || root.locked) {
            return false;
        }
        // revealSource must be set BEFORE held: flipping held re-evaluates
        // the window's `visible` binding synchronously, and its
        // onVisibleChanged handler logs the source it reads right then.
        root.revealSource = String(source === undefined || source === null ? "" : source);
        root.held = true;
        return true;
    }

    // Hide the resting dock. Hover, an open preview/menu or keyboard
    // mode keep it up by their own rules — hiding never force-closes
    // something the pointer is sitting on (that is Escape's job), but it
    // does drop keyboard mode and subviews so nothing is left dangling.
    // dockHovered is cleared deliberately: the pointer may still be over
    // the strip, and without this an autoHide dock could never be hidden
    // by Escape (the hover binding would re-show it on the next tick).
    // The view re-reports hover when the window remaps underneath it.
    function hide(source) {
        hoverGrace.stop();
        root.held = false;
        root.revealSource = "";
        root.dockHovered = false;
        root.exitKeyboard();
        root.closeTransient();
    }

    function toggle(source) {
        if (root.shown) {
            root.hide(source);
            return false;
        }
        return root.reveal(source);
    }

    // --- keyboard mode ---------------------------------------------------
    // Super+Shift+Space / 3-finger down continued. Selection starts on
    // the app you are working in (first slot when on the desktop).
    function revealKeyboard() {
        if (!root.enabled || root.locked) {
            return false;
        }
        // Same ordering rule as reveal(): the source first, then held —
        // the visible-changed handler runs synchronously on held.
        root.revealSource = "keyboard";
        root.held = true;
        root.keyboardMode = true;
        const idx = ApplicationStore.slotIndex(ApplicationStore.focusedKey());
        root.keyboardIndex = idx === -1 ? 0 : idx;
        SurfaceCoordinator.requestWorkbench("WorkbenchKeyboardMode");
        return true;
    }

    function exitKeyboard() {
        if (!root.keyboardMode) {
            return false;
        }
        root.keyboardMode = false;
        if (SurfaceCoordinator.workbenchSurface === "WorkbenchKeyboardMode") {
            SurfaceCoordinator.close("WorkbenchKeyboardMode");
        }
        return true;
    }

    function moveSelection(delta) {
        const n = ApplicationStore.slots.length;
        if (n === 0) {
            root.keyboardIndex = 0;
            return;
        }
        root.keyboardIndex = ((root.keyboardIndex + delta) % n + n) % n;
    }

    function activateSelection() {
        return root.activateSlot(ApplicationStore.slots[root.keyboardIndex]);
    }

    function previewSelection() {
        const slot = ApplicationStore.slots[root.keyboardIndex];
        return slot !== undefined && slot !== null && root.openPreview(slot.key);
    }

    function menuSelection() {
        const slot = ApplicationStore.slots[root.keyboardIndex];
        return slot !== undefined && slot !== null && root.openMenu(slot.key);
    }

    // --- slot activation policy (left click + Enter) ---------------------
    // 0 windows → launch the desktop entry (never a guess at a command).
    // 1 window  → focus it (validates; switches workspace on the way).
    // n windows → `multiWindowClickBehavior`: "mru" focuses the most
    //              recently used one and cycles when it is already
    //              focused; "preview" opens the preview strip instead.
    // Cross-workspace activation NEVER opens the overview (plan §activation).
    function activateSlot(slot) {
        if (slot === null || slot === undefined) {
            return false;
        }
        if (slot.count === 0) {
            root.closeTransient();
            return WindowActions.launch(slot.entry);
        }
        if (slot.count === 1) {
            root.closeTransient();
            return WindowActions.activateAddress(slot.windows[0].address);
        }
        if (WorkbenchSettings.multiWindowClickBehavior === "preview") {
            return root.openPreview(slot.key);
        }
        root.closeTransient();
        const mru = slot.windows[0];
        if (WindowActions.isFocused(mru)) {
            return WindowActions.cycleApp(slot.key);
        }
        return WindowActions.activateAddress(mru.address);
    }

    // Middle click: request a fresh instance. A single-instance app
    // focuses itself instead — we never fabricate a second window.
    function newInstance(slot) {
        if (slot === null || slot === undefined || slot.entry === null) {
            return false;
        }
        return WindowActions.launch(slot.entry);
    }

    // --- preview strip / action palette ----------------------------------
    function openPreview(key) {
        // Defence in depth: the dock cannot be up while disabled, but
        // the IPC entry point must not open a surface for it either.
        if (!root.enabled || root.locked) {
            return false;
        }
        if (ApplicationStore.countFor(key) === 0) {
            return false;
        }
        if (root.previewOpen && root.previewKey === key) {
            root.closeTransient();
            return false;
        }
        if (!SurfaceCoordinator.requestWorkbench("WorkbenchPreview")) {
            return false;
        }
        root.previewKey = key;
        return true;
    }

    function openMenu(key) {
        if (!root.enabled || root.locked) {
            return false;
        }
        const slot = ApplicationStore.slotByKey(key);
        if (slot === null) {
            return false;
        }
        // Only real actions: nothing to show ⇒ nothing opens (no
        // invented rows, no empty palette).
        if (!ContextActionRegistry.hasAny(slot.entry)) {
            return false;
        }
        if (!SurfaceCoordinator.requestWorkbench("WorkbenchActionMenu")) {
            return false;
        }
        root.menuKey = key;
        return true;
    }

    // Which app each subview is showing ("" = none). The coordinator
    // owns open/closed; this just keeps the two keys in step with it.
    property string previewKey: ""
    property string menuKey: ""

    function closeTransient() {
        let closed = false;
        if (SurfaceCoordinator.workbenchSurface === "WorkbenchPreview") {
            SurfaceCoordinator.close("WorkbenchPreview");
            closed = true;
        }
        if (SurfaceCoordinator.workbenchSurface === "WorkbenchActionMenu") {
            SurfaceCoordinator.close("WorkbenchActionMenu");
            closed = true;
        }
        if (closed) {
            root.pointerSeen = false;
        }
        return closed;
    }

    // First slot that can actually show a preview / a palette — the IPC
    // and QA entry points (a dock with nothing to show reports false
    // instead of opening an empty surface).
    function firstPreviewKey() {
        const list = ApplicationStore.slots;
        for (let i = 0; i < list.length; i++) {
            if (list[i].count > 0) {
                return list[i].key;
            }
        }
        return "";
    }

    function firstMenuKey() {
        const list = ApplicationStore.slots;
        for (let i = 0; i < list.length; i++) {
            if (ContextActionRegistry.hasAny(list[i].entry)) {
                return list[i].key;
            }
        }
        return "";
    }

    // --- Escape (dock scope): subviews first, then the dock --------------
    function handleEscape() {
        if (root.keyboardMode) {
            root.exitKeyboard();
            root.closeTransient();
            return true;
        }
        if (SurfaceCoordinator.handleEscape()) {
            return true;
        }
        if (root.shown) {
            root.hide("escape");
            return true;
        }
        return false;
    }

    // --- drag reorder (pinned slots only) --------------------------------
    // Threshold → placeholder (view) → here: validate + one atomic
    // write. A rejected write returns false and the store never changed,
    // so the view snaps back — no auto-unpin, no half-applied order.
    function beginDrag(key) {
        const slot = ApplicationStore.slotByKey(key);
        if (slot === null || !slot.pinned || root.locked) {
            return false;
        }
        root.dragging = true;
        root.dragKey = key;
        root.dropKey = key;
        return true;
    }

    function dragOver(key) {
        if (root.dragging && key !== root.dropKey) {
            root.dropKey = key;
        }
    }

    function commitDrag() {
        if (!root.dragging) {
            return false;
        }
        const from = root.dragKey;
        const to = root.dropKey;
        root.dragging = false;
        root.dragKey = "";
        root.dropKey = "";
        if (from === to) {
            return true;
        }
        const pins = ApplicationStore.pins;
        const ids = [];
        for (let i = 0; i < pins.length; i++) {
            ids.push(String(pins[i].id));
        }
        const fromIdx = ids.indexOf(String(from));
        const toIdx = ids.indexOf(String(to));
        if (fromIdx === -1 || toIdx === -1) {
            return false;   // dropped on a running-only slot: not a pin, no auto-pin
        }
        ids.splice(toIdx, 0, ids.splice(fromIdx, 1)[0]);
        return WorkbenchSettings.setDockOrder(ids);
    }

    function cancelDrag() {
        root.dragging = false;
        root.dragKey = "";
        root.dropKey = "";
    }

    // --- pointer reporting (views call in) -------------------------------
    // A hover-loss is only trusted after it persists. Qt delivers a
    // slot MouseArea's leave *before* the window probe's enter within
    // one hover event (and a delegate rebuild delivers no enter at all
    // until the next pointer motion), so `dockPointer` dips to false
    // while the pointer is still physically over the dock — taking that
    // at face value unmapped the dock under the pointer (the reported
    // flicker). Any fresh enter cancels the grace instantly; a real
    // leave retreats the dock once the grace elapses.
    function setDockHovered(v) {
        if (v) {
            hoverGrace.stop();
            root.dockHovered = true;
            root.pointerSeen = true;
            hideTimer.stop();
            return;
        }
        if (root.dockHovered) {
            hoverGrace.restart();
        }
    }

    function setOverlayHovered(v) {
        root.overlayHovered = v;
        if (v) {
            root.pointerSeen = true;
        }
    }

    function edgeEntered() {
        root.edgeHover = true;
        edgeDwell.restart();
    }

    function edgeExited() {
        root.edgeHover = false;
        edgeDwell.stop();
    }

    // Grace period for the hover-loss above: short enough to feel
    // immediate when the pointer really leaves, long enough to bridge
    // a same-event hover handoff or a model rebuild.
    Timer {
        id: hoverGrace
        interval: 200
        repeat: false
        onTriggered: root.dockHovered = false
    }

    // Edge dwell: never instant (plan §edgeRevealDelay).
    Timer {
        id: edgeDwell
        interval: Math.max(0, WorkbenchSettings.edgeRevealDelay)
        repeat: false
        onTriggered: {
            if (root.edgeHover && root.edgeZone) {
                root.reveal("edge");
            }
        }
    }

    // Held with nothing engaging the dock ⇒ retreat after hideDelay
    // (gesture/edge/IPC reveals "stay briefly", then leave — unless the
    // pointer made it onto the dock in time). The QA hook holds instead:
    // a scripted reveal must still be there when the gate reads `state`.
    Timer {
        id: hideTimer
        interval: Math.max(300, WorkbenchSettings.hideDelay)
        repeat: false
        running: root.held && !root.dockHovered && !root.engaged && !root.qaHold
        onTriggered: {
            if (root.held && !root.dockHovered && !root.engaged) {
                root.held = false;
                root.revealSource = "";
            }
        }
    }

    // Pointer left the dock *and* an open preview/menu: close the
    // subview after hideDelay (the resting dock then retreats through
    // its own rules — nothing is left hovering over nothing).
    Timer {
        id: leaveTimer
        interval: Math.max(300, WorkbenchSettings.hideDelay)
        repeat: false
        running: root.surfaceOpen && root.pointerSeen && !root.dockHovered
            && !root.overlayHovered && !root.keyboardMode && !root.dragging
        onTriggered: root.closeTransient()
    }

    // --- coherence: one source of truth, no parallel state ---------------
    Connections {
        target: SurfaceCoordinator
        function onWorkbenchSurfaceChanged() {
            if (SurfaceCoordinator.workbenchSurface !== "WorkbenchPreview") {
                root.previewKey = "";
            }
            if (SurfaceCoordinator.workbenchSurface !== "WorkbenchActionMenu") {
                root.menuKey = "";
            }
            // Whoever cleared the record (Escape, a gesture `dismiss`, a
            // keybind opening a popup) also ends keyboard mode: the mode
            // lives and dies with that major, never one beat apart. A
            // subview switching *to* the preview/menu keeps it — the keys
            // still drive the dock underneath.
            if (SurfaceCoordinator.workbenchSurface === "" && root.keyboardMode) {
                root.keyboardMode = false;
            }
        }
    }

    // The app's windows changed while its preview is open: when the last
    // one closes, the preview has nothing left to show and retires
    // instead of sitting on an empty strip.
    Connections {
        target: ApplicationStore
        function onSlotsChanged() {
            if (root.previewOpen && ApplicationStore.countFor(root.previewKey) === 0) {
                root.closeTransient();
            }
        }
    }

    // Workspace changed under an open preview (native swipe, keybind,
    // dock activation): the captures are stale the moment you move, so
    // they close — the rule "workspace swipe clears Workbench subviews"
    // lives here instead of a per-frame gesture stream (plan §coordination).
    Connections {
        target: DesktopNavigationStore
        function onFocusedWorkspaceChanged() {
            if (root.surfaceOpen) {
                root.closeTransient();
            }
        }
    }

    // The lock surface owns the screen: nothing of ours stays engaged.
    Connections {
        target: PopupManager
        function onLockedChanged() {
            if (PopupManager.locked) {
                root.held = false;
                root.exitKeyboard();
                root.closeTransient();
            }
        }
    }

    Connections {
        target: WorkbenchSettings
        function onEnabledChanged() {
            if (!WorkbenchSettings.enabled) {
                root.held = false;
                root.exitKeyboard();
                root.closeTransient();
            }
        }
    }

    // --- IPC surface (keybind + gate) ------------------------------------
    //   qs -c voidshell ipc call workbench keyboard   (Super+Shift+Space)
    //   qs -c voidshell ipc call workbench state
    IpcHandler {
        target: "workbench"

        function show(): bool {
            return root.reveal("ipc");
        }

        function hide() {
            root.hide("ipc");
        }

        function toggle(): bool {
            return root.toggle("ipc");
        }

        function keyboard(): bool {
            if (root.keyboardMode) {
                root.exitKeyboard();
                return false;
            }
            return root.revealKeyboard();
        }

        function preview(): bool {
            const key = root.firstPreviewKey();
            if (key === "") {
                return false;
            }
            root.reveal("ipc");
            return root.openPreview(key);
        }

        function menu(): bool {
            const key = root.firstMenuKey();
            if (key === "") {
                return false;
            }
            root.reveal("ipc");
            return root.openMenu(key);
        }

        function state(): string {
            return JSON.stringify({
                shown: root.shown,
                mode: root.mode,
                enabled: root.enabled,
                held: root.held,
                source: root.revealSource,
                hovered: root.dockHovered,
                fullscreen: root.fullscreen,
                covered: root.covered,
                keyboard: root.keyboardMode,
                previewKey: root.previewKey,
                menuKey: root.menuKey,
                drag: root.dragging,
                slots: ApplicationStore.slots.length,
                pins: ApplicationStore.pins.length,
                screen: DesktopNavigationStore.targetScreen !== null ? String(DesktopNavigationStore.targetScreen.name) : ""
            });
        }

        function ping(): string {
            return "pong";
        }
    }

    // --- QA hook ---------------------------------------------------------
    // No input injection exists in this environment (no wtype/ydotool),
    // so the dock's surfaces are driven like VOID_POPUP / VOID_SHELF:
    //   VOID_WORKBENCH=1        → resting reveal
    //   VOID_WORKBENCH=keyboard → keyboard mode
    //   VOID_WORKBENCH=preview  → reveal + first preview strip
    //   VOID_WORKBENCH=menu     → reveal + first action palette
    // Inert unless the variable is set; waits for the settings load the
    // same way the shelf hook does (cold start reads the store twice).
    readonly property bool qaHook: String(Quickshell.env("VOID_WORKBENCH") || "") !== ""
    property bool qaApplied: false
    // A QA reveal is pinned: nothing scripted may age it out from under
    // the gate's read (IPC `hide` still works — it clears `held`).
    readonly property bool qaHold: root.qaHook && root.qaApplied

    function qaApply() {
        if (!root.qaHook || root.qaApplied || !WorkbenchSettings.loaded || !WorkbenchSettings.enabled) {
            return;
        }
        root.qaApplied = true;
        const wanted = String(Quickshell.env("VOID_WORKBENCH"));
        if (wanted === "keyboard") {
            root.revealKeyboard();
        } else if (wanted === "preview") {
            root.reveal("qa");
            const key = root.firstPreviewKey();
            if (key !== "") {
                root.openPreview(key);
            }
        } else if (wanted === "menu") {
            root.reveal("qa");
            const key2 = root.firstMenuKey();
            if (key2 !== "") {
                root.openMenu(key2);
            }
        } else {
            root.reveal("qa");
        }
        console.log("[voidshell] workbench QA hook: " + wanted);
    }

    Connections {
        target: WorkbenchSettings
        enabled: root.qaHook
        function onLoadedChanged() {
            root.qaApply();
        }
    }

    Component.onCompleted: root.qaApply()
}
