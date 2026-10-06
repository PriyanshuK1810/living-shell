import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — now-playing panel, restyled after the neon-purple mockup:
// header (player name + circular close), artwork in a glowing rounded
// frame, title with a favorite badge, artist/album, seek bar with
// elapsed/duration, and five circular transport buttons around a neon
// play knob. Every binding is null-safe; unsupported controls dim and
// swallow input instead of pretending, and with no player the panel
// shows an intentional empty state.
Scope {
    id: root

    // Seek position in [0, 1]; 0 while the player reports no duration.
    readonly property real seekRatio: MediaService.duration > 0 ? Math.min(1, MediaService.position / MediaService.duration) : 0

    // Circular glass transport button (mockup language). `tapped` is
    // named away from MouseArea's own clicked signal.
    component TransportBtn: Item {
        id: tbtn
        property string glyph: ""
        property int glyphSize: 15
        property bool active: false
        property bool available: true
        signal tapped

        implicitWidth: 32
        implicitHeight: 32
        opacity: tbtn.available ? 1.0 : 0.35
        scale: tArea.pressed && tbtn.available ? Theme.pressedScale : 1.0

        Behavior on scale {
            NumberAnimation {
                duration: Theme.durationFast
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: tbtn.active ? Colors.accentStrong : (tArea.containsMouse ? Colors.glassHover : Colors.glassCard)
            border.width: 1
            border.color: tbtn.active ? Colors.borderAccent : (tArea.containsMouse ? Colors.borderGlass : Colors.borderSubtle)
        }

        Text {
            anchors.centerIn: parent
            text: tbtn.glyph
            font.family: Theme.fontMono
            font.pixelSize: tbtn.glyphSize
            color: tbtn.active ? Colors.textOnAccent : (tArea.containsMouse ? Colors.accentLight : Colors.textSecondary)
        }

        MouseArea {
            id: tArea
            anchors.fill: parent
            enabled: tbtn.available
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tbtn.tapped()
        }
    }

    PanelWindow {
        id: win
        anchors {
            top: true
            right: true
        }
        margins {
            top: Theme.topMargin + Theme.barHeight + Theme.space8
            right: Theme.sideMargin
        }
        implicitWidth: 376
        implicitHeight: panel.height + Theme.space16
        // Blur-exempt (halo around the transparent gutter) + ignores the
        // bar's exclusive zone — see PopupShell.
        WlrLayershell.namespace: "voidshell-media"
        // Keyboard while open so Escape closes the panel (default None).
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusiveZone: -1
        color: "transparent"
        visible: PopupManager.isOpen("media")

        onVisibleChanged: {
            if (visible) {
                escGrab.forceActiveFocus();
            }
        }

        // Escape closes from window scope (a clicked slider takes
        // activeFocus and would swallow an off-chain Keys handler) —
        // same treatment as PopupShell; focus claim stays on escGrab.
        Shortcut {
            enabled: win.visible
            context: Qt.ApplicationShortcut
            sequences: [StandardKey.Cancel]
            onActivated: PopupManager.handleEscape()
        }

        Item {
            id: escGrab
            anchors.fill: parent
            focus: true
        }

        Comp.GlassPanel {
            id: panel
            texture: true
            textureSource: InkArt.sourceFor("media")
            anchors.top: parent.top
            // space8 of room above: the ambient shadow bleeds 8px past
            // the panel on every side (see GlassPanel).
            anchors.topMargin: Theme.space8
            anchors.horizontalCenter: parent.horizontalCenter
            width: 360
            height: panelCol.implicitHeight + Theme.space12 * 2

            Column {
                id: panelCol
                anchors.fill: parent
                spacing: Theme.space8

                // --- header: player + circular close -----------------------
                Row {
                    width: parent.width
                    height: 30
                    spacing: Theme.space8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - closeBtn.width - Theme.space8
                        elide: Text.ElideRight
                        text: MediaService.available ? MediaService.identity : "Now Playing"
                        font.family: Theme.fontUi
                        font.weight: Font.DemiBold
                        font.pixelSize: 16
                        color: Colors.textPrimary
                    }

                    Item {
                        id: closeBtn
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        height: 30

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: closeArea.containsMouse ? Colors.glassHover : Qt.rgba(1, 1, 1, 0.05)
                            border.width: 1
                            border.color: closeArea.containsMouse ? Colors.accentLight : Colors.borderGlass
                        }

                        Text {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(0xF00D) // fa-xmark
                            font.family: Theme.fontMono
                            font.pixelSize: 13
                            color: closeArea.containsMouse ? Colors.textPrimary : Colors.textMuted
                        }

                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: PopupManager.closeAll()
                        }
                    }
                }

                // --- artwork: accent bloom + rounded clip + neon outline ----
                Item {
                    id: artFrame
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 180
                    height: 180

                    // One padded layer, blurred shape inside it: the falloff
                    // finishes exactly in the 12px padding (blurMax), so the
                    // layer edge never leaves a hard ring (GlassPanel rule).
                    Item {
                        anchors.centerIn: parent
                        width: artFrame.width + 24
                        height: artFrame.height + 24
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            blurEnabled: true
                            blur: 1.0
                            blurMax: 12
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: artFrame.width
                            height: artFrame.height
                            radius: Theme.radiusSm
                            color: Colors.accentPrimary
                            opacity: 0.95
                        }
                    }

                    // Mask source (alpha channel only): placed behind the
                    // opaque artwork so it reads as part of the art tile
                    // whether the effect samples it or not.
                    Rectangle {
                        id: artMask
                        anchors.fill: parent
                        radius: Theme.radiusSm
                        color: Colors.indigoDeep
                        layer.enabled: true
                    }

                    // Artwork clipped to the rounded frame.
                    Item {
                        id: artClip
                        anchors.fill: parent
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: artMask
                        }

                        Comp.MediaArtwork {
                            anchors.fill: parent
                            artUrl: MediaService.artUrl
                            iconSize: 180
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusSm
                        color: "transparent"
                        border.width: 2
                        border.color: Colors.accentLight
                    }
                }

                // --- title / favorite badge / artist / album ----------------
                Column {
                    width: parent.width
                    spacing: 2

                    Row {
                        width: parent.width
                        spacing: Theme.space8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - favBadge.width - Theme.space8
                            elide: Text.ElideRight
                            text: MediaService.trackTitle !== "" ? MediaService.trackTitle : (MediaService.available ? MediaService.identity : "Nothing playing")
                            font.family: Theme.fontUi
                            font.weight: Font.DemiBold
                            font.pixelSize: 17
                            color: Colors.textPrimary
                        }

                        // Visual-only favorite badge: MPRIS exposes no rating
                        // or favorite property, so it never pretends to be a
                        // button and never claims a state it can't back.
                        Item {
                            id: favBadge
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30
                            height: 30

                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: Qt.rgba(1, 1, 1, 0.04)
                                border.width: 1
                                border.color: Colors.borderAccent
                            }

                            Text {
                                anchors.centerIn: parent
                                text: String.fromCodePoint(0xF004) // fa-heart
                                font.family: Theme.fontMono
                                font.pixelSize: 13
                                color: Colors.accentLight
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: MediaService.artist !== "" ? MediaService.artist : "—"
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        color: Colors.textSecondary
                    }

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: MediaService.album
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        color: Colors.textMuted
                        visible: MediaService.album !== ""
                    }
                }

                // --- seek + elapsed/duration -------------------------------
                Column {
                    width: parent.width
                    spacing: Theme.space4

                    Item {
                        id: seekHost
                        width: parent.width
                        height: 18

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 5
                            radius: 3
                            color: Colors.indigo
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * root.seekRatio
                            height: 5
                            radius: 3
                            color: !MediaService.canSeek ? Colors.plumMuted : (seekArea.containsMouse ? Colors.accentLight : Colors.accentPrimary)

                            Behavior on width {
                                enabled: !seekArea.pressed
                                NumberAnimation {
                                    duration: Theme.durationFast
                                }
                            }
                        }

                        // Soft accent bloom under the handle.
                        Rectangle {
                            x: seekHost.width * root.seekRatio - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22
                            height: 22
                            radius: 11
                            color: Colors.glowAccent
                            visible: MediaService.canSeek
                        }

                        Rectangle {
                            x: seekHost.width * root.seekRatio - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            height: 12
                            radius: 6
                            color: Colors.textOnAccent
                            border.width: 2
                            border.color: MediaService.canSeek ? Colors.accentPrimary : Colors.textDisabled
                        }

                        MouseArea {
                            id: seekArea
                            anchors.fill: parent
                            enabled: MediaService.canSeek
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: mouse => root.seekTo(mouse.x, seekHost.width)
                            onPositionChanged: mouse => {
                                if (pressed) {
                                    root.seekTo(mouse.x, seekHost.width);
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

                // --- transport: shuffle · prev · play · next · repeat --------
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.space12

                    TransportBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32
                        height: 32
                        glyphSize: 14
                        glyph: String.fromCodePoint(0xF074) // fa-shuffle
                        active: MediaService.shuffle
                        available: MediaService.shuffleSupported
                        onTapped: MediaService.toggleShuffle()
                    }

                    TransportBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36
                        height: 36
                        glyph: String.fromCodePoint(0xF048) // fa-backward-step
                        available: MediaService.canPrevious
                        onTapped: MediaService.previous()
                    }

                    // Neon play knob: blurred accent bloom behind a filled
                    // circle — the mockup's signature control.
                    Item {
                        id: playBtn
                        anchors.verticalCenter: parent.verticalCenter
                        width: 46
                        height: 46
                        opacity: playBtn.playable ? 1.0 : 0.35
                        scale: playArea.pressed ? Theme.pressedScale : 1.0

                        readonly property bool playable: MediaService.available && (MediaService.player.canTogglePlaying || (MediaService.playing ? MediaService.canPause : MediaService.canPlay))

                        Behavior on scale {
                            NumberAnimation {
                                duration: Theme.durationFast
                            }
                        }

                        Item {
                            anchors.centerIn: parent
                            width: playBtn.width + 28
                            height: playBtn.height + 28
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                blurEnabled: true
                                blur: 1.0
                                blurMax: 14
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 40
                                height: 40
                                radius: 20
                                color: Colors.accentPrimary
                                opacity: playBtn.playable ? (playArea.containsMouse ? 1.0 : 0.9) : 0.4
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            border.width: 1.5
                            border.color: Colors.accentLight
                            gradient: Gradient {
                                GradientStop {
                                    position: 0.0
                                    color: Colors.accentPrimary
                                }
                                GradientStop {
                                    position: 1.0
                                    color: Colors.accentStrong
                                }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Qt.rgba(1, 1, 1, 0.10)
                            visible: playBtn.playable && playArea.containsMouse
                        }

                        Text {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(MediaService.playing ? 0xF04C : 0xF04B) // fa-pause : fa-play
                            font.family: Theme.fontMono
                            font.pixelSize: 20
                            color: Colors.textOnAccent
                        }

                        MouseArea {
                            id: playArea
                            anchors.fill: parent
                            enabled: playBtn.playable
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: MediaService.togglePlaying()
                        }
                    }

                    TransportBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36
                        height: 36
                        glyph: String.fromCodePoint(0xF051) // fa-forward-step
                        available: MediaService.canNext
                        onTapped: MediaService.next()
                    }

                    TransportBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32
                        height: 32
                        glyphSize: 14
                        glyph: String.fromCodePoint(0xF01E) // fa-repeat
                        active: MediaService.loopState !== 0
                        available: MediaService.loopSupported
                        onTapped: MediaService.cycleLoop()
                    }
                }

                // Repeat state spelled out when it is on (never color-only);
                // hidden at rest so the default panel matches the mockup.
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Repeat: " + MediaService.loopName
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    color: Colors.textMuted
                    visible: MediaService.loopSupported && MediaService.loopState !== 0
                }
            }
        }
    }

    function seekTo(x, w) {
        var ratio = Math.max(0, Math.min(1, x / Math.max(1, w)));
        MediaService.seek(ratio * MediaService.duration);
    }
}
