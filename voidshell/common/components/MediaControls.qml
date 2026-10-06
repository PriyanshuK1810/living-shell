import QtQuick
import ".."
import "../../services"

// VOID SHELL — media transport row wired to the shared MediaService.
// Unsupported controls render dimmed and do nothing; with no player the
// whole row is dimmed. `large` selects the panel variant.
Item {
    id: root
    property bool large: false
    // Reference's round glowing play button (dashboard overview card).
    property bool glowPlay: false

    readonly property int btnSize: root.large ? 48 : 30
    readonly property int playSize: root.large ? 56 : 34

    implicitWidth: btnSize * 2 + playSize + Theme.space8 * 2
    implicitHeight: playSize

    Row {
        anchors.centerIn: parent
        spacing: Theme.space8

        IconButton {
            anchors.verticalCenter: parent.verticalCenter
            width: root.btnSize
            height: root.btnSize
            icon: ""
            enabled: MediaService.canPrevious
            opacity: enabled ? 1.0 : 0.35
            onClicked: MediaService.previous()
        }

        IconButton {
            anchors.verticalCenter: parent.verticalCenter
            width: root.playSize
            height: root.playSize
            icon: MediaService.playing ? "" : ""
            iconSize: root.large ? 22 : 15
            active: MediaService.playing
            glow: root.glowPlay
            round: root.glowPlay
            enabled: MediaService.available && (MediaService.player.canTogglePlaying || (MediaService.playing ? MediaService.canPause : MediaService.canPlay))
            opacity: enabled ? 1.0 : 0.35
            onClicked: MediaService.togglePlaying()
        }

        IconButton {
            anchors.verticalCenter: parent.verticalCenter
            width: root.btnSize
            height: root.btnSize
            icon: ""
            enabled: MediaService.canNext
            opacity: enabled ? 1.0 : 0.35
            onClicked: MediaService.next()
        }
    }
}
