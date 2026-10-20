pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — centralized launcher model.
// Holds pinned application IDs and exposes the full DesktopEntries
// list with search filtering. All UI binds to this singleton.
Singleton {
    id: root

    // --- Pinned configuration ---
    // Edit this list to change pinned apps. Missing apps are hidden.
    readonly property var pinnedIds: [
        "firefox.desktop",
        "org.kde.dolphin.desktop",
        "kitty.desktop",
        "code.desktop",
        "spotify.desktop",
        "discord.desktop"
    ]

    // --- Internal state ---
    property string searchText: ""
    property int selectedIndex: -1

    // Active in-launcher plugin view ("" = app/command list). See PRD §19.2.
    property string activePlugin: ""

    // Active sidebar section: "all" | "favorites" | "recent" | "cat:<name>".
    // Search filters within the active section (the sidebar keeps saying
    // where you are); the `@` command list is section-independent.
    property string section: "all"

    // --- Persisted launcher state ----------------------------------------
    // ~/.local/share/voidshell/launcher.json — favorites (the sidebar's
    // Favorites row) and recent launches (Recent section + bottom strip).
    // First run (or an unreadable file) seeds favorites from pinnedIds
    // above; after that the store is the source of truth.
    property var favoriteIds: []
    property var recentIds: []        // [{id, ts}] newest first

    // Typed-query history (rofi's entry history): submitted commands,
    // newest first, capped at 30 — persisted in the same store as
    // favourites/recents so nothing here is rofi-private. `historyCursor`
    // is the index being shown, -1 meaning "the field holds live text";
    // `historyEcho` is the text history navigation last wrote, which is
    // how setSearch tells a recalled query (leave the cursor alone) from
    // fresh typing (reset it), and `historyDraft` is the line the first
    // Ctrl+Up stashed so the last Ctrl+Down can hand it back.
    property var queryHistory: []
    property int historyCursor: -1
    property string historyEcho: ""
    property string historyDraft: ""

    // First installed terminal found by the startup probe ("" = none);
    // the detail panel's "Open in Terminal" row disables itself honestly.
    property string terminalBin: ""

    // --- Computed pinned apps (only those that exist) ---
    readonly property var pinnedApps: {
        var result = [];
        for (var i = 0; i < root.pinnedIds.length; i++) {
            var entry = DesktopEntries.byId(root.pinnedIds[i]);
            if (entry && !entry.noDisplay) {
                result.push(entry);
            }
        }
        return result;
    }

    // --- Sidebar sections ------------------------------------------------
    // Real backends only: All = every visible entry; Favorites and Recent
    // come from launcher.json; categories are the entry's own desktop-file
    // Categories field (the UI hides zero-count categories).
    readonly property var sidebarSections: [
        { id: "all", label: "All Apps", glyph: 0xf00a },
        { id: "favorites", label: "Favorites", glyph: 0xf004 },
        { id: "recent", label: "Recent", glyph: 0xf017 },
        { id: "cat:Development", label: "Development", glyph: 0xf121, cats: ["Development"] },
        { id: "cat:Internet", label: "Internet", glyph: 0xf0ac, cats: ["Network"] },
        { id: "cat:Multimedia", label: "Multimedia", glyph: 0xf001, cats: ["AudioVideo", "Audio", "Video"] },
        { id: "cat:System", label: "System", glyph: 0xf013, cats: ["System", "Settings"] },
        { id: "cat:Utilities", label: "Utilities", glyph: 0xf0ad, cats: ["Utility"] }
    ];

    function sectionSpec(sectionId) {
        for (var i = 0; i < root.sidebarSections.length; i++) {
            if (root.sidebarSections[i].id === sectionId) {
                return root.sidebarSections[i];
            }
        }
        return null;
    }

    // --- Every visible application entry (no search/section filter) -----
    readonly property var allEntries: {
        var result = [];
        var apps = DesktopEntries.applications;
        if (!apps || !apps.values) {
            return result;
        }
        var vals = apps.values;
        for (var i = 0; i < vals.length; i++) {
            var entry = vals[i];
            if (entry && !entry.noDisplay && entry.name) {
                result.push(entry);
            }
        }
        return result;
    }

    // Base list for a section, before the search filter. Recent keeps its
    // chronological order (allApps skips the sort for it).
    function appsForSection(sectionId) {
        var all = root.allEntries;
        if (sectionId === "all" || !sectionId) {
            return all;
        }
        var out = [];
        var i;
        if (sectionId === "favorites") {
            for (i = 0; i < root.favoriteIds.length; i++) {
                var fe = root.entryById(root.favoriteIds[i]);
                if (fe && !fe.noDisplay && fe.name) {
                    out.push(fe);
                }
            }
            return out;
        }
        if (sectionId === "recent") {
            for (i = 0; i < root.recentIds.length; i++) {
                var re = root.entryById(root.recentIds[i].id);
                if (re && !re.noDisplay && re.name) {
                    out.push(re);
                }
            }
            return out;
        }
        var spec = root.sectionSpec(sectionId);
        if (!spec || !spec.cats) {
            return all;
        }
        for (i = 0; i < all.length; i++) {
            var cats = all[i].categories;
            if (!cats || cats.length === undefined) {
                continue;
            }
            for (var c = 0; c < spec.cats.length; c++) {
                var hit = false;
                for (var m = 0; m < cats.length; m++) {
                    if (String(cats[m]) === spec.cats[c]) {
                        hit = true;
                        break;
                    }
                }
                if (hit) {
                    out.push(all[i]);
                    break;
                }
            }
        }
        return out;
    }

    // Reactive base list for the active section — the grid, the sidebar
    // counts and the detail panel all re-run when favorites, recents or
    // the desktop entries change.
    readonly property var sectionApps: root.appsForSection(root.section)

    // Real app count behind one sidebar row.
    function countFor(sectionId) {
        return root.appsForSection(sectionId).length;
    }

    // Recent launches as entries, newest first (bottom strip uses this).
    readonly property var recentApps: root.appsForSection("recent")

    // --- Section + search filtered applications --------------------------
    //
    // Field set is the union of both drawers': this list adds name,
    // generic, comment and id (the shell's own), and now exec, categories
    // and keywords too — the three rofi's `drun-match-fields` adds
    // (config.rasi). Superset on purpose, so a query that finds an app in
    // SUPER+R finds it here as well. The one asymmetry left is comment/id:
    // rofi does not search those, so this drawer can still match a query
    // SUPER+R will not.
    function matches(entry, needle) {
        if (needle === "") {
            return true;
        }
        const fields = [entry.name, entry.genericName, entry.comment, entry.id, entry.execString];
        for (var i = 0; i < fields.length; i++) {
            if (fields[i] && String(fields[i]).toLowerCase().indexOf(needle) !== -1) {
                return true;
            }
        }
        // categories/keywords are QStringList-valued on DesktopEntry, so
        // they are walked entry by entry; a missing property is a miss.
        const lists = [entry.categories, entry.keywords];
        for (var l = 0; l < lists.length; l++) {
            var list = lists[l];
            if (!list || list.length === undefined) {
                continue;
            }
            for (var k = 0; k < list.length; k++) {
                if (String(list[k]).toLowerCase().indexOf(needle) !== -1) {
                    return true;
                }
            }
        }
        return false;
    }

    readonly property var allApps: {
        var base = root.sectionApps;
        var needle = root.searchText.toLowerCase();
        var result = [];
        for (var i = 0; i < base.length; i++) {
            var entry = base[i];
            if (root.matches(entry, needle)) {
                result.push(entry);
            }
        }
        // Recent stays chronological; other sections sort by match quality.
        // SUPER+R runs `sort: false` and takes the mode's own order, which
        // is this same localeCompare once the query is empty — so browsing
        // reads identically. The prefix boost below is the documented
        // divergence: typed queries rank prefix matches first here, while
        // rofi hands ranking to its matcher.
        if (root.section !== "recent") {
            result.sort(function(a, b) {
                var an = a.name.toLowerCase();
                var bn = b.name.toLowerCase();
                var aPref = an.startsWith(needle) ? 0 : 1;
                var bPref = bn.startsWith(needle) ? 0 : 1;
                if (aPref !== bPref) return aPref - bPref;
                return an.localeCompare(bn);
            });
        }
        return result;
    }

    // The detail panel's app (null in command mode or with no selection).
    readonly property var selectedEntry: {
        if (root.commandMode) {
            return null;
        }
        var list = root.allApps;
        if (root.selectedIndex < 0 || root.selectedIndex >= list.length) {
            return null;
        }
        return list[root.selectedIndex];
    }

    function setSection(sectionId) {
        root.section = sectionId;
        root.selectedIndex = 0;
    }

    // --- Section cycling (rofi's kb-mode-next / kb-mode-previous) --------
    // rofi walks its modes with Ctrl+Tab and Shift+Left / Shift+Right;
    // this drawer's eight sections sit behind a mouse-only sidebar, so the
    // same keys walk sidebarSections here, wrapping both ways. The query
    // is deliberately kept: search filters *within* the section you land
    // on, which is what the sidebar has always meant (the `@` command
    // list stays section-independent — its sidebar highlight is the only
    // visible half of a cycle there).
    function cycleSection(delta) {
        const secs = root.sidebarSections;
        if (secs.length === 0) {
            return;
        }
        let i = 0;
        for (let j = 0; j < secs.length; j++) {
            if (secs[j].id === root.section) {
                i = j;
                break;
            }
        }
        let next = (i + delta) % secs.length;
        if (next < 0) {
            next += secs.length;
        }
        root.setSection(secs[next].id);
    }

    // --- Launcher commands / plugins (PRD §19.2) ------------------------
    // kind: plugin  → opens an in-launcher plugin view
    //       popup   → opens a shell popup (dashboard, monitor, …)
    //       action  → runs a real service call (screenshot, recording)
    //       web     → web search for the typed query
    // `available` is evaluated against live service state, so commands
    // whose backend is missing render disabled with a reason (PRD §37).
    readonly property var commands: [
        {
            id: "git", prefix: "@git", title: "Repository Browser",
            hint: "Search configured git roots", keywords: "git repo repositories vcs source branch",
            kind: "plugin", plugin: "git", glyph: 0xec6f, available: true
        },
        {
            id: "containers", prefix: "@containers", title: "Docker / Containers",
            hint: "Containers, images and volumes", keywords: "docker containers images volumes compose",
            kind: "plugin", plugin: "containers", glyph: 0xf21f, available: true
        },
        {
            id: "monitor", title: "System Monitor",
            hint: "CPU, memory, disk, network and processes", keywords: "system monitor cpu memory ram process htop performance",
            kind: "popup", target: "taskManager", glyph: 0xeeb2, available: true
        },
        {
            id: "dashboard", title: "Dashboard",
            hint: "Overview, media, weather, alerts, productivity", keywords: "dashboard widgets overview stats",
            kind: "popup", target: "dashboard", glyph: 0xf0570, available: true
        },
        {
            id: "overview", title: "Workspace Overview",
            hint: "All workspaces and their windows", keywords: "workspace overview windows spaces expose",
            kind: "popup", target: "overview", glyph: 0xeb23, available: true
        },
        {
            id: "settings", title: "Quick Settings",
            hint: "Network, bluetooth, audio, brightness", keywords: "settings quick settings wifi network bluetooth audio brightness",
            kind: "popup", target: "quickSettings", glyph: 0xf1de, available: true
        },
        {
            id: "shotFull", title: "Screenshot — Full screen",
            hint: "Saves to ~/Pictures/Screenshots", keywords: "screenshot capture grab screen print",
            kind: "action", action: "shot-full", glyph: 0xf030,
            available: ScreenshotService.available, unavailableReason: "grim or slurp is not installed"
        },
        {
            id: "shotRegion", title: "Screenshot — Region",
            hint: "Select an area with slurp", keywords: "screenshot capture area region selection grab",
            kind: "action", action: "shot-region", glyph: 0xf030,
            available: ScreenshotService.available, unavailableReason: "grim or slurp is not installed"
        },
        {
            id: "shotOutput", title: "Screenshot — Active output",
            hint: "Current monitor only", keywords: "screenshot capture monitor output",
            kind: "action", action: "shot-output", glyph: 0xf030,
            available: ScreenshotService.available, unavailableReason: "grim or slurp is not installed"
        },
        {
            id: "record", title: "Screen Recording — Start / Stop",
            hint: "wf-recorder to ~/Videos", keywords: "record recording video capture wf-recorder screencast",
            kind: "action", action: "record", glyph: 0xf0ec2,
            available: RecordingService.available, unavailableReason: "wf-recorder is not installed"
        },
        {
            id: "theme", prefix: "@color", title: "Theme Manager",
            hint: "Presets with palette previews, dark / light", keywords: "theme color accent palette preset colors light dark appearance",
            kind: "plugin", plugin: "theme", glyph: 0xefcc, available: true
        },
        {
            id: "wallpaper", prefix: "@wp", title: "Wallpaper Manager",
            hint: "Browse wallpapers, locked or dynamic palette", keywords: "wallpaper background image picture backdrop desktop wp",
            kind: "plugin", plugin: "wallpaper", glyph: 0xf02e9, available: true
        },
        {
            id: "web", prefix: "@web", title: "Web Search",
            hint: "Open the typed query in your browser", keywords: "web search internet duckduckgo browser",
            kind: "web", glyph: 0xf0ac, available: true
        }
    ];

    // Typing `@` switches the result list from apps to commands (PRD §19.2:
    // discoverable when the user types `@` or opens launcher commands).
    readonly property bool commandMode: root.searchText.startsWith("@")

    readonly property var filteredCommands: {
        if (!root.commandMode) {
            return [];
        }
        const q = root.searchText.toLowerCase();
        const bare = q.slice(1);
        const out = [];
        for (let i = 0; i < root.commands.length; i++) {
            const c = root.commands[i];
            const prefix = c.prefix ? c.prefix.toLowerCase() : "";
            const title = c.title.toLowerCase();
            const keywords = c.keywords ? c.keywords.toLowerCase() : "";
            if (q === "@" ||
                (prefix !== "" && (prefix.indexOf(q) === 0 || q.indexOf(prefix) === 0)) ||
                title.indexOf(bare) !== -1 ||
                keywords.indexOf(bare) !== -1) {
                out.push(c);
            }
        }
        return out;
    }

    // Whatever the selection index currently walks over.
    readonly property var results: root.commandMode ? root.filteredCommands : root.allApps

    // Query text after the active command prefix ("@git foo" → "foo").
    readonly property string pluginQuery: {
        const i = root.searchText.indexOf(" ");
        return i === -1 ? "" : root.searchText.slice(i + 1).trim();
    }

    // Dynamic hint for stateful commands (recording toggles label).
    function hintFor(cmd) {
        if (cmd && cmd.action === "record") {
            return RecordingService.recording ? "Recording " + RecordingService.elapsedLabel + " — press to stop" : "wf-recorder to ~/Videos";
        }
        return cmd ? cmd.hint : "";
    }

    function commandForPlugin(pluginId) {
        for (let i = 0; i < root.commands.length; i++) {
            if (root.commands[i].plugin === pluginId) {
                return root.commands[i];
            }
        }
        return null;
    }

    function commandById(id) {
        for (let i = 0; i < root.commands.length; i++) {
            if (root.commands[i].id === id) {
                return root.commands[i];
            }
        }
        return null;
    }

    // Query the drawer applies the next time it opens. rofi's `act` mode
    // lands here through services/RofiBridge.qml: @git, @containers,
    // @color, @wp and @web are QML views that only exist inside this
    // drawer, so rofi hands the query over instead of pretending to have
    // them. Launcher.qml listens for the change and applies it — see
    // openWithQuery there for why the property is cleared inside the
    // handler rather than by the writer.
    property string pendingQuery: ""

    function setSearch(text) {
        // Fresh typing (or any write that isn't a history recall) puts
        // the history cursor back to "live": historyPrev/historyNext set
        // historyEcho first, so the query they wrote passes this test.
        if (text !== root.historyEcho) {
            root.historyCursor = -1;
            root.historyDraft = "";
        }
        root.searchText = text;
        root.selectedIndex = 0;
        if (!text.startsWith("@")) {
            root.activePlugin = "";
            return;
        }
        // Leave the plugin when its prefix stops matching what is typed.
        if (root.activePlugin !== "") {
            const cmd = root.commandForPlugin(root.activePlugin);
            if (!cmd || !text.startsWith(cmd.prefix)) {
                root.activePlugin = "";
            }
        }
    }

    function clearSearch() {
        root.searchText = "";
        root.activePlugin = "";
        root.section = "all";
        root.selectedIndex = -1;
        root.historyCursor = -1;
        root.historyEcho = "";
        root.historyDraft = "";
    }

    // Back out of a plugin view to the command list, keeping the prefix.
    function clearPlugin() {
        const cmd = root.commandForPlugin(root.activePlugin);
        root.activePlugin = "";
        if (cmd) {
            root.searchText = cmd.prefix;
            root.selectedIndex = 0;
        }
    }

    function moveSelection(delta) {
        const list = root.results;
        if (list.length === 0) {
            root.selectedIndex = -1;
            return;
        }
        let next = root.selectedIndex + delta;
        if (next < 0) next = list.length - 1;
        if (next >= list.length) next = 0;
        root.selectedIndex = next;
    }

    // Enter / click: apps launch, commands dispatch (PRD §19.1–19.2).
    function activateSelected() {
        const list = root.results;
        if (root.selectedIndex < 0 || root.selectedIndex >= list.length) {
            return;
        }
        const item = list[root.selectedIndex];
        if (root.commandMode) {
            root.activateCommand(item);
        } else {
            root.launchApp(item);
        }
    }

    function launchSelected() {
        root.activateSelected();
    }

    function activateCommand(cmd) {
        if (!cmd || cmd.available === false) {
            return;
        }
        if (cmd.kind === "plugin") {
            root.activePlugin = cmd.plugin;
            root.selectedIndex = 0;
            return;
        }
        if (cmd.kind === "popup") {
            PopupManager.open(cmd.target);
            return;
        }
        if (cmd.kind === "web") {
            const q = root.pluginQuery;
            if (q === "") {
                ToastService.push("Web search", "Type a query after @web", "", "warning");
                return;
            }
            HyprlandService.execShell("xdg-open " + HyprlandService.shQuote("https://duckduckgo.com/?q=" + encodeURIComponent(q)));
            PopupManager.closeAll();
            return;
        }
        if (cmd.kind === "action") {
            root.runAction(cmd.action);
            PopupManager.closeAll();
        }
    }

    function runAction(action) {
        if (action === "shot-full") {
            ScreenshotService.capture("full");
        } else if (action === "shot-region") {
            ScreenshotService.capture("region");
        } else if (action === "shot-output") {
            ScreenshotService.capture("output");
        } else if (action === "record") {
            RecordingService.toggle("full");
        }
    }

    function launchApp(entry) {
        if (!entry || !entry.command || !entry.command.length) {
            return;
        }
        root.recordLaunch(entry);
        try {
            // Hyprland 0.56 (Lua IPC): `hl.dsp.exec_cmd` runs the string
            // through /bin/sh, so each argv part is shell-quoted. The old
            // two-argument `Hyprland.dispatch("exec", …)` form no longer
            // resolves on this build.
            const parts = [];
            for (let i = 0; i < entry.command.length; i++) {
                parts.push(HyprlandService.shQuote(entry.command[i]));
            }
            HyprlandService.execShell(parts.join(" "));
        } catch (e) {
            console.log("Launch failed:", e);
        }
    }

    function launchPinned(index) {
        const pinned = root.pinnedApps;
        if (index >= 0 && index < pinned.length) {
            launchApp(pinned[index]);
        }
    }

    // --- Favorites / recents (persisted) ----------------------------------
    // Stored ids come from entry.id; the legacy pinnedIds list (and some
    // desktop files) use the "x.desktop" file form — resolve either.
    function entryById(id) {
        if (!id) {
            return null;
        }
        var e = DesktopEntries.byId(id);
        if (e) {
            return e;
        }
        var bare = String(id).replace(/\.desktop$/, "");
        e = DesktopEntries.byId(bare);
        if (e) {
            return e;
        }
        var vals = root.allEntries;
        for (var i = 0; i < vals.length; i++) {
            if (vals[i].id === id || vals[i].id === bare) {
                return vals[i];
            }
        }
        return null;
    }

    function isFavorite(entry) {
        return !!entry && root.favoriteIds.indexOf(entry.id) !== -1;
    }

    function toggleFavorite(entry) {
        if (!entry) {
            return;
        }
        var list = root.favoriteIds.slice();
        var i = list.indexOf(entry.id);
        if (i === -1) {
            list.push(entry.id);
        } else {
            list.splice(i, 1);
        }
        root.favoriteIds = list;
        root.saveState();
        // Removing the selected app while in Favorites can leave the
        // selection past the end of the (now shorter) list — clamp after
        // the bindings have re-evaluated.
        Qt.callLater(function() {
            if (root.section === "favorites" && root.selectedIndex >= root.allApps.length) {
                root.selectedIndex = root.allApps.length > 0 ? root.allApps.length - 1 : -1;
            }
        });
    }

    function recordLaunch(entry) {
        if (!entry || !entry.id) {
            return;
        }
        var list = root.recentIds.filter(function(r) { return r.id !== entry.id; });
        list.unshift({ id: entry.id, ts: Date.now() });
        if (list.length > 30) {
            list = list.slice(0, 30);
        }
        root.recentIds = list;
        root.saveState();
    }

    // --- Typed query → command (rofi's `run` / kb-accept-custom) ---------
    // With no row to take, the field is a command line: the string goes
    // to /bin/sh through hl.dsp.exec_cmd, so pipes, globs and quoting
    // behave exactly like a terminal line. Output is not captured and
    // nothing waits on it — rofi runs custom entries the same way.
    function runQuery(query) {
        const raw = (query === undefined || query === null) ? root.searchText : query;
        const q = String(raw).trim();
        if (q === "") {
            return false;
        }
        root.recordQuery(q);
        HyprlandService.execShell(q);
        return true;
    }

    function recordQuery(q) {
        var list = root.queryHistory.filter(function (s) { return s !== q; });
        list.unshift(q);
        if (list.length > 30) {
            list = list.slice(0, 30);
        }
        root.queryHistory = list;
        root.historyCursor = -1;
        root.historyEcho = "";
        root.historyDraft = "";
        root.saveState();
    }

    // Ctrl+Up walks back to older queries, Ctrl+Down forward again, and
    // the last Ctrl+Down returns the stashed draft. Returns the text to
    // show, or null for "nothing to do" (caller leaves the field alone).
    function historyPrev() {
        if (root.queryHistory.length === 0) {
            return null;
        }
        if (root.historyCursor < 0) {
            root.historyDraft = root.searchText;
            root.historyCursor = 0;
        } else if (root.historyCursor < root.queryHistory.length - 1) {
            root.historyCursor++;
        }
        root.historyEcho = root.queryHistory[root.historyCursor];
        return root.historyEcho;
    }

    function historyNext() {
        if (root.historyCursor > 0) {
            root.historyCursor--;
            root.historyEcho = root.queryHistory[root.historyCursor];
            return root.historyEcho;
        }
        if (root.historyCursor === 0) {
            root.historyCursor = -1;
            root.historyEcho = "";
            return root.historyDraft;
        }
        return null;
    }

    // Persist favorites + recents (state dir owned by StorageService;
    // FileView reports loadFailed for a missing file → first-run seed).
    FileView {
        id: stateFile
        path: StorageService.ready ? StorageService.path("launcher.json") : ""
        printErrors: false
        onLoaded: root.parseState(stateFile.text())
        onLoadFailed: root.seedState()
    }

    function parseState(content) {
        if (typeof content !== "string" || content.trim() === "") {
            root.seedState();
            return;
        }
        try {
            var data = JSON.parse(content);
            root.favoriteIds = Array.isArray(data.favorites)
                ? data.favorites.filter(function(s) { return typeof s === "string"; })
                : [];
            root.recentIds = Array.isArray(data.recents)
                ? data.recents.filter(function(r) { return r && typeof r.id === "string"; })
                      .map(function(r) { return { id: r.id, ts: typeof r.ts === "number" ? r.ts : 0 }; })
                : [];
            root.queryHistory = Array.isArray(data.queries)
                ? data.queries.filter(function(q) { return typeof q === "string" && q !== ""; }).slice(0, 30)
                : [];
            // Migration: state written before the `seeded` stamp (or by
            // the startup-race first run) — seed pinned defaults once.
            // Afterwards the flag keeps a deliberately emptied list empty.
            if (data.seeded !== true) {
                root.seedState();
            }
        } catch (e) {
            console.warn("[voidshell] launcher.json malformed, reseeding:", e);
            root.seedState();
        }
    }

    property int seedRetries: 0

    function seedState() {
        if (root.allEntries.length === 0) {
            // .desktop files are not parsed yet — persisting now would
            // freeze an empty favorite list forever (the first-run race);
            // retry shortly instead, capped so a broken system gives up.
            if (root.seedRetries < 40) {
                root.seedRetries++;
                seedRetry.restart();
            } else {
                console.warn("[voidshell] launcher state seed gave up: no desktop entries");
            }
            return;
        }
        var favs = [];
        for (var i = 0; i < root.pinnedIds.length; i++) {
            var e = root.entryById(root.pinnedIds[i]);
            if (e && !e.noDisplay) {
                favs.push(e.id); // canonical entry.id form
            }
        }
        root.favoriteIds = favs;
        root.recentIds = [];
        root.queryHistory = [];
        root.historyCursor = -1;
        root.historyEcho = "";
        root.historyDraft = "";
        root.saveState();
    }

    Timer {
        id: seedRetry
        interval: 250
        onTriggered: root.seedState()
    }

    function saveState() {
        if (!StorageService.ready) {
            return;
        }
        stateFile.setText(JSON.stringify({
            version: 1,
            seeded: true,
            favorites: root.favoriteIds,
            recents: root.recentIds,
            queries: root.queryHistory
        }, null, 2));
    }

    // --- Terminal probe (detail panel "Open in Terminal" row) ------------
    Process {
        id: termProbe
        command: ["sh", "-c", "command -v kitty || command -v ghostty || command -v alacritty || command -v foot || command -v gnome-terminal || true"]
        stdout: StdioCollector {
            id: termOut
        }
        onExited: {
            root.terminalBin = String(termOut.text || "").trim().split("\n")[0] || "";
        }
    }

    Component.onCompleted: termProbe.running = true

    // --- Detail panel actions ---------------------------------------------
    // "Open in Terminal": the entry's own argv inside a real terminal.
    function launchInTerminal(entry) {
        if (!entry || !entry.command || !entry.command.length) {
            ToastService.push("Launcher", "This entry has no command to run", "", "warning");
            return false;
        }
        if (!root.terminalBin) {
            ToastService.push("Launcher", "No terminal installed (kitty, ghostty, alacritty, foot)", "", "warning");
            return false;
        }
        var parts = [];
        for (var i = 0; i < entry.command.length; i++) {
            parts.push(HyprlandService.shQuote(entry.command[i]));
        }
        return root.runInTerminal(parts.join(" "));
    }

    // Runs a shell snippet inside the detected terminal — real terminal,
    // real prompt; this shell never runs privileged commands itself.
    function runInTerminal(script) {
        if (!root.terminalBin) {
            return false;
        }
        var base = root.terminalBin.split("/").pop();
        var argv;
        if (base === "foot") {
            argv = [root.terminalBin, "sh", "-c", script];
        } else if (base === "gnome-terminal") {
            argv = [root.terminalBin, "--", "sh", "-c", script];
        } else {
            argv = [root.terminalBin, "-e", "sh", "-c", script];
        }
        var quoted = [];
        for (var i = 0; i < argv.length; i++) {
            quoted.push(HyprlandService.shQuote(argv[i]));
        }
        HyprlandService.execShell(quoted.join(" "));
        return true;
    }

    // "Open Location": open the XDG directory that actually holds the
    // entry's .desktop file in the default file manager; honest toasts
    // when the file or xdg-open can't be found.
    function openEntryLocation(entry) {
        if (!entry || !entry.id) {
            return;
        }
        locProc.entryName = entry.name;
        locProc.command = ["sh", "-c",
            "command -v xdg-open >/dev/null 2>&1 || exit 127; " +
            "for d in \"$HOME/.local/share/applications\" /usr/share/applications /usr/local/share/applications " +
            "/var/lib/flatpak/exports/share/applications \"$HOME/.local/share/flatpak/exports/share/applications\"; do " +
            "if [ -f \"$d/\" " + HyprlandService.shQuote(entry.id) + " ]; then " +
            "xdg-open \"$d\" >/dev/null 2>&1; exit $?; fi; done; exit 1"];
        locProc.running = true;
    }

    Process {
        id: locProc
        property string entryName: ""
        onExited: exitCode => {
            locProc.running = false;
            if (exitCode === 127) {
                ToastService.push("Launcher", "No file manager (xdg-open) found", "", "warning");
            } else if (exitCode !== 0) {
                ToastService.push("Launcher", "Desktop file for " + locProc.entryName + " not found", "", "warning");
            }
        }
    }

    // "Uninstall": resolve the owning package with a read-only
    // `pacman -Qo`, then hand the privileged confirmation to a real
    // terminal (sudo prompts there, never here). Nothing is removed when
    // the package can't be identified — an honest toast says so.
    function uninstallEntry(entry) {
        if (!entry || !entry.command || !entry.command.length) {
            ToastService.push("Launcher", "No executable to resolve a package from", "", "warning");
            return;
        }
        if (!root.terminalBin) {
            ToastService.push("Launcher", "No terminal to confirm the removal", "", "warning");
            return;
        }
        pkgProc.entryName = entry.name;
        pkgProc.command = ["sh", "-c",
            "exe=$(command -v " + HyprlandService.shQuote(entry.command[0]) + " 2>/dev/null || true); " +
            "[ -n \"$exe\" ] || exit 4; " +
            "pacman -Qo -- \"$exe\" 2>/dev/null | sed -n \"s/.* is owned by \\([^ ]*\\).*/\\1/p\" | head -n1"];
        pkgProc.running = true;
    }

    Process {
        id: pkgProc
        property string entryName: ""
        stdout: StdioCollector {
            id: pkgOut
        }
        onExited: exitCode => {
            pkgProc.running = false;
            var pkg = String(pkgOut.text || "").trim();
            if (exitCode !== 0 || pkg === "" || !/^[A-Za-z0-9@._+-]+$/.test(pkg)) {
                ToastService.push("Launcher", "No package owns " + pkgProc.entryName + " (nothing removed)", "", "warning");
                return;
            }
            if (root.runInTerminal("sudo pacman -R -- " + HyprlandService.shQuote(pkg))) {
                PopupManager.closeAll();
            }
        }
    }
}