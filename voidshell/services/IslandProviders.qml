pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

// VOID SHELL — Living State Island provider adapters (MASTER PROMPT §17.B).
//
// Translates the *existing* services into Island vocabulary: it watches
// each provider for a real change, turns it into an announcement (via
// AnnouncementEngine) or a continuing activity (via ActivityStore), and
// maintains the capability matrix in IslandSettings. It owns no state of
// its own beyond a change-detection snapshot.
//
// Rules honoured here:
//   * every observation is event-driven off an existing service signal —
//     the only timers are the two polling fallbacks where no signal
//     exists (accessory battery, temperature), each with a conservative
//     interval, and both stop when their feature is disabled;
//   * a warm-up window suppresses the first observation of every
//     provider, so a shell restart never replays a backlog (§18 startup);
//   * nothing is ever announced that was not actually observed — an
//     unavailable backend produces a capability row, not a success.
Singleton {
    id: root

    property bool settled: false
    property var snap: ({})

    // --- capability probe (once at startup, cached) ----------------------
    Process {
        id: capProbe
        command: ["sh", "-c", "for c in cliphist wl-paste wl-copy powerprofilesctl hyprsunset checkupdates yay kdeconnect-cli wf-recorder systemd-inhibit playerctl; do if command -v \"$c\" >/dev/null 2>&1; then echo \"$c ok\"; else echo \"$c missing\"; fi; done"]
        running: false
        stdout: StdioCollector {
            id: capOut
        }
        onExited: root.parseCapabilities(capOut.text)
    }

    Component.onCompleted: {
        capProbe.running = true;
        root.probeServiceProviders();
    }

    Timer {
        interval: 3000
        repeat: false
        running: true
        onTriggered: root.settle()
    }

    function settle() {
        root.seedBaselines();
        root.settled = true;
        root.probeServiceProviders();
        root.syncPrivacy();
    }

    // Baseline capture — runs while the warm-up window is still closed, so
    // every note* below stores its snapshot and returns without announcing.
    // This is what makes the first change *after* warm-up a real event:
    // observe() returns null for a key it has never seen, so without a
    // seeded baseline the very first volume step, playback start, track
    // title, bluetooth edge or brightness change after a shell restart
    // would be consumed as a "first observation" and silently dropped.
    // noteNotification / noteWorkspace are deliberately absent — they have
    // no snapshot and announce unconditionally, so seeding them would
    // replay a backlog the warm-up window exists to suppress.
    function seedBaselines() {
        const wasSettled = root.settled;
        root.settled = false;
        root.noteVolume();
        root.noteTrack();
        root.notePlayback();
        root.noteBluetooth();
        root.noteCharging();
        root.noteBattery();
        root.noteNetwork();
        root.noteBrightness();
        root.noteDnd();
        root.noteFocusComplete();
        root.noteFocusMode();
        root.noteFocusState();
        root.noteRecording();
        root.noteScreenshot();
        root.noteUpdates();
        root.settled = wasSettled;
    }

    // --- change-detection helper ----------------------------------------
    // Stores `cur` under `key` and returns the previous value — but only
    // once the warm-up window has passed, so the first observation of a
    // provider is baseline, never an event.
    function observe(key, cur) {
        const prev = root.snap[key] === undefined ? null : root.snap[key];
        root.snap[key] = cur;
        if (!root.settled) {
            return null;
        }
        return prev;
    }

    function announce(ev) {
        return AnnouncementEngine.announce(ev);
    }

    // =========================================================================
    // F04 / F05 — audio volume, mute and device selection
    // =========================================================================
    Connections {
        target: AudioService
        function onVolumePercentChanged() {
            root.noteVolume();
        }
        function onMutedChanged() {
            root.noteVolume();
        }
        function onAvailableChanged() {
            root.probeServiceProviders();
        }
    }

    function noteVolume() {
        const cur = { v: AudioService.volumePercent, m: AudioService.muted, a: AudioService.available };
        const prev = root.observe("volume", cur);
        if (prev === null) {
            return;
        }
        if (prev.a !== cur.a) {
            root.probeServiceProviders();
        }
        if (prev.v === cur.v && prev.m === cur.m) {
            return;
        }
        if (IslandSettings.featureOn("volume") && AudioService.available) {
            root.announce({
                key: "volume",
                priority: 1,
                category: "control",
                feature: "volume",
                title: cur.m ? "Audio muted" : "Volume " + cur.v + "%",
                subtitle: cur.m ? "" : AudioService.sinkName,
                icon: cur.m ? 0xF026 : (cur.v < 50 ? 0xF027 : 0xF028),
                tone: cur.m ? "warning" : "info"
            });
        }
    }

    // =========================================================================
    // F02 — media announcements (playback start + meaningful track change)
    // =========================================================================
    Connections {
        target: MediaService
        function onTrackTitleChanged() {
            root.noteTrack();
        }
        function onPlayingChanged() {
            root.notePlayback();
        }
        function onAvailableChanged() {
            root.probeServiceProviders();
        }
    }

    function noteTrack() {
        const title = MediaService.trackTitle;
        const cur = { t: title, a: MediaService.available };
        const prev = root.observe("track", cur);
        if (prev === null) {
            return;
        }
        if (prev.t === cur.t && prev.a === cur.a) {
            return;
        }
        if (cur.t === "") {
            return;
        }
        if (IslandSettings.featureOn("media")) {
            root.announce({
                key: "track",
                priority: 3,
                category: "track",
                feature: "media",
                title: title,
                subtitle: MediaService.artist,
                icon: 0xF001,
                tone: "accent",
                target: "dashboard:media"
            });
        }
    }

    function notePlayback() {
        // Only the *start* of playback is an event; pause/stop is already
        // visible in the persistent media pill (§7 media pill).
        const cur = { p: MediaService.playing, a: MediaService.available };
        const prev = root.observe("playback", cur);
        if (prev === null) {
            return;
        }
        if (prev.a !== cur.a) {
            root.probeServiceProviders();
        }
        if (!cur.p || prev.p === cur.p) {
            return;
        }
        if (!IslandSettings.featureOn("media")) {
            return;
        }
        // A player that reports no track metadata still really started
        // playing — that is the observed fact. Announce the player's
        // identity instead of dropping the event on an empty title (the
        // bar's media pill already falls back the same way).
        const named = MediaService.trackTitle !== "";
        const label = named ? MediaService.trackTitle : MediaService.identity;
        if (label === "") {
            return;
        }
        root.announce({
            key: "track",
            priority: 3,
            category: "track",
            feature: "media",
            title: label,
            subtitle: named ? MediaService.artist : "Playback started",
            icon: 0xF001,
            tone: "accent",
            target: "dashboard:media"
        });
    }

    // =========================================================================
    // F06 — bluetooth connect/disconnect + accessory battery
    // =========================================================================
    Connections {
        target: BluetoothService
        function onConnectedDevicesChanged() {
            root.noteBluetooth();
        }
    }

    function btSignature() {
        const list = BluetoothService.connectedDevices;
        const parts = [];
        for (let i = 0; i < list.length; i++) {
            parts.push(list[i].address + "|" + Math.round((list[i].battery || 0) * 100));
        }
        return parts.join(";");
    }

    function deviceKind(device) {
        const n = String(device.deviceName || device.name || "").toLowerCase();
        if (n.indexOf("headphone") !== -1 || n.indexOf("headset") !== -1 || n.indexOf("ear") !== -1) {
            return 0xF025;
        }
        if (n.indexOf("phone") !== -1) {
            return 0xF095;
        }
        if (n.indexOf("laptop") !== -1) {
            return 0xF109;
        }
        if (n.indexOf("controller") !== -1 || n.indexOf("gamepad") !== -1) {
            return 0xF11B;
        }
        return 0xF00AF;
    }

    function btName(device) {
        return String(device.deviceName || device.name || "Device");
    }

    // Battery is reported as 0..1 by BlueZ; an *unknown* battery reads as
    // undefined/null and must never be presented as 0 (§F06).
    function btBatteryText(device) {
        const b = device.battery;
        if (typeof b !== "number" || !isFinite(b) || b <= 0) {
            return "";
        }
        return Math.round(b * 100) + "%";
    }

    function noteBluetooth() {
        const sig = root.btSignature();
        const prev = root.observe("bt", sig);
        if (prev === null) {
            return;
        }
        if (prev === sig) {
            return;
        }
        if (!IslandSettings.featureOn("bluetooth")) {
            return;
        }
        const now = BluetoothService.connectedDevices;
        const before = prev === "" ? [] : prev.split(";").map(s => s.split("|")[0]);

        // Newly connected: announce the newest arrival.
        for (let i = 0; i < now.length; i++) {
            if (before.indexOf(now[i].address) === -1) {
                root.announce({
                    key: "bt:" + now[i].address,
                    priority: 2,
                    category: "device",
                    feature: "bluetooth",
                    title: btName(now[i]) + " connected",
                    subtitle: batteryLine(btBatteryText(now[i])),
                    icon: deviceKind(now[i]),
                    tone: "info",
                    target: "provider:bluetooth-panel"
                });
                return;
            }
        }
        // Newly disconnected: report which one left.
        const current = [];
        for (let i = 0; i < now.length; i++) {
            current.push(now[i].address);
        }
        for (let i = 0; i < before.length; i++) {
            if (before[i] !== "" && current.indexOf(before[i]) === -1) {
                const left = BluetoothService.deviceAt(before[i]);
                root.announce({
                    key: "bt:" + before[i],
                    priority: 2,
                    category: "device",
                    feature: "bluetooth",
                    title: (left !== null ? btName(left) : "Device") + " disconnected",
                    subtitle: "",
                    icon: 0xF00AF,
                    tone: "info",
                    target: "provider:bluetooth-panel"
                });
                return;
            }
        }
    }

    function batteryLine(text) {
        return text === "" ? "" : "Battery " + text;
    }

    // Low accessory battery: BlueZ exposes no change signal for `battery`,
    // so this is the documented polling fallback — one signature check a
    // minute, armed with hysteresis so it cannot flicker.
    property var btBatteryArmed: ({})

    Timer {
        interval: 60000
        repeat: true
        running: IslandSettings.enabled && IslandSettings.featureOn("bluetooth") && BluetoothService.connectedCount > 0
        onTriggered: root.checkAccessoryBattery()
    }

    function checkAccessoryBattery() {
        const list = BluetoothService.connectedDevices;
        for (let i = 0; i < list.length; i++) {
            const d = list[i];
            const b = d.battery;
            if (typeof b !== "number" || !isFinite(b) || b <= 0) {
                continue;
            }
            const pct = Math.round(b * 100);
            const armed = root.btBatteryArmed[d.address] !== false;
            if (pct <= 20 && armed) {
                root.announce({
                    key: "bt-batt:" + d.address,
                    priority: 2,
                    category: "device",
                    feature: "bluetooth",
                    title: btName(d) + " low battery",
                    subtitle: batteryLine(btBatteryText(d)),
                    icon: 0xF00AF,
                    tone: "warning",
                    target: "provider:bluetooth-panel"
                });
                root.btBatteryArmed[d.address] = false;
            } else if (pct > 25) {
                root.btBatteryArmed[d.address] = true;
            }
        }
    }

    // =========================================================================
    // F07 — laptop battery and charging
    // =========================================================================
    Connections {
        target: PowerService
        function onChargingChanged() {
            root.noteCharging();
        }
        function onPercentageChanged() {
            root.noteBattery();
        }
        function onReadyChanged() {
            root.probeServiceProviders();
        }
    }

    property bool lowArmed: true
    property bool criticalArmed: true
    property bool fullArmed: true

    function noteCharging() {
        const prev = root.observe("charging", PowerService.charging);
        if (prev === null) {
            return;
        }
        if (!PowerService.hasBattery || !IslandSettings.featureOn("battery")) {
            return;
        }
        if (prev === PowerService.charging) {
            return;
        }
        root.lowArmed = true;
        root.criticalArmed = true;
        root.announce({
            key: "charging",
            priority: 3,
            category: "device",
            feature: "battery",
            title: PowerService.charging ? "Charger connected" : "On battery",
            subtitle: PowerService.percentage + "% · " + PowerService.stateLabel,
            icon: PowerService.charging ? 0xF0085 : 0xF0079,
            tone: PowerService.charging ? "success" : "info",
            target: "dashboard:overview"
        });
    }

    function noteBattery() {
        const pct = PowerService.percentage;
        const prev = root.observe("battery", pct);
        if (prev === null) {
            return;
        }
        if (!PowerService.hasBattery || !IslandSettings.featureOn("battery")) {
            return;
        }

        const low = IslandSettings.batteryLow;
        const critical = IslandSettings.batteryCritical;
        const hyst = IslandSettings.batteryHysteresis;

        if (root.criticalArmed && pct <= critical) {
            root.criticalArmed = false;
            root.lowArmed = false;
            IslandController.raiseWarning("battery-critical", "Battery critical", pct + "% remaining", "danger");
            root.announce({
                key: "battery",
                priority: 0,
                category: "device",
                feature: "battery",
                title: "Battery critical · " + pct + "%",
                subtitle: PowerService.stateLabel,
                icon: 0xF0083,
                tone: "danger",
                target: "dashboard:overview"
            });
            return;
        }
        if (root.lowArmed && pct <= low) {
            root.lowArmed = false;
            IslandController.raiseWarning("battery-low", "Battery low", pct + "% remaining", "warning");
            root.announce({
                key: "battery",
                priority: 1,
                category: "device",
                feature: "battery",
                title: "Battery low · " + pct + "%",
                subtitle: PowerService.stateLabel,
                icon: 0xF0083,
                tone: "warning",
                target: "dashboard:overview"
            });
            return;
        }
        // Hysteresis rearms the thresholds so a value hovering at the
        // boundary cannot re-announce every couple of percent.
        if (pct >= critical + hyst && !root.criticalArmed) {
            root.criticalArmed = true;
            IslandController.clearWarning("battery-critical");
        }
        if (pct >= low + hyst && !root.lowArmed) {
            root.lowArmed = true;
            IslandController.clearWarning("battery-low");
        }
        if (PowerService.fullyCharged && root.fullArmed && pct >= 99) {
            root.fullArmed = false;
            root.announce({
                key: "battery-full",
                priority: 3,
                category: "device",
                feature: "battery",
                title: "Battery full",
                subtitle: pct + "%",
                icon: 0xF0085,
                tone: "success",
                target: "dashboard:overview"
            });
        }
        if (!PowerService.fullyCharged) {
            root.fullArmed = true;
        }
    }

    // =========================================================================
    // F09 — connectivity
    // =========================================================================
    Connections {
        target: NetworkService
        function onConnectedChanged() {
            root.noteNetwork();
        }
        function onSsidChanged() {
            root.noteNetwork();
        }
        function onBackendAvailableChanged() {
            root.probeServiceProviders();
        }
    }

    function noteNetwork() {
        const cur = { c: NetworkService.connected, s: NetworkService.ssid };
        const prev = root.observe("network", cur);
        if (prev === null) {
            return;
        }
        if (prev.c === cur.c && prev.s === cur.s) {
            return;
        }
        if (!IslandSettings.featureOn("network")) {
            return;
        }
        if (cur.c && !prev.c) {
            root.announce({
                key: "network",
                priority: 3,
                category: "device",
                feature: "network",
                title: NetworkService.ethernetConnected ? "Wired connection up" : "Wi-Fi connected",
                subtitle: NetworkService.ethernetConnected ? NetworkService.ethernetName : NetworkService.ssid,
                icon: NetworkService.ethernetConnected ? 0xF091F : 0xF05A9,
                tone: "info",
                target: "provider:network-panel"
            });
        } else if (!cur.c && prev.c) {
            root.announce({
                key: "network",
                priority: 1,
                category: "device",
                feature: "network",
                title: "Connection lost",
                subtitle: NetworkService.wifiEnabled ? "Wi-Fi on" : "No link",
                icon: NetworkService.wifiEnabled ? 0xF05AA : 0xF091F,
                tone: "warning",
                target: "provider:network-panel"
            });
        }
    }

    // =========================================================================
    // F10 — brightness (coalesced)
    // =========================================================================
    Connections {
        target: BrightnessService
        function onPercentChanged() {
            root.noteBrightness();
        }
        function onAvailableChanged() {
            root.probeServiceProviders();
        }
    }

    function noteBrightness() {
        const cur = BrightnessService.percent;
        const prev = root.observe("brightness", cur);
        if (prev === null) {
            return;
        }
        if (prev === cur || !BrightnessService.available) {
            return;
        }
        if (!IslandSettings.featureOn("brightness")) {
            return;
        }
        root.announce({
            key: "brightness",
            priority: 1,
            category: "control",
            feature: "brightness",
            title: "Brightness " + cur + "%",
            subtitle: BrightnessService.deviceName,
            icon: 0xF00DF,
            tone: "info"
        });
    }

    // =========================================================================
    // F11 / F13 — notification previews and DND
    // =========================================================================
    Connections {
        target: NotificationService
        function onArrivalCountChanged() {
            root.noteNotification();
        }
        function onDndChanged() {
            root.noteDnd();
        }
    }

    function noteNotification() {
        const n = NotificationService.lastArrival;
        if (n === null || n === undefined) {
            return;
        }
        if (!IslandSettings.featureOn("notifications")) {
            return;
        }
        // Body content follows the configured privacy level (§13 F11).
        const showBody = IslandSettings.privacy !== "strict";
        const body = showBody && typeof n.body === "string" ? n.body : "";
        root.announce({
            key: "notification",
            priority: 2,
            category: "notification",
            feature: "notifications",
            title: n.summary !== "" ? n.summary : n.appName,
            subtitle: body !== "" ? body : n.appName,
            icon: 0xF0F3,
            tone: NotificationService.isCritical(n) ? "danger" : "info",
            target: "dashboard:alerts"
        });
    }

    function noteDnd() {
        const prev = root.observe("dnd", NotificationService.dnd);
        if (prev === null || prev === NotificationService.dnd) {
            return;
        }
        if (!IslandSettings.featureOn("dnd")) {
            return;
        }
        root.announce({
            key: "dnd",
            priority: 1,
            category: "control",
            feature: "dnd",
            title: NotificationService.dnd ? "Do not disturb on" : "Do not disturb off",
            subtitle: NotificationService.dnd ? NotificationService.count + " in history" : "",
            icon: NotificationService.dnd ? 0xF1F6 : 0xF0F3,
            tone: "info",
            target: "dashboard:alerts"
        });
    }

    // =========================================================================
    // F15 — focus timer (reuses the existing FocusTimer singleton)
    // =========================================================================
    Connections {
        target: FocusTimer
        function onCompletedSessionsChanged() {
            root.noteFocusComplete();
        }
        function onRunningChanged() {
            root.noteFocusState();
        }
        function onModeChanged() {
            root.noteFocusMode();
            root.noteFocusState();
        }
    }

    // Completion fires once, from FocusTimer's own edge — never twice for
    // one countdown, and never replayed after a restart.
    function noteFocusComplete() {
        const prev = root.observe("focusDone", FocusTimer.completedSessions);
        if (prev === null || !IslandSettings.featureOn("timer")) {
            return;
        }
        root.announce({
            key: "timer",
            priority: 1,
            category: "timer",
            feature: "timer",
            title: "Focus complete",
            subtitle: FocusTimer.focusMinutes + " minutes",
            icon: 0xF017,
            tone: "success",
            target: "dashboard:productivity"
        });
    }

    // A break only ends by running out (mode flips break -> focus).
    function noteFocusMode() {
        const prev = root.observe("focusMode", FocusTimer.mode);
        if (prev === null || prev !== "break" || FocusTimer.mode !== "focus") {
            return;
        }
        if (!IslandSettings.featureOn("timer")) {
            return;
        }
        root.announce({
            key: "timer",
            priority: 1,
            category: "timer",
            feature: "timer",
            title: "Break finished",
            subtitle: "Back to focus",
            icon: 0xF017,
            tone: "success",
            target: "dashboard:productivity"
        });
    }

    function noteFocusState() {
        const prev = root.observe("focusRunning", FocusTimer.running);
        TimerStore.syncFocusActivity();
        if (prev === null || prev === FocusTimer.running || !IslandSettings.featureOn("timer")) {
            return;
        }
        root.announce({
            key: "timer-state",
            priority: 1,
            category: "control",
            feature: "timer",
            title: FocusTimer.running ? FocusTimer.modeLabel + " started" : FocusTimer.modeLabel + " paused",
            subtitle: FocusTimer.remainingLabel,
            icon: 0xF017,
            tone: "info",
            target: "dashboard:productivity"
        });
    }

    // =========================================================================
    // F22 / F23 — recording and verified microphone capture
    // =========================================================================
    Connections {
        target: RecordingService
        function onStateChanged() {
            root.noteRecording();
        }
        function onAvailableChanged() {
            root.probeServiceProviders();
        }
    }

    function noteRecording() {
        const state = RecordingService.state;
        const prev = root.observe("recording", state);
        root.syncPrivacy();
        if (prev === null || prev === state) {
            return;
        }
        if (!IslandSettings.featureOn("recording")) {
            return;
        }
        if (state === "recording") {
            root.announce({
                key: "recording",
                priority: 1,
                category: "control",
                feature: "recording",
                title: "Recording started",
                subtitle: RecordingService.backend,
                icon: 0xF00DF,
                tone: "danger",
                target: "stack"
            });
        } else if (state === "idle" && prev === "recording") {
            root.announce({
                key: "recording",
                priority: 1,
                category: "control",
                feature: "recording",
                title: "Recording saved",
                subtitle: RecordingService.lastOutput,
                icon: 0xF00C,
                tone: "success",
                target: "stack"
            });
        } else if (state === "error") {
            root.announce({
                key: "recording",
                priority: 1,
                category: "control",
                feature: "recording",
                title: "Recording failed",
                subtitle: RecordingService.lastError,
                icon: 0xF00D,
                tone: "danger"
            });
        }
    }

    // Verified active capture: exactly the PipeWire *input stream* nodes
    // (type AudioInStream = Audio|Stream|Source). A capture *device* is
    // AudioSource and never counts, and the shell's own metering opens no
    // node — so this is real external capture, not an open permission.
    readonly property bool captureActive: {
        const vals = Pipewire.nodes.values;
        for (let i = 0; i < vals.length; i++) {
            const n = vals[i];
            if (n.isStream === true && n.type === PwNodeType.AudioInStream) {
                return true;
            }
        }
        return false;
    }

    readonly property string captureLabel: {
        const vals = Pipewire.nodes.values;
        for (let i = 0; i < vals.length; i++) {
            const n = vals[i];
            if (n.isStream === true && n.type === PwNodeType.AudioInStream) {
                const d = String(n.description !== undefined && n.description !== "" ? n.description : n.name);
                return d;
            }
        }
        return "";
    }

    // Streaming is only ever reported by the recorder itself; with no
    // OBS/websocket adapter configured there is no honest source.
    readonly property bool streamingActive: false

    onCaptureActiveChanged: root.syncPrivacy()

    function syncPrivacy() {
        IslandController.recordingActive = RecordingService.recording || RecordingService.state === "starting";
        IslandController.captureActive = root.captureActive;
        IslandController.streamingActive = root.streamingActive;
    }

    // =========================================================================
    // F24 — screenshot completion
    // =========================================================================
    Connections {
        target: ScreenshotService
        function onSavedCountChanged() {
            root.noteScreenshot();
        }
        function onAvailableChanged() {
            root.probeServiceProviders();
        }
    }

    function noteScreenshot() {
        const prev = root.observe("shots", ScreenshotService.savedCount);
        if (prev === null || prev === ScreenshotService.savedCount) {
            return;
        }
        if (!IslandSettings.featureOn("screenshot")) {
            return;
        }
        root.announce({
            key: "screenshot",
            priority: 2,
            category: "job",
            feature: "screenshot",
            title: "Screenshot saved",
            subtitle: "",
            icon: 0xF02E9,
            tone: "success",
            target: "context:screenshot"
        });
    }

    // =========================================================================
    // Workspace announcements (existing HyprlandService hook — on by
    // default; the dual gate keeps both the hook and this renderer
    // independently switchable off)
    // =========================================================================
    Connections {
        target: HyprlandService
        function onAnnouncementSerialChanged() {
            root.noteWorkspace();
        }
    }

    function noteWorkspace() {
        if (!ManagerSettings.islandAnnouncements || !IslandSettings.featureOn("workspace")) {
            return;
        }
        root.announce({
            key: "workspace",
            priority: 3,
            category: "workspace",
            feature: "workspace",
            title: HyprlandService.announcement,
            subtitle: "workspace",
            icon: 0xF0570,
            tone: "accent"
        });
    }

    // =========================================================================
    // F26 — Arch update notice (read-only, existing SystemStats probe)
    // =========================================================================
    Connections {
        target: SystemStats
        function onUpdateCountChanged() {
            root.noteUpdates();
        }
        function onUpdatesStateChanged() {
            root.probeServiceProviders();
        }
    }

    function noteUpdates() {
        const cur = SystemStats.updateCount;
        const prev = root.observe("updates", cur);
        if (prev === null) {
            return;
        }
        if (cur <= prev) {
            return;
        }
        if (!IslandSettings.featureOn("updates")) {
            return;
        }
        root.announce({
            key: "updates",
            priority: 2,
            category: "job",
            feature: "updates",
            title: cur + " update" + (cur === 1 ? "" : "s") + " available",
            subtitle: "Official repositories",
            icon: 0xF0450,
            tone: "info",
            target: "dashboard:overview"
        });
    }

    // =========================================================================
    // F27 — hardware warnings (temperature) with hysteresis and cooldown
    // =========================================================================
    property bool tempWarned: false
    property real tempLastEvent: 0

    Timer {
        interval: 30000
        repeat: true
        running: IslandSettings.enabled && IslandSettings.featureOn("hardware")
        onTriggered: root.checkTemperature()
    }

    function checkTemperature() {
        if (!SystemStats.tempAvailable) {
            IslandController.clearWarning("hardware-temp");
            return;
        }
        const t = SystemStats.cpuTemp;
        const limit = IslandSettings.tempWarning;
        const hyst = IslandSettings.tempHysteresis;
        const now = Date.now();
        if (!root.tempWarned && t >= limit) {
            root.tempWarned = true;
            root.tempLastEvent = now;
            IslandController.raiseWarning("hardware-temp", "CPU " + Math.round(t) + "°C", "Sensor reading " + Math.round(t) + "°C", "danger");
            root.announce({
                key: "hardware",
                priority: 0,
                category: "device",
                feature: "hardware",
                title: "CPU " + Math.round(t) + "°C",
                subtitle: "Above the configured " + limit + "°C threshold",
                icon: 0xF0083,
                tone: "danger",
                target: "dashboard:overview"
            });
            return;
        }
        if (root.tempWarned && t <= limit - hyst) {
            root.tempWarned = false;
            IslandController.clearWarning("hardware-temp");
            return;
        }
        // Cooldown: a condition that stays hot is not re-announced.
        if (root.tempWarned && now - root.tempLastEvent > IslandSettings.tempCooldownMinutes * 60000 && t >= limit) {
            root.tempLastEvent = now;
            IslandController.raiseWarning("hardware-temp", "CPU " + Math.round(t) + "°C", "Still above threshold", "danger");
        }
    }

    // =========================================================================
    // Capability matrix — one honest row per optional integration.
    // =========================================================================
    function probeServiceProviders() {
        IslandSettings.setProvider("clock", "ready", "SystemClock (Qt) — locale time and date");
        IslandSettings.setProvider("media", MediaService.available ? "ready" : "missing",
            MediaService.available ? "MPRIS via " + MediaService.identity : "no MPRIS player on the session bus");
        IslandSettings.setProvider("volume", AudioService.available ? "ready" : "missing",
            AudioService.available ? "PipeWire default sink · " + AudioService.sinkName : "no PipeWire default sink");
        IslandSettings.setProvider("audioDevices", AudioService.available ? "ready" : "missing",
            AudioService.available ? "Pipewire.nodes — settable via preferredDefaultAudioSink" : "no PipeWire backend");
        IslandSettings.setProvider("bluetooth", BluetoothService.available ? "ready" : "missing",
            BluetoothService.available ? "BlueZ adapter" : "no BlueZ adapter");
        IslandSettings.setProvider("battery", PowerService.hasBattery ? "ready" : "unsupported",
            PowerService.hasBattery ? "UPower display device" : "no laptop battery on this machine");
        IslandSettings.setProvider("powerProfiles", "missing", "power-profiles-daemon CLI (powerprofilesctl) not installed");
        IslandSettings.setProvider("network", NetworkService.backendAvailable ? "ready" : "missing",
            NetworkService.backendAvailable ? "NetworkManager (link state only — no internet probe configured)" : "no NetworkManager devices");
        IslandSettings.setProvider("brightness", BrightnessService.available ? "ready" : "missing",
            BrightnessService.available ? "brightnessctl · " + BrightnessService.deviceName : "no writable backlight");
        IslandSettings.setProvider("brightnessNightLight", "missing", "hyprsunset not installed — no night-light backend");
        IslandSettings.setProvider("notifications", "ready", "org.freedesktop.Notifications server owned by this shell");
        IslandSettings.setProvider("dnd", "ready", "shared NotificationService.dnd");
        IslandSettings.setProvider("timer", "ready", "FocusTimer singleton");
        IslandSettings.setProvider("timerExtras", "ready", "TimerStore (local, session scoped)");
        IslandSettings.setProvider("calendar", "ready", "EventStore (local JSON calendar)");
        IslandSettings.setProvider("tasks", "ready", "TaskStore (local JSON tasks)");
        IslandSettings.setProvider("weather", WeatherService.hasData ? "ready" : "needs-config",
            WeatherService.hasData ? "Open-Meteo cache · " + WeatherService.locationLabel : "no location configured yet");
        IslandSettings.setProvider("recording", RecordingService.available ? "ready" : "missing",
            RecordingService.available ? RecordingService.backend : "no recorder installed (wf-recorder)");
        IslandSettings.setProvider("microphone", AudioService.micAvailable ? "ready" : "missing",
            AudioService.micAvailable ? "PipeWire input node; capture state read from AudioInStream nodes" : "no input device");
        IslandSettings.setProvider("screenshot", ScreenshotService.available ? "ready" : "missing",
            ScreenshotService.available ? "grim + slurp" : "grim/slurp not installed");
        IslandSettings.setProvider("updates", "ready", "pacman -Qu (checkupdates absent) — official repos only, AUR not checked");
        IslandSettings.setProvider("hardware", SystemStats.tempAvailable ? "ready" : "unsupported",
            SystemStats.tempAvailable ? "hwmon sensor at " + SystemStats.tempPath : "no temperature sensor readable");
        IslandSettings.setProvider("storage", "missing", "no storage-job source registered (use the job IPC)");
        IslandSettings.setProvider("phone", "missing", "kdeconnect-cli not installed — no phone companion");
        IslandSettings.setProvider("keepAwake", "ready", "systemd-inhibit (idle) — verified at runtime");
        IslandSettings.setProvider("presets", "ready", "PresetStore (local JSON)");
        IslandSettings.setProvider("peek", "ready", "Wayland screencopy via PreviewController (opt-in)");
        IslandSettings.setProvider("jobs", "ready", "local IPC target `job` (session socket only)");
        IslandSettings.setProvider("workspace", "ready", "HyprlandService announcement hook");
    }

    function parseCapabilities(text) {
        const lines = String(text || "").split("\n");
        const found = {};
        for (let i = 0; i < lines.length; i++) {
            const parts = lines[i].trim().split(" ");
            if (parts.length === 2) {
                found[parts[0]] = parts[1] === "ok";
            }
        }
        IslandSettings.setProvider("clipboard", found["cliphist"] ? "ready" : "missing",
            found["cliphist"] ? "cliphist + wl-clipboard (existing collector: wl-paste --watch cliphist store)"
                : "cliphist not installed — no clipboard history backend");
        IslandSettings.setProvider("powerProfiles", found["powerprofilesctl"] ? "ready" : "missing",
            found["powerprofilesctl"] ? "powerprofilesctl" : "power-profiles-daemon CLI not installed");
        IslandSettings.setProvider("brightnessNightLight", found["hyprsunset"] ? "ready" : "missing",
            found["hyprsunset"] ? "hyprsunset" : "hyprsunset not installed — no night-light backend");
        IslandSettings.setProvider("recording", (found["wf-recorder"] || RecordingService.available) ? "ready" : "missing",
            RecordingService.available ? RecordingService.backend : "wf-recorder not installed");
        IslandSettings.setProvider("phone", found["kdeconnect-cli"] ? "ready" : "missing",
            found["kdeconnect-cli"] ? "kdeconnect-cli" : "kdeconnect-cli not installed — no phone companion");
        IslandSettings.setProvider("updates", found["checkupdates"] ? "ready" : "ready",
            found["checkupdates"] ? "checkupdates (official repos)"
                : (found["yay"] ? "pacman -Qu fallback (official repos only; AUR not checked)" : "no update source"));
        IslandSettings.setProvider("keepAwake", found["systemd-inhibit"] ? "ready" : "missing",
            found["systemd-inhibit"] ? "systemd-inhibit" : "systemd-inhibit not installed");
    }
}
