import QtQuick
import "../../../common"
import "../../../common/components/" as Comp
import "../../../services"

// VOID SHELL — `@git` repository browser (PRD §28). Serves the cached
// repository index (never a rescan per keystroke), shows a lightweight
// clean/dirty/unknown status dot from a batched status pass, and offers
// open-folder / open-terminal actions only when those openers exist.
Item {
    id: root

    property string query: ""

    readonly property var shown: GitService.search(root.query)

    width: parent ? parent.width : 560
    implicitHeight: body.implicitHeight + Theme.space8

    Component.onCompleted: GitService.ensureLoaded()

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
                        text: "@git"
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                        color: Colors.accentLight
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Repositories"
                    font.family: Theme.fontUi
                    font.weight: Font.DemiBold
                    font.pixelSize: 14
                    color: Colors.textPrimary
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: GitService.loaded && !GitService.busy && root.shown.length > 0
                    text: root.shown.length + " · " + GitService.dirtyCount + " dirty"
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    color: Colors.textMuted
                }

                Comp.IconButton {
                    icon: String.fromCodePoint(0xF0450) // md-refresh
                    iconSize: 14
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: GitService.gitAvailable && !GitService.busy
                    opacity: enabled ? 1 : 0.4
                    onClicked: GitService.refresh()

                    RotationAnimation on rotation {
                        running: GitService.busy
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 900
                    }
                }
            }
        }

        // --- Body states ------------------------------------------------
        Comp.EmptyState {
            width: parent.width
            visible: !GitService.gitAvailable
            glyph: String.fromCodePoint(0xEC6F)
            title: "Git is not installed"
            body: "Install git to browse repositories from the launcher."
        }

        Comp.EmptyState {
            width: parent.width
            visible: GitService.gitAvailable && GitService.busy && !GitService.loaded
            busy: true
            title: "Scanning repository roots"
            body: GitService.roots.join(" · ")
        }

        Comp.EmptyState {
            width: parent.width
            visible: GitService.gitAvailable && GitService.loaded && !GitService.busy && root.shown.length === 0
            glyph: String.fromCodePoint(0xEC6F)
            title: root.query !== "" && GitService.repos.length > 0 ? "No repositories match" : "No repositories found"
            body: root.query !== "" && GitService.repos.length > 0 ? "Clear the search to see all " + GitService.repos.length + " repositories." : "Searched: " + GitService.roots.join(" · ") + ". Create ~/.local/share/voidshell/git-roots.json to configure your own roots."
        }

        // --- Repository list --------------------------------------------
        Flickable {
            width: parent.width
            height: Math.min(contentHeight, 440)
            visible: root.shown.length > 0
            contentHeight: repoColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: repoColumn
                width: parent.width
                spacing: 4

                Repeater {
                    model: root.shown
                    delegate: Rectangle {
                        required property var modelData
                        readonly property var repo: modelData
                        width: repoColumn.width
                        height: 48
                        radius: Theme.radiusSm
                        color: repoArea.containsMouse ? Colors.glassCard : "transparent"
                        border.width: 1
                        border.color: repoArea.containsMouse ? Colors.borderSubtle : "transparent"

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space12
                            anchors.rightMargin: Theme.space8
                            spacing: Theme.space12

                            // Status dot: clean / dirty / unknown
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8
                                height: 8
                                radius: 4
                                color: repo.status === "clean" ? Colors.success : (repo.status === "dirty" ? Colors.warning : Colors.textDisabled)
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 8 - Theme.space12 - 88
                                spacing: 1

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: repo.name
                                    font.family: Theme.fontUi
                                    font.weight: Font.Medium
                                    font.pixelSize: 13
                                    color: Colors.textPrimary
                                }

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: repo.path
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                    color: Colors.textMuted
                                }
                            }

                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8
                                height: 1
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: repo.status === "unknown" ? "unknown" : repo.status
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                                color: repo.status === "clean" ? Colors.success : (repo.status === "dirty" ? Colors.warning : Colors.textDisabled)
                            }

                            Comp.IconButton {
                                visible: GitService.folderAvailable
                                icon: String.fromCodePoint(0xF07C) // fa-folder_open
                                iconSize: 13
                                anchors.verticalCenter: parent.verticalCenter
                                onClicked: HyprlandService.execShell("xdg-open " + HyprlandService.shQuote(repo.path))
                            }

                            Comp.IconButton {
                                visible: GitService.terminalAvailable
                                icon: String.fromCodePoint(0xF120) // fa-terminal
                                iconSize: 13
                                anchors.verticalCenter: parent.verticalCenter
                                onClicked: HyprlandService.execShell("kitty -d " + HyprlandService.shQuote(repo.path))
                            }
                        }

                        MouseArea {
                            id: repoArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }
                    }
                }
            }
        }

        // --- Footer note -------------------------------------------------
        Text {
            width: parent.width
            visible: GitService.loaded && GitService.repos.length > 0
            text: GitService.scannedAt > 0 ? "Index cached " + relativeTime(GitService.scannedAt) + " · refresh rescans configured roots" : "Index built from configured roots"
            font.family: Theme.fontUi
            font.pixelSize: 10
            color: Colors.textDisabled
        }
    }

    function relativeTime(ms) {
        const secs = Math.max(0, Math.floor((Date.now() - ms) / 1000));
        if (secs < 60) return secs + "s ago";
        const mins = Math.floor(secs / 60);
        if (mins < 60) return mins + "m ago";
        const hours = Math.floor(mins / 60);
        if (hours < 24) return hours + "h ago";
        return Math.floor(hours / 24) + "d ago";
    }
}
