pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — shared system sampler (PRD 34.9, 36).
// One sampler feeds every consumer (dashboard, system monitor, overview);
// modules never poll on their own. /proc is read through FileView (no
// fork) on a 2 s timer; disk, package updates and the process list use
// subprocesses at their own, much slower cadence — and the process list
// only runs while the task manager asks for it.
Singleton {
    id: root

    // ---- live gauges ---------------------------------------------------------
    property real cpuUsage: 0
    property real cpuTemp: -1
    property real memUsage: 0
    property real memTotalKb: 0
    property real memAvailableKb: 0
    property real diskUsage: 0
    property real diskUsedBytes: 0
    property real diskTotalBytes: 0
    property real netDown: 0
    property real netUp: 0
    property real uptimeSeconds: 0

    readonly property bool tempAvailable: root.cpuTemp >= 0

    // ---- rolling history (oldest first) -------------------------------------
    property var cpuHistory: []
    property var memHistory: []
    property var netHistory: []
    property var netUpHistory: []
    readonly property int historyLimit: 60

    // ---- identity ------------------------------------------------------------
    property string osName: ""
    property string kernel: ""
    property string hostname: ""
    property string username: {
        const u = Quickshell.env("USER");
        if (u !== "" && u !== undefined && u !== null) {
            return u;
        }
        const l = Quickshell.env("LOGNAME");
        return l !== "" && l !== undefined && l !== null ? l : "user";
    }
    property string wmName: "Hyprland"
    readonly property string uptimeText: root.formatDuration(root.uptimeSeconds)

    // ---- package updates -----------------------------------------------------
    property int updateCount: 0
    property var updateList: []
    property string updatesState: "idle" // idle | checking | ok | unavailable
    readonly property bool updatesAvailable: root.updateCount > 0

    // ---- process table (only while the task manager is open) -----------------
    property bool processEnabled: false
    property var processes: []
    property int processSerial: 0

    // ---- /proc deltas --------------------------------------------------------
    property var prevCpu: null
    property var prevNet: null
    property real prevNetTime: 0

    // ======================= /proc sampling ==================================
    FileView {
        id: cpuFile
        path: "/proc/stat"
        printErrors: false
        onLoaded: root.parseCpu(cpuFile.text())
    }

    FileView {
        id: memFile
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: root.parseMem(memFile.text())
    }

    FileView {
        id: netFile
        path: "/proc/net/dev"
        printErrors: false
        onLoaded: root.parseNet(netFile.text())
    }

    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        printErrors: false
        onLoaded: root.parseUptime(uptimeFile.text())
    }

    // CPU temperature path is discovered once (hwmon layout varies).
    property string tempPath: ""
    FileView {
        id: tempFile
        path: root.tempPath
        printErrors: false
        onLoaded: root.parseTemp(tempFile.text())
    }

    Process {
        id: tempProbe
        command: ["sh", "-c", "for d in /sys/class/hwmon/hwmon*; do n=$(cat \"$d/name\" 2>/dev/null); case \"$n\" in coretemp|k10temp|zenpower|cpu_thermal) for t in \"$d\"/temp*_input; do [ -r \"$t\" ] && { echo \"$t\"; exit 0; }; done;; esac; done; exit 1"]
        running: true
        stdout: StdioCollector {
            id: tempOut
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                const p = tempOut.text.trim();
                if (p !== "") {
                    root.tempPath = p;
                }
            }
        }
    }

    // PRD §36: ~2 s stats polling, but only while a stats view is actually
    // on screen (task manager, dashboard) — an idle shell must do no
    // unnecessary background work. Measured on this hardware: always-on 2 s
    // sampling cost 2.1% idle CPU; demand-driven sampling ~0.1%. Opening a
    // stats view samples immediately, so gauges are fresh on frame one and
    // graphs fill at full rate (historyLimit = 60 points = 2 min at 2 s).
    readonly property bool statsFast: PopupManager.isOpen("taskManager") || PopupManager.isOpen("dashboard")

    Timer {
        id: sampleTimer
        interval: 2000
        repeat: true
        running: root.statsFast
        onTriggered: root.sample()
    }

    onStatsFastChanged: {
        if (root.statsFast) {
            // Opening a stats view gets fresh numbers immediately instead of
            // waiting for the first 2 s tick.
            root.sample();
        }
    }

    function sample() {
        cpuFile.reload();
        memFile.reload();
        netFile.reload();
        uptimeFile.reload();
        if (root.tempPath !== "") {
            tempFile.reload();
        }
    }

    function pushHistory(listName, value) {
        const next = root[listName].slice();
        next.push(value);
        while (next.length > root.historyLimit) {
            next.shift();
        }
        root[listName] = next;
    }

    function parseCpu(content) {
        const line = String(content).split("\n")[0];
        const parts = line.trim().split(/\s+/);
        if (parts.length < 5 || parts[0] !== "cpu") {
            return;
        }
        let idle = Number(parts[4]);
        if (parts.length > 5) {
            idle += Number(parts[5]);
        }
        let total = 0;
        for (let i = 1; i < parts.length; i++) {
            total += Number(parts[i]);
        }
        if (root.prevCpu !== null) {
            const dt = total - root.prevCpu.total;
            const di = idle - root.prevCpu.idle;
            if (dt > 0) {
                const usage = (1 - di / dt) * 100;
                root.cpuUsage = Math.max(0, Math.min(100, usage));
                root.pushHistory("cpuHistory", Math.round(root.cpuUsage * 10) / 10);
            }
        }
        root.prevCpu = {
            idle: idle,
            total: total
        };
    }

    function parseMem(content) {
        const text = String(content);
        const total = /MemTotal:\s+(\d+)\s+kB/.exec(text);
        const avail = /MemAvailable:\s+(\d+)\s+kB/.exec(text);
        if (!total) {
            return;
        }
        const totalKb = Number(total[1]);
        const availKb = avail ? Number(avail[1]) : 0;
        root.memTotalKb = totalKb;
        root.memAvailableKb = availKb;
        if (totalKb > 0) {
            root.memUsage = Math.max(0, Math.min(100, (1 - availKb / totalKb) * 100));
            root.pushHistory("memHistory", Math.round(root.memUsage * 10) / 10);
        }
    }

    function parseNet(content) {
        const lines = String(content).split("\n");
        let rx = 0;
        let tx = 0;
        for (let i = 5; i < lines.length; i++) {
            const line = lines[i];
            const colon = line.indexOf(":");
            if (colon < 0) {
                continue;
            }
            const iface = line.slice(0, colon).trim();
            if (iface === "lo") {
                continue;
            }
            const fields = line.slice(colon + 1).trim().split(/\s+/);
            if (fields.length < 9) {
                continue;
            }
            rx += Number(fields[0]);
            tx += Number(fields[8]);
        }
        const now = Date.now() / 1000;
        if (root.prevNet !== null) {
            const dt = now - root.prevNetTime;
            if (dt > 0.5) {
                const down = Math.max(0, (rx - root.prevNet.rx) / dt);
                const up = Math.max(0, (tx - root.prevNet.tx) / dt);
                root.netDown = down;
                root.netUp = up;
                root.pushHistory("netHistory", down);
                root.pushHistory("netUpHistory", up);
            }
        }
        root.prevNet = {
            rx: rx,
            tx: tx
        };
        root.prevNetTime = now;
    }

    function parseUptime(content) {
        const secs = Number(String(content).trim().split(/\s+/)[0]);
        if (isFinite(secs) && secs >= 0) {
            root.uptimeSeconds = secs;
        }
    }

    function parseTemp(content) {
        const raw = Number(String(content).trim());
        if (!isFinite(raw) || raw <= 0) {
            return;
        }
        // hwmon reports millidegrees; tolerate Celsius-native sources.
        root.cpuTemp = Math.round(raw > 1000 ? raw / 1000 : raw);
    }

    // ======================= identity ========================================
    FileView {
        id: osReleaseFile
        path: "/etc/os-release"
        printErrors: false
        onLoaded: root.parseOsRelease(osReleaseFile.text())
    }

    FileView {
        id: kernelFile
        path: "/proc/sys/kernel/osrelease"
        printErrors: false
        onLoaded: {
            const v = kernelFile.text().trim();
            if (v !== "") {
                root.kernel = v;
            }
        }
    }

    FileView {
        id: hostnameFile
        path: "/proc/sys/kernel/hostname"
        printErrors: false
        onLoaded: {
            const v = hostnameFile.text().trim();
            if (v !== "") {
                root.hostname = v;
            }
        }
    }

    function parseOsRelease(content) {
        const lines = String(content).split("\n");
        let pretty = "";
        let name = "";
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (line.indexOf("PRETTY_NAME=") === 0) {
                pretty = line.slice("PRETTY_NAME=".length).replace(/^"|"$/g, "");
            } else if (line.indexOf("NAME=") === 0) {
                name = line.slice("NAME=".length).replace(/^"|"$/g, "");
            }
        }
        root.osName = pretty !== "" ? pretty : (name !== "" ? name : "Linux");
    }

    // ======================= disk ============================================
    Process {
        id: diskProc
        command: ["df", "-P", "-B1", "/"]
        running: true
        stdout: StdioCollector {
            id: diskOut
        }
        onExited: exitCode => {
            diskProc.running = false;
            if (exitCode === 0) {
                root.parseDisk(diskOut.text);
            }
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: {
            if (!diskProc.running) {
                diskProc.running = true;
            }
        }
    }

    function parseDisk(content) {
        const lines = String(content).trim().split("\n");
        if (lines.length < 2) {
            return;
        }
        const fields = lines[lines.length - 1].trim().split(/\s+/);
        if (fields.length < 5) {
            return;
        }
        const total = Number(fields[1]);
        const used = Number(fields[2]);
        const capacity = Number(String(fields[4]).replace("%", ""));
        if (!isFinite(total) || total <= 0) {
            return;
        }
        root.diskTotalBytes = total;
        root.diskUsedBytes = used;
        root.diskUsage = Math.max(0, Math.min(100, isFinite(capacity) ? capacity : (used / total) * 100));
    }

    // ======================= package updates =================================
    Process {
        id: updatesProc
        command: ["sh", "-c", "command -v checkupdates >/dev/null 2>&1 && checkupdates || pacman -Qu"]
        stdout: StdioCollector {
            id: updatesOut
        }
        onExited: exitCode => {
            updatesProc.running = false;
            root.parseUpdates(exitCode, updatesOut.text);
        }
    }

    // Cadence comes from the Island settings (default 6 h): package
    // updates are cheap to ask for but not free, and the Dashboard also
    // refreshes on demand when its Overview tab is opened.
    Timer {
        interval: Math.max(60, IslandSettings.updateCheckMinutes) * 60 * 1000
        repeat: true
        running: true
        onTriggered: root.refreshUpdates()
    }

    function refreshUpdates() {
        if (updatesProc.running) {
            return;
        }
        root.updatesState = "checking";
        updatesProc.running = true;
    }

    function parseUpdates(exitCode, output) {
        const raw = String(output || "").split("\n");
        const list = [];
        for (let i = 0; i < raw.length; i++) {
            const line = raw[i].trim();
            if (line !== "") {
                list.push(line);
            }
        }
        // Any lines at all are real data regardless of the exit code.
        if (list.length > 0) {
            root.updateList = list.slice(0, 60);
            root.updateCount = list.length;
            root.updatesState = "ok";
            return;
        }
        // checkupdates exits 2 when nothing is outdated; pacman -Qu exits 0.
        if (exitCode === 0 || exitCode === 2) {
            root.updateList = [];
            root.updateCount = 0;
            root.updatesState = "ok";
            return;
        }
        // Empty output on any other code: no data to report. Never claim
        // "up to date" without evidence.
        root.updatesState = "unavailable";
        root.updateCount = 0;
        root.updateList = [];
    }

    // ======================= process table ===================================
    Process {
        id: procProc
        command: ["sh", "-c", "ps -eo pid=,pcpu=,pmem=,comm= --sort=-pcpu | head -n 41"]
        stdout: StdioCollector {
            id: procOut
        }
        onExited: () => {
            procProc.running = false;
            root.parseProcesses(procOut.text);
        }
    }

    onProcessEnabledChanged: {
        if (root.processEnabled) {
            root.refreshProcesses();
        }
    }

    function refreshProcesses() {
        if (!procProc.running) {
            procProc.running = true;
        }
    }

    function parseProcesses(content) {
        const lines = String(content).split("\n");
        const out = [];
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            if (line === "") {
                continue;
            }
            const parts = line.split(/\s+/);
            if (parts.length < 4) {
                continue;
            }
            out.push({
                pid: Number(parts[0]),
                cpu: Number(parts[1]),
                mem: Number(parts[2]),
                name: parts.slice(3).join(" ")
            });
        }
        root.processes = out;
        root.processSerial = root.processSerial + 1;
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.processEnabled
        onTriggered: root.refreshProcesses()
    }

    // ======================= formatting helpers ==============================
    function formatBytes(bytes) {
        const b = Number(bytes);
        if (!isFinite(b) || b < 0) {
            return "—";
        }
        if (b >= 1073741824) {
            return (b / 1073741824).toFixed(1) + " GB";
        }
        if (b >= 1048576) {
            return Math.round(b / 1048576) + " MB";
        }
        if (b >= 1024) {
            return Math.round(b / 1024) + " KB";
        }
        return Math.round(b) + " B";
    }

    function formatRate(bytesPerSecond) {
        return root.formatBytes(bytesPerSecond) + "/s";
    }

    function formatDuration(seconds) {
        const total = Math.floor(Number(seconds) || 0);
        if (total <= 0) {
            return "—";
        }
        const days = Math.floor(total / 86400);
        const hours = Math.floor((total % 86400) / 3600);
        const minutes = Math.floor((total % 3600) / 60);
        if (days > 0) {
            return days + "d " + hours + "h";
        }
        if (hours > 0) {
            return hours + "h " + minutes + "m";
        }
        return minutes + "m";
    }

    function formatKb(kb) {
        return root.formatBytes((Number(kb) || 0) * 1024);
    }
}
