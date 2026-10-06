import Quickshell
import Quickshell.Wayland
import QtQuick
import ".."
import "../../services"

// VOID SHELL — popup window scaffold (PRD 13).
// One primary popup at a time: `visible` is derived from PopupManager, so
// panels never own open/closed state. Escape closes, placement is
// monitor-aware (`screen` follows the initiating bar), and the panel sits
// beneath the top bar with the standard gap.
//
// anchor: "left" | "center" | "right" — the bar region it belongs under.
// Children declared on a PopupShell land inside the panel column.
//
// Namespace: `voidshell-popup` keeps the panel out of the compositor's
// `^quickshell` blur rule. Hyprland 0.56 has no ignore-zero-alpha blur
// option, so blurring this surface paints a halo around the panel's
// transparent gutter (same artifact as the bar, docs/design-system §2).
PanelWindow {
    id: root

    // --- API -------------------------------------------------------------
    property string popupName: ""
    property int panelWidth: 340
    property int maxHeight: 640
    property string anchor: "right"
    property bool glow: false
    // Ink-wash wallpaper texture behind the panel glass (dashboard only).
    property bool texture: false
    // Explicit artwork for that texture; empty = live wallpaper.
    property string textureSource: ""
    // Content that animates its height pins the shell for the transition
    // (column-height units, -1 = follow the column). Every extra frame of
    // animation would otherwise resize the layer surface, and each resize
    // waits out a configure round trip — measured to pace a 180 ms tween
    // over ~500 ms. With the pin, open/close resizes the window once.
    property int heightPin: -1
    // Escape can be held off while a transient child surface (the Wi-Fi
    // password dialog, the device context menu) owns its own window-scope
    // handler: two matching ApplicationShortcuts are ambiguous to Qt and
    // then neither fires. The child surfaces flip this off while open and
    // the panel takes Escape back when they close.
    property bool escapeEnabled: true
    default property alias content: panelCol.data

    // --- geometry --------------------------------------------------------
    readonly property int columnHeight: panelCol.implicitHeight
    readonly property int panelHeight: Math.min(root.maxHeight,
        (root.heightPin >= 0 ? root.heightPin : panelCol.implicitHeight) + Theme.space12 * 2)
    readonly property var targetScreen: PopupManager.activeScreen !== null ? PopupManager.activeScreen : PopupManager.fallbackScreen
    readonly property int screenCenterX: Math.round(((root.targetScreen ? root.targetScreen.width : 1672) - root.implicitWidth) / 2)

    visible: PopupManager.isOpen(root.popupName)
    screen: root.targetScreen
    color: "transparent"
    WlrLayershell.namespace: "voidshell-popup"
    // Quickshell defaults to WlrKeyboardFocus.None, so without this the
    // compositor never sends a keystroke to the panel — Escape, search
    // typing and arrow keys all die. Exclusive grabs the keyboard while
    // the panel is mapped; Hyprland hands focus back to the previously
    // focused app when it unmaps.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    // -1: ignore other surfaces' exclusive zones — the bar's reservation
    // must never shove an already top-anchored panel downwards.
    exclusiveZone: -1


    implicitWidth: root.panelWidth + Theme.space16
    implicitHeight: root.panelHeight + Theme.space16

    anchors {
        top: true
        left: root.anchor !== "right"
        right: root.anchor === "right"
    }

    margins {
        top: Theme.topMargin + Theme.barHeight + Theme.space8
        left: root.anchor === "center" ? Math.max(Theme.sideMargin, root.screenCenterX) : Theme.sideMargin
        right: Theme.sideMargin
    }

    // Escape closes (PRD 13.1), from window scope: a clicked slider or
    // list inside the panel takes activeFocus, which would swallow an
    // Items-level Keys handler that isn't in its parent chain. The
    // application context keeps it honest — the shortcut only fires while
    // this shell owns keyboard focus, never while another app is focused.
    // The lock surface never uses a PopupShell, so PRD §25 stands.
    Shortcut {
        enabled: root.visible && root.escapeEnabled
        context: Qt.ApplicationShortcut
        sequences: [StandardKey.Cancel]
        onActivated: PopupManager.handleEscape()
    }

    // Focus claim on open (so the window holds keyboard focus at all).
    Item {
        id: escGrab
        anchors.fill: parent
        focus: root.visible
    }

    // Re-claim keyboard focus after a transient child window (password
    // dialog, device menu) closes, so the panel owns keys again.
    function claimFocus() {
        escGrab.forceActiveFocus();
    }

    onVisibleChanged: {
        if (visible) {
            escGrab.forceActiveFocus();
        }
    }

    GlassPanel {
        id: panel
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: Theme.space8
        width: root.panelWidth
        height: root.panelHeight
        glow: root.glow
        texture: root.texture
        textureSource: root.textureSource

        Column {
            id: panelCol
            width: parent.width
            spacing: Theme.space8
        }
    }
}
