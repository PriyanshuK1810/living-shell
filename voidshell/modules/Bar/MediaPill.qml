import Quickshell
import QtQuick
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — media pill: album art, elided track/artist and transport
// controls, all live from the shared MediaService. With no player the
// pill stays visually intentional (dimmed note + "No media"); the
// transport row is dimmed and inert. Clicks on empty pill area toggle
// the now-playing panel.
//
// WIDTH BUDGET: Bar.qml passes `maxWidth` (the right island's budget
// share). The box never exceeds it, and it pays for every pixel it gives
// back in content — track/artist text elides first, then the artwork
// shrinks and finally disappears — so the row can never spill across the
// clock island. `naturalWidth`/`textShrinkable`/`artShrinkable` are the
// lever report Bar splits the budget with; they depend only on the live
// text, never on `maxWidth`, so no binding loop is possible.
Comp.SlantedPill {
    id: root
    property var shellScreen: null

    // --- width budget (set by Bar.qml) ---------------------------------
    property int maxWidth: 4000

    readonly property int padBase: (Theme.slantDepth + 14) * 2
    readonly property int artMax: 30
    readonly property int gapW: Theme.space8
    readonly property int colMax: 110
    readonly property int colMin: 40

    // Natural geometry at full content width (never driven by maxWidth).
    readonly property int colNatural: Math.min(root.colMax, Math.max(titleText.implicitWidth, artistText.implicitWidth))
    readonly property int naturalContent: root.artMax + root.gapW + root.colNatural + root.gapW + controls.implicitWidth
    readonly property int naturalWidth: Math.min(360, Math.max(200, root.naturalContent + root.padBase))

    // Lever capacities, spent in this order: text, then artwork.
    readonly property int textShrinkable: Math.max(0, root.colNatural - root.colMin)
    readonly property int artShrinkable: root.artMax + root.gapW

    // Where the pixels the box gave back actually went.
    readonly property int shrink: Math.max(0, root.naturalWidth - root.width)
    readonly property int textShrink: Math.min(root.shrink, root.textShrinkable)
    readonly property int artShrink: Math.max(0, root.shrink - root.textShrink)
    readonly property int artSize: Math.max(0, root.artMax - Math.min(root.artMax, root.artShrink))
    readonly property int colCap: Math.max(root.colMin, root.colNatural - root.textShrink)

    width: Math.min(root.maxWidth, root.naturalWidth)
    height: Theme.barHeight
    mirrored: true
    fillColor: Colors.glassBase
    borderColor: Colors.borderSubtle
    glowEnabled: true

    MouseArea {
        anchors.fill: parent
        onClicked: PopupManager.toggle("media", root.shellScreen, root)
    }

    Row {
        id: pillRow
        anchors.centerIn: parent
        spacing: Theme.space8

        Comp.MediaArtwork {
            anchors.verticalCenter: parent.verticalCenter
            artUrl: MediaService.artUrl
            iconSize: root.artSize
            visible: root.artSize > 0
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
                id: titleText
                width: Math.min(implicitWidth, root.colCap)
                elide: Text.ElideRight
                text: MediaService.available ? (MediaService.trackTitle !== "" ? MediaService.trackTitle : MediaService.identity) : "No media"
                font.family: Theme.fontUi
                font.weight: Font.Medium
                font.pixelSize: 13
                color: MediaService.available ? Colors.textSecondary : Colors.textMuted
            }

            Text {
                id: artistText
                width: Math.min(implicitWidth, root.colCap)
                elide: Text.ElideRight
                text: MediaService.available ? (MediaService.artist !== "" ? MediaService.artist : MediaService.album) : "—"
                font.family: Theme.fontUi
                font.pixelSize: 11
                color: Colors.textMuted
            }
        }

        Comp.MediaControls {
            id: controls
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
