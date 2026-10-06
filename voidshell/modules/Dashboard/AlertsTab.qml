import QtQuick
import Quickshell
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — dashboard Alerts tab (PRD 22.4): reuses the notification
// service and history that this shell already owns; there is no second
// notification store anywhere in the project.
Item {
    id: root

    Column {
        anchors.fill: parent
        spacing: Theme.space12

        Row {
            width: parent.width
            spacing: Theme.space8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - clearBtn.width - Theme.space8
                elide: Text.ElideRight
                text: NotificationService.count > 0 ? NotificationService.count + " in history" + (NotificationService.hasUnread ? " · " + NotificationService.unreadLabel : "") : "No alerts"
                font.family: Theme.fontUi
                font.weight: Font.Medium
                font.pixelSize: 13
                color: Colors.textSecondary
            }

            Comp.TextButton {
                id: clearBtn
                anchors.verticalCenter: parent.verticalCenter
                label: "Clear All"
                enabled: NotificationService.count > 0
                opacity: enabled ? 1.0 : 0.5
                onClicked: NotificationService.clearAll()
            }
        }

        // DND state row.
        Item {
            width: parent.width
            height: 36

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusSm
                color: Colors.glassCard
                border.width: 1
                border.color: NotificationService.dnd ? Colors.borderAccent : Colors.borderSubtle
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Theme.space12
                text: String.fromCodePoint(NotificationService.dnd ? 0xF009B : 0xF0F3)
                font.family: Theme.fontMono
                font.pixelSize: 14
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

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Theme.space12
                text: NotificationService.dnd ? "Toasts suppressed" : "Toasts on"
                font.family: Theme.fontUi
                font.pixelSize: 11
                color: Colors.textMuted
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: NotificationService.dnd = !NotificationService.dnd
            }
        }

        Flickable {
            width: parent.width
            height: parent.height - Theme.space12 * 2 - 36 - 40
            clip: true
            contentHeight: cards.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            visible: NotificationService.count > 0

            Column {
                id: cards
                width: parent.width
                spacing: Theme.space8

                Repeater {
                    model: NotificationService.notifications

                    Comp.NotificationCard {
                        width: cards.width
                        notification: modelData
                        onDismissRequested: NotificationService.dismiss(modelData)
                    }
                }
            }
        }

        Comp.EmptyState {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            glyph: String.fromCodePoint(0xF0F3) // fa-bell
            title: "No alerts"
            body: "Notifications from your applications appear here for the whole session."
            visible: NotificationService.count === 0
        }
    }

    // Opening the Alerts view is what counts as "read" (PRD 15.2).
    onVisibleChanged: {
        if (visible) {
            NotificationService.markAllRead();
        }
    }
}
