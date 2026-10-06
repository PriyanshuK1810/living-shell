import QtQuick
import "../../common"
import "../../services"

// VOID SHELL — launcher sidebar navigation (reference: "Neon Purple
// Glassmorphism App Launcher"). Every row maps to a real LauncherModel
// section; the active row is marked by a gradient pill plus a heavier
// label — never color alone — and zero-count categories hide themselves
// so the nav never offers an empty shelf.
Item {
    id: root

    readonly property int itemH: 34

    implicitWidth: 230
    implicitHeight: navCol.implicitHeight

    Column {
        id: navCol
        width: parent.width
        spacing: 2

        Repeater {
            model: LauncherModel.sidebarSections

            delegate: Item {
                id: row
                required property var modelData
                required property int index

                readonly property int count: LauncherModel.countFor(modelData.id)
                readonly property bool active: LauncherModel.section === modelData.id
                readonly property bool isCat: modelData.id.indexOf("cat:") === 0
                readonly property bool empty: row.isCat && row.count === 0
                // Divider above the first *visible* category row.
                readonly property bool firstCat: {
                    if (!row.isCat) {
                        return false;
                    }
                    var secs = LauncherModel.sidebarSections;
                    for (var i = 3; i < row.index; i++) {
                        if (LauncherModel.countFor(secs[i].id) > 0) {
                            return false;
                        }
                    }
                    return true;
                }

                width: navCol.width
                height: row.empty ? 0 : root.itemH + (row.firstCat ? 16 : 0)
                visible: !row.empty

                Rectangle {
                    visible: row.firstCat
                    anchors.top: parent.top
                    anchors.topMargin: 7
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Theme.space12
                    anchors.rightMargin: Theme.space12
                    height: 1
                    color: Colors.borderSubtle
                }

                Item {
                    id: pill
                    anchors.top: parent.top
                    anchors.topMargin: row.firstCat ? 16 : 0
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: root.itemH

                    // Active: purple gradient pill (shape change, not a
                    // bare recolor — the label also goes DemiBold below).
                    Rectangle {
                        anchors.fill: parent
                        visible: row.active
                        radius: Theme.radiusSm
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Colors.accentPrimary }
                            GradientStop { position: 1.0; color: Colors.accentStrong }
                        }
                    }

                    // Hover wash for inactive rows.
                    Rectangle {
                        anchors.fill: parent
                        visible: !row.active && hover.containsMouse
                        radius: Theme.radiusSm
                        color: Colors.glassHover
                    }

                    Text {
                        id: glyph
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.space12
                        anchors.verticalCenter: parent.verticalCenter
                        text: String.fromCodePoint(modelData.glyph)
                        font.family: Theme.fontMono
                        font.pixelSize: 14
                        color: row.active ? Colors.textOnAccent : Colors.textSecondary
                    }

                    Text {
                        anchors.left: glyph.right
                        anchors.leftMargin: Theme.space12
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, badge.x - Theme.space8 - x)
                        elide: Text.ElideRight
                        text: modelData.label
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: row.active ? Font.DemiBold : Font.Normal
                        color: row.active ? Colors.textOnAccent : Colors.textSecondary
                    }

                    // Count badge — the section's real app count.
                    Rectangle {
                        id: badge
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.space12
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(22, badgeText.width + 12)
                        height: 18
                        radius: 9
                        color: row.active ? Qt.rgba(1, 1, 1, 0.24) : Colors.glassCard
                        border.width: row.active ? 0 : 1
                        border.color: Colors.borderSubtle

                        Text {
                            id: badgeText
                            anchors.centerIn: parent
                            text: String(row.count)
                            font.family: Theme.fontUi
                            font.pixelSize: 10
                            font.weight: Font.Medium
                            color: row.active ? Colors.textOnAccent : Colors.textMuted
                        }
                    }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: LauncherModel.setSection(modelData.id)
                    }
                }
            }
        }
    }
}
