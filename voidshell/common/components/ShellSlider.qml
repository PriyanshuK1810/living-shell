import QtQuick
import ".."

// VOID SHELL — slider primitive (volume / brightness).
// Mockup layout: circular icon badge, name above the track, value on the
// right. The badge doubles as an action when the caller asks for it
// (volume: tap the speaker to mute) so no extra chrome is needed.
// Pointer-driven: click or drag anywhere on the track jumps and drags.
// `moved` reports the requested value in [from, to]; the caller stays the
// single source of truth for `value`, so a backend that refuses the change
// simply never updates and the handle follows real state back.
Item {
    id: root
    property real from: 0
    property real to: 1
    property real value: 0
    property bool enabled: true
    property bool showValue: false
    property string valueText: ""
    property bool valueAlert: false
    property string icon: ""
    property string label: ""
    property bool iconAction: false
    signal iconClicked
    signal moved(real value)

    implicitWidth: 200
    implicitHeight: root.label !== "" ? 48 : 30
    opacity: root.enabled ? 1.0 : 0.45

    readonly property real span: Math.max(0.0001, root.to - root.from)
    readonly property real ratio: Math.max(0, Math.min(1, (root.value - root.from) / root.span))

    readonly property int badgeSize: 30
    readonly property int knobSize: 13
    // Size the track so the knob and the value label stay inside the bounds.
    readonly property int valueW: root.showValue && root.valueText !== "" ? valueText.implicitWidth : 0
    readonly property int trackW: Math.max(1, labelCol.width - root.valueW - (root.valueW > 0 ? Theme.space12 : 0))

    function valueAt(x) {
        const w = Math.max(1, trackW);
        const r = Math.max(0, Math.min(1, x / w));
        return root.from + r * root.span;
    }

    // --- circular icon badge (optional action target) --------------------
    Rectangle {
        id: badge
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.badgeSize
        height: root.badgeSize
        radius: root.badgeSize / 2
        color: badgeArea.containsMouse ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: badgeArea.containsMouse ? Colors.borderGlass : Colors.borderSubtle

        Text {
            anchors.centerIn: parent
            text: root.icon
            font.family: Theme.fontMono
            font.pixelSize: 15
            color: badgeArea.containsMouse ? Colors.accentLight : (root.enabled ? Colors.textSecondary : Colors.textDisabled)
            visible: root.icon !== ""
        }
    }

    MouseArea {
        id: badgeArea
        anchors.fill: badge
        hoverEnabled: true
        enabled: root.iconAction && root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.iconClicked()
    }

    // --- label + track + value ------------------------------------------
    Column {
        id: labelCol
        anchors.left: badge.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5

        Text {
            width: parent.width
            text: root.label
            font.family: Theme.fontUi
            font.weight: Font.Medium
            font.pixelSize: 12
            color: root.enabled ? Colors.textSecondary : Colors.textDisabled
            visible: root.label !== ""
        }

        Row {
            width: parent.width
            spacing: Theme.space12

            Item {
                id: trackHost
                width: root.trackW
                height: root.knobSize + 11

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 5
                    radius: 3
                    color: Colors.indigo
                }

                Rectangle {
                    id: fill
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * root.ratio
                    height: 5
                    radius: 3
                    color: dragArea.containsMouse && root.enabled ? Colors.accentLight : Colors.accentPrimary

                    Behavior on width {
                        enabled: !dragArea.pressed
                        NumberAnimation {
                            duration: Theme.durationFast
                        }
                    }
                }

                // Soft accent bloom under the handle (mockup's glowing knob).
                Rectangle {
                    x: trackHost.width * root.ratio - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.knobSize + 10
                    height: width
                    radius: width / 2
                    color: Colors.glowAccent
                    visible: root.enabled
                }

                Rectangle {
                    id: knob
                    x: trackHost.width * root.ratio - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.knobSize
                    height: root.knobSize
                    radius: root.knobSize / 2
                    color: Colors.textOnAccent
                    border.width: 2
                    border.color: Colors.accentPrimary
                    scale: dragArea.pressed ? 1.25 : 1.0

                    Behavior on scale {
                        NumberAnimation {
                            duration: Theme.durationFast
                        }
                    }
                }

                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    enabled: root.enabled
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => root.moved(root.valueAt(mouse.x))
                    onPositionChanged: mouse => {
                        if (pressed) {
                            root.moved(root.valueAt(mouse.x));
                        }
                    }
                }
            }

            Text {
                id: valueText
                anchors.verticalCenter: parent.verticalCenter
                text: root.valueText
                font.family: Theme.fontUi
                font.weight: Font.Medium
                font.pixelSize: 12
                color: root.valueAlert ? Colors.warning : (dragArea.containsMouse ? Colors.textPrimary : Colors.textMuted)
                visible: root.showValue && root.valueText !== ""
            }
        }
    }
}
