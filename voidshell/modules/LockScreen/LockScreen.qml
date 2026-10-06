import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — lock screen surface (PRD 25).
// Wallpaper-aware dark glass with large time, date, avatar + username,
// password input, weather and layout chips, compact media controls and
// protected power actions.
//
// Authentication is never implemented here: the field hands off to the
// discovered system locker (hyprlock / swaylock / gtklock), which performs
// the real PAM authentication. The surface stays up underneath it and
// dismisses only when that locker reports a successful unlock — there is
// no home-grown password validation (PRD 25) and no Escape bypass: while
// locked, PopupManager refuses to open or dismiss anything else.
Scope {
    id: root

    // QA-only escape hatch: `VOID_POPUP=lock qs -c voidshell` opens this
    // surface for render checks and must be dismissible by the harness.
    // A lock opened for real (power menu / keybind) never closes on Esc.
    readonly property bool qaMode: Quickshell.env("VOID_POPUP") === "lock"

    property bool authBusy: false
    property string authError: ""
    property string attempt: ""

    property string armed: ""

    Timer {
        running: root.armed !== ""
        interval: 4000
        repeat: false
        onTriggered: root.armed = ""
    }

    // The lock surface is the weather-chip consumer while it is up.
    Binding {
        target: WeatherService
        property: "viewsLock"
        value: win.visible
    }

    Process {
        id: locker
        running: false
        onExited: exitCode => {
            root.authBusy = false;
            root.attempt = "";
            if (exitCode === 0) {
                // Real authentication succeeded — drop the surface.
                root.authError = "";
                PopupManager.closeAll();
            } else {
                root.authError = "Unlock did not complete (locker exit " + exitCode + ").";
            }
        }
    }

    function startAuth() {
        if (root.authBusy || !PowerService.canDo("lock")) {
            return;
        }
        root.authError = "";
        const cmd = PowerService.commandFor("lock");
        if (cmd.length === 0) {
            root.authError = "No lock screen installed (hyprlock / swaylock / gtklock).";
            return;
        }
        // Any text in the field is discarded: hyprlock owns the password.
        root.attempt = "";
        locker.command = cmd;
        root.authBusy = true;
        locker.running = true;
    }

    function request(action) {
        if (!PowerService.canDo(action)) {
            return;
        }
        if (action === "reboot" || action === "poweroff") {
            // Two-step confirm (PRD 18 / 25): protected against accidents.
            if (root.armed !== action) {
                root.armed = action;
                return;
            }
            root.armed = "";
        }
        PowerService.execute(action);
    }

    function labelFor(action) {
        switch (action) {
        case "suspend":
            return "Suspend";
        case "reboot":
            return "Restart";
        case "poweroff":
            return "Shut Down";
        default:
            return "";
        }
    }

    function glyphFor(action) {
        switch (action) {
        case "suspend":
            return String.fromCodePoint(0xF04B2); // md-sleep
        case "reboot":
            return String.fromCodePoint(0xF0709); // md-restart
        case "poweroff":
            return String.fromCodePoint(0xF0902); // md-power_off
        default:
            return "";
        }
    }

    component PowerButton: Item {
        id: btn
        property string action: ""
        readonly property bool allowed: PowerService.canDo(btn.action)
        readonly property bool danger: btn.action === "poweroff"
        readonly property bool armedNow: root.armed === btn.action

        width: btnRow.buttonWidth
        height: 46

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusSm
            color: btn.armedNow ? Colors.dangerDeep : (btn.allowed && btnArea.containsMouse ? Colors.glassHover : Colors.glassCard)
            border.width: 1
            border.color: btn.armedNow ? Colors.danger : (btn.allowed && btnArea.containsMouse ? (btn.danger ? Colors.danger : Colors.borderGlass) : Colors.borderSubtle)

            Behavior on color {
                ColorAnimation {
                    duration: Theme.durationNormal
                }
            }
        }

        Row {
            anchors.centerIn: parent
            spacing: Theme.space8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.glyphFor(btn.action)
                font.family: Theme.fontMono
                font.pixelSize: 14
                color: btn.armedNow ? Colors.textOnAccent : (btn.allowed ? (btn.danger && btnArea.containsMouse ? Colors.danger : Colors.textSecondary) : Colors.textDisabled)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: btn.armedNow ? "Confirm" : root.labelFor(btn.action)
                font.family: Theme.fontUi
                font.weight: Font.DemiBold
                font.pixelSize: 13
                color: btn.armedNow ? Colors.textOnAccent : (btn.allowed ? (btn.danger ? Colors.danger : Colors.textPrimary) : Colors.textDisabled)
            }
        }

        MouseArea {
            id: btnArea
            anchors.fill: parent
            enabled: btn.allowed
            hoverEnabled: true
            cursorShape: btn.allowed ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.request(btn.action)
        }
    }

    PanelWindow {
        id: win

        readonly property int screenW: screen ? screen.width : 1920
        readonly property int screenH: screen ? screen.height : 1080

        visible: PopupManager.isOpen("lock")
        screen: PopupManager.activeScreen !== null ? PopupManager.activeScreen : PopupManager.fallbackScreen
        // Blur-exempt + fullscreen must never shrink to avoid the bar's
        // reserved zone (design-system §2).
        WlrLayershell.namespace: "voidshell-lock"
        exclusiveZone: -1
        // Near-opaque so the session behind is not readable, with just
        // enough transparency for the wallpaper palette to show through.
        color: Qt.rgba(14 / 255, 11 / 255, 20 / 255, 0.94)

        anchors {
            left: true
            right: true
            top: true
            bottom: true
        }

        // Keyboard focus lives on the password field; only the QA build
        // lets Escape dismiss this surface.
        Item {
            id: keyScope
            anchors.fill: parent
            focus: win.visible
            Keys.enabled: win.visible
            Keys.onEscapePressed: {
                if (root.qaMode) {
                    PopupManager.closeAll();
                }
            }
        }

        SystemClock {
            id: clock
            precision: SystemClock.Minutes
        }

        // Layout chip is refreshed whenever the surface appears.
        onVisibleChanged: {
            if (visible) {
                keyScope.forceActiveFocus();
                KeyboardService.refresh();
                if (authField) {
                    authField.forceActiveFocus();
                }
            } else {
                root.armed = "";
                root.authError = "";
                root.attempt = "";
            }
        }

        Column {
            id: column
            anchors.centerIn: parent
            width: Math.min(560, win.screenW - 96)
            spacing: Theme.space16

            // ---- time + date ---------------------------------------------
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatTime(clock.date, "hh:mm")
                font.family: Theme.fontMono
                font.weight: Font.DemiBold
                font.pixelSize: 84
                color: Colors.textPrimary
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(clock.date, "dddd, MMMM d")
                font.family: Theme.fontUi
                font.pixelSize: 17
                color: Colors.textSecondary
            }

            // ---- identity -------------------------------------------------
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.space12

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 44
                    radius: 22
                    color: Colors.indigoDeep
                    border.width: 1
                    border.color: Colors.borderGlass

                    Text {
                        anchors.centerIn: parent
                        text: SystemStats.username !== "" ? SystemStats.username.charAt(0).toUpperCase() : "?"
                        font.family: Theme.fontUi
                        font.weight: Font.DemiBold
                        font.pixelSize: 17
                        color: Colors.accentLight
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        text: SystemStats.username !== "" ? SystemStats.username : "Unknown user"
                        font.family: Theme.fontUi
                        font.weight: Font.DemiBold
                        font.pixelSize: 15
                        color: Colors.textPrimary
                    }

                    Text {
                        text: SystemStats.hostname !== "" ? SystemStats.hostname : SystemStats.osName
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        color: Colors.textMuted
                    }
                }
            }

            // ---- password input (hands off to the system locker) ----------
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 340
                height: 46

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusSm
                    color: Colors.glassCard
                    border.width: 1
                    border.color: authField.activeFocus ? Colors.borderAccent : Colors.borderGlass
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.space12
                    anchors.verticalCenter: parent.verticalCenter
                    text: String.fromCodePoint(0xF033E) // md-lock
                    font.family: Theme.fontMono
                    font.pixelSize: 15
                    color: authField.activeFocus ? Colors.accentLight : Colors.textMuted
                }

                TextInput {
                    id: authField
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.space12 + 26
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.space12
                    anchors.verticalCenter: parent.verticalCenter
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    selectByMouse: false
                    enabled: PowerService.canDo("lock") && !root.authBusy
                    font.family: Theme.fontUi
                    font.pixelSize: 14
                    color: Colors.textPrimary
                    selectionColor: Colors.accentStrong
                    onTextChanged: root.authError = ""
                    Keys.onReturnPressed: root.startAuth()
                    Keys.onEnterPressed: root.startAuth()
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                text: root.authError !== "" ? root.authError : (root.authBusy ? "Waiting for the authenticator…" : (PowerService.canDo("lock") ? "Press Enter to unlock — authentication is handled by " + PowerService.lockCommand.replace(/^.*\//, "") + " (PAM)." : "No lock screen installed (hyprlock / swaylock / gtklock): authentication unavailable."))
                font.family: Theme.fontUi
                font.pixelSize: 12
                color: root.authError !== "" ? Colors.danger : Colors.textMuted
            }

            // ---- chips: weather + keyboard layout -------------------------
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.space8

                Item {
                    visible: WeatherService.hasData
                    width: weatherChip.implicitWidth + Theme.space32
                    height: 30

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusSm
                        color: Colors.glassCard
                        border.width: 1
                        border.color: Colors.borderSubtle
                    }

                    Row {
                        id: weatherChip
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: WeatherService.iconFor(WeatherService.weatherCode)
                            font.family: Theme.fontMono
                            font.pixelSize: 13
                            color: Colors.accentLight
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(WeatherService.temperature) + "° " + WeatherService.conditionText
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                            color: Colors.textSecondary
                        }
                    }
                }

                Item {
                    visible: KeyboardService.available
                    width: langChip.implicitWidth + Theme.space32
                    height: 30

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusSm
                        color: Colors.glassCard
                        border.width: 1
                        border.color: Colors.borderSubtle
                    }

                    Row {
                        id: langChip
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: String.fromCodePoint(0xF1AB) // fa-language
                            font.family: Theme.fontMono
                            font.pixelSize: 13
                            color: Colors.accentLight
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: KeyboardService.layout
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                            color: Colors.textSecondary
                        }
                    }
                }
            }

            // ---- compact media controls -----------------------------------
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(420, parent.width)
                height: visible ? 56 : 0
                visible: MediaService.available

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.space12

                    Comp.MediaArtwork {
                        anchors.verticalCenter: parent.verticalCenter
                        artUrl: MediaService.artUrl
                        iconSize: 48
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 170
                        spacing: 1

                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: MediaService.trackTitle !== "" ? MediaService.trackTitle : "No track"
                            font.family: Theme.fontUi
                            font.weight: Font.Medium
                            font.pixelSize: 13
                            color: Colors.textPrimary
                        }

                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: MediaService.artist !== "" ? MediaService.artist : MediaService.identity
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            color: Colors.textMuted
                        }
                    }
                }

                Comp.MediaControls {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // ---- protected power actions ----------------------------------
            Row {
                id: btnRow
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.space8
                readonly property int buttonWidth: 132

                PowerButton {
                    action: "suspend"
                }

                PowerButton {
                    action: "reboot"
                }

                PowerButton {
                    action: "poweroff"
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: PowerService.ready ? (PowerService.onBattery ? "On battery · " + PowerService.percentage + "%" : (PowerService.hasBattery ? "Plugged in · " + PowerService.percentage + "%" : "")) : "Battery state unavailable"
                visible: text !== ""
                font.family: Theme.fontUi
                font.pixelSize: 11
                color: Colors.textDisabled
            }
        }
    }
}
