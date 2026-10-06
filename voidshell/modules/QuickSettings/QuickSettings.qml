import QtQuick
import Quickshell
import Quickshell.Io
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — quick settings (PRD 17).
// Composition follows the glassmorphism mockup: header, a 2-tile row
// (Wi-Fi, Bluetooth) over a full-width Airplane tile, a divider, then the
// brightness and volume sliders. Display, Dark Mode, Performance and the
// advanced disclosure were deliberately dropped so the panel is exactly
// those five controls.
//
// Each radio tile carries a chevron that drops down a detail list below
// the tile row — saved and available Wi-Fi networks, paired and discovered
// Bluetooth devices — one list at a time (accordion), so the panel height
// stays bounded. Scanning/discovery is requested only while a list is
// open on a visible panel (PRD 36).
//
// Every control is backed by a real backend or is rendered disabled with
// an accurate reason — no toggle ever flips only its own visual state.
Scope {
    id: root

    // Which detail dropdown is open: "wifi" | "bt" | "".
    property string openMenu: ""

    // Swap which dropdown is open. The popup window is pinned for the
    // transition (PopupShell.heightPin): open pins to the final height so
    // the window grows once up front and the list cascades into it; close
    // and switch pin to the current height and the release below takes the
    // single settling step. That removes the per-frame configure round
    // trips that stretched a 180 ms tween over ~500 ms when every frame
    // resized the layer surface.
    function setMenu(next) {
        const cur = root.openMenu === "wifi" ? wifiList.contentH
            : (root.openMenu === "bt" ? btList.contentH : 0);
        const nxt = next === "wifi" ? wifiList.contentH
            : (next === "bt" ? btList.contentH : 0);
        const base = win.columnHeight;
        root.openMenu = next;
        win.heightPin = Math.max(base - cur + nxt, base);
    }

    // The pin is held while either list is still moving; when both settle
    // the window takes its one sizing step (identical height on open — no
    // configure at all — and the collapse snap on close).
    readonly property bool menusAnimating: wifiList.animating || btList.animating

    onMenusAnimatingChanged: {
        if (!root.menusAnimating && win.heightPin !== -1) {
            win.heightPin = -1;
        }
    }

    // Grow a held pin with content (a scan batch arriving mid-transition)
    // so a stale target can never clip rows that already exist.
    Connections {
        target: win
        function onColumnHeightChanged() {
            if (win.heightPin >= 0 && win.columnHeight > win.heightPin) {
                win.heightPin = win.columnHeight;
            }
        }
    }

    // "Airplane" means the coordinated radios-off state, derived from the
    // real radio switches (the hardware rfkill flag is not required).
    readonly property bool airplaneOn: NetworkService.backendAvailable && !NetworkService.wifiEnabled && (!BluetoothService.available || !BluetoothService.powered)

    Comp.PopupShell {
        id: win
        popupName: "quickSettings"
        texture: true
        textureSource: InkArt.sourceFor("quickSettings")
        panelWidth: 400
        maxHeight: 700
        anchor: "right"
        // Hold the panel's Escape while a transient child surface with
        // its own window-scope handler is up — two matching
        // ApplicationShortcuts are ambiguous and Qt fires neither.
        escapeEnabled: !pwDialog.open && !deviceMenu.open

        Column {
            width: parent.width
            spacing: Theme.space8

            Comp.PopupHeader {
                width: parent.width
                title: "Quick Settings"
                subtitle: {
                    const bits = [];
                    if (NetworkService.connected) {
                        bits.push(NetworkService.wifiConnected ? "Wi-Fi" : "Ethernet");
                    } else {
                        bits.push("Offline");
                    }
                    if (BluetoothService.connectedCount > 0) {
                        bits.push(BluetoothService.connectedCount + " BT");
                    }
                    if (PowerService.hasBattery) {
                        bits.push(PowerService.percentage + "%");
                    }
                    return bits.join(" · ");
                }
                onClosed: PopupManager.closeAll()
            }

            // --- tiles: Wi-Fi + Bluetooth, then full-width Airplane ------
            Column {
                width: parent.width
                spacing: Theme.space8

                Row {
                    width: parent.width
                    spacing: Theme.space8

                    Comp.ToggleTile {
                        width: (parent.width - Theme.space8) / 2
                        title: "Wi-Fi"
                        icon: String.fromCodePoint(NetworkService.wifiEnabled ? 0xF05A9 : 0xF05AA)
                        enabled: NetworkService.wifiPresent
                        checked: NetworkService.wifiPresent && NetworkService.wifiEnabled
                        subtitle: {
                            if (!NetworkService.wifiPresent) {
                                return "No hardware";
                            }
                            if (!NetworkService.wifiEnabled) {
                                return "Radio off";
                            }
                            if (NetworkService.wifiConnected) {
                                return NetworkService.ssid + " · " + NetworkService.signalPercent + "%";
                            }
                            return "Not connected";
                        }
                        onToggled: NetworkService.toggleWifi()
                        showStatePill: false
                        expandable: NetworkService.wifiPresent
                        expanded: root.openMenu === "wifi"
                        onExpandToggled: root.setMenu(root.openMenu === "wifi" ? "" : "wifi")
                    }

                    Comp.ToggleTile {
                        width: (parent.width - Theme.space8) / 2
                        title: "Bluetooth"
                        icon: String.fromCodePoint(BluetoothService.powered ? 0xF00AF : 0xF00B2)
                        enabled: BluetoothService.available
                        checked: BluetoothService.powered
                        // Short forms: the tile text column is ~70px wide and
                        // must not elide the state label (PRD 17.3).
                        subtitle: {
                            if (!BluetoothService.available) {
                                return BluetoothService.statusLabel;
                            }
                            if (!BluetoothService.powered) {
                                return "Off";
                            }
                            if (BluetoothService.connectedCount === 0) {
                                return "No devices";
                            }
                            if (BluetoothService.connectedCount === 1) {
                                return BluetoothService.connectedDevices[0].deviceName;
                            }
                            return BluetoothService.connectedCount + " connected";
                        }
                        onToggled: BluetoothService.toggle()
                        showStatePill: false
                        expandable: BluetoothService.available
                        expanded: root.openMenu === "bt"
                        onExpandToggled: root.setMenu(root.openMenu === "bt" ? "" : "bt")
                    }
                }

                // --- detail dropdowns: drop down right under the tile row ---
                NetworkList {
                    id: wifiList
                    width: parent.width
                    expanded: root.openMenu === "wifi"
                    onPskRequested: net => {
                        pwDialog.net = net;
                    }
                }

                DeviceList {
                    id: btList
                    width: parent.width
                    expanded: root.openMenu === "bt"
                    onContextRequested: address => root.openDeviceMenu(address)
                }

                Comp.ToggleTile {
                    width: parent.width
                    title: "Airplane Mode"
                    icon: String.fromCodePoint(0xF001D) // md-airplane
                    enabled: NetworkService.backendAvailable
                    checked: root.airplaneOn
                    subtitle: {
                        if (!NetworkService.backendAvailable) {
                            return "No network backend";
                        }
                        return root.airplaneOn ? "Radios off" : "Radios on";
                    }
                    onToggled: {
                        const turningOn = !root.airplaneOn;
                        NetworkService.setWifiEnabled(!turningOn);
                        if (BluetoothService.available) {
                            BluetoothService.setPowered(!turningOn);
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Colors.borderSubtle
            }

            // --- sliders --------------------------------------------------
            Comp.ShellSlider {
                width: parent.width
                label: "Brightness"
                icon: String.fromCodePoint(0xF00DF) // md-brightness_6
                enabled: BrightnessService.available
                showValue: true
                valueText: BrightnessService.available ? BrightnessService.percent + "%" : "No backlight"
                value: BrightnessService.level
                from: 0
                to: 1
                onMoved: v => BrightnessService.setLevel(v)
            }

            Comp.ShellSlider {
                width: parent.width
                label: "Volume"
                icon: String.fromCodePoint(AudioService.muted || AudioService.volumePercent === 0 ? 0xF0581 : 0xF057E)
                iconAction: AudioService.available
                enabled: AudioService.available
                showValue: true
                valueText: AudioService.available ? AudioService.volumeText() : "—"
                valueAlert: AudioService.muted
                value: AudioService.volume
                from: 0
                to: 1
                onIconClicked: AudioService.toggleMute()
                onMoved: v => AudioService.setVolume(v)
            }
        }
    }

    // --- transient children: password dialog + device context menu --------
    // Both are separate layer surfaces with their own Escape handlers and
    // focus grabs; dismissing either hands keyboard focus back to the
    // panel (win.claimFocus).
    WifiDialog {
        id: pwDialog
        onDismissed: win.claimFocus()
    }

    DeviceMenu {
        id: deviceMenu
        onDismissed: win.claimFocus()
    }

    // Resolve the device behind a row's right-click, then park the menu
    // at the pointer. The pointer position comes from hyprctl in one shot
    // (cursor + monitor geometry) so the card lands inside the output no
    // matter which space that build of hyprctl reports in.
    property var pendingMenuDevice: null

    function openDeviceMenu(address) {
        const dev = BluetoothService.deviceAt(address);
        if (!dev) {
            return;
        }
        // QA override: deterministic position for scripted screenshots.
        const pos = Quickshell.env("VOID_QS_POS");
        if (pos !== "") {
            const parts = pos.split(",");
            deviceMenu.atX = parseInt(parts[0], 10) || 0;
            deviceMenu.atY = parseInt(parts[1], 10) || 0;
            deviceMenu.device = dev;
            return;
        }
        root.pendingMenuDevice = dev;
        cursorProbe.running = false;
        cursorProbe.running = true;
    }

    Process {
        id: cursorProbe
        running: false
        command: ["sh", "-c", "hyprctl -j cursorpos; echo QSMENUSEP; hyprctl -j monitors"]
        stdout: StdioCollector {
            id: probeOut
        }
        onExited: () => {
            if (root.pendingMenuDevice === null) {
                return;
            }
            const dev = root.pendingMenuDevice;
            root.pendingMenuDevice = null;
            // Fallback point if the probe fails: inside the panel area.
            let cx = 900;
            let cy = 300;
            try {
                const parts = probeOut.text.split("QSMENUSEP");
                const cur = JSON.parse(parts[0]);
                const mons = JSON.parse(parts[1]);
                const m = (mons.find(x => x.focused) || mons[0]);
                const scale = m.scale > 0 ? m.scale : 1;
                const ow = Math.round(m.width / scale);
                const oh = Math.round(m.height / scale);
                cx = cur.x;
                cy = cur.y;
                // hyprctl has reported the pointer in layout space on
                // some versions and physical space on others — normalize
                // into output-local logical pixels either way.
                if (cx > ow || cy > oh) {
                    cx = Math.round(cx / scale);
                    cy = Math.round(cy / scale);
                }
                cx -= (m.x !== undefined ? m.x : 0);
                cy -= (m.y !== undefined ? m.y : 0);
                // Clamp so the card stays fully on-screen.
                cx = Math.max(8, Math.min(cx, ow - deviceMenu.cardW - 8));
                cy = Math.max(8, Math.min(cy, oh - deviceMenu.cardH - 8));
            } catch (e) {
                // Keep the fallback point.
            }
            deviceMenu.atX = cx;
            deviceMenu.atY = cy;
            deviceMenu.device = dev;
        }
    }

    // --- QA hooks (VOID_QS): open the panel and reveal a transient
    // surface for scripted screenshots — same pattern as the launcher's
    // VOID_LAUNCHER_QUERY. No effect when unset.
    readonly property string qaMode: Quickshell.env("VOID_QS")

    Component.onCompleted: {
        if (root.qaMode === "") {
            return;
        }
        PopupManager.open("quickSettings");
        qaExpand.restart();
    }

    Timer {
        id: qaExpand
        interval: 400
        onTriggered: {
            root.setMenu(root.qaMode === "menu" ? "bt" : "wifi");
            qaReveal.restart();
        }
    }

    Timer {
        id: qaReveal
        interval: 1500
        onTriggered: {
            if (root.qaMode === "dialog") {
                const list = NetworkService.visibleNetworks;
                for (let i = 0; i < list.length; i++) {
                    if (NetworkService.needsPsk(list[i])) {
                        pwDialog.net = list[i].network;
                        return;
                    }
                }
            } else if (root.qaMode === "menu") {
                const devs = BluetoothService.sortedDevices;
                for (let i = 0; i < devs.length; i++) {
                    if (devs[i].paired || devs[i].trusted) {
                        root.openDeviceMenu(devs[i].address);
                        return;
                    }
                }
            }
        }
    }

    // --- scanning / discovery only while a list is open (PRD 36) ---------
    // `scanMenu` trails `openMenu` by one beat instead of flipping in the
    // same event: NetworkManager answers a scan switch inline (27 cached
    // results rebuilt in 174 ms was measured in the click's own event),
    // and that flood ran before the dropdown's own expand binding — 188 ms
    // of dead time before the first animation frame. Deferring lets the
    // animation start first and the flood land under it; stopping a scan
    // is equally unhurried (the drain re-evaluates the list too). PRD 36
    // still holds: no scan while idle, and the visible-gate below still
    // cuts both off the moment the panel closes.
    property string scanMenu: ""

    onOpenMenuChanged: scanRelay.restart()

    Timer {
        id: scanRelay
        interval: 60
        onTriggered: root.scanMenu = root.openMenu
    }

    Binding {
        target: NetworkService
        property: "scanRequested"
        value: root.scanMenu === "wifi" && win.visible
    }

    Binding {
        target: BluetoothService
        property: "scanRequested"
        value: root.scanMenu === "bt" && win.visible
    }

    // Backlight probe is gated on panel visibility (PRD 36): one probe
    // when the panel appears plus the service's 1.5 s re-probes while it
    // stays open, so the slider reads and drives the real screen
    // brightness (and tracks Fn-key changes). Idle: no work.
    Binding {
        target: BrightnessService
        property: "active"
        value: win.visible
    }
}
