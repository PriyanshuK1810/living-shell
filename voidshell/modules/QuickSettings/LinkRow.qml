import QtQuick
import "../../common"

// VOID SHELL — quick-settings detail row (one Wi-Fi network or one
// Bluetooth device): circular badge, title, state line, trailing glyph.
// A row the shell cannot act on is inert (no hover, no pointer) and its
// state line spells out why — nothing ever looks tappable and then does
// nothing (PRD 17.3). The current connection washes purple and carries a
// check, so state is never colour-only. Right-click (two-finger tap on a
// touchpad) opens the device context menu on rows that are `menuable`.
Item {
    id: root

    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property string trailIcon: ""
    property color trailColor: Colors.textMuted
    property bool active: false
    property bool interactive: false
    // Rows with real context-menu actions (paired Bluetooth devices):
    // right-click opens the menu even while a left-click would do
    // something else.
    property bool menuable: false
    signal triggered
    signal contextRequested

    implicitWidth: 340
    height: 44

    // --- surface: accent wash when live, hover wash when actionable -----
    Rectangle {
        id: bg
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        radius: Theme.radiusSm
        color: root.active ? Colors.accentStrong : ((root.interactive || root.menuable) && rowArea.containsMouse ? Colors.glassHover : "transparent")
        opacity: root.active ? 0.35 : 1.0
        border.width: root.active ? 1 : 0
        border.color: Colors.borderAccentStrong
    }

    // --- badge -----------------------------------------------------------
    Rectangle {
        id: badge
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 28
        height: 28
        radius: 14
        color: root.active ? Colors.accentStrong : Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: root.active ? Colors.borderAccentStrong : Colors.borderSubtle

        Text {
            anchors.centerIn: parent
            text: root.icon
            font.family: Theme.fontMono
            font.pixelSize: 14
            color: root.active ? Colors.textOnAccent : ((root.interactive || root.menuable) ? Colors.textSecondary : Colors.textMuted)
        }
    }

    // --- title / state line ---------------------------------------------
    Column {
        anchors.left: badge.right
        anchors.leftMargin: 10
        anchors.right: trail.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: root.title
            font.family: Theme.fontUi
            font.weight: Font.DemiBold
            font.pixelSize: 13
            color: Colors.textPrimary
        }

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: root.subtitle
            font.family: Theme.fontUi
            font.pixelSize: 11
            color: root.active ? Colors.accentLight : Colors.textMuted
            visible: root.subtitle !== ""
        }
    }

    // --- trailing glyph: check (live) / chevron (actionable) / lock -----
    Text {
        id: trail
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: root.trailIcon
        font.family: Theme.fontMono
        font.pixelSize: 11
        color: root.trailColor
        visible: root.trailIcon !== ""
    }

    MouseArea {
        id: rowArea
        anchors.fill: parent
        enabled: root.interactive || root.menuable
        hoverEnabled: enabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                if (root.menuable) {
                    root.contextRequested();
                }
                return;
            }
            if (root.interactive) {
                root.triggered();
            }
        }
    }
}
