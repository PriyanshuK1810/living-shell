import QtQuick
import QtQuick.Effects
import "../../common"
import "../../services"

// VOID SHELL — workspace card (Shadow Spaces plan §5), label-free.
//
// One card per workspace in the overview: the card *is* its real window
// previews — no number badge, no count chip, no text (Neon Purple
// form; identity is carried by the preview and the indicator pills).
// Up to `ManagerSettings.maxStackedPreviews` windows are shown, stacked
// front-to-back in real focus order (Hyprland's own focus history);
// the rest stay reachable through the expanded view. State that cannot
// be shown by shape alone keeps a glyph: an urgent workspace shows its
// bang, an empty one says so.
//
// Shape (Neon Purple form): a wide ~2:1 card — the root is a fixed
// *slot* and the painted card sits inside it (`cardSurface`). The
// focused card is at full size behind a bright accent border with a
// violet halo; the others sit back — a little smaller and dimmer — so
// the strip reads as a carousel with one obvious centre. Slots keep
// the row still when focus moves: only the emphasis animates, the
// layout never re-flows.
//
// Click a card → switch workspace, click a preview → focus that window,
// double-click → the expanded view.
Item {
    id: root

    property var ws
    // True while this workspace's windows are open in the expanded
    // view: its card previews then hold their stills and release their
    // live slots to the view in front.
    property bool covered: false
    // A preview is being carried over the strip (drag in flight): this
    // card is the source, so it lifts above its neighbours and the
    // dragged preview is never hidden behind them.
    property bool lifted: false
    // A foreign preview is hovering this card — the drop would land here.
    property bool dropHover: false

    // The painted card, exposed for the strip's drop hit-test: a drop
    // must land on the rectangle that is *visibly* there, and the
    // surface can be smaller than its slot (idle cards sit back).
    readonly property Item surfaceItem: cardSurface

    // Slot: fixed for every card, sized for the full card + its halo.
    // Mirrored by the strip's own slot metrics (the per-row maths) —
    // keep both in sync.
    readonly property int slotW: 340
    readonly property int slotH: 176

    signal expandRequested(var ws)
    signal windowFocused(var toplevel)
    // A card click: exactly this workspace, nowhere else.
    signal switchRequested(var ws)
    // Pointer tracking of a carried preview, forwarded from the preview
    // to the strip (Phase D): the strip owns the hit-test across all
    // cards and decides where the drop lands — the card never dispatches
    // and never guesses.
    signal dragPosition(real sceneX, real sceneY)
    signal dragReleased(var toplevel, real sceneX, real sceneY)
    // Carrying ended over nothing: the strip clears its highlight and
    // no window moves.
    signal dragAborted()

    readonly property bool activeWs: HyprlandService.focusedWorkspace !== null && root.ws !== null && root.ws.id === HyprlandService.focusedWorkspace.id
    readonly property bool urgentWs: root.ws !== null && root.ws.urgent
    readonly property bool hovered: cardArea.containsMouse

    width: root.slotW
    height: root.slotH
    // While a preview is being carried, the card it came from rises
    // above the strip (same parent = same stacking context).
    z: root.lifted ? 40 : 0

    readonly property int windowCount: {
        HyprlandService.eventSerial;
        return root.ws === null ? 0 : HyprlandService.windowCountOf(root.ws);
    }

    // Focus order comes from the compositor (`lastwindow` +
    // `focusHistoryID`), never from a shell-side sort.
    readonly property var windows: {
        HyprlandService.eventSerial;
        return root.ws === null ? [] : HyprlandService.orderedWindows(root.ws);
    }

    readonly property int shownCount: Math.min(root.windows.length, Math.max(1, ManagerSettings.maxStackedPreviews))
    // Each stacked preview steps down-right so the ones behind peek out
    // at the card's bottom-right corner.
    readonly property int stackOffset: 7

    // ---- the painted card ------------------------------------------------
    // Everything below lives in `cardSurface`, centred in the slot. Its
    // scale is the carousel emphasis: full size for the focused card,
    // set back for the rest.
    Item {
        id: cardSurface

        readonly property int cardW: 328
        readonly property int cardH: 164

        width: cardW
        height: cardH
        anchors.centerIn: parent
        // The dim is a fade (it survives "reduced"); the scale is
        // movement and drops to 0 there (§12). Idle cards sit back only
        // a little — the neon border and halo carry the emphasis.
        opacity: root.activeWs ? 1 : 0.86
        scale: root.activeWs ? 1 : 0.94

        Behavior on scale {
            NumberAnimation {
                duration: ManagerSettings.durationCard
                easing.type: Easing.OutCubic
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: ManagerSettings.durationFade
                easing.type: Easing.OutCubic
            }
        }

        // Accent bloom behind the focused card: the card's own rounded
        // shape, drawn once into a layer padded by exactly `blurMax` and
        // blurred, so the falloff ends at the layer edge (GlassPanel
        // rule) — one static layer per visible bloom, no per-frame work.
        Item {
            id: bloom
            anchors.centerIn: parent
            width: cardSurface.cardW + 32
            height: cardSurface.cardH + 32
            opacity: root.activeWs ? 1 : 0
            // Visible only while it has something to show: an idle card
            // costs no layer, a fading-out one keeps it.
            visible: opacity > 0.01
            z: -30

            Behavior on opacity {
                NumberAnimation {
                    duration: ManagerSettings.durationFade
                    easing.type: Easing.OutCubic
                }
            }

            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1.0
                blurMax: 16
            }

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusXl + 6
                color: Colors.glowAccent
                border.width: 4
                border.color: Colors.accentStrong
            }
        }

        // ---- card surface --------------------------------------------------
        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusXl
            color: root.activeWs ? Colors.glassElevated : (root.hovered ? Colors.glassHover : Colors.glassCard)
            border.width: root.dropHover ? 2 : (root.activeWs && !root.urgentWs ? 0 : 1)
            border.color: root.dropHover ? Colors.accentStrong : (root.urgentWs ? Colors.danger : (root.hovered ? Colors.borderAccent : Colors.borderGlass))
            z: -20
        }

        // The neon ring: the reference's bright violet outline, sitting
        // over the halo so the focused card reads first (PRD 12.1
        // language for focus).
        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusXl
            color: "transparent"
            border.width: root.activeWs ? 3 : 0
            border.color: Colors.accentStrong
            visible: root.activeWs
            z: -10
        }

        // Click anywhere but a preview/header control → switch workspace.
        // The switch itself lives in the overview (one function shared with
        // the QA hook), so a click and a probe run exactly the same path.
        MouseArea {
            id: cardArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.ws !== null) {
                    root.switchRequested(root.ws);
                }
            }
            onDoubleClicked: {
                if (root.ws !== null) {
                    root.expandRequested(root.ws);
                }
            }
        }

        // Empty stage: an honest "nothing here" plate, no invented tiles.
        Rectangle {
            x: 12
            y: 12
            width: cardSurface.cardW - 24
            height: cardSurface.cardH - 24
            radius: 8
            color: Colors.glassPressed
            border.width: 1
            border.color: Colors.borderSubtle
            visible: root.windowCount === 0
            z: -20

            Text {
                anchors.centerIn: parent
                text: "Empty"
                font.family: Theme.fontUi
                font.pixelSize: 11
                color: Colors.textDisabled
            }
        }

        // ---- preview stack (label-free content) ----------------------------
        Item {
            id: stage
            x: 12
            y: 12
            width: cardSurface.cardW - 24
            height: cardSurface.cardH - 24

            Repeater {
                model: root.shownCount > 0 ? root.windows.slice(0, root.shownCount) : []

                WindowPreview {
                    required property var modelData
                    required property int index

                    toplevel: modelData
                    // Focused workspace keeps the first slots, other cards
                    // queue behind it (PreviewController decides).
                    priority: root.activeWs ? 5 : 12
                    requested: !root.covered

                    readonly property size fit: HyprlandService.fitWindow(modelData, stage.width, stage.height)
                    width: fit.width
                    height: fit.height
                    x: (stage.width - width) / 2 + root.stackOffset * index
                    y: (stage.height - height) / 2 + root.stackOffset * index
                    // Back of the stack first, front card on top.
                    z: -index

                    onFocused: tl => root.windowFocused(tl)
                    // While this preview is carried its card lifts above the
                    // strip; pointer tracking is forwarded to the strip,
                    // which owns the cross-card hit-test (Phase D).
                    onDraggingChanged: root.lifted = dragging
                    onDragPosition: (x, y) => root.dragPosition(x, y)
                    onDragReleased: (x, y) => root.dragReleased(toplevel, x, y)
                    onDragAborted: root.dragAborted()
                }
            }
        }

        // ---- urgency glyph (state, not identity) ---------------------------
        // The Neon Purple card carries no badge and no chips — its only
        // identity is the preview. Urgency is the one state shape cannot
        // show, so it keeps its bang: top-right, present only while the
        // workspace is urgent (PRD 12.1: never colour alone).
        Rectangle {
            x: cardSurface.cardW - 30
            y: 12
            width: 18
            height: 18
            radius: 9
            color: Colors.dangerDeep
            visible: root.urgentWs
            z: 5

            Text {
                anchors.centerIn: parent
                text: "!"
                font.family: Theme.fontUi
                font.weight: Font.DemiBold
                font.pixelSize: 11
                color: Colors.textOnAccent
            }
        }
    }
}
