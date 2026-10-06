import QtQuick
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — the Island's contextual card (MASTER PROMPT §5 D): the
// expanded view of exactly one activity. Everything on the card is read
// from the activity or from a registered action route — the card never
// invents state and never runs a command. When the activity has already
// finished (or was removed) the card says so instead of showing a stale
// snapshot.
Item {
    id: root

    property var activity: null

    readonly property bool hasActivity: root.activity !== null
    readonly property bool hasWindow: root.hasActivity && root.activity.windowReference !== null
    readonly property bool canPin: root.hasActivity && !ActivityStore.isTerminal(root.activity.state)

    implicitHeight: col.implicitHeight
    visible: root.hasActivity

    Column {
        id: col
        width: parent.width
        spacing: Theme.space8

        // --- state + progress -------------------------------------------
        Row {
            width: parent.width
            spacing: Theme.space8

            Rectangle {
                width: 34
                height: 34
                radius: Theme.radiusXs
                color: Colors.glassHover
                border.width: 1
                border.color: Colors.borderGlass

                Text {
                    anchors.centerIn: parent
                    text: {
                        if (!root.hasActivity) {
                            return "";
                        }
                        switch (root.activity.state) {
                        case "success": return String.fromCodePoint(0xF00C);
                        case "failure": return String.fromCodePoint(0xF00D);
                        case "cancelled": return String.fromCodePoint(0xF00D);
                        case "blocked": return String.fromCodePoint(0xF02E9);
                        case "waiting": return String.fromCodePoint(0xF017);
                        case "paused": return String.fromCodePoint(0xF04A3);
                        default: return String.fromCodePoint(0xF0450);
                        }
                    }
                    font.family: Theme.fontMono
                    font.pixelSize: 16
                    color: root.hasActivity && root.activity.state === "failure" ? Colors.danger : Colors.accentLight
                }
            }

            Column {
                width: parent.width - 42
                spacing: 0

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.hasActivity ? root.activity.title : ""
                    font.family: Theme.fontUi
                    font.weight: Font.DemiBold
                    font.pixelSize: 14
                    color: Colors.textPrimary
                }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: {
                        if (!root.hasActivity) {
                            return "";
                        }
                        const bits = [root.activity.state];
                        const live = TimerStore.labelFor(root.activity.key);
                        if (live !== "") {
                            bits.push(live);
                        } else if (root.activity.subtitle !== "") {
                            bits.push(root.activity.subtitle);
                        }
                        const el = ActivityStore.elapsedLabel(root.activity);
                        if (el !== "") {
                            bits.push(el);
                        }
                        return bits.join(" · ");
                    }
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    color: Colors.textMuted
                }
            }
        }

        // Progress bar + read-out (determinate only).
        Column {
            width: parent.width
            spacing: 2
            visible: root.hasActivity && root.activity.progressMode === "determinate"

            Item {
                width: parent.width
                height: progressLeft.implicitHeight

                Text {
                    id: progressLeft
                    text: "Progress"
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    color: Colors.textMuted
                }
                Text {
                    anchors.right: parent.right
                    text: root.hasActivity ? ActivityStore.progressLabel(root.activity) : ""
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                    color: Colors.textSecondary
                }
            }

            Rectangle {
                width: parent.width
                height: 5
                radius: 2.5
                color: Colors.glassHover

                Rectangle {
                    width: parent.width * (root.hasActivity ? Math.max(0, Math.min(100, root.activity.progressValue)) / 100 : 0)
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
        }

        // --- registered actions (routes against the allowlist) ----------
        Flow {
            width: parent.width
            spacing: Theme.space4
            visible: root.hasActivity && root.activity.registeredActions.length > 0

            Repeater {
                model: root.hasActivity ? root.activity.registeredActions : []

                Comp.TextButton {
                    required property var modelData
                    label: modelData.label
                    height: 30
                    onClicked: ActivityStore.invoke(root.activity.key, modelData.id)
                }
            }
        }

        // --- secondary row: pin, window, dashboard -----------------------
        Row {
            width: parent.width
            spacing: Theme.space4
            visible: root.hasActivity

            Comp.TextButton {
                width: (parent.width - Theme.space4 * 2) / 3
                height: 30
                label: root.pinnedLabel()
                active: root.canPin && ActivityStore.pinnedKey === root.activity.key
                onClicked: ActivityStore.pin(root.activity.key)
            }

            Comp.TextButton {
                width: (parent.width - Theme.space4 * 2) / 3
                height: 30
                // "Return to work": focus the exact window this activity
                // came from. Disabled (not hidden) when there is none.
                label: "Return to work"
                enabled: root.hasWindow
                opacity: enabled ? 1 : 0.5
                onClicked: {
                    if (root.hasWindow) {
                        HyprlandService.activateWindow(root.activity.windowReference.address);
                    }
                }
            }

            Comp.TextButton {
                width: (parent.width - Theme.space4 * 2) / 3
                height: 30
                label: "Dashboard"
                onClicked: IslandRouter.runRoute("dashboard:" + (root.hasActivity ? root.activity.dashboardTarget : "overview"), root.activity)
            }
        }

        // --- sensitive activity: its dashboard target is not shown -------
        Text {
            width: parent.width
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            text: "This activity is marked sensitive — details stay out of the island."
            font.family: Theme.fontUi
            font.pixelSize: 11
            color: Colors.textMuted
            visible: root.hasActivity && root.activity.sensitivity === "sensitive"
        }

        // --- finished state ---------------------------------------------
        Text {
            width: parent.width
            elide: Text.ElideRight
            text: root.hasActivity && ActivityStore.isTerminal(root.activity.state)
                ? "Finished: " + root.activity.state + " · " + ActivityStore.elapsedLabel(root.activity)
                : ""
            font.family: Theme.fontUi
            font.pixelSize: 11
            color: root.hasActivity && root.activity.state === "failure" ? Colors.danger : Colors.success
            visible: text !== ""
        }
    }

    function pinnedLabel() {
        if (!root.canPin) {
            return "Unpin";
        }
        return ActivityStore.pinnedKey === root.activity.key ? "Unpin" : "Pin to clock";
    }
}
