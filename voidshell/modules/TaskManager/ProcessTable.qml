import QtQuick
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — process table (PRD 23.5).
// Name / PID / CPU / memory with sortable columns; SystemStats samples `ps`
// about every 3 s while this view is open and stops when it closes.
//
// Deliberately read-only: PRD 23.5 keeps terminate/kill out of the baseline
// unless a confirmation flow exists, and the test suite must never run a
// destructive action — so no kill control is rendered at all.
Item {
    id: root

    property string sortKey: "cpu" // cpu | mem | pid | name
    property bool descending: true

    // Column widths are derived from the panel width so the table fits any
    // drawer size; the name column absorbs the remainder.
    readonly property int pidWidth: 56
    readonly property int valueWidth: 62
    readonly property int fixedWidth: pidWidth + valueWidth * 2

    // Re-sorted from the live service array on every sample.
    readonly property var rows: {
        const list = SystemStats.processes.slice();
        const key = root.sortKey;
        const dir = root.descending ? -1 : 1;
        list.sort((a, b) => {
            const av = key === "name" ? String(a.name).toLowerCase() : a[key];
            const bv = key === "name" ? String(b.name).toLowerCase() : b[key];
            if (av < bv) {
                return -dir;
            }
            if (av > bv) {
                return dir;
            }
            return 0;
        });
        return list;
    }

    readonly property bool waiting: SystemStats.processes.length === 0

    implicitWidth: 308
    implicitHeight: 244

    function select(key) {
        if (root.sortKey === key) {
            root.descending = !root.descending;
        } else {
            root.sortKey = key;
            root.descending = key !== "name" && key !== "pid";
        }
    }

    function headerCell(label, key, w) {
        const active = root.sortKey === key;
        return {
            label: label,
            key: key,
            active: active,
            width: w,
            arrow: active ? (root.descending ? String.fromCodePoint(0xF063) : String.fromCodePoint(0xF062)) : ""
        };
    }

    Column {
        id: col
        anchors.fill: parent
        spacing: Theme.space4

        // Column header (click to sort, click again to flip direction).
        Row {
            width: parent.width
            height: 24

            Repeater {
                model: [
                    root.headerCell("Process", "name", root.width - root.fixedWidth),
                    root.headerCell("PID", "pid", root.pidWidth),
                    root.headerCell("CPU", "cpu", root.valueWidth),
                    root.headerCell("MEM", "mem", root.valueWidth)
                ]

                delegate: Rectangle {
                    required property var modelData
                    width: modelData.width
                    height: 24
                    radius: Theme.radiusXs
                    color: cellArea.containsMouse ? Colors.glassHover : "transparent"

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        spacing: 4

                        Text {
                            text: modelData.label
                            font.family: Theme.fontUi
                            font.weight: Font.Medium
                            font.pixelSize: 11
                            color: modelData.active ? Colors.accentLight : Colors.textMuted
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            visible: modelData.arrow !== ""
                            text: modelData.arrow
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            color: Colors.accentLight
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: cellArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.select(modelData.key)
                    }
                }
            }
        }

        // Sampled rows.
        Flickable {
            width: parent.width
            height: root.height - 28
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentHeight: rowsCol.implicitHeight
            flickableDirection: Flickable.VerticalFlick

            Column {
                id: rowsCol
                width: parent.width

                Repeater {
                    model: root.rows

                    delegate: Rectangle {
                        required property var modelData
                        width: rowsCol.width
                        height: 24
                        color: "transparent"

                        Row {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 24

                            Text {
                                width: parent.width - root.fixedWidth
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name
                                font.family: Theme.fontUi
                                font.pixelSize: 12
                                color: Colors.textSecondary
                            }

                            Text {
                                width: root.pidWidth
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: String(modelData.pid)
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                                color: Colors.textMuted
                            }

                            Text {
                                width: root.valueWidth
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: Number(modelData.cpu).toFixed(1) + "%"
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                                color: modelData.cpu >= 50 ? Colors.warning : Colors.textSecondary
                            }

                            Text {
                                width: root.valueWidth
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: Number(modelData.mem).toFixed(1) + "%"
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                                color: Colors.textSecondary
                            }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: Colors.borderSubtle
                            opacity: 0.5
                        }
                    }
                }
            }
        }
    }

    // Honest empty / first-sample states (PRD 37).
    Comp.EmptyState {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 28
        anchors.bottom: parent.bottom
        visible: root.waiting
        busy: SystemStats.processSerial === 0
        glyph: String.fromCodePoint(0xF120) // fa-terminal
        title: SystemStats.processSerial === 0 ? "Reading processes" : "No process data"
        body: SystemStats.processSerial === 0 ? "Sampling the process table…" : "The process list could not be read on this system."
    }
}
