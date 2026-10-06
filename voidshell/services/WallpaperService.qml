pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — wallpaper authority (PRD §21, §34.10, §35).
// Scans the user's wallpaper directories once per scan request (never a
// subprocess per frame), applies the chosen image through the running
// awww daemon, and owns the locked/dynamic palette switch:
//
//   locked  — wallpaper changes never touch shell tokens (default, keeps
//             the exact PRD palette of the default wallpaper).
//   dynamic — applying a wallpaper derives a restrained accent family
//             from its pixels and pushes it into ThemeService (§21.2:
//             semantic roles and contrast stay untouched).
//
// State persists in wallpaper.json; a missing or malformed file falls
// back to the PRD default wallpaper.
Singleton {
    id: root

    readonly property string wallpapersDir: StorageService.home + "/Pictures/wallpapers"
    readonly property string wallpapersDirAlt: StorageService.home + "/Pictures/Wallpapers"
    // Default per PRD §21.1 (matches the hyprland.lua startup exec).
    readonly property string defaultWallpaper: root.wallpapersDir + "/void-purple.png"

    property string current: root.defaultWallpaper
    property string paletteMode: "locked" // locked | dynamic
    // Wallpaper overlay mode (PRD §29–§30). off is the finalized-design
    // default; visualizer = audio-reactive wallpaper (§29); clock and
    // clock+lyrics are the §30 modes (clock+lyrics adds the audio-reactive
    // waveform + synced lyrics around the central clock).
    property string overlay: "off"
    property var available: []
    property bool loaded: false
    property bool scanning: false
    property bool applying: false

    readonly property bool availableReady: root.loaded && !root.scanning
    readonly property bool audioOverlay: root.overlay === "visualizer" || root.overlay === "clock+lyrics"
    readonly property bool clockOverlay: root.overlay === "clock" || root.overlay === "clock+lyrics"

    function isValidOverlay(mode) {
        return mode === "off" || mode === "visualizer" || mode === "clock" || mode === "clock+lyrics";
    }

    // --- persistence (PRD §35: wallpaper.json) ---------------------------
    FileView {
        id: file
        path: StorageService.ready ? StorageService.path("wallpaper.json") : ""
        printErrors: false
        onLoaded: root.parse(file.text())
        // Missing wallpaper.json fires loadFailed; start from the default
        // wallpaper so scan/save run (loaded gates both).
        onLoadFailed: root.parse("")
    }

    function parse(content) {
        root.loaded = true;
        if (content && content.trim() !== "") {
            try {
                const data = JSON.parse(content);
                if (data && typeof data.path === "string" && data.path !== "") {
                    root.current = data.path;
                }
                if (data && (data.paletteMode === "locked" || data.paletteMode === "dynamic")) {
                    root.paletteMode = data.paletteMode;
                }
                if (data && typeof data.overlay === "string" && root.isValidOverlay(data.overlay)) {
                    root.overlay = data.overlay;
                }
            } catch (e) {
                // Malformed state keeps the default wallpaper (PRD §35).
                console.warn("[voidshell] wallpaper.json malformed, using default:", e);
            }
        }
        root.scan();
        // Restore the user's last choice: hyprland.lua applies the default
        // at login, so re-apply only when a saved choice exists.
        if (content && content.trim() !== "") {
            root.applyImage(root.current, true);
        }
        // A saved dynamic palette re-derives from the restored wallpaper.
        if (root.paletteMode === "dynamic") {
            ThemeService.computeToneFor("file://" + root.current);
        }
    }

    function save() {
        if (!StorageService.ready || !root.loaded) {
            return;
        }
        file.setText(JSON.stringify({
            version: 1,
            path: root.current,
            paletteMode: root.paletteMode,
            overlay: root.overlay
        }, null, 2));
    }

    // Overlay mode switch (PRD §29–§30, off by default).
    function setOverlay(mode) {
        if (!root.isValidOverlay(mode) || mode === root.overlay) {
            return;
        }
        root.overlay = mode;
        root.save();
        const labels = {
            "off": "Overlay off",
            "visualizer": "Audio wallpaper on",
            "clock": "Wallpaper clock on",
            "clock+lyrics": "Clock + lyrics on"
        };
        ToastService.push("Wallpaper", labels[mode], mode === "off" ? "Desktop restored" : "Behind windows and panels", "info");
    }

    // --- directory scan --------------------------------------------------
    readonly property string findCommand: "find \"" + root.wallpapersDir + "\" \"" + root.wallpapersDirAlt + "\" -maxdepth 2 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.bmp' \\) 2>/dev/null | sort";

    Process {
        id: scanProc
        command: ["sh", "-c", root.findCommand]
        running: false
        stdout: StdioCollector {
            id: scanOut
        }
        onExited: exitCode => {
            root.scanning = false;
            if (exitCode !== 0) {
                root.available = [];
                return;
            }
            const lines = String(scanOut.text || "").split("\n");
            const out = [];
            for (let i = 0; i < lines.length; i++) {
                const p = lines[i].trim();
                if (p !== "") {
                    out.push(p);
                }
            }
            root.available = out;
        }
    }

    function scan() {
        if (root.scanning) {
            return;
        }
        root.scanning = true;
        scanProc.running = true;
    }

    // --- apply -----------------------------------------------------------
    Process {
        id: applyProc
        command: []
        running: false
        onExited: exitCode => {
            root.applying = false;
            if (exitCode !== 0) {
                ToastService.push("Wallpaper", "awww rejected the image", "", "warning");
                return;
            }
            if (root.paletteMode === "dynamic") {
                ThemeService.computeToneFor("file://" + root.current);
            }
        }
    }

    function apply(path) {
        root.applyImage(path, false);
    }

    function applyImage(path, silent) {
        if (!path || path === "" || root.applying) {
            return;
        }
        root.applying = true;
        const first = path !== root.current;
        root.current = path;
        // Only persist an actual change: writing from inside the FileView
        // load handler (restore path) races the in-flight load operation.
        if (first) {
            root.save();
        }
        applyProc.command = ["awww", "img", path];
        applyProc.running = true;
        if (!silent) {
            const name = root.baseName(path);
            ToastService.push("Wallpaper", (first ? "Applied " : "Restored ") + name, "", "info");
        }
    }

    // Locked/dynamic palette switch (PRD §21.2). Both directions go
    // through ThemeService so the token override is always in sync with
    // this service's persisted mode.
    function setPaletteMode(mode, silent) {
        if (mode !== "locked" && mode !== "dynamic") {
            return;
        }
        root.paletteMode = mode;
        root.save();
        if (mode === "dynamic") {
            ThemeService.computeToneFor("file://" + root.current);
            if (!silent) {
                ToastService.push("Wallpaper", "Dynamic palette on", "Accents follow the wallpaper", "info");
            }
        } else {
            ThemeService.setDynamicTone(null);
            if (!silent) {
                ToastService.push("Wallpaper", "Locked palette on", "Void tokens preserved", "info");
            }
        }
    }

    function baseName(path) {
        const i = path.lastIndexOf("/");
        return i === -1 ? path : path.slice(i + 1);
    }

    function search(text) {
        const needle = String(text || "").trim().toLowerCase();
        if (needle === "") {
            return root.available;
        }
        const out = [];
        for (let i = 0; i < root.available.length; i++) {
            if (root.baseName(root.available[i]).toLowerCase().indexOf(needle) !== -1) {
                out.push(root.available[i]);
            }
        }
        return out;
    }
}
