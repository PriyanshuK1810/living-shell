import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — toast layer (PRD 15.3): bottom-right arrival pulse that
// never touches the top-bar geometry. Notification arrivals are relayed
// from the shell's own notification server (Do Not Disturb suppresses
// them, exactly as the panel promises); screenshot/recording results
// publish through ToastService directly. One toast at a time, auto-dismiss
// with hover pause, click-through to the notification history.
Scope {
    id: root

    // Relay real arrivals onto the bus. DND keeps history but hides pulses.
    Connections {
        target: NotificationService
        function onArrivalCountChanged() {
            if (NotificationService.dnd) {
                return;
            }
            const n = NotificationService.lastArrival;
            if (!n) {
                return;
            }
            const tone = NotificationService.isCritical(n) ? "danger" : "info";
            ToastService.push(n.summary, n.body !== "" ? n.body : n.appName, n.appIcon, tone);
        }
    }

    // Auto-dismiss; hovering the toast pauses the countdown.
    property bool paused: toastArea.containsMouse

    Timer {
        id: autoDismiss
        interval: 4800
        repeat: false
        running: ToastService.current !== null && !root.paused
        onTriggered: ToastService.dismiss()
    }

    PanelWindow {
        id: win
        anchors {
            bottom: true
            right: true
        }
        margins {
            bottom: Theme.sideMargin
            right: Theme.sideMargin
        }
        implicitWidth: 340 + Theme.space16
        implicitHeight: toastCol.implicitHeight + Theme.space16
        // Blur-exempt + ignores other surfaces' zones (design-system §2).
        WlrLayershell.namespace: "voidshell-toast"
        exclusiveZone: -1
        color: "transparent"
        visible: ToastService.current !== null
        screen: PopupManager.activeScreen !== null ? PopupManager.activeScreen : PopupManager.fallbackScreen

        // Escape dismisses the toast (PRD 33: Escape closes transients).
        Item {
            id: escGrab
            anchors.fill: parent
            focus: win.visible
            Keys.enabled: win.visible
            Keys.onEscapePressed: ToastService.dismiss()
        }

        // Single arrival pulse: slides up and fades in (PRD 15.3).
        Item {
            id: slide
            anchors.fill: parent
            opacity: win.visible ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.durationPanel
                }
            }

            transform: Translate {
                y: win.visible ? 0 : 18

                Behavior on y {
                    NumberAnimation {
                        duration: Theme.durationPanel
                    }
                }
            }

        Comp.GlassCard {
            id: card
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: Theme.space8
            width: 340
            height: toastCol.implicitHeight + Theme.space24 * 2
            hovered: toastArea.containsMouse

            MouseArea {
                id: toastArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    PopupManager.toggle("notifications", win.screen);
                    ToastService.dismiss();
                }
            }

            Column {
                id: toastCol
                width: parent.width
                spacing: Theme.space4

                Row {
                    width: parent.width
                    spacing: Theme.space8

                    // Tone is shown with a glyph, not only a color.
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            const tone = ToastService.current ? ToastService.current.tone : "info";
                            if (tone === "success") {
                                return String.fromCodePoint(0xF012C); // md-check
                            }
                            if (tone === "danger") {
                                return String.fromCodePoint(0xF0026); // md-alert
                            }
                            return String.fromCodePoint(0xF0F3); // fa-bell
                        }
                        font.family: Theme.fontMono
                        font.pixelSize: 15
                        color: {
                            const tone = ToastService.current ? ToastService.current.tone : "info";
                            if (tone === "success") {
                                return Colors.success;
                            }
                            if (tone === "danger") {
                                return Colors.danger;
                            }
                            return Colors.accentLight;
                        }
                    }

                    Text {
                        width: parent.width - 15 - Theme.space8 - 24
                        elide: Text.ElideRight
                        text: ToastService.current ? ToastService.current.title : ""
                        font.family: Theme.fontUi
                        font.weight: Font.DemiBold
                        font.pixelSize: 13
                        color: Colors.textPrimary
                    }

                    Item {
                        id: close
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 24

                        Text {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(0xF00D) // fa-xmark
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                            color: closeArea.containsMouse ? Colors.textPrimary : Colors.textMuted
                        }

                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // Stop propagation so the panel does not open.
                            z: 1
                            onClicked: ToastService.dismiss()
                        }
                    }
                }

                Text {
                    width: parent.width
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    text: ToastService.current ? ToastService.current.body : ""
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    color: Colors.textSecondary
                    visible: text !== ""
                }
            }
        }
        }
    }
}
