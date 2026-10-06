import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Wayland
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — Bluetooth device context menu: opens on right-click
// (two-finger tap on a touchpad) over a paired/saved device row in the
// quick-settings dropdown, positioned at the pointer like the Windows
// device menu.
//
// The window covers the whole output transparently so the first click
// anywhere outside the card dismisses the menu (the dismissing click is
// consumed by this surface — one swallowed click, the standard Wayland
// compromise for a click-outside catcher). Escape and every action also
// dismiss, and QuickSettings reclaims panel focus afterwards.
//
// Actions are exactly what BluetoothDevice exposes — connect/disconnect,
// block/unblock, forget — with forget gated behind an in-place two-step
// confirm. No pairing entry: quickshell registers no BlueZ agent, so a
// Pair button would promise a confirmation flow that cannot happen
// (PRD 17.3). Unpaired rows therefore never open this menu at all.
PanelWindow {
    id: root

    property var device: null
    // Pointer position in output-local logical pixels; QuickSettings
    // resolves it from hyprctl before assigning the device.
    property int atX: 0
    property int atY: 0

    readonly property bool open: root.device !== null

    // Estimated card size — used to keep the card on-screen before its
    // real height is known (single head: origin 0,0).
    readonly property int cardW: 216
    readonly property int cardH: 220

    signal dismissed

    visible: root.open && PopupManager.isOpen("quickSettings")
    screen: PopupManager.activeScreen !== null ? PopupManager.activeScreen : PopupManager.fallbackScreen
    color: "transparent"
    WlrLayershell.namespace: "voidshell-popup"
    // Keyboard while open so Escape dismisses the menu (default is None).
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusiveZone: -1

    // Full output: the transparent catcher fills the screen; the card
    // floats inside it at the pointer.
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    margins {
        top: 0
        bottom: 0
        left: 0
        right: 0
    }

    // Escape dismisses just the menu — the panel's own handler is held
    // off while this window is up (see QuickSettings).
    Shortcut {
        enabled: root.visible
        context: Qt.ApplicationShortcut
        sequences: [StandardKey.Cancel]
        onActivated: root.dismiss()
    }

    Item {
        id: escGrab
        anchors.fill: parent
        focus: root.visible
    }

    onVisibleChanged: {
        if (visible) {
            escGrab.forceActiveFocus();
        } else if (root.device !== null) {
            root.device = null;
            disarmTimer.stop();
        }
    }

    function dismiss() {
        disarmTimer.stop();
        root.device = null;
        root.dismissed();
    }

    // Same gate as DeviceList.canToggle: only actions that can actually
    // run right now are live; the rest render muted and inert.
    function canAct(dev) {
        if (!dev || !BluetoothService.powered || dev.blocked || dev.pairing) {
            return false;
        }
        if (!dev.paired && !dev.trusted) {
            return false;
        }
        return dev.state !== BluetoothDeviceState.Connecting && dev.state !== BluetoothDeviceState.Disconnecting;
    }

    function stateLabel(dev) {
        if (!dev) {
            return "";
        }
        if (dev.blocked) {
            return "Blocked";
        }
        if (dev.connected) {
            if (dev.batteryAvailable) {
                return "Connected · " + Math.round(dev.battery * 100) + "%";
            }
            return "Connected";
        }
        if (dev.state === BluetoothDeviceState.Connecting) {
            return "Connecting…";
        }
        if (dev.state === BluetoothDeviceState.Disconnecting) {
            return "Disconnecting…";
        }
        return "Saved";
    }

    // Any click outside the card (left or right) dismisses.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.dismiss()
    }

    Comp.GlassPanel {
        id: card
        texture: true
        textureSource: InkArt.sourceFor("deviceMenu")
        width: root.cardW
        height: menuCol.implicitHeight + Theme.space12 * 2
        x: Math.max(8, Math.min(root.atX, root.width - root.cardW - 8))
        y: Math.max(8, Math.min(root.atY, root.height - card.height - 8))

        Column {
            id: menuCol
            width: parent.width
            spacing: 2

            // --- header: device identity + live state (never colour-only) --
            Column {
                width: parent.width
                spacing: 1

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.device ? (root.device.deviceName || root.device.name || root.device.address) : ""
                    font.family: Theme.fontUi
                    font.weight: Font.DemiBold
                    font.pixelSize: 13
                    color: Colors.textPrimary
                }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.stateLabel(root.device)
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    color: Colors.textMuted
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Colors.borderSubtle
            }

            MenuRow {
                width: parent.width
                icon: String.fromCodePoint(root.device && root.device.connected ? 0xF011 : 0xF00E3) // fa-power-off / fa-bolt
                label: root.device && root.device.connected ? "Disconnect" : "Connect"
                available: root.canAct(root.device)
                onTriggered: {
                    if (!root.device) {
                        return;
                    }
                    if (root.device.connected) {
                        root.device.disconnect();
                    } else {
                        root.device.connect();
                    }
                    root.dismiss();
                }
            }

            MenuRow {
                width: parent.width
                icon: String.fromCodePoint(root.device && root.device.blocked ? 0xF00C : 0xF01E) // fa-check / fa-ban
                label: root.device && root.device.blocked ? "Unblock" : "Block"
                available: BluetoothService.powered && !!root.device && !root.device.pairing
                onTriggered: {
                    if (!root.device) {
                        return;
                    }
                    root.device.blocked = !root.device.blocked;
                    root.dismiss();
                }
            }

            MenuRow {
                width: parent.width
                visible: root.device && (root.device.paired || root.device.trusted)
                icon: String.fromCodePoint(0xF1FD) // fa-trash
                label: root.armed ? "Tap again to forget" : "Forget device"
                armed: root.armed
                available: BluetoothService.powered && !!root.device && !root.device.pairing
                onTriggered: {
                    if (!root.armed) {
                        root.armed = true;
                        disarmTimer.start();
                        return;
                    }
                    if (root.device) {
                        root.device.forget();
                    }
                    root.dismiss();
                }
            }
        }
    }

    // Two-step destructive confirm: the armed state expires on its own.
    property bool armed: false

    Timer {
        id: disarmTimer
        interval: 3000
        onTriggered: root.armed = false
    }

    onDeviceChanged: {
        if (root.device !== null) {
            root.armed = false;
        }
    }
}
