pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

// VOID SHELL — wallpaper audio visualizer engine (PRD §29.1, §36).
//
// Real spectrum, never simulated: ffmpeg captures the default sink's
// monitor stream as raw PCM, base64 frames it over ASCII lines (the
// text channel is UTF-8 and would corrupt raw bytes), and a rolling
// ring buffer feeds an in-process 512-point FFT producing 24 log-spaced
// bands. Lifecycle honours §36 — the pipeline exists only while a
// wallpaper audio overlay is enabled, stops after a few silent seconds,
// and wakes on real audio activity (a pipewire peak tap or MPRIS play),
// so an idle shell pays nothing.
Singleton {
    id: root

    readonly property bool active: WallpaperService.audioOverlay
    readonly property bool running: captureProc.running

    readonly property int sampleRate: 16000
    readonly property int fftSize: 512
    readonly property int ringSize: 2048
    readonly property int bandCount: 24
    readonly property real silenceSeconds: 4.2

    // 0..1 per band, replaced at ~30 fps while active (PRD §36: animation
    // frequency only while enabled and audio-active).
    property var bands: []
    property double lastAudioAt: 0

    // --- audio activity tap (wake source, no polling) --------------------
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    PwNodePeakMonitor {
        id: sinkPeak
        node: Pipewire.defaultAudioSink
        // Wake tap, per PRD §36 — no polling, the pipeline rises on real
        // audio activity. Gated on un-muted: a muted sink outputs digital
        // silence, so the monitor could never wake anything and would only
        // burn ~2.8% CPU (measured) pushing zeros through pipewire+QML.
        // MPRIS play remains a second wake source for muted-visual testing.
        enabled: root.active && !root.running && !AudioService.muted
    }

    Connections {
        target: sinkPeak
        function onPeakChanged() {
            if (root.active && !root.running && sinkPeak.peak > 0.02) {
                root.tryStart();
            }
        }
    }

    Connections {
        target: MediaService
        function onPlayingChanged() {
            if (MediaService.playing && root.active) {
                root.tryStart();
            }
        }
    }

    onActiveChanged: {
        if (root.active) {
            if (MediaService.playing) {
                root.tryStart();
            }
        } else {
            root.stopCapture();
            frameTimer.stop();
            root.bands = [];
        }
    }

    onRunningChanged: {
        if (root.running) {
            // Audio-active: animate at 30 fps. The loop stops itself once
            // the decay flattens (see frame()) — a silent overlay renders
            // statically, per PRD §36.
            frameTimer.restart();
        }
    }

    // --- capture pipeline -------------------------------------------------
    // Raw s16le @16 kHz mono from the sink monitor, framed as base64
    // lines. SplitParser hands each line over immediately, so nothing
    // accumulates in memory.
    readonly property string captureCommand: "ffmpeg -nostdin -v error -f pulse -i '@DEFAULT_MONITOR@' -ac 1 -ar " + root.sampleRate + " -f s16le - 2>/dev/null | base64 -w 768";

    Process {
        id: captureProc
        running: false
        command: ["sh", "-c", root.captureCommand]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => root.ingestLine(line)
        }
        onExited: exitCode => {
            // A manual silence-stop delivers SIGTERM; only unexpected
            // failures are worth a line.
            if (exitCode > 1 && root.active) {
                console.log("[voidshell] visualizer capture exited with", exitCode);
            }
        }
    }

    function tryStart() {
        if (!root.active || root.running) {
            return;
        }
        root.lastAudioAt = Date.now(); // startup grace for the first frames
        captureProc.running = true;
    }

    function stopCapture() {
        if (!root.running) {
            return;
        }
        captureProc.running = false;
    }

    // --- base64 → PCM -----------------------------------------------------
    property var b64rev: {
        const t = new Int16Array(128);
        for (let i = 0; i < 128; i++) {
            t[i] = -1;
        }
        const a = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        for (let i = 0; i < 64; i++) {
            t[a.charCodeAt(i)] = i;
        }
        return t;
    }

    property var ring: new Float32Array(2048)
    property int ringPos: 0

    function ingestLine(line) {
        const tbl = root.b64rev;
        const n = line.length;
        if (n < 8) {
            return;
        }
        const bytes = new Uint8Array(Math.floor(n * 3 / 4));
        let o = 0;
        let buf = 0;
        let bits = 0;
        for (let i = 0; i < n; i++) {
            const c = line.charCodeAt(i);
            if (c === 61) {
                break; // padding
            }
            const v = c < 128 ? tbl[c] : -1;
            if (v < 0) {
                continue;
            }
            buf = (buf << 6) | v;
            bits += 6;
            if (bits >= 8) {
                bits -= 8;
                bytes[o++] = (buf >> bits) & 0xff;
            }
        }
        if (o < 2 || (o & 1) === 1) {
            return;
        }
        const R = root.ringSize;
        const ring = root.ring;
        let heard = false;
        for (let i = 0; i + 1 < o; i += 2) {
            let v = bytes[i] | (bytes[i + 1] << 8);
            if (v & 0x8000) {
                v -= 0x10000;
            }
            const s = v / 32768;
            ring[root.ringPos] = s;
            root.ringPos = (root.ringPos + 1) & (R - 1);
            if (s > 0.004 || s < -0.004) {
                heard = true;
            }
        }
        if (heard) {
            root.lastAudioAt = Date.now();
        }
    }

    // --- FFT tables (built once) ------------------------------------------
    property var hann: null
    property var twRe: null
    property var twIm: null
    property var bitRev: null
    property var fftRe: null
    property var fftIm: null

    function ensureTables() {
        if (root.hann !== null) {
            return;
        }
        const N = root.fftSize;
        const h = new Float32Array(N);
        for (let i = 0; i < N; i++) {
            h[i] = 0.5 - 0.5 * Math.cos(2 * Math.PI * i / (N - 1));
        }
        root.hann = h;
        const tr = new Float32Array(N / 2);
        const ti = new Float32Array(N / 2);
        for (let k = 0; k < N / 2; k++) {
            tr[k] = Math.cos(-2 * Math.PI * k / N);
            ti[k] = Math.sin(-2 * Math.PI * k / N);
        }
        root.twRe = tr;
        root.twIm = ti;
        const bits = Math.round(Math.log2(N));
        const br = new Uint16Array(N);
        for (let i = 0; i < N; i++) {
            let r = 0;
            for (let b = 0; b < bits; b++) {
                if (i & (1 << b)) {
                    r |= 1 << (bits - 1 - b);
                }
            }
            br[i] = r;
        }
        root.bitRev = br;
        root.fftRe = new Float32Array(N);
        root.fftIm = new Float32Array(N);
    }

    // Log-spaced band edges from 40 Hz to 8 kHz (bin width 31.25 Hz),
    // built once alongside the FFT tables.
    function bandBinEdges() {
        if (root.bandEdges !== null) {
            return root.bandEdges;
        }
        const edges = [];
        const ratio = Math.pow(8000 / 40, 1 / root.bandCount);
        let f = 40;
        for (let k = 0; k <= root.bandCount; k++) {
            edges.push(Math.max(1, Math.round(f / (root.sampleRate / root.fftSize))));
            f *= ratio;
        }
        root.bandEdges = edges;
        return edges;
    }

    property var bandEdges: null

    function computeBands() {
        root.ensureTables();
        const N = root.fftSize;
        const R = root.ringSize;
        const re = root.fftRe;
        const im = root.fftIm;
        const ring = root.ring;
        const start = (root.ringPos - N + R) & (R - 1);
        const hann = root.hann;
        for (let i = 0; i < N; i++) {
            re[i] = ring[(start + i) & (R - 1)] * hann[i];
            im[i] = 0;
        }
        for (let i = 0; i < N; i++) {
            const j = root.bitRev[i];
            if (j > i) {
                let t = re[i];
                re[i] = re[j];
                re[j] = t;
                t = im[i];
                im[i] = im[j];
                im[j] = t;
            }
        }
        const twRe = root.twRe;
        const twIm = root.twIm;
        for (let len = 2; len <= N; len <<= 1) {
            const half = len >> 1;
            const step = N / len;
            for (let i = 0; i < N; i += len) {
                for (let k = 0; k < half; k++) {
                    const t = k * step;
                    const wr = twRe[t];
                    const wi = twIm[t];
                    const a = i + k;
                    const b = a + half;
                    const xr = re[b] * wr - im[b] * wi;
                    const xi = re[b] * wi + im[b] * wr;
                    re[b] = re[a] - xr;
                    im[b] = im[a] - xi;
                    re[a] += xr;
                    im[a] += xi;
                }
            }
        }
        const edges = root.bandBinEdges();
        const cur = root.bands;
        const next = new Array(root.bandCount);
        for (let band = 0; band < root.bandCount; band++) {
            const lo = edges[band];
            const hi = Math.max(lo + 1, edges[band + 1]);
            let mag = 0;
            for (let bin = lo; bin < hi && bin < N / 2; bin++) {
                const m = Math.sqrt(re[bin] * re[bin] + im[bin] * im[bin]);
                if (m > mag) {
                    mag = m;
                }
            }
            // Full-scale sine lands at N/2; map [-52 dB, 0 dB] → [0, 1].
            const norm = mag / (N / 2);
            let db = 20 * Math.log10(norm > 0.000001 ? norm : 0.000001);
            let target = (db + 52) / 52;
            if (target < 0) {
                target = 0;
            } else if (target > 1) {
                target = 1;
            }
            const old = (cur !== null && cur.length === root.bandCount) ? (cur[band] || 0) : 0;
            // Fast attack, slow decay — reads like a spectrum meter.
            next[band] = target > old ? old + (target - old) * 0.5 : old + (target - old) * 0.14;
        }
        root.bands = next;
    }

    function flattenBands() {
        const next = new Array(root.bandCount);
        for (let i = 0; i < root.bandCount; i++) {
            next[i] = 0;
        }
        root.bands = next;
    }

    // --- animation frame (30 fps, only while an audio overlay is on) ------
    function frame() {
        if (!root.running) {
            // Decay toward flat after the pipeline stops (or when bands are
            // still empty), then end the loop: no audio means no animation.
            let alive = false;
            const next = new Array(root.bandCount);
            for (let i = 0; i < root.bandCount; i++) {
                next[i] = (root.bands[i] || 0) * 0.82;
                if (next[i] > 0.004) {
                    alive = true;
                }
            }
            if (alive) {
                root.bands = next;
                return;
            }
            root.flattenBands();
            frameTimer.stop(); // fully flat — §36: no idle animation work
            return;
        }
        if (Date.now() - root.lastAudioAt > root.silenceSeconds * 1000) {
            root.stopCapture(); // §29.1: idle when no audio is playing
            return;
        }
        root.computeBands();
    }

    Timer {
        id: frameTimer
        interval: 33
        repeat: true
        running: false
        onTriggered: root.frame()
    }
}
