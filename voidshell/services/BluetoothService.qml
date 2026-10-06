pragma Singleton

import Quickshell
import Quickshell.Bluetooth
import QtQuick

// VOID SHELL — bluetooth state (PRD 34.5): real BlueZ adapter power,
// device list and connection counts. When no adapter exists the UI shows
// an accurately labelled unavailable state instead of a fake toggle.
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
