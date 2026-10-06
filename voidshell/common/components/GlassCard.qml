import QtQuick
import ".."

// VOID SHELL — card surface nested inside a GlassPanel.
// Denser (more opaque) than the parent panel so the panel -> card step
// stays visible. Hover state for interactive cards.
Item {
    id: root

    property bool hovered: false
    // Ink-wash wallpaper texture behind the card glass (dashboard only).
    property bool texture: false
    // Explicit artwork for that texture; empty = live wallpaper.
    property string textureSource: ""
    // Curated crop passed through to the texture (see InkTexture):
    // artwork point at card centre + cover zoom; defaults = centred cover.
    property real textureFocusX: 0.5
    property real textureFocusY: 0.5
    property real textureZoom: 1.0
    // Restrained accent halo (reference's glowing card edges).
    property bool glow: false
    // Border at rest; hovered always wins to glass.
    property color borderNormal: Colors.borderSubtle

    default property alias content: contentItem.data

    implicitWidth: 200
    implicitHeight: 120

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: Theme.radiusMd + 4
        color: Colors.shadowSoft
        opacity: 0.5
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: Theme.radiusMd
        border.width: 1
        border.color: root.hovered ? Colors.borderGlass : root.borderNormal
        color: root.hovered ? Colors.glassHover : Colors.glassCard

        InkTexture {
            anchors.fill: parent
            anchors.margins: 1
            radius: Theme.radiusMd
            source: root.textureSource
            focusX: root.textureFocusX
            focusY: root.textureFocusY
            zoom: root.textureZoom
            visible: root.texture
        }
    }

    GlowBorder {
        anchors.fill: parent
        visible: root.glow
    }

    Item {
        id: contentItem
        anchors.fill: parent
        anchors.margins: Theme.space12
    }
}
