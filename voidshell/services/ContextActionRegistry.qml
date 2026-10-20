pragma Singleton

import Quickshell
import QtQuick

// VOID SHELL — ContextActionRegistry (Workbench plan §palette).
//
// What the dock's right-click palette may show — and nothing else:
//
//   app section     → up to 4 of the *real* desktop actions declared by
//                     the focused app's own .desktop file
//                     (DesktopEntry.actions → DesktopAction.execute()).
//                     No title inference, no guessed verbs: an app with
//                     no actions contributes no rows.
//   universal rows  → opt-in only (WorkbenchSettings.universalActions,
//                     empty by default). Ids are config values, but the
//                     handler behind each id lives in the catalog below:
//                     config picks, code executes — JSON never runs a
//                     command. An unknown id is ignored (logged once).
//
// Availability is checked per run (a missing terminal or disabled shelf
// disables its row instead of failing on click), and system controls
// (battery/Wi-Fi/Bluetooth/volume/notifications) are deliberately not in
// the catalog: the dock never duplicates the top bar or Quick Settings.
Singleton {
    id: root

    // Ids with no provider in this shell are documented here and are
    // simply not offered: "projectFolder" (the Stage shelf has no
    // project model to own a folder), "notes" (no notes app/provider),
    // "search" (the launcher popup already is the search surface).
    readonly property var catalog: [
        {
            id: "terminal",
            label: "Terminal",
            icon: "utilities-terminal",
            available: () => LauncherModel.terminalBin !== "",
            run: () => HyprlandService.execShell(HyprlandService.shQuote(LauncherModel.terminalBin))
        },
        {
            id: "files",
            label: "File manager",
            icon: "system-file-manager",
            available: () => root.fileManagerEntry() !== null,
            run: () => LauncherModel.launchApp(root.fileManagerEntry())
        },
        {
            id: "screenshot",
            label: "Screenshot",
            icon: "camera-photo",
            available: () => ScreenshotService.available,
            run: () => ScreenshotService.capture("full")
        },
        {
            id: "clipboard",
            label: "Clipboard history",
            icon: "edit-paste",
            available: () => IslandController.enabled && ClipboardService.available,
            run: () => {
                IslandController.setSection("clip");
                IslandController.openStack();
            }
        },
        {
            id: "launcher",
            label: "Command launcher",
            icon: "system-run",
            available: () => true,
            run: () => PopupManager.open("launcher")
        },
        {
            id: "shelf",
            label: "Inventory shelf",
            icon: "view-list",
            available: () => ManagerSettings.managerEnabled && ManagerSettings.shelfEnabled && !PopupManager.locked,
            run: () => HyprlandService.execShell("qs -c voidshell ipc call shelf toggle")
        }
    ]

    // Installed file managers, most specific first. Resolved against
    // real desktop entries; no hit means no provider (the row hides).
    readonly property var fileManagerIds: [
        "org.kde.dolphin.desktop",
        "org.gnome.Nautilus.desktop",
        "thunar.desktop",
        "pcmanfm.desktop",
        "nemo.desktop"
    ]

    function fileManagerEntry() {
        for (let i = 0; i < root.fileManagerIds.length; i++) {
            const e = LauncherModel.entryById(root.fileManagerIds[i]);
            if (e !== null && e !== undefined && !e.noDisplay) {
                return e;
            }
        }
        return null;
    }

    function lookup(id) {
        for (let i = 0; i < root.catalog.length; i++) {
            if (root.catalog[i].id === id) {
                return root.catalog[i];
            }
        }
        return null;
    }

    // --- app actions (real desktop actions, at most four) ---------------
    function appActions(entry) {
        if (entry === null || entry === undefined) {
            return [];
        }
        let list = null;
        try {
            list = entry.actions;
        } catch (e) {
            return [];
        }
        if (list === null || list === undefined || list.length === undefined) {
            return [];
        }
        const out = [];
        for (let i = 0; i < list.length && out.length < 4; i++) {
            const a = list[i];
            if (a === null || a === undefined) {
                continue;
            }
            let runnable = false;
            try {
                const cmd = a.command !== undefined && a.command !== null ? a.command : [];
                const exec = a.execString !== undefined && a.execString !== null ? String(a.execString) : "";
                runnable = (cmd.length !== undefined && cmd.length > 0) || exec !== "";
            } catch (e) {
                runnable = false;
            }
            if (!runnable) {
                continue;
            }
            const action = a;
            out.push({
                id: String(action.id !== undefined && action.id !== null ? action.id : ""),
                label: String(action.name !== undefined && action.name !== null ? action.name : ""),
                icon: action.icon !== undefined && action.icon !== null ? String(action.icon) : "",
                universal: false,
                run: () => action.execute()
            });
        }
        return out;
    }

    // --- universal rows (opt-in ids, trusted handlers only) -------------
    property var unknownLogged: []

    function logUnknown(id) {
        if (root.unknownLogged.indexOf(id) === -1) {
            root.unknownLogged = root.unknownLogged.concat([id]);
            console.warn("[voidshell] workbench: universal action '" + id + "' has no provider, ignored");
        }
    }

    function universalActions() {
        const ids = WorkbenchSettings.universalActions;
        const out = [];
        for (let i = 0; i < ids.length; i++) {
            const id = String(ids[i]);
            const entry = root.lookup(id);
            if (entry === null) {
                root.logUnknown(id);
                continue;
            }
            let ok = false;
            try {
                ok = entry.available() === true;
            } catch (e) {
                ok = false;
            }
            if (!ok) {
                continue;
            }
            const trusted = entry;
            out.push({
                id: trusted.id,
                label: trusted.label,
                icon: trusted.icon,
                universal: true,
                run: trusted.run
            });
        }
        return out;
    }

    // The palette's two sections. A section with no provider simply
    // stays empty — the view hides it, it is never padded with filler.
    function sectionsFor(entry) {
        return {
            app: root.appActions(entry),
            universal: root.universalActions()
        };
    }

    function hasAny(entry) {
        const s = root.sectionsFor(entry);
        return s.app.length > 0 || s.universal.length > 0;
    }
}
