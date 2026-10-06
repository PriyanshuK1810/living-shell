import QtQuick
import QtQuick.Effects
import Quickshell
import "../../common"

// VOID SHELL — large wallpaper clock/date (PRD §30).
// Independent of the top bar, locale-aware, and legible over any
// wallpaper via a soft drop shadow. Only ever instantiated inside the
// overlay window, so it costs nothing while the mode is off.
Column {
    id: root

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    spacing: Theme.space4

    Text {
        id: timeText
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatTime(clock.date, "hh:mm")
        font.family: Theme.fontUi
        font.weight: Font.DemiBold
        font.pixelSize: 148
        color: Colors.textPrimary

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#bb000000"
            shadowBlur: 0.5
            shadowVerticalOffset: 3
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatDate(clock.date, "dddd, d MMMM")
        font.family: Theme.fontUi
        font.weight: Font.Medium
        font.pixelSize: 30
        color: Colors.textSecondary
    }
}
