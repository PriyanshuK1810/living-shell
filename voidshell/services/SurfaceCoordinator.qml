pragma Singleton

import Quickshell
import QtQuick

// VOID SHELL — SurfaceCoordinator (Workbench plan §coordination).
//
// One owner for the *major* surfaces, so incompatible views can never
// stack and every open is atomic (opening one closes the others in the
// same call, never leaving a half-state):
//
//   majors: WorkspaceOverview, Dashboard, WorkbenchPreview,
//           WorkbenchActionMenu, WorkbenchKeyboardMode, ExpandedIsland,
//           StageManagerModal
//
// Integration, not a fork: the one-primary-popup machine in
// PopupManager stays authoritative for the popup panels (launcher,
// dashboard, overview, …) and the Island stack. This singleton adds
// the three Workbench subviews that are *not* PopupManager popups and
// enforces the cross-rules both ways:
//
//  * a popup/Island opening closes every Workbench subview
//    (Connections below — PopupManager never learns about us);
//  * a Workbench subview opening closes every popup + the Island
//    (requestWorkbench → PopupManager.closeAll()).
//
// Resting dock + top bar is explicitly compatible: the dock itself is
// not a major — only its preview/menu/keyboard subviews are. The Stage
// shelf stays a suppressed non-major (its own §9 rules already hide it
// whenever a popup is busy).
Singleton {
    id: root

    readonly property var majors: [
        "WorkspaceOverview",
        "Dashboard",
        "WorkbenchPreview",
        "WorkbenchActionMenu",
        "WorkbenchKeyboardMode",
        "ExpandedIsland",
        "StageManagerModal"
    ]

    // Current Workbench subview: "" | "WorkbenchPreview" |
    // "WorkbenchActionMenu" | "WorkbenchKeyboardMode".
    // Popup-side majors are read straight from PopupManager so there is
    // no second copy of that state.
    property string workbenchSurface: ""

    readonly property bool workbenchBusy: root.workbenchSurface !== ""

    // The one active major across both machines ("" = none / resting).
    readonly property string active: {
        if (PopupManager.activePopup === "overview") {
            return "WorkspaceOverview";
        }
        if (PopupManager.activePopup === "dashboard") {
            return "Dashboard";
        }
        if (PopupManager.islandOpen) {
            return "ExpandedIsland";
        }
        return root.workbenchSurface;
    }

    // Compatibility table used by request() and by the QA gate.
    // Resting dock (no subview) + top bar is compatible with everything
    // except the lock surface, which owns the screen outright.
    function compatible(a, b) {
        if (a === b) {
            return false;
        }
        if (a === "StageManagerModal" && b === "StageManagerModal") {
            return false;
        }
        return true;
    }

    function isOpen(major) {
        return root.active === major;
    }

    // --- atomic open -----------------------------------------------------
    // Returns true when the major now owns the surface. Opens are
    // refused while locked (the lock surface owns the screen, PRD 25).
    function request(major) {
        if (root.majors.indexOf(major) === -1) {
            console.warn("[voidshell] surface: unknown major " + major);
            return false;
        }
        if (PopupManager.locked && major !== "StageManagerModal") {
            return false;
        }
        root.closeAll(major);
        return true;
    }

    // A Workbench subview claims the surface: close every popup and the
    // Island first (never stack on the overview, never ride under the
    // dashboard), then record it. Returns false when the name is not a
    // Workbench major.
    function requestWorkbench(major) {
        if (major !== "WorkbenchPreview" && major !== "WorkbenchActionMenu" && major !== "WorkbenchKeyboardMode") {
            return false;
        }
        if (PopupManager.locked) {
            return false;
        }
        PopupManager.closeAll();     // closes the Island too
        root.workbenchSurface = major;
        return true;
    }

    // Atomic close of every major except `keep` ("" = close everything).
    function closeAll(keep) {
        const target = keep === undefined || keep === null ? "" : String(keep);
        if (root.workbenchSurface !== target && root.workbenchSurface !== "") {
            root.workbenchSurface = "";
        }
        if (target !== "WorkspaceOverview" && target !== "Dashboard"
                && target !== "ExpandedIsland" && PopupManager.activePopup !== "none") {
            PopupManager.closeAll();
        }
        if (target !== "ExpandedIsland" && PopupManager.islandOpen) {
            PopupManager.closeIsland();
        }
    }

    // Close one named major if it is the active one.
    function close(major) {
        if (major === root.workbenchSurface) {
            root.workbenchSurface = "";
            return;
        }
        if (major === "WorkspaceOverview" && PopupManager.activePopup === "overview") {
            PopupManager.closeAll();
            return;
        }
        if (major === "Dashboard" && PopupManager.activePopup === "dashboard") {
            PopupManager.closeAll();
            return;
        }
        if (major === "ExpandedIsland" && PopupManager.islandOpen) {
            PopupManager.closeIsland();
        }
    }

    // Escape / dismiss: topmost first — a Workbench subview is always
    // above the resting dock, so it goes before any popup state.
    function handleEscape() {
        if (root.workbenchSurface !== "") {
            root.workbenchSurface = "";
            return true;
        }
        return false;
    }

    // The popup machine moved without us (keybind, bar button, IPC):
    // every Workbench subview closes in the same beat, so a Dashboard
    // opened by Super+Shift+D can never coexist with the dock preview.
    Connections {
        target: PopupManager
        function onActivePopupChanged() {
            if (PopupManager.activePopup !== "none" && root.workbenchSurface !== "") {
                root.workbenchSurface = "";
            }
        }
        function onIslandModeChanged() {
            if (PopupManager.islandOpen && root.workbenchSurface !== "") {
                root.workbenchSurface = "";
            }
        }
        function onLockedChanged() {
            if (PopupManager.locked && root.workbenchSurface !== "") {
                root.workbenchSurface = "";
            }
        }
    }
}
