import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — Living State Island surface (MASTER PROMPT §5 D/E).
//
// The only expanding Island surface: a panel anchored directly below the
// clock, on its own layer namespace (`voidshell-island`), that shows
// either one activity's contextual card (state D) or the activity stack
// (state E). It is never counted as a second bar island — it reserves
// nothing (`exclusiveZone: -1`) and never pushes the bar or a window.
//
// Surface ownership stays with PopupManager (one primary surface at a
// time): `visible` is derived, this file keeps no open/closed state of
// its own. Opening a popup closes the Island and opening the Island
// closes conflicting popups, from the single state machine.
//
// The panel appears directly under the clock's column: both are centered
// on the output, so an unanchored (centered) layer surface with the bar's
// own top margin lines up with the pill without hard-coding x.
Scope {
    id: root

    // Which block of the stack is showing (§5 E keeps the stack one
    // surface with a segmented body, never five popups).
    //   acts | ctrl | timers | presets | clip
    // The selection itself lives on IslandController so the IPC surface
    // and the gates can drive it without reaching into this file.
    readonly property string stackSection: IslandController.stackSection

    // Rows the stack shows — pinned first, then most recently updated
    // (derived in ActivityStore, frozen while the pointer is inside).
    readonly property var rows: ActivityStore.stack
    readonly property bool isContext: PopupManager.islandMode === "context"
    readonly property var contextActivity: {
        if (!root.isContext) {
            return null;
        }
        if (IslandController.contextKind === "activity") {
            return ActivityStore.byId(IslandController.contextKey);
        }
        return null;
    }

    readonly property var sections: [
        { id: "acts", label: "Activities", feature: "jobs", hint: "" },
        { id: "ctrl", label: "Controls", feature: "volume", hint: "Toggles and levels" },
        { id: "timers", label: "Timers", feature: "timers", hint: "Countdowns and stopwatch" },
        { id: "presets", label: "Presets", feature: "presets", hint: "Saved arrangements" },
        { id: "clip", label: "Clipboard", feature: "clipboard", hint: "Recent copies" }
    ]

    readonly property var currentSection: {
        for (let i = 0; i < root.sections.length; i++) {
            if (root.sections[i].id === root.stackSection) {
                return root.sections[i];
            }
        }
        return root.sections[0];
    }

    // The clipboard block re-reads the history each time it is opened
    // (cliphist is only consulted on demand — never polled).
    onStackSectionChanged: {
        if (stackSection === "clip") {
            ClipboardService.refresh();
        }
    }

    PanelWindow {
        id: win

        visible: PopupManager.islandOpen && IslandSettings.enabled
        color: "transparent"
        screen: PopupManager.islandScreen !== null ? PopupManager.islandScreen : PopupManager.fallbackScreen
        exclusiveZone: -1

        // Centered horizontally (no left/right anchor) and hung from the
        // bar's own top margin + bar height + the standard gap, so the
        // panel sits immediately below the clock on any output scale.
        anchors {
            top: true
        }
        margins {
            top: Theme.topMargin + Theme.barHeight + Theme.space8
        }

        implicitWidth: panelW + Theme.space16
        implicitHeight: panel.implicitHeight + Theme.space16

        WlrLayershell.namespace: "voidshell-island"
        // Interactive states take the keyboard (Escape must reach the
        // surface); the read-only hover preview never steals focus from
        // the application the user is working in.
        WlrLayershell.keyboardFocus: IslandController.hoverPreviewActive
            ? WlrKeyboardFocus.None
            : WlrKeyboardFocus.Exclusive
        // Ignore the bar's exclusive zone: the panel is already below it.
        WlrLayershell.layer: WlrLayer.Overlay

        readonly property int panelW: 420
        // The stack is capped to a screen-relative height; longer
        // content scrolls inside the panel instead of growing a layer
        // surface past the output.
        readonly property int maxBodyH: Math.max(220, Math.min(560, Math.round((screen ? screen.height : 720) * 0.62)))

        Shortcut {
            enabled: win.visible
            context: Qt.ApplicationShortcut
            sequences: [StandardKey.Cancel]
            onActivated: IslandController.handleEscape()
        }

        // Claim focus while mapped so Escape and arrow keys work.
        Item {
            id: grab
            anchors.fill: parent
            focus: win.visible
        }

        onVisibleChanged: {
            if (visible) {
                grab.forceActiveFocus();
                IslandController.beginInteraction();
            } else {
                IslandController.endInteraction();
            }
        }

        Comp.GlassPanel {
            id: panel
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: Theme.space8
            width: win.panelW
            implicitHeight: scroller.height + Theme.space12 * 2

            Flickable {
                id: scroller
                width: parent.width
                height: Math.min(body.implicitHeight, win.maxBodyH)
                contentWidth: width
                contentHeight: body.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                // Wheel scrolling only (no drag: a drag would fight the
                // row click targets inside the stack).
                interactive: body.implicitHeight > height

                Column {
                    id: body
                    width: scroller.width
                    spacing: Theme.space8

                    Comp.PopupHeader {
                        id: header
                        width: parent.width
                        // The header names what is on screen: the contextual
                        // card in state D, the selected block in state E.
                        title: root.isContext
                            ? (root.contextActivity !== null ? root.contextActivity.title : "Activity")
                            : root.currentSection.label
                        subtitle: root.isContext
                            ? (root.contextActivity !== null ? root.contextActivity.subtitle : "")
                            : (root.stackSection === "acts"
                                ? (ActivityStore.activeCount > 0
                                    ? ActivityStore.activeCount + " ongoing · " + ActivityStore.historyCount + " finished"
                                    : "Nothing running")
                                : root.currentSection.hint)
                        onClosed: IslandController.close()
                    }

                    // --- state E: activity stack -----------------------------
                    Column {
                        width: parent.width
                        spacing: Theme.space8
                        visible: !root.isContext

                        // Segmented block switcher (only blocks whose feature
                        // is on are offered; an unavailable provider still
                        // renders its block, honestly disabled).
                        Flow {
                            width: parent.width
                            spacing: Theme.space4

                            Repeater {
                                model: root.sections
                                delegate: Rectangle {
                                    required property var modelData
                                    visible: IslandSettings.featureOn(modelData.feature)
                                    width: segLabel.implicitWidth + Theme.space16
                                    height: 26
                                    radius: 13
                                    color: root.stackSection === modelData.id ? Colors.accentStrong : (segArea.containsMouse ? Colors.glassHover : Colors.glassCard)
                                    border.width: 1
                                    border.color: root.stackSection === modelData.id ? Colors.borderAccent : Colors.borderSubtle

                                    Text {
                                        id: segLabel
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        font.family: Theme.fontUi
                                        font.weight: Font.Medium
                                        font.pixelSize: 11
                                        color: root.stackSection === modelData.id ? Colors.textOnAccent : Colors.textSecondary
                                    }

                                    MouseArea {
                                        id: segArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: IslandController.setSection(modelData.id)
                                    }
                                }
                            }
                        }

                        // --- activities ------------------------------------
                        Column {
                            width: parent.width
                            spacing: Theme.space8
                            visible: root.stackSection === "acts"

                            Comp.EmptyState {
                                width: parent.width
                                visible: root.rows.length === 0
                                glyph: String.fromCodePoint(0xF017) // md-clock
                                title: "No activities"
                                body: "Timers, jobs and recordings appear here while they run."
                            }

                            Repeater {
                                model: root.rows
                                delegate: ActivityRow {
                                    required property var modelData
                                    width: parent.width
                                    activity: modelData
                                    expanded: modelData.key === IslandController.contextKey && root.isContext
                                    onOpenRequested: IslandController.openContext("activity", modelData.key, win.screen, win)
                                }
                            }
                        }

                        // --- controls / timers / presets / clipboard --------
                        ControlsSection {
                            width: parent.width
                            visible: root.stackSection === "ctrl"
                        }

                        TimersSection {
                            width: parent.width
                            visible: root.stackSection === "timers"
                        }

                        PresetsSection {
                            width: parent.width
                            visible: root.stackSection === "presets"
                        }

                        ClipboardSection {
                            width: parent.width
                            visible: root.stackSection === "clip"
                        }
                    }

                    // --- state D: one activity's contextual card --------------
                    ContextCard {
                        width: parent.width
                        visible: root.isContext
                        activity: root.contextActivity
                    }
                }   // body column
            }   // scroller
        }   // glass panel
    }   // panel window
}
