pragma Singleton

import Quickshell
import QtQuick

// VOID SHELL — WindowActions (Workbench plan §architecture).
//
// The one place the Workbench dock *acts* on windows. Thin dispatch
// wrappers over HyprlandService's validated helpers — this service owns
// no window model of its own (the model lives in HyprlandService /
// ApplicationStore), only the call sequences the dock needs:
//
//   activate   : validate the address → focus (the compositor switches
//                workspace as part of focusing a window on another one)
//                → HyprlandService.trackAction observes the result.
//                Never opens the overview, never touches PopupManager.
//   cycle      : walk one app's windows in the compositor's own MRU
//                order, wrapping at the end.
//   launch     : desktop entries only, through LauncherModel — the dock
//                never invents a command from a window title.
//
// Every function is idempotent and safe on a dead address: HyprlandService
// re-validates before dispatching, so a stale slot reports false instead
// of focusing a window that no longer exists (plan §activation).
Singleton {
    id: root

    // Focus the exact window behind a slot's most-recent entry.
    function activateAddress(address) {
        return HyprlandService.activateWindow(address);
    }

    // Focus one app's most recently used window (left click, MRU mode).
    // Returns false when the app has no windows — the caller launches
    // instead (never both).
    function activateApp(key) {
        const tl = ApplicationStore.mruWindow(key);
        if (tl === null || tl === undefined) {
            return false;
        }
        return HyprlandService.activateWindow(tl.address);
    }

    // MRU with cycle: focus the MRU window, or — when it already holds
    // focus — step to the app's next window in MRU order (the "click the
    // focused app again to walk its windows" behaviour, plan §click).
    function cycleApp(key) {
        const windows = ApplicationStore.windowsFor(key);
        if (windows.length === 0) {
            return false;
        }
        if (!root.isFocused(windows[0])) {
            return HyprlandService.activateWindow(windows[0].address);
        }
        let idx = 0;
        const active = DesktopNavigationStore.activeAddress;
        for (let i = 0; i < windows.length; i++) {
            if (HyprlandService.normalizeAddress(windows[i].address) === active) {
                idx = i;
                break;
            }
        }
        const next = windows[(idx + 1) % windows.length];
        return HyprlandService.activateWindow(next.address);
    }

    // True when this exact toplevel is the active window.
    function isFocused(toplevel) {
        if (toplevel === null || toplevel === undefined) {
            return false;
        }
        const active = DesktopNavigationStore.activeAddress;
        return active !== "" && HyprlandService.normalizeAddress(toplevel.address) === active;
    }

    // Launch (or re-launch) a desktop entry. Left click on an idle pin
    // and middle click ("new instance") both land here: the exec path is
    // a fresh process request, and an app that answers single-instance
    // focuses itself instead — we never fake a second window.
    function launch(entry) {
        if (entry === null || entry === undefined) {
            return false;
        }
        LauncherModel.launchApp(entry);
        return true;
    }
}
