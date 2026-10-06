import QtQuick
import ".."

// VOID SHELL — icon button: transparent at rest, glass on hover,
// accent fill when active. Press scales to Theme.pressedScale.
Item {
    id: root

    property string icon: ""
    property bool active: false
    // Reference-matched round glowing action (dashboard play button).
    property bool glow: false
    property bool round: false
    property int iconSize: 16
    signal clicked

    implicitWidth: 36
    implicitHeight: 36

    scale: pressArea.pressed ? Theme.pressedScale : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: Theme.durationFast
        }
    }

    GlowBorder {
        anchors.fill: parent
        radius: root.round ? root.width / 2 : Theme.radiusSm
        glowColor: Colors.glowStrong
        visible: root.glow
    }

    Rectangle {
        anchors.fill: parent
        radius: root.round ? root.width / 2 : Theme.radiusSm
        color: root.active || root.glow ? Colors.accentStrong : (pressArea.containsMouse ? Colors.glassHover : "transparent")
        border.width: 1
        border.color: root.active || root.glow ? Colors.borderAccent : (pressArea.containsMouse ? Colors.borderGlass : "transparent")
    }

    Text {
        anchors.centerIn: parent
        text: root.icon
        font.family: Theme.fontMono
        font.pixelSize: root.iconSize
        color: root.active || root.glow ? Colors.textOnAccent : (pressArea.containsMouse ? Colors.accentLight : Colors.textSecondary)
    }

    MouseArea {
        id: pressArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
