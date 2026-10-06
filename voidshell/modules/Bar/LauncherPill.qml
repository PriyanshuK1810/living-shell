import Quickshell
import QtQuick
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — launcher pill (straight outer-left edge).
Comp.SlantedPill {
    id: root
    // Screen reported by the bar so popups open on the initiating monitor.
    property var shellScreen: null
    width: 64
    height: Theme.barHeight
    slantLeft: false
    fillColor: Colors.glassBase
    borderColor: Colors.borderSubtle
    glowEnabled: true

    Text {
        anchors.centerIn: parent
        text: ""
        font.family: Theme.fontMono
        font.pixelSize: 20
        color: pressArea.containsMouse ? Colors.accentLight : Colors.textSecondary
    }

    MouseArea {
        id: pressArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: PopupManager.toggle("launcher", root.shellScreen, root)
    }
}
