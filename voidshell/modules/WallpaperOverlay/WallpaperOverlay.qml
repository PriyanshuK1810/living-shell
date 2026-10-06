import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../common"
import "../../services"

// VOID SHELL — optional wallpaper overlay window (PRD §29–§30).
//
// One full-screen, fully transparent surface on the Bottom layer: above
// the wallpaper, behind every normal window and on the same layer as
// the bar (which also sits behind apps now); popups stay above windows.
// The input region is an empty mask so nothing here ever captures the
// pointer or keyboard (§29.1), and the whole window only exists while
// an overlay mode other than `off` is selected — the finalized-design
// default (§30).
PanelWindow {
    id: root

    readonly property bool audioOn: WallpaperService.audioOverlay
    readonly property bool clockOn: WallpaperService.clockOverlay

    visible: WallpaperService.overlay !== "off"
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    // -1: never avoid another surface's exclusive zone — the fullscreen
    // overlay must not shrink because the bar reserves the top edge.
    exclusiveZone: -1

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "voidshell-wallpaper-overlay"
    // Empty input region: clicks fall through to whatever is underneath.
    mask: Region {
    }

    // Audio-reactive waveform (PRD §29.1) — spans most of the width.
    OverlayVisualizer {
        visible: root.audioOn
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.70)
    }

    // Central stack: large clock (§30) above synced lyrics (§29.2),
    // nudged up while the waveform owns the lower third.
    Column {
        id: center
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.audioOn ? -60 : 0
        spacing: Theme.space32

        OverlayClock {
            visible: root.clockOn
        }

        OverlayLyrics {
            visible: root.audioOn
        }
    }
}
