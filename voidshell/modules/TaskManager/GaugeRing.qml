import QtQuick
import "../../common"
import "../../services"

// VOID SHELL — circular usage gauge (PRD 23.3).
// One gauge per real metric (CPU, RAM, disk) fed by SystemStats. The ring
// recolours as load rises so a hot machine is visible at a glance; no
// synthetic smoothing is applied on top of the sampler's values.
Item {
    id: root

    property string label: ""
    property string glyph: ""
    property real value: 0 // percent, 0..100
    property string detail: ""

    readonly property real clamped: {
        const v = Number(value);
        if (!isFinite(v)) {
            return 0;
        }
        return Math.max(0, Math.min(100, v));
    }

    readonly property color ringColor: root.clamped >= 92 ? Colors.danger : (root.clamped >= 78 ? Colors.warning : Colors.accentPrimary)

    implicitWidth: 150
    implicitHeight: 152

    onValueChanged: ring.requestPaint()
    onClampedChanged: ring.requestPaint()

    Column {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.space8

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 104
            height: 104

            Canvas {
                id: ring
                anchors.fill: parent

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const cx = width / 2;
                    const cy = height / 2;
                    const r = Math.min(width, height) / 2 - 8;
                    ctx.lineWidth = 9;
                    ctx.lineCap = "round";
                    ctx.strokeStyle = String(Colors.indigo);
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, 0, Math.PI * 2);
                    ctx.stroke();
                    if (root.clamped > 0.5) {
                        ctx.strokeStyle = String(root.ringColor);
                        ctx.beginPath();
                        ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * (root.clamped / 100));
                        ctx.stroke();
                    }
                }

                // Track color comes from Colors — repaint on theme change.
                Connections {
                    target: ThemeService
                    function onRevisionChanged() {
                        ring.requestPaint();
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 0

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: String(Math.round(root.clamped))
                    font.family: Theme.fontMono
                    font.weight: Font.DemiBold
                    font.pixelSize: 26
                    color: Colors.textPrimary
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "%"
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    color: Colors.textMuted
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 5

            Text {
                text: root.glyph
                font.family: Theme.fontMono
                font.pixelSize: 12
                color: root.ringColor
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: root.label
                font.family: Theme.fontUi
                font.weight: Font.Medium
                font.pixelSize: 12
                color: Colors.textSecondary
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.detail
            font.family: Theme.fontMono
            font.pixelSize: 11
            color: Colors.textMuted
        }
    }
}
