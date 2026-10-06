import QtQuick
import ".."

// VOID SHELL — popup panel header: title (+ optional subtitle) with a real
// close affordance on the right. `closed` is wired to PopupManager by the
// owning panel, so Escape and the X button behave identically.
// `centered` centers the label block across the panel (used by the
// dashboard Overview tab); the close button stays pinned right.
Item {
    id: root
    property string title: ""
    property string subtitle: ""
    property bool showClose: true
    property bool centered: false
    // Larger title for the dashboard's reference-matched header.
    property int titleSize: 15
    signal closed

    implicitWidth: 260
    implicitHeight: subtitle !== "" ? 40 : 30

    Column {
        id: labels
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 2
        // Centered mode spans the full width (close button and all) so
        // the aligned text lands on the panel's true center.
        width: root.centered ? parent.width - 4 : (root.showClose ? parent.width - 36 : parent.width) - 4
        spacing: 1

        Text {
            width: parent.width
            elide: Text.ElideRight
            horizontalAlignment: root.centered ? Text.AlignHCenter : Text.AlignLeft
            text: root.title
            font.family: Theme.fontUi
            font.weight: root.titleSize > 15 ? Font.Bold : Font.DemiBold
            font.pixelSize: root.titleSize
            color: Colors.textPrimary
        }

        Text {
            width: parent.width
            elide: Text.ElideRight
            horizontalAlignment: root.centered ? Text.AlignHCenter : Text.AlignLeft
            text: root.subtitle
            font.family: Theme.fontUi
            font.pixelSize: 12
            color: Colors.textMuted
            visible: root.subtitle !== ""
        }
    }

    Item {
        id: closeBtn
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        width: 28
        height: 28
        visible: root.showClose

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusXs
            color: closeArea.containsMouse ? Colors.glassHover : "transparent"
            border.width: 1
            border.color: closeArea.containsMouse ? Colors.borderGlass : "transparent"
        }

        Text {
            anchors.centerIn: parent
            text: String.fromCodePoint(0xF00D) // fa-xmark
            font.family: Theme.fontMono
            font.pixelSize: 13
            color: closeArea.containsMouse ? Colors.textPrimary : Colors.textMuted
        }

        MouseArea {
            id: closeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.closed()
        }
    }
}
