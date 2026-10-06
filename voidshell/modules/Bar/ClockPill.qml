import Quickshell
import QtQuick
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — clock/date pill (center focus): live time over secondary
// date line, locale-aware. Click opens the dashboard.
//
// LIVING STATE ISLAND (MASTER PROMPT §5) — the renderer for the island's
// three in-pill presentation states. The allocation is fixed: 170 ×
// Theme.barHeight, exactly as before, asserted by scripts/coord-check.sh.
// Nothing here ever resizes, moves or re-anchors the pill — states only
// swap what is painted inside the same rectangle.
//
// CONTENT INSET — SlantedPill routes every declared child into its
// contentItem, which is already inset by slantDepth(16) + contentPad(14)
// = 30px on each side (170 - 60 = 110, i.e. root.contentWidth). Children
// must therefore never add side padding of their own: an extra leftMargin
// here shifted the whole column 30px right (empty left gap, content
// crowding the right slant) instead of centring it in the pill.
//
//   A idle     time over date (unchanged look)
//   B ambient  time over the one compact ambient indicator (activity,
//              DND or warning), with the verified privacy badge in its
//              own reserved region so no content can cover it
//   C event    the presented announcement (title over what it is)
//   T timer    the live countdown (exact remaining time over what is
//              counting down) while a timer or focus session runs
//   G locked   nothing — the lock surface owns the screen
//
// The workspace announcement (Shadow Spaces §18) keeps its original
// dwell renderer and its original double gate: the manager setting and
// the Island's per-feature policy must both allow it.
Comp.SlantedPill {
    id: root
    property var shellScreen: null
    width: 170
    height: Theme.barHeight
    mirrored: true
    fillColor: Colors.glassElevated
    borderColor: Colors.borderGlass
    active: true
    glowEnabled: true

    // Seconds only tick when the user asked for them (§21 showSeconds):
    // an idle shell stays on the minute clock it always had.
    SystemClock {
        id: clock
        precision: IslandSettings.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    // True while the workspace announcement is being shown (set on the
    // event, cleared by the dwell below).
    property bool announcing: false

    Timer {
        id: annDwell
        interval: 2400
        repeat: false
        onTriggered: root.announcing = false
    }

    Connections {
        target: HyprlandService
        function onAnnouncementSerialChanged() {
            const allowed = ManagerSettings.islandAnnouncements && IslandSettings.featureOn("workspace");
            if (allowed && HyprlandService.announcement !== "") {
                root.announcing = true;
                annDwell.restart();
            } else {
                root.announcing = false;
            }
        }
    }

    // Presentation state actually drawn right now (A/B/C/T/G). The
    // workspace dwell outranks the island states — it was here first and
    // its own setting is independent of the island's feature flags.
    readonly property string islandState: {
        if (root.announcing) {
            return "workspace";
        }
        // Locked (state G): the island features stand down and the pill
        // falls back to the plain clock — the lock surface owns the
        // screen, nothing is announced and no ambient line is shown.
        if (IslandController.clockState === "event") {
            return "event";
        }
        // A running countdown outranks the ambient line: it is the only
        // state that changes every second, so it stays exact instead of
        // sharing the second line with an unrelated indicator.
        if (IslandController.liveCountdown !== null) {
            return "timer";
        }
        if (IslandController.clockState === "ambient") {
            return "ambient";
        }
        return "idle";
    }

    // --- reserved privacy region (§5 B) ---------------------------------
    // Verified capture state gets a fixed corner of the pill; content is
    // laid out in what is left, so a media badge or a long event title
    // can never push the badge out or hide behind it.
    readonly property bool privacyVisible: IslandController.privacyActive && root.islandState !== "hidden"
    readonly property int privacyWidth: privacyVisible ? 34 : 0
    readonly property int contentWidth: 110 - privacyWidth

    // Time formatting respects the seconds setting without a second
    // renderer: the minute clock drives state, the seconds clock is only
    // read while showSeconds is on.
    function timeText() {
        return Qt.formatTime(clock.date, IslandSettings.showSeconds ? "hh:mm:ss" : "hh:mm");
    }

    // The clock/ambient column (states A and B share the same shape —
    // only the second line changes, so the island never jumps).
    Column {
        id: baseColumn
        width: root.contentWidth
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        opacity: (root.islandState === "idle" || root.islandState === "ambient") ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: IslandSettings.durationCrossfade
                easing.type: Easing.OutCubic
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.timeText()
            font.family: Theme.fontUi
            font.weight: Font.DemiBold
            font.pixelSize: 19
            color: Colors.textPrimary
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            // State B shows the one ambient indicator; state A keeps the
            // locale date exactly as before. The ambient label is empty
            // in state B only when a verified capture is active, in which
            // case the date is the honest fallback (the badge carries the
            // capture state in its own region).
            text: IslandController.ambientLabel !== ""
                ? IslandController.ambientLabel
                : Qt.formatDate(clock.date, "ddd MMM d")
            font.family: Theme.fontUi
            font.pixelSize: 11
            color: root.islandState === "ambient" ? Colors.textSecondary : Colors.textMuted
        }
    }

    // The event (state C): same two-line shape, so nothing moves.
    Column {
        id: eventColumn
        width: root.contentWidth
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        opacity: root.islandState === "event" ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: IslandSettings.durationCrossfade
                easing.type: Easing.OutCubic
            }
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: IslandController.announcement === null ? "" : IslandController.announcement.title
            font.family: Theme.fontUi
            font.weight: Font.DemiBold
            font.pixelSize: 14
            color: Colors.textPrimary
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: {
                const ev = IslandController.announcement;
                if (ev === null) {
                    return "";
                }
                return ev.subtitle !== "" ? ev.subtitle : (ev.icon > 0 ? String.fromCodePoint(ev.icon) : "");
            }
            font.family: evIcon ? Theme.fontMono : Theme.fontUi
            font.pixelSize: 11
            color: Colors.textMuted
            // Icon-only second line when there is no subtitle: a glyph in
            // the mono font beats an empty line.
            readonly property bool evIcon: IslandController.announcement !== null && IslandController.announcement.subtitle === "" && IslandController.announcement.icon > 0
        }
    }

    // Workspace announcement (pre-island behaviour, unchanged shape).
    Column {
        id: wsColumn
        width: root.contentWidth
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        opacity: root.islandState === "workspace" ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: ManagerSettings.durationFade
                easing.type: Easing.OutCubic
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: HyprlandService.announcement
            font.family: Theme.fontMono
            font.weight: Font.DemiBold
            font.pixelSize: 19
            color: Colors.accentStrong
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "workspace"
            font.family: Theme.fontUi
            font.pixelSize: 11
            color: Colors.textMuted
        }
    }

    // Live countdown (state T): same two-line shape, but this is the one
    // state that repaints every second. Both lines are bounded by the
    // content box (width + AlignHCenter + elide), so a long timer name
    // or an hours-long countdown can never reach the privacy region or
    // the slant — the countdown itself is padded by TimerStore.fmt, so
    // the layout never twitches as a digit rolls over.
    Column {
        id: timerColumn
        width: root.contentWidth
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        opacity: root.islandState === "timer" ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: IslandSettings.durationCrossfade
                easing.type: Easing.OutCubic
            }
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: IslandController.countdownText
            font.family: Theme.fontMono
            font.weight: Font.DemiBold
            font.pixelSize: 19
            color: Colors.accentStrong
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: IslandController.countdownName
            font.family: Theme.fontUi
            font.pixelSize: 11
            color: Colors.textMuted
        }
    }

    // --- privacy badge (its own region, never covered) -------------------
    Rectangle {
        id: privacyBadge
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.privacyWidth
        height: 20
        radius: 6
        visible: root.privacyVisible
        color: Colors.dangerDeep
        border.width: 1
        border.color: Colors.borderAccent

        Text {
            anchors.centerIn: parent
            text: IslandController.privacyLabel
            font.family: Theme.fontMono
            font.weight: Font.Bold
            font.pixelSize: 9
            color: Colors.textOnAccent
        }
    }

    MouseArea {
        id: primaryArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true

        onEntered: IslandController.hoverEntered(root.shellScreen, root)
        onExited: IslandController.hoverLeft()

        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                // Right-click opens the activity stack (§5 state E).
                IslandController.openStack(root.shellScreen, root);
            } else if (mouse.button === Qt.MiddleButton) {
                IslandController.close();
            } else {
                // Left click: Dashboard, its Overview home tab (§3).
                IslandController.close();
                IslandRouter.goOverview(root.shellScreen, root);
            }
        }
    }

    // Suppress hover previews while a pointer button is down over the
    // pill: dragging out of the pill must not leave a surface open.
    onPressedChanged: {
        if (pressed) {
            IslandController.hoverLeft();
        }
    }
}
