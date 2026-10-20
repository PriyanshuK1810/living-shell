import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../common"
import "../../services"

// VOID SHELL — Workbench (Workbench plan §dock).
//
// The bottom-centred application dock: which app/window/tool I am
// working with. It is a fourth layer under the existing shell, never a
// replacement: the top bar keeps system state, the workspace indicator
// keeps "where am I", the overview keeps "which workspace/window
// group", the Stage shelf keeps "which project" (§hierarchy).
//
// Surfaces (all `voidshell-workbench*`, all overlay — exclusive zone -1
// so nothing below is resized):
//
//   dock      62 px tall, 14 px off the bottom, centred, capped at 74%
//             of the screen; grows upward only while a tooltip shows.
//   edge      a 260×4 reveal strip at the very bottom centre — visible
//             (a faint accent line, never an invisible pointer
//             blocker), only while the dock is hidden in autoHide mode,
//             never over fullscreen.
//   preview   the on-demand capture strip, 10 px above the dock.
//   palette   the right-click action palette, same placement.
//
// The preview and palette windows are gated by Loaders, so closing
// them destroys the items (and with them every ScreencopyView) — same
// lifecycle rule as the Stage shelf. Keyboard focus is Exclusive only
// while keyboard mode, a drag or an open subview holds the dock: at
// rest the dock never steals a key from the focused window.
Scope {
    id: root

    // --- geometry (plan §geometry) --------------------------------------
    readonly property int dockH: 62              // allowed 58–66
    readonly property int dockBottom: 14         // allowed 10–18
    readonly property int edgeW: 260
    readonly property int previewW: 820
    readonly property int paletteW: 250
    readonly property real screenW: DesktopNavigationStore.targetScreen !== null
        && DesktopNavigationStore.targetScreen !== undefined
        ? DesktopNavigationStore.targetScreen.width : 1280
    readonly property int dockMaxW: Math.round(root.screenW * 0.74)
    readonly property int contentW: Math.max(160,
        Math.min(dockRow.implicitWidth + 32, root.dockMaxW))
    readonly property int dockMarginX: Math.max(0, Math.round((root.screenW - root.contentW) / 2))

    // --- dock hover: the window probe *or* any slot ----------------------
    // Hover is exclusive per item (a DockItem's MouseArea takes it from
    // the window probe), so the two are OR-combined — the Stage shelf's
    // exact trick (bodyProbe || group probes).
    property int slotHoverCount: 0
    readonly property bool dockPointer: glassProbe.containsMouse || root.slotHoverCount > 0

    // When the dock holds the keyboard: keyboard mode, an active pin
    // drag (Escape must cancel it) or an open subview (Escape closes
    // it first). At rest: never.
    readonly property bool dockKeys: WorkbenchController.keyboardMode
        || WorkbenchController.dragging || WorkbenchController.surfaceOpen

    // The tip and the row's magnification index live exactly as long as
    // the pointer is somewhere on the dock — never per-slot. Clearing
    // them on a slot's hover-exit fed back through the tooltip's own
    // window growth: showing the tip resizes the surface, the resize
    // re-runs hover delivery (transient slot-exit), the exit cleared the
    // tip, the tip's shrink re-ran hover again — an endless show/hide
    // loop (the flicker). A 250 ms debounce covers the one-frame
    // ownership handoff between the slot and the window probe.
    Timer {
        id: tipClearTimer
        interval: 250
        onTriggered: {
            if (!root.dockPointer) {
                root.clearTip();
                dockRow.hoverIndex = -1;
            }
        }
    }
    onDockPointerChanged: {
        WorkbenchController.setDockHovered(root.dockPointer);
        if (root.dockPointer) {
            tipClearTimer.stop();
        } else {
            tipClearTimer.start();
        }
    }

    // --- tooltip (inside the dock window, above the glass) ---------------
    property int tipIndex: -1
    property bool tipOn: false
    readonly property bool tipVisible: root.tipOn && WorkbenchController.shown
        && !WorkbenchController.keyboardMode && !WorkbenchController.dragging
        && !SurfaceCoordinator.workbenchBusy
    readonly property string tipText: root.tipIndex >= 0
        && root.tipIndex < ApplicationStore.slots.length
        ? ApplicationStore.slots[root.tipIndex].name : ""

    function noteTip(index) {
        // Re-entry (hover's frame-level ownership handoff during a
        // window resize) must not re-arm the timer for the same slot —
        // that would push the tip's first show out forever.
        if (root.tipIndex === index && (root.tipOn || tipTimer.running)) {
            return;
        }
        root.tipIndex = index;
        tipTimer.restart();
    }

    function clearTip() {
        tipTimer.stop();
        root.tipOn = false;
        root.tipIndex = -1;
    }

    Timer {
        id: tipTimer
        interval: 450
        repeat: false
        onTriggered: root.tipOn = true
    }

    // Hover anchor for the tooltip, in dock-window coordinates (the
    // glass sits flush with the window's left edge, so row + slot x is
    // already the window x).
    readonly property real tipAnchorX: {
        if (root.tipIndex < 0) {
            return 0;
        }
        for (let i = 0; i < dockRow.children.length; i++) {
            const c = dockRow.children[i];
            if (c !== undefined && c !== null && c.slotIndex === root.tipIndex) {
                return dockRow.x + c.x + c.width / 2;
            }
        }
        return 0;
    }

    // Global geometry of the dock's strip (dodgeWindows tests it).
    function reportStrip() {
        const s = DesktopNavigationStore.targetScreen;
        const m = HyprlandService.focusedMonitor;
        if (s === null || s === undefined) {
            return;
        }
        const mx = m !== null && m !== undefined && m.x !== undefined ? Number(m.x) : 0;
        const my = m !== null && m !== undefined && m.y !== undefined ? Number(m.y) : 0;
        WorkbenchController.stripRect = Qt.rect(
            mx + root.dockMarginX,
            my + s.height - root.dockBottom - root.dockH,
            root.contentW, root.dockH);
    }

    // =====================================================================
    // dock
    // =====================================================================
    PanelWindow {
        id: dock
        visible: WorkbenchController.shown
        screen: DesktopNavigationStore.targetScreen

        WlrLayershell.namespace: "voidshell-workbench"
        // Never steals keys at rest; exclusive only while the dock is
        // actually being driven (keyboard mode, drag Escape, subview
        // Escape) — plan §keyboard.
        WlrLayershell.keyboardFocus: root.dockKeys
            ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusiveZone: -1
        color: "transparent"

        anchors {
            left: true
            right: true
            bottom: true
        }
        margins {
            left: root.dockMarginX
            right: root.dockMarginX
            bottom: root.dockBottom
        }
        implicitWidth: root.contentW
        // Grows upward only while the tooltip shows — the glass itself
        // never moves (bottom anchored).
        implicitHeight: root.dockH + (root.tipVisible ? tip.height + 8 : 0)

        onVisibleChanged: {
            if (visible) {
                root.reportStrip();
                console.log("[voidshell] workbench: dock shown (source="
                    + WorkbenchController.revealSource + ")");
            } else {
                // An unmapped window may not deliver hover-leave; reset
                // the counters so an autoHide dock can never stick on.
                root.slotHoverCount = 0;
                root.clearTip();
                dockRow.hoverIndex = -1;
                tipClearTimer.stop();
            }
        }
        onImplicitWidthChanged: root.reportStrip()

        // Window probe: gaps between slots, the keyboard hint and the
        // tooltip zone all count as "the pointer is on the dock".
        MouseArea {
            id: glassProbe
            anchors.fill: parent
            z: -1
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
        }

        // --- glass body ---------------------------------------------------
        Rectangle {
            id: glass
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: root.dockH
            radius: Theme.radiusLg
            color: Colors.glassCard
            border.width: 1
            border.color: WorkbenchController.keyboardMode
                ? Colors.borderAccent : Colors.borderGlass

            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
                height: 1
                radius: 0.5
                color: Colors.highlightTop
                opacity: 0.6
            }
        }

        // --- the slot row -------------------------------------------------
        Row {
            id: dockRow
            anchors.centerIn: glass
            spacing: 6
            // Neighbour term for magnification (hover index of the row).
            property int hoverIndex: -1

            Repeater {
                model: ApplicationStore.slots

                DockItem {
                    required property var modelData
                    required property int index

                    slot: modelData
                    slotIndex: index
                    rowHoverIndex: dockRow.hoverIndex

                    onHoveredChanged: {
                        root.slotHoverCount = Math.max(0,
                            root.slotHoverCount + (hovered ? 1 : -1));
                        if (hovered) {
                            dockRow.hoverIndex = index;
                            root.noteTip(index);
                        } else {
                            // Tip and magnification index deliberately
                            // survive a slot's hover-exit: they end when
                            // the pointer leaves the whole dock (see
                            // onDockPointerChanged). Per-slot cleanup
                            // here was the flicker loop's trigger.
                        }
                    }
                    Component.onDestruction: {
                        if (hovered) {
                            root.slotHoverCount = Math.max(0, root.slotHoverCount - 1);
                        }
                    }
                }
            }

            // --- keyboard hint (only while keyboard mode drives the dock) --
            Rectangle {
                visible: WorkbenchController.keyboardMode
                width: 1
                height: 28
                color: Colors.borderSubtle
            }

            Item {
                visible: WorkbenchController.keyboardMode
                width: hintText.implicitWidth + 4
                height: 46

                Text {
                    id: hintText
                    anchors.centerIn: parent
                    text: "←/→ move · Enter open · ↑ previews · ↓ actions · Esc"
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                    color: Colors.textMuted
                }
            }
        }

        // --- tooltip ------------------------------------------------------
        Rectangle {
            id: tip
            visible: root.tipVisible && root.tipText !== ""
            anchors {
                bottom: glass.top
                bottomMargin: 8
            }
            x: Math.max(4, Math.min(root.tipAnchorX - width / 2,
                dock.implicitWidth - width - 4))
            width: tipLabel.implicitWidth + 22
            height: 26
            radius: Theme.radiusSm
            color: Colors.glassElevated
            border.width: 1
            border.color: Colors.borderGlass

            Text {
                id: tipLabel
                anchors.centerIn: parent
                text: root.tipText
                font.family: Theme.fontUi
                font.pixelSize: 12
                color: Colors.textPrimary
            }
        }

        // --- keys (only while dockKeys: keyboard mode / drag / subview) ----
        Item {
            id: keyScope
            focus: dock.visible && root.dockKeys
            onFocusChanged: {
                if (focus) {
                    forceActiveFocus();
                }
            }
            Keys.enabled: focus

            Keys.onEscapePressed: {
                if (WorkbenchController.dragging) {
                    WorkbenchController.cancelDrag();
                } else {
                    WorkbenchController.handleEscape();
                }
            }
            Keys.onLeftPressed: {
                if (WorkbenchController.keyboardMode) {
                    WorkbenchController.moveSelection(-1);
                }
            }
            Keys.onRightPressed: {
                if (WorkbenchController.keyboardMode) {
                    WorkbenchController.moveSelection(1);
                }
            }
            Keys.onUpPressed: {
                if (WorkbenchController.keyboardMode) {
                    WorkbenchController.previewSelection();
                }
            }
            Keys.onDownPressed: {
                if (WorkbenchController.keyboardMode) {
                    WorkbenchController.menuSelection();
                }
            }
            Keys.onReturnPressed: {
                if (WorkbenchController.keyboardMode) {
                    WorkbenchController.activateSelection();
                }
            }
            Keys.onEnterPressed: {
                if (WorkbenchController.keyboardMode) {
                    WorkbenchController.activateSelection();
                }
            }
        }
    }

    // =====================================================================
    // edge reveal strip (autoHide only, hidden dock only, never fullscreen)
    // =====================================================================
    PanelWindow {
        id: edge
        visible: WorkbenchController.edgeZone
        screen: DesktopNavigationStore.targetScreen

        WlrLayershell.namespace: "voidshell-workbench-edge"
        exclusiveZone: -1
        color: "transparent"

        anchors {
            left: true
            right: true
            bottom: true
        }
        margins {
            left: Math.max(0, Math.round((root.screenW - root.edgeW) / 2))
            right: Math.max(0, Math.round((root.screenW - root.edgeW) / 2))
            bottom: 0
        }
        implicitWidth: root.edgeW
        implicitHeight: 4

        // Honest affordance: a faint accent line, brighter on approach —
        // the reveal zone is never an invisible blocker.
        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: 2
            radius: 1
            color: Colors.accentPrimary
            opacity: edgeHit.containsMouse ? 0.9 : 0.35

            Behavior on opacity {
                NumberAnimation {
                    duration: ManagerSettings.durationHover
                }
            }
        }

        MouseArea {
            id: edgeHit
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: WorkbenchController.edgeEntered()
            onExited: WorkbenchController.edgeExited()
        }
    }

    // =====================================================================
    // preview strip (above the dock; destroyed when closed)
    // =====================================================================
    PanelWindow {
        id: previewWin
        visible: SurfaceCoordinator.workbenchSurface === "WorkbenchPreview"
            && WorkbenchController.previewKey !== ""
        screen: DesktopNavigationStore.targetScreen

        WlrLayershell.namespace: "voidshell-workbench-preview"
        exclusiveZone: -1
        color: "transparent"

        anchors {
            left: true
            right: true
            bottom: true
        }
        margins {
            left: Math.max(0, Math.round((root.screenW - root.previewW) / 2))
            right: Math.max(0, Math.round((root.screenW - root.previewW) / 2))
            bottom: root.dockBottom + root.dockH + 10
        }
        implicitWidth: Math.min(root.previewW, root.dockMaxW)
        implicitHeight: previewLoader.item
            ? previewLoader.item.implicitHeight : 140

        onVisibleChanged: {
            WorkbenchController.setOverlayHovered(false);
            if (visible) {
                console.log("[voidshell] workbench: preview strip shown ("
                    + WorkbenchController.previewKey + ")");
            }
        }

        Loader {
            id: previewLoader
            anchors.fill: parent
            active: previewWin.visible
            sourceComponent: previewStrip
        }
    }

    Component {
        id: previewStrip

        PreviewStrip {
            requested: previewWin.visible
        }
    }

    // =====================================================================
    // action palette (above the dock; destroyed when closed)
    // =====================================================================
    PanelWindow {
        id: paletteWin
        visible: SurfaceCoordinator.workbenchSurface === "WorkbenchActionMenu"
            && WorkbenchController.menuKey !== ""
        screen: DesktopNavigationStore.targetScreen

        WlrLayershell.namespace: "voidshell-workbench-palette"
        exclusiveZone: -1
        color: "transparent"

        anchors {
            left: true
            right: true
            bottom: true
        }
        margins {
            left: Math.max(0, Math.round((root.screenW - root.paletteW) / 2))
            right: Math.max(0, Math.round((root.screenW - root.paletteW) / 2))
            bottom: root.dockBottom + root.dockH + 10
        }
        implicitWidth: root.paletteW
        implicitHeight: paletteLoader.item
            ? paletteLoader.item.implicitHeight : 120

        onVisibleChanged: {
            WorkbenchController.setOverlayHovered(false);
            if (visible) {
                console.log("[voidshell] workbench: action palette shown ("
                    + WorkbenchController.menuKey + ")");
            }
        }

        Loader {
            id: paletteLoader
            anchors.fill: parent
            active: paletteWin.visible
            sourceComponent: palettePanel
        }
    }

    Component {
        id: palettePanel

        ActionPalette {}
    }
}
