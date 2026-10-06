import QtQuick
import "../../../common"
import "../../../common/components/" as Comp
import "../../../services"

// VOID SHELL — `@containers` docker manager (PRD §27). Three tabs
// (Containers / Images / Volumes) over real `docker` CLI output, with
// only the baseline non-destructive actions (start / stop / restart /
// refresh / copy id). Nothing removes containers, images or volumes, and
// no action runs without a direct click. When docker is absent the view
// says so plainly instead of showing an empty list (PRD §37).
Item {
    id: root

    property string query: ""

    width: parent ? parent.width : 560
    implicitHeight: body.implicitHeight + Theme.space8

    readonly property var groups: {
        const out = [];
        const list = DockerService.containers;
        const q = root.query.toLowerCase();
        let current = null;
        for (let i = 0; i < list.length; i++) {
            const c = list[i];
            if (q !== "" && c.name.toLowerCase().indexOf(q) === -1 && c.image.toLowerCase().indexOf(q) === -1 && c.project.toLowerCase().indexOf(q) === -1) {
                continue;
            }
            const g = c.project || "";
            if (!current || current.name !== g) {
                current = { name: g, items: [] };
                out.push(current);
            }
            current.items.push(c);
        }
        return out;
    }

    readonly property int shownContainers: {
        let n = 0;
        for (let i = 0; i < root.groups.length; i++) {
            n += root.groups[i].items.length;
        }
        return n;
    }

    readonly property var shownImages: {
        const q = root.query.toLowerCase();
        if (q === "") return DockerService.images;
        const out = [];
        for (let i = 0; i < DockerService.images.length; i++) {
            const img = DockerService.images[i];
            if ((img.repo + ":" + img.tag).toLowerCase().indexOf(q) !== -1) out.push(img);
        }
        return out;
    }

    readonly property var shownVolumes: {
        const q = root.query.toLowerCase();
        if (q === "") return DockerService.volumes;
        const out = [];
        for (let i = 0; i < DockerService.volumes.length; i++) {
            if (DockerService.volumes[i].name.toLowerCase().indexOf(q) !== -1) out.push(DockerService.volumes[i]);
        }
        return out;
    }

    Component.onCompleted: DockerService.ensureDetected()

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
                        text: "@containers"
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                        color: Colors.accentLight
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Docker"
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
                    visible: DockerService.state === "ready"
                    text: DockerService.runningCount + "/" + DockerService.containers.length + " running"
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    color: Colors.textMuted
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: DockerService.state !== "ready"
                    text: DockerService.state === "checking" ? "checking…" : "unavailable"
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    color: DockerService.state === "checking" ? Colors.textMuted : Colors.warning
                }

                Comp.IconButton {
                    icon: String.fromCodePoint(0xF0450) // md-refresh
                    iconSize: 14
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: DockerService.state === "ready" && !DockerService.loading
                    opacity: enabled ? 1 : 0.4
                    onClicked: DockerService.refresh()

                    RotationAnimation on rotation {
                        running: DockerService.loading
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 900
                    }
                }
            }
        }

        // --- Tabs -------------------------------------------------------
        Row {
            visible: DockerService.state === "ready"
            spacing: Theme.space8

            Repeater {
                model: ["containers", "images", "volumes"]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool activeTab: DockerService.activeTab === modelData
                    width: tabLabel.implicitWidth + Theme.space24
                    height: 28
                    radius: Theme.radiusSm
                    color: activeTab ? Colors.accentStrong : (tabArea.containsMouse ? Colors.glassHover : Colors.glassCard)
                    border.width: 1
                    border.color: activeTab ? Colors.borderAccent : Colors.borderSubtle

                    Text {
                        id: tabLabel
                        anchors.centerIn: parent
                        text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                        font.family: Theme.fontUi
                        font.weight: Font.Medium
                        font.pixelSize: 12
                        color: parent.activeTab ? Colors.textOnAccent : Colors.textSecondary
                    }

                    MouseArea {
                        id: tabArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: DockerService.refresh(modelData)
                    }
                }
            }
        }

        // --- Unavailable / checking states ------------------------------
        Comp.EmptyState {
            width: parent.width
            visible: DockerService.state === "checking"
            busy: true
            title: "Contacting Docker"
            body: "Checking for the docker CLI and a reachable daemon."
        }

        Comp.EmptyState {
            width: parent.width
            visible: DockerService.state === "unavailable"
            glyph: String.fromCodePoint(0xF21F) // fa-docker
            title: "Docker unavailable"
            body: DockerService.reason
        }

        // --- Containers tab ---------------------------------------------
        Comp.EmptyState {
            width: parent.width
            visible: DockerService.state === "ready" && DockerService.activeTab === "containers" && !DockerService.loading && root.shownContainers === 0
            glyph: String.fromCodePoint(0xF21F)
            title: root.query !== "" ? "No containers match" : "No containers"
            body: root.query !== "" ? "Clear the search to see every container." : "docker ps reported no containers on this system."
        }

        Column {
            width: parent.width
            spacing: Theme.space8
            visible: DockerService.state === "ready" && DockerService.activeTab === "containers" && root.shownContainers > 0

            Repeater {
                model: root.groups
                delegate: Column {
                    required property var modelData
                    readonly property var group: modelData
                    width: parent ? parent.width : body.width
                    spacing: 4

                    Text {
                        visible: group.name !== ""
                        text: group.name
                        font.family: Theme.fontUi
                        font.weight: Font.DemiBold
                        font.pixelSize: 11
                        color: Colors.textMuted
                        topPadding: 6
                    }

                    Repeater {
                        model: group.items
                        delegate: Rectangle {
                            required property var modelData
                            readonly property var container: modelData
                            readonly property bool running: container.state === "running"
                            width: parent ? parent.width : body.width
                            height: 52
                            radius: Theme.radiusSm
                            color: Colors.glassCard
                            border.width: 1
                            border.color: Colors.borderSubtle

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.space12
                                anchors.rightMargin: Theme.space8
                                spacing: Theme.space12

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: container.state === "running" ? Colors.success : (container.state === "exited" || container.state === "created" ? Colors.textDisabled : Colors.warning)
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 8 - Theme.space12 - actionRow.width - Theme.space12
                                    spacing: 1

                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: container.name
                                        font.family: Theme.fontUi
                                        font.weight: Font.Medium
                                        font.pixelSize: 13
                                        color: Colors.textPrimary
                                    }

                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: container.status + (container.ports !== "" ? "  ·  " + container.ports : "") + (container.image !== "" ? "  ·  " + container.image : "")
                                        font.family: Theme.fontMono
                                        font.pixelSize: 10
                                        color: Colors.textMuted
                                    }
                                }

                                Row {
                                    id: actionRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4

                                    Comp.IconButton {
                                        visible: !container.running
                                        icon: String.fromCodePoint(0xF04B) // fa-play
                                        iconSize: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        enabled: !DockerService.acting
                                        opacity: enabled ? 1 : 0.4
                                        onClicked: DockerService.startContainer(container.name)
                                    }

                                    Comp.IconButton {
                                        visible: container.running
                                        icon: String.fromCodePoint(0xF04D) // fa-stop
                                        iconSize: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        enabled: !DockerService.acting
                                        opacity: enabled ? 1 : 0.4
                                        onClicked: DockerService.stopContainer(container.name)
                                    }

                                    Comp.IconButton {
                                        visible: container.running
                                        icon: String.fromCodePoint(0xF021) // fa-refresh
                                        iconSize: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        enabled: !DockerService.acting
                                        opacity: enabled ? 1 : 0.4
                                        onClicked: DockerService.restartContainer(container.name)
                                    }

                                    Comp.IconButton {
                                        visible: DockerService.copyAvailable
                                        icon: String.fromCodePoint(0xF24D) // fa-clone (copy)
                                        iconSize: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        onClicked: {
                                            HyprlandService.execShell("echo -n " + HyprlandService.shQuote(container.id) + " | wl-copy");
                                            ToastService.push("Container ID copied", container.id, "", "info");
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // --- Images tab --------------------------------------------------
        Comp.EmptyState {
            width: parent.width
            visible: DockerService.state === "ready" && DockerService.activeTab === "images" && !DockerService.loading && root.shownImages.length === 0
            glyph: String.fromCodePoint(0xF1B2) // fa-cube
            title: root.query !== "" ? "No images match" : "No images"
            body: root.query !== "" ? "Clear the search to see every image." : "docker reported no images on this system."
        }

        Column {
            width: parent.width
            spacing: 4
            visible: DockerService.state === "ready" && DockerService.activeTab === "images" && root.shownImages.length > 0

            Repeater {
                model: root.shownImages
                delegate: Rectangle {
                    required property var modelData
                    readonly property var img: modelData
                    width: body.width
                    height: 44
                    radius: Theme.radiusSm
                    color: Colors.glassCard
                    border.width: 1
                    border.color: Colors.borderSubtle

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space12
                        anchors.rightMargin: Theme.space12
                        spacing: Theme.space12

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: String.fromCodePoint(0xF1B2)
                            font.family: Theme.fontMono
                            font.pixelSize: 13
                            color: Colors.accentLight
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 16 - Theme.space12 - 160
                            elide: Text.ElideRight
                            text: img.repo + ":" + img.tag
                            font.family: Theme.fontUi
                            font.weight: Font.Medium
                            font.pixelSize: 13
                            color: Colors.textPrimary
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: img.size + (img.created !== "" ? " · " + img.created : "")
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            color: Colors.textMuted
                        }
                    }
                }
            }
        }

        // --- Volumes tab -------------------------------------------------
        Comp.EmptyState {
            width: parent.width
            visible: DockerService.state === "ready" && DockerService.activeTab === "volumes" && !DockerService.loading && root.shownVolumes.length === 0
            glyph: String.fromCodePoint(0xF1C0) // fa-database
            title: root.query !== "" ? "No volumes match" : "No volumes"
            body: root.query !== "" ? "Clear the search to see every volume." : "docker reported no volumes on this system."
        }

        Column {
            width: parent.width
            spacing: 4
            visible: DockerService.state === "ready" && DockerService.activeTab === "volumes" && root.shownVolumes.length > 0

            Repeater {
                model: root.shownVolumes
                delegate: Rectangle {
                    required property var modelData
                    readonly property var vol: modelData
                    width: body.width
                    height: 44
                    radius: Theme.radiusSm
                    color: Colors.glassCard
                    border.width: 1
                    border.color: Colors.borderSubtle

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space12
                        anchors.rightMargin: Theme.space12
                        spacing: Theme.space12

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: String.fromCodePoint(0xF1C0)
                            font.family: Theme.fontMono
                            font.pixelSize: 13
                            color: Colors.accentLight
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 16 - Theme.space12 - 140
                            elide: Text.ElideRight
                            text: vol.name
                            font.family: Theme.fontUi
                            font.weight: Font.Medium
                            font.pixelSize: 13
                            color: Colors.textPrimary
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: vol.driver + (vol.scope !== "" ? " · " + vol.scope : "")
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            color: Colors.textMuted
                        }
                    }
                }
            }
        }

        // --- Footer ------------------------------------------------------
        Text {
            width: parent.width
            visible: DockerService.state === "ready" && DockerService.lastError !== ""
            text: DockerService.lastError
            font.family: Theme.fontUi
            font.pixelSize: 10
            color: Colors.warning
        }
    }
}
