import QtQuick
import "../../../common"
import "../../../common/components/" as Comp
import "../../../services"

// VOID SHELL — `@wp` wallpaper manager (PRD §21). Thumbnail grid over the
// user's wallpaper directories, search through the typed query, locked /
// dynamic palette switch and the dark/light control. Applying goes
// through WallpaperService (awww daemon), which owns persistence and the
// dynamic-tone recalculation.
Item {
    id: root

    property string query: ""

    readonly property var shown: WallpaperService.search(root.query)
    readonly property bool dynamicMode: WallpaperService.paletteMode === "dynamic"

    width: parent ? parent.width : 560
    implicitHeight: body.implicitHeight + Theme.space8

    readonly property int cols: 3
    readonly property int cellW: width > 0 ? Math.floor((width - Theme.space12 * (cols - 1)) / cols) : 160
    readonly property int cellH: Math.round(cellW * 0.56) + 26

    Column {
        id: body
        width: parent.width
        spacing: Theme.space8

        // --- Header -----------------------------------------------------
        Item {
            width: parent.width
            height: 34

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space8

                Comp.IconButton {
                    icon: String.fromCodePoint(0xF053) // fa-chevron_left
                    iconSize: 14
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: LauncherModel.clearPlugin()
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: pillText.implicitWidth + 16
                    height: 24
                    radius: Theme.radiusSm
                    color: Colors.glassCard
                    border.width: 1
                    border.color: Colors.borderSubtle

                    Text {
                        id: pillText
                        anchors.centerIn: parent
                        text: "@wp"
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                        color: Colors.accentLight
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Wallpapers"
                    font.family: Theme.fontUi
                    font.weight: Font.DemiBold
                    font.pixelSize: 14
                    color: Colors.textPrimary
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: WallpaperService.availableReady
                    text: WallpaperService.available.length + (WallpaperService.available.length === 1 ? " image" : " images")
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    color: Colors.textMuted
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space4

                // Locked / dynamic palette (PRD §21.2).
                ModeBtn {
                    label: "Locked"
                    active: !root.dynamicMode
                    onClicked: WallpaperService.setPaletteMode("locked")
                }

                ModeBtn {
                    label: "Dynamic"
                    active: root.dynamicMode
                    onClicked: WallpaperService.setPaletteMode("dynamic")
                }
            }
        }

        // --- Body states -------------------------------------------------
        Comp.EmptyState {
            width: parent.width
            visible: WallpaperService.scanning
            glyph: String.fromCodePoint(0xF0450) // md-refresh
            title: "Scanning for wallpapers"
            body: "Looking in ~/Pictures/wallpapers and ~/Pictures/Wallpapers."
        }

        Comp.EmptyState {
            width: parent.width
            visible: WallpaperService.availableReady && WallpaperService.available.length === 0
            glyph: String.fromCodePoint(0xF02E9) // md-image
            title: "No wallpapers found"
            body: "Add images to ~/Pictures/wallpapers — png, jpg, webp or gif."
        }

        Comp.EmptyState {
            width: parent.width
            visible: WallpaperService.availableReady && WallpaperService.available.length > 0 && root.shown.length === 0
            glyph: String.fromCodePoint(0xF002) // fa-magnifying-glass
            title: "No match"
            body: "No wallpaper name matches your search."
        }

        // --- Thumbnail grid ----------------------------------------------
        Flow {
            id: grid
            width: parent.width
            spacing: Theme.space12
            visible: root.shown.length > 0

            Repeater {
                model: root.shown

                delegate: Item {
                    id: cell
                    required property var modelData
                    readonly property bool isCurrent: modelData === WallpaperService.current
                    readonly property string fileName: WallpaperService.baseName(modelData)

                    width: root.cellW
                    height: root.cellH

                    Rectangle {
                        id: frame
                        anchors.top: parent.top
                        width: parent.width
                        height: parent.height - 22
                        radius: Theme.radiusSm
                        color: Colors.glassCard
                        clip: true
                        border.width: cell.isCurrent ? 2 : 1
                        border.color: cell.isCurrent ? Colors.borderAccent : (cellArea.containsMouse ? Colors.borderGlass : Colors.borderSubtle)

                        Image {
                            anchors.fill: parent
                            source: "file://" + cell.modelData
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                        }

                        // Current badge.
                        Rectangle {
                            visible: cell.isCurrent
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.top: parent.top
                            anchors.topMargin: 6
                            width: 20
                            height: 20
                            radius: 10
                            color: Colors.accentStrong

                            Text {
                                anchors.centerIn: parent
                                text: String.fromCodePoint(0xF00C) // md-check
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                                color: Colors.textOnAccent
                            }
                        }

                        // Busy dim while awww applies.
                        Rectangle {
                            visible: WallpaperService.applying && cell.isCurrent
                            anchors.fill: parent
                            color: Qt.rgba(0, 0, 0, 0.35)

                            Text {
                                anchors.centerIn: parent
                                text: "Applying…"
                                font.family: Theme.fontUi
                                font.weight: Font.Medium
                                font.pixelSize: 12
                                color: Colors.textPrimary
                            }
                        }
                    }

                    Text {
                        anchors.top: frame.bottom
                        anchors.topMargin: 5
                        anchors.left: parent.left
                        width: parent.width
                        elide: Text.ElideMiddle
                        horizontalAlignment: Text.AlignHCenter
                        text: cell.fileName
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                        color: cell.isCurrent ? Colors.accentLight : Colors.textMuted
                    }

                    MouseArea {
                        id: cellArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: WallpaperService.apply(cell.modelData)
                    }
                }
            }
        }

        // --- Overlay mode (PRD §29–§30, off by default) -------------------
        Item {
            width: parent.width
            height: overlayRow.implicitHeight

            Row {
                id: overlayRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Overlay"
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    color: Colors.textMuted
                }

                ModeBtn {
                    label: "Off"
                    active: WallpaperService.overlay === "off"
                    onClicked: WallpaperService.setOverlay("off")
                }

                ModeBtn {
                    label: "Visualizer"
                    active: WallpaperService.overlay === "visualizer"
                    onClicked: WallpaperService.setOverlay("visualizer")
                }

                ModeBtn {
                    label: "Clock"
                    active: WallpaperService.overlay === "clock"
                    onClicked: WallpaperService.setOverlay("clock")
                }

                ModeBtn {
                    label: "Clock+Lyrics"
                    active: WallpaperService.overlay === "clock+lyrics"
                    onClicked: WallpaperService.setOverlay("clock+lyrics")
                }
            }
        }

        // --- Dark / light control (PRD §21 observed behavior) -------------
        Item {
            width: parent.width
            height: modeRow.implicitHeight

            Row {
                id: modeRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Appearance"
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    color: Colors.textMuted
                }

                ModeBtn {
                    label: "Dark"
                    active: ThemeService.mode === "dark"
                    onClicked: ThemeService.setMode("dark")
                }

                ModeBtn {
                    label: "Light"
                    active: ThemeService.mode === "light"
                    onClicked: ThemeService.setMode("light")
                }
            }
        }
    }

    component ModeBtn: Rectangle {
        id: btn
        property string label: ""
        property bool active: false
        signal clicked

        width: modeLabel.implicitWidth + Theme.space24
        height: 26
        radius: Theme.radiusSm
        color: active ? Colors.accentStrong : Colors.glassCard
        border.width: 1
        border.color: active ? Colors.borderAccent : (btnArea.containsMouse ? Colors.borderGlass : Colors.borderSubtle)

        Text {
            id: modeLabel
            anchors.centerIn: parent
            text: btn.label
            font.family: Theme.fontUi
            font.weight: Font.DemiBold
            font.pixelSize: 12
            color: btn.active ? Colors.textOnAccent : Colors.textSecondary
        }

        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
