pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

// VOID SHELL — power state and session actions (PRD 34.8, 18).
// Battery facts come from UPower; capability detection is real: the lock
// implementation is discovered, hibernate is only offered when the kernel
// reports disk sleep *and* swap exists. `commandFor()` builds commands so
// tests can verify construction without ever executing them.
Singleton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool ready: root.device !== null && root.device.ready

    // UPower exposes charge as an energy ratio (0..1); normalize to 0..100
    // while tolerating a percentage-native backend.
    readonly property int percentage: {
        if (!root.ready) {
            return -1;
        }
        const p = root.device.percentage;
        return Math.round(p <= 1 ? p * 100 : p);
    }

    readonly property bool onBattery: UPower.onBattery
    readonly property int upowerState: root.ready ? root.device.state : -1

    readonly property bool charging: root.upowerState === UPowerDeviceState.Charging || root.upowerState === UPowerDeviceState.PendingCharge
    readonly property bool fullyCharged: root.upowerState === UPowerDeviceState.FullyCharged
    readonly property bool discharging: root.upowerState === UPowerDeviceState.Discharging

    readonly property bool hasBattery: root.ready && root.device.isPresent && root.device.isLaptopBattery

    readonly property string stateLabel: {
        if (!root.ready) {
            return "No battery";
        }
        if (root.fullyCharged) {
            return "Fully charged";
        }
        if (root.charging) {
            return "Charging";
        }
        if (root.discharging) {
            return root.onBattery ? "On battery" : "Discharging";
        }
        return "Not charging";
    }

    // "2h 14m" remaining/til-full, empty when UPower has no estimate.
    readonly property string timeLabel: {
        if (!root.ready) {
            return "";
        }
        const secs = root.charging || root.fullyCharged ? root.device.timeToFull : root.device.timeToEmpty;
        if (!isFinite(secs) || secs <= 0) {
            return "";
        }
        const total = Math.round(secs);
        const hours = Math.floor(total / 3600);
        const minutes = Math.floor((total % 3600) / 60);
        if (hours > 0) {
            return hours + "h " + minutes + "m";
        }
        return minutes + "m";
    }

    // ---- capability detection -------------------------------------------------
    property bool canLock: false
    property bool canSuspend: true
    property bool canHibernate: false
    property bool canReboot: true
    property bool canPowerOff: true
    property string lockCommand: ""

    readonly property bool capabilitiesReady: root.lockReady && root.hibernateReady

    property bool lockReady: false
    property bool hibernateReady: false

    Process {
        id: lockProbe
        command: ["sh", "-c", "command -v hyprlock || command -v swaylock || command -v gtklock || command -v swaylock-effects || true"]
        running: true
        stdout: StdioCollector {
            id: lockOut
        }
        onExited: () => {
            const path = lockOut.text.trim();
            root.lockReady = true;
            if (path !== "") {
                root.lockCommand = path;
                root.canLock = true;
            } else {
                // Fall back to the logind lock signal only if something listens.
                root.lockCommand = "";
                root.canLock = false;
            }
        }
    }

    Process {
        id: hibernateProbe
        command: ["sh", "-c", "grep -qw disk /sys/power/state 2>/dev/null || exit 1; swapon --show --noheadings 2>/dev/null | grep -q ."]
        running: true
        onExited: exitCode => {
            root.hibernateReady = true;
            root.canHibernate = exitCode === 0;
        }
    }

    // ---- session actions ------------------------------------------------------
    // Pure function: never executes anything (PRD 43.4 — tests must only
    // inspect command construction).
    function commandFor(action) {
        switch (action) {
        case "lock":
            if (root.lockCommand !== "") {
                return [root.lockCommand];
            }
            return ["loginctl", "lock-session"];
        case "suspend":
            return ["systemctl", "suspend"];
        case "hibernate":
            return ["systemctl", "hibernate"];
        case "reboot":
            return ["systemctl", "reboot"];
        case "poweroff":
            return ["systemctl", "poweroff"];
        default:
            return [];
        }
    }

    function canDo(action) {
        switch (action) {
        case "lock":
            return root.canLock;
        case "suspend":
            return root.canSuspend;
        case "hibernate":
            return root.canHibernate;
        case "reboot":
            return root.canReboot;
        case "poweroff":
            return root.canPowerOff;
        default:
            return false;
        }
    }

    function describe(action) {
        return root.commandFor(action).join(" ");
    }

    Process {
        id: actionProc
    }

    function execute(action) {
        if (!root.canDo(action)) {
            return false;
        }
        const cmd = root.commandFor(action);
        if (cmd.length === 0) {
            return false;
        }
        // Detached so a config reload or shell crash can never kill a
        // session action in flight (e.g. hyprlock staying up while locked).
        actionProc.command = cmd;
        actionProc.startDetached();
        return true;
    }
}
