import QtQuick
import Quickshell.Wayland
import "../../common"
import "../../services"

// VOID SHELL — one window preview (Shadow Spaces plan §5).
//
// A real capture of one Hyprland toplevel through ScreencopyView, with
// the honest three-step chain the spec demands — never a fake preview:
//
//   live      → this preview holds one of PreviewController's slots and
//               streams (budget: ManagerSettings.livePreviewBudget).
//   still     → no slot: the single frame the session captured when it
//               was created stays on screen, held in memory by the
//               compositor's screencopy buffers. Never on disk.
//   neutral   → no frame (capture refused, window gone, or the window
//               is on the sensitive-exclusion list): the app icon or
//               its initial on a plate; sensitive windows say so with a
//               lock glyph instead of showing content.
//
// No process is spawned and nothing polls: capture is a Wayland
// protocol request, and the only triggers are this item being created,
// its source changing, and a live slot being granted or released.
Item {
    id: root

    // The toplevel to capture (Hyprland's per-workspace window object).
    property var toplevel: null
    // Live-slot priority: 0 = most important (expanded view), higher =
    // less important. `requested:false` freezes a preview onto its
    // still and hands the slot to whatever is in front of it.
    property int priority: 20
    property bool requested: true

    signal focused(var toplevel)
    // --- drag-to-move (Phase D) -----------------------------------------
    // Press and carry this preview over another card: `dragging` lets
    // the card lift itself above the strip, `dragPosition` reports where
    // the pointer is (live highlight), `dragReleased` says where it came
    // down (scene coordinates). The overview resolves both against the
    // live layout and performs the move — this item never dispatches.
    signal dragPosition(real sceneX, real sceneY)
    signal dragReleased(real sceneX, real sceneY)
    // The pointer let go over nothing (or the grab was stolen): the
    // strip clears its highlight and no window moves.
    signal dragAborted()

    // The strip is the only surface with drop targets (the expanded view
    // covers the cards), so ExpandedView turns this off and keeps plain
    // clicks.
    property bool draggable: true
    readonly property bool dragging: hit.drag.active
    // A press that never crossed the threshold must still read as a
    // click; it is reset on the next press, so the click handler that
    // runs *after* release can still see it.
    property bool wasDragged: false
    property real pressX: 0
    property real pressY: 0

    readonly property string key: root.toplevel !== null ? String(root.toplevel.address) : ""
    readonly property var handle: root.toplevel !== null ? root.toplevel.wayland : null
    readonly property bool sensitive: HyprlandService.isSensitiveWindow(root.toplevel)
    // A sensitive window's surface is never handed to the capturer, no
    // matter what the fallback chain would otherwise do.
    readonly property bool capturable: !root.sensitive && root.handle !== null
    readonly property bool granted: root.requested && root.capturable && PreviewController.isLive(root.key)
    readonly property bool hasFrame: view.hasContent
    readonly property bool focusedWindow: root.toplevel !== null && root.toplevel.activated === true

    // What the card/expanded view is looking at right now — exposed for
    // QA probes and for the state overlay below.
    readonly property string mode: {
        if (!root.capturable) {
            return "hidden";
        }
        if (root.hasFrame) {
            return root.granted ? "live" : "still";
        }
        return "unavailable";
    }

    function syncRequest() {
        if (root.requested && root.capturable && root.key !== "") {
            PreviewController.requestLive(root.key, root.priority);
        } else {
            PreviewController.releaseLive(root.key);
        }
    }

    Component.onCompleted: root.syncRequest()
    Component.onDestruction: PreviewController.releaseLive(root.key)
    onKeyChanged: root.syncRequest()
    onRequestedChanged: root.syncRequest()
    onCapturableChanged: root.syncRequest()

    // --- carried surface -------------------------------------------------
    // Everything visual lives in `carrier`, not in `root`: the card
    // keeps root's slot position as a binding, while the drag moves only
    // the carrier — and the release below puts it straight back, so a
    // cancelled drop never leaves a preview stranded.
    Item {
        id: carrier
        x: 0
        y: 0
        width: root.width
        height: root.height

    // --- captured content ----------------------------------------------
    ScreencopyView {
        id: view
        anchors.fill: parent
        // live:false still captures exactly one frame on session
        // creation (quickshell's createContext() asks for it), which is
        // where every "last still" on this screen comes from.
        captureSource: root.capturable ? root.handle : null
        live: root.granted
        paintCursor: false
        visible: root.hasFrame
    }

    // --- neutral plate: no frame, no invention --------------------------
    Rectangle {
        id: plate
        anchors.fill: parent
        visible: !root.hasFrame
        radius: 8
        color: Colors.glassPressed
        border.width: 1
        border.color: root.sensitive ? Colors.borderGlass : Colors.borderSubtle

        Column {
            anchors.centerIn: parent
            spacing: 3

            // Lock glyph for an excluded window — the reason is visible,
            // not implied (PRD 37).
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.sensitive
                text: String.fromCodePoint(0xF023) // fa-lock
                font.family: Theme.fontMono
                font.pixelSize: 13
                color: Colors.textMuted
            }

            // Desktop-entry icon when one exists.
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !root.sensitive && root.toplevel !== null && HyprlandService.iconUrlForWindow(root.toplevel) !== ""
                source: root.toplevel !== null ? HyprlandService.iconUrlForWindow(root.toplevel) : ""
                asynchronous: true
                width: 18
                height: 18
                fillMode: Image.PreserveAspectFit
            }

            // First letter of the class when there is no icon.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !root.sensitive && root.toplevel !== null && HyprlandService.iconUrlForWindow(root.toplevel) === ""
                text: root.toplevel !== null ? HyprlandService.initialForWindow(root.toplevel) : ""
                font.family: Theme.fontUi
                font.weight: Font.DemiBold
                font.pixelSize: 14
                color: Colors.textSecondary
            }

            // State word only where it carries real information.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.sensitive
                text: "Hidden"
                font.family: Theme.fontUi
                font.pixelSize: 9
                color: Colors.textMuted
            }
        }
    }

    // --- chrome ----------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        radius: 8
        color: "transparent"
        border.width: root.focusedWindow ? 2 : 1
        border.color: root.focusedWindow ? Colors.borderAccentStrong : (root.dragging || hit.containsMouse ? Colors.borderGlass : Qt.rgba(1, 1, 1, 0.12))
        z: 2
    }
    } // carrier

    // Focus this window — unless the press turned into a drag (Phase D).
    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        z: 3

        // The pointer carries `carrier` across the strip; the card's own
        // slot (root) never moves, so the stack layout stays put and a
        // drop onto nothing simply snaps back when carrier.x/y reset.
        drag.target: root.draggable ? carrier : null
        drag.axis: Drag.XAndYAxis
        drag.threshold: 10

        onPressed: mouse => {
            root.wasDragged = false;
            root.pressX = mouse.x;
            root.pressY = mouse.y;
        }
        onPositionChanged: mouse => {
            if (!pressed || !root.draggable) {
                return;
            }
            if (!root.wasDragged && (Math.abs(mouse.x - root.pressX) > 10 || Math.abs(mouse.y - root.pressY) > 10)) {
                root.wasDragged = true;
            }
            if (root.wasDragged) {
                const p = hit.mapToItem(null, mouse.x, mouse.y);
                root.dragPosition(p.x, p.y);
            }
        }
        onReleased: mouse => {
            if (root.wasDragged) {
                const p = hit.mapToItem(null, mouse.x, mouse.y);
                root.dragReleased(p.x, p.y);
            }
            // Put the carrier back in its slot: the drop already ran (or
            // there was nothing under the pointer — an honest no-op).
            // `wasDragged` is deliberately left set: the `clicked` that
            // follows must not read a completed drag as a focus click
            // (the next press resets it).
            carrier.x = 0;
            carrier.y = 0;
        }
        onCanceled: {
            carrier.x = 0;
            carrier.y = 0;
            root.dragAborted();
        }
        onClicked: {
            if (!root.wasDragged) {
                root.focused(root.toplevel);
            }
        }
    }
}
