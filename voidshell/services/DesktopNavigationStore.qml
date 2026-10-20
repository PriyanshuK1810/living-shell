pragma Singleton

import Quickshell
import QtQuick

// VOID SHELL — DesktopNavigationStore (Workbench plan §architecture).
//
// The dock family's read model: a thin facade over HyprlandService that
// answers exactly the navigation questions the Workbench asks (where am
// I, which monitor owns the gesture, which workspace holds this window)
// without ever copying the window list. Every property re-evaluates off
// HyprlandService's own state, so there is one model and no drift:
//
//   where I am     → focusedWorkspace / activeAddress
//   fullscreen?    → fullscreenHere (drives dodge + edge-reveal policy)
//   which monitor  → targetScreen (gesture owner ⇒ dock owner, plan §multi-monitor)
//   the workspace list → workspaces (all of them, specials included: a
//     window on `special:magic` is still "running elsewhere", not gone)
//
// Nothing here dispatches. Activation stays in WindowActions so "read"
// and "act" never blur (plan §architecture).
Singleton {
    id: root

    // HyprlandService ticks this on every compositor event; every list
    // derived below depends on it, exactly like the overview and shelf.
    readonly property int serial: HyprlandService.eventSerial
    readonly property var workspaces: HyprlandService.workspaces
    readonly property var focusedWorkspace: HyprlandService.focusedWorkspace
    readonly property var focusedMonitor: HyprlandService.focusedMonitor
    readonly property var activeToplevel: HyprlandService.focusedToplevel

    // Normalised (no `0x`) address of the active window ("" = desktop).
    readonly property string activeAddress: {
        const t = root.activeToplevel;
        return t === null || t === undefined ? "" : HyprlandService.normalizeAddress(t.address);
    }

    // Wayland app_id of the active window ("" = desktop).
    readonly property string activeAppId: HyprlandService.focusedAppId

    readonly property bool onDesktop: HyprlandService.onDesktop

    // A fullscreen window owns the screen: the dock neither dodges via
    // the edge zone nor shows it, and the dodge mode treats it as
    // "covered" (plan §fullscreen).
    readonly property bool fullscreenHere: {
        const ws = root.focusedWorkspace;
        return ws !== null && ws !== undefined && ws.hasFullscreen === true;
    }

    readonly property bool focusedIsUrgent: {
        const ws = root.focusedWorkspace;
        return ws !== null && ws !== undefined && ws.urgent === true;
    }

    function isFocusedWorkspace(workspace) {
        if (workspace === null || workspace === undefined || root.focusedWorkspace === null) {
            return false;
        }
        return workspace.id === root.focusedWorkspace.id;
    }

    // Windows of the focused workspace, MRU first (the compositor's own
    // order — this facade never sorts anything itself).
    function windowsHere() {
        const ws = root.focusedWorkspace;
        return ws === null ? [] : HyprlandService.orderedWindows(ws);
    }

    // Validate → activate a workspace by name (never a raw dispatch).
    function activate(workspaceName) {
        return HyprlandService.goToWorkspace(String(workspaceName));
    }

    // --- the monitor that owns the dock ---------------------------------
    // The gesture's monitor (the focused one, or the one under the
    // pointer — Hyprland keeps both in sync for a touchpad session) is
    // where the dock appears. Quickshell screens and Hyprland monitors
    // meet on the connector name; with no match the popup machine's
    // screens are the fallback every other surface uses. Single-monitor
    // sessions resolve to the same screen either way.
    readonly property var targetScreen: {
        const mon = root.focusedMonitor;
        const name = mon !== null && mon !== undefined && mon.name !== undefined ? String(mon.name) : "";
        if (name !== "") {
            const screens = Quickshell.screens;
            for (let i = 0; i < screens.length; i++) {
                if (String(screens[i].name) === name) {
                    return screens[i];
                }
            }
        }
        return PopupManager.activeScreen !== null ? PopupManager.activeScreen : PopupManager.fallbackScreen;
    }
}
