pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — central theme authority (PRD §20, §34.10, §35).
// Holds the named preset list, the dark/light mode and the optional
// dynamic wallpaper tone. Every shell token flows out through Colors,
// so a change here repaints the whole shell through bindings.
//
// Design rules:
//  - The default preset is "Void Wallpaper" and its values are the exact
//    PRD §7–10 palette (identity hue shift, no derived drift).
//  - Presets change accent families, support tones and the hue of
//    border/glow tokens only. Glass surfaces, text ladders and semantic
//    colors are mode-scoped so contrast stays verified (PRD §20.2:
//    light mode is a complete palette, not inverted text).
//  - The dynamic wallpaper tone is an accent-family override pushed in
//    by WallpaperService when the palette mode is "dynamic" (§21.2).
//    Semantic roles are never recalculated from wallpaper pixels.
Singleton {
    id: root

    // --- persisted state -------------------------------------------------
    property string presetId: "void"
    property string mode: "dark" // dark | light
    property bool loaded: false

    // Wallpaper-derived accent family (null = follow the preset).
    property var dynTone: null

    // Bumped on any token-affecting change; Canvas painters watch it so
    // drawn surfaces repaint when the theme moves.
    property int revision: 0

    // --- presets (PRD §20: named themes with palette-dot previews) -------
    readonly property var presets: [
        {
            id: "void", name: "Void Wallpaper", default: true,
            keywords: "default void violet purple ink parchment shell",
            accent: { primary: "#8B4DFF", light: "#B487FF", tint: "#C9A7FF", strong: "#6A2DE2", deep: "#4A1D9B" },
            support: { plum: "#56346C", plumMuted: "#40304D", indigo: "#302747", indigoDeep: "#211B31" }
        },
        {
            id: "frost", name: "Frost",
            keywords: "blue ice icy arctic cold cyan sky winter",
            accent: { primary: "#4DA6FF", light: "#86C7FF", tint: "#A9D7FF", strong: "#2478DB", deep: "#17518F" },
            support: { plum: "#33506E", plumMuted: "#293F57", indigo: "#27384F", indigoDeep: "#1B283A" }
        },
        {
            id: "mint", name: "Mint",
            keywords: "green mint teal emerald nature awwwards",
            accent: { primary: "#2DD4A7", light: "#6FE7C6", tint: "#98F0DA", strong: "#149876", deep: "#0C6550" },
            support: { plum: "#2C5A4E", plumMuted: "#23453C", indigo: "#234039", indigoDeep: "#182C28" }
        },
        {
            id: "solar", name: "Solar",
            keywords: "amber gold orange warm sun solar yellow sunset",
            accent: { primary: "#F5A623", light: "#FFC96B", tint: "#FFDCA0", strong: "#C97D0A", deep: "#8A5506" },
            support: { plum: "#6B4A24", plumMuted: "#513A1E", indigo: "#49351F", indigoDeep: "#332516" }
        },
        {
            id: "rose", name: "Rose",
            keywords: "pink rose red magenta blush love",
            accent: { primary: "#FF5B8A", light: "#FF96B5", tint: "#FFB9CC", strong: "#DB2E66", deep: "#97204A" },
            support: { plum: "#6B3049", plumMuted: "#51263A", indigo: "#4B2739", indigoDeep: "#351B29" }
        },
        {
            id: "ocean", name: "Ocean",
            keywords: "cyan teal aqua sea sky blue water turquoise",
            accent: { primary: "#22C3E6", light: "#6BD9F0", tint: "#9DE8F6", strong: "#0E93B4", deep: "#0A6178" },
            support: { plum: "#2C5564", plumMuted: "#23414D", indigo: "#24404C", indigoDeep: "#192D37" }
        }
    ];

    readonly property bool light: root.mode === "light"

    function presetById(id) {
        for (var i = 0; i < root.presets.length; i++) {
            if (root.presets[i].id === id) {
                return root.presets[i];
            }
        }
        return root.presets[0];
    }

    readonly property var preset: root.presetById(root.presetId)

    // Active tone: the wallpaper override wins only while WallpaperService
    // reports dynamic mode; otherwise the selected preset is authoritative.
    readonly property var tone: root.dynTone !== null ? root.dynTone : {
        "accent": root.preset.accent,
        "support": root.preset.support
    }

    // --- persistence (PRD §35: theme.json) -------------------------------
    FileView {
        id: file
        path: StorageService.ready ? StorageService.path("theme.json") : ""
        printErrors: false
        onLoaded: root.parse(file.text())
        // Missing theme.json on first launch: loadFailed (not loaded);
        // keep the PRD defaults but flip loaded so setPreset/setMode can
        // persist the first change.
        onLoadFailed: root.parse("")
    }

    function parse(content) {
        root.loaded = true;
        if (!content || content.trim() === "") {
            return; // missing file keeps the PRD defaults.
        }
        try {
            const data = JSON.parse(content);
            if (data && typeof data.presetId === "string") {
                const found = root.presetById(data.presetId);
                // presetById falls back to the default entry for unknown ids.
                root.presetId = found.id;
            }
            if (data && (data.mode === "dark" || data.mode === "light")) {
                root.mode = data.mode;
            }
            if (data && data.dynTone && typeof data.dynTone === "object") {
                root.dynTone = data.dynTone;
            }
        } catch (e) {
            // Malformed state never crashes the shell (PRD §35).
            console.warn("[voidshell] theme.json malformed, keeping defaults:", e);
        }
        root.revision++;
    }

    function save() {
        if (!StorageService.ready || !root.loaded) {
            return;
        }
        file.setText(JSON.stringify({
            version: 1,
            presetId: root.presetId,
            mode: root.mode,
            dynTone: root.dynTone
        }, null, 2));
    }

    // --- public API (PRD §20.2, §34.10) ----------------------------------
    function setPreset(id) {
        const found = root.presetById(id);
        root.presetId = found.id;
        root.revision++;
        root.save();
        ToastService.push("Theme", "Switched to " + found.name, "", "info");
    }

    function setMode(mode) {
        if (mode !== "dark" && mode !== "light") {
            return;
        }
        if (root.mode === mode) {
            return;
        }
        root.mode = mode;
        root.revision++;
        root.save();
    }

    // Pushed by WallpaperService (dynamic palette mode, PRD §21.2).
    function setDynamicTone(tone) {
        root.dynTone = tone;
        root.revision++;
        root.save();
    }

    // --- color math helpers ---------------------------------------------
    function hexToRgb(hex) {
        var h = String(hex).replace("#", "");
        if (h.length === 3) {
            h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
        }
        return [parseInt(h.substr(0, 2), 16) / 255, parseInt(h.substr(2, 2), 16) / 255, parseInt(h.substr(4, 2), 16) / 255];
    }

    function rgbToHsl(r, g, b) {
        const max = Math.max(r, g, b);
        const min = Math.min(r, g, b);
        const l = (max + min) / 2;
        var h = 0;
        var s = 0;
        if (max !== min) {
            const d = max - min;
            s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
            if (max === r) h = (g - b) / d + (g < b ? 6 : 0);
            else if (max === g) h = (b - r) / d + 2;
            else h = (r - g) / d + 4;
            h /= 6;
        }
        return [h, s, l];
    }

    function hslToRgb(h, s, l) {
        if (s === 0) {
            return [l, l, l];
        }
        const hue2rgb = (p, q, t) => {
            var tt = t;
            if (tt < 0) tt += 1;
            if (tt > 1) tt -= 1;
            if (tt < 1 / 6) return p + (q - p) * 6 * tt;
            if (tt < 1 / 2) return q;
            if (tt < 2 / 3) return p + (q - p) * (2 / 3 - tt) * 6;
            return p;
        };
        const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
        const p = 2 * l - q;
        return [hue2rgb(p, q, h + 1 / 3), hue2rgb(p, q, h), hue2rgb(p, q, h - 1 / 3)];
    }

    // Rotate an [r,g,b] triple (0–255) by a hue delta while keeping
    // saturation/lightness. A delta of 0 is the identity, so the default
    // preset reproduces the PRD border/glow values exactly.
    function rotateTriple(triple, deltaNorm) {
        if (!deltaNorm) {
            return triple;
        }
        const c = root.rgbToHsl(triple[0] / 255, triple[1] / 255, triple[2] / 255);
        var h = c[0] + deltaNorm;
        h = h - Math.floor(h);
        const out = root.hslToRgb(h, c[1], c[2]);
        return [out[0] * 255, out[1] * 255, out[2] * 255];
    }

    function rgba(triple, alpha) {
        return Qt.rgba(triple[0] / 255, triple[1] / 255, triple[2] / 255, alpha);
    }

    function colorOf(hex) {
        const t = root.hexToRgb(hex);
        return Qt.rgba(t[0], t[1], t[2], 1);
    }

    // Hue delta between the active accent family and the void default.
    // Used to carry border/glow/highlight triples along with the preset.
    readonly property real hueDelta: {
        const base = root.rgbToHsl.apply(null, root.hexToRgb(root.presetById("void").accent.primary));
        const cur = root.rgbToHsl.apply(null, root.hexToRgb(root.tone.accent.primary));
        return cur[0] - base[0];
    }

    // --- wallpaper tone extraction (PRD §21.2) ---------------------------
    // Restrained: only accent/support families are derived from pixels;
    // text, glass and semantic tokens keep their verified values.
    //
    // Canvas pixel reads need a rendered window, and services are
    // singletons without one, so the grab surface lives in PaletteGrab
    // (hosted by shell.qml). This service only publishes the requested
    // URL (grabUrl) and maths the RGBA buffer PaletteGrab delivers.
    property string grabUrl: ""

    function computeToneFor(url) {
        root.grabUrl = "";
        root.grabUrl = url;
    }

    function grabDone() {
        root.grabUrl = "";
    }

    function adoptPixelData(data) {
        // Circular-mean hue over saturated mid-tone pixels.
        var sr = 0;
        var sg = 0;
        var sb = 0;
        for (var i = 0; i < data.length; i += 4) {
            const r = data[i] / 255;
            const g = data[i + 1] / 255;
            const b = data[i + 2] / 255;
            const hsl = root.rgbToHsl(r, g, b);
            if (hsl[2] > 0.92 || hsl[2] < 0.08) {
                continue; // parchment paper and black ink carry no accent
            }
            const w = (1 - Math.abs(2 * hsl[2] - 1)) * hsl[1];
            if (w < 0.15) {
                // Weight by real chroma, not raw HSL saturation: pale
                // surfaces (parchment paper) carry little color signal
                // despite a mid saturation reading.
                continue;
            }
            const ang = hsl[0] * Math.PI * 2;
            sr += Math.cos(ang) * w;
            sg += Math.sin(ang) * w;
            sb += w;
        }
        if (sb < 0.5) {
            // Nearly monochrome wallpaper: stay with the chosen preset
            // instead of inventing an accent (restrained by design).
            root.setDynamicTone(null);
            ToastService.push("Wallpaper", "Palette unchanged (image too neutral)", "", "warning");
            return;
        }
        var hue = Math.atan2(sg, sr) / (Math.PI * 2);
        if (hue < 0) hue += 1;
        const s = 0.62;
        const mk = (l, sat) => {
            const c = root.hslToRgb(hue, sat, l);
            const t = [c[0] * 255, c[1] * 255, c[2] * 255];
            const hex = t.map(v => Math.round(v).toString(16).padStart(2, "0")).join("");
            return "#" + hex.toUpperCase();
        };
        const tone = {
            accent: {
                primary: mk(0.55, s),
                light: mk(0.73, s - 0.08),
                tint: mk(0.82, s - 0.16),
                strong: mk(0.42, s + 0.06),
                deep: mk(0.27, s + 0.04)
            },
            support: {
                plum: mk(0.30, 0.30),
                plumMuted: mk(0.23, 0.26),
                indigo: mk(0.20, 0.28),
                indigoDeep: mk(0.14, 0.24)
            }
        };
        root.setDynamicTone(tone);
        ToastService.push("Wallpaper", "Dynamic palette applied", "", "info");
    }
}
