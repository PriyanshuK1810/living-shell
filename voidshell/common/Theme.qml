pragma Singleton

import Quickshell
import QtQuick

// VOID SHELL — centralized geometry, typography and motion.
// No module may scatter these numbers.
Singleton {
    id: root

    // Radii
    readonly property int radiusXs: 6
    readonly property int radiusSm: 10
    readonly property int radiusMd: 14
    readonly property int radiusLg: 18
    readonly property int radiusXl: 22
    readonly property int radiusPanel: 20

    // Spacing
    readonly property int space4: 4
    readonly property int space8: 8
    readonly property int space12: 12
    readonly property int space16: 16
    readonly property int space20: 20
    readonly property int space24: 24
    readonly property int space32: 32
    readonly property int space48: 48
    readonly property int space64: 64

    // Top bar
    readonly property int topMargin: 10
    readonly property int sideMargin: 18
    readonly property int barHeight: 46
    readonly property int pillGap: 8
    readonly property int slantDepth: 16
    readonly property int pillBorderWidth: 1

    // FONTS
    readonly property string fontUi: "Outfit"
    readonly property string fontMono: "JetBrainsMono Nerd Font"

    // MOTION (ms)
    readonly property int durationFast: 140
    readonly property int durationNormal: 180
    readonly property int durationPanel: 220
    readonly property real pressedScale: 0.985
}
