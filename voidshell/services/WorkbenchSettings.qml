pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — Workbench dock + gesture settings (Workbench plan).
// One JSON store (`~/.local/share/voidshell/workbench.json`), written
// through FileView exactly like ManagerSettings: malformed or missing
// files degrade to the documented defaults, every write is atomic.
// Shortcuts are intentionally NOT stored here — they live in
// ~/.config/hypr/hyprland.lua where every other binding lives; the
// gesture threshold table below is read by the Lua gesture handlers
// through the `gesture config` IPC, so one edit here retunes both sides.
Singleton {
    id: root

    // --- defaults --------------------------------------------------------
    // enabled            : master switch for the dock surface.
    // visibility         : "alwaysVisible" | "autoHide" (default) |
    //                      "manual" | "dodgeWindows".
    // hideDelay          : ms the dock waits after the pointer leaves
    //                      before it retreats (autoHide).
    // edgeRevealDelay    : ms the pointer must dwell in the bottom-center
    //                      reveal zone before the dock appears. The zone
    //                      itself is small and only exists while hidden.
    // magnification      : "off" | "subtle" (default) | "full".
    //                      subtle: hovered 1.12, adjacent 1.04.
    //                      full:   hovered 1.18, adjacent 1.08.
    // multiWindowClickBehavior : "mru" (default — focus most recently
    //                      used window, cycle when already focused) |
    //                      "preview" (open the preview strip).
    // gestureProfile     : "minimal" (default: 3-finger L/R workspace,
    //                      up overview, down workbench) | "power" |
    //                      "custom".
    // activationDistance / commitThreshold : logical px of gesture travel
    //                      before a gesture claims an axis / commits.
    // velocityThreshold  : px/ms below which a short flick does not
    //                      commit (conservative — no accidental calls).
    // cooldown           : ms between two committed intents; a rapid
    //                      repeat inside it *retargets* (last write wins
    //                      in GestureRouter) instead of queueing.
    // gestureAllowFullscreen : per-surface policy while a fullscreen
    //                      window is focused. Overview/workbench stay
    //                      available (deliberate gesture, like
    //                      "explicit-only"), the dashboard gesture is
    //                      suppressed by default (plan §fullscreen).
    // universalActions   : explicit opt-in list of universal palette
    //                      actions (see ContextActionRegistry). Empty by
    //                      default: an app with no real actions hides
    //                      the section instead of padding it.
    // enableSuperNumberSlots : false — Super+1..0 are the workspace
    //                      binds in hyprland.lua, so dock slot digits
    //                      stay unbound until the user rebinds workspaces.
    // gestureEnable      : per-gesture switches for the "custom"
    //                      profile ("minimal" = the 3-finger core only,
    //                      "power" = every flag on). The flags cover the
    //                      compositor-side gestures gestures.lua gates at
    //                      start: stage (4-finger L/R), dashboard
    //                      (4-finger up), special (4-finger down), zoom
    //                      (pinch cursor zoom).
    // dockOrder          : desktop ids in the order the dock's drag
    //                      last persisted them; empty = the favorites'
    //                      own order (see ApplicationStore.pins).
    readonly property var defaults: ({
        enabled: true,
        visibility: "autoHide",
        hideDelay: 1400,
        edgeRevealDelay: 400,
        magnification: "subtle",
        multiWindowClickBehavior: "mru",
        gestureProfile: "minimal",
        activationDistance: 24,
        commitThreshold: 96,
        velocityThreshold: 0.6,
        cooldown: 220,
        gestureAllowFullscreen: { overview: true, workbench: true, dashboard: false },
        universalActions: [],
        enableSuperNumberSlots: false,
        gestureEnable: { stage: false, dashboard: false, special: false, zoom: false },
        dockOrder: []
    })

    property bool enabled: true
    property string visibility: "autoHide"
    property int hideDelay: 1400
    property int edgeRevealDelay: 400
    property string magnification: "subtle"
    property string multiWindowClickBehavior: "mru"
    property string gestureProfile: "minimal"
    property int activationDistance: 24
    property int commitThreshold: 96
    property real velocityThreshold: 0.6
    property int cooldown: 220
    property var gestureAllowFullscreen: ({ overview: true, workbench: true, dashboard: false })
    property var universalActions: []
    property bool enableSuperNumberSlots: false
    property var gestureEnable: ({ stage: false, dashboard: false, special: false, zoom: false })
    property var dockOrder: []

    property bool loaded: false

    // Which optional gestures are armed for the current profile — one
    // table computed here and read on both sides: gestures.lua applies
    // it when a gesture starts, the gate cross-checks it against the
    // `gesture config` IPC blob. Profile change ⇒ hyprctl reload (the
    // compositor registers its gesture table when the config runs);
    // threshold changes are picked up by gestures.lua on the next
    // gesture start, so they need no reload at all.
    readonly property var gestureEnableNow: {
        if (root.gestureProfile === "power") {
            return { stage: true, dashboard: true, special: true, zoom: true };
        }
        if (root.gestureProfile === "custom") {
            return root.gestureEnable;
        }
        return { stage: false, dashboard: false, special: false, zoom: false };
    }

    // Magnification factors resolved from `magnification`, so no view
    // ever hardcodes a scale (reduced motion disables the animation at
    // the view, not the factor — the size step stays honest).
    readonly property real magHover: root.magnification === "full" ? 1.18 : (root.magnification === "subtle" ? 1.12 : 1.0)
    readonly property real magAdjacent: root.magnification === "full" ? 1.08 : (root.magnification === "subtle" ? 1.04 : 1.0)
    readonly property bool magAnimated: root.magnification !== "off" && ManagerSettings.motionEnabled

    FileView {
        id: file
        path: StorageService.ready ? StorageService.path("workbench.json") : ""
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
                console.warn("[voidshell] workbench.json malformed, using defaults:", e);
                data = {};
            }
        }
        root.apply(data);
    }

    function apply(data) {
        const d = root.defaults;
        root.enabled = typeof data.enabled === "boolean" ? data.enabled : d.enabled;
        root.visibility = ["alwaysVisible", "autoHide", "manual", "dodgeWindows"].indexOf(data.visibility) !== -1 ? data.visibility : d.visibility;
        root.hideDelay = clampInt(data.hideDelay, 300, 10000, d.hideDelay);
        root.edgeRevealDelay = clampInt(data.edgeRevealDelay, 0, 3000, d.edgeRevealDelay);
        root.magnification = ["off", "subtle", "full"].indexOf(data.magnification) !== -1 ? data.magnification : d.magnification;
        root.multiWindowClickBehavior = data.multiWindowClickBehavior === "preview" ? "preview" : "mru";
        root.gestureProfile = ["minimal", "power", "custom"].indexOf(data.gestureProfile) !== -1 ? data.gestureProfile : d.gestureProfile;
        root.activationDistance = clampInt(data.activationDistance, 8, 96, d.activationDistance);
        root.commitThreshold = clampInt(data.commitThreshold, 32, 320, d.commitThreshold);
        root.velocityThreshold = typeof data.velocityThreshold === "number" && isFinite(data.velocityThreshold) && data.velocityThreshold >= 0 ? data.velocityThreshold : d.velocityThreshold;
        root.cooldown = clampInt(data.cooldown, 0, 2000, d.cooldown);
        const fa = (data.gestureAllowFullscreen !== null && typeof data.gestureAllowFullscreen === "object") ? data.gestureAllowFullscreen : {};
        root.gestureAllowFullscreen = {
            overview: typeof fa.overview === "boolean" ? fa.overview : d.gestureAllowFullscreen.overview,
            workbench: typeof fa.workbench === "boolean" ? fa.workbench : d.gestureAllowFullscreen.workbench,
            dashboard: typeof fa.dashboard === "boolean" ? fa.dashboard : d.gestureAllowFullscreen.dashboard
        };
        root.universalActions = Array.isArray(data.universalActions)
            ? data.universalActions.filter(a => typeof a === "string" && a !== "")
            : d.universalActions;
        root.enableSuperNumberSlots = typeof data.enableSuperNumberSlots === "boolean" ? data.enableSuperNumberSlots : d.enableSuperNumberSlots;
        const ge = (data.gestureEnable !== null && typeof data.gestureEnable === "object" && !Array.isArray(data.gestureEnable)) ? data.gestureEnable : {};
        root.gestureEnable = {
            stage: typeof ge.stage === "boolean" ? ge.stage : d.gestureEnable.stage,
            dashboard: typeof ge.dashboard === "boolean" ? ge.dashboard : d.gestureEnable.dashboard,
            special: typeof ge.special === "boolean" ? ge.special : d.gestureEnable.special,
            zoom: typeof ge.zoom === "boolean" ? ge.zoom : d.gestureEnable.zoom
        };
        root.dockOrder = Array.isArray(data.dockOrder)
            ? data.dockOrder.filter(k => typeof k === "string" && k !== "").slice(0, 64)
            : d.dockOrder;
        console.log("[voidshell] workbench: enabled=" + root.enabled
            + " visibility=" + root.visibility
            + " magnification=" + root.magnification
            + " multiWindowClick=" + root.multiWindowClickBehavior
            + " gestureProfile=" + root.gestureProfile
            + " thresholds=" + root.activationDistance + "/" + root.commitThreshold
            + "@" + root.velocityThreshold + " cooldown=" + root.cooldown
            + " hideDelay=" + root.hideDelay
            + " slots=" + root.dockOrder.length);
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
            enabled: root.enabled,
            visibility: root.visibility,
            hideDelay: root.hideDelay,
            edgeRevealDelay: root.edgeRevealDelay,
            magnification: root.magnification,
            multiWindowClickBehavior: root.multiWindowClickBehavior,
            gestureProfile: root.gestureProfile,
            activationDistance: root.activationDistance,
            commitThreshold: root.commitThreshold,
            velocityThreshold: root.velocityThreshold,
            cooldown: root.cooldown,
            gestureAllowFullscreen: root.gestureAllowFullscreen,
            universalActions: root.universalActions,
            enableSuperNumberSlots: root.enableSuperNumberSlots,
            gestureEnable: root.gestureEnable,
            dockOrder: root.dockOrder
        }, null, 2));
    }

    // Runtime toggles (settings UI / QA); each persists immediately.
    function setEnabled(on) {
        root.enabled = on === true;
        root.save();
    }

    function setVisibility(mode) {
        if (["alwaysVisible", "autoHide", "manual", "dodgeWindows"].indexOf(mode) !== -1) {
            root.visibility = mode;
            root.save();
        }
    }

    function setGestureProfile(profile) {
        if (["minimal", "power", "custom"].indexOf(profile) !== -1) {
            root.gestureProfile = profile;
            root.save();
        }
    }

    // Reorder the dock's pinned slots (drag release). Validation first,
    // then one atomic write: a duplicate/unknown/short list or an
    // unwritable store returns false *before* anything changes, so the
    // view can snap back to the previous order instead of persisting a
    // broken one (plan §drag: atomic persist → revert on failure).
    function setDockOrder(ids) {
        if (!Array.isArray(ids) || ids.length === 0 || !root.loaded || !StorageService.ready) {
            return false;
        }
        const clean = [];
        for (let i = 0; i < ids.length; i++) {
            const v = ids[i];
            if (typeof v !== "string" || v === "" || clean.indexOf(v) !== -1) {
                return false;
            }
            clean.push(v);
        }
        root.dockOrder = clean;
        root.save();
        return true;
    }

    // The compact config blob served by the `gesture config` IPC — the
    // gate cross-checks it against what gestures.lua parsed out of this
    // same file, so one JSON edit retunes both sides and the check
    // proves they agree (gestures.lua reads workbench.json directly at
    // every gesture start: no subprocess in a gesture callback, and
    // thresholds stay live without a hyprctl reload).
    function configBlob() {
        return JSON.stringify({
            profile: root.gestureProfile,
            activationDistance: root.activationDistance,
            commitThreshold: root.commitThreshold,
            velocityThreshold: root.velocityThreshold,
            cooldown: root.cooldown,
            allowFullscreen: root.gestureAllowFullscreen,
            enable: root.gestureEnableNow
        });
    }
}
