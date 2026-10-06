import QtQuick
import Quickshell
import ".."
import "../../services" as Svc

// VOID SHELL — notification card: renders one tracked notification from
// the shell's own server (PRD 15). App name, summary, body, age and
// actions all come from the real payload; nothing is templated. Critical
// urgency is marked with a labeled badge + danger edge, never color alone.
Item {
    id: root

    property var notification: null
    readonly property string appName: root.notification ? root.notification.appName : ""
    readonly property string summary: root.notification ? root.notification.summary : ""
    readonly property string body: root.notification ? root.notification.body : ""
    readonly property string age: root.notification ? Svc.NotificationService.ageLabel(root.notification) : ""
    readonly property bool critical: root.notification !== null && Svc.NotificationService.isCritical(root.notification)
    readonly property var actionList: root.notification ? Svc.NotificationService.actionsOf(root.notification) : []

    // Real icon path when the app ships one, else a neutral glyph.
    readonly property string iconUrl: {
        if (!root.notification || !root.notification.appIcon) {
            return "";
        }
        return Quickshell.iconPath(root.notification.appIcon, "");
    }

    signal dismissRequested

    implicitWidth: 300
    implicitHeight: cardCol.implicitHeight + Theme.space12 * 2

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMd
        color: Colors.glassCard
        border.width: 1
        border.color: root.critical ? Colors.danger : (cardArea.containsMouse ? Colors.borderGlass : Colors.borderSubtle)

        Behavior on border.color {
            ColorAnimation {
                duration: Theme.durationNormal
            }
        }
    }

    MouseArea {
        id: cardArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    Column {
        id: cardCol
        anchors.fill: parent
        anchors.margins: Theme.space12
        spacing: Theme.space8

        Row {
            width: parent.width
            spacing: Theme.space8

            // App identity: themed icon when available, first-letter mark
            // otherwise (brand icons keep their own colors, PRD 32.2).
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusXs
                    color: Colors.glassHover
                    border.width: 1
                    border.color: Colors.borderSubtle
                    visible: root.iconUrl === ""
                }

                Text {
                    anchors.centerIn: parent
                    text: root.appName !== "" ? root.appName.charAt(0).toUpperCase() : String.fromCodePoint(0xF0004) // md-account
                    font.family: Theme.fontUi
                    font.weight: Font.DemiBold
                    font.pixelSize: 14
                    color: Colors.textSecondary
                    visible: root.iconUrl === ""
                }

                Image {
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    source: root.iconUrl
                    asynchronous: true
                    visible: root.iconUrl !== ""
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 30 - Theme.space8 - ageText.width - Theme.space8 - closeBtn.width - Theme.space8
                spacing: 1

                Row {
                    width: parent.width
                    spacing: Theme.space4

                    Text {
                        width: Math.min(parent.width, implicitWidth)
                        elide: Text.ElideRight
                        text: root.appName
                        font.family: Theme.fontUi
                        font.weight: Font.Medium
                        font.pixelSize: 11
                        color: Colors.textMuted
                    }

                    // Critical is stated in words, not only in red.
                    Text {
                        text: "CRITICAL"
                        font.family: Theme.fontUi
                        font.weight: Font.DemiBold
                        font.pixelSize: 9
                        font.letterSpacing: 1
                        color: Colors.danger
                        visible: root.critical
                    }
                }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.summary
                    font.family: Theme.fontUi
                    font.weight: Font.DemiBold
                    font.pixelSize: 14
                    color: Colors.textPrimary
                }
            }

            Text {
                id: ageText
                anchors.verticalCenter: parent.verticalCenter
                text: root.age
                font.family: Theme.fontUi
                font.pixelSize: 11
                color: Colors.textMuted
            }

            Item {
                id: closeBtn
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                height: 22

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusXs
                    color: closeArea.containsMouse ? Colors.glassHover : "transparent"
                    border.width: 1
                    border.color: closeArea.containsMouse ? Colors.borderGlass : "transparent"
                }

                Text {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(0xF00D) // fa-xmark
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                    color: closeArea.containsMouse ? Colors.textPrimary : Colors.textMuted
                }

                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.dismissRequested()
                }
            }
        }

        Text {
            width: parent.width
            height: Math.min(implicitHeight, 60)
            maximumLineCount: 3
            elide: Text.ElideRight
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            text: root.body
            font.family: Theme.fontUi
            font.pixelSize: 13
            lineHeight: 1.15
            color: Colors.textSecondary
            visible: root.body !== ""
        }

        Row {
            width: parent.width
            spacing: Theme.space8
            visible: root.actionList.length > 0

            Repeater {
                model: Math.min(3, root.actionList.length)

                Rectangle {
                    required property int index
                    width: actionLabel.implicitWidth + Theme.space16
                    height: 26
                    radius: Theme.radiusXs
                    color: actionArea.containsMouse ? Colors.glassHover : Colors.glassElevated
                    border.width: 1
                    border.color: actionArea.containsMouse ? Colors.borderGlass : Colors.borderSubtle

                    Text {
                        id: actionLabel
                        anchors.centerIn: parent
                        text: root.actionList[index].text
                        font.family: Theme.fontUi
                        font.weight: Font.Medium
                        font.pixelSize: 12
                        color: Colors.textSecondary
                    }

                    MouseArea {
                        id: actionArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Svc.NotificationService.invoke(root.notification, root.actionList[index])
                    }
                }
            }
        }
    }
}
