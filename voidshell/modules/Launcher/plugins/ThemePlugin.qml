import QtQuick
import "../../../common"
import "../../../common/components/" as Comp
import "../../../services"

// VOID SHELL — `@color` theme manager (PRD §20). Searchable preset list
// with palette-dot previews, a visible current selection, and the
// dark/light toggle. Choosing a preset writes through ThemeService, so
// every token in the shell rebinds at once; picking a preset while the
// palette follows the wallpaper locks it back (§21.2 stays explicit).
Item {
    id: root

    property string query: ""

    readonly property bool dynamicActive: WallpaperService.paletteMode === "dynamic"

    readonly property var shown: {
        const needle = root.query.trim().toLowerCase();
        if (needle === "") {
            return ThemeService.presets;
        }
        const out = [];
        for (let i = 0; i < ThemeService.presets.length; i++) {
            const p = ThemeService.presets[i];
            if (p.name.toLowerCase().indexOf(needle) !== -1 ||
                p.keywords.indexOf(needle) !== -1 ||
                p.id.indexOf(needle) !== -1) {
                out.push(p);
            }
        }
        return out;
    }

    function selected(presetId) {
        return !root.dynamicActive && ThemeService.presetId === presetId;
    }

    function choose(presetId) {
        if (root.dynamicActive) {
            // An explicit preset choice wins over the wallpaper tone.
            WallpaperService.setPaletteMode("locked", true);
        }
        ThemeService.setPreset(presetId);
    }

    width: parent ? parent.width : 560
    implicitHeight: body.implicitHeight + Theme.space8

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
                        text: "@color"
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                        color: Colors.accentLight
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Themes"
                    font.family: Theme.fontUi
                    font.weight: Font.DemiBold
                    font.pixelSize: 14
                    color: Colors.textPrimary
                }
            }

            // Dark / light control (PRD §20 observed behavior).
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space4

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

        // Dynamic-palette notice (PRD §21.2): selection is only claimed
        // when this shell actually follows a preset.
        Rectangle {
            visible: root.dynamicActive
            width: parent.width
            height: dynamicRow.implicitHeight + Theme.space16
            radius: Theme.radiusSm
            color: Colors.glassCard
            border.width: 1
            border.color: Colors.borderGlass

            Row {
                id: dynamicRow
                anchors.centerIn: parent
                spacing: Theme.space8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String.fromCodePoint(0xF02E9) // md-image
                    font.family: Theme.fontMono
                    font.pixelSize: 13
                    color: Colors.accentLight
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, root.width - 90)
                    wrapMode: Text.WordWrap
                    text: "Palette follows your wallpaper. Pick a preset to lock it."
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    color: Colors.textSecondary
                }
            }
        }

        // --- Preset rows (palette-dot previews) -------------------------
        Column {
            width: parent.width
            spacing: Theme.space4

            Repeater {
                model: root.shown

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool selectedNow: root.selected(modelData.id)
                    readonly property bool hovered: rowArea.containsMouse

                    width: parent ? parent.width : 560
                    height: 56
                    radius: Theme.radiusSm
                    color: hovered ? Colors.glassHover : Colors.glassCard
                    border.width: selectedNow ? 2 : 1
                    border.color: selectedNow ? Colors.borderAccent : (hovered ? Colors.borderGlass : Colors.borderSubtle)

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.space12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space12

                        // Five palette dots: primary, strong, light, support, deep.
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5

                            Repeater {
                                model: [modelData.accent.primary, modelData.accent.strong, modelData.accent.light, modelData.support.plum, modelData.accent.deep]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 14
                                    height: 14
                                    radius: 7
                                    color: ThemeService.colorOf(modelData)
                                    border.width: 1
                                    border.color: Qt.rgba(0, 0, 0, 0.28)
                                }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name
                            font.family: Theme.fontUi
                            font.weight: Font.DemiBold
                            font.pixelSize: 13
                            color: Colors.textPrimary
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: modelData.default === true
                            width: defText.implicitWidth + 12
                            height: 20
                            radius: 10
                            color: Colors.glassBase
                            border.width: 1
                            border.color: Colors.borderSubtle

                            Text {
                                id: defText
                                anchors.centerIn: parent
                                text: "Default"
                                font.family: Theme.fontUi
                                font.pixelSize: 10
                                color: Colors.textMuted
                            }
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.space12
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.selectedNow
                        text: String.fromCodePoint(0xF00C) // md-check
                        font.family: Theme.fontMono
                        font.pixelSize: 14
                        color: Colors.accentPrimary
                    }

                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.choose(row.modelData.id)
                    }
                }
            }
        }

        Comp.EmptyState {
            width: parent.width
            visible: root.shown.length === 0
            glyph: String.fromCodePoint(0xEFCC) // fa-palette
            title: "No matching themes"
            body: "Try another word — presets match on name and keywords."
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
