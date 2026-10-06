import QtQuick
import QtQuick.Effects
import ".."

// VOID SHELL — popup panel surface: premium dark glass.
// Combines: two-step ambient shadow (QML-side only — the shell opts out
// of compositor blur, design-system §2),
// subtle top-lit gradient, thin luminous edge, top highlight, optional
// restrained accent glow. Corner radius is fixed to Theme.radiusPanel.
// NOTE: shadow bleeds 3px plus blur falloff (≤8px) past bounds — panels
// need window/padding margin (PopupShell/Media give space8).
Item {
    id: root

    property bool glow: false
    property color glowColor: Colors.glowAccent
    // Ink-wash wallpaper texture behind the glass (dashboard only).
    property bool texture: false
    // Explicit artwork for that texture; empty = live wallpaper.
    property string textureSource: ""

    default property alias content: contentItem.data

    implicitWidth: 320
    implicitHeight: 200

    // Ambient shadow falloff (outer + inner step). Both steps live in one
    // padded layer that MultiEffect blurs: bare Rectangles have hard
    // edges, so two nested steps painted two concentric rings around the
    // panel that read as a halo along the border on light wallpapers —
    // and the compositor can't blur it away (design-system §2), so the
    // falloff has to be soft in QML.
    //
    // Geometry: the host stops at the 8px window gutter every panel gets,
    // each shape stops 3px/1.5px past the panel, and blurMax equals the
    // 5px of padding left outside the shapes. Layer effects are clipped
    // to the layer bounds — if the blur outreached that padding it would
    // leave a weaker (but still visible) step at the layer edge.
    Item {
        anchors.fill: parent
        anchors.margins: -8
        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 5
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 5
            radius: Theme.radiusPanel + 3
            color: Colors.shadowMedium
            opacity: 0.6
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 6.5
            radius: Theme.radiusPanel + 1.5
            color: Colors.shadowMedium
            opacity: 0.4
        }
    }

    // Surface: top-lit gradient between neighboring glass tones.
    Rectangle {
        id: surface
        anchors.fill: parent
        radius: Theme.radiusPanel
        border.color: Colors.borderGlass
        border.width: 1
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Colors.glassHover
            }
            GradientStop {
                position: 1.0
                color: Colors.glassElevated
            }
        }

        // Wallpaper texture under the gradient (1px inset keeps the
        // glass border crisp above it).
        InkTexture {
            anchors.fill: parent
            anchors.margins: 1
            radius: Theme.radiusPanel
            source: root.textureSource
            visible: root.texture
        }
    }

    // Inner top highlight.
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 1
        anchors.leftMargin: Theme.space12
        anchors.rightMargin: Theme.space12
        height: 1
        color: Colors.highlightTop
    }

    GlowBorder {
        anchors.fill: parent
        anchors.margins: -1
        glowColor: root.glowColor
        visible: root.glow
    }

    Item {
        id: contentItem
        anchors.fill: parent
        anchors.margins: Theme.space12
    }
}
