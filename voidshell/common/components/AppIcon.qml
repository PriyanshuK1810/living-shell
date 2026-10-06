import QtQuick
import ".."

// VOID SHELL — application icon scaffold. Real desktop-entry/icon-theme
// lookup arrives with the launcher phase; API (name/size/fallback) is fixed.
Item {
    id: root
    property string iconName: ""
    property int iconSize: 32

    implicitWidth: root.iconSize
    implicitHeight: root.iconSize

    Text {
        anchors.centerIn: parent
        text: "▢"
        font.family: Theme.fontMono
        font.pixelSize: root.iconSize * 0.7
        color: Colors.textMuted
    }
}
