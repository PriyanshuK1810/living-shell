import QtQuick
import "../../common"
import "../../services"

// VOID SHELL — launcher command row (PRD §19.2). Renders one entry from
// LauncherModel.commands: glyph, title, hint, kind badge. Commands whose
// backend is missing are shown dimmed with the concrete reason instead of
// being hidden or silently inert (PRD §37).
Item {
    id: root

    property var cmd: null
    property bool selected: false
    signal clicked

    readonly property bool available: !cmd || cmd.available !== false
    readonly property string kindLabel: {
        if (!cmd) return "";
        if (cmd.kind === "plugin") return "Plugin";
        if (cmd.kind === "popup") return "Open";
        if (cmd.kind === "web") return "Search";
        return "Action";
    }

    implicitWidth: parent ? parent.width : 560
    height: 52

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: root.available ? (root.selected ? Colors.glassHover : (rowArea.containsMouse ? Colors.glassCard : "transparent")) : Colors.glassCard
        border.width: root.selected && root.available ? 1 : 0
        border.color: Colors.borderAccent
    }

    Row {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Theme.space12
        anchors.rightMargin: Theme.space12
        spacing: Theme.space12

        // Glyph badge
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            height: 32
            radius: Theme.radiusSm
            color: Colors.glassCard
            border.width: 1
            border.color: Colors.borderSubtle

            Text {
                anchors.centerIn: parent
                text: root.cmd ? String.fromCodePoint(root.cmd.glyph) : ""
                font.family: Theme.fontMono
                font.pixelSize: 15
                color: root.available ? Colors.accentLight : Colors.textDisabled
            }
        }

        // Title + hint
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 32 - Theme.space12 - badgeRow.width - Theme.space12
            spacing: 1

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: root.cmd ? root.cmd.title : ""
                font.family: Theme.fontUi
                font.weight: Font.Medium
                font.pixelSize: 13
                color: root.available ? Colors.textPrimary : Colors.textDisabled
            }

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: {
                    if (!root.cmd) return "";
                    if (!root.available) return root.cmd.unavailableReason || "Unavailable";
                    return LauncherModel.hintFor(root.cmd);
                }
                font.family: Theme.fontUi
                font.pixelSize: 11
                color: root.available ? Colors.textMuted : Colors.danger
            }
        }

        // Kind badge / prefix
        Row {
            id: badgeRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.cmd && root.cmd.prefix !== undefined
                text: root.cmd && root.cmd.prefix ? root.cmd.prefix : ""
                font.family: Theme.fontMono
                font.pixelSize: 11
                color: Colors.textMuted
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.kindLabel
                font.family: Theme.fontUi
                font.pixelSize: 10
                font.weight: Font.DemiBold
                color: Colors.textMuted

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -6
                    z: -1
                    radius: Theme.radiusSm
                    color: Colors.glassCard
                    border.width: 1
                    border.color: Colors.borderSubtle
                }
            }
        }
    }

    MouseArea {
        id: rowArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.available) {
                root.clicked();
            }
        }
    }
}
