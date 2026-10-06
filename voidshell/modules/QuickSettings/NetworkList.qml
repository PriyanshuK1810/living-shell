import QtQuick
import Quickshell.Networking
import "../../common"
import "../../services"

// VOID SHELL — quick-settings Wi-Fi dropdown: drops straight down from
// the Wi-Fi tile and lists what the device can see — the current
// connection first, then saved networks, then the rest by strength
// (ordering comes from NetworkService.visibleNetworks). A scan is kept
// alive only while this list is open and the panel is visible (PRD 36).
//
// The expanded box is FIXED: five row slots (5×44 + 4×2 = 228px of
// viewport) plus the header, sized once when the accordion opens. Scan
// batches re-render inside it — they never resize the card, the window,
// or each other — so the panel can't jitter while results stream in, and
// a row can't be clipped mid-height (the old 224px cap ended 4px into
// row five). Beyond five rows a scrollbar appears in the right gutter;
// it drags and tracks the flick.
//
// Rows the shell can join act on click: saved/open networks connect
// directly, PSK-typed unsaved ones open the password dialog (signal
// `pskRequested`). Enterprise/WEP rows stay inert with an honest reason —
// no button that cannot work (PRD 17.3).
Rectangle {
    id: root

    property bool expanded: false

    // Emits with the WifiNetwork entry when a "Needs password" row is
    // clicked; QuickSettings owns the dialog.
    signal pskRequested(var net)

    // Fixed geometry — a constant by design (see header comment).
    readonly property int viewportH: 5 * 44 + 4 * 2 // five rows, four gaps
    readonly property int contentH: Theme.space8 + 18 + Theme.space4 + root.viewportH + Theme.space16

    // Only expand/collapse animates; content changes (scan batches,
    // signal ticks) re-render in place and can never retarget the box.
    property real displayH: 0

    // While a transition runs the popup holds its size for it (see
    // QuickSettings.setMenu); this flag is what tells it when to settle.
    readonly property bool animating: hAnim.running

    width: parent ? parent.width : 368
    implicitHeight: height
    height: root.displayH
    clip: true
    radius: Theme.radiusMd
    color: Colors.glassCard
    border.width: 1
    border.color: Colors.borderSubtle

    onExpandedChanged: {
        hAnim.stop();
        hAnim.to = root.expanded ? root.contentH : 0;
        hAnim.start();
        if (!root.expanded) {
            list.contentY = 0;
        }
    }

    Component.onCompleted: root.displayH = root.expanded ? root.contentH : 0

    NumberAnimation {
        id: hAnim
        target: root
        property: "displayH"
        duration: Theme.durationNormal
        easing.type: Easing.OutCubic
    }

    // The subtitle also spells out why a secured row is inert when no PSK
    // prompt could satisfy it (enterprise or WEP — PRD 17.3).
    function joinLabel(net) {
        if (!net) {
            return "";
        }
        const n = net.network;
        const sig = Math.round(net.strength) + "%";
        if (net.connected) {
            return "Connected · " + sig;
        }
        if (n.state === ConnectionState.Connecting) {
            return "Connecting…";
        }
        if (n.state === ConnectionState.Disconnecting) {
            return "Disconnecting…";
        }
        if (net.known) {
            return "Saved · " + sig;
        }
        if (n.security === WifiSecurityType.Open || n.security === WifiSecurityType.Owe) {
            return "Open · " + sig;
        }
        if (NetworkService.needsPsk(net)) {
            return "Needs password";
        }
        const sec = n.security;
        if (sec === WifiSecurityType.WpaEap || sec === WifiSecurityType.Wpa2Eap || sec === WifiSecurityType.DynamicWep || sec === WifiSecurityType.Leap) {
            return "Enterprise · unsupported";
        }
        return "Secured · unsupported";
    }

    Column {
        id: body
        width: parent.width - Theme.space16
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Theme.space8
        spacing: Theme.space4

        // --- header: label + live scan state ------------------------------
        Item {
            width: parent.width
            height: 18

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "NETWORKS"
                font.family: Theme.fontUi
                font.weight: Font.DemiBold
                font.pixelSize: 10
                font.letterSpacing: 1.2
                color: Colors.textMuted
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    height: 18
                    verticalAlignment: Text.AlignVCenter
                    visible: NetworkService.scanning
                    text: String.fromCodePoint(0xF110) // fa-spinner
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                    color: Colors.textMuted

                    RotationAnimation on rotation {
                        running: NetworkService.scanning
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 900
                    }
                }

                Text {
                    height: 18
                    verticalAlignment: Text.AlignVCenter
                    text: NetworkService.scanning ? "Scanning…" : NetworkService.visibleNetworks.length + " networks"
                    font.family: Theme.fontUi
                    font.pixelSize: 10
                    color: Colors.textMuted
                }
            }
        }

        // --- fixed viewport: states and rows share these five slots -------
        Item {
            id: viewport
            width: parent.width
            height: root.viewportH

            // --- empty states (radio off / looking / none) ---------------
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                topPadding: Theme.space4
                bottomPadding: Theme.space4
                text: "Radio off — turn Wi-Fi on from the tile above"
                font.family: Theme.fontUi
                font.pixelSize: 11
                color: Colors.textMuted
                visible: NetworkService.wifiPresent && !NetworkService.wifiEnabled
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                topPadding: Theme.space4
                bottomPadding: Theme.space4
                text: "Looking for networks…"
                font.family: Theme.fontUi
                font.pixelSize: 11
                color: Colors.textMuted
                visible: NetworkService.wifiEnabled && NetworkService.scanning && NetworkService.visibleNetworks.length === 0
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                topPadding: Theme.space4
                bottomPadding: Theme.space4
                text: "No networks found"
                font.family: Theme.fontUi
                font.pixelSize: 11
                color: Colors.textMuted
                visible: NetworkService.wifiEnabled && !NetworkService.scanning && NetworkService.visibleNetworks.length === 0
            }

            // --- the list: always the full viewport, flicking inside it ---
            Flickable {
                id: list
                anchors.fill: parent
                contentWidth: width
                contentHeight: netCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: NetworkService.wifiEnabled && NetworkService.visibleNetworks.length > 0

                Column {
                    id: netCol
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: NetworkService.visibleNetworks.length

                        LinkRow {
                            width: netCol.width
                            // Index-driven on purpose: every signal tick or
                            // scan batch re-evaluates visibleNetworks into a
                            // fresh array, and an array model resets the whole
                            // Repeater — measured as ~6 ms inline stalls per
                            // tick. With an index model only a count change
                            // creates or destroys a row; content changes
                            // re-bind in place.
                            readonly property var net: {
                                const listRef = NetworkService.visibleNetworks;
                                return index < listRef.length ? listRef[index] : null;
                            }
                            icon: String.fromCodePoint(0xF05A9) // mdi-wifi
                            title: net ? net.name : ""
                            subtitle: root.joinLabel(net)
                            active: net ? net.connected : false
                            interactive: NetworkService.canConnect(net) || NetworkService.needsPsk(net)
                            trailIcon: {
                                if (!net) {
                                    return "";
                                }
                                if (net.connected) {
                                    return String.fromCodePoint(0xF00C); // fa-check
                                }
                                if (net.network.stateChanging) {
                                    return "";
                                }
                                if (NetworkService.canConnect(net) || NetworkService.needsPsk(net)) {
                                    return String.fromCodePoint(0xF054); // fa-chevron-right
                                }
                                return String.fromCodePoint(0xF023); // fa-lock
                            }
                            trailColor: net && net.connected ? Colors.accentLight : Colors.textMuted
                            onTriggered: {
                                if (!net) {
                                    return;
                                }
                                if (NetworkService.needsPsk(net)) {
                                    // The dialog wants the WifiNetwork
                                    // itself — that's where security,
                                    // stateChanging and connectWithPsk
                                    // live — not the list entry.
                                    root.pskRequested(net.network);
                                } else {
                                    NetworkService.connect(net);
                                }
                            }
                        }
                    }
                }
            }

            // --- scrollbar: visible only when content overflows -----------
            Item {
                id: sbar
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 8
                visible: list.visible && list.contentHeight > list.height + 1

                Rectangle {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 3
                    radius: 2
                    color: Colors.borderSubtle
                }

                Rectangle {
                    id: sHandle
                    width: 3
                    radius: 2
                    color: Colors.textMuted
                    opacity: sbarArea.containsMouse || sbarArea.pressed ? 0.9 : 0.5
                    height: Math.max(20, list.height / list.contentHeight * sbar.height)
                    y: {
                        const scrollable = list.contentHeight - list.height;
                        const usable = sbar.height - height;
                        return scrollable > 0 && usable > 0 ? (list.contentY / scrollable) * usable : 0;
                    }
                }

                // Drag anywhere on the track: jump-to-point on press,
                // proportional tracking while held.
                MouseArea {
                    id: sbarArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    property real grabY: 0
                    property real grabContentY: 0
                    onPressed: mouse => {
                        const scrollable = list.contentHeight - list.height;
                        const usable = Math.max(1, sbar.height - sHandle.height);
                        grabY = mouse.y;
                        list.contentY = Math.max(0, Math.min(scrollable, (mouse.y - sHandle.height / 2) / usable * scrollable));
                        grabContentY = list.contentY;
                    }
                    onPositionChanged: mouse => {
                        if (!pressed) {
                            return;
                        }
                        const scrollable = list.contentHeight - list.height;
                        const usable = Math.max(1, sbar.height - sHandle.height);
                        list.contentY = Math.max(0, Math.min(scrollable, grabContentY + (mouse.y - grabY) / usable * scrollable));
                    }
                }
            }
        }
    }
}
