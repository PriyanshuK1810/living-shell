import QtQuick
import "../../common"
import "../../services"

// VOID SHELL — rolling history chart (PRD 23.4).
// Draws the real sample series held by SystemStats (CPU, memory, network).
// An empty series renders as a quiet baseline, never as a fake curve.
Item {
    id: root

    property string title: ""
    property string subtitle: ""
    property var values: []
    property var values2: [] // optional second series (e.g. upload)
    property real maxValue: 100
    property color series1: Colors.accentPrimary
    property color series2: Colors.success
    property string legend1: ""
    property string legend2: ""

    implicitWidth: 240
    implicitHeight: header.implicitHeight + 96

    onValuesChanged: chart.requestPaint()
    onValues2Changed: chart.requestPaint()
    onMaxValueChanged: chart.requestPaint()

    Column {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 2

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: root.title
            font.family: Theme.fontUi
            font.weight: Font.DemiBold
            font.pixelSize: 13
            color: Colors.textPrimary
        }

        Row {
            spacing: 10

            Text {
                visible: root.subtitle !== ""
                text: root.subtitle
                font.family: Theme.fontMono
                font.pixelSize: 11
                color: Colors.textMuted
            }

            Text {
                visible: root.legend1 !== ""
                text: root.legend1
                font.family: Theme.fontUi
                font.pixelSize: 10
                color: root.series1
            }

            Text {
                visible: root.legend2 !== ""
                text: root.legend2
                font.family: Theme.fontUi
                font.pixelSize: 10
                color: root.series2
            }
        }
    }

    Canvas {
        id: chart
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: Theme.space8

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const w = width;
            const h = height;
            if (w <= 0 || h <= 0) {
                return;
            }

            // Baseline grid: 50% and 100% guides.
            ctx.strokeStyle = String(Colors.borderSubtle);
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.moveTo(0, Math.round(h / 2) + 0.5);
            ctx.lineTo(w, Math.round(h / 2) + 0.5);
            ctx.stroke();

            root.drawSeries(ctx, root.values, root.series1, w, h);
            root.drawSeries(ctx, root.values2, root.series2, w, h);
        }

        // Grid lines come from Colors — repaint on theme change.
        Connections {
            target: ThemeService
            function onRevisionChanged() {
                chart.requestPaint();
            }
        }
    }

    // Draws one sample series as a line plus a translucent area fill.
    // maxValue <= 0 means "auto-scale to the series peak".
    function drawSeries(ctx, arr, color, w, h) {
        if (arr === undefined || arr === null || arr.length === 0) {
            return;
        }
        let max = Number(maxValue);
        if (!isFinite(max) || max <= 0) {
            max = 1;
            for (let k = 0; k < arr.length; k++) {
                const sample = Number(arr[k]);
                if (isFinite(sample)) {
                    max = Math.max(max, sample);
                }
            }
            max = max * 1.15;
        }
        const n = arr.length;
        const px = i => (n > 1 ? (i / (n - 1)) * w : w);
        const py = v => {
            const value = Number(v);
            const clamped = isFinite(value) ? Math.max(0, Math.min(max, value)) : 0;
            return h - 1 - (clamped / max) * (h - 4);
        };

        ctx.beginPath();
        for (let i = 0; i < n; i++) {
            const x = px(i);
            const y = py(arr[i]);
            if (i === 0) {
                ctx.moveTo(x, y);
            } else {
                ctx.lineTo(x, y);
            }
        }
        ctx.lineWidth = 1.6;
        ctx.lineJoin = "round";
        ctx.strokeStyle = String(color);
        ctx.stroke();

        // Area fill under the line (alpha via globalAlpha, keeps it
        // independent of how the colour token is written).
        if (n > 1) {
            ctx.lineTo(px(n - 1), h);
            ctx.lineTo(px(0), h);
            ctx.closePath();
            ctx.globalAlpha = 0.14;
            ctx.fillStyle = String(color);
            ctx.fill();
            ctx.globalAlpha = 1;
        } else {
            // Single sample: show it as a point instead of a flat line.
            ctx.beginPath();
            ctx.arc(px(0), py(arr[0]), 2.2, 0, Math.PI * 2);
            ctx.fillStyle = String(color);
            ctx.fill();
        }
    }
}
