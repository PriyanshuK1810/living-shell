import QtQuick
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — clipboard block (MASTER PROMPT F24): the most recent
// entries from the session's existing cliphist collector, copied back on
// click. Previews are read-only text with control characters stripped;
// under strict privacy the *value* is never rendered at all — only that
// an entry exists — because a clipboard string is exactly the kind of
// content §13 keeps off screen.
Item {
    id: root

    readonly property bool strict: IslandSettings.privacy === "strict"

    implicitHeight: col.implicitHeight

    Column {
        id: col
        width: parent.width
        spacing: Theme.space4

        Row {
            width: parent.width
            spacing: Theme.space4

            Text {
                width: parent.width - 72
                elide: Text.ElideRight
                text: {
                    if (!ClipboardService.available) {
                        return "cliphist / wl-copy not installed";
                    }
                    if (!ClipboardService.loaded) {
                        return "Reading clipboard history…";
                    }
                    if (ClipboardService.count === 0) {
                        return "Clipboard history is empty";
                    }
                    return ClipboardService.count + " entries · newest first";
                }
                font.family: Theme.fontUi
                font.pixelSize: 11
                color: Colors.textMuted
            }

            Comp.TextButton {
                width: 68
                height: 24
                label: "Clear"
                enabled: ClipboardService.available && ClipboardService.count > 0
                opacity: enabled ? 1 : 0.5
                onClicked: ClipboardService.clear()
            }
        }

        Repeater {
            model: ClipboardService.entries

            delegate: Rectangle {
                required property var modelData
                width: col.width
                height: 28
                radius: Theme.radiusXs
                color: clipArea.containsMouse ? Colors.glassHover : Colors.glassCard
                border.width: 1
                border.color: Colors.borderSubtle

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.space8
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.space8
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    // Strict privacy: the row exists (so the user knows
                    // something is there) but the value never paints.
                    text: root.strict ? "Entry " + modelData.id + " (hidden by privacy mode)" : modelData.preview
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    color: root.strict ? Colors.textDisabled : Colors.textSecondary
                }

                MouseArea {
                    id: clipArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // A clipboard value must never become a command: this
                    // only ever hands a validated numeric id to the adapter.
                    onClicked: ClipboardService.copyId(modelData.id)
                }
            }
        }
    }
}
