import QtQuick
import ".."

// VOID SHELL — media artwork: real MPRIS art when artUrl resolves,
// quiet note glyph on a deep indigo tile otherwise (never blank).
Item {
    id: root
    property string artUrl: ""
    property int iconSize: 56

    implicitWidth: root.iconSize
    implicitHeight: root.iconSize

    Rectangle {
        anchors.fill: parent
        color: Colors.indigoDeep
        border.color: Colors.borderSubtle
        border.width: 1
        radius: Theme.radiusSm
    }

    Text {
        anchors.centerIn: parent
        text: "♪"
        font.family: Theme.fontMono
        font.pixelSize: root.iconSize * 0.45
        color: Colors.textMuted
        visible: artImage.status !== Image.Ready
    }

    Image {
        id: artImage
        anchors.fill: parent
        source: root.artUrl
        visible: status === Image.Ready
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        smooth: true
    }
}
