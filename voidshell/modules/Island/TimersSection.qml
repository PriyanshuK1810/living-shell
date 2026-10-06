import QtQuick
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — the Island's timer block (MASTER PROMPT F16): the named
// countdowns and the stopwatch from TimerStore, plus one-tap creation of
// the three lengths a laptop user actually reaches for. Every timer row
// shows its real remaining time (wall-clock anchored) and can be paused,
// reset or dropped. The focus/break timer stays in the Dashboard's
// Productivity tab — this block does not duplicate it.
Item {
    id: root

    readonly property bool showStopwatch: TimerStore.swRunning || TimerStore.swAccumulatedMs > 0

    implicitHeight: col.implicitHeight

    Column {
        id: col
        width: parent.width
        spacing: Theme.space8

        // --- creation row ----------------------------------------------
        Flow {
            width: parent.width
            spacing: Theme.space4

            Comp.TextButton {
                label: "5 min"
                height: 28
                onClicked: TimerStore.addTimer("Timer", 5 * 60)
            }
            Comp.TextButton {
                label: "10 min"
                height: 28
                onClicked: TimerStore.addTimer("Timer", 10 * 60)
            }
            Comp.TextButton {
                label: "25 min"
                height: 28
                onClicked: TimerStore.addTimer("Focus", 25 * 60)
            }
            Comp.TextButton {
                label: root.showStopwatch ? ("Stopwatch " + TimerStore.swLabel) : "Stopwatch"
                height: 28
                active: TimerStore.swRunning
                onClicked: TimerStore.swToggle()
            }
        }

        Text {
            width: parent.width
            text: root.showStopwatch ? "" : "No countdowns running"
            font.family: Theme.fontUi
            font.pixelSize: 11
            color: Colors.textMuted
            visible: TimerStore.count === 0 && !root.showStopwatch
        }

        // --- countdown rows --------------------------------------------
        Repeater {
            model: TimerStore.timers

            delegate: Rectangle {
                required property var modelData
                width: col.width
                height: 34
                radius: Theme.radiusXs
                color: Colors.glassCard
                border.width: 1
                border.color: modelData.running ? Colors.borderAccent : Colors.borderSubtle

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.space8
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 120
                    elide: Text.ElideRight
                    text: modelData.label + " · " + TimerStore.fmt(TimerStore.remainingOf(modelData) * 1000)
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    color: Colors.textPrimary
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.space4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.space4

                    Comp.TextButton {
                        width: 44
                        height: 24
                        label: modelData.running ? "Pause" : "Start"
                        onClicked: TimerStore.toggleTimer(modelData.id)
                    }
                    Comp.TextButton {
                        width: 44
                        height: 24
                        label: "Reset"
                        onClicked: TimerStore.resetTimer(modelData.id)
                    }
                    Comp.TextButton {
                        width: 24
                        height: 24
                        label: "×"
                        onClicked: TimerStore.removeTimer(modelData.id)
                    }
                }
            }
        }

        // --- stopwatch row ---------------------------------------------
        Row {
            width: parent.width
            spacing: Theme.space4
            visible: root.showStopwatch

            Comp.TextButton {
                width: (parent.width - Theme.space4 * 2) / 3
                height: 28
                label: TimerStore.swRunning ? "Lap" : "Resume"
                enabled: TimerStore.swRunning || TimerStore.swAccumulatedMs > 0
                onClicked: TimerStore.swRunning ? TimerStore.swLap() : TimerStore.swStart()
            }
            Comp.TextButton {
                width: (parent.width - Theme.space4 * 2) / 3
                height: 28
                label: TimerStore.swRunning ? "Stop" : "Start"
                active: TimerStore.swRunning
                onClicked: TimerStore.swToggle()
            }
            Comp.TextButton {
                width: (parent.width - Theme.space4 * 2) / 3
                height: 28
                label: "Reset"
                onClicked: TimerStore.swReset()
            }
        }
    }
}
