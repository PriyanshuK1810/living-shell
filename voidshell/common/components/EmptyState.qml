import QtQuick
import ".."

// VOID SHELL — empty / unavailable state (PRD 37, 39).
// States an absence honestly: a glyph, a short title and one line of
// explanation, so a panel never pads itself with placeholder content.
Item {
    id: root

    property string glyph: ""
    property string title: ""
    property string body: ""
    property bool busy: false

    implicitWidth: 260
    implicitHeight: col.implicitHeight + Theme.space32 * 2

    Column {
        id: col
        anchors.centerIn: parent
        width: parent.width - Theme.space32 * 2
        spacing: Theme.space8

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.busy ? String.fromCodePoint(0xF110) : root.glyph // fa-spinner when busy
            font.family: Theme.fontMono
            font.pixelSize: 26
            color: Colors.textDisabled

            RotationAnimation on rotation {
                running: root.busy
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 900
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            text: root.title
            font.family: Theme.fontUi
            font.weight: Font.DemiBold
            font.pixelSize: 14
            color: Colors.textSecondary
            visible: root.title !== ""
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            text: root.body
            font.family: Theme.fontUi
            font.pixelSize: 12
            color: Colors.textMuted
            visible: root.body !== ""
        }
    }
}
