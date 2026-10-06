import QtQuick
import ".."

// VOID SHELL — Gregorian month grid shared by the calendar panel and the
// dashboard overview (PRD 16, 22.1).
// Month arithmetic is delegated to the JS Date type, which is proleptic
// Gregorian, so leap years are always correct; overflow dates from the
// adjacent months render muted; week start follows the system locale.
// Event markers are supplied by the caller — this component never
// invents entries.
Item {
    id: root

    property int year: 2026
    property int month: 0
    property var selected: 0
    property var today: 0
    property var eventTimes: []
    property bool interactive: true
    property int cellHeight: 34
    signal daySelected(var time)

    readonly property int firstDay: {
        const d = Qt.locale().firstDayOfWeek;
        // Qt: Monday=1..Sunday=7; JS Date: Sunday=0..Saturday=6.
        return typeof d === "number" && d >= 1 && d <= 7 ? d % 7 : 0;
    }
    readonly property var cells: buildCells(root.year, root.month, root.firstDay)
    readonly property var weekdayLabels: {
        const names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        const out = [];
        for (let i = 0; i < 7; i++) {
            out.push(names[(root.firstDay + i) % 7]);
        }
        return out;
    }

    implicitWidth: 294
    implicitHeight: weekdayRow.height + gridCol.implicitHeight + Theme.space4

    // 42 cells (6 weeks). new Date(y, m, day) normalizes overflow, which
    // is exactly the Gregorian behaviour needed for 28/29/30/31-day months.
    function buildCells(year, month, firstDay) {
        const first = new Date(year, month, 1);
        const offset = (first.getDay() - firstDay + 7) % 7;
        const start = new Date(year, month, 1 - offset);
        const out = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
            out.push({
                day: d.getDate(),
                inMonth: d.getMonth() === month,
                time: new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
            });
        }
        return out;
    }

    function hasEvent(time) {
        return root.eventTimes.indexOf(time) !== -1;
    }

    Column {
        id: gridCol
        width: parent ? parent.width : root.implicitWidth
        spacing: 2

        Row {
            id: weekdayRow
            width: gridCol.width

            Repeater {
                model: root.weekdayLabels

                Text {
                    required property string modelData
                    width: weekdayRow.width / 7
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    font.family: Theme.fontUi
                    font.weight: Font.Medium
                    font.pixelSize: 10
                    font.letterSpacing: 0.6
                    color: Colors.textMuted
                }
            }
        }

        Repeater {
            model: 6

            Row {
                id: weekRow
                required property int index
                width: gridCol.width

                Repeater {
                    model: 7

                    Item {
                        id: cell
                        required property int index
                        readonly property int cellIndex: weekRow.index * 7 + index
                        readonly property var info: root.cells[cellIndex]
                        readonly property bool isToday: info.time === root.today
                        readonly property bool isSelected: info.time === root.selected
                        readonly property bool hasEvent: root.hasEvent(info.time)
                        width: parent.width / 7
                        height: root.cellHeight

                        Rectangle {
                            anchors.centerIn: parent
                            width: root.cellHeight - 6
                            height: root.cellHeight - 6
                            radius: Theme.radiusXs
                            color: cell.isSelected ? Colors.accentStrong : (cell.isToday ? Colors.glassHover : "transparent")
                            border.width: 1
                            border.color: cell.isSelected ? Colors.borderAccent : "transparent"

                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.durationNormal
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: cell.hasEvent ? -3 : 0
                            text: cell.info.day
                            font.family: Theme.fontUi
                            font.weight: cell.isSelected || cell.isToday ? Font.DemiBold : Font.Normal
                            font.pixelSize: root.cellHeight > 30 ? 13 : 11
                            color: {
                                if (!cell.info.inMonth) {
                                    return Colors.textDisabled;
                                }
                                if (cell.isSelected) {
                                    return Colors.textOnAccent;
                                }
                                if (cell.isToday) {
                                    return Colors.accentLight;
                                }
                                return Colors.textSecondary;
                            }
                        }

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 3
                            width: 4
                            height: 4
                            radius: 2
                            color: cell.isSelected ? Colors.textOnAccent : Colors.accentLight
                            visible: cell.hasEvent
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.interactive
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.daySelected(cell.info.time)
                        }
                    }
                }
            }
        }
    }
}
