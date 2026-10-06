import QtQuick
import Quickshell
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — calendar view (PRD 16): locale-aware Gregorian month grid
// with leap-year-correct arithmetic delegated to the JS Date type,
// muted overflow dates, live today highlight, and a local event store
// under ~/.local/share/voidshell/calendar.json. Events are only ever read
// from that store — the panel never invents sample entries.
// Formerly its own popup; now hosted as the Dashboard's Calendar tab
// (the clock pill and the calendar IPC target open the dashboard).
Item {
    id: root

    // Content height for hosts that scroll (the dashboard tab wraps this
    // item in a Flickable).
    implicitHeight: calCol.implicitHeight

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // --- date model ------------------------------------------------------
    readonly property var todayStart: {
        const d = clock.date;
        return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    }
    readonly property int viewYear: viewDate.getFullYear()
    readonly property int viewMonth: viewDate.getMonth()
    property var viewDate: (() => {
        const d = clock.date;
        return new Date(d.getFullYear(), d.getMonth(), 1);
    })()
    property var selectedStart: root.todayStart
    property bool composing: false
    property string draftTitle: ""
    property string draftTime: "12:00"
    property string draftCategory: "accent"

    readonly property string monthLabel: Qt.formatDate(new Date(viewYear, viewMonth, 1), "MMMM yyyy")
    // Day starts (local) that carry events, for the shared month grid.
    readonly property var eventDayTimes: {
        const out = [];
        const list = EventStore.events;
        for (let i = 0; i < list.length; i++) {
            const d = new Date(list[i].start);
            const t = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
            if (out.indexOf(t) === -1) {
                out.push(t);
            }
        }
        return out;
    }
    readonly property var dayEvents: EventStore.eventsOn(selectedStart)
    readonly property bool selectedIsToday: selectedStart === todayStart

    function startOfDay(ms) {
        const d = new Date(ms);
        return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    }

    function shiftMonth(delta) {
        viewDate = new Date(viewYear, viewMonth + delta, 1);
        composing = false;
    }

    function selectDay(time) {
        selectedStart = time;
        composing = false;
    }

    function categoryColor(name) {
        if (name === "gold") {
            return Colors.goldMuted;
        }
        if (name === "success") {
            return Colors.success;
        }
        if (name === "info") {
            return Colors.info;
        }
        return Colors.accentPrimary;
    }

    function timeLabel(ms) {
        return Qt.formatTime(new Date(ms), "HH:mm");
    }

    function eventsForSelected() {
        const list = EventStore.eventsOn(selectedStart);
        return list;
    }

    function saveDraft() {
        const title = draftTitle.trim();
        if (title === "") {
            return;
        }
        const parts = draftTime.split(":");
        let h = parts.length > 0 ? parseInt(parts[0], 10) : 12;
        let m = parts.length > 1 ? parseInt(parts[1], 10) : 0;
        if (isNaN(h) || h < 0 || h > 23) {
            h = 12;
        }
        if (isNaN(m) || m < 0 || m > 59) {
            m = 0;
        }
        const day = new Date(selectedStart);
        const start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), h, m, 0, 0).getTime();
        EventStore.add(title, start, start + 3600000, draftCategory, "");
        draftTitle = "";
        composing = false;
    }

    // Visual host: sizes to the tab that wraps it (no popup window).
    Item {
        id: win
        anchors.fill: parent

        Column {
            id: calCol
            width: parent.width
            spacing: Theme.space8

            // Month / year navigator.
            Item {
                width: parent.width
                height: 32

                Comp.IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    icon: String.fromCodePoint(0xF0141) // md-chevron_left
                    onClicked: root.shiftMonth(-1)
                }

                Text {
                    anchors.centerIn: parent
                    text: root.monthLabel
                    font.family: Theme.fontUi
                    font.weight: Font.DemiBold
                    font.pixelSize: 15
                    color: Colors.textPrimary
                }

                Comp.IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    icon: String.fromCodePoint(0xF0142) // md-chevron_right
                    onClicked: root.shiftMonth(1)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 44
                    text: "Today"
                    font.family: Theme.fontUi
                    font.weight: Font.Medium
                    font.pixelSize: 12
                    color: todayArea.containsMouse ? Colors.accentLight : Colors.textMuted
                    visible: !root.selectedIsToday || root.viewMonth !== new Date(root.todayStart).getMonth()

                    MouseArea {
                        id: todayArea
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.selectedStart = root.todayStart;
                            const d = new Date(root.todayStart);
                            root.viewDate = new Date(d.getFullYear(), d.getMonth(), 1);
                        }
                    }
                }
            }

            // Month grid (shared component with the dashboard overview).
            Comp.MonthGrid {
                width: parent.width
                year: root.viewYear
                month: root.viewMonth
                selected: root.selectedStart
                today: root.todayStart
                eventTimes: root.eventDayTimes
                cellHeight: 34
                onDaySelected: time => root.selectDay(time)
            }

            // Events for the selected day.
            Column {
                width: parent.width
                spacing: Theme.space8

                Item {
                    width: parent.width
                    height: 16

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        text: "EVENTS"
                        font.family: Theme.fontUi
                        font.weight: Font.Medium
                        font.pixelSize: 11
                        font.letterSpacing: 1.5
                        color: Colors.textMuted
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        text: root.dayEvents.length > 0 ? root.dayEvents.length + (root.dayEvents.length === 1 ? " event" : " events") : ""
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                        color: Colors.textDisabled
                        visible: text !== ""
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    text: "No events on this day"
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    color: Colors.textDisabled
                    visible: root.dayEvents.length === 0
                }

                Repeater {
                    model: root.dayEvents

                    Item {
                        required property var modelData
                        width: parent.width
                        height: eventRow.implicitHeight

                        Row {
                            id: eventRow
                            width: parent.width
                            spacing: Theme.space8

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8
                                height: 8
                                radius: 4
                                color: root.categoryColor(modelData.category)
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.timeLabel(modelData.start)
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                                color: Colors.textMuted
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - eventRow.spacing * 2 - 8 - eventTimeWidth - delBtn.width
                                readonly property int eventTimeWidth: 38
                                elide: Text.ElideRight
                                text: modelData.title
                                font.family: Theme.fontUi
                                font.weight: Font.Medium
                                font.pixelSize: 13
                                color: Colors.textPrimary
                            }

                            Item {
                                id: delBtn
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20
                                height: 20

                                Text {
                                    anchors.centerIn: parent
                                    text: String.fromCodePoint(0xF00D) // fa-xmark
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                    color: delArea.containsMouse ? Colors.danger : Colors.textDisabled
                                }

                                MouseArea {
                                    id: delArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: EventStore.remove(modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            // New event composer (functional local store, PRD 16.2).
            Column {
                width: parent.width
                spacing: Theme.space8
                visible: root.composing

                Rectangle {
                    width: parent.width
                    height: 36
                    radius: Theme.radiusSm
                    color: Colors.bgElevated
                    border.width: 1
                    border.color: titleField.activeFocus ? Colors.borderAccent : Colors.borderSubtle

                    TextInput {
                        id: titleField
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space12
                        anchors.rightMargin: Theme.space12
                        verticalAlignment: Text.AlignVCenter
                        clip: true
                        color: Colors.textPrimary
                        selectionColor: Colors.accentStrong
                        selectedTextColor: Colors.textOnAccent
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        text: root.draftTitle
                        onTextEdited: root.draftTitle = text
                        Keys.onReturnPressed: root.saveDraft()
                        Keys.onEnterPressed: root.saveDraft()

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Event title"
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                            color: Colors.textDisabled
                            visible: titleField.text === ""
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: Theme.space8

                    Rectangle {
                        width: 84
                        height: 32
                        radius: Theme.radiusSm
                        color: Colors.bgElevated
                        border.width: 1
                        border.color: timeField.activeFocus ? Colors.borderAccent : Colors.borderSubtle

                        TextInput {
                            id: timeField
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space8
                            verticalAlignment: Text.AlignVCenter
                            color: Colors.textPrimary
                            selectionColor: Colors.accentStrong
                            selectedTextColor: Colors.textOnAccent
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                            text: root.draftTime
                            onTextEdited: root.draftTime = text
                        }
                    }

                    // Category accent picker.
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space8

                        Repeater {
                            model: ["accent", "gold", "success", "info"]

                            Rectangle {
                                required property string modelData
                                width: 18
                                height: 18
                                radius: 9
                                color: root.categoryColor(modelData)
                                border.width: 2
                                border.color: root.draftCategory === modelData ? Colors.textOnAccent : "transparent"

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.draftCategory = modelData
                                }
                            }
                        }
                    }

                    Item {
                        width: parent.width - 84 - Theme.space8 * 2 - 4 * 18 - 3 * 8 - saveBtn.width - Theme.space8
                        height: 1
                    }

                    Comp.TextButton {
                        id: saveBtn
                        anchors.verticalCenter: parent.verticalCenter
                        label: "Save"
                        active: root.draftTitle.trim() !== ""
                        enabled: root.draftTitle.trim() !== ""
                        opacity: enabled ? 1.0 : 0.5
                        onClicked: root.saveDraft()
                    }
                }
            }

            Comp.TextButton {
                width: parent.width
                label: root.composing ? "Cancel" : "+ New Event"
                active: root.composing
                onClicked: {
                    root.composing = !root.composing;
                    if (root.composing) {
                        root.draftTitle = "";
                        titleField.forceActiveFocus();
                    }
                }
            }
        }
    }
}
