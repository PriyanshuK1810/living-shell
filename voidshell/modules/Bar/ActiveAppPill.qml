import QtQuick
import Quickshell
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — active-app pill (PRD 12.2): reflects the focused Hyprland
// client through HyprlandService. Prefers a desktop-entry icon, falls back
// to the app id and finally to a neutral `Desktop` label when no client
// has focus. Long titles elide instead of stretching the pill.
Comp.SlantedPill {
    id: root
    height: Theme.barHeight

    // --- width budget (set by Bar.qml) ---------------------------------
    // The left island may never cross the clock island either: Bar hands
    // over a `maxWidth` and the label elides to pay for it.
    property int maxWidth: 4000
    readonly property int padBase: (Theme.slantDepth + 14) * 2
    readonly property int colMax: 150
    readonly property int colMin: 40

    readonly property int colNatural: Math.min(root.colMax, titleText.implicitWidth)
    readonly property int naturalWidth: Math.min(260, 24 + Theme.space8 + root.colNatural + root.padBase)
    readonly property int textShrinkable: Math.max(0, root.colNatural - root.colMin)
    readonly property int shrink: Math.max(0, root.naturalWidth - root.width)
    readonly property int colCap: Math.max(root.colMin, root.colNatural - root.shrink)

    width: Math.min(root.maxWidth, root.naturalWidth)
    fillColor: Colors.glassBase
    borderColor: Colors.borderSubtle
    glowEnabled: true

    readonly property string appId: HyprlandService.focusedAppId
    readonly property string appTitle: HyprlandService.focusedTitle
    readonly property bool onDesktop: HyprlandService.onDesktop

    function resolveIcon() {
        if (root.appId === "") {
            return "";
        }
        try {
            const byHeuristic = DesktopEntries.heuristicLookup(root.appId);
            if (byHeuristic && byHeuristic.icon !== "") {
                return Quickshell.iconPath(byHeuristic.icon, "");
            }
            const byId = DesktopEntries.byId(root.appId);
            if (byId && byId.icon !== "") {
                return Quickshell.iconPath(byId.icon, "");
            }
        } catch (e) {
            // Unknown app id — the text label below still identifies it.
        }
        return "";
    }

    readonly property string iconUrl: resolveIcon()
    readonly property string label: root.onDesktop ? "Desktop" : (root.appTitle !== "" ? root.appTitle : (root.appId !== "" ? root.appId : "Desktop"))

    Row {
        id: appRow
        anchors.centerIn: parent
        spacing: Theme.space8

        Comp.AppIcon {
            anchors.verticalCenter: parent.verticalCenter
            iconName: root.appId
            iconSize: 24
            visible: root.iconUrl === ""
        }

        Image {
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            source: root.iconUrl
            visible: root.iconUrl !== ""
            asynchronous: true
        }

        Text {
            id: titleText
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.colCap)
            elide: Text.ElideRight
            text: root.label
            font.family: Theme.fontUi
            font.weight: Font.Medium
            font.pixelSize: 13
            color: root.onDesktop ? Colors.textMuted : Colors.textSecondary
        }
    }
}
