import QtQuick
import QtQuick.Effects
import ".."
import "../../services"

// VOID SHELL — ink-wash wallpaper texture for dashboard glass surfaces
// (reference-matched redesign): the current wallpaper behind a dark veil
// so text keeps contrast, clipped to the host's rounded shape.
// QML's `clip` is rectangular on this Qt build (verified), so the
// artwork rides in a layer masked by a rounded white rect — the mask
// item stays visible:false but still renders its layer (verified).
// Opt-in decoration: callers flip `visible` off for plain glass.
Item {
    id: root

    property int radius: Theme.radiusPanel
    // Explicit artwork (bundled ink-wash asset, resolved by the caller).
    // Empty falls back to the live wallpaper.
    property string source: ""
    // Tuned for the dashboard's dark ink-wash assets: strong presence,
    // veil keeps white text >= ~4.5:1 over the brightest mist areas.
    property real strength: 0.75 // artwork visibility
    property real veil: 0.55 // dark veil alpha over the artwork
    // Curated framing (dashboard cards): focusX/focusY is the artwork
    // point that lands at the centre of the host; zoom scales the cover
    // size so a card can frame one region instead of the whole image.
    // Defaults reproduce the old centred cover-crop (panel, wallpaper).
    property real focusX: 0.5
    property real focusY: 0.5
    property real zoom: 1.0

    layer.enabled: true
    layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: mask
    }

    Item {
        id: mask
        anchors.fill: parent
        layer.enabled: true
        visible: false
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: "white"
        }
    }

    Image {
        id: art
        source: root.source !== "" ? root.source : (WallpaperService.current !== "" ? "file://" + WallpaperService.current : "")
        asynchronous: true
        smooth: true
        opacity: root.strength
        visible: status === Image.Ready
        // Cover size, then shift so focusX/focusY lands on the host's
        // centre — explicit geometry instead of fillMode so the crop
        // stays curated per card. sourceSize is valid once Ready (the
        // visible gate), so the aspect ratio never flashes wrong.
        readonly property real ar: sourceSize.width > 0 ? sourceSize.width / sourceSize.height : 3.0
        readonly property real coverH: Math.max(root.height, root.width / ar)
        width: coverH * ar * root.zoom
        height: coverH * root.zoom
        x: root.width / 2 - root.focusX * width
        y: root.height / 2 - root.focusY * height
    }

    // Ink veil: a flat dark violet wash so bright wallpapers don't eat
    // text contrast inside the card/panel.
    Rectangle {
        anchors.fill: parent
        color: "#0a0714"
        opacity: root.veil
    }
}
