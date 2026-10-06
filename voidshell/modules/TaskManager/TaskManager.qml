import QtQuick
import Quickshell
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — system monitor / task manager drawer (PRD 23).
// A left-side drawer under the bar, laid out as two columns so every
// section of PRD 23 is visible without hunting for a scroll:
//   left  — identity header, package updates, gauges, history graphs
//   right — the sortable process table (sampled only while open)
// Everything reads SystemStats, the one shared sampler, so the drawer
// never keeps its own copy of system state.
Scope {
    id: root

    readonly property int rightColumn: 316

    // PRD 23.5 / 36: `ps` runs about every 3 s while the view is open.
    Binding {
        target: SystemStats
        property: "processEnabled"
        value: win.visible
    }

    // First open kicks off a package update check so the row is never a
    // stale "idle" placeholder (PRD 23.2).
    Connections {
        target: win
        function onVisibleChanged() {
            if (win.visible && SystemStats.updatesState === "idle") {
                SystemStats.refreshUpdates();
            }
        }
    }

    function updatesMessage() {
        switch (SystemStats.updatesState) {
        case "checking":
            return "Checking for updates…";
        case "unavailable":
            return "No update data — install checkupdates (pacman-contrib) and sync the package database.";
        case "ok":
            return SystemStats.updateCount === 0 ? "System is up to date." : "";
        default:
            return "Not checked in this session yet — press refresh.";
        }
    }

    Comp.PopupShell {
        id: win
        popupName: "taskManager"
        texture: true
        textureSource: InkArt.sourceFor("taskManager")
        panelWidth: 760
        // Worst case for a 720-tall screen under the bar: 72 top offset +
        // (632 panel + 16 window gutter) = 720 — the monitor drawer must
        // never run off the bottom of the screen again (it used to sit
        // 142px past the edge with maxHeight 940).
        maxHeight: 632
        anchor: "left"

        Comp.PopupHeader {
            width: parent.width
            title: "System Monitor"
            subtitle: SystemStats.username !== "" ? SystemStats.username + "@" + SystemStats.hostname + " · " + SystemStats.wmName : SystemStats.wmName
            onClosed: PopupManager.closeAll()
        }

        // The drawer scrolls only when the screen is too short for it;
        // the cap is the part of a 720 screen left under the bar (72 top
        // offset + 40 header + 8 gap + 556 + 24 panel padding + 16 window
        // gutter = 716).
        Flickable {
            id: scroller
            width: parent.width
            height: Math.min(inner.implicitHeight, 556)
            contentHeight: inner.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            Row {
                id: inner
                width: scroller.width
                spacing: Theme.space12

                // ================= left column ============================
                Column {
                    id: leftCol
                    width: parent.width - root.rightColumn - Theme.space12
                    spacing: Theme.space12

                    // ---- identity header (PRD 23.1) ---------------------
                    Comp.GlassCard {
                        width: parent.width
                        height: identityRow.height + Theme.space24

                        Item {
                            id: identityRow
                            width: parent.width
                            height: 56

                            // Avatar: initials from the real logged-in user.
                            Rectangle {
                                id: avatar
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 52
                                height: 52
                                radius: 26
                                color: Colors.indigoDeep
                                border.width: 1
                                border.color: Colors.borderGlass

                                Text {
                                    anchors.centerIn: parent
                                    text: SystemStats.username !== "" ? SystemStats.username.charAt(0).toUpperCase() : "?"
                                    font.family: Theme.fontUi
                                    font.weight: Font.DemiBold
                                    font.pixelSize: 20
                                    color: Colors.accentLight
                                }
                            }

                            // Settings + session shortcuts (PRD 23.1).
                            Row {
                                id: actions
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.space8

                                Comp.IconButton {
                                    icon: String.fromCodePoint(0xF0493) // md-cog
                                    onClicked: PopupManager.open("quickSettings")
                                }

                                Comp.IconButton {
                                    icon: String.fromCodePoint(0xF0425) // md-power
                                    onClicked: PopupManager.open("power")
                                }
                            }

                            Column {
                                anchors.left: avatar.right
                                anchors.right: actions.left
                                anchors.leftMargin: Theme.space12
                                anchors.rightMargin: Theme.space12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: SystemStats.username !== "" ? SystemStats.username : "Unknown user"
                                    font.family: Theme.fontUi
                                    font.weight: Font.DemiBold
                                    font.pixelSize: 15
                                    color: Colors.textPrimary
                                }

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: (SystemStats.osName !== "" ? SystemStats.osName : "Linux") + " · " + SystemStats.wmName
                                    font.family: Theme.fontUi
                                    font.pixelSize: 12
                                    color: Colors.textMuted
                                }

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: "Up " + SystemStats.uptimeText + (SystemStats.kernel !== "" ? " · " + SystemStats.kernel : "")
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                    color: Colors.textDisabled
                                }
                            }
                        }
                    }

                    // ---- package updates (PRD 23.2) ----------------------
                    Comp.GlassCard {
                        width: parent.width
                        height: updatesCol.implicitHeight + Theme.space24

                        Column {
                            id: updatesCol
                            width: parent.width
                            spacing: Theme.space8

                            Item {
                                width: parent.width
                                height: 34

                                Comp.SectionHeader {
                                    id: updatesTitle
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Package updates"
                                }

                                Rectangle {
                                    anchors.left: updatesTitle.right
                                    anchors.leftMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: SystemStats.updateCount > 0
                                    width: updateBadge.implicitWidth + 12
                                    height: 18
                                    radius: 9
                                    color: Colors.accentStrong

                                    Text {
                                        id: updateBadge
                                        anchors.centerIn: parent
                                        text: String(SystemStats.updateCount)
                                        font.family: Theme.fontMono
                                        font.weight: Font.DemiBold
                                        font.pixelSize: 10
                                        color: Colors.textOnAccent
                                    }
                                }

                                Comp.IconButton {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    icon: String.fromCodePoint(0xF0450) // md-refresh
                                    onClicked: SystemStats.refreshUpdates()

                                    RotationAnimation on rotation {
                                        running: SystemStats.updatesState === "checking"
                                        loops: Animation.Infinite
                                        from: 0
                                        to: 360
                                        duration: 900
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                visible: root.updatesMessage() !== ""
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                text: root.updatesMessage()
                                font.family: Theme.fontUi
                                font.pixelSize: 12
                                color: Colors.textMuted
                            }

                            Repeater {
                                model: SystemStats.updatesState === "ok" ? SystemStats.updateList.slice(0, 4) : []

                                delegate: Text {
                                    required property var modelData
                                    width: updatesCol.width
                                    elide: Text.ElideRight
                                    text: modelData
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                    color: Colors.textSecondary
                                }
                            }

                            Text {
                                width: parent.width
                                visible: SystemStats.updateCount > 4
                                elide: Text.ElideRight
                                text: "+" + (SystemStats.updateCount - 4) + " more"
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                                color: Colors.textDisabled
                            }
                        }
                    }

                    // ---- gauges (PRD 23.3) -------------------------------
                    Row {
                        width: parent.width
                        spacing: Theme.space12

                        GaugeRing {
                            width: (parent.width - Theme.space12 * 2) / 3
                            label: "CPU"
                            glyph: String.fromCodePoint(0xF2DB) // fa-microchip
                            value: SystemStats.cpuUsage
                            detail: SystemStats.tempAvailable ? SystemStats.cpuTemp + "°C" : "no sensor"
                        }

                        GaugeRing {
                            width: (parent.width - Theme.space12 * 2) / 3
                            label: "Memory"
                            glyph: String.fromCodePoint(0xF035B) // md-memory
                            value: SystemStats.memUsage
                            detail: SystemStats.formatKb(SystemStats.memTotalKb - SystemStats.memAvailableKb) + " / " + SystemStats.formatKb(SystemStats.memTotalKb)
                        }

                        GaugeRing {
                            width: (parent.width - Theme.space12 * 2) / 3
                            label: "Disk"
                            glyph: String.fromCodePoint(0xF02CA) // md-harddisk
                            value: SystemStats.diskUsage
                            detail: SystemStats.formatBytes(SystemStats.diskUsedBytes) + " / " + SystemStats.formatBytes(SystemStats.diskTotalBytes)
                        }
                    }

                    // ---- history graphs (PRD 23.4) -----------------------
                    Row {
                        width: parent.width
                        spacing: Theme.space12

                        Comp.GlassCard {
                            width: (parent.width - Theme.space12) / 2
                            height: cpuChart.implicitHeight + Theme.space24

                            HistoryChart {
                                id: cpuChart
                                width: parent.width
                                height: parent.height
                                title: "CPU history"
                                subtitle: "last " + SystemStats.historyLimit + " samples"
                                values: SystemStats.cpuHistory
                                maxValue: 100
                                series1: Colors.accentPrimary
                            }
                        }

                        Comp.GlassCard {
                            width: (parent.width - Theme.space12) / 2
                            height: memChart.implicitHeight + Theme.space24

                            HistoryChart {
                                id: memChart
                                width: parent.width
                                height: parent.height
                                title: "Memory history"
                                subtitle: "% used"
                                values: SystemStats.memHistory
                                maxValue: 100
                                series1: Colors.info
                            }
                        }
                    }

                    Comp.GlassCard {
                        width: parent.width
                        height: netChart.implicitHeight + Theme.space24

                        HistoryChart {
                            id: netChart
                            width: parent.width
                            height: parent.height
                            title: "Network history"
                            subtitle: "↓ " + SystemStats.formatRate(SystemStats.netDown) + "   ↑ " + SystemStats.formatRate(SystemStats.netUp)
                            values: SystemStats.netHistory
                            values2: SystemStats.netUpHistory
                            maxValue: 0 // auto-scale: byte rates are unbounded
                            series1: Colors.success
                            series2: Colors.accentLight
                            legend1: "download"
                            legend2: "upload"
                        }
                    }
                }

                // ================= right column ===========================
                Item {
                    id: rightCol
                    width: root.rightColumn
                    height: leftCol.height

                    Item {
                        id: procHeader
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 24

                        Comp.SectionHeader {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Processes"
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: SystemStats.processes.length + " · 3s"
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            color: Colors.textDisabled
                        }
                    }

                    ProcessTable {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: procHeader.bottom
                        anchors.topMargin: Theme.space4
                        anchors.bottom: parent.bottom
                    }
                }
            }
        }

    }
}
