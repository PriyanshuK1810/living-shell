pragma Singleton

import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick

// VOID SHELL — bluetooth state (PRD 34.5): real BlueZ adapter power,
// device list and connection counts. When no adapter exists the UI shows
// an accurately labelled unavailable state instead of a fake toggle.
//
// Also owns the two pieces that make a tap on an unpaired device actually
// do something: the BlueZ agent (below) and the pairing watch that turns
// device.pair() into a success or failure the panel can show.
Singleton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: root.adapter !== null
    readonly property bool powered: root.available && root.adapter.enabled
    readonly property bool discovering: root.available && root.adapter.discovering

    readonly property var deviceList: {
        if (!root.available) {
            return [];
        }
        const list = root.adapter.devices ? root.adapter.devices.values : null;
        return list ? list : [];
    }

    readonly property int deviceCount: root.deviceList.length

    // Device list ordered for panels: connected first, then saved ones
    // (paired or trusted), then the rest — each group by name. The sort
    // reads connected/paired/name here, so those notifies re-run it and
    // the order follows live state.
    readonly property var sortedDevices: {
        const list = root.deviceList.slice();
        const rank = d => (d.connected ? 0 : ((d.paired || d.trusted) ? 1 : 2));
        list.sort((a, b) => {
            const ra = rank(a);
            const rb = rank(b);
            if (ra !== rb) {
                return ra - rb;
            }
            return String(a.deviceName || a.name || "").localeCompare(String(b.deviceName || b.name || ""));
        });
        return list;
    }

    readonly property var connectedDevices: {
        const out = [];
        for (let i = 0; i < root.deviceList.length; i++) {
            if (root.deviceList[i].connected) {
                out.push(root.deviceList[i]);
            }
        }
        return out;
    }

    readonly property int connectedCount: root.connectedDevices.length

    // One-line summary for tiles: "Off" / "No devices" / "2 connected" /
    // the first connected device name.
    readonly property string statusLabel: {
        if (!root.available) {
            return "Unavailable";
        }
        if (!root.powered) {
            return "Off";
        }
        if (root.connectedCount === 0) {
            return root.deviceCount > 0 ? "No devices connected" : "No paired devices";
        }
        if (root.connectedCount === 1) {
            return root.connectedDevices[0].deviceName;
        }
        return root.connectedCount + " devices connected";
    }

    // Discovery runs only while a panel asks for it (PRD 36).
    property bool scanRequested: false

    Binding {
        target: root.adapter
        property: "discovering"
        value: root.scanRequested && root.powered
        when: root.available
    }

    // --- BlueZ agent (scripts/bt-agent) ---------------------------------
    // bluetoothd needs an org.bluez.Agent1 to authorize service connections
    // and to take pairing confirmations. With none registered, connecting a
    // device that is not Trusted dies with "Authentication attempt without
    // agent" -> org.bluez.Error.Rejected, and Pair() has nobody to answer it.
    // The agent registers itself as the default agent and accepts, which is
    // what makes the unpaired rows in the device list tappable at all.
    //
    // Exit 0 is a deliberate stop (SIGTERM, e.g. quickshell tearing the old
    // Process down on reload) so it is not restarted — a replacement Process
    // is created with `running: true` instead. Anything else means the bus
    // connection was lost, so come back after a short backoff.
    Process {
        id: btAgent

        command: [Quickshell.shellDir + "/scripts/bt-agent"]
        running: true

        onExited: exitCode => {
            if (exitCode !== 0) {
                btAgentRetry.start();
            }
        }
    }

    Timer {
        id: btAgentRetry

        interval: 3000
        repeat: false
        onTriggered: btAgent.running = true
    }

    // --- tap-to-pair ------------------------------------------------------
    // quickshell's pair() only reports failure through the log, and the
    // Pair() reply lands once bonding has finished, so an attempt is watched
    // here: paired turns into trust + connect + a success toast, and a row
    // that stops moving is cancelled and reported instead of spinning.
    property var pairingDevice: null
    property int pairingTicks: 0
    property string pairingName: ""
    readonly property bool pairing: root.pairingDevice !== null

    function pairDevice(device) {
        if (!device || !root.available || !root.powered || device.blocked) {
            return;
        }
        if (device.paired) {
            root.setConnected(device, true);
            return;
        }
        // One pairing at a time: a second tap must not race the first, and
        // the other rows stay inert until this one resolves.
        if (root.pairing || device.pairing) {
            return;
        }
        root.pairingDevice = device;
        root.pairingTicks = 0;
        root.pairingName = device.deviceName || device.name || device.address;
        device.pair();
        pairWatch.start();
    }

    function watchPairing() {
        const dev = root.pairingDevice;
        if (!dev) {
            pairWatch.stop();
            return;
        }
        root.pairingTicks = root.pairingTicks + 1;

        if (dev.paired) {
            // BlueZ marks the device paired before the Pair() reply reaches
            // quickshell. Trust it so the next connect skips service
            // authorization, then bring the link up — one tap, connected.
            dev.trusted = true;
            dev.connected = true;
            root.endPair(true);
            return;
        }

        // pairing drops on both outcomes, so a row that has gone quiet while
        // still unpaired has failed; the three-tick grace covers Paired being
        // flushed a beat after it on devices whose services resolve late.
        if (!dev.pairing && root.pairingTicks > 3) {
            root.endPair(false);
            return;
        }
        if (root.pairingTicks > 75) { // ~30s hard cap
            if (dev.pairing) {
                dev.cancelPair();
            }
            root.endPair(false);
        }
    }

    function endPair(ok) {
        const name = root.pairingName;
        pairWatch.stop();
        root.pairingDevice = null;
        root.pairingTicks = 0;
        root.pairingName = "";
        if (ok) {
            ToastService.push(name, "Paired and connected", "", "success");
        } else {
            ToastService.push(name, "Pairing failed", "The device did not finish pairing.", "danger");
        }
    }

    Timer {
        id: pairWatch

        interval: 400
        repeat: true
        onTriggered: root.watchPairing()
    }

    function setPowered(on) {
        if (!root.available) {
            return;
        }
        root.adapter.enabled = on;
    }

    function toggle() {
        root.setPowered(!root.powered);
    }

    function setConnected(device, on) {
        if (!device) {
            return;
        }
        device.connected = on;
    }

    function toggleDevice(device) {
        root.setConnected(device, !device.connected);
    }

    function deviceAt(address) {
        for (let i = 0; i < root.deviceList.length; i++) {
            if (root.deviceList[i].address === address) {
                return root.deviceList[i];
            }
        }
        return null;
    }
}
