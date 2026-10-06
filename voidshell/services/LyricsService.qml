pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — synced lyrics engine (PRD §29.2, §35, §37).
//
// Local-first by design: one lazy `find` collects every `.lrc` under
// ~/.local/share/voidshell/lyrics and ~/Music, then tracks are matched
// in memory — no external API is ever contacted, so the fetch/cache
// rules are satisfied by construction. Timestamped lines advance off a
// single position event hook plus a 250 ms tick that extrapolates from
// the last reported position (MPRIS players do not stream Position),
// with seeks absorbed through the position-change signal.
//
// Missing lyrics stay a clean empty state: `checked` flips true and
// `lines` stays empty, and the overlay decides what (if anything) to
// say — PRD §37.
Singleton {
    id: root

    readonly property string lyricsDir: StorageService.home + "/.local/share/voidshell/lyrics"
    readonly property string musicDir: StorageService.home + "/Music"

    // [{ t: seconds, text, sub }] sorted by time; sub carries a second
    // line at the same timestamp (commonly a translation).
    property var lines: []
    property bool checked: false
    property int currentIndex: -1
    readonly property bool hasLyrics: root.lines.length > 0

    // Track identity the current lyrics were resolved for.
    readonly property string trackKey: MediaService.available ? MediaService.artist + "\u0001" + MediaService.trackTitle : ""
    readonly property string trackTitle: MediaService.trackTitle
    readonly property string trackArtist: MediaService.artist

    // --- playback clock ----------------------------------------------------
    property double rawPos: 0
    property double rawAt: 0

    function syncRaw() {
        root.rawPos = MediaService.position;
        root.rawAt = Date.now();
    }

    function effectivePos() {
        if (!MediaService.playing) {
            return root.rawPos;
        }
        return root.rawPos + (Date.now() - root.rawAt) / 1000;
    }

    function updateIndex() {
        if (!root.hasLyrics) {
            if (root.currentIndex !== -1) {
                root.currentIndex = -1;
            }
            return;
        }
        const pos = root.effectivePos();
        let idx = -1;
        for (let i = 0; i < root.lines.length; i++) {
            if (root.lines[i].t <= pos + 0.05) {
                idx = i;
            } else {
                break;
            }
        }
        if (idx !== root.currentIndex) {
            root.currentIndex = idx;
        }
    }

    Timer {
        interval: 250
        repeat: true
        running: MediaService.available && root.hasLyrics
        onTriggered: root.updateIndex()
    }

    Connections {
        target: MediaService
        function onPositionChanged() {
            // Fires on seeks and on ordinary position reports.
            root.syncRaw();
            root.updateIndex();
        }
        function onPlayingChanged() {
            root.syncRaw();
        }
    }

    // --- lyric discovery ---------------------------------------------------
    property var lrcFiles: []
    property bool scanDone: false
    property bool scanRunning: false
    property string lrcPath: ""

    Process {
        id: scanProc
        running: false
        stdout: StdioCollector {
            id: scanOut
        }
        onExited: exitCode => {
            root.scanRunning = false;
            root.scanDone = true;
            const out = [];
            if (exitCode === 0) {
                const parts = String(scanOut.text || "").split("\n");
                for (let i = 0; i < parts.length; i++) {
                    const p = parts[i].trim();
                    if (p !== "") {
                        out.push(p);
                    }
                }
            }
            root.lrcFiles = out;
            if (root.trackKey !== "") {
                root.resolveForCurrentTrack();
            }
        }
    }

    function ensureScanned() {
        if (root.scanDone || root.scanRunning) {
            return;
        }
        root.scanRunning = true;
        scanProc.command = ["sh", "-c", "find \"" + root.lyricsDir + "\" \"" + root.musicDir + "\" -maxdepth 4 -type f -iname \"*.lrc\" 2>/dev/null | sort"];
        scanProc.running = true;
    }

    function baseName(path) {
        const i = path.lastIndexOf("/");
        return i === -1 ? path : path.slice(i + 1);
    }

    function matchLyrics() {
        // Null-safe: MPRIS exposes nothing before metadata arrives, and
        // `.trim()` on undefined logged a TypeError on every position tick
        // (the field is MediaService.artist — trackArtist does not exist).
        const title = (MediaService.trackTitle || "").trim().toLowerCase();
        const artist = (MediaService.artist || "").trim().toLowerCase();
        if (title.length < 2) {
            return "";
        }
        let fallback = "";
        for (let i = 0; i < root.lrcFiles.length; i++) {
            const name = root.baseName(root.lrcFiles[i]).toLowerCase();
            const hitTitle = name.indexOf(title) !== -1;
            if (hitTitle && artist.length > 0 && name.indexOf(artist) !== -1) {
                return root.lrcFiles[i]; // artist + title both match
            }
            if (hitTitle && fallback === "") {
                fallback = root.lrcFiles[i];
            }
        }
        return fallback;
    }

    function setLyricFile(path) {
        if (path === root.lrcPath) {
            // Same file for a new track: re-read what is already loaded.
            root.parseLrc(lrcFile.text);
        } else {
            root.lrcPath = path; // FileView reloads and fires onLoaded
        }
    }

    function resolveForCurrentTrack() {
        const path = root.matchLyrics();
        if (path === "") {
            root.lines = [];
            root.currentIndex = -1;
            root.checked = true;
            root.lrcPath = "";
            return;
        }
        root.setLyricFile(path);
    }

    function reload() {
        root.lines = [];
        root.currentIndex = -1;
        root.checked = false;
        if (root.trackKey === "") {
            return;
        }
        root.ensureScanned();
        if (root.scanRunning) {
            return; // resolveForCurrentTrack runs when the scan lands
        }
        root.resolveForCurrentTrack();
    }

    onTrackKeyChanged: root.reload()

    // --- lyric file content -------------------------------------------------
    FileView {
        id: lrcFile
        path: root.lrcPath
        printErrors: false
        onLoaded: root.parseLrc(lrcFile.text())
        onLoadFailed: {
            root.lines = [];
            root.currentIndex = -1;
            root.checked = true;
        }
    }

    // --- LRC parsing ---------------------------------------------------------
    function parseLrc(content) {
        const raw = String(content || "").split("\n");
        const re = /\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]/g;
        const entries = [];
        for (let i = 0; i < raw.length; i++) {
            const line = raw[i];
            re.lastIndex = 0;
            let m = re.exec(line);
            while (m !== null) {
                const min = Number(m[1]);
                const sec = Number(m[2]);
                let frac = 0;
                if (m[3] !== undefined) {
                    frac = Number(m[3]) / Math.pow(10, m[3].length);
                }
                // Text runs to end of line; drop any trailing timestamps
                // (multi-stamp lines) and inline word timings.
                const text = line.slice(re.lastIndex).replace(/\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]/g, "").replace(/<[^>]*>/g, "").trim();
                if (text !== "") {
                    entries.push({
                        t: min * 60 + sec + frac,
                        text: text
                    });
                }
                m = re.exec(line);
            }
        }
        entries.sort((a, b) => a.t - b.t);
        const merged = [];
        for (let i = 0; i < entries.length; i++) {
            const e = entries[i];
            const last = merged.length > 0 ? merged[merged.length - 1] : null;
            if (last !== null && Math.abs(last.t - e.t) < 0.001) {
                // Same timestamp twice: second line is a translation/sub.
                if (last.sub === "") {
                    last.sub = e.text;
                }
            } else {
                merged.push({
                    t: e.t,
                    text: e.text,
                    sub: ""
                });
            }
        }
        root.lines = merged;
        root.checked = true;
        root.syncRaw();
        root.updateIndex();
    }
}
