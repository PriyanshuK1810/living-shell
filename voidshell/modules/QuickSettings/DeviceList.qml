import QtQuick
import Quickshell.Bluetooth
import "../../common"
import "../../services"

// VOID SHELL — quick-settings Bluetooth dropdown: drops down from the
// Bluetooth tile with the connected device first, then saved ones, then
// whatever discovery finds (BluetoothService.sortedDevices). Discovery
// runs only while this list is open and the panel is visible (PRD 36).
//
// The expanded box is FIXED like the Wi-Fi list — five row slots sized
// once when the accordion opens, discovery re-rendering inside them, and
// a scrollbar in the right gutter past five rows — so the panel never
// resizes while devices are being scanned and rows never clip mid-height.
//
// Unpaired devices are listed but inert with "Not paired" — pairing
// needs a confirmation flow the shell does not implement, so there is
// no button to pretend with (PRD 17.3). Paired/saved rows are `menuable`:
// right-click (two-finger tap) opens the device context menu with the
// real actions — connect/disconnect, block/unblock, forget.
Rectangle {
    id: root

    property bool expanded: false

    // The row's address travels up; QuickSettings resolves the device and
    // positions the menu at the pointer.
    signal contextRequested(string address)

    readonly property int viewportH: 5 * 44 + 4 * 2 // five rows, four gaps
    readonly property int contentH: Theme.space8 + 18 + Theme.space4 + root.viewportH + Theme.space16

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

    // BlueZ icon name → a glyph verified to exist in the nerd font;
    // anything unrecognised falls back to the generic Bluetooth mark
    // rather than guessing an icon that might not be there.
    function deviceGlyph(icon) {
        if (icon === "audio-headset" || icon === "audio-headphones") {
            return String.fromCodePoint(0xF025); // fa-headphones
        }
        if (icon === "phone") {
            return String.fromCodePoint(0xF095); // fa-phone
        }
        if (icon === "laptop") {
            return String.fromCodePoint(0xF109); // fa-laptop
        }
        if (icon === "desktop" || icon === "computer") {
            return String.fromCodePoint(0xF108); // fa-desktop
        }
        if (icon && icon.indexOf("game") !== -1) {
            return String.fromCodePoint(0xF11B); // fa-gamepad
        }
        return String.fromCodePoint(0xF00AF); // mdi-bluetooth
    }

    function deviceState(device) {
        if (!device) {
            return "";
        }
        if (device.blocked) {
            return "Blocked";
        }
        if (device.pairing) {
            return "Pairing…";
        }
        if (device.connected) {
            if (device.batteryAvailable) {
                return "Connected · " + Math.round(device.battery * 100) + "%";
            }
            return "Connected";
        }
        if (device.state === BluetoothDeviceState.Connecting) {
            return "Connecting…";
        }
        if (device.state === BluetoothDeviceState.Disconnecting) {
            return "Disconnecting…";
        }
        if (device.paired || device.trusted) {
            return "Saved";
        }
        return "Not paired";
    }

    // Same policy as the row's interactivity — connected devices can be
    // dropped, saved ones connected, everything else stays inert. The
    // context menu is offered on the same paired/saved set: there is no
    // pairing action to put in it (no agent flow), so an unpaired row
    // would only ever contain dead entries.
    function canToggle(device) {
        if (!device) {
            return false;
        }
        if (!BluetoothService.powered || device.blocked || device.pairing) {
            return false;
        }
        if (!device.paired && !device.trusted) {
            return false;
        }
        return device.state !== BluetoothDeviceState.Connecting && device.state !== BluetoothDeviceState.Disconnecting;
    }

    function menuable(device) {
        return !!device && (device.paired || device.trusted);
    }

    Column {
        id: body
        width: parent.width - Theme.space16
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Theme.space8
        spacing: Theme.space4

        // --- header: label + live discovery state -------------------------
        Item {
            width: parent.width
            height: 18

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "DEVICES"
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
                    visible: BluetoothService.discovering
                    text: String.fromCodePoint(0xF110) // fa-spinner
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                    color: Colors.textMuted

                    RotationAnimation on rotation {
                        running: BluetoothService.discovering
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 900
                    }
                }

                Text {
                    height: 18
                    verticalAlignment: Text.AlignVCenter
                    text: BluetoothService.discovering ? "Searching…" : BluetoothService.deviceCount + " devices"
                    font.family: Theme.fontUi
                    font.pixelSize: 10
                    color: Colors.textMuted
                }
            }
        }

        // --- fixed viewport: states and rows share these five slots ---------
        Item {
            id: viewport
            width: parent.width
            height: root.viewportH

            // --- adapter states --------------------------------------------
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                topPadding: Theme.space4
                bottomPadding: Theme.space4
                text: BluetoothService.statusLabel
                font.family: Theme.fontUi
                font.pixelSize: 11
                color: Colors.textMuted
                visible: !BluetoothService.available
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                topPadding: Theme.space4
                bottomPadding: Theme.space4
                text: "Bluetooth is off — turn it on from the tile above"
                font.family: Theme.fontUi
                font.pixelSize: 11
                color: Colors.textMuted
                visible: BluetoothService.available && !BluetoothService.powered
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                topPadding: Theme.space4
                bottomPadding: Theme.space4
                text: "Searching for devices…"
                font.family: Theme.fontUi
                font.pixelSize: 11
                color: Colors.textMuted
                visible: BluetoothService.powered && BluetoothService.discovering && BluetoothService.sortedDevices.length === 0
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                topPadding: Theme.space4
                bottomPadding: Theme.space4
                text: "No devices found"
                font.family: Theme.fontUi
                font.pixelSize: 11
                color: Colors.textMuted
                visible: BluetoothService.powered && !BluetoothService.discovering && BluetoothService.sortedDevices.length === 0
            }

            // --- the list: always the full viewport, flicking inside it -----
            Flickable {
                id: list
                anchors.fill: parent
                contentWidth: width
                contentHeight: devCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: BluetoothService.powered && BluetoothService.sortedDevices.length > 0

                Column {
                    id: devCol
                    width: parent.width
                    spacing: 2

                    Repeater {
                        // Index-driven like the Wi-Fi list: discovery adding a
                        // device (or a name/battery notify re-sorting the list)
                        // used to reset the whole Repeater and rebuild every
                        // row; now only a count change touches delegates.
                        model: BluetoothService.sortedDevices.length

                        LinkRow {
                            width: devCol.width
                            readonly property var dev: {
                                const listRef = BluetoothService.sortedDevices;
                                return index < listRef.length ? listRef[index] : null;
                            }
                            icon: root.deviceGlyph(dev ? dev.icon : "")
                            title: dev ? (dev.deviceName || dev.name || dev.address) : ""
                            subtitle: root.deviceState(dev)
                            active: dev ? dev.connected : false
                            interactive: root.canToggle(dev)
                            menuable: root.menuable(dev)
                            trailIcon: {
                                if (!dev) {
                                    return "";
                                }
                                if (dev.connected) {
                                    return String.fromCodePoint(0xF00C); // fa-check
                                }
                                if (dev.blocked) {
                                    return String.fromCodePoint(0xF023); // fa-lock
                                }
                                if (root.canToggle(dev)) {
                                    return String.fromCodePoint(0xF054); // fa-chevron-right
                                }
                                return "";
                            }
                            trailColor: dev && dev.connected ? Colors.accentLight : Colors.textMuted
                            onTriggered: {
                                if (dev) {
                                    BluetoothService.toggleDevice(dev);
                                }
                            }
                            onContextRequested: {
                                if (dev) {
                                    root.contextRequested(dev.address);
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
