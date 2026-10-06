import QtQuick
import Quickshell
import "../../common"
import "../../common/components/" as Comp
import "../../services"
import "../Calendar" as CalendarModule

// VOID SHELL — dashboard Overview tab (PRD 22.1): responsive two-column
// cards with real data only — clock, the full calendar (navigator, month
// grid, day agenda, new-event form — the old calendar panel merged in),
// live weather, compact media card, identity (user/OS/WM) and uptime.
// No example values are hard-coded; a card without data says so.
// The left column outgrows the fixed body with a long day agenda, so the
// tab scrolls vertically instead of clipping.
Item {
    id: root

    readonly property int colWidth: (width - Theme.space12) / 2
    readonly property int halfWidth: width

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: overviewRow.implicitHeight
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Row {
            id: overviewRow
            width: scroll.width
            spacing: Theme.space12

            // ---- left column: clock + calendar -------------------------------
            Column {
                width: root.colWidth
                spacing: Theme.space12

                GlassCardLike {
                    width: parent.width
                    height: 116
                    textureSource: Qt.resolvedUrl("../../assets/dashboard/ink-1.jpg")
                    textureZoom: 2.4
                    textureFocusX: 0.63
                    textureFocusY: 0.26

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatTime(clock.date, "hh:mm")
                            font.family: Theme.fontUi
                            font.weight: Font.Bold
                            font.pixelSize: 44
                            color: Colors.textPrimary
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDate(clock.date, "dddd, MMMM d")
                            font.family: Theme.fontUi
                            font.pixelSize: 14
                            color: Colors.textMuted
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDate(clock.date, "yyyy")
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                            color: Colors.textDisabled
                        }
                    }
                }

                // The calendar (navigator, grid, day agenda, new event) — the
                // standalone panel merged into the overview; sized by its own
                // implicitHeight so the column (and this tab) scroll when the
                // agenda grows. Carded to match the reference grid.
                GlassCardLike {
                    width: parent.width
                    height: calendar.implicitHeight + Theme.space24
                    textureSource: Qt.resolvedUrl("../../assets/dashboard/ink-3.jpg")
                    textureZoom: 1.7
                    textureFocusX: 0.2
                    textureFocusY: 0.42

                    CalendarModule.Calendar {
                        id: calendar
                        width: parent.width
                    }
                }
            }

            // ---- right column: weather, media, identity ----------------------
            Column {
                width: root.colWidth
                spacing: Theme.space12

                GlassCardLike {
                    width: parent.width
                    height: 132
                    textureSource: Qt.resolvedUrl("../../assets/dashboard/ink-2.jpg")
                    textureZoom: 2.6
                    textureFocusX: 0.68
                    textureFocusY: 0.7

                    // Weather with a real unavailable state (PRD 37).
                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        visible: WeatherService.hasData

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Theme.space12

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: WeatherService.iconFor(WeatherService.weatherCode)
                                font.family: Theme.fontMono
                                font.pixelSize: 34
                                color: Colors.accentLight
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0

                                Text {
                                    text: Math.round(WeatherService.temperature) + "°"
                                    font.family: Theme.fontUi
                                    font.weight: Font.DemiBold
                                    font.pixelSize: 30
                                    color: Colors.textPrimary
                                }

                                Text {
                                    text: WeatherService.conditionText
                                    font.family: Theme.fontUi
                                    font.pixelSize: 13
                                    color: Colors.textSecondary
                                }
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: [WeatherService.locationLabel, WeatherService.updatedLabel !== "" ? "updated " + WeatherService.updatedLabel : ""].filter(v => v !== "").join(" · ")
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            color: Colors.textMuted
                        }
                    }

                    Comp.EmptyState {
                        anchors.centerIn: parent
                        width: parent.width - Theme.space32
                        busy: WeatherService.fetching
                        glyph: String.fromCodePoint(0xF0590) // md-weather_cloudy
                        title: WeatherService.fetching ? "Loading weather" : "Weather unavailable"
                        body: WeatherService.stale ? "Showing cached data from " + WeatherService.updatedLabel : "The dashboard only shows real fetched conditions."
                        visible: !WeatherService.hasData
                    }
                }

                GlassCardLike {
                    width: parent.width
                    height: 176
                    textureSource: Qt.resolvedUrl("../../assets/dashboard/ink-4.jpg")
                    textureZoom: 2.2
                    textureFocusX: 0.67
                    textureFocusY: 0.29

                    // Compact media card — same MediaService as the bar;
                    // reference layout: artwork + text with the round
                    // glowing play, real volume slider across the bottom.
                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.space16
                        spacing: Theme.space8

                        Row {
                            width: parent.width
                            spacing: Theme.space12

                            Comp.MediaArtwork {
                                anchors.verticalCenter: parent.verticalCenter
                                artUrl: MediaService.artUrl
                                iconSize: 88
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 88 - Theme.space12
                                spacing: 4

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: MediaService.available ? (MediaService.trackTitle !== "" ? MediaService.trackTitle : "Nothing playing") : "No player running"
                                    font.family: Theme.fontUi
                                    font.weight: Font.DemiBold
                                    font.pixelSize: 15
                                    color: Colors.textPrimary
                                }

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: MediaService.available && MediaService.artist !== "" ? MediaService.artist : "—"
                                    font.family: Theme.fontUi
                                    font.pixelSize: 13
                                    color: Colors.textSecondary
                                }

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: MediaService.available ? MediaService.identity : ""
                                    font.family: Theme.fontUi
                                    font.pixelSize: 11
                                    color: Colors.textMuted
                                    visible: text !== ""
                                }

                                Row {
                                    spacing: Theme.space8

                                    Comp.MediaControls {
                                        anchors.verticalCenter: parent.verticalCenter
                                        large: false
                                        glowPlay: true
                                    }
                                }
                            }
                        }

                        Comp.ShellSlider {
                            width: parent.width
                            icon: String.fromCodePoint(AudioService.muted || AudioService.volumePercent === 0 ? 0xF0581 : 0xF057E)
                            iconAction: AudioService.available
                            enabled: AudioService.available
                            value: AudioService.volume
                            from: 0
                            to: 1
                            onIconClicked: AudioService.toggleMute()
                            onMoved: v => AudioService.setVolume(v)
                        }
                    }
                }

                GlassCardLike {
                    width: parent.width
                    height: 152
                    textureSource: Qt.resolvedUrl("../../assets/dashboard/ink-5.jpg")
                    textureZoom: 2.3
                    textureFocusX: 0.23
                    textureFocusY: 0.29

                    // Identity: real /etc/os-release + Hyprland + uptime,
                    // one outline glyph per row (reference's info card).
                    Grid {
                        anchors.centerIn: parent
                        width: parent.width - Theme.space32
                        columns: 2
                        columnSpacing: Theme.space16
                        rowSpacing: Theme.space8

                        Repeater {
                            model: [
                                {
                                    label: "User",
                                    value: SystemStats.username !== "" ? SystemStats.username : "—",
                                    icon: 0xF0004 // md-account
                                },
                                {
                                    label: "OS",
                                    value: SystemStats.osName !== "" ? SystemStats.osName : "—",
                                    icon: 0xE732 // dev-archlinux
                                },
                                {
                                    label: "Window manager",
                                    value: SystemStats.wmName,
                                    icon: 0xEB7F // cod-window
                                },
                                {
                                    label: "Kernel",
                                    value: SystemStats.kernel !== "" ? SystemStats.kernel : "—",
                                    icon: 0xF013 // fa-gear
                                },
                                {
                                    label: "Host",
                                    value: SystemStats.hostname !== "" ? SystemStats.hostname : "—",
                                    icon: 0xF109 // fa-laptop
                                },
                                {
                                    label: "Uptime",
                                    value: SystemStats.uptimeText !== "" ? SystemStats.uptimeText : "—",
                                    icon: 0xF017 // fa-clock_o
                                }
                            ]

                            Row {
                                required property var modelData
                                width: (root.colWidth - Theme.space32 - Theme.space16) / 2
                                spacing: Theme.space8

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: String.fromCodePoint(modelData.icon)
                                    font.family: Theme.fontMono
                                    font.pixelSize: 15
                                    color: Colors.accentLight
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 24 - Theme.space8
                                    spacing: 1

                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: modelData.label
                                        font.family: Theme.fontUi
                                        font.pixelSize: 11
                                        color: Colors.textMuted
                                    }

                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: modelData.value
                                        font.family: Theme.fontUi
                                        font.weight: Font.Medium
                                        font.pixelSize: 13
                                        color: Colors.textPrimary
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Local card surface: reference-matched ink texture behind the glass
    // with a visible violet edge; still the shared GlassCard tokens.
    component GlassCardLike: Comp.GlassCard {
        texture: true
        borderNormal: Colors.borderAccent
    }
}
