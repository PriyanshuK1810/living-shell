import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../common"

// VOID SHELL — persistent top bar: three independent floating glass
// islands (left / center / right). No continuous bar background; the
// wallpaper stays visible between modules. Only the center island owns
// the top-edge exclusive zone.
Scope {
    id: root

    // RESERVATION (Hyprland 0.56): only the center island sets a positive
    // exclusive zone (topMargin + barHeight = 56), so windows stop loading
    // underneath the bar. Honoring a zone makes the compositor push every
    // other top-edge surface away by zone + margin — which is why the left
    // and right islands (and every popup/overlay in the shell) pass
    // exclusiveZone: -1 ("ignore other surfaces' zones") and keep sitting
    // at Theme.topMargin.

    // LAYER — all three islands sit on the Bottom layer, behind the
    // window layer: a fullscreen or floating app draws over the bar
    // instead of the bar floating on top of it. Tiled windows still stop
    // at the center island's exclusive zone, keeping the strip clear.

    // BLUR — every voidshell surface declares a `voidshell-*` namespace so
    // the compositor rule `quickshell-blur` (namespace ^quickshell,
    // ~/.config/hypr/hyprland.lua) never matches it. Hyprland 0.56 blurs
    // every pixel of a matched surface — zero-alpha pixels too — which
    // painted a white halo around the pills, in the gaps between them and
    // around every popup panel; it has no ignore-zero-alpha option, so
    // the only fix is to not match. See docs/design-system.md §2.

    // --- island width budget (no island may touch another) --------------
    // The clock island is horizontally centered, so its edges sit at
    // screenW/2 ± ceil(centerW/2). Each outer island gets the span from
    // its side margin out to the clock edge minus one pillGap — never
    // more, so a long media title can no longer push the right island
    // under the clock (measured: 588px wide, 51px of overlap).
    readonly property int screenW: rightWin.screen ? rightWin.screen.width : 1280
    readonly property int centerHalf: Math.ceil(centerWin.implicitWidth / 2)
    readonly property int rightBudget: Math.max(360, Math.floor(screenW / 2) - centerHalf - Theme.sideMargin - Theme.pillGap)
    readonly property int leftBudget: Math.max(360, Math.floor(screenW / 2) - centerHalf - Theme.sideMargin - Theme.pillGap)

    // LEFT: launcher + workspaces + active app may occupy the span from
    // the side margin out to the clock's left edge minus one pillGap.
    readonly property int leftNatural: launcherPill.width + workspacesPill.width + activeAppPill.naturalWidth + Theme.pillGap * 2
    readonly property int leftOver: Math.max(0, leftNatural - leftBudget)
    // The active-app label is the only eliding pill on this side.
    readonly property int takeActive: Math.min(leftOver, activeAppPill.textShrinkable)
    readonly property int leftResidual: Math.max(0, leftOver - takeActive)

    // RIGHT: media + tray + status + power.
    readonly property int rightPills: 3 + (trayPill.trayItems.length > 0 ? 1 : 0)
    readonly property int rightGaps: Theme.pillGap * Math.max(0, rightPills - 1)
    readonly property int rightNatural: mediaPill.naturalWidth + trayPill.naturalWidth + statusPill.naturalWidth + powerPill.width + rightGaps
    readonly property int rightOver: Math.max(0, rightNatural - rightBudget)

    // Split of the shortfall, cheapest first: media text elides (the most
    // elastic lever), then the status pill tightens gaps and padding —
    // never state, then the media artwork shrinks. The tray folds ahead
    // of all of it: it is the only pill built to give items up.
    readonly property int takeTray: Math.min(rightOver, trayPill.foldable)
    readonly property int takeMediaText: Math.min(rightOver - takeTray, mediaPill.textShrinkable)
    readonly property int takeStatus: Math.min(rightOver - takeTray - takeMediaText, statusPill.compressible)
    readonly property int takeMediaArt: Math.min(Math.max(0, rightOver - takeTray - takeMediaText - takeStatus), mediaPill.artShrinkable)
    readonly property int rightResidual: Math.max(0, rightOver - takeTray - takeMediaText - takeStatus - takeMediaArt)

    // LEFT: launcher + workspaces + active app.
    PanelWindow {
        id: leftWin
        anchors {
            top: true
            left: true
        }
        margins {
            top: Theme.topMargin
            left: Theme.sideMargin
        }
        implicitWidth: Math.min(leftRow.implicitWidth, root.leftBudget)
        implicitHeight: Theme.topMargin + Theme.barHeight
        // -1: ignore the center island's exclusive zone, otherwise
        // avoidance (zone + margin) shoves this island off its topMargin.
        exclusiveZone: -1
        color: "transparent"
        WlrLayershell.namespace: "voidshell-bar"
        // Behind the window layer: the active app draws over the bar
        // (fullscreen/floating windows cover it). The center island's
        // exclusive zone still reserves the top strip for tiled windows,
        // so the bar stays visible in its own lane.
        WlrLayershell.layer: WlrLayer.Bottom

        Row {
            id: leftRow
            anchors.top: parent.top
            height: Theme.barHeight
            spacing: Theme.pillGap

            LauncherPill {
                id: launcherPill
                shellScreen: leftWin.screen
            }
            WorkspacesPill {
                id: workspacesPill
            }
            ActiveAppPill {
                id: activeAppPill
                maxWidth: activeAppPill.naturalWidth - root.takeActive
            }
        }
    }

    // CENTER: clock/date (owns the top exclusive zone).
    PanelWindow {
        id: centerWin
        anchors {
            top: true
        }
        margins {
            top: Theme.topMargin
        }
        implicitWidth: 170
        implicitHeight: Theme.topMargin + Theme.barHeight
        // The bar's reservation: tiled windows now start at the pill row's
        // bottom edge (topMargin + barHeight = 56) instead of sliding under
        // the bar. Only this island reserves — the other islands, popups,
        // toasts and overlays all pass -1 so nothing is pushed around by it.
        exclusiveZone: Theme.topMargin + Theme.barHeight
        color: "transparent"
        WlrLayershell.namespace: "voidshell-bar"
        // Behind the window layer: the active app draws over the bar
        // (fullscreen/floating windows cover it). The center island's
        // exclusive zone still reserves the top strip for tiled windows,
        // so the bar stays visible in its own lane.
        WlrLayershell.layer: WlrLayer.Bottom

        ClockPill {
            shellScreen: centerWin.screen
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    // RIGHT: media + tray + status + power.
    PanelWindow {
        id: rightWin
        anchors {
            top: true
            right: true
        }
        margins {
            top: Theme.topMargin
            right: Theme.sideMargin
        }
        implicitWidth: Math.min(rightRow.implicitWidth, root.rightBudget)
        implicitHeight: Theme.topMargin + Theme.barHeight
        exclusiveZone: -1
        color: "transparent"
        WlrLayershell.namespace: "voidshell-bar"
        // Behind the window layer: the active app draws over the bar
        // (fullscreen/floating windows cover it). The center island's
        // exclusive zone still reserves the top strip for tiled windows,
        // so the bar stays visible in its own lane.
        WlrLayershell.layer: WlrLayer.Bottom

        Row {
            id: rightRow
            anchors.top: parent.top
            height: Theme.barHeight
            spacing: Theme.pillGap

            MediaPill {
                id: mediaPill
                shellScreen: rightWin.screen
                maxWidth: mediaPill.naturalWidth - root.takeMediaText - root.takeMediaArt
            }
            TrayPill {
                id: trayPill
                maxWidth: trayPill.naturalWidth - root.takeTray
            }
            StatusPill {
                id: statusPill
                shellScreen: rightWin.screen
                maxWidth: statusPill.naturalWidth - root.takeStatus
            }
            PowerPill {
                id: powerPill
                shellScreen: rightWin.screen
            }
        }
    }
}
