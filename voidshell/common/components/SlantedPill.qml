import QtQuick
import QtQuick.Shapes
import ".."

// VOID SHELL — slanted glass pill primitive (top-bar geometry).
// Real Shape parallelogram; no glyph tricks, no fake overlaps.
//
//   slantLeft / slantRight : which edges slant (complementary joints:
//                            pill A right-only + pill B mirrored left-only
//                            produce parallel shared edges).
//   mirrored = false : lean right  (/ content \)
//   mirrored = true  : lean left   (\ content /)
// Corners are softened with quadratic blends (cornerRadius); edges are
// antialiased (CurveRenderer). The Item never clips, so the optional
// slant-following glow is never cut. Hit box is the full item rect:
// slanted corner triangles are transparent but clickable by design.
Item {
    id: root

    // Geometry config
    property bool slantLeft: true
    property bool slantRight: true
    property bool mirrored: false
    property int slantDepth: Theme.slantDepth
    property int cornerRadius: 10

    // Content inset beyond the slant (Theme: 14). Pills under an island
    // width budget tighten this before they drop any state — see Bar.qml.
    property int contentPad: 14

    // Surface states
    property color fillColor: Colors.glassBase
    property color hoverFillColor: Colors.glassHover
    property color activeFillColor: Colors.glassElevated
    property color borderColor: Colors.borderSubtle
    property color activeBorderColor: Colors.borderAccent
    property int borderWidth: Theme.pillBorderWidth
    property color glowColor: Colors.glowAccent
    property bool glowEnabled: false
    property bool active: false
    property bool hovered: false
    property bool pressed: false

    default property alias content: contentItem.data

    implicitWidth: 140
    implicitHeight: Theme.barHeight

    readonly property color currentFill: (root.active || root.pressed) ? root.activeFillColor : (root.hovered ? root.hoverFillColor : root.fillColor)
    readonly property color currentBorder: root.active ? root.activeBorderColor : root.borderColor

    // Clamped slant so trims never invert on narrow pills.
    readonly property real _s: Math.min(root.slantDepth, root.width * 0.45)

    // Corner coordinates.
    readonly property real _tlX: (!root.mirrored && root.slantLeft) ? _s : 0
    readonly property real _trX: root.width - ((root.mirrored && root.slantRight) ? _s : 0)
    readonly property real _brX: root.width - ((!root.mirrored && root.slantRight) ? _s : 0)
    readonly property real _blX: (root.mirrored && root.slantLeft) ? _s : 0

    // Edge lengths (top/bottom are horizontal by construction).
    readonly property real _topLen: Math.max(0.001, _trX - _tlX)
    readonly property real _rightLen: Math.max(0.001, Math.sqrt(Math.pow(_brX - _trX, 2) + Math.pow(root.height, 2)))
    readonly property real _botLen: Math.max(0.001, _brX - _blX)
    readonly property real _leftLen: Math.max(0.001, Math.sqrt(Math.pow(_tlX - _blX, 2) + Math.pow(root.height, 2)))

    // Corner trim shared by all vertices (bounded by shortest edge).
    readonly property real _d: Math.max(0, Math.min(root.cornerRadius, _topLen / 2, _rightLen / 2, _botLen / 2, _leftLen / 2))

    // Right-edge unit (top -> bottom).
    readonly property real _rux: (_brX - _trX) / _rightLen
    readonly property real _ruy: root.height / _rightLen
    // Left-edge unit (bottom -> top).
    readonly property real _lux: (_tlX - _blX) / _leftLen
    readonly property real _luy: -root.height / _leftLen

    Shape {
        anchors.fill: parent
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer

        // Base surface + border.
        ShapePath {
            fillColor: root.currentFill
            strokeColor: root.currentBorder
            strokeWidth: root.borderWidth
            joinStyle: ShapePath.MiterJoin

            PathMove {
                x: root._tlX + root._d
                y: 0
            }
            PathLine {
                x: root._trX - root._d
                y: 0
            }
            PathQuad {
                x: root._trX + root._rux * root._d
                y: root._ruy * root._d
                controlX: root._trX
                controlY: 0
            }
            PathLine {
                x: root._brX - root._rux * root._d
                y: root.height - root._ruy * root._d
            }
            PathQuad {
                x: root._brX - root._d
                y: root.height
                controlX: root._brX
                controlY: root.height
            }
            PathLine {
                x: root._blX + root._d
                y: root.height
            }
            PathQuad {
                x: root._blX + root._lux * root._d
                y: root.height + root._luy * root._d
                controlX: root._blX
                controlY: root.height
            }
            PathLine {
                x: root._tlX - root._lux * root._d
                y: 0 - root._luy * root._d
            }
            PathQuad {
                x: root._tlX + root._d
                y: 0
                controlX: root._tlX
                controlY: 0
            }
        }

        // Slant-following glow (transparent stroke when disabled).
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.glowEnabled ? root.glowColor : "transparent"
            strokeWidth: root.borderWidth + 4
            joinStyle: ShapePath.MiterJoin

            PathMove {
                x: root._tlX + root._d
                y: 0
            }
            PathLine {
                x: root._trX - root._d
                y: 0
            }
            PathQuad {
                x: root._trX + root._rux * root._d
                y: root._ruy * root._d
                controlX: root._trX
                controlY: 0
            }
            PathLine {
                x: root._brX - root._rux * root._d
                y: root.height - root._ruy * root._d
            }
            PathQuad {
                x: root._brX - root._d
                y: root.height
                controlX: root._brX
                controlY: root.height
            }
            PathLine {
                x: root._blX + root._d
                y: root.height
            }
            PathQuad {
                x: root._blX + root._lux * root._d
                y: root.height + root._luy * root._d
                controlX: root._blX
                controlY: root.height
            }
            PathLine {
                x: root._tlX - root._lux * root._d
                y: 0 - root._luy * root._d
            }
            PathQuad {
                x: root._tlX + root._d
                y: 0
                controlX: root._tlX
                controlY: 0
            }
        }

        // Inner top highlight.
        ShapePath {
            fillColor: "transparent"
            strokeColor: Colors.highlightTop
            strokeWidth: 1

            PathMove {
                x: root._tlX + 4
                y: 1.5
            }
            PathLine {
                x: root._trX - 4
                y: 1.5
            }
        }
    }

    Item {
        id: contentItem
        anchors.fill: parent
        anchors.leftMargin: (root.slantLeft ? root._s : 0) + root.contentPad
        anchors.rightMargin: (root.slantRight ? root._s : 0) + root.contentPad
        anchors.topMargin: 2
        anchors.bottomMargin: 2
    }
}
