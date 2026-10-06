import Quickshell
import QtQuick
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — power pill: quiet at rest, danger-tinted on hover
// (never permanently red). Click opens the power menu.
Comp.SlantedPill {
    id: root
    property var shellScreen: null
    width: 64
    height: Theme.barHeight
    mirrored: true
    slantRight: false
    fillColor: Colors.glassBase
    borderColor: Colors.borderSubtle
    glowEnabled: true
    activeFillColor: Colors.dangerDeep
    activeBorderColor: Colors.danger
    active: pressArea.containsMouse

    Text {
        anchors.centerIn: parent
        text: "⏻"
        font.family: Theme.fontMono
        font.pixelSize: 17
        color: pressArea.containsMouse ? Colors.textOnAccent : Colors.textSecondary
    }

    MouseArea {
        id: pressArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: PopupManager.toggle("power", root.shellScreen, root)
    }
}
