pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — Living State Island settings (MASTER PROMPT §21).
//
// One JSON store (`~/.local/share/voidshell/island.json`) written through
// FileView exactly like TaskStore/ManagerSettings: a missing or malformed
// file degrades to the documented defaults instead of breaking the shell,
// and every write is atomic. Shortcuts are NOT stored here — they live in
// ~/.config/hypr/hyprland.lua like every other binding.
//
// Two kinds of state live in this file:
//
//   persisted  — per-feature enable + announcement policy, durations,
//                pinning, hover, animation, privacy, DND/fullscreen and
//                monitor policy, thresholds, refresh intervals, history
//                retention, sensitive exclusions, diagnostics.
//   runtime    — the provider capability matrix (`providers`), written by
//                IslandProviders at startup and on every re-probe. It is
//                never saved: availability is a fact about the running
//                session, not a preference.
//
// Availability vocabulary (§21): ready | disabled | needs-config |
// missing | denied | unsupported | stale | error. `diagnostics()` renders
// it for the settings surface so a feature can be honestly labelled
// without ever showing a fake success.
Singleton {
    id: root

    // --- defaults -------------------------------------------------------
    readonly property var defaultFeatures: ({
        clock: true,
        media: true,
        volume: true,
        audioDevices: true,
        bluetooth: true,
        battery: true,
        powerProfiles: true,
        network: true,
        brightness: true,
        notifications: true,
        dnd: true,
        digest: true,
        timer: true,
        timers: true,
        calendar: true,
        tasks: true,
        presets: true,
        keepAwake: true,
        weather: true,
        recording: true,
        microphone: true,
        screenshot: true,
        clipboard: true,
        updates: true,
        hardware: true,
        storage: true,
        phone: true,
        jobs: true,
        workspace: true,
        peek: false,
        progressEdge: false,
        levelAccent: false
    })

    // Per-feature announcement policy: "all" | "important" | "none".
    readonly property var defaultAnnounce: ({
        media: "all",
        volume: "all",
        audioDevices: "all",
        bluetooth: "all",
        battery: "all",
        powerProfiles: "important",
        network: "all",
        brightness: "all",
        notifications: "all",
        dnd: "important",
        digest: "important",
        timer: "all",
        timers: "all",
        calendar: "all",
        tasks: "all",
        presets: "important",
        keepAwake: "important",
        weather: "all",
        recording: "all",
        microphone: "important",
        screenshot: "all",
        clipboard: "none",
        updates: "important",
        hardware: "all",
        storage: "important",
        phone: "important",
        jobs: "all",
        workspace: "all"
    })

    readonly property var defaults: ({
        enabled: true,
        features: root.defaultFeatures,
        announce: root.defaultAnnounce,
        durationControl: 1200,
        durationTrack: 3000,
        durationDevice: 3000,
        durationNotification: 4000,
        durationJob: 4000,
        durationTimer: 4000,
        durationWorkspace: 800,
        queueLimit: 20,
        hoverPreview: false,
        hoverDelayMs: 400,
        animation: "inherit",
        privacy: "standard",
        dndSuppress: true,
        fullscreenPolicy: "quiet",
        monitorPolicy: "invoking",
        batteryLow: 15,
        batteryCritical: 5,
        batteryHysteresis: 2,
        tempWarning: 80,
        tempHysteresis: 3,
        tempCooldownMinutes: 10,
        updateCheckMinutes: 360,
        historyRetention: 50,
        completionSound: false,
        showSeconds: false,
        clipboardMaxEntries: 60,
        reminderLeadMinutes: 10,
        sensitiveExclusions: []
    })

    property bool enabled: true
    property var features: ({})
    property var announce: ({})

    property int durationControl: 1200
    property int durationTrack: 3000
    property int durationDevice: 3000
    property int durationNotification: 4000
    property int durationJob: 4000
    property int durationTimer: 4000
    property int durationWorkspace: 800
    property int queueLimit: 20

    property bool hoverPreview: false
    property int hoverDelayMs: 400

    // "inherit" follows the shell motion model (ManagerSettings.animation)
    // so one switch still drives the whole desktop; the explicit modes
    // let the Island be quieter or louder than the rest on purpose.
    property string animation: "inherit"
    property string privacy: "standard"
    property bool dndSuppress: true
    property string fullscreenPolicy: "quiet"
    property string monitorPolicy: "invoking"

    property int batteryLow: 15
    property int batteryCritical: 5
    property int batteryHysteresis: 2
    property int tempWarning: 80
    property int tempHysteresis: 3
    property int tempCooldownMinutes: 10

    property int updateCheckMinutes: 360
    property int historyRetention: 50
    property bool completionSound: false
    property bool showSeconds: false
    property int clipboardMaxEntries: 60
    property int reminderLeadMinutes: 10
    property var sensitiveExclusions: []

    property bool loaded: false

    // --- runtime capability matrix (never persisted) --------------------
    // sourceId -> { state, note }. Maintained by IslandProviders.
    property var providers: ({})
    property int providerSerial: 0

    // --- motion model ---------------------------------------------------
    // Island animations follow the shell unless overridden: "off" kills
    // every duration, "reduced" keeps fades and drops movement, exactly
    // like ManagerSettings so reduced-motion is honoured from one place.
    readonly property bool motionEnabled: root.effectiveAnimation !== "off"
    readonly property bool motionReduced: root.effectiveAnimation === "reduced"
    readonly property string effectiveAnimation: {
        if (root.animation !== "inherit") {
            return root.animation;
        }
        return ManagerSettings.animation;
    }
    // Content crossfade 120–180 ms (§19), row transitions 120–180 ms,
    // island open/close 180–260 ms — all collapse to 0 when motion is off.
    readonly property int durationCrossfade: !root.motionEnabled ? 0 : (root.motionReduced ? 120 : 160)
    readonly property int durationRow: !root.motionEnabled ? 0 : (root.motionReduced ? 120 : 160)
    readonly property int durationSurface: !root.motionEnabled ? 0 : (root.motionReduced ? 140 : 220)

    FileView {
        id: file
        path: StorageService.ready ? StorageService.path("island.json") : ""
        printErrors: false
        onLoaded: root.parse(file.text())
        onLoadFailed: root.parse("")
    }

    function parse(content) {
        root.loaded = true;
        let data = {};
        if (content && content.trim() !== "") {
            try {
                data = JSON.parse(content);
                if (data === null || typeof data !== "object" || Array.isArray(data)) {
                    data = {};
                }
            } catch (e) {
                console.warn("[voidshell] island.json malformed, using defaults:", e);
                data = {};
            }
        }
        root.apply(data);
    }

    function pick(map, key, fallback) {
        if (map && typeof map === "object" && typeof map[key] === "string") {
            return map[key];
        }
        return fallback;
    }

    function clampInt(value, min, max, fallback) {
        if (typeof value !== "number" || !isFinite(value)) {
            return fallback;
        }
        return Math.max(min, Math.min(max, Math.round(value)));
    }

    function apply(data) {
        const d = root.defaults;
        root.enabled = typeof data.enabled === "boolean" ? data.enabled : d.enabled;

        const f = {};
        for (const k in d.features) {
            const v = data.features && typeof data.features[k] === "boolean" ? data.features[k] : d.features[k];
            f[k] = v;
        }
        root.features = f;

        const a = {};
        for (const k in d.announce) {
            const v = root.pick(data.announce, k, d.announce[k]);
            a[k] = (v === "none" || v === "important" || v === "all") ? v : d.announce[k];
        }
        root.announce = a;

        root.durationControl = root.clampInt(data.durationControl, 400, 10000, d.durationControl);
        root.durationTrack = root.clampInt(data.durationTrack, 500, 15000, d.durationTrack);
        root.durationDevice = root.clampInt(data.durationDevice, 500, 15000, d.durationDevice);
        root.durationNotification = root.clampInt(data.durationNotification, 500, 15000, d.durationNotification);
        root.durationJob = root.clampInt(data.durationJob, 500, 15000, d.durationJob);
        root.durationTimer = root.clampInt(data.durationTimer, 500, 15000, d.durationTimer);
        root.durationWorkspace = root.clampInt(data.durationWorkspace, 200, 5000, d.durationWorkspace);
        root.queueLimit = root.clampInt(data.queueLimit, 4, 100, d.queueLimit);

        root.hoverPreview = typeof data.hoverPreview === "boolean" ? data.hoverPreview : d.hoverPreview;
        root.hoverDelayMs = root.clampInt(data.hoverDelayMs, 100, 2000, d.hoverDelayMs);

        root.animation = (data.animation === "full" || data.animation === "reduced" || data.animation === "off") ? data.animation : "inherit";
        root.privacy = data.privacy === "strict" ? "strict" : "standard";
        root.dndSuppress = typeof data.dndSuppress === "boolean" ? data.dndSuppress : d.dndSuppress;
        root.fullscreenPolicy = (data.fullscreenPolicy === "show" || data.fullscreenPolicy === "critical") ? data.fullscreenPolicy : "quiet";
        root.monitorPolicy = data.monitorPolicy === "focused" ? "focused" : "invoking";

        root.batteryLow = root.clampInt(data.batteryLow, 1, 50, d.batteryLow);
        root.batteryCritical = root.clampInt(data.batteryCritical, 1, 20, d.batteryCritical);
        root.batteryHysteresis = root.clampInt(data.batteryHysteresis, 0, 10, d.batteryHysteresis);
        root.tempWarning = root.clampInt(data.tempWarning, 40, 110, d.tempWarning);
        root.tempHysteresis = root.clampInt(data.tempHysteresis, 0, 20, d.tempHysteresis);
        root.tempCooldownMinutes = root.clampInt(data.tempCooldownMinutes, 1, 240, d.tempCooldownMinutes);

        root.updateCheckMinutes = root.clampInt(data.updateCheckMinutes, 60, 4320, d.updateCheckMinutes);
        root.historyRetention = root.clampInt(data.historyRetention, 5, 500, d.historyRetention);
        root.completionSound = typeof data.completionSound === "boolean" ? data.completionSound : d.completionSound;
        root.showSeconds = typeof data.showSeconds === "boolean" ? data.showSeconds : d.showSeconds;
        root.clipboardMaxEntries = root.clampInt(data.clipboardMaxEntries, 5, 500, d.clipboardMaxEntries);
        root.reminderLeadMinutes = root.clampInt(data.reminderLeadMinutes, 0, 1440, d.reminderLeadMinutes);
        root.sensitiveExclusions = Array.isArray(data.sensitiveExclusions)
            ? data.sensitiveExclusions.filter(c => typeof c === "string" && c !== "")
            : d.sensitiveExclusions;

        console.log("[voidshell] island: enabled=" + root.enabled
            + " animation=" + root.effectiveAnimation
            + " privacy=" + root.privacy
            + " queue=" + root.queueLimit
            + " hover=" + root.hoverPreview);
    }

    function save() {
        if (!StorageService.ready || !root.loaded) {
            return;
        }
        file.setText(JSON.stringify({
            version: 1,
            enabled: root.enabled,
            features: root.features,
            announce: root.announce,
            durationControl: root.durationControl,
            durationTrack: root.durationTrack,
            durationDevice: root.durationDevice,
            durationNotification: root.durationNotification,
            durationJob: root.durationJob,
            durationTimer: root.durationTimer,
            durationWorkspace: root.durationWorkspace,
            queueLimit: root.queueLimit,
            hoverPreview: root.hoverPreview,
            hoverDelayMs: root.hoverDelayMs,
            animation: root.animation,
            privacy: root.privacy,
            dndSuppress: root.dndSuppress,
            fullscreenPolicy: root.fullscreenPolicy,
            monitorPolicy: root.monitorPolicy,
            batteryLow: root.batteryLow,
            batteryCritical: root.batteryCritical,
            batteryHysteresis: root.batteryHysteresis,
            tempWarning: root.tempWarning,
            tempHysteresis: root.tempHysteresis,
            tempCooldownMinutes: root.tempCooldownMinutes,
            updateCheckMinutes: root.updateCheckMinutes,
            historyRetention: root.historyRetention,
            completionSound: root.completionSound,
            showSeconds: root.showSeconds,
            clipboardMaxEntries: root.clipboardMaxEntries,
            reminderLeadMinutes: root.reminderLeadMinutes,
            sensitiveExclusions: root.sensitiveExclusions
        }, null, 2));
    }

    // --- feature helpers -------------------------------------------------
    function featureOn(id) {
        if (!root.enabled) {
            return false;
        }
        return root.features[id] !== false;
    }

    function setFeature(id, on) {
        const f = {};
        for (const k in root.features) {
            f[k] = root.features[k];
        }
        f[id] = on === true;
        root.features = f;
        root.save();
    }

    // "all" | "important" | "none" for one feature.
    function announcePolicy(id) {
        const v = root.announce[id];
        return v === undefined ? "all" : v;
    }

    function setAnnouncePolicy(id, policy) {
        const a = {};
        for (const k in root.announce) {
            a[k] = root.announce[k];
        }
        a[id] = (policy === "none" || policy === "important" || policy === "all") ? policy : "all";
        root.announce = a;
        root.save();
    }

    function setEnabled(on) {
        root.enabled = on === true;
        root.save();
    }

    // --- runtime capability matrix ---------------------------------------
    function setProvider(id, state, note) {
        const p = {};
        for (const k in root.providers) {
            p[k] = root.providers[k];
        }
        p[id] = { state: String(state || "unsupported"), note: String(note || "") };
        root.providers = p;
        root.providerSerial = root.providerSerial + 1;
    }

    function providerState(id) {
        const p = root.providers[id];
        return p === undefined ? "unknown" : p.state;
    }

    function providerNote(id) {
        const p = root.providers[id];
        return p === undefined ? "" : p.note;
    }

    // Settings-facing list: one row per configured feature with its
    // enablement and the live availability of its provider.
    function diagnostics() {
        const rows = [];
        for (const id in root.features) {
            rows.push({
                id: id,
                enabled: root.features[id] !== false,
                announce: root.announcePolicy(id),
                state: root.featureOn(id) ? (root.providers[id] === undefined ? "ready" : root.providers[id].state) : "disabled",
                note: root.providers[id] === undefined ? "" : root.providers[id].note
            });
        }
        return rows;
    }
}
