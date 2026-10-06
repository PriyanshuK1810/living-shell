import QtQuick
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — expanded workspace view (Shadow Spaces plan §5).
//
// The detail surface behind a card's expand affordance: every window of
// one workspace as a large real preview, in the compositor's focus
// order, with its title underneath (labels belong here — this is the
// detail view, not the label-free card strip). Previews take the live
// slots first (`priority: 0`); windows that must not be captured keep
// the neutral lock plate and are labelled by class instead of title.
//
// Click a preview → focus that window (the overview closes), the back
// button or the backdrop → cards, Escape → cards first, then close.
Item {
    id: root

    property var ws: null

    signal closeRequested()
    signal windowFocused(var toplevel)

    readonly property bool urgentWs: root.ws !== null && root.ws.urgent
    readonly property int windowCount: {
        HyprlandService.eventSerial;
        return root.ws === null ? 0 : HyprlandService.windowCountOf(root.ws);
    }
    readonly property var windows: {
        HyprlandService.eventSerial;
        return root.ws === null ? [] : HyprlandService.orderedWindows(root.ws);
    }

    visible: root.ws !== null
    // Two columns on narrow panels, three once there is room. Sized from
    // the panel (not the screen) so the grid always fits inside it.
    readonly property int columns: panel.width >= 900 ? 3 : 2
    readonly property int cellW: Math.max(160, Math.floor((panel.width - 32 - (columns - 1) * 16) / columns))
    readonly property int cellMaxH: 208

    // Sensitive windows are labelled by class — the title of an excluded
    // window is exactly the thing the exclusion is meant to spare.
    function labelFor(toplevel) {
        if (toplevel === null) {
            return "";
        }
        if (HyprlandService.isSensitiveWindow(toplevel)) {
            const cls = HyprlandService.windowClass(toplevel);
            return cls !== "" ? cls + " · hidden" : "Hidden";
        }
        const title = HyprlandService.titleForWindow(toplevel);
        if (title !== "") {
            return title;
        }
        return HyprlandService.windowClass(toplevel);
    }

    // --- backdrop --------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(8 / 255, 6 / 255, 13 / 255, 0.94)

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeRequested()
        }
    }

    // --- panel -----------------------------------------------------------
    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(1000, parent.width - 64)
        // Fits its content up to the scroll cap: one window doesn't get
        // a wall of empty glass, twenty still scroll inside 660.
        height: Math.min(660, Math.max(240, 72 + flow.implicitHeight + 32))
        radius: Theme.radiusXl
        color: Colors.glassElevated
        border.width: 1
        border.color: Colors.borderSubtle

        // ---- header -----------------------------------------------------
        Item {
            id: header
            x: 16
            y: 14
            width: panel.width - 32
            height: 30

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Comp.IconButton {
                    width: 28
                    height: 28
                    iconSize: 12
                    icon: String.fromCodePoint(0xF060) // fa-arrow-left
                    onClicked: root.closeRequested()
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: badgeText.implicitWidth + 16
                    height: 24
                    radius: 6
                    color: Colors.glassPressed
                    border.width: 1
                    border.color: root.urgentWs ? Colors.danger : Colors.borderSubtle

                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: root.ws !== null ? String(root.ws.name) : ""
                        font.family: Theme.fontMono
                        font.weight: Font.DemiBold
                        font.pixelSize: 14
                        color: Colors.textPrimary
                    }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.windowCount > 0
                    width: countText.implicitWidth + 12
                    height: 20
                    radius: 10
                    color: Colors.glassPressed
                    border.width: 1
                    border.color: Colors.borderSubtle

                    Text {
                        id: countText
                        anchors.centerIn: parent
                        text: root.windowCount + (root.windowCount === 1 ? " window" : " windows")
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                        color: Colors.textMuted
                    }
                }
            }

            Comp.IconButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                height: 28
                iconSize: 12
                icon: String.fromCodePoint(0xF00D) // fa-xmark
                onClicked: root.closeRequested()
            }
        }

        // ---- window grid ------------------------------------------------
        Flickable {
            id: flick
            x: 16
            y: 56
            width: panel.width - 32
            height: panel.height - 72
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: flow.implicitHeight
            flickableDirection: Flickable.VerticalFlick

            Flow {
                id: flow
                width: flick.width
                spacing: 16

                Repeater {
                    model: root.windows

                    Item {
                        required property var modelData
                        required property int index

                        width: root.cellW
                        height: fit.height + 26

                        readonly property size fit: HyprlandService.fitWindow(modelData, root.cellW, root.cellMaxH)

                        WindowPreview {
                            width: parent.fit.width
                            height: parent.fit.height
                            toplevel: parent.modelData
                            priority: 0
                            // The expanded view covers the strip, so
                            // there is nothing to drop onto from here.
                            draggable: false
                            onFocused: tl => root.windowFocused(tl)
                        }

                        // Title under the preview (detail view).
                        Text {
                            anchors.top: parent.top
                            anchors.topMargin: parent.fit.height + 6
                            width: parent.width
                            height: 20
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                            text: root.labelFor(parent.modelData)
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                            color: HyprlandService.isSensitiveWindow(parent.modelData) ? Colors.textMuted : Colors.textSecondary
                        }
                    }
                }

                // Honest empty state (PRD 37) — no placeholder windows.
                Text {
                    visible: root.windowCount === 0
                    width: flick.width
                    height: 60
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: "No windows on this workspace"
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    color: Colors.textDisabled
                }
            }
        }
    }
}
