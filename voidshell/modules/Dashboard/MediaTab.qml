import QtQuick
import Quickshell
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — dashboard Media tab (PRD 22.2): large art, identity,
// title/artist, seekable timeline and transport — all from the single
// shared MediaService (no second MPRIS stack). With no player the tab
// shows an honest empty state instead of sample metadata.
Item {
    id: root

    Column {
        anchors.centerIn: parent
        width: parent.width - Theme.space32
        spacing: Theme.space16

        Comp.MediaArtwork {
            anchors.horizontalCenter: parent.horizontalCenter
            artUrl: MediaService.artUrl
            iconSize: 200
            visible: MediaService.available
        }

        Comp.EmptyState {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            glyph: String.fromCodePoint(0xF0004) // md-account (media placeholder)
            title: "No player running"
            body: "Start a player and its real MPRIS metadata appears here."
            visible: !MediaService.available
        }

        Column {
            width: parent.width
            spacing: 2
            visible: MediaService.available

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: MediaService.trackTitle !== "" ? MediaService.trackTitle : "Nothing playing"
                font.family: Theme.fontUi
                font.weight: Font.DemiBold
                font.pixelSize: 20
                color: Colors.textPrimary
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: MediaService.artist !== "" ? MediaService.artist : "—"
                font.family: Theme.fontUi
                font.pixelSize: 14
                color: Colors.textSecondary
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: [MediaService.identity, MediaService.album].filter(v => v !== "").join(" · ")
                font.family: Theme.fontUi
                font.pixelSize: 12
                color: Colors.textMuted
                visible: text !== ""
            }
        }

        // Timeline: seek only when the player reports seek support.
        Column {
            width: parent.width
            spacing: Theme.space4
            visible: MediaService.available

            Item {
                width: parent.width
                height: 20

                Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 5
                    radius: 3
                    color: Colors.indigo
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: MediaService.duration > 0 ? track.width * Math.min(1, MediaService.position / MediaService.duration) : 0
                    height: 5
                    radius: 3
                    color: MediaService.canSeek ? Colors.accentPrimary : Colors.plumMuted
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: MediaService.duration > 0 ? track.width * Math.min(1, MediaService.position / MediaService.duration) - 6 : -6
                    width: 12
                    height: 12
                    radius: 6
                    color: MediaService.canSeek ? Colors.accentLight : Colors.textDisabled
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: MediaService.canSeek
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => seek(mouse.x, track.width)
                    onPositionChanged: mouse => {
                        if (pressed) {
                            seek(mouse.x, track.width);
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: 14

                Text {
                    anchors.left: parent.left
                    text: MediaService.fmtTime(MediaService.position)
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    color: Colors.textMuted
                }

                Text {
                    anchors.right: parent.right
                    text: MediaService.fmtTime(MediaService.duration)
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    color: Colors.textMuted
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.space16
            visible: MediaService.available

            Comp.IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: String.fromCodePoint(0xF074) // fa-shuffle
                active: MediaService.shuffle
                enabled: MediaService.shuffleSupported
                opacity: enabled ? 1.0 : 0.3
                onClicked: MediaService.toggleShuffle()
            }

            Comp.MediaControls {
                anchors.verticalCenter: parent.verticalCenter
                large: true
            }

            Comp.IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: String.fromCodePoint(0xF01E) // fa-repeat
                active: MediaService.loopState !== 0
                enabled: MediaService.loopSupported
                opacity: enabled ? 1.0 : 0.3
                onClicked: MediaService.cycleLoop()
            }
        }
    }

    function seek(x, w) {
        const ratio = Math.max(0, Math.min(1, x / Math.max(1, w)));
        MediaService.seek(ratio * MediaService.duration);
    }
}
