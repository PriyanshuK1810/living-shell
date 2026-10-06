import QtQuick
import Quickshell
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — launcher detail panel (reference: "Neon Purple
// Glassmorphism App Launcher"): big icon, name, subtitle and the action
// list. Every row is backed by a real operation; rows without a backend
// disable themselves and say why in the keycap slot (PRD §37 — never
// hidden, never silently inert). The keycaps are real: Launcher's key
// handler implements each shortcut shown here.
Item {
    id: root

    property var entry: null

    signal launched
    signal terminalRequested
    signal locationRequested
    signal favoriteToggled
    signal uninstallRequested

    readonly property bool isFavorite: root.entry ? LauncherModel.isFavorite(root.entry) : false

    // Keycap chip (fixed 18px tall, mono label).
    component Keycap: Item {
        property string label: ""
        width: keycapText.width + 14
        height: 18

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: Colors.glassCard
            border.width: 1
            border.color: Colors.borderSubtle
        }
        Text {
            id: keycapText
            anchors.centerIn: parent
            text: parent.label
            font.family: Theme.fontMono
            font.pixelSize: 10
            color: Colors.textMuted
        }
    }

    // One action row: glyph + label + keycap (or the concrete reason
    // when the backend is missing).
    component ActionRow: Item {
        id: row
        property var glyph: 0
        property string label: ""
        property string keycap: ""
        property string reason: ""
        property bool primary: false
        property bool available: true
        signal clicked

        height: 34
        width: parent ? parent.width : 100
        opacity: row.available ? 1 : 0.55

        // Primary row — purple gradient, as in the reference.
        Rectangle {
            anchors.fill: parent
            visible: row.primary
            radius: Theme.radiusSm
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.28)
            gradient: Gradient {
                GradientStop { position: 0.0; color: Colors.accentPrimary }
                GradientStop { position: 1.0; color: Colors.accentStrong }
            }
        }

        // Secondary hover wash (only while the row can actually run).
        Rectangle {
            anchors.fill: parent
            visible: !row.primary && row.available && rowMouse.containsMouse
            radius: Theme.radiusSm
            color: Colors.glassHover
        }

        Text {
            id: rowGlyph
            anchors.left: parent.left
            anchors.leftMargin: Theme.space12
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(row.glyph)
            font.family: Theme.fontMono
            font.pixelSize: 13
            color: row.primary ? Colors.textOnAccent : (row.available ? Colors.accentLight : Colors.textMuted)
        }

        Text {
            id: rowLabel
            anchors.left: rowGlyph.right
            anchors.leftMargin: Theme.space8
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, rowRight.x - Theme.space8 - x)
            elide: Text.ElideRight
            text: row.label
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: Font.Medium
            color: row.primary ? Colors.textOnAccent : (row.available ? Colors.textPrimary : Colors.textMuted)
        }

        // Right slot: keycap when runnable, concrete reason when not.
        Item {
            id: rowRight
            anchors.right: parent.right
            anchors.rightMargin: Theme.space12
            anchors.verticalCenter: parent.verticalCenter
            width: !row.available ? reasonText.implicitWidth : (row.keycap !== "" ? keycapItem.width : 0)
            height: 18

            Keycap {
                id: keycapItem
                visible: row.available && row.keycap !== ""
                label: row.keycap
            }

            Text {
                id: reasonText
                x: 0
                anchors.verticalCenter: parent.verticalCenter
                visible: !row.available
                text: row.reason
                font.family: Theme.fontUi
                font.pixelSize: 10
                color: Colors.textMuted
            }
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: row.available
            cursorShape: Qt.PointingHandCursor
            onClicked: row.clicked()
        }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Theme.radiusPanel
        color: Colors.glassCard
        border.width: 1
        border.color: Colors.borderSubtle
    }

    // Placeholder while nothing is selected (honest empty state).
    Column {
        anchors.centerIn: parent
        visible: root.entry === null
        spacing: Theme.space8

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: String.fromCodePoint(0xf002)
            font.family: Theme.fontMono
            font.pixelSize: 22
            color: Colors.textMuted
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Select an app\nto see its details"
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.fontUi
            font.pixelSize: 12
            color: Colors.textMuted
        }
    }

    // --- populated state -------------------------------------------------
    Column {
        id: detailCol
        visible: root.entry !== null
        x: 14
        y: 14
        width: root.width - 28

        Item {
            width: parent.width
            height: 96

            Item {
                anchors.centerIn: parent
                width: 80
                height: 80

                Rectangle {
                    anchors.fill: parent
                    visible: detailIcon.status !== Image.Ready
                    radius: Theme.radiusLg
                    color: Colors.glassCard
                    border.width: 1
                    border.color: Colors.borderSubtle
                }
                Text {
                    anchors.centerIn: parent
                    visible: detailIcon.status !== Image.Ready
                    text: root.entry && root.entry.name ? root.entry.name.charAt(0).toUpperCase() : "?"
                    font.family: Theme.fontUi
                    font.weight: Font.DemiBold
                    font.pixelSize: 30
                    color: Colors.accentLight
                }
                Image {
                    id: detailIcon
                    anchors.fill: parent
                    visible: status === Image.Ready
                    source: root.entry && root.entry.icon !== "" ? Quickshell.iconPath(root.entry.icon, "") : ""
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                }
            }
        }

        Text {
            width: parent.width
            height: 24
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.entry ? root.entry.name : ""
            font.family: Theme.fontUi
            font.weight: Font.Bold
            font.pixelSize: 17
            color: Colors.textPrimary
        }

        Text {
            width: parent.width
            height: 30
            clip: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            maximumLineCount: 2
            elide: Text.ElideMiddle
            text: root.entry ? (root.entry.genericName || root.entry.comment || "") : ""
            font.family: Theme.fontUi
            font.pixelSize: 11
            color: Colors.textMuted
        }

        Item { width: parent.width; height: 14 }
        Rectangle { width: parent.width; height: 1; color: Colors.borderSubtle }
        Item { width: parent.width; height: 12 }

        Column {
            id: actions
            width: parent.width
            spacing: 6

            ActionRow {
                width: actions.width
                primary: true
                glyph: 0xf04b
                label: "Open"
                keycap: "Enter"
                available: root.entry !== null && root.entry.command && root.entry.command.length > 0
                reason: "No executable"
                onClicked: root.launched()
            }
            ActionRow {
                width: actions.width
                glyph: 0xf120
                label: "Open in Terminal"
                keycap: "Ctrl Enter"
                available: LauncherModel.terminalBin !== ""
                reason: "No terminal"
                onClicked: root.terminalRequested()
            }
            ActionRow {
                width: actions.width
                glyph: 0xf07b
                label: "Open Location"
                keycap: "Ctrl O"
                onClicked: root.locationRequested()
            }
            ActionRow {
                width: actions.width
                glyph: 0xf004
                label: root.isFavorite ? "Remove from Favorites" : "Add to Favorites"
                keycap: "Ctrl D"
                onClicked: root.favoriteToggled()
            }
            ActionRow {
                width: actions.width
                glyph: 0xf1f8
                label: "Uninstall"
                onClicked: root.uninstallRequested()
            }
        }
    }
}
