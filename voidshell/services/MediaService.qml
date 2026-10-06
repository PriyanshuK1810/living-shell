pragma Singleton

import Quickshell
import Quickshell.Services.Mpris

// VOID SHELL — shared media state. Sole owner of the native MPRIS binding;
// bar pill, now-playing panel and lyrics layer read this singleton and
// never touch Mpris.players directly. Fully event-driven, no polling.
// All properties are null-safe: with no player everything reads empty /
// zero / false and every method is a no-op.
Singleton {
    id: root

    // Preferred player: a playing one when several exist, else the first.
    readonly property var player: {
        var vals = Mpris.players.values;
        for (var i = 0; i < vals.length; i++) {
            if (vals[i].isPlaying) {
                return vals[i];
            }
        }
        return vals.length > 0 ? vals[0] : null;
    }

    readonly property bool available: root.player !== null
    readonly property string identity: root.player ? root.player.identity : ""
    readonly property string trackTitle: root.player ? root.player.trackTitle : ""
    readonly property string artist: root.player ? root.player.trackArtist : ""
    readonly property string album: root.player ? root.player.trackAlbum : ""
    readonly property string artUrl: root.player ? root.player.trackArtUrl : ""
    readonly property double position: root.player ? root.player.position : 0
    readonly property double duration: root.player ? root.player.length : 0
    readonly property bool playing: root.player ? root.player.isPlaying : false

    readonly property bool canPrevious: root.player ? root.player.canGoPrevious : false
    readonly property bool canNext: root.player ? root.player.canGoNext : false
    readonly property bool canPlay: root.player ? root.player.canPlay : false
    readonly property bool canPause: root.player ? root.player.canPause : false
    readonly property bool canSeek: root.player ? (root.player.canSeek && root.player.positionSupported && root.player.lengthSupported) : false

    // Shuffle / repeat surface only what the active player supports.
    readonly property bool shuffleSupported: root.player ? root.player.shuffleSupported : false
    readonly property bool shuffle: root.player ? root.player.shuffle : false
    readonly property bool loopSupported: root.player ? root.player.loopSupported : false
    // 0 = off, 1 = track, 2 = playlist (mirrors MprisLoopState).
    readonly property int loopState: root.player ? root.player.loopState : 0
    readonly property string loopName: root.loopState === 1 ? "Track" : (root.loopState === 2 ? "All" : "Off")

    function previous() {
        if (root.canPrevious) {
            root.player.previous();
        }
    }

    function next() {
        if (root.canNext) {
            root.player.next();
        }
    }

    function togglePlaying() {
        if (!root.player) {
            return;
        }
        if (root.player.canTogglePlaying) {
            root.player.togglePlaying();
        } else if (root.playing && root.canPause) {
            root.player.pause();
        } else if (!root.playing && root.canPlay) {
            root.player.play();
        }
    }

    function seek(pos) {
        if (!root.canSeek) {
            return;
        }
        var clamped = Math.max(0, Math.min(pos, root.duration));
        root.player.position = clamped;
    }

    function toggleShuffle() {
        if (root.shuffleSupported) {
            root.player.shuffle = !root.player.shuffle;
        }
    }

    function cycleLoop() {
        if (root.loopSupported) {
            root.player.loopState = (root.loopState + 1) % 3;
        }
    }

    function fmtTime(s) {
        if (!isFinite(s) || s < 0) {
            return "0:00";
        }
        var total = Math.floor(s);
        var m = Math.floor(total / 60);
        var sec = total % 60;
        return m + ":" + (sec < 10 ? "0" + sec : sec);
    }
}
