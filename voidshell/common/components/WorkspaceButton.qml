import QtQuick
import ".."
import "../../services"

// VOID SHELL — workspace slot marker (plan §4).
//
// One component, two renderings, so a settings flag can restore the
// previous interface without a second component tree (§16):
//   style "dash"   — the desktop manager's glass count chip: a 26px
//                    pill showing the workspace's real window count,
//                    blank when the workspace is empty (plan §4)
//   style "number" — the original numbered button, kept byte-for-byte
//                    for managerEnabled = false
//
// The dash shows the *resting* state of its workspace; the focused
// slot's bright highlight is drawn by the pill as one element that
// animates horizontally between the fixed slots, so neither the pill nor
// its neighbours can move.
Item {
    id: root

    property int index: 1
    property bool active: false
    property bool urgent: false
    property bool exists: true
    property bool occupied: false
    // Real window count of this workspace (plan §4): the caller reads it
    // from the shared model on every event, so the chip can never show a
    // stale or invented number.
    property int count: 0
    property string style: "dash"
    // Value reported by `selected`. Defaults to the numeric index, which
    // is what the legacy strip activates by; the dash passes the
    // workspace name so a named workspace is activated by its real name
    // instead of a guessed id.
    property var selectionTarget: root.index
    signal selected(var target)

    readonly property bool hovered: area.containsMouse
    // Hover only brightens: it never activates a workspace (plan §4).

    implicitWidth: 30
    implicitHeight: 30

    // ---- dash style ----------------------------------------------------
    Item {
        anchors.fill: parent
        visible: root.style === "dash"

        // Restrained halo behind the focused slot; the pill's one sliding
        // underline lands on this slot, so the halo only adds depth.
        Rectangle {
            anchors.centerIn: parent
            width: 30
            height: 24
            radius: 12
            color: Colors.glowAccent
            visible: root.active
            opacity: 0.35
        }

        // Glass count chip (plan §4): 26px pill carrying the workspace's
        // real window count. A chip with no number means zero windows —
        // an empty outline is the honest "0", nothing is ever faked.
        Rectangle {
            id: chip
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -3
            width: 26
            height: 18
            radius: 6
            color: root.occupied && root.exists ? Colors.glassElevated : "transparent"
            border.width: 1
            border.color: {
                if (root.urgent) {
                    return Colors.danger;
                }
                if (!root.exists) {
                    return Colors.borderSubtle;
                }
                if (root.active) {
                    return Colors.borderAccentStrong;
                }
                if (root.hovered) {
                    return Colors.borderGlass;
                }
                return root.occupied ? Colors.borderGlass : Colors.borderSubtle;
            }
            Behavior on border.color {
                ColorAnimation {
                    duration: ManagerSettings.durationHover
                }
            }
        }

        Text {
            anchors.centerIn: chip
            text: root.occupied && root.exists ? String(root.count) : ""
            font.family: Theme.fontUi
            font.weight: Font.DemiBold
            font.pixelSize: 11
            color: root.urgent ? Colors.danger : (root.active ? Colors.textPrimary : Colors.textSecondary)
        }
    }

    // ---- legacy numbered style (feature disabled) ----------------------
    Item {
        anchors.fill: parent
        visible: root.style === "number"

        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            radius: 10
            color: "transparent"
            border.color: Colors.glowAccent
            border.width: 2
            opacity: 0.5
            visible: root.active
        }

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: root.active ? Colors.accentStrong : "transparent"
            border.width: 1
            border.color: root.active ? Colors.borderAccent : (root.urgent ? Colors.danger : "transparent")
        }

        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: root.urgent ? -2 : 0
            text: root.index
            font.family: Theme.fontUi
            font.weight: Font.DemiBold
            font.pixelSize: 13
            opacity: root.exists ? 1.0 : 0.45
            color: root.active ? Colors.textOnAccent : (root.urgent ? Colors.danger : Colors.textMuted)
        }

        // Urgency marker (PRD 12.1): a danger dot, hidden on the active
        // workspace where the accent treatment already carries attention.
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 1
            anchors.bottomMargin: 1
            width: 6
            height: 6
            radius: 3
            color: Colors.danger
            visible: root.urgent && !root.active
        }
    }

    // One hit area for both styles: left click activates (only when the
    // workspace actually exists), hover changes nothing else.
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.exists) {
                root.selected(root.selectionTarget);
            }
        }
    }
}
