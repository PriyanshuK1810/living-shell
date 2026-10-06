import QtQuick
import Quickshell
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — power / session panel (PRD 18).
// Rows run real session commands through PowerService; every row is gated
// by live capability detection (locker discovered, hibernate only when the
// kernel + swap allow it) and states the reason when disabled. Reboot and
// Shut Down require a second click within 4 seconds so a stray click can
// never power the machine off — while ordinary use stays one extra click.
Scope {
    id: root

    property string armed: ""

    Timer {
        running: root.armed !== ""
        interval: 4000
        repeat: false
        onTriggered: root.armed = ""
    }

    function request(action) {
        if (!PowerService.canDo(action)) {
            return;
        }
        if (action === "reboot" || action === "poweroff") {
            if (root.armed !== action) {
                root.armed = action;
                return;
            }
            root.armed = "";
        }
        if (action === "lock") {
            // Show the themed lock surface (PRD 25); authentication is
            // handed to the system locker when the user submits the field.
            PopupManager.open("lock");
            return;
        }
        if (PowerService.execute(action)) {
            PopupManager.closeAll();
        }
    }

    function iconFor(action) {
        switch (action) {
        case "lock":
            return String.fromCodePoint(0xF033E); // md-lock
        case "suspend":
            return String.fromCodePoint(0xF04B2); // md-sleep
        case "hibernate":
            return String.fromCodePoint(0xF0594); // md-weather_night
        case "reboot":
            return String.fromCodePoint(0xF0709); // md-restart
        case "poweroff":
            return String.fromCodePoint(0xF0902); // md-power_off
        default:
            return "";
        }
    }

    function labelFor(action) {
        switch (action) {
        case "lock":
            return "Lock Screen";
        case "suspend":
            return "Suspend";
        case "hibernate":
            return "Hibernate";
        case "reboot":
            return "Reboot";
        case "poweroff":
            return "Shut Down";
        default:
            return "";
        }
    }

    function hintFor(action) {
        if (PowerService.canDo(action)) {
            return "";
        }
        switch (action) {
        case "lock":
            return "No lock screen installed (hyprlock/swaylock/gtklock)";
        case "hibernate":
            return "Kernel swap-to-disk unavailable";
        case "suspend":
            return "Suspend unsupported";
        case "reboot":
            return "systemctl unavailable";
        case "poweroff":
            return "systemctl unavailable";
        default:
            return "";
        }
    }

    component PowerRow: Item {
        id: row
        property string action: ""
        readonly property bool allowed: PowerService.canDo(row.action)
        readonly property bool danger: row.action === "poweroff"
        readonly property bool armed: root.armed === row.action
        readonly property string hint: root.hintFor(row.action)
        width: parent ? parent.width : 240
        height: row.hint !== "" ? 62 : 50

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusSm
            color: row.armed ? Colors.dangerDeep : (row.allowed && rowArea.containsMouse ? Colors.glassHover : Colors.glassCard)
            border.width: 1
            border.color: row.armed ? Colors.danger : (row.allowed && rowArea.containsMouse ? (row.danger ? Colors.danger : Colors.borderGlass) : Colors.borderSubtle)

            Behavior on color {
                ColorAnimation {
                    duration: Theme.durationNormal
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Theme.space12
            text: root.iconFor(row.action)
            font.family: Theme.fontMono
            font.pixelSize: 17
            color: row.armed ? Colors.textOnAccent : (row.danger && rowArea.containsMouse ? Colors.danger : (row.allowed ? Colors.textSecondary : Colors.textDisabled))
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Theme.space12 + 30
            text: root.armed ? "Click again to confirm" : root.labelFor(row.action)
            font.family: Theme.fontUi
            font.weight: Font.DemiBold
            font.pixelSize: 14
            color: row.armed ? Colors.textOnAccent : (row.allowed ? (row.danger ? Colors.danger : Colors.textPrimary) : Colors.textDisabled)
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.space12 + 30
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 7
            width: parent.width - (Theme.space12 + 30) - Theme.space12
            elide: Text.ElideRight
            text: row.hint
            font.family: Theme.fontUi
            font.pixelSize: 11
            color: Colors.textMuted
            visible: row.hint !== ""
        }

        MouseArea {
            id: rowArea
            anchors.fill: parent
            enabled: row.allowed
            hoverEnabled: true
            cursorShape: row.allowed ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.request(row.action)
        }
    }

    Comp.PopupShell {
        id: win
        popupName: "power"
        texture: true
        textureSource: InkArt.sourceFor("power")
        panelWidth: 240
        maxHeight: 520
        anchor: "right"
        glow: root.armed === "poweroff"

        Column {
            width: parent.width
            spacing: Theme.space8

            Comp.PopupHeader {
                width: parent.width
                title: "Session"
                subtitle: PowerService.ready ? PowerService.stateLabel + (PowerService.timeLabel !== "" ? " · " + PowerService.timeLabel : "") : "Battery state unavailable"
                onClosed: PopupManager.closeAll()
            }

            PowerRow {
                action: "lock"
            }

            PowerRow {
                action: "suspend"
            }

            PowerRow {
                action: "hibernate"
            }

            PowerRow {
                action: "reboot"
            }

            PowerRow {
                action: "poweroff"
            }

            // Real command preview: documents exactly what a row will run.
            Text {
                width: parent.width
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                text: root.armed !== "" ? "> " + PowerService.describe(root.armed) : ""
                font.family: Theme.fontMono
                font.pixelSize: 10
                color: Colors.textDisabled
                visible: text !== ""
            }
        }
    }
}
