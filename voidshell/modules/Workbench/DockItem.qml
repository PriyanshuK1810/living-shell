import QtQuick
import "../../common"
import "../../services"

// VOID SHELL — one Workbench dock slot (Workbench plan §dock).
//
// A slot is a plain snapshot from ApplicationStore (`slot`): desktop
// entry or class group, its windows, and where they live. This item
// renders exactly the state vocabulary the plan allows — never a
// bouncing icon, never a colour-only signal:
//
//   pinned / running-here  → solid violet dash (belongs on this dock)
//   running-elsewhere      → muted segmented dash (alive, not here)
//   focused                → brighter plate + accent border
//   multi-window           → stacked-bars glyph at the plate corner
//   urgent                 → exactly one pulse when urgency arrives
//   keyboard-current       → accent ring while keyboard mode drives it
//
// Left click runs the activation policy in WorkbenchController (launch /
// focus / MRU cycle / preview), middle click requests a new instance,
// right click opens the action palette — and only if it has real rows.
// A pinned slot can be dragged (14 px threshold) to reorder: the
// controller validates and persists atomically, a rejected write snaps
// the plate back, and nothing ever auto-unpins.
Item {
    id: root

    property var slot: null
    property int slotIndex: 0
    // Hover index of the whole row (magnification's neighbour term).
    property int rowHoverIndex: -1

    implicitWidth: 52
    implicitHeight: 46

    readonly property bool pinned: slot !== null && slot.pinned === true
    readonly property bool here: slot !== null && slot.here > 0
    readonly property int count: slot !== null ? slot.count : 0
    readonly property bool multi: root.count > 1
    readonly property bool urgent: slot !== null && slot.urgent === true
    readonly property bool focused: slot !== null && slot.focused === true
    readonly property bool hovered: hit.containsMouse
    readonly property bool keyboardCurrent: WorkbenchController.keyboardMode
        && WorkbenchController.keyboardIndex === root.slotIndex
    readonly property bool beingDragged: WorkbenchController.dragging
        && slot !== null && String(WorkbenchController.dragKey) === String(slot.key)
    // Placeholder ring: a *different* slot is being dragged onto this one.
    readonly property bool dropTarget: WorkbenchController.dragging
        && slot !== null && String(WorkbenchController.dropKey) === String(slot.key)
        && !root.beingDragged
    // The first running-only slot gets the group divider on its left.
    readonly property bool needsDivider: !root.pinned && root.slotIndex === ApplicationStore.pins.length

    // Magnification (plan §magnification): factors live in
    // WorkbenchSettings (off/subtle/full → magHover/magAdjacent), so no
    // view hardcodes a scale. Layout never moves — only the plate
    // scales — so the row cannot jitter under the pointer.
    //
    // The hovered term is the *row's* hover index, not this item's
    // `hit.containsMouse`: during the tooltip's window resize Qt
    // re-runs hover and slot ownership hands off to the window probe
    // for a frame — keying mag off per-item hover dipped the plate on
    // every tip show (flicker). The row index changes only on a real
    // slot entry, and survives the handoff; it clears when the pointer
    // leaves the dock.
    readonly property real mag: {
        if (WorkbenchSettings.magnification === "off") {
            return 1.0;
        }
        if (root.rowHoverIndex === root.slotIndex) {
            return WorkbenchSettings.magHover;
        }
        if (root.rowHoverIndex >= 0 && Math.abs(root.rowHoverIndex - root.slotIndex) === 1) {
            return WorkbenchSettings.magAdjacent;
        }
        return 1.0;
    }

    readonly property string iconSource: slot !== null ? String(slot.icon) : ""
    readonly property string initial: slot !== null && slot.name !== "" ? slot.name.charAt(0) : "▢"
    // State-dash shape: solid violet (pinned or here) vs segmented
    // muted (running elsewhere, not pinned).
    readonly property bool violetDash: root.pinned || root.here
    readonly property bool segmentedDash: root.count > 0 && !root.violetDash

    // Group divider before the first running slot.
    Rectangle {
        visible: root.needsDivider
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: 28
        color: Colors.borderSubtle
    }

    // Drop placeholder: where a dragged pin would land.
    Rectangle {
        visible: root.dropTarget
        x: (root.width - 46) / 2
        y: -3
        width: 46
        height: 46
        radius: 14
        color: ThemeService.light ? Qt.rgba(139 / 255, 77 / 255, 255 / 255, 0.12) : Qt.rgba(139 / 255, 77 / 255, 255 / 255, 0.18)
        border.width: 2
        border.color: Colors.accentPrimary
        opacity: 0.95
    }

    // Invisible drag handle: the MouseArea drags *this*, and the plate
    // follows through a binding — so the plate's own layout position
    // survives every drag (release just zeroes the handle).
    Item {
        id: dragHandle
        x: 0
        y: 0
        width: 1
        height: 1
    }

    // --- the plate -------------------------------------------------------
    Item {
        id: plate
        property real baseX: (root.width - width) / 2
        x: plate.baseX + dragHandle.x
        y: 0
        width: 40
        height: 40
        scale: root.beingDragged ? 1.12 : root.mag
        z: root.beingDragged ? 5 : 0
        opacity: root.slot === null ? 0.5 : 1.0

        Behavior on scale {
            NumberAnimation {
                duration: WorkbenchSettings.magAnimated ? ManagerSettings.durationHover : 0
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: root.focused ? Colors.glassHover : Colors.glassCard
            border.width: root.focused || root.keyboardCurrent ? 1.5 : 1
            border.color: root.keyboardCurrent ? Colors.accentPrimary
                : (root.focused ? Colors.borderAccentStrong : Colors.borderGlass)
        }

        Image {
            id: icon
            anchors.centerIn: parent
            width: 26
            height: 26
            source: root.iconSource
            fillMode: Image.PreserveAspectFit
            visible: status === Image.Ready
            asynchronous: true
        }

        // Honest fallback: the app's first letter on the plate, never a
        // fake screenshot or a guessed glyph.
        Text {
            anchors.centerIn: parent
            visible: icon.status !== Image.Ready
            text: root.initial
            font.family: Theme.fontUi
            font.pixelSize: 15
            font.weight: Font.Medium
            color: Colors.textSecondary
        }

        // Multi-window: stacked-bars glyph (shape, not colour, carries
        // the state — PRD: colour alone never carries state).
        Item {
            visible: root.multi
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: -3
            width: 11
            height: 9
            z: 2

            Rectangle {
                x: 0
                y: 0
                width: 8
                height: 3
                radius: 1.5
                color: Colors.textSecondary
            }
            Rectangle {
                x: 3
                y: 5
                width: 8
                height: 3
                radius: 1.5
                color: Colors.textMuted
            }
        }
    }

    // --- state dash ------------------------------------------------------
    Item {
        id: dash
        anchors.horizontalCenter: parent.horizontalCenter
        y: 41
        width: 20
        height: 4

        Rectangle {
            visible: root.violetDash
            anchors.fill: parent
            radius: 2
            color: Colors.accentPrimary
        }

        Row {
            visible: root.segmentedDash
            anchors.centerIn: parent
            spacing: 2

            Repeater {
                model: 3

                Rectangle {
                    width: 4
                    height: 3
                    radius: 1.5
                    color: Colors.textMuted
                }
            }
        }
    }

    // One pulse when urgency arrives — one iteration, never a loop
    // (plan §urgent: a single pulse, no nagging animation).
    SequentialAnimation {
        id: urgentPulse

        NumberAnimation {
            target: dash
            property: "opacity"
            to: 0.15
            duration: 170
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: dash
            property: "opacity"
            to: 1.0
            duration: 340
            easing.type: Easing.OutCubic
        }
    }

    onUrgentChanged: {
        if (root.urgent) {
            urgentPulse.restart();
        }
    }

    // --- pointer ---------------------------------------------------------
    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        enabled: root.slot !== null

        // Drag only for pinned slots: a running-only slot dropped
        // anywhere simply finds no pin to join (no auto-pin), so the
        // gesture is refused at the source instead of failing late.
        // QQuickDrag has no `enabled` switch — a null target disables it.
        drag.target: root.pinned && !WorkbenchController.locked ? dragHandle : null
        drag.axis: Drag.XAxis
        drag.threshold: 14
        drag.minimumX: -2000
        drag.maximumX: 2000

        onPositionChanged: mouse => {
            if (root.slot === null) {
                return;
            }
            // QQuickDrag exposes no started() signal: `drag.active` flips
            // to true exactly when the 14 px threshold is crossed, and
            // that is when the controller drag begins.
            if (drag.active && !WorkbenchController.dragging) {
                WorkbenchController.beginDrag(root.slot.key);
            }
            if (!WorkbenchController.dragging) {
                return;
            }
            root.updateDrop(mouse.x);
        }

        onReleased: mouse => {
            // The handle only ever moves after the threshold was crossed,
            // so a zeroed handle means "click" and a moved one means
            // "drop" (release also clears drag.active, so it can't tell).
            const moved = dragHandle.x !== 0;
            dragHandle.x = 0;
            if (root.slot === null) {
                return;
            }
            if (moved) {
                if (!WorkbenchController.dragging) {
                    // Cover the one-event race where the crossing move
                    // never delivered another positionChanged.
                    WorkbenchController.beginDrag(root.slot.key);
                    root.updateDrop(mouse.x);
                }
                if (String(WorkbenchController.dragKey) === String(root.slot.key)) {
                    WorkbenchController.commitDrag();
                } else {
                    WorkbenchController.cancelDrag();
                }
                return;
            }
            if (mouse.button === Qt.LeftButton) {
                WorkbenchController.activateSlot(root.slot);
            } else if (mouse.button === Qt.MiddleButton) {
                WorkbenchController.newInstance(root.slot);
            } else if (mouse.button === Qt.RightButton) {
                WorkbenchController.openMenu(root.slot.key);
            }
        }

        onCanceled: {
            dragHandle.x = 0;
            if (root.slot !== null && WorkbenchController.dragging
                    && String(WorkbenchController.dragKey) === String(root.slot.key)) {
                WorkbenchController.cancelDrag();
            }
        }
    }

    // Any drag that ends anywhere (Escape, lost grab, model change)
    // zeroes the handle, so a cancelled drag can never leave a plate
    // parked mid-row.
    Connections {
        target: WorkbenchController

        function onDraggingChanged() {
            if (!WorkbenchController.dragging) {
                dragHandle.x = 0;
            }
        }
    }

    // Drop-target lookup: which pinned slot does the pointer (row
    // coordinates) sit past? Pin count bounds the index — a drop never
    // lands on a running-only slot, and never past the last pin.
    function updateDrop(mouseX) {
        const row = root.parent;
        if (row === null || row === undefined) {
            return;
        }
        const rowX = root.x + mouseX;
        const pins = ApplicationStore.pins.length;
        let landed = 0;
        for (let i = 0; i < row.children.length; i++) {
            const c = row.children[i];
            if (c === undefined || c === null || c.slotIndex === undefined || c.slot === undefined) {
                continue;
            }
            if (c.slot === null || c.slot.pinned !== true) {
                continue;
            }
            if (rowX > c.x + c.width / 2) {
                landed = Math.max(landed, c.slotIndex + 1);
            }
        }
        let idx = landed - 1;
        if (idx < 0) {
            idx = 0;
        }
        if (idx > pins - 1) {
            idx = pins - 1;
        }
        const slots = ApplicationStore.slots;
        if (idx >= 0 && idx < slots.length) {
            WorkbenchController.dragOver(slots[idx].key);
        }
    }
}
