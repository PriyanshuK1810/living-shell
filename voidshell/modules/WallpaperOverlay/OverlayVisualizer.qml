import QtQuick
import "../../common"
import "../../services"

// VOID SHELL — audio waveform over the wallpaper (PRD §29.1).
// 24 rounded bars spanning most of the screen width, coloured from the
// active accent family and driven by VisualizerService's real FFT bands.
// Flat (near-idle) whenever no audio is playing.
Item {
    id: root

    readonly property int barCount: VisualizerService.bandCount
    readonly property int gap: 6

    width: Math.round((Screen.width || 1280) * 0.86)
    height: 110

    Row {
        id: row
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        spacing: root.gap

        Repeater {
            model: root.barCount

            Rectangle {
                id: bar
                readonly property real level: {
                    const b = VisualizerService.bands;
                    return (b && index < b.length) ? (b[index] || 0) : 0;
                }
                width: Math.max(6, Math.round((root.width - root.gap * (root.barCount - 1)) / root.barCount))
                height: 10 + bar.level * (root.height - 10)
                radius: width / 2
                color: Colors.accentPrimary
            }
        }
    }
}
