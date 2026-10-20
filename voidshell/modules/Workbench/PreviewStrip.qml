import QtQuick
import "../WorkspaceOverview" as Overview
import "../../common"
import "../../services"

// VOID SHELL — the Workbench preview strip (Workbench plan §preview).
//
// Real captures of one app's windows, nothing else:
//
//  * the windows come from ApplicationStore (the same model the
//    overview and the shelf use — no second window list) and are
//    capped at five per strip so the surface stays bounded on a
//    1280-logical screen; the remainder is an honest "+N" count,
//    never a truncated lie;
//  * WindowPreview owns the capture budget and the fallback chain
//    (live → still → icon+title): a window that cannot be captured
//    shows its fallback rather than a fake screenshot, and its
//    `priority` queues behind the overview's captures;
//  * click ⇒ focus that window (WindowActions validates and switches
//    workspace on the way; it never opens the overview);
//  * the whole strip reports pointer hover so the controller's leave
//    timer can retire it — an IPC/QA-opened strip has no pointer to
//    leave with and stays until told otherwise.
//
// The window above this item is created only while the strip is open
// (a Loader gates it), so hiding the strip destroys every ScreencopyView
// — exactly the StageShelf rule: captures exist only while the surface
// that shows them exists.
Item {
    id: root

    // Bound by the dock window: false ⇒ the strip is on its way out and
    // must stop asking for frames.
    property bool requested: true

    readonly property var slot: ApplicationStore.slotByKey(WorkbenchController.previewKey)
    readonly property var wins: slot !== null && slot.windows !== undefined ? slot.windows.slice(0, 5) : []
    readonly property int extra: slot !== null ? Math.max(0, slot.count - 5) : 0

    implicitWidth: 820
    implicitHeight: body.implicitHeight + 26
    // A narrow screen (or six-plus windows) must never bleed past the
    // glass: the row clips, the honest "+N" states the rest.
    clip: true

    // --- glass shell -----------------------------------------------------
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Theme.radiusLg
        color: Colors.glassCard
        border.width: 1
        border.color: Colors.borderGlass
    }

    // Hover probe behind the content: hovering anywhere on the strip
    // (including over a capture) counts as "the pointer is here".
    MouseArea {
        id: probe
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: WorkbenchController.setOverlayHovered(true)
        onExited: WorkbenchController.setOverlayHovered(false)
    }

    Column {
        id: body
        anchors.centerIn: parent
        width: root.width - 28
        spacing: 10

        // --- header: which app, how many windows, how to use it ---------
        Item {
            width: parent.width
            height: 20

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    height: 20
                    verticalAlignment: Text.AlignVCenter
                    text: root.slot !== null ? root.slot.name : ""
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Colors.textPrimary
                }

                Text {
                    height: 20
                    verticalAlignment: Text.AlignVCenter
                    text: root.slot !== null && root.slot.count > 0
                        ? root.slot.count + (root.slot.count === 1 ? " window" : " windows") : ""
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    color: Colors.textMuted
                }
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "click to focus"
                font.family: Theme.fontUi
                font.pixelSize: 11
                color: Colors.textMuted
                opacity: 0.8
            }
        }

        // --- the captures -------------------------------------------------
        Row {
            id: previewRow
            width: parent.width
            spacing: 6

            Repeater {
                model: root.wins

                Overview.WindowPreview {
                    required property var modelData
                    required property int index

                    toplevel: modelData
                    requested: root.requested
                    // Queue behind the overview and the shelf: the dock's
                    // strip is the least urgent consumer of frames.
                    priority: 6 + index
                    draggable: false

                    readonly property size fit: HyprlandService.fitWindow(modelData, 140, 80)
                    width: fit.width
                    height: fit.height

                    onFocused: toplevel => WindowActions.activateAddress(toplevel.address)
                }
            }

            // The bounded remainder, stated plainly.
            Text {
                visible: root.extra > 0
                height: 40
                verticalAlignment: Text.AlignVCenter
                text: "+" + root.extra
                font.family: Theme.fontMono
                font.pixelSize: 12
                color: Colors.textMuted
            }
        }
    }
}
