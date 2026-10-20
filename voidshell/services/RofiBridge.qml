pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// VOID SHELL — the IPC surface rofi's shell-backed modes call into.
//
// SUPER+R runs rofi's own `drun` list: it reads the .desktop files
// itself and nothing can interpose on it. Three of rofi's other modes
// belong to this shell instead, and they are deliberately thin —
// ~/.config/rofi/scripts/{fav,recent,act}.sh ask here for rows and hand
// the selection straight back:
//
//   qs -c voidshell ipc call void rows fav|recent|act
//   qs -c voidshell ipc call void run <payload>
//
// Everything the rows carry — the labels, the icons, the order, and
// what a click does — comes out of LauncherModel, the very model
// SUPER+Space renders. That is the point: the two drawers cannot drift
// apart because there is only one copy of the list, and this file is
// just rofi's line protocol spoken over it.
//
//   payload \x1f label \x1f icon     one row per line (rofi's \x1f)
//   label \0 icon \x1f <icon> \x1f info \x1f <payload>
//                                     what rofi actually wants
// The script does the second translation; this file only ever speaks
// the first.
Singleton {
    id: root

    // rofi's own field separator — the same \x1f its script protocol
    // uses for row options, so the scripts never have to re-split.
    readonly property string fs: "\u001f"

    // shell.qml references this so the singleton is instantiated at
    // startup: IpcHandler registers its target on construction, and a
    // target nothing references would never exist — every rofi selection
    // would come back "Target not found."
    readonly property bool registered: true

    /*
     * Icon names for the `act` rows. The drawer draws these commands as
     * Nerd Font glyphs (LauncherModel.commands[*].glyph); rofi's icon
     * widget takes theme names only, so this table is the one place the
     * two drawers are spelled differently. Every name below resolves
     * against `icon-theme: "Adwaita"` from config.rasi, which falls back
     * to AdwaitaLegacy where these live — checked against the installed
     * theme rather than assumed.
     */
    readonly property var commandIcons: ({
        "git":         "applications-development",
        "containers":  "package-x-generic",
        "monitor":     "utilities-system-monitor",
        "dashboard":   "preferences-desktop-display",
        "overview":    "preferences-system-windows",
        "settings":    "preferences-system",
        "shotFull":    "camera-photo",
        "shotRegion":  "applets-screenshooter",
        "shotOutput":  "video-display",
        "record":      "media-record",
        "theme":       "preferences-desktop-theme",
        "wallpaper":   "preferences-desktop-wallpaper",
        "web":         "web-browser"
    });

    /*
     * The IPC surface itself. Quickshell calls these by name, so the
     * signatures *are* the protocol:
     *
     *   qs -c voidshell ipc call void rows <mode>   -> rows, one per line
     *   qs -c voidshell ipc call void run <payload> -> handled or not
     *
     * They delegate rather than being the implementation, because
     * `rows`/`run` on the handler would shadow these and recurse.
     */
    IpcHandler {
        target: "void"

        function rows(mode: string): string {
            return root.rows(mode);
        }

        function run(payload: string): bool {
            return root.run(payload);
        }
    }

    // One row: "payload␟label␟icon". Uncoerced QML undefined would reach
    // rofi as the literal string "undefined", so everything is stringified
    // here rather than at each call site.
    function row(payload, label, icon) {
        const s = v => (v === undefined || v === null) ? "" : String(v);
        return s(payload) + root.fs + s(label) + root.fs + s(icon);
    }

    // Rows for one rofi script mode, in the order the drawer lists them.
    // `fav` and `recent` walk launcher.json through LauncherModel — the
    // same store the sidebar's two sections read — and `act` walks the
    // drawer's own command table, skipping whatever has no backend: the
    // drawer shows those greyed out with a reason, rofi omits them
    // instead, which says the same thing — not available on this machine.
    function rows(mode: string): string {
        const out = [];
        let i;
        let e;

        if (mode === "fav") {
            const favs = LauncherModel.favoriteIds;
            for (i = 0; i < favs.length; i++) {
                e = LauncherModel.entryById(favs[i]);
                if (e && !e.noDisplay && e.name) {
                    out.push(root.row(e.id, e.name, e.icon));
                }
            }
        } else if (mode === "recent") {
            const rec = LauncherModel.recentIds;
            for (i = 0; i < rec.length; i++) {
                e = LauncherModel.entryById(rec[i].id);
                if (e && !e.noDisplay && e.name) {
                    out.push(root.row(e.id, e.name, e.icon));
                }
            }
        } else if (mode === "act") {
            const cmds = LauncherModel.commands;
            for (i = 0; i < cmds.length; i++) {
                if (cmds[i].available === false) {
                    continue;
                }
                out.push(root.row(cmds[i].id, cmds[i].title, root.commandIcons[cmds[i].id] || ""));
            }
        }

        return out.join("\n");
    }

    // One selection, from any of the three modes. A drawer command wins
    // over an application id, because command ids are the only ones that
    // could collide with a desktop-file id in practice.
    function run(payload: string): bool {
        if (!payload) {
            return false;
        }
        const cmd = LauncherModel.commandById(payload);
        if (cmd) {
            return root.openCommand(cmd);
        }
        const entry = LauncherModel.entryById(payload);
        if (entry && !entry.noDisplay && entry.name) {
            // launchApp, not a raw exec: it is the drawer's own path, so
            // picking from rofi's Favorites records the launch into
            // launcher.json and the drawer's Recent stays truthful.
            LauncherModel.launchApp(entry);
            return true;
        }
        return false;
    }

    function openCommand(cmd): bool {
        if (cmd.kind === "popup" || cmd.kind === "action") {
            // Identical to pressing Enter on the row inside the drawer:
            // activateCommand owns the one-primary-popup rule and the
            // screenshot / recording service calls.
            LauncherModel.activateCommand(cmd);
            return true;
        }
        // @git / @containers / @color / @wp / @web only exist *inside*
        // the drawer (their views are QML, not a list rofi could render),
        // so hand the query over and let the drawer open itself. Launcher
        // applies pendingQuery the moment it moves — see Launcher.qml.
        // @web keeps a trailing space so the query gets typed rather than
        // fired empty, which is what the drawer's own Enter would do.
        LauncherModel.pendingQuery = (cmd.kind === "web") ? "@web " : cmd.prefix;
        return true;
    }
}
