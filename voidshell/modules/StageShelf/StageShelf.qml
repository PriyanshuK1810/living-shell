import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../WorkspaceOverview" as Overview
import "../../common"
import "../../services"

// VOID SHELL — Stage shelf (Shadow Spaces plan §9, Phase E).
//
// The same model, the same previews and the same actions as the
// workspace overview, presented as a compact column at the screen edge
// (default left, `shelfSide` flips it without touching behaviour):
// one small overlapping stack per *other* occupied workspace — never a
// second workspace system, never a permanent label. The workspace you
// are on is your main working area, so it is not listed.
//
// Rules this surface keeps (plan §9):
//  * opt-in (`shelfEnabled`, default false) and revealed by shortcut —
//    `Super+Shift+W` → `qs -c voidshell ipc call shelf toggle`;
//  * edge-hover reveal is optional (`edgeReveal`, off by default) and,
//    when it is on, needs a deliberate dwell; it is refused outright
//    while the focused workspace holds a fullscreen window;
//  * hovering a group fans its stack wider without activating
//    anything; clicking a group activates that workspace, clicking a
//    preview focuses exactly that window;
//  * a revealed shelf auto-hides after the pointer dwells away from it
//    (unless the shortcut pinned it), and clicking a group hides it;
//  * it is suppressed whenever any other popup/overview/dashboard is
//    open and while locked — so it never fights a primary surface;
//  * when it is hidden there is no surface at all: no invisible
//    input-blocking strip, no reserved screen space, no fullscreen
//    scrim, and no keyboard focus grab (it can never swallow a key).
//
// Captures follow the same discipline as the overview: the preview
// items exist only while the shelf is revealed, so hiding it destroys
// every ScreencopyView and releases its live slot and its still.
Scope {
    id: root

    // Revealed by the shortcut and held there until toggled off.
    property bool pinned: false
    // Pointer states driving the optional edge reveal and the dwell
    // auto-hide.
    property bool edgeHover: false
    property bool edgeRevealed: false

    readonly property bool sideLeft: ManagerSettings.shelfSide !== "right"
    // Any primary surface (dashboard, overview, launcher, …) wins.
    readonly property bool popupBusy: PopupManager.activePopup !== "none"
    readonly property bool fullscreenHere: HyprlandService.focusedWorkspace !== null
        && HyprlandService.focusedWorkspace.hasFullscreen === true

    // Groups: occupied workspaces other than the focused one, in the
    // model's own order (by id — never focus order, so switching
    // windows can never reshuffle the shelf).
    readonly property var groups: {
        HyprlandService.eventSerial;
        const focus = HyprlandService.focusedWorkspace;
        const out = [];
        const list = HyprlandService.eligibleWorkspaces;
        for (let i = 0; i < list.length; i++) {
            const ws = list[i];
            if (focus !== null && ws.id === focus.id) {
                continue;
            }
            if (HyprlandService.windowCountOf(ws) > 0) {
                out.push(ws);
            }
        }
        return out;
    }

    // managerEnabled is the master switch (plan §16): with it off the
    // shelf is part of the previous workspace interface, so it does not
    // exist; shelfEnabled is the opt-in on top of that. Locked and any
    // open popup suppress it as well.
    readonly property bool allowed: ManagerSettings.managerEnabled && ManagerSettings.shelfEnabled
        && !PopupManager.locked && !root.popupBusy
    // Nothing to show ⇒ no surface (never an empty strip).
    readonly property bool revealed: root.allowed && root.groups.length > 0 && (root.pinned || root.edgeRevealed)
    // The column is clamped so it always fits the screen: six stacks is
    // already more than a shelf can show without running off the edge.
    readonly property var shownGroups: root.groups.length > 6 ? root.groups.slice(0, 6) : root.groups
    // The 4 px dwell zone only exists when the user turned edge reveal
    // on *and* the shelf itself is not already pinned open.
    readonly property bool edgeZone: root.allowed && ManagerSettings.edgeReveal && root.groups.length > 0
        && !root.fullscreenHere && !root.pinned
    // The pointer is on the shelf when it is over one of its groups or
    // over the column's own padding (one probe below the groups, one
    // inside each group — hover never has to be stolen from the
    // previews' own areas to work).
    readonly property bool shelfHovered: bodyProbe.containsMouse || root.anyGroupHovered()
    readonly property bool pointerInside: root.shelfHovered || root.edgeHover

    function anyGroupHovered() {
        for (let i = 0; i < groupRepeater.count; i++) {
            const g = groupRepeater.itemAt(i);
            if (g !== null && g !== undefined && g.hovered) {
                return true;
            }
        }
        return false;
    }

    // --- actions (shared with every other view's dispatch helpers) ------
    function hide() {
        root.pinned = false;
        root.edgeRevealed = false;
        hideDwell.stop();
    }

    function toggle() {
        if (root.pinned || root.edgeRevealed) {
            root.hide();
            return;
        }
        if (!root.allowed) {
            return;
        }
        root.pinned = true;
        console.log("[voidshell] shelf QA: revealed (pinned, groups=" + root.groups.length + ")");
    }

    // Group click: exactly this workspace (same bounded helper the pill
    // and the overview cards use), then the shelf steps out of the way.
    function activateGroup(ws) {
        if (ws !== null && ws !== undefined) {
            HyprlandService.goToWorkspace(String(ws.name));
        }
        root.hide();
    }

    // Preview click: focus exactly this window (the dispatch switches
    // to its workspace as part of the same validated path), then hide.
    function focusWindow(toplevel) {
        if (toplevel !== null && toplevel !== undefined) {
            HyprlandService.activateWindow(toplevel.address);
        }
        root.hide();
    }

    // Opening anything else dismisses the shelf: one primary surface at
    // a time, and the shelf is never one of them.
    onPopupBusyChanged: {
        if (root.popupBusy) {
            root.hide();
        }
    }

    onPointerInsideChanged: {
        if (root.pointerInside) {
            hideDwell.stop();
        } else if (!root.pinned && root.revealed) {
            hideDwell.start();
        }
    }

    onEdgeHoverChanged: {
        if (root.edgeHover && root.edgeZone) {
            edgeDwell.restart();
        } else {
            edgeDwell.stop();
        }
    }

    // Dwell at the edge before the shelf appears (never instant).
    Timer {
        id: edgeDwell
        interval: 550
        repeat: false
        onTriggered: {
            if (root.edgeHover && root.edgeZone) {
                root.edgeRevealed = true;
                console.log("[voidshell] shelf QA: revealed (edge dwell)");
            }
        }
    }

    // Pointer left the shelf without entering it: auto-hide, unless the
    // shortcut pinned it open.
    Timer {
        id: hideDwell
        interval: 1200
        repeat: false
        onTriggered: {
            if (!root.pinned && !root.pointerInside && root.revealed) {
                root.edgeRevealed = false;
            }
        }
    }

    // --- IPC surface for the keybind (hyprland.lua) ---------------------
    //   qs -c voidshell ipc call shelf toggle
    // Deliberately NOT a PopupManager popup: the shelf is suppressed
    // whenever a primary popup is open rather than replacing it.
    IpcHandler {
        target: "shelf"
        function toggle() {
            root.toggle();
        }
    }

    // --- edge dwell zone (opt-in) ---------------------------------------
    // Only instantiated when `edgeReveal` is on: it is the one case
    // where a narrow input zone exists while the shelf is hidden — the
    // price of edge-hover reveal, off by default for exactly that
    // reason. It reserves no screen space and is 4 px wide.
    PanelWindow {
        id: edge
        visible: root.edgeZone
        screen: PopupManager.activeScreen !== null ? PopupManager.activeScreen : PopupManager.fallbackScreen
        WlrLayershell.namespace: "voidshell-shelf-edge"
        exclusiveZone: -1
        color: "transparent"
        anchors {
            left: root.sideLeft
            right: !root.sideLeft
            top: true
            bottom: true
        }
        implicitWidth: 4

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: root.edgeHover = true
            onExited: root.edgeHover = false
        }
    }

    // --- the shelf itself ------------------------------------------------
    PanelWindow {
        id: shelf
        visible: root.revealed
        screen: PopupManager.activeScreen !== null ? PopupManager.activeScreen : PopupManager.fallbackScreen
        WlrLayershell.namespace: "voidshell-shelf"
        // No reserved space, no grab: the shelf overlays, it never
        // resizes the layout or steals the keyboard. Ignoring other
        // surfaces' zones (like the bar does) keeps the column exactly
        // where this window centres it instead of pushing it under the
        // bar's zone.
        exclusiveZone: -1
        color: "transparent"
        anchors {
            left: root.sideLeft
            right: !root.sideLeft
            top: true
        }
        implicitWidth: 136
        implicitHeight: column.implicitHeight + 24
        margins {
            left: root.sideLeft ? 10 : 0
            right: root.sideLeft ? 0 : 10
            // Vertically centred on the screen, never under the bar.
            top: Math.max(84, ((shelf.screen !== null ? shelf.screen.height : 720) - shelf.implicitHeight) / 2)
        }

        onVisibleChanged: {
            if (!visible) {
                // Every preview in the column is destroyed with the
                // surface, releasing its live slot and its still.
                root.edgeRevealed = false;
            }
        }

        // Padding probe: sits under the groups, so it only ever reports
        // the gaps between them — hover is never stolen from a group.
        MouseArea {
            id: bodyProbe
            anchors.fill: parent
            z: -10
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
        }

        Column {
            id: column
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Repeater {
                id: groupRepeater
                model: root.shownGroups

                delegate: Component {
                    id: groupComponent

                    Item {
                        id: group

                        required property var modelData

                        readonly property var ws: modelData
                        readonly property bool urgent: group.ws !== null && group.ws.urgent === true
                        readonly property bool hovered: probe.containsMouse
                        readonly property int windowCount: {
                            HyprlandService.eventSerial;
                            return group.ws === null ? 0 : HyprlandService.windowCountOf(group.ws);
                        }
                        // Focus order from the compositor, never a
                        // shell-side sort (same as the overview cards).
                        readonly property var windows: {
                            HyprlandService.eventSerial;
                            return group.ws === null ? [] : HyprlandService.orderedWindows(group.ws);
                        }
                        readonly property int shownCount: Math.min(group.windows.length, Math.max(1, ManagerSettings.maxStackedPreviews))

                        width: 116
                        height: 92

                        // Glass plate.
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusMd
                            color: group.hovered ? Colors.glassHover : Colors.glassCard
                            border.width: 1
                            border.color: group.urgent ? Colors.danger : (group.hovered ? Colors.borderGlass : Colors.borderSubtle)
                        }

                        // Background click → activate the workspace.
                        // The preview stack sits above this (stage z 0 >
                        // z -1), so clicking one focuses that window
                        // instead of switching blindly.
                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activateGroup(group.ws)
                        }

                        // Overlapping preview stack: real captures,
                        // fanned down-right, wider while hovered.
                        Item {
                            id: stage
                            anchors.fill: parent
                            anchors.margins: group.hovered ? 5 : 9

                            Loader {
                                anchors.fill: parent
                                // Captures exist only while the shelf is
                                // revealed (hide ⇒ stop captures).
                                active: root.revealed
                                sourceComponent: previewsComponent
                            }
                        }

                        Component {
                            id: previewsComponent

                            Repeater {
                                model: group.shownCount > 0 ? group.windows.slice(0, group.shownCount) : []

                                Overview.WindowPreview {
                                    required property var modelData
                                    required property int index

                                    toplevel: modelData
                                    // Shelf captures queue behind the
                                    // overview's (budget unchanged).
                                    priority: 25
                                    requested: root.revealed
                                    draggable: false

                                    readonly property size fit: HyprlandService.fitWindow(modelData, stage.width, stage.height)
                                    width: fit.width
                                    height: fit.height
                                    x: (stage.width - width) / 2 + (group.hovered ? 7 : 4) * index
                                    y: (stage.height - height) / 2 + (group.hovered ? 7 : 4) * index
                                    z: -index

                                    // Hover fans the stack wider: this is
                                    // movement, so it follows durationShelf
                                    // (0 under "reduced"/"off" → it jumps
                                    // straight to the new offset).
                                    Behavior on x {
                                        NumberAnimation {
                                            duration: ManagerSettings.durationShelf
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                    Behavior on y {
                                        NumberAnimation {
                                            duration: ManagerSettings.durationShelf
                                            easing.type: Easing.OutCubic
                                        }
                                    }

                                    onFocused: tl => root.focusWindow(tl)
                                }
                            }
                        }

                        // Identity chips: on hover only, so the shelf
                        // carries no permanent labels (plan §9).
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 5
                            width: badgeText.implicitWidth + 10
                            height: 15
                            radius: 5
                            opacity: group.hovered ? 1 : 0
                            color: Colors.glassPressed
                            border.width: 1
                            border.color: Colors.borderSubtle

                            Behavior on opacity {
                                // Chips fade in: kept under "reduced".
                                NumberAnimation { duration: ManagerSettings.durationFade }
                            }

                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: group.ws !== null ? String(group.ws.name) : ""
                                font.family: Theme.fontMono
                                font.weight: Font.DemiBold
                                font.pixelSize: 10
                                color: Colors.textSecondary
                            }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.margins: 5
                            width: countText.implicitWidth + 10
                            height: 15
                            radius: 5
                            opacity: group.hovered && group.windowCount > 0 ? 1 : 0
                            color: Colors.glassPressed
                            border.width: 1
                            border.color: Colors.borderSubtle

                            Behavior on opacity {
                                // Chips fade in: kept under "reduced".
                                NumberAnimation { duration: ManagerSettings.durationFade }
                            }

                            Text {
                                id: countText
                                anchors.centerIn: parent
                                text: String(group.windowCount)
                                font.family: Theme.fontMono
                                font.pixelSize: 10
                                color: Colors.textMuted
                            }
                        }

                        // Urgency is a glyph, always visible — colour
                        // alone never carries state (PRD 12.1).
                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 5
                            visible: group.urgent
                            width: 15
                            height: 15
                            radius: 7.5
                            color: Colors.dangerDeep

                            Text {
                                anchors.centerIn: parent
                                text: "!"
                                font.family: Theme.fontUi
                                font.weight: Font.DemiBold
                                font.pixelSize: 10
                                color: Colors.textOnAccent
                            }
                        }

                        // Hover probe above the stack: it accepts no
                        // buttons, so clicks still reach the previews
                        // underneath while hover state stays stable.
                        MouseArea {
                            id: probe
                            anchors.fill: parent
                            z: 5
                            acceptedButtons: Qt.NoButton
                            hoverEnabled: true
                        }
                    }
                }
            }
        }
    }

    // --- QA hook ---------------------------------------------------------
    // No input injection exists in this environment (no wtype/ydotool,
    // /dev/input is not writable), so the shortcut's effect is driven
    // the same way VOID_POPUP drives the other surfaces: set the
    // setting first (`shelfEnabled: true` in desktop-manager.json), then
    // `VOID_SHELF=1 qs -c voidshell` reveals it at startup.
    //
    // The store is read twice on a cold start (StorageService creates
    // the state directory with a process, so the first FileView pass
    // lands on the defaults before the real file is readable), which is
    // why the hook watches instead of deciding once: it reveals the
    // moment the setting really says yes, and stays silent when the
    // feature is off. Inert unless the variable is set — nothing in the
    // running shell sets it.
    readonly property bool qaHook: String(Quickshell.env("VOID_SHELF") || "") !== ""
    property bool qaApplied: false

    function qaApply() {
        if (!root.qaHook || root.qaApplied || !ManagerSettings.loaded
            || !ManagerSettings.managerEnabled || !ManagerSettings.shelfEnabled) {
            return;
        }
        root.qaApplied = true;
        root.pinned = true;
        console.log("[voidshell] shelf QA hook: revealed via VOID_SHELF (groups=" + root.groups.length + ")");
    }

    Connections {
        target: ManagerSettings
        enabled: root.qaHook
        function onLoadedChanged() {
            root.qaApply();
        }
        function onShelfEnabledChanged() {
            root.qaApply();
        }
        function onManagerEnabledChanged() {
            root.qaApply();
        }
    }

    Component.onCompleted: root.qaApply()
}
