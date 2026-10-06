import QtQuick
import Quickshell
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — dashboard Productivity tab (PRD 22.5): tasks + focus.
// Tasks persist through TaskStore (tasks.json); the focus timer lives in
// FocusTimer, a singleton, so a session keeps counting while the
// dashboard is closed or the panel is switched.
Item {
    id: root

    property string submode: "tasks" // tasks | focus
    property bool showCompleted: false
    property string draft: ""

    // ---------------- tasks ----------------
    function addDraft() {
        const t = draft.trim();
        if (t === "") {
            return;
        }
        TaskStore.add(t);
        draft = "";
    }

    // ---------------- focus ----------------
    readonly property real ringProgress: FocusTimer.progress

    Column {
        anchors.fill: parent
        spacing: Theme.space12

        // Segmented switch between the two submodes.
        Item {
            width: parent.width
            height: 30

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space4

                SegButton {
                    label: "Tasks"
                    active: root.submode === "tasks"
                    onClicked: root.submode = "tasks"
                }

                SegButton {
                    label: "Focus"
                    active: root.submode === "focus"
                    onClicked: root.submode = "focus"
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                text: root.submode === "tasks" ? TaskStore.activeCount + " active · " + TaskStore.doneCount + " done" : FocusTimer.sessionLabel
                font.family: Theme.fontUi
                font.pixelSize: 12
                color: Colors.textMuted
            }
        }

        // ------- tasks view -------
        Column {
            width: parent.width
            spacing: Theme.space8
            visible: root.submode === "tasks"

            Row {
                width: parent.width
                spacing: Theme.space8

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - addBtn.width - Theme.space8
                    height: 36
                    radius: Theme.radiusSm
                    color: Colors.bgElevated
                    border.width: 1
                    border.color: taskField.activeFocus ? Colors.borderAccent : Colors.borderSubtle

                    TextInput {
                        id: taskField
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
                        text: root.draft
                        onTextEdited: root.draft = text
                        Keys.onReturnPressed: root.addDraft()
                        Keys.onEnterPressed: root.addDraft()

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Add a task and press Enter"
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                            color: Colors.textDisabled
                            visible: taskField.text === ""
                        }
                    }
                }

                Comp.TextButton {
                    id: addBtn
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Add"
                    enabled: root.draft.trim() !== ""
                    opacity: enabled ? 1.0 : 0.5
                    onClicked: root.addDraft()
                }
            }

            // Active / Completed segmented switch.
            Row {
                width: parent.width
                spacing: Theme.space4

                SegButton {
                    label: "Active (" + TaskStore.activeCount + ")"
                    active: !root.showCompleted
                    onClicked: root.showCompleted = false
                }

                SegButton {
                    label: "Completed (" + TaskStore.doneCount + ")"
                    active: root.showCompleted
                    onClicked: root.showCompleted = true
                }

                Item {
                    width: 4
                    height: 1
                }

                Comp.TextButton {
                    label: "Clear completed"
                    visible: root.showCompleted && TaskStore.doneCount > 0
                    onClicked: TaskStore.clearCompleted()
                }
            }

            Flickable {
                width: parent.width
                height: root.height - 150
                clip: true
                contentHeight: taskList.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: taskList
                    width: parent.width
                    spacing: Theme.space4

                    Repeater {
                        model: root.visibleTasks()

                        TaskRow {
                            width: taskList.width
                            required property var modelData
                            task: modelData
                        }
                    }

                    Comp.EmptyState {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        glyph: String.fromCodePoint(0xF012C) // md-check
                        title: root.showCompleted ? "Nothing completed yet" : "No active tasks"
                        body: root.showCompleted ? "Tasks you finish land here." : "Add your first task above; it is saved to disk immediately."
                        // Empty-state visibility must not read the Column's
                        // own implicitHeight: that creates a polish loop
                        // (height -> visible -> height) when the list is
                        // empty. Bind to the source list instead.
                        visible: root.visibleTasks().length === 0
                    }
                }
            }
        }

        // ------- focus view -------
        Column {
            width: parent.width
            spacing: Theme.space16
            visible: root.submode === "focus"

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.space4

                SegButton {
                    label: "Focus"
                    active: FocusTimer.mode === "focus"
                    onClicked: FocusTimer.setMode("focus")
                }

                SegButton {
                    label: "Break"
                    active: FocusTimer.mode === "break"
                    onClicked: FocusTimer.setMode("break")
                }
            }

            // Circular timer.
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 220
                height: 220

                Canvas {
                    id: ring
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const cx = width / 2;
                        const cy = height / 2;
                        const r = Math.min(width, height) / 2 - 14;
                        ctx.lineWidth = 10;
                        ctx.lineCap = "round";
                        ctx.strokeStyle = String(ThemeService.light ? Colors.parchmentMuted : Colors.indigo);
                        ctx.beginPath();
                        ctx.arc(cx, cy, r, 0, Math.PI * 2);
                        ctx.stroke();
                        ctx.strokeStyle = FocusTimer.mode === "focus" ? String(Colors.accentPrimary) : String(Colors.success);
                        ctx.beginPath();
                        ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * root.ringProgress);
                        ctx.stroke();
                    }

                    Connections {
                        target: FocusTimer
                        function onProgressChanged() {
                            ring.requestPaint();
                        }
                        function onModeChanged() {
                            ring.requestPaint();
                        }
                    }

                    // Repaint when the theme (preset / mode / wallpaper
                    // tone) moves — Canvas pixels are cached across
                    // token changes.
                    Connections {
                        target: ThemeService
                        function onRevisionChanged() {
                            ring.requestPaint();
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 2

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: FocusTimer.remainingLabel
                        font.family: Theme.fontMono
                        font.weight: Font.DemiBold
                        font.pixelSize: 42
                        color: Colors.textPrimary
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: FocusTimer.modeLabel + " · " + (FocusTimer.mode === "focus" ? FocusTimer.focusMinutes + " min" : FocusTimer.breakMinutes + " min")
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        color: Colors.textMuted
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: FocusTimer.running ? "Running" : "Paused"
                        font.family: Theme.fontUi
                        font.weight: Font.Medium
                        font.pixelSize: 11
                        color: FocusTimer.running ? Colors.success : Colors.textDisabled
                    }
                }
            }

            // Duration adjust + transport.
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.space12

                StepBtn {
                    label: "−"
                    enabled: !FocusTimer.running
                    onClicked: FocusTimer.mode === "focus" ? FocusTimer.adjustFocus(-5) : FocusTimer.adjustBreak(-1)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (FocusTimer.mode === "focus" ? FocusTimer.focusMinutes : FocusTimer.breakMinutes) + " min"
                    font.family: Theme.fontUi
                    font.weight: Font.Medium
    font.pixelSize: 14
                    color: Colors.textSecondary
                    width: 62
                    horizontalAlignment: Text.AlignHCenter
                }

                StepBtn {
                    label: "+"
                    enabled: !FocusTimer.running
                    onClicked: FocusTimer.mode === "focus" ? FocusTimer.adjustFocus(5) : FocusTimer.adjustBreak(1)
                }

                Comp.TextButton {
                    anchors.verticalCenter: parent.verticalCenter
                    label: FocusTimer.running ? "Pause" : (FocusTimer.remaining === FocusTimer.totalSeconds ? "Start" : "Resume")
                    active: FocusTimer.running
                    onClicked: FocusTimer.toggleRunning()
                }

                Comp.TextButton {
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Reset"
                    onClicked: FocusTimer.reset()
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: FocusTimer.completedSessions + " focus session(s) completed this session"
                font.family: Theme.fontUi
                font.pixelSize: 12
                color: Colors.textMuted
            }
        }
    }

    function visibleTasks() {
        const out = [];
        const list = TaskStore.tasks;
        for (let i = 0; i < list.length; i++) {
            if (root.showCompleted ? list[i].done : !list[i].done) {
                out.push(list[i]);
            }
        }
        return out;
    }

    component SegButton: Rectangle {
        id: seg
        property string label: ""
        property bool active: false
        signal clicked
        width: segLabel.implicitWidth + Theme.space24
        height: 30
        radius: Theme.radiusSm
        color: active ? Colors.accentStrong : (segArea.containsMouse ? Colors.glassHover : Colors.glassCard)
        border.width: 1
        border.color: active ? Colors.borderAccent : (segArea.containsMouse ? Colors.borderGlass : Colors.borderSubtle)

        Text {
            id: segLabel
            anchors.centerIn: parent
            text: seg.label
            font.family: Theme.fontUi
            font.weight: Font.DemiBold
            font.pixelSize: 12
            color: active ? Colors.textOnAccent : Colors.textSecondary
        }

        MouseArea {
            id: segArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: seg.clicked()
        }
    }

    component StepBtn: Rectangle {
        id: step
        property string label: ""
        signal clicked
        width: 34
        height: 34
        radius: Theme.radiusSm
        opacity: enabled ? 1.0 : 0.4
        color: stepArea.containsMouse && enabled ? Colors.glassHover : Colors.glassCard
        border.width: 1
        border.color: stepArea.containsMouse && enabled ? Colors.borderGlass : Colors.borderSubtle

        Text {
            anchors.centerIn: parent
            text: step.label
            font.family: Theme.fontUi
            font.weight: Font.DemiBold
            font.pixelSize: 18
            color: Colors.textPrimary
        }

        MouseArea {
            id: stepArea
            anchors.fill: parent
            enabled: step.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: step.clicked()
        }
    }

    component TaskRow: Item {
        id: row
        property var task: null
        height: 40

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusSm
            color: row.hover ? Colors.glassHover : Colors.glassCard
            border.width: 1
            border.color: Colors.borderSubtle
        }

        property bool hover: rowArea.containsMouse

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Theme.space12
            width: 20
            height: 20
            radius: 10
            color: row.task && row.task.done ? Colors.accentStrong : "transparent"
            border.width: 1.5
            border.color: row.task && row.task.done ? Colors.borderAccent : Colors.textDisabled

            Text {
                anchors.centerIn: parent
                text: String.fromCodePoint(0xF00C) // md-check
                font.family: Theme.fontMono
                font.pixelSize: 11
                color: Colors.textOnAccent
                visible: row.task !== null && row.task.done
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (row.task) {
                        TaskStore.toggle(row.task.id);
                    }
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Theme.space12 + 30
            width: parent.width - (Theme.space12 + 30) - Theme.space12 - 28
            elide: Text.ElideRight
            text: row.task ? row.task.title : ""
            font.family: Theme.fontUi
            font.pixelSize: 13
            color: row.task && row.task.done ? Colors.textDisabled : Colors.textPrimary
            font.strikeout: row.task !== null && row.task.done
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: Theme.space12
            text: String.fromCodePoint(0xF00D) // fa-xmark
            font.family: Theme.fontMono
            font.pixelSize: 12
            color: delArea.containsMouse ? Colors.danger : Colors.textDisabled

            MouseArea {
                id: delArea
                anchors.fill: parent
                anchors.margins: -8
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (row.task) {
                        TaskStore.remove(row.task.id);
                    }
                }
            }
        }

        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }
    }
}
