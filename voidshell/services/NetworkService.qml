pragma Singleton

import Quickshell
import Quickshell.Networking
import QtQuick

// VOID SHELL — network state (PRD 34.4): Wi-Fi radio, connection, SSID,
// signal, ethernet. Backed entirely by the NetworkManager plugin, so all
// values are real; panels must degrade to `unavailable` when no device
// exists rather than inventing state.
Singleton {
    id: root

    readonly property var deviceList: Networking.devices.values

    // First device of a given DeviceType, or null.
    function firstOfType(kind) {
        const list = root.deviceList;
        if (!list) {
            return null;
        }
        for (let i = 0; i < list.length; i++) {
            if (list[i].type === kind) {
                return list[i];
            }
        }
        return null;
    }

    readonly property var wifiDevice: root.firstOfType(DeviceType.Wifi)
    readonly property var wiredDevice: root.firstOfType(DeviceType.Wired)

    readonly property bool backendAvailable: root.deviceList !== null && root.deviceList.length > 0
    readonly property bool wifiPresent: root.wifiDevice !== null
    readonly property bool ethernetPresent: root.wiredDevice !== null

    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property bool wifiHardwareEnabled: Networking.wifiHardwareEnabled
    readonly property bool wifiSupported: root.wifiPresent && Networking.wifiHardwareEnabled

    readonly property bool wifiConnected: root.wifiDevice !== null && root.wifiDevice.connected
    readonly property bool ethernetConnected: root.wiredDevice !== null && root.wiredDevice.connected
    readonly property bool connected: root.wifiConnected || root.ethernetConnected

    readonly property bool airplaneMode: root.backendAvailable && !root.wifiEnabled && !root.wifiHardwareEnabled

    // The network the Wi-Fi device is actually associated with.
    readonly property var activeNetwork: {
        const dev = root.wifiDevice;
        if (dev === null || !dev.connected) {
            return null;
        }
        const list = dev.networks ? dev.networks.values : null;
        if (!list) {
            return null;
        }
        for (let i = 0; i < list.length; i++) {
            if (list[i].connected) {
                return list[i];
            }
        }
        return null;
    }

    readonly property string ssid: root.activeNetwork ? root.activeNetwork.name : ""
    // NetworkManager reports 0..100; normalize defensively so a 0..1
    // backend can never silently render as "1%".
    readonly property real signalStrength: {
        const net = root.activeNetwork;
        if (!net) {
            return 0;
        }
        const raw = net.signalStrength;
        const pct = raw <= 1 ? raw * 100 : raw;
        return Math.max(0, Math.min(100, pct));
    }
    readonly property int signalPercent: Math.round(root.signalStrength)

    readonly property string ethernetName: root.wiredDevice !== null ? root.wiredDevice.name : ""

    // Scanning is only requested while a panel wants the network list, so
    // an idle shell never keeps the radio busy (PRD 36).
    property bool scanRequested: false
    readonly property bool scanning: root.wifiDevice !== null && root.wifiDevice.scannerEnabled

    Binding {
        target: root.wifiDevice
        property: "scannerEnabled"
        value: root.scanRequested && root.wifiEnabled
        when: root.wifiDevice !== null
    }

    // Available networks for the quick-settings expandable row.
    readonly property var visibleNetworks: {
        const dev = root.wifiDevice;
        const out = [];
        if (dev === null || !dev.networks) {
            return out;
        }
        const list = dev.networks.values;
        if (!list) {
            return out;
        }
        const seen = {};
        for (let i = 0; i < list.length; i++) {
            const n = list[i];
            if (!n.name || seen[n.name]) {
                continue;
            }
            seen[n.name] = true;
            let pct = n.signalStrength;
            pct = pct <= 1 ? pct * 100 : pct;
            out.push({
                name: n.name,
                connected: n.connected,
                known: n.known,
                strength: Math.max(0, Math.min(100, pct)),
                network: n
            });
        }
        out.sort((a, b) => {
            if (a.connected !== b.connected) {
                return a.connected ? -1 : 1;
            }
            if (a.known !== b.known) {
                return a.known ? -1 : 1;
            }
            return b.strength - a.strength;
        });
        return out;
    }

    function setWifiEnabled(on) {
        if (!root.wifiPresent) {
            return;
        }
        Networking.wifiEnabled = on;
    }

    function toggleWifi() {
        root.setWifiEnabled(!root.wifiEnabled);
    }

    // Airplane mode must coordinate real radios (PRD 17.3): if the backend
    // cannot do it, the UI disables the tile instead of faking state.
    function setAirplaneMode(on) {
        if (!root.backendAvailable) {
            return;
        }
        root.setWifiEnabled(!on);
    }

    // Can the shell join this network without prompting for a PSK? Saved
    // networks and open/open-equivalent ones; everything else needs the
    // dialog or stays inert (see needsPsk below). Bindings that call this
    // track its property reads, so rows re-evaluate live as state changes.
    function canConnect(entry) {
        if (!entry || !entry.network) {
            return false;
        }
        const n = entry.network;
        if (n.connected || n.stateChanging) {
            return false;
        }
        if (n.known) {
            return true;
        }
        return n.security === WifiSecurityType.Open || n.security === WifiSecurityType.Owe;
    }

    // Unsaved networks whose secrets a PSK prompt can satisfy — exactly
    // the rows that open the password dialog (WifiNetwork.connectWithPsk
    // documents WpaPsk/Wpa2Psk/Sae as the PSK types it accepts). Enterprise
    // (EAP), WEP and unknown types are not covered by that prompt and stay
    // inert with an honest reason instead of a dialog that could never
    // succeed (PRD 17.3).
    function needsPsk(entry) {
        if (!entry || !entry.network) {
            return false;
        }
        const n = entry.network;
        if (n.connected || n.stateChanging || n.known) {
            return false;
        }
        const sec = n.security;
        return sec === WifiSecurityType.WpaPsk || sec === WifiSecurityType.Wpa2Psk || sec === WifiSecurityType.Sae;
    }

    // Reconnect a joinable network. `connect()` is the invokable on the
    // Network type; `requestConnect` is only a signal and does nothing on
    // its own when emitted.
    function connect(entry) {
        if (!root.canConnect(entry)) {
            return;
        }
        entry.network.connect();
    }

    // Join with a user-provided PSK (WifiNetwork.connectWithPsk — the
    // backend the password dialog is built on). A wrong key comes back as
    // connectionFailed(NoSecrets) on the same network object, which the
    // dialog renders as an inline error.
    function connectWithPsk(network, psk) {
        if (!network || network.stateChanging || !psk) {
            return;
        }
        network.connectWithPsk(psk);
    }

    function disconnectActive() {
        const dev = root.wifiDevice;
        if (dev !== null && dev.connected) {
            // Method, not the requestDisconnect signal (see connect()).
            dev.disconnect();
        }
    }
}
