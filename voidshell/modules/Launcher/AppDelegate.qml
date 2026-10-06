import QtQuick
import Quickshell
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — one application tile in the launcher grid (and the
// compact icon in the recent strip when showName is off).
// Real icon (neutral initial-letter fallback while it loads — never a
// checkbox glyph), name, and a running dot driven by live toplevel state
// (HyprlandService.isAppRunning) — selection is never color-only: the
// keyboard-selected tile also takes the glow border.
// `selected` is keyboard state bound by Launcher; `hovered` is mouse.
Item {
    id: root

    property var entry: null
    property bool selected: false
    property bool showName: true
    property int iconSize: 56
    property int cellW: 139

    readonly property bool hovered: mouseArea.containsMouse
    readonly property bool highlighted: root.selected || root.hovered
    // Live "this app is open" hint; false = no matching toplevel.
    readonly property bool running: root.entry ? HyprlandService.isAppRunning(root.entry) : false

    // tapped   → single click (grid: select, strip: launch)
    // activated → double click (grid: launch)
    signal tapped
    signal activated

    implicitWidth: root.cellW
    implicitHeight: root.showName ? 112 : root.iconSize + 12

    // Hover/selection wash + thin lavender border (tile states).
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Theme.radiusMd
        color: root.selected ? Colors.launcherTile : (root.hovered ? Colors.glassHover : "transparent")
        border.width: root.highlighted ? 1 : 0
        border.color: Colors.launcherTileBorder
        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
    }

    // Keyboard selection — restrained purple glow around the tile.
    Comp.GlowBorder {
        anchors.fill: parent
        visible: root.selected
    }

    Column {
        id: content
        anchors.top: parent.top
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 6

        Item {
            id: iconBox
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.iconSize
            height: root.iconSize

            // Fallback: neutral rounded square with the app initial,
            // shown only while the real icon is missing or loading.
            Rectangle {
                anchors.fill: parent
                visible: appImage.status !== Image.Ready
                radius: Theme.radiusSm
                color: Colors.glassCard
                border.width: 1
                border.color: Colors.borderSubtle
            }

            Text {
                anchors.centerIn: parent
                visible: appImage.status !== Image.Ready
                text: root.entry && root.entry.name ? root.entry.name.charAt(0).toUpperCase() : "?"
                font.family: Theme.fontUi
                font.weight: Font.DemiBold
                font.pixelSize: Math.round(root.iconSize * 0.4)
                color: Colors.accentLight
            }

            Image {
                id: appImage
                anchors.fill: parent
                visible: status === Image.Ready
                source: root.entry && root.entry.icon !== "" ? Quickshell.iconPath(root.entry.icon, "") : ""
                asynchronous: true
                fillMode: Image.PreserveAspectFit
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.cellW - Theme.space8
            height: 16
            visible: root.showName
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.entry && root.entry.name ? root.entry.name : ""
            font.family: Theme.fontUi
            font.weight: Font.Medium
            font.pixelSize: 13
            color: Colors.textPrimary
        }

        // Running dot — real state (a matching toplevel exists), not a
        // decorative pip: it only lights up for apps that are open.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 5
            height: 5
            radius: 3
            visible: root.showName && root.running
            color: Colors.accentLight
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.tapped()
        onDoubleClicked: root.activated()
    }
}
