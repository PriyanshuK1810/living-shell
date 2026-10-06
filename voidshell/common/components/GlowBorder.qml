import QtQuick
import ".."

// VOID SHELL — restrained luminous edge for focused/active elements.
// One 1px accent line + one faint outer halo. Never a neon outline:
// keep halo opacity low and widths small.
Item {
    id: root
    property color glowColor: Colors.borderAccent
    // Host radius (pills pass their own; cards default to radiusMd).
    property int radius: Theme.radiusMd

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        color: "transparent"
        border.color: root.glowColor
        border.width: 1
        radius: root.radius
        opacity: 0.9
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: Colors.glowAccent
        border.width: 2
        radius: root.radius + 2
        opacity: 0.35
    }
}
