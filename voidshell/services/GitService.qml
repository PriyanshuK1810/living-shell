pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — git repository index (PRD §28) backing the `@git` launcher
// plugin. Repositories are found under configured roots (a JSON list in
// the state directory, or sensible defaults) and cached on disk, so the
// plugin never rescans on keystrokes. Per-repository status is a single
// batched `git status --porcelain` pass run on open/refresh, never per
// row. Missing git or empty results are reported honestly.
Singleton {
    id: root

    // [{ path, name, status, checkedAt }] — status: clean | dirty | unknown
    property var repos: []
    property bool loaded: false
    property bool scanning: false
    property bool checking: false
    property bool gitAvailable: false
    property bool folderAvailable: false
    property bool terminalAvailable: false
    property string lastError: ""
    property double scannedAt: 0

    readonly property bool busy: root.scanning || root.checking
    readonly property int cleanCount: root.countWhere("clean")
    readonly property int dirtyCount: root.countWhere("dirty")

    // Set once ensureLoaded() runs: the pending flag makes the cache
    // FileView decide between "use cache" and "no cache, scan now".
    property bool pending: false

    readonly property var defaultRoots: {
        const home = StorageService.home;
        return [home + "/Projects", home + "/projects", home + "/dev", home + "/src", home + "/code", home + "/dotfiles", home];
    }

    // Configured roots from git-roots.json (array of absolute or ~ paths).
    property var configuredRoots: []

    readonly property var roots: {
        const raw = root.configuredRoots.length > 0 ? root.configuredRoots : root.defaultRoots;
        const out = [];
        for (let i = 0; i < raw.length; i++) {
            let p = String(raw[i]);
            if (p === "~") {
                p = StorageService.home;
            } else if (p.startsWith("~/")) {
                p = StorageService.home + p.slice(1);
            }
            if (p !== "" && out.indexOf(p) === -1) {
                out.push(p);
            }
        }
        return out;
    }

    function countWhere(status) {
        let n = 0;
        for (let i = 0; i < root.repos.length; i++) {
            if (root.repos[i].status === status) {
                n++;
            }
        }
        return n;
    }

    // --- Persistence ----------------------------------------------------
    FileView {
        id: rootsFile
        path: StorageService.ready ? StorageService.path("git-roots.json") : ""
        printErrors: false
        onLoaded: root.parseRoots(rootsFile.text())
    }

    FileView {
        id: indexFile
        path: StorageService.ready ? StorageService.path("git-index.json") : ""
        printErrors: false
        onLoaded: root.parseIndex(indexFile.text())
    }

    function parseRoots(content) {
        if (!content || content.trim() === "") {
            return;
        }
        try {
            const data = JSON.parse(content);
            const list = Array.isArray(data) ? data : (Array.isArray(data.roots) ? data.roots : []);
            const clean = [];
            for (let i = 0; i < list.length; i++) {
                if (typeof list[i] === "string" && list[i] !== "") {
                    clean.push(list[i]);
                }
            }
            root.configuredRoots = clean;
        } catch (e) {
            console.warn("[voidshell] git-roots.json malformed, using defaults:", e);
        }
    }

    function parseIndex(content) {
        if (!content || content.trim() === "") {
            // No cache yet: if someone is waiting, fall back to a scan.
            if (root.pending) {
                root.pending = false;
                root.refresh();
            }
            return;
        }
        try {
            const data = JSON.parse(content);
            const list = Array.isArray(data.repos) ? data.repos : [];
            const clean = [];
            for (let i = 0; i < list.length; i++) {
                const item = list[i];
                if (item && typeof item.path === "string" && item.path !== "") {
                    clean.push({
                        path: item.path,
                        name: root.baseName(item.path),
                        status: item.status === "clean" || item.status === "dirty" ? item.status : "unknown",
                        checkedAt: typeof item.checkedAt === "number" ? item.checkedAt : 0
                    });
                }
            }
            root.repos = clean;
            root.scannedAt = typeof data.scannedAt === "number" ? data.scannedAt : 0;
            root.loaded = true;
            if (root.pending) {
                root.pending = false;
                // Refresh status dots if the cached ones are stale, but show
                // the cached index immediately either way.
                if (root.scannedAt === 0 || Date.now() - root.scannedAt > 300000) {
                    root.refreshStatuses();
                }
            }
        } catch (e) {
            console.warn("[voidshell] git-index.json malformed, rescanning:", e);
            if (root.pending) {
                root.pending = false;
                root.refresh();
            }
        }
    }

    function save() {
        if (!StorageService.ready || indexFile.path === "") {
            return;
        }
        indexFile.setText(JSON.stringify({
            scannedAt: root.scannedAt,
            repos: root.repos
        }, null, 2));
    }

    function baseName(path) {
        const parts = String(path).split("/");
        return parts[parts.length - 1] || String(path);
    }

    // --- Public API -----------------------------------------------------
    // Called when the plugin opens: serve the cache first, scan only when
    // there has never been one.
    function ensureLoaded() {
        if (root.loaded || root.scanning || root.checking) {
            return;
        }
        root.pending = true;
        cacheWait.restart();
    }

    // Full rescan: find .git dirs under the roots, then check statuses.
    function refresh() {
        if (root.scanning || root.checking) {
            return;
        }
        root.lastError = "";
        root.scanning = true;
        const quoted = [];
        for (let i = 0; i < root.roots.length; i++) {
            quoted.push(HyprlandService.shQuote(root.roots[i]));
        }
        scanProc.command = ["sh", "-c", "for d in " + quoted.join(" ") + "; do [ -e \"$d\" ] && find -L \"$d\" -maxdepth 4 \\( -name node_modules -o -name .cache -o -name .local \\) -prune -o \\( -name .git -prune -print \\) 2>/dev/null; done | head -80"];
        scanProc.running = true;
    }

    // Status-only pass over the current index (cheap, no filesystem walk).
    function refreshStatuses() {
        if (root.checking || root.repos.length === 0) {
            return;
        }
        root.checking = true;
        let script = "";
        for (let i = 0; i < root.repos.length; i++) {
            const q = HyprlandService.shQuote(root.repos[i].path);
            script += "r=" + q + "; out=$(git -C \"$r\" status --porcelain -uno 2>/dev/null); rc=$?; ";
            script += "if [ $rc -ne 0 ]; then echo \"$r|unknown\"; elif [ -n \"$out\" ]; then echo \"$r|dirty\"; else echo \"$r|clean\"; fi; ";
        }
        statusProc.command = ["sh", "-c", script];
        statusProc.running = true;
    }

    // Plugin-side filter: substring match on name or path.
    function search(query) {
        const q = String(query || "").trim().toLowerCase();
        if (q === "") {
            return root.repos;
        }
        const out = [];
        for (let i = 0; i < root.repos.length; i++) {
            const r = root.repos[i];
            if (r.name.toLowerCase().indexOf(q) !== -1 || r.path.toLowerCase().indexOf(q) !== -1) {
                out.push(r);
            }
        }
        return out;
    }

    // --- Detection ------------------------------------------------------
    Process {
        id: detectGit
        command: ["sh", "-c", "command -v git >/dev/null 2>&1"]
        running: true
        onExited: exitCode => root.gitAvailable = exitCode === 0
    }

    // Opener availability for the plugin's row actions: an action button
    // only exists when its backend does (PRD §37).
    Process {
        id: detectOpeners
        command: ["sh", "-c", "command -v xdg-open >/dev/null 2>&1; a=$?; command -v kitty >/dev/null 2>&1; b=$?; echo \"$a $b\""]
        running: true
        stdout: StdioCollector {
            id: openersOut
        }
        onExited: exitCode => {
            const parts = String(openersOut.text || "").trim().split(/\s+/);
            root.folderAvailable = parts[0] === "0";
            root.terminalAvailable = parts[1] === "0";
        }
    }

    Timer {
        id: cacheWait
        interval: 500
        onTriggered: {
            if (!root.loaded) {
                root.pending = false;
                root.refresh();
            }
        }
    }

    // --- Scan (find) ----------------------------------------------------
    Process {
        id: scanProc
        stdout: StdioCollector {
            id: scanOut
        }
        onExited: exitCode => {
            root.scanning = false;
            if (exitCode !== 0) {
                root.lastError = "Repository scan failed";
            }
            const lines = String(scanOut.text || "").split("\n");
            const seen = {};
            const paths = [];
            for (let i = 0; i < lines.length; i++) {
                let line = lines[i].trim();
                if (line === "") {
                    continue;
                }
                if (line.endsWith("/.git")) {
                    line = line.slice(0, -5);
                } else if (line === ".git") {
                    continue;
                } else if (line.endsWith(".git")) {
                    // gitfile (worktree/submodule): keep the containing dir.
                    line = line.slice(0, -4);
                }
                if (line !== "" && !seen[line]) {
                    seen[line] = true;
                    paths.push(line);
                }
            }
            paths.sort((a, b) => root.baseName(a).localeCompare(root.baseName(b)));
            const now = Date.now();
            const prev = {};
            for (let i = 0; i < root.repos.length; i++) {
                prev[root.repos[i].path] = root.repos[i];
            }
            const repos = [];
            for (let i = 0; i < paths.length; i++) {
                const old = prev[paths[i]];
                repos.push({
                    path: paths[i],
                    name: root.baseName(paths[i]),
                    status: old ? old.status : "unknown",
                    checkedAt: old ? old.checkedAt : 0
                });
            }
            root.repos = repos;
            root.scannedAt = now;
            root.loaded = true;
            root.save();
            root.refreshStatuses();
        }
    }

    // --- Status batch ---------------------------------------------------
    Process {
        id: statusProc
        stdout: StdioCollector {
            id: statusOut
        }
        onExited: exitCode => {
            root.checking = false;
            if (exitCode !== 0) {
                root.lastError = "Status check failed";
                return;
            }
            const lines = String(statusOut.text || "").split("\n");
            const map = {};
            const now = Date.now();
            for (let i = 0; i < lines.length; i++) {
                const idx = lines[i].lastIndexOf("|");
                if (idx <= 0) {
                    continue;
                }
                map[lines[i].slice(0, idx)] = lines[i].slice(idx + 1);
            }
            const repos = [];
            for (let i = 0; i < root.repos.length; i++) {
                const r = root.repos[i];
                const status = map[r.path];
                repos.push({
                    path: r.path,
                    name: r.name,
                    status: status === "clean" || status === "dirty" ? status : "unknown",
                    checkedAt: now
                });
            }
            root.repos = repos;
            root.save();
        }
    }
}
