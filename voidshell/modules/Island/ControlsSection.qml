import QtQuick
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — the Island's compact control block (MASTER PROMPT F18/F19):
// the four controls that belong next to an activity — do not disturb,
// keep-awake, output volume and backlight. Every one of them drives an
// existing service; a missing backend renders disabled with its reason
// instead of flipping a fake state.
Item {
    id: root

    implicitHeight: col.implicitHeight

    Column {
        id: col
        width: parent.width
        spacing: Theme.space8

        Row {
            width: parent.width
            spacing: Theme.space4

            Comp.TextButton {
                width: (parent.width - Theme.space4) / 2
                height: 32
                label: NotificationService.dnd ? "DND on" : "DND off"
                active: NotificationService.dnd
                onClicked: NotificationService.dnd = !NotificationService.dnd
            }

            Comp.TextButton {
                width: (parent.width - Theme.space4) / 2
                height: 32
                // The inhibitor *is* the state: an unavailable backend
                // can never claim the screen is being kept awake.
                label: KeepAwake.active ? "Awake " + KeepAwake.elapsedLabel : "Keep awake"
                active: KeepAwake.active
                onClicked: KeepAwake.toggle("Island keep-awake")
            }
        }

        Text {
            width: parent.width
            text: KeepAwake.available ? "" : "systemd-inhibit is not installed — keep-awake unavailable"
            font.family: Theme.fontUi
            font.pixelSize: 11
            color: Colors.warning
            visible: text !== ""
        }

        Comp.ShellSlider {
            width: parent.width
            label: "Volume"
            icon: String.fromCodePoint(AudioService.muted || AudioService.volumePercent === 0 ? 0xF0581 : 0xF057E)
            iconAction: AudioService.available
            enabled: AudioService.available
            showValue: true
            valueText: AudioService.available ? AudioService.volumeText() : "No audio device"
            valueAlert: AudioService.muted
            value: AudioService.volume
            from: 0
            to: 1
            onIconClicked: AudioService.toggleMute()
            onMoved: v => AudioService.setVolume(v)
        }

        Comp.ShellSlider {
            width: parent.width
            label: "Brightness"
            icon: String.fromCodePoint(0xF00DF) // md-brightness_6
            enabled: BrightnessService.available
            showValue: true
            valueText: BrightnessService.available ? BrightnessService.percent + "%" : "No backlight"
            value: BrightnessService.level
            from: 0
            to: 1
            onMoved: v => BrightnessService.setLevel(v)
        }
    }
}
