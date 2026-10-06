import QtQuick
import ".."

// VOID SHELL — text button: glass card surface, brighter on hover,
// accent fill when active. Press scales to Theme.pressedScale.
Item {
    id: root

    property string label: ""
    property bool active: false
    signal clicked

    implicitWidth: labelText.implicitWidth + Theme.space32
    implicitHeight: 36

    scale: pressArea.pressed ? Theme.pressedScale : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: Theme.durationFast
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        border.width: 1
        color: root.active ? Colors.accentStrong : (pressArea.containsMouse ? Colors.glassHover : Colors.glassCard)
        border.color: root.active ? Colors.borderAccent : (pressArea.containsMouse ? Colors.borderGlass : Colors.borderSubtle)
    }

    Text {
        id: labelText
        anchors.centerIn: parent
        text: root.label
        font.family: Theme.fontUi
        font.weight: Font.Medium
        font.pixelSize: 13
        color: root.active ? Colors.textOnAccent : Colors.textPrimary
    }

    MouseArea {
        id: pressArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
