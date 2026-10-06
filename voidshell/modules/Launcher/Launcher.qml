import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — glassmorphism app drawer, redesigned after the
// "Neon Purple Glassmorphism App Launcher" reference: a large centered
// panel — search capsule with a real Ctrl+K keycap, sidebar sections
// (all / favorites / recent / desktop categories), a 4-column app grid,
// a detail panel with real actions, and a recent-apps strip along the
// bottom. Typing `@` swaps the grid for launcher commands (PRD §19.2);
// plugin commands open an in-launcher plugin view. PopupManager owns
// open/close/Escape; open and close play the 180ms scale+fade.
Scope {
    id: root

    readonly property bool pluginMode: LauncherModel.activePlugin !== ""
    readonly property bool appMode: !LauncherModel.commandMode && !root.pluginMode
    // Grid keyboard walk: arrows move by row inside the app grid.
    readonly property bool gridNav: root.appMode

    readonly property string pluginSource: {
        const id = LauncherModel.activePlugin;
        if (id === "git") return "plugins/GitPlugin.qml";
        if (id === "containers") return "plugins/ContainerPlugin.qml";
        if (id === "theme") return "plugins/ThemePlugin.qml";
        if (id === "wallpaper") return "plugins/WallpaperPlugin.qml";
        return "";
    }

    // --- popup geometry (logical px) --------------------------------------
    readonly property int panelW: 1160
    readonly property int panelH: 600
    readonly property int shadowPad: 28    // window gutter: shadow + blur ring
    readonly property int pad: Theme.space20

    readonly property int contentW: root.panelW - root.pad * 2     // 1120
    readonly property int contentH: root.panelH - root.pad * 2     // 560
    readonly property int searchH: 46

    readonly property int sideW: 230
    readonly property int detailW: 264
    readonly property int colGap: Theme.space16
    readonly property int centerW: root.contentW - root.sideW - root.detailW - root.colGap * 2
    readonly property int gridColumns: 4
    readonly property int stripH: 84

    // Escape inside a plugin returns to the command list; a second
    // Escape closes the launcher (PRD §19.1).
    function handleEscape() {
        if (root.pluginMode) {
            LauncherModel.clearPlugin();
            return;
        }
        PopupManager.handleEscape();
    }

    // One key router for the search field and the focus fallback: any
    // item that holds keyboard focus inside this window feeds it.
    function handleKey(event) {
        const k = event.key;
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;

        if (k === Qt.Key_Escape) {
            root.handleEscape();
            event.accepted = true;
            return;
        }
        if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            if (ctrl) {
                root.terminalSelected();
            } else {
                root.activateAndMaybeClose();
            }
            event.accepted = true;
            return;
        }
        if (k === Qt.Key_Up || k === Qt.Key_Down) {
            const dir = k === Qt.Key_Up ? -1 : 1;
            LauncherModel.moveSelection(root.gridNav ? dir * root.gridColumns : dir);
            event.accepted = true;
            return;
        }
        if (k === Qt.Key_Left || k === Qt.Key_Right) {
            // Left/Right walk tiles in app mode even while the field is
            // focused (launcher convention); command/plugin modes keep
            // them as caret keys inside the field.
            if (root.gridNav) {
                LauncherModel.moveSelection(k === Qt.Key_Left ? -1 : 1);
                event.accepted = true;
            }
            return;
        }
        if (ctrl) {
            if (k === Qt.Key_K) {
                searchField.forceActiveFocus();
                searchField.selectAll();
                event.accepted = true;
                return;
            }
            if (k === Qt.Key_D) {
                root.toggleFavoriteSelected();
                event.accepted = true;
                return;
            }
            if (k === Qt.Key_O) {
                root.locationSelected();
                event.accepted = true;
                return;
            }
        }
    }

    // Enter / click: launch apps and dispatch commands, but only close
    // when the activation did not open a plugin view.
    function activateAndMaybeClose() {
        if (LauncherModel.selectedIndex < 0) {
            return;
        }
        LauncherModel.activateSelected();
        if (!root.pluginMode) {
            PopupManager.closeAll();
        }
    }

    function launchEntry(entry) {
        if (!entry) {
            return;
        }
        LauncherModel.launchApp(entry);
        PopupManager.closeAll();
    }

    function terminalSelected() {
        const e = LauncherModel.selectedEntry;
        if (e && LauncherModel.launchInTerminal(e)) {
            PopupManager.closeAll();
        }
    }

    function locationSelected() {
        const e = LauncherModel.selectedEntry;
        if (e) {
            LauncherModel.openEntryLocation(e);
            PopupManager.closeAll();
        }
    }

    function toggleFavoriteSelected() {
        LauncherModel.toggleFavorite(LauncherModel.selectedEntry);
    }

    function uninstallSelected() {
        // Async package lookup; the model closes the launcher itself
        // once a terminal is about to ask for the sudo password.
        LauncherModel.uninstallEntry(LauncherModel.selectedEntry);
    }

    // Keep the keyboard selection inside the scroll area: both the app
    // grid and the command list scroll their selection into view.
    function ensureSelectionVisible() {
        const idx = LauncherModel.selectedIndex;
        if (idx < 0 || root.pluginMode) {
            return;
        }
        let item = null;
        if (LauncherModel.commandMode) {
            item = commandRepeater.itemAt(idx);
        } else {
            item = appRepeater.itemAt(idx);
        }
        if (!item) {
            return;
        }
        const top = item.mapToItem(centerCol, 0, 0).y;
        const bottom = top + item.height;
        const view = centerFlick.height;
        if (top < centerFlick.contentY) {
            centerFlick.contentY = Math.max(0, top - Theme.space8);
        } else if (bottom > centerFlick.contentY + view) {
            const maxY = Math.max(0, centerFlick.contentHeight - view);
            centerFlick.contentY = Math.min(bottom + Theme.space8, maxY);
        }
    }

    Connections {
        target: LauncherModel
        function onSelectedIndexChanged() {
            Qt.callLater(root.ensureSelectionVisible);
        }
    }

    PanelWindow {
        id: win

        // Monitor-aware placement — same pattern as PopupShell.
        readonly property var targetScreen: PopupManager.activeScreen !== null ? PopupManager.activeScreen : PopupManager.fallbackScreen
        readonly property int screenW: win.targetScreen ? win.targetScreen.width : 1280
        readonly property int screenH: win.targetScreen ? win.targetScreen.height : 720
        readonly property bool targetOpen: PopupManager.isOpen("launcher")

        // The window hugs the panel + its shadow, so nothing but the
        // launcher itself is ever drawn (namespace `voidshell-launcher`
        // also keeps the compositor's `^quickshell` blur rule away from
        // this transparent gutter — a matched surface would wash a halo
        // over it; wallpaper/windows stay visible through the surface).
        implicitWidth: root.panelW + root.shadowPad * 2
        implicitHeight: root.panelH + root.shadowPad * 2

        // Centered horizontally; the panel top lands at y=76 so it sits
        // clear of the bar islands (y 10–56) instead of colliding with
        // them mid-screen.
        anchors {
            top: true
            left: true
        }
        margins {
            left: Math.max(0, Math.round((win.screenW - win.implicitWidth) / 2))
            top: Math.max(0, 76 - root.shadowPad)
        }
        screen: win.targetScreen
        // Blur-exempt namespace: the compositor's `^quickshell` blur rule
        // would wash a halo around the panel's transparent shadow gutter
        // (no ignore-zero-alpha option in Hyprland 0.56, design-system §2).
        WlrLayershell.namespace: "voidshell-launcher"
        // Exclusive: typing-to-search and arrow/Enter navigation need
        // real key events — Quickshell's default (None) starves the
        // window of keyboard input entirely.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        // -1: never avoid the bar's exclusive zone (centered placement).
        exclusiveZone: -1
        color: "transparent"

        // Stays mapped while the close animation fades the panel out.
        visible: win.targetOpen || closeAnim.running

        // Escape closes from window scope: a clicked tile or plugin list
        // can hold keyboard focus, which would swallow an off-chain Keys
        // handler — the application-context shortcut stays honest (it
        // only fires while this shell owns keyboard focus).
        Shortcut {
            enabled: win.visible
            context: Qt.ApplicationShortcut
            sequences: ["Escape"]
            onActivated: root.handleEscape()
        }

        onTargetOpenChanged: {
            if (win.targetOpen) {
                closeAnim.stop();
                panel.opacity = 0;
                panel.scale = 0.96;
                enterAnim.restart();
            } else if (win.visible) {
                enterAnim.stop();
                closeAnim.restart();
            }
        }

        onVisibleChanged: {
            if (visible) {
                // Reset both model and field: a stale query in the field
                // with a reset model would show mismatched results.
                searchField.text = "";
                LauncherModel.clearSearch();
                // Preselect the first app — the detail panel opens with
                // content instead of a placeholder.
                LauncherModel.selectedIndex = 0;
                centerFlick.contentY = 0;
                const q = Quickshell.env("VOID_LAUNCHER_QUERY");
                if (q !== undefined && q !== null && q !== "") {
                    // QA hook: preset a command query and activate it so
                    // plugin views can be captured without input synthesis.
                    searchField.text = q;
                    LauncherModel.setSearch(q);
                    LauncherModel.activateSelected();
                } else {
                    const s = Quickshell.env("VOID_LAUNCHER_SECTION");
                    if (s !== undefined && s !== null && s !== "") {
                        // QA hook: preset a sidebar section for capture.
                        LauncherModel.setSection(s);
                    }
                    searchField.forceActiveFocus();
                }
            }
        }

        // Subtle open/close motion: scale 0.96→1 + fade, 180ms (spec
        // window 150–220ms). Layer-shell surfaces get no compositor open
        // animation, so the motion runs in QML on the panel.
        ParallelAnimation {
            id: enterAnim
            NumberAnimation {
                target: panel
                property: "opacity"
                to: 1
                duration: Theme.durationNormal
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: panel
                property: "scale"
                to: 1
                duration: Theme.durationNormal
                easing.type: Easing.OutCubic
            }
        }

        ParallelAnimation {
            id: closeAnim
            NumberAnimation {
                target: panel
                property: "opacity"
                to: 0
                duration: Theme.durationNormal
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: panel
                property: "scale"
                to: 0.96
                duration: Theme.durationNormal
                easing.type: Easing.InCubic
            }
        }

        // Focus fallback: keyboard events from anywhere inside the window
        // bubble here when the search field doesn't hold focus.
        Item {
            id: escGrab
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => root.handleKey(event)
        }

        // --- glass panel --------------------------------------------------
        Item {
            id: panel
            anchors.centerIn: parent
            width: root.panelW
            height: root.panelH

            // Ambient shadow: two-step downward-offset falloff (spec
            // ~0 18px 60px rgba(0,0,0,0.35)); fully QML-side, since the
            // launcher surface opts out of compositor blur. Both steps
            // live in one padded layer so MultiEffect blurs them
            // together: bare Rectangles have hard edges, and two nested
            // steps painted two concentric rings around the panel that
            // read as a halo along the border on light wallpapers.
            // Host padding = blurMax = 8 (the space left between the
            // shapes and the shadowPad window gutter), so alpha reaches
            // zero before the layer edge instead of being clipped into
            // a step (layer effects are clipped to layer bounds).
            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: -26
                anchors.rightMargin: -26
                anchors.topMargin: -16
                anchors.bottomMargin: -28
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 8
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 8
                    radius: Theme.radiusXl + 18
                    color: Colors.shadowMedium
                    opacity: 0.5
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    anchors.topMargin: 14
                    anchors.bottomMargin: 14
                    radius: Theme.radiusXl + 8
                    color: Colors.shadowMedium
                    opacity: 0.4
                }
            }

            // Surface (neon purple glass: purple-tinted translucency,
            // 1px lavender border).
            Rectangle {
                id: surface
                anchors.fill: parent
                radius: Theme.radiusXl
                color: Colors.launcherSurface
                border.width: 1
                border.color: Colors.launcherSurfaceBorder
            }

            // Session-random ink art (InkArt) under the content — the
            // drawer takes the same per-panel texture as the popups.
            Comp.InkTexture {
                anchors.fill: surface
                anchors.margins: 1
                radius: Theme.radiusXl
                source: InkArt.sourceFor("launcher")
            }

            // Inner top highlight (shell glass identity).
            Rectangle {
                anchors.top: surface.top
                anchors.left: surface.left
                anchors.right: surface.right
                anchors.topMargin: 1
                anchors.leftMargin: Theme.space20
                anchors.rightMargin: Theme.space20
                height: 1
                color: Colors.highlightTop
            }

            // --- content ---------------------------------------------------
            Item {
                anchors.fill: parent
                anchors.margins: root.pad

                // Search: centered capsule + the real Ctrl+K keycap at the
                // row's right edge (the shortcut itself focuses the field).
                Item {
                    id: searchRow
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: root.searchH

                    Item {
                        id: capsule
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.round(root.contentW * 0.7)
                        height: root.searchH

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusLg
                            color: Colors.glassCard
                            border.width: 1
                            border.color: searchField.activeFocus ? Colors.borderAccent : Colors.borderSubtle
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.space16
                            anchors.verticalCenter: parent.verticalCenter
                            text: String.fromCodePoint(0xf002) // nerd fa-search
                            font.family: Theme.fontMono
                            font.pixelSize: 15
                            color: searchField.activeFocus ? Colors.accentLight : Colors.textMuted
                        }

                        TextInput {
                            id: searchField
                            anchors.fill: parent
                            leftPadding: 44
                            rightPadding: 16
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: Theme.fontUi
                            font.pixelSize: 14
                            color: Colors.textPrimary
                            selectByMouse: true
                            onTextChanged: {
                                LauncherModel.setSearch(text);
                                Qt.callLater(root.ensureSelectionVisible);
                            }
                            Keys.onPressed: event => root.handleKey(event)
                        }

                        // Placeholder (spec: "Search applications...").
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 44
                            anchors.verticalCenter: parent.verticalCenter
                            visible: searchField.text === ""
                            text: "Search applications..."
                            font.family: Theme.fontUi
                            font.pixelSize: 14
                            color: Colors.textDisabled
                        }
                    }

                    // Ctrl + K keycap — real: handleKey focuses the field.
                    Item {
                        id: ctrlKey
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: ctrlKeyText.width + 18
                        height: 24

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusXs
                            color: Colors.glassCard
                            border.width: 1
                            border.color: Colors.borderSubtle
                        }
                        Text {
                            id: ctrlKeyText
                            anchors.centerIn: parent
                            text: "Ctrl + K"
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            color: Colors.textMuted
                        }
                    }
                }

                // Body: sidebar | center column | detail panel.
                Item {
                    id: body
                    anchors.top: searchRow.bottom
                    anchors.topMargin: Theme.space16
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: bottomStrip.top
                    anchors.bottomMargin: 14

                    SideNav {
                        id: sideNav
                        anchors.top: parent.top
                        anchors.left: parent.left
                        width: root.sideW
                    }

                    AppDetail {
                        id: detail
                        anchors.top: parent.top
                        anchors.right: parent.right
                        width: root.detailW
                        height: parent.height
                        visible: root.appMode
                        entry: LauncherModel.selectedEntry
                        onLaunched: root.launchEntry(LauncherModel.selectedEntry)
                        onTerminalRequested: root.terminalSelected()
                        onLocationRequested: root.locationSelected()
                        onFavoriteToggled: root.toggleFavoriteSelected()
                        onUninstallRequested: root.uninstallSelected()
                    }

                    // Center column: plugin view, commands and the app
                    // grid scroll here; the detail panel's disappearance
                    // in command/plugin mode hands it the width back.
                    Flickable {
                        id: centerFlick
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: sideNav.right
                        anchors.leftMargin: root.colGap
                        anchors.right: parent.right
                        anchors.rightMargin: detail.visible ? root.detailW + root.colGap : 0
                        contentWidth: width
                        contentHeight: centerCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: centerCol.implicitHeight > height

                        Column {
                            id: centerCol
                            width: centerFlick.width
                            spacing: Theme.space16

                            // Plugin view (@git, @containers, …) replaces the lists.
                            Loader {
                                id: pluginLoader
                                width: centerCol.width
                                active: root.pluginMode && root.pluginSource !== ""
                                source: root.pluginSource
                            }

                            Binding {
                                target: pluginLoader.item
                                property: "query"
                                value: LauncherModel.pluginQuery
                                when: pluginLoader.item !== null
                            }

                            // Command section (visible when typing `@`)
                            Item {
                                width: centerCol.width
                                height: commandCol.implicitHeight
                                visible: LauncherModel.commandMode && !root.pluginMode && LauncherModel.filteredCommands.length > 0

                                Column {
                                    id: commandCol
                                    width: parent.width
                                    spacing: 2

                                    Comp.SectionHeader {
                                        anchors.left: parent.left
                                        text: "Commands"
                                    }

                                    Repeater {
                                        id: commandRepeater
                                        model: LauncherModel.filteredCommands
                                        delegate: CommandRow {
                                            required property var modelData
                                            required property int index
                                            cmd: modelData
                                            selected: LauncherModel.selectedIndex >= 0 && LauncherModel.results[LauncherModel.selectedIndex] === modelData
                                            onClicked: {
                                                LauncherModel.selectedIndex = index;
                                                root.activateAndMaybeClose();
                                            }
                                        }
                                    }
                                }
                            }

                            // Application grid (reference: 4 columns, icon +
                            // name tiles, running dot, detail on the right).
                            Item {
                                id: appsSection
                                width: centerCol.width
                                height: appsGrid.implicitHeight
                                visible: root.appMode && LauncherModel.allApps.length > 0

                                readonly property real cellW: (width - Theme.space12 * (root.gridColumns - 1)) / root.gridColumns

                                Grid {
                                    id: appsGrid
                                    width: parent.width
                                    columns: root.gridColumns
                                    spacing: Theme.space12

                                    Repeater {
                                        id: appRepeater
                                        model: LauncherModel.allApps
                                        delegate: AppDelegate {
                                            required property var modelData
                                            required property int index
                                            entry: modelData
                                            cellW: appsSection.cellW
                                            selected: LauncherModel.selectedIndex === index
                                            // Grid click selects (the detail
                                            // panel follows); double-click or
                                            // Enter launches.
                                            onTapped: LauncherModel.selectedIndex = index
                                            onActivated: root.launchEntry(modelData)
                                        }
                                    }
                                }
                            }

                            // Empty states — concrete, never a blank panel.
                            Item {
                                width: centerCol.width
                                height: 64
                                visible: !root.pluginMode
                                         && ((LauncherModel.commandMode && LauncherModel.filteredCommands.length === 0)
                                             || (root.appMode && LauncherModel.allApps.length === 0))

                                Text {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    text: LauncherModel.commandMode
                                          ? "No commands match \"" + LauncherModel.searchText + "\""
                                          : (LauncherModel.searchText !== ""
                                             ? "No applications match \"" + LauncherModel.searchText + "\""
                                             : "Nothing in this section yet")
                                    font.family: Theme.fontUi
                                    font.pixelSize: 13
                                    color: Colors.textMuted
                                }
                            }
                        }
                    }
                }

                // Bottom strip: divider, real recent-launch icons (single
                // click launches) and the View All Apps shortcut back to
                // the All Apps section.
                Item {
                    id: bottomStrip
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: root.stripH

                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        color: Colors.borderSubtle
                    }

                    Text {
                        id: stripLabel
                        anchors.top: parent.top
                        anchors.topMargin: 10
                        anchors.left: parent.left
                        text: "Recent Apps"
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Colors.textSecondary
                    }

                    Row {
                        id: stripRow
                        anchors.top: stripLabel.bottom
                        anchors.topMargin: 6
                        anchors.left: parent.left
                        spacing: Theme.space8

                        Repeater {
                            model: LauncherModel.recentApps.slice(0, 8)
                            delegate: AppDelegate {
                                required property var modelData
                                required property int index
                                entry: modelData
                                showName: false
                                iconSize: 40
                                cellW: 52
                                onTapped: root.launchEntry(modelData)
                            }
                        }

                        // Honest empty state: no launches recorded yet.
                        Text {
                            width: implicitWidth
                            height: 52
                            verticalAlignment: Text.AlignVCenter
                            visible: LauncherModel.recentApps.length === 0
                            text: "No launches yet — apps you open appear here"
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            color: Colors.textMuted
                        }
                    }

                    Item {
                        id: viewAll
                        anchors.right: parent.right
                        anchors.verticalCenter: stripRow.verticalCenter
                        visible: root.appMode
                        width: viewAllText.width + Theme.space24
                        height: 28

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusSm
                            color: viewAllMouse.containsMouse ? Colors.glassHover : "transparent"
                            border.width: 1
                            border.color: Colors.borderSubtle
                        }
                        Text {
                            id: viewAllText
                            anchors.centerIn: parent
                            text: "View All Apps " + String.fromCodePoint(0xf061) // fa-arrow-right
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: Colors.textSecondary
                        }
                        MouseArea {
                            id: viewAllMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchField.text = "";
                                LauncherModel.clearSearch();
                                LauncherModel.setSection("all");
                            }
                        }
                    }
                }
            }
        }
    }
}
