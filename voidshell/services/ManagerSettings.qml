pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — Shadow Spaces desktop-manager settings (plan §3).
// One JSON store (`~/.local/share/voidshell/desktop-manager.json`),
// written through FileView exactly like TaskStore: malformed or missing
// files degrade to the documented defaults instead of breaking the
// shell, and every write is atomic so a partial write cannot corrupt
// existing state. Shortcuts are intentionally NOT stored here — they
// live in ~/.config/hypr/hyprland.lua where every other binding lives.
Singleton {
    id: root

    // --- defaults (plan §3) --------------------------------------------
    // managerEnabled   : the dash pill and the Stage shelf; false
    //                    restores the previous numbered workspace strip
    //                    (§16). The overview stays available — it is
    //                    the PRD §24 surface behind Super+W, and the
    //                    legacy fallback must not kill that binding.
    // shelfEnabled     : the Stage shelf is opt-in.
    // shelfSide        : "left" (spec §9) or "right".
    // edgeReveal       : dwell-at-edge reveal, off by default.
    // animation        : "full" | "reduced" (fades only) | "off".
    // maxStackedPreviews: previews shown per card (default 3).
    // livePreviewBudget: concurrent live captures (small by default).
    // scope            : "monitor" (focused monitor) | "all".
    // sensitiveExclusions: app classes never captured (navigation ok).
    // fullscreenPolicy : "explicit-only" (overview overlays fullscreen
    //                    only when the user invoked it).
    // islandAnnouncements: the Living State Island announces a real
    //                    workspace switch (§23 — the clock island is the
    //                    only surface that does). Both the hook and the
    //                    renderer keep their own check, so setting this
    //                    false still silences everything.
    readonly property var defaults: ({
        managerEnabled: true,
        shelfEnabled: false,
        shelfSide: "left",
        edgeReveal: false,
        animation: "full",
        maxStackedPreviews: 3,
        livePreviewBudget: 2,
        scope: "monitor",
        sensitiveExclusions: [],
        fullscreenPolicy: "explicit-only",
        islandAnnouncements: true
    })

    property bool managerEnabled: true
    property bool shelfEnabled: false
    property string shelfSide: "left"
    property bool edgeReveal: false
    property string animation: "full"
    property int maxStackedPreviews: 3
    property int livePreviewBudget: 2
    property string scope: "monitor"
    property var sensitiveExclusions: []
    property string fullscreenPolicy: "explicit-only"
    property bool islandAnnouncements: true

    property bool loaded: false

    // Motion helpers: one place every surface reads durations from, so
    // "reduced"/"off" cannot be forgotten by a single component (§12).
    //
    //   "full"    — every duration at its normal value;
    //   "reduced" — *fades only*: movement (slides, lifts, jumps) is 0
    //               so nothing travels across the screen, while fades
    //               stay, shortened;
    //   "off"     — nothing animates.
    readonly property bool motionEnabled: root.animation !== "off"
    readonly property bool motionReduced: root.animation === "reduced"
    // Movement — full mode only.
    readonly property int durationPill: root.motionEnabled && !root.motionReduced ? 190 : 0
    readonly property int durationHover: root.motionEnabled && !root.motionReduced ? 140 : 0
    readonly property int durationShelf: root.motionEnabled && !root.motionReduced ? 210 : 0
    // The overview's active-card emphasis (scale + bloom): the card
    // grows/shrinks, so it is movement — full mode only.
    readonly property int durationCard: root.motionEnabled && !root.motionReduced ? 200 : 0
    // Fades — kept (and shortened) under "reduced".
    readonly property int durationFade: !root.motionEnabled ? 0 : (root.motionReduced ? 120 : 160)
    readonly property int durationOverview: !root.motionEnabled ? 0 : (root.motionReduced ? 120 : 220)

    FileView {
        id: file
        path: StorageService.ready ? StorageService.path("desktop-manager.json") : ""
        printErrors: false
        onLoaded: root.parse(file.text())
        // A missing file fires loadFailed, not loaded: treat it as the
        // defaults so `loaded` flips and the first save can create it.
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
                console.warn("[voidshell] desktop-manager.json malformed, using defaults:", e);
                data = {};
            }
        }
        root.apply(data);
    }

    function apply(data) {
        const d = root.defaults;
        root.managerEnabled = typeof data.managerEnabled === "boolean" ? data.managerEnabled : d.managerEnabled;
        root.shelfEnabled = typeof data.shelfEnabled === "boolean" ? data.shelfEnabled : d.shelfEnabled;
        root.shelfSide = data.shelfSide === "right" ? "right" : "left";
        root.edgeReveal = typeof data.edgeReveal === "boolean" ? data.edgeReveal : d.edgeReveal;
        root.animation = (data.animation === "reduced" || data.animation === "off") ? data.animation : "full";
        root.maxStackedPreviews = clampInt(data.maxStackedPreviews, 1, 3, d.maxStackedPreviews);
        root.livePreviewBudget = clampInt(data.livePreviewBudget, 0, 6, d.livePreviewBudget);
        root.scope = data.scope === "all" ? "all" : "monitor";
        root.sensitiveExclusions = Array.isArray(data.sensitiveExclusions) ? data.sensitiveExclusions.filter(c => typeof c === "string" && c !== "") : d.sensitiveExclusions;
        root.fullscreenPolicy = data.fullscreenPolicy === "follow-focus" ? "follow-focus" : "explicit-only";
        root.islandAnnouncements = typeof data.islandAnnouncements === "boolean" ? data.islandAnnouncements : d.islandAnnouncements;
        // One line per (re)load: the resolved motion configuration the
        // whole shell uses from here on. It makes a silent "off" mode
        // visible, and the Phase G gate greps it instead of guessing.
        console.log("[voidshell] motion: mode=" + root.animation
            + " pill=" + root.durationPill
            + " hover=" + root.durationHover
            + " shelf=" + root.durationShelf
            + " card=" + root.durationCard
            + " fade=" + root.durationFade
            + " overview=" + root.durationOverview);
    }

    function clampInt(value, min, max, fallback) {
        if (typeof value !== "number" || !isFinite(value)) {
            return fallback;
        }
        return Math.max(min, Math.min(max, Math.round(value)));
    }

    function save() {
        if (!StorageService.ready || !root.loaded) {
            return;
        }
        file.setText(JSON.stringify({
            version: 1,
            managerEnabled: root.managerEnabled,
            shelfEnabled: root.shelfEnabled,
            shelfSide: root.shelfSide,
            edgeReveal: root.edgeReveal,
            animation: root.animation,
            maxStackedPreviews: root.maxStackedPreviews,
            livePreviewBudget: root.livePreviewBudget,
            scope: root.scope,
            sensitiveExclusions: root.sensitiveExclusions,
            fullscreenPolicy: root.fullscreenPolicy,
            islandAnnouncements: root.islandAnnouncements
        }, null, 2));
    }

    // Runtime toggles (settings UI / QA); each persists immediately.
    function setManagerEnabled(on) {
        root.managerEnabled = on === true;
        root.save();
    }

    function setShelfEnabled(on) {
        root.shelfEnabled = on === true;
        root.save();
    }
}
