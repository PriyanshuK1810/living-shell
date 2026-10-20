import QtQuick
import Quickshell
import "../../common"
import "../../services"

// VOID SHELL — the Workbench action palette (Workbench plan §palette).
//
// Right-click an app slot ⇒ its real actions, and nothing else:
//
//  * the rows come from ContextActionRegistry: up to four *actual*
//    desktop actions from the app's own .desktop file (with their own
//    icons), then the opt-in universal rows (empty by default). A
//    section with no provider is not rendered — no filler, no invented
//    verbs, no title inference;
//  * availability is re-evaluated when the palette opens (a missing
//    terminal simply has no row), and clicking runs the trusted
//    handler then retires the palette — one action, one menu;
//  * system controls (battery/Wi-Fi/Bluetooth/volume/notifications)
//    are deliberately absent: the dock never duplicates the top bar.
//
// Open is already gated by the controller (`hasAny` — a palette with
// nothing to show never opens), so the view may assume at least one
// section exists while it is up, and still hides empty sections
// defensively.
Item {
    id: root

    readonly property var slot: ApplicationStore.slotByKey(WorkbenchController.menuKey)
    readonly property var sections: slot !== null
        ? ContextActionRegistry.sectionsFor(slot.entry) : ({ app: [], universal: [] })
    readonly property int rowCount: sections.app.length + sections.universal.length

    implicitWidth: 250
    implicitHeight: body.implicitHeight + 20

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Theme.radiusLg
        color: Colors.glassCard
        border.width: 1
        border.color: Colors.borderGlass
    }

    // Same contract as the preview strip: pointer anywhere on the
    // palette counts as engagement (see leaveTimer in the controller).
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
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: 10
        anchors.leftMargin: 10
        width: parent.width - 20
        spacing: 2

        // --- app section header (the app itself) -------------------------
        Text {
            visible: sections.app.length > 0
            width: parent.width
            height: 18
            verticalAlignment: Text.AlignVCenter
            text: root.slot !== null ? root.slot.name : ""
            font.family: Theme.fontUi
            font.pixelSize: 11
            font.weight: Font.DemiBold
            color: Colors.textMuted
            elide: Text.ElideRight
        }

        Repeater {
            model: root.sections.app
            delegate: actionRow
        }

        // --- universal section (opt-in; hidden when empty) ---------------
        Item {
            visible: sections.universal.length > 0 && sections.app.length > 0
            width: parent.width
            height: 9

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Colors.borderSubtle
            }
        }

        Text {
            visible: sections.universal.length > 0
            width: parent.width
            height: 18
            verticalAlignment: Text.AlignVCenter
            text: "Actions"
            font.family: Theme.fontUi
            font.pixelSize: 11
            font.weight: Font.DemiBold
            color: Colors.textMuted
        }

        Repeater {
            model: root.sections.universal
            delegate: actionRow
        }
    }

    // --- one action row ---------------------------------------------------
    // A trusted handler only: `run()` lives in code (a desktop action's
    // own execute(), or a catalog entry), never a command from JSON.
    Component {
        id: actionRow

        Rectangle {
            required property var modelData

            width: body.width
            height: 28
            radius: 8
            color: rowHit.containsMouse ? Colors.glassHover : "transparent"

            // Icon when the theme has one, the label's first letter
            // otherwise — never an empty hole.
            Item {
                id: iconSlot
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16

                Image {
                    id: rowIcon
                    anchors.fill: parent
                    source: modelData.icon !== undefined && modelData.icon !== ""
                        ? Quickshell.iconPath(modelData.icon, "") : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    visible: status === Image.Ready
                }

                Text {
                    anchors.centerIn: parent
                    visible: rowIcon.status !== Image.Ready
                    text: modelData.label !== undefined && modelData.label !== ""
                        ? modelData.label.charAt(0) : "·"
                    font.family: Theme.fontUi
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    color: Colors.textMuted
                }
            }

            Text {
                anchors.left: iconSlot.right
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label !== undefined ? modelData.label : ""
                font.family: Theme.fontUi
                font.pixelSize: 12
                color: Colors.textPrimary
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            MouseArea {
                id: rowHit
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    try {
                        modelData.run();
                    } catch (e) {
                        console.warn("[voidshell] workbench: action failed: " + e);
                    }
                    WorkbenchController.closeTransient();
                }
            }
        }
    }
}
