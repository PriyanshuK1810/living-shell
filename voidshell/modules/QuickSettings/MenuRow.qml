import QtQuick
import "../../common"

// VOID SHELL — context-menu row (device menu): icon + label, hover wash
// when the action is available right now, muted and inert otherwise.
// Unavailable rows keep their label (the menu never hides what exists)
// and carry no pointer — honest disabled state, never colour alone
// (PRD 17.3). `armed` is the destructive two-step confirm: the label is
// switched to its warning text so the second click is a decision, not an
// accident.
Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property bool available: true
    property bool armed: false
    signal triggered

    width: parent ? parent.width : 192
    height: 34
    radius: Theme.radiusSm
    color: {
        if (!root.available) {
            return "transparent";
        }
        if (root.armed) {
            return Qt.rgba(196 / 255, 43 / 255, 73 / 255, 0.22); // danger wash
        }
        return rowArea.containsMouse ? Colors.glassHover : "transparent";
    }

    Text {
        id: iconText
        anchors.left: parent.left
        anchors.leftMargin: Theme.space8
        anchors.verticalCenter: parent.verticalCenter
        text: root.icon
        font.family: Theme.fontMono
        font.pixelSize: 12
        color: !root.available ? Colors.textDisabled : (root.armed ? Colors.danger : Colors.textSecondary)
    }

    Text {
        anchors.left: iconText.right
        anchors.leftMargin: Theme.space8
        anchors.right: parent.right
        anchors.rightMargin: Theme.space8
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: root.label
        font.family: Theme.fontUi
        font.weight: Font.Medium
        font.pixelSize: 12
        color: !root.available ? Colors.textDisabled : (root.armed ? Colors.danger : Colors.textPrimary)
    }

    MouseArea {
        id: rowArea
        anchors.fill: parent
        enabled: root.available
        hoverEnabled: enabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.triggered()
    }
}
