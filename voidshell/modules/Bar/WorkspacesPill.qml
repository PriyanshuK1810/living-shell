import QtQuick
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — workspaces pill (PRD 12.1 + Shadow Spaces plan §4).
//
// One pill, two renderings selected by the manager setting:
//
//   style "number" — the original strip: five fixed 30px buttons over
//                    the workspace ids 1..5 (a slot only lights up when
//                    Hyprland reports that workspace), wheel steps
//                    through existing ids with wrap-around. Kept as-is
//                    so `managerEnabled = false` restores the previous
//                    interface without a second component tree.
//
//   style "dash"   — the desktop manager's horizontal dash: five fixed
//                    30px slots over the *real* eligible workspaces, one
//                    bright underline that slides between them, and a
//                    bounded scroll window that always keeps the focused
//                    workspace visible. Slot geometry never changes, so
//                    the pill's footprint is byte-identical to the strip
//                    it replaces (5*30 + 4*2 + (slantDepth+14)*2 = 218px)
//                    — the bar never reflows while workspaces come and go.
//
// Shared for both: click activates a workspace, the wheel steps through
// existing workspaces in the same direction as before (the dash then
// scrolls the strip to follow focus), and a secondary click toggles the
// overview — the same action as SUPER+W (plan §6).
Comp.SlantedPill {
    id: root
    property string style: "dash"
    height: Theme.barHeight
    width: (root.dashMode ? root.dashContentWidth : wsRow.implicitWidth) + (Theme.slantDepth + 14) * 2
    fillColor: Colors.glassBase
    borderColor: Colors.borderSubtle
    glowEnabled: true

    // --- shared state ---------------------------------------------------
    // Legacy strip: fixed 1..5 slots. A slot only lights up when
    // Hyprland reports that workspace, so no number is ever faked.
    readonly property var slots: [1, 2, 3, 4, 5]
    readonly property bool urgentAny: HyprlandService.urgentCount > 0

    readonly property bool dashMode: ManagerSettings.managerEnabled && root.style === "dash"

    // Fixed dash geometry (plan §4): 30px slot, 2px gap, five visible.
    readonly property int slotSize: 30
    readonly property int slotGap: 2
    readonly property int slotStep: root.slotSize + root.slotGap
    readonly property int maxVisible: 5
    readonly property int dashContentWidth: root.maxVisible * root.slotSize + (root.maxVisible - 1) * root.slotGap

    // Real workspaces in id order (specials excluded upstream). The list
    // never reorders with focus — only the scroll window moves.
    readonly property var dashWorkspaces: root.dashMode ? HyprlandService.eligibleWorkspaces : []

    // Index of the focused workspace inside that list, or -1. Re-read on
    // every IPC event because window/workspace lists carry no signal of
    // their own.
    readonly property int focusIndex: {
        HyprlandService.eventSerial;
        if (!root.dashMode) {
            return -1;
        }
        const ws = HyprlandService.focusedWorkspace;
        if (!ws) {
            return -1;
        }
        const list = root.dashWorkspaces;
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === ws.id) {
                return i;
            }
        }
        return -1;
    }

    readonly property bool focusUrgent: {
        const ws = HyprlandService.focusedWorkspace;
        return !!ws && ws.urgent === true;
    }

    // --- bounded scrolling ----------------------------------------------
    // The visible window is whole slots only and never leaves
    // [0, max(0, count - 5)], so the strip slides instead of growing.
    property int slotOffset: 0
    readonly property int maxOffset: Math.max(0, root.dashWorkspaces.length - root.maxVisible)

    function syncScroll() {
        if (!root.dashMode) {
            root.slotOffset = 0;
            return;
        }
        const max = Math.max(0, root.dashWorkspaces.length - root.maxVisible);
        let next = Math.max(0, Math.min(root.slotOffset, max));
        const idx = root.focusIndex;
        if (idx >= 0) {
            if (idx < next) {
                next = idx;
            } else if (idx > next + root.maxVisible - 1) {
                next = idx - root.maxVisible + 1;
            }
        }
        next = Math.max(0, Math.min(next, max));
        if (next !== root.slotOffset) {
            root.slotOffset = next;
        }
    }

    // Footprint invariant (plan §4): the dash must keep the exact width
    // of the numbered strip it replaces (5*30 + 4*2 + 2*(slant+14) =
    // 218px) so the bar can never reflow while workspaces come and go.
    // Silent when correct, loud (console.warn — the QA gates grep for
    // it) the moment a future edit breaks it.
    function checkFootprint() {
        if (root.dashMode && Math.round(root.width) !== 218) {
            console.warn("[voidshell] workspaces pill footprint changed:", root.width, "expected 218");
        }
    }

    onFocusIndexChanged: syncScroll()
    onDashWorkspacesChanged: syncScroll()
    onWidthChanged: checkFootprint()
    Component.onCompleted: {
        syncScroll();
        checkFootprint();
    }

    // Window/workspace events rebuild the eligible list; the offset is
    // re-derived from real state each time (never from a timer).
    Connections {
        target: HyprlandService
        function onEventSerialChanged() {
            root.syncScroll();
        }
    }

    // Wheel: unchanged behaviour — one workspace per notch, same
    // direction as before (wraps through existing ids). The touchpad
    // joins in too: Wayland two-finger scroll arrives as `pixelDelta`
    // with a zero `angleDelta`, so both streams are read and folded
    // into detents (120 units, or 180px of travel, per step) — a
    // flick walks a few workspaces instead of every delta tick
    // switching one. The dash then scrolls itself to keep the newly
    // focused workspace visible.
    WheelHandler {
        id: wsWheel
        acceptedModifiers: Qt.NoModifier
        property real acc: 0
        onWheel: event => {
            const pd = event.pixelDelta;
            const ad = event.angleDelta;
            const dpx = Math.abs(pd.x) >= Math.abs(pd.y) ? pd.x : pd.y;
            const dan = Math.abs(ad.x) >= Math.abs(ad.y) ? ad.x : ad.y;
            let d = 0;
            let unit = 0;
            if (dpx !== 0) {
                d = dpx;
                unit = 180;
            } else if (dan !== 0) {
                d = dan;
                unit = 120;
            }
            if (d === 0) {
                return;
            }
            wsWheel.acc += d / unit;
            let guard = 0;
            while (Math.abs(wsWheel.acc) >= 1 && guard < 6) {
                // Positive delta steps backwards — the direction the
                // old angle-only handler took for a rising y.
                const back = wsWheel.acc > 0;
                wsWheel.acc += back ? -1 : 1;
                HyprlandService.goToRelativeWorkspace(back ? -1 : 1);
                guard++;
            }
        }
    }

    // Secondary click toggles the overview (plan §6) — same surface the
    // SUPER+W binding opens, so both paths stay in sync through
    // PopupManager.
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: PopupManager.toggle("overview")
    }

    // Content area: clipped in dash mode so the sliding strip can never
    // paint over the neighbouring pills; unclipped in legacy mode so the
    // original rendering (glow included) is untouched.
    Item {
        id: body
        anchors.centerIn: parent
        clip: root.dashMode
        width: root.dashMode ? root.dashContentWidth : wsRow.implicitWidth
        height: 30

        // ---- dash strip ------------------------------------------------
        Item {
            id: slotsRow
            visible: root.dashMode
            x: -root.slotOffset * root.slotStep
            width: root.dashWorkspaces.length * root.slotStep
            height: parent.height

            Behavior on x {
                NumberAnimation {
                    duration: ManagerSettings.durationPill
                    easing.type: Easing.OutCubic
                }
            }

            // One bright underline for the focused slot. It moves inside
            // the strip, so it always lands on its own slot and shares
            // the strip's timing exactly.
            Rectangle {
                id: dashMark
                visible: root.focusIndex >= 0
                x: root.focusIndex * root.slotStep + 1
                y: parent.height - 6
                width: root.slotSize - 2
                height: 5
                radius: 2.5
                color: root.focusUrgent ? Colors.danger : Colors.accentLight
                opacity: 0.9

                Behavior on x {
                    NumberAnimation {
                        duration: ManagerSettings.durationPill
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on color {
                    ColorAnimation {
                        // Colour is a fade, not movement: it survives
                        // "reduced" (fades only) and dies under "off".
                        duration: ManagerSettings.durationFade
                    }
                }
            }

            Repeater {
                model: root.dashWorkspaces

                delegate: Item {
                    id: slot
                    required property var modelData
                    required property int index

                    // Real window count, re-read on every IPC event so
                    // the chip cannot show a stale number.
                    readonly property int windowCount: {
                        HyprlandService.eventSerial;
                        return HyprlandService.windowCountOf(modelData);
                    }

                    x: index * root.slotStep
                    width: root.slotStep
                    height: parent ? parent.height : 30

                    Comp.WorkspaceButton {
                        anchors.centerIn: parent
                        style: "dash"
                        index: slot.modelData.id
                        // Activate by name: ids are the fallback, names
                        // are what a named workspace really is.
                        selectionTarget: slot.modelData.name
                        exists: true
                        urgent: slot.modelData.urgent === true
                        active: root.focusIndex === slot.index
                        occupied: slot.windowCount > 0
                        count: slot.windowCount
                        onSelected: target => HyprlandService.goToWorkspace(target)
                    }
                }
            }
        }

        // ---- legacy numbered strip (manager disabled) -------------------
        Row {
            id: wsRow
            visible: !root.dashMode
            anchors.centerIn: parent
            spacing: 2

            Repeater {
                model: root.slots

                Comp.WorkspaceButton {
                    required property int modelData
                    style: "number"
                    index: modelData
                    active: HyprlandService.focusedWorkspaceName === String(modelData)
                    urgent: HyprlandService.isUrgent(modelData)
                    exists: HyprlandService.workspaceById(modelData) !== null
                    onSelected: idx => HyprlandService.goToWorkspace(idx)
                }
            }
        }
    }
}
