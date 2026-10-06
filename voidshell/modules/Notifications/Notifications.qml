import QtQuick
import Quickshell
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — notifications panel (PRD 15): header with unread count,
// the session's real notification history from this shell's own server,
// per-card dismiss + actions, Do Not Disturb and a full-width Clear All.
// An empty history renders an honest empty state, never placeholder cards.
Scope {
    id: root

    Comp.PopupShell {
        id: win
        popupName: "notifications"
        texture: true
        textureSource: InkArt.sourceFor("notifications")
        panelWidth: 340
        maxHeight: 560
        anchor: "right"

        Column {
            width: parent.width
            spacing: Theme.space8

            Comp.PopupHeader {
                width: parent.width
                title: "Notifications"
                subtitle: {
                    const n = NotificationService.count;
                    if (n === 0) {
                        return "No notifications";
                    }
                    return NotificationService.hasUnread ? NotificationService.unreadLabel : n + " in history";
                }
                onClosed: PopupManager.closeAll()
            }

            // Do Not Disturb — binds straight to NotificationService (17.3).
            Item {
                width: parent.width
                height: 40

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusSm
                    color: dndArea.containsMouse ? Colors.glassHover : Colors.glassCard
                    border.width: 1
                    border.color: NotificationService.dnd ? Colors.borderAccent : Colors.borderSubtle
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.space12
                    text: String.fromCodePoint(0xF009B) // md-bell_off
                    font.family: Theme.fontMono
                    font.pixelSize: 15
                    color: NotificationService.dnd ? Colors.accentLight : Colors.textSecondary
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.space12 + 24
                    text: "Do Not Disturb"
                    font.family: Theme.fontUi
                    font.weight: Font.Medium
                    font.pixelSize: 13
                    color: Colors.textPrimary
                }

                // Explicit state text (state never rides on color alone).
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: switchTrack.left
                    anchors.rightMargin: Theme.space8
                    text: NotificationService.dnd ? "Toasts suppressed" : "Toasts on"
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    color: Colors.textMuted
                }

                Rectangle {
                    id: switchTrack
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.space12
                    width: 34
                    height: 18
                    radius: 9
                    color: NotificationService.dnd ? Colors.accentStrong : Colors.indigo
                    border.width: 1
                    border.color: NotificationService.dnd ? Colors.borderAccent : "transparent"

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        x: NotificationService.dnd ? parent.width - width - 2 : 2
                        width: 14
                        height: 14
                        radius: 7
                        color: Colors.textOnAccent

                        Behavior on x {
                            NumberAnimation {
                                duration: Theme.durationFast
                            }
                        }
                    }
                }

                MouseArea {
                    id: dndArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotificationService.dnd = !NotificationService.dnd
                }
            }

            // History list.
            Flickable {
                width: parent.width
                height: Math.min(contentHeight, 380)
                clip: true
                contentHeight: cardsCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                visible: NotificationService.count > 0

                Column {
                    id: cardsCol
                    width: parent.width
                    spacing: Theme.space8

                    Repeater {
                        model: NotificationService.notifications

                        Comp.NotificationCard {
                            width: cardsCol.width
                            notification: modelData
                            onDismissRequested: NotificationService.dismiss(modelData)
                        }
                    }
                }
            }

            // Honest empty state (no fabricated history).
            Column {
                width: parent.width
                spacing: Theme.space8
                visible: NotificationService.count === 0
                topPadding: Theme.space16
                bottomPadding: Theme.space16

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: String.fromCodePoint(0xF0F3) // fa-bell
                    font.family: Theme.fontMono
                    font.pixelSize: 26
                    color: Colors.textDisabled
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No notifications yet"
                    font.family: Theme.fontUi
                    font.weight: Font.Medium
                    font.pixelSize: 14
                    color: Colors.textSecondary
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - Theme.space32
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    text: "This shell owns the notification server, so anything that arrives shows up here."
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    color: Colors.textMuted
                }
            }

            // Footer: full-width Clear All.
            Comp.TextButton {
                width: parent.width
                label: NotificationService.count > 0 ? "Clear All (" + NotificationService.count + ")" : "Clear All"
                enabled: NotificationService.count > 0
                opacity: enabled ? 1.0 : 0.5
                onClicked: NotificationService.clearAll()
            }
        }
    }
}
