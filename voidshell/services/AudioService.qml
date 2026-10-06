pragma Singleton

import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// VOID SHELL — audio state (PRD 34.6): the single PipeWire binding shared
// by the status pill, quick settings and the dashboard. Sink/source nodes
// are bound through PwObjectTracker so volume and mute are real.
// The input peak meter only runs while a view asks for it (micLevelEnabled).
Singleton {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sinkAudio: root.sink ? root.sink.audio : null
    readonly property var sourceAudio: root.source ? root.source.audio : null

    readonly property bool available: root.sinkAudio !== null
    readonly property bool micAvailable: root.sourceAudio !== null

    readonly property real volume: root.available ? Math.max(0, root.sinkAudio.volume) : 0
    readonly property bool muted: root.available ? root.sinkAudio.muted : false
    readonly property real micVolume: root.micAvailable ? Math.max(0, root.sourceAudio.volume) : 0
    readonly property bool micMuted: root.micAvailable ? root.sourceAudio.muted : false

    readonly property int volumePercent: Math.round(root.volume * 100)
    readonly property int micPercent: Math.round(root.micVolume * 100)

    readonly property string sinkName: root.sink ? (root.sink.nickname !== "" ? root.sink.nickname : root.sink.description) : ""
    readonly property string sourceName: root.source ? (root.source.nickname !== "" ? root.source.nickname : root.source.description) : ""

    // Input level meter (PRD 17.2) — off by default so an idle shell never
    // pays for peak tracking.
    property bool micLevelEnabled: false
    readonly property real micPeak: peakMonitor.peak

    // Binds the nodes so their audio properties can be read and written.
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    PwNodePeakMonitor {
        id: peakMonitor
        node: Pipewire.defaultAudioSource
        enabled: root.micLevelEnabled && root.micAvailable
    }

    function clamp(v) {
        return Math.max(0, Math.min(1, v));
    }

    function setVolume(v) {
        if (!root.available) {
            return;
        }
        root.sinkAudio.volume = root.clamp(v);
    }

    function setMuted(m) {
        if (!root.available) {
            return;
        }
        root.sinkAudio.muted = m;
    }

    function toggleMute() {
        root.setMuted(!root.muted);
    }

    function setMicVolume(v) {
        if (!root.micAvailable) {
            return;
        }
        root.sourceAudio.volume = root.clamp(v);
    }

    function toggleMicMute() {
        if (!root.micAvailable) {
            return;
        }
        root.sourceAudio.muted = !root.sourceAudio.muted;
    }

    // PRD 9.3 — percent labels are always derived, never invented.
    function volumeText() {
        if (!root.available) {
            return "—";
        }
        if (root.muted) {
            return "Muted";
        }
        return root.volumePercent + "%";
    }

    function micText() {
        if (!root.micAvailable) {
            return "No input device";
        }
        if (root.micMuted) {
            return "Muted";
        }
        return root.micPercent + "%";
    }
}
