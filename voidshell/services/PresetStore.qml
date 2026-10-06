pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — Island control presets (MASTER PROMPT F18).
//
// A preset is a *named bundle of control values* the Island can apply in
// one gesture: do-not-disturb, output volume and backlight brightness.
// Every action is routed through the existing services (NotificationService,
// AudioService, BrightnessService) — there is no shell command, no new
// daemon and no free-form payload: only the allowlisted action types below
// are ever executed, and unknown ones are dropped during parse.
//
// Defaults ship with three presets that make sense on a laptop; they can be
// edited or removed and the file is repaired (never crashed on) when it is
// malformed. `saveCurrent` snapshots the live control state into a new
// preset so the user does not have to hand-edit JSON.
Singleton {
    id: root

    property var presets: []
    property bool loaded: false
    property string lastApplied: ""

    readonly property int count: root.presets.length

    readonly property var actionTypes: ["dnd", "volume", "brightness", "mute"]

    FileView {
        id: file
        path: StorageService.ready ? StorageService.path("island-presets.json") : ""
        printErrors: false
        onLoaded: root.parse(file.text())
        // A missing file is the normal fresh-system state: fall back to the
        // shipped presets so the surface is never empty on first open.
        onLoadFailed: root.parse("")
    }

    function defaults() {
        return [
            {
                id: "focus",
                name: "Focus",
                icon: 0xF017,
                actions: [
                    { type: "dnd", value: true },
                    { type: "brightness", value: 80 }
                ]
            },
            {
                id: "presentation",
                name: "Presentation",
                icon: 0xF02E9,
                actions: [
                    { type: "dnd", value: true },
                    { type: "brightness", value: 100 },
                    { type: "volume", value: 60 }
                ]
            },
            {
                id: "movie",
                name: "Movie",
                icon: 0xF001,
                actions: [
                    { type: "dnd", value: true },
                    { type: "brightness", value: 35 },
                    { type: "volume", value: 45 }
                ]
            }
        ];
    }

    function parse(content) {
        root.loaded = true;
        if (content && content.trim() !== "") {
            try {
                const data = JSON.parse(content);
                const list = Array.isArray(data) ? data : (Array.isArray(data.presets) ? data.presets : []);
                const clean = root.normalizeList(list);
                if (clean.length > 0) {
                    root.presets = clean;
                    return;
                }
            } catch (e) {
                console.warn("[voidshell] island-presets.json malformed, using defaults:", e);
            }
        }
        root.presets = root.defaults();
        root.save();
    }

    function normalizeList(list) {
        const out = [];
        for (let i = 0; i < list.length; i++) {
            const p = root.normalize(list[i], i);
            if (p !== null) {
                out.push(p);
            }
        }
        return out;
    }

    // Keeps only allowlisted action types with sane values; a preset whose
    // actions are all unknown is dropped rather than half-applied.
    function normalize(raw, index) {
        if (!raw || typeof raw !== "object") {
            return null;
        }
        const name = String(raw.name === undefined ? "" : raw.name).trim().slice(0, 32);
        if (name === "") {
            return null;
        }
        const id = String(raw.id === undefined ? "" : raw.id).trim().replace(/[^a-z0-9_-]/gi, "").slice(0, 32) || ("p" + index);
        const actions = [];
        const src = Array.isArray(raw.actions) ? raw.actions : [];
        for (let i = 0; i < src.length; i++) {
            const a = src[i];
            if (!a || typeof a !== "object") {
                continue;
            }
            const type = String(a.type === undefined ? "" : a.type);
            if (root.actionTypes.indexOf(type) === -1) {
                continue;
            }
            if (type === "dnd" || type === "mute") {
                actions.push({ type: type, value: a.value === true });
            } else {
                const v = typeof a.value === "number" && isFinite(a.value) ? a.value : NaN;
                if (isNaN(v)) {
                    continue;
                }
                actions.push({ type: type, value: Math.max(0, Math.min(100, Math.round(v))) });
            }
        }
        if (actions.length === 0) {
            return null;
        }
        return {
            id: id,
            name: name,
            icon: typeof raw.icon === "number" && isFinite(raw.icon) ? raw.icon : 0xF00C,
            builtin: raw.builtin === true,
            actions: actions
        };
    }

    function save() {
        if (!StorageService.ready || !root.loaded) {
            return;
        }
        file.setText(JSON.stringify({
            version: 1,
            presets: root.presets
        }, null, 2));
    }

    function byId(id) {
        const sid = String(id === undefined ? "" : id);
        for (let i = 0; i < root.presets.length; i++) {
            if (root.presets[i].id === sid) {
                return root.presets[i];
            }
        }
        return null;
    }

    // Human-readable summary of what a preset will change ("DND, 80%
    // brightness") — used by the stack row so the effect is visible
    // before it happens.
    function describe(preset) {
        if (!preset) {
            return "";
        }
        const parts = [];
        for (let i = 0; i < preset.actions.length; i++) {
            const a = preset.actions[i];
            if (a.type === "dnd") {
                parts.push(a.value ? "DND on" : "DND off");
            } else if (a.type === "volume") {
                parts.push("volume " + a.value + "%");
            } else if (a.type === "brightness") {
                parts.push("brightness " + a.value + "%");
            } else if (a.type === "mute") {
                parts.push(a.value ? "mute" : "unmute");
            }
        }
        return parts.join(" · ");
    }

    // Applies through the existing services only. Returns the number of
    // actions actually applied (0 when the preset or a provider refuses,
    // which the caller reports honestly — never as a success).
    function apply(id) {
        const preset = root.byId(id);
        if (!preset) {
            return 0;
        }
        let applied = 0;
        for (let i = 0; i < preset.actions.length; i++) {
            const a = preset.actions[i];
            if (a.type === "dnd") {
                NotificationService.dnd = a.value;
                applied++;
            } else if (a.type === "volume" && AudioService.available) {
                AudioService.setVolume(a.value / 100);
                applied++;
            } else if (a.type === "mute" && AudioService.available) {
                AudioService.setMuted(a.value);
                applied++;
            } else if (a.type === "brightness" && BrightnessService.available) {
                BrightnessService.setLevel(a.value / 100);
                applied++;
            }
        }
        root.lastApplied = preset.name;
        if (applied > 0) {
            AnnouncementEngine.announce({
                key: "presets",
                priority: 2,
                category: "control",
                feature: "presets",
                title: preset.name + " applied",
                subtitle: root.describe(preset),
                icon: preset.icon,
                tone: "accent",
                target: "stack"
            });
        }
        return applied;
    }

    // Snapshot of the live control state, so a user-defined preset is made
    // from what the machine is doing right now — never from guessed values.
    function saveCurrent(name) {
        const label = String(name === undefined ? "" : name).trim().slice(0, 32);
        if (label === "") {
            return false;
        }
        const actions = [{ type: "dnd", value: NotificationService.dnd }];
        if (AudioService.available) {
            actions.push({ type: "volume", value: AudioService.volumePercent });
        }
        if (BrightnessService.available) {
            actions.push({ type: "brightness", value: BrightnessService.percent });
        }
        const id = label.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 24) || ("p" + Date.now().toString(36));
        const list = root.presets.filter(p => p.id !== id);
        list.push({ id: id, name: label, icon: 0xF00C, builtin: false, actions: actions });
        root.presets = list;
        root.save();
        return true;
    }

    function remove(id) {
        const sid = String(id === undefined ? "" : id);
        const next = root.presets.filter(p => p.id !== sid);
        if (next.length !== root.presets.length) {
            root.presets = next;
            root.save();
            return true;
        }
        return false;
    }
}
