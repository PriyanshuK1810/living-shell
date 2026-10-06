import QtQuick
import "../../common"
import "../../services"

// VOID SHELL — synced lyrics block (PRD §29.2).
// Current line emphasized, neighbours and translation lines at lower
// opacity. Missing lyrics collapse to the minimal §37 unavailable line;
// with no player at all the block renders nothing.
Column {
    id: root

    readonly property int idx: LyricsService.currentIndex
    readonly property var lines: LyricsService.lines
    readonly property bool ready: LyricsService.checked && LyricsService.hasLyrics
    readonly property bool noLyrics: LyricsService.checked && !LyricsService.hasLyrics && MediaService.available

    readonly property string prevText: (root.ready && root.idx > 0) ? root.lines[root.idx - 1].text : ""
    readonly property string curText: (root.ready && root.idx >= 0) ? root.lines[root.idx].text : ""
    readonly property string curSub: (root.ready && root.idx >= 0) ? root.lines[root.idx].sub : ""
    readonly property string nextText: {
        if (!root.ready) {
            return "";
        }
        if (root.idx >= 0 && root.idx + 1 < root.lines.length) {
            return root.lines[root.idx + 1].text;
        }
        if (root.idx < 0 && root.lines.length > 0) {
            return root.lines[0].text;
        }
        return "";
    }

    width: 900
    spacing: Theme.space8

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.width
        visible: root.prevText !== ""
        text: root.prevText
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontUi
        font.pixelSize: 19
        color: Colors.textMuted
        opacity: 0.55
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.width
        spacing: Theme.space4
        visible: root.curText !== ""

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.width
            text: root.curText
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.fontUi
            font.weight: Font.DemiBold
            font.pixelSize: 34
            color: Colors.textPrimary
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.width
            visible: root.curSub !== ""
            text: root.curSub
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.fontUi
            font.pixelSize: 20
            color: Colors.textSecondary
            opacity: 0.8
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.width
        visible: root.nextText !== ""
        text: root.nextText
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontUi
        font.pixelSize: 19
        color: Colors.textMuted
        opacity: 0.5
    }

    // Minimal unavailable state (PRD §37) — only inside lyrics modes.
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.noLyrics
        text: "No lyrics for this track"
        font.family: Theme.fontUi
        font.pixelSize: 16
        color: Colors.textMuted
        opacity: 0.7
    }
}
