import QtQuick
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — one row of the Living State Island activity stack
// (MASTER PROMPT §17). Shows what an activity is, how it is going and
// what the user can do about it — every action is a *registered route*
// resolved by IslandRouter against its allowlist, never a command.
Item {
    id: root

    property var activity: null
    property bool expanded: false
    signal openRequested

    readonly property bool terminal: root.activity !== null && ActivityStore.isTerminal(root.activity.state)
    readonly property bool pinned: root.activity !== null && ActivityStore.pinnedKey === root.activity.key

    height: row.implicitHeight + (root.expanded ? actions.implicitHeight + Theme.space8 : 0)
    implicitHeight: height

    // Interaction protection: pressing inside a row freezes the stack
    // order so no row can move out from under the pointer (§7). The same
    // area provides the hover state for the row background.
    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        onPressed: IslandController.beginInteraction()
        onReleased: IslandController.endInteraction()
        onCanceled: IslandController.endInteraction()
        onClicked: root.openRequested()
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: hit.containsMouse ? Colors.glassHover : Colors.glassCard
        border.width: 1
        border.color: root.pinned ? Colors.borderAccent : (root.expanded ? Colors.borderGlass : Colors.borderSubtle)
    }

    Column {
        id: row
        width: parent.width
        padding: Theme.space8
        spacing: 2

        Row {
            width: parent.width - Theme.space16
            spacing: Theme.space8

            // State glyph: honest per state, never a fake spinner.
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    if (root.activity === null) {
                        return "";
                    }
                    switch (root.activity.state) {
                    case "success": return String.fromCodePoint(0xF00C); // check
                    case "failure": return String.fromCodePoint(0xF00D); // xmark
                    case "cancelled": return String.fromCodePoint(0xF00D);
                    case "blocked": return String.fromCodePoint(0xF02E9); // pause-ish
                    case "waiting": return String.fromCodePoint(0xF017); // clock
                    case "paused": return String.fromCodePoint(0xF04A3); // pause
                    default: return String.fromCodePoint(0xF0450); // refresh (working)
                    }
                }
                font.family: Theme.fontMono
                font.pixelSize: 13
                color: root.terminal
                    ? (root.activity !== null && root.activity.state === "failure" ? Colors.danger : Colors.success)
                    : Colors.accentLight
            }

            Column {
                width: parent.width - Theme.space48
                spacing: 0

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.activity === null ? "" : root.activity.title
                    font.family: Theme.fontUi
                    font.weight: Font.DemiBold
                    font.pixelSize: 13
                    color: Colors.textPrimary
                }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    // Live labels (timers/stopwatch) come from TimerStore so
                    // the row never needs a per-second activity write.
                    text: {
                        if (root.activity === null) {
                            return "";
                        }
                        const live = TimerStore.labelFor(root.activity.key);
                        if (live !== "") {
                            return live;
                        }
                        return root.activity.subtitle !== "" ? root.activity.subtitle : root.activity.activityType;
                    }
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    color: Colors.textMuted
                }
            }

            // Pin marker (exactly one activity may be pinned).
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.pinned
                text: String.fromCodePoint(0xF0389) // md-pin
                font.family: Theme.fontMono
                font.pixelSize: 12
                color: Colors.accentLight
            }

            // Progress read-out, only when the activity reports one.
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.activity !== null && root.activity.progressMode !== "none"
                text: root.activity === null ? "" : ActivityStore.progressLabel(root.activity)
                font.family: Theme.fontMono
                font.pixelSize: 11
                color: Colors.textSecondary
            }
        }

        // Determinate progress bar (never indeterminate guessing).
        Rectangle {
            width: parent.width - Theme.space16
            height: 3
            radius: 1.5
            color: Colors.glassHover
            visible: root.activity !== null && root.activity.progressMode === "determinate"

            Rectangle {
                width: parent.width * (root.activity === null ? 0 : Math.max(0, Math.min(100, root.activity.progressValue)) / 100)
                height: parent.height
                radius: parent.radius
                color: Colors.accentStrong

                Behavior on width {
                    NumberAnimation {
                        duration: IslandSettings.durationRow
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // Expanded: registered actions only (routes, not commands).
        Column {
            id: actions
            width: parent.width - Theme.space16
            spacing: Theme.space4
            visible: root.expanded && root.activity !== null && root.activity.registeredActions.length > 0

            Flow {
                width: parent.width
                spacing: Theme.space4

                Repeater {
                    model: root.activity === null ? [] : root.activity.registeredActions

                    Comp.TextButton {
                        required property var modelData
                        label: modelData.label
                        height: 28
                        onClicked: ActivityStore.invoke(root.activity.key, modelData.id)
                    }
                }
            }
        }
    }
}
