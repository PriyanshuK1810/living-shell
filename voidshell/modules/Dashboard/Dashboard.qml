import QtQuick
import Quickshell
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — dashboard (PRD 22): large centered glass panel with four
// top tabs (Overview, Media, Alerts, Productivity). All tabs are backed
// by the existing service layer — no dashboard-local copies of media,
// weather, notification or task state. The overview hosts the merged
// calendar (the old standalone panel) and the weather card; the clock
// pill opens the dashboard on it.
Scope {
    id: root

    // Weather is fetched only while the dashboard can show it (PRD 36);
    // the header badge and the Overview card both read it, so any open
    // tab counts. The service keeps its own >=15 minute refresh cadence.
    readonly property bool wantsWeather: win.visible

    Binding {
        target: WeatherService
        property: "viewsDashboard"
        value: root.wantsWeather
    }

    property string activeTab: "overview"

    // Island routing (MASTER PROMPT §17): the router records the
    // destination and its item target just before opening the dashboard,
    // so this consumer can land on the requested tab instead of always
    // falling back to Overview. `routeTarget` is the item the event named
    // (a date, notification id, task id…); tabs that do not use one
    // simply ignore it.
    property string routeTarget: ""

    Connections {
        target: IslandRouter
        function onSerialChanged() {
            root.activeTab = IslandRouter.normalizeTab(IslandRouter.tab);
            root.routeTarget = IslandRouter.target;
        }
    }

    readonly property var tabs: [
        {
            id: "overview",
            label: "Overview",
            icon: 0xF0570 // md-view_grid
        },
        {
            id: "media",
            label: "Media",
            icon: 0xF001 // fa-music
        },
        {
            id: "alerts",
            label: "Alerts",
            icon: 0xF0F3 // fa-bell
        },
        {
            id: "productivity",
            label: "Productivity",
            icon: 0xF080 // fa-chart_bar
        }
    ]

    function tabLabel(tabId) {
        for (let i = 0; i < tabs.length; i++) {
            if (tabs[i].id === tabId) {
                return tabs[i].label;
            }
        }
        return "";
    }

    // QA hook (PRD 43.2): VOID_TAB=<id> selects a tab at startup.
    Component.onCompleted: {
        const t = Quickshell.env("VOID_TAB");
        if (t !== undefined && t !== null && t !== "") {
            activeTab = t;
        }
    }

    Comp.PopupShell {
        id: win
        popupName: "dashboard"
        panelWidth: 780
        maxHeight: 680
        anchor: "center"
        // Reference-matched chrome: violet glow edge + ink-wash
        // wallpaper texture behind the glass.
        glow: true
        texture: true
        // Bundled ink-wash scene (4:3 — fits the panel almost 1:1); the
        // cards each carry a different piece of the same set.
        textureSource: Qt.resolvedUrl("../../assets/dashboard/ink-3.jpg")

        // Closing returns the dashboard to its home tab: the next keybind
        // open always lands on Overview, never on a tab the clock pill or
        // a previous session left behind.
        onVisibleChanged: {
            if (!visible) {
                root.activeTab = "overview";
                root.routeTarget = "";
            } else {
                // Opening the dashboard is an explicit look at system
                // state: refresh the package count on demand instead of
                // waiting out the (6 h) background cadence.
                SystemStats.refreshUpdates();
            }
        }

        Column {
            width: parent.width
            spacing: Theme.space8

            // Header: centered title block with the real weather glyph
            // pinned left (reference's sun badge) — only when fetched.
            Item {
                width: parent.width
                height: header.implicitHeight

                Comp.PopupHeader {
                    id: header
                    width: parent.width
                    title: "Dashboard"
                    // The dashboard always centers its heading (PRD-style
                    // centered chrome); other panels keep the left default.
                    centered: true
                    titleSize: 19
                    subtitle: SystemStats.username !== "" ? SystemStats.username + "@" + SystemStats.hostname + " · " + SystemStats.osName : "System overview"
                    onClosed: PopupManager.closeAll()
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.space4
                    anchors.verticalCenter: parent.verticalCenter
                    text: WeatherService.hasData ? WeatherService.iconFor(WeatherService.weatherCode) : ""
                    visible: text !== ""
                    font.family: Theme.fontMono
                    font.pixelSize: 22
                    color: Colors.accentLight
                }
            }

            // Tab bar: centered segmented pills, active filled violet with
            // a restrained glow (reference's Overview pill).
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.space4

                Repeater {
                    model: root.tabs

                    Rectangle {
                        required property var modelData
                        readonly property bool activeTab: root.activeTab === modelData.id
                        width: pillRow.implicitWidth + Theme.space24
                        height: 36
                        radius: 18
                        color: activeTab ? Colors.accentStrong : (tabArea.containsMouse ? Colors.glassHover : "transparent")
                        border.width: 1
                        border.color: activeTab ? Colors.borderAccent : (tabArea.containsMouse ? Colors.borderGlass : "transparent")

                        Comp.GlowBorder {
                            anchors.fill: parent
                            anchors.margins: -1
                            radius: 18
                            glowColor: Colors.glowStrong
                            visible: parent.activeTab
                        }

                        Row {
                            id: pillRow
                            anchors.centerIn: parent
                            spacing: Theme.space8

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: String.fromCodePoint(modelData.icon)
                                font.family: Theme.fontMono
                                font.pixelSize: 14
                                color: parent.parent.activeTab ? Colors.textOnAccent : Colors.textSecondary
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                font.family: Theme.fontUi
                                font.weight: Font.DemiBold
                                font.pixelSize: 13
                                color: parent.parent.activeTab ? Colors.textOnAccent : Colors.textSecondary
                            }
                        }

                        // Alerts carries the real unread count.
                        Rectangle {
                            anchors.left: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: -6
                            anchors.topMargin: 2
                            width: badgeText.implicitWidth + 8
                            height: 16
                            radius: 8
                            color: Colors.dangerDeep
                            visible: modelData.id === "alerts" && NotificationService.hasUnread

                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: String(NotificationService.unreadCount)
                                font.family: Theme.fontUi
                                font.weight: Font.DemiBold
                                font.pixelSize: 10
                                color: Colors.textOnAccent
                            }
                        }

                        MouseArea {
                            id: tabArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activeTab = modelData.id
                        }
                    }
                }
            }

            // Tab body: all tabs stay alive so scroll/selection state is
            // preserved while flipping between them.
            Item {
                id: body
                width: parent.width
                height: 500

                OverviewTab {
                    anchors.fill: parent
                    visible: root.activeTab === "overview"
                }

                MediaTab {
                    anchors.fill: parent
                    visible: root.activeTab === "media"
                }

                AlertsTab {
                    anchors.fill: parent
                    visible: root.activeTab === "alerts"
                }

                ProductivityTab {
                    anchors.fill: parent
                    visible: root.activeTab === "productivity"
                }
            }
        }
    }
}
