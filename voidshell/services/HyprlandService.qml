pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

// VOID SHELL — Hyprland state bridge (PRD 34.1): active workspace,
// workspace list, focused client, monitors and window focus actions.
// Fully event-driven: quickshell consumes Hyprland's event socket and the
// wayland toplevel-management protocol, so this service never polls.
//
// NOTE (Hyprland 0.56 / Lua IPC): dispatch requests are Lua expressions.
// The installed build accepts `hl.dsp.focus({ workspace = N })` and window
// selectors of the form `address:0x...`. Dispatcher tables (`hl.dsp.*`)
// only execute when passed through `hyprctl dispatch` (Quickshell's
// `Hyprland.dispatch`); `hyprctl eval` evaluates Lua but never commits
// them, so every effect here goes through `dispatch`.
Singleton {
    id: root

    readonly property bool ready: Hyprland.monitors.values.length > 0

    readonly property var workspaces: Hyprland.workspaces.values
    readonly property var monitors: Hyprland.monitors.values
    readonly property var focusedWorkspace: Hyprland.focusedWorkspace
    readonly property var focusedMonitor: Hyprland.focusedMonitor
    readonly property var focusedToplevel: ToplevelManager.activeToplevel

    // Focused client (PRD 12.2). Empty strings mean "no focused client",
    // which the bar renders as the neutral `Desktop` label.
    readonly property string focusedTitle: root.focusedToplevel ? root.focusedToplevel.title : ""
    readonly property string focusedAppId: root.focusedToplevel ? root.focusedToplevel.appId : ""
    readonly property bool onDesktop: !root.focusedToplevel

    readonly property string focusedWorkspaceName: root.focusedWorkspace ? root.focusedWorkspace.name : ""

    // Numeric workspaces ascending. Named/special workspaces carry
    // negative ids and never appear in the 1..N strip.
    readonly property var numericWorkspaces: {
        const list = root.workspaces;
        const out = [];
        if (!list) {
            return out;
        }
        for (let i = 0; i < list.length; i++) {
            if (list[i].id > 0) {
                out.push(list[i]);
            }
        }
        out.sort((a, b) => a.id - b.id);
        return out;
    }

    // Every Hyprland IPC event bumps this counter. `workspace.toplevels`
    // is exposed as a plain list with no change signal, so views that show
    // per-workspace window counts re-read it whenever the stream ticks
    // (window open/close/move, workspace changes, title updates).
    property int eventSerial: 0

    // --- Living State Island hook (Shadow Spaces plan §18, Phase F) ------
    // The clock island is the only surface meant to announce a workspace
    // switch, and only when `islandAnnouncements` says so (default: on).
    // This is the *hook*, not the UI: it publishes the event as
    // `announcement` + `announcementSerial`, event-driven off the same
    // focused-workspace change everything else watches. ClockPill renders
    // it (the workspace dwell) and IslandProviders re-publishes it into
    // the announcement engine; both keep their own gate, so switching the
    // setting off silences every consumer at once.
    property string announcement: ""
    property int announcementSerial: 0
    property var announcedWorkspace: null

    function publishAnnouncement() {
        const ws = root.focusedWorkspace;
        const previous = root.announcedWorkspace;
        root.announcedWorkspace = ws;
        // The first observation is startup state, not a switch; while the
        // setting is off we still track it so enabling later never
        // announces a switch that already happened.
        if (!ManagerSettings.islandAnnouncements || ws === null || previous === null || previous.id === ws.id) {
            return;
        }
        root.announcement = String(ws.name);
        root.announcementSerial = root.announcementSerial + 1;
        console.log("[voidshell] island hook: workspace announcement " + root.announcement);
    }

    onFocusedWorkspaceChanged: root.publishAnnouncement()

    Connections {
        target: Hyprland
        function onRawEvent() {
            root.eventSerial = root.eventSerial + 1;
            // Every compositor event is also a confirmation opportunity:
            // pending focus/move requests are re-checked against real
            // state here instead of waiting for their deadline.
            root.checkPendingActions();
        }
    }

    // PRD 12.1 — urgent workspaces may flag without changing layout.
    readonly property int urgentCount: {
        const list = root.workspaces;
        if (!list) {
            return 0;
        }
        let n = 0;
        for (let i = 0; i < list.length; i++) {
            if (list[i].urgent) {
                n++;
            }
        }
        return n;
    }

    // Real window count of one workspace (dash chips, overview cards).
    // Hyprland's own IPC record carries the count, so it is read from
    // there first; the toplevel list is the fallback before the first
    // event of this session arrives. Never rounded, never cached across
    // events — callers re-read it whenever eventSerial ticks.
    function windowCountOf(workspace) {
        if (!workspace) {
            return 0;
        }
        const ipc = workspace.lastIpcObject;
        if (ipc && typeof ipc.windows === "number" && isFinite(ipc.windows) && ipc.windows >= 0) {
            return ipc.windows;
        }
        return root.windowsOf(workspace).length;
    }

    // Windows of one workspace (workspace overview previews).
    function windowsOf(workspace) {
        if (!workspace || !workspace.toplevels) {
            return [];
        }
        const list = workspace.toplevels.values;
        return list ? list : [];
    }

    // Best-effort "is this desktop entry running" (launcher tile dot): a
    // toplevel whose wayland app_id matches the entry's desktop id or
    // startup class after normalization. Substring matches need 4+
    // characters so short ids ("sh", "qt") can't light up unrelated
    // tiles. A miss shows no dot — it never claims a closed app is open.
    function isAppRunning(entry) {
        if (!entry) {
            return false;
        }
        const id = String(entry.id || "").toLowerCase().replace(/\.desktop$/, "");
        const sc = String(entry.startupClass || "").toLowerCase();
        const vals = ToplevelManager.toplevels.values;
        if (!vals) {
            return false;
        }
        for (let i = 0; i < vals.length; i++) {
            const a = String(vals[i].appId || "").toLowerCase();
            if (a === "") {
                continue;
            }
            if (id !== "" && (id === a || (id.length >= 4 && a.length >= 4 && (id.indexOf(a) !== -1 || a.indexOf(id) !== -1)))) {
                return true;
            }
            if (sc !== "" && (sc === a || (sc.length >= 4 && a.length >= 4 && (sc.indexOf(a) !== -1 || a.indexOf(sc) !== -1)))) {
                return true;
            }
        }
        return false;
    }

    function workspaceById(id) {
        const list = root.workspaces;
        if (!list) {
            return null;
        }
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === id) {
                return list[i];
            }
        }
        return null;
    }

    function isUrgent(name) {
        const ws = root.workspaceByName(String(name));
        return ws !== null && ws.urgent;
    }

    function workspaceByName(name) {
        const list = root.workspaces;
        if (!list) {
            return null;
        }
        const target = String(name);
        for (let i = 0; i < list.length; i++) {
            if (list[i].name === target) {
                return list[i];
            }
        }
        return null;
    }

    // Focus a workspace through the Lua dispatcher. Numeric ids are
    // passed raw; named workspaces are quoted and charset-checked so a
    // name can never break out of the Lua literal (plan §3 — named and
    // non-consecutive ids are first-class).
    function goToWorkspace(name) {
        const target = String(name);
        if (/^\d+$/.test(target)) {
            return root.dispatchLua("hl.dsp.focus({ workspace = " + target + " })");
        }
        if (/^[A-Za-z0-9_:.\-]+$/.test(target)) {
            return root.dispatchLua("hl.dsp.focus({ workspace = \"" + target + "\" })");
        }
        root.actionFailed("focus", "unsupported workspace selector");
        return false;
    }

    function goToPreviousWorkspace() {
        Hyprland.dispatch('hl.dsp.focus({ workspace = "previous" })');
    }

    // Step through the existing numeric workspaces by id, wrapping at both
    // ends. Used by wheel scroll on the bar strip and by keybinds; computes
    // the target itself because the Lua build has no verified "next"
    // workspace selector.
    function goToRelativeWorkspace(step) {
        const list = root.numericWorkspaces;
        if (!list.length) {
            return;
        }
        const ids = [];
        for (let i = 0; i < list.length; i++) {
            ids.push(list[i].id);
        }
        const currentId = root.focusedWorkspace ? root.focusedWorkspace.id : ids[0];
        let idx = ids.indexOf(currentId);
        if (idx === -1) {
            idx = 0;
        }
        const next = ((idx + step) % ids.length + ids.length) % ids.length;
        Hyprland.dispatch("hl.dsp.focus({ workspace = " + ids[next] + " })");
    }

    // Focus a specific window by address (workspace overview previews).
    // Quickshell reports addresses without the `0x` prefix Hyprland's
    // window selector expects, so normalise before dispatching.
    function focusAddress(address) {
        if (!address) {
            return;
        }
        const raw = String(address);
        const selector = raw.indexOf("0x") === 0 ? raw : "0x" + raw;
        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + selector + '" })');
    }

    function focusToplevel(toplevel) {
        if (!toplevel) {
            return;
        }
        root.focusAddress(toplevel.address);
    }

    // =====================================================================
    // SHADOW SPACES — shared desktop-manager model (plan §3, §10)
    // =====================================================================

    // --- eligibility ----------------------------------------------------
    // Special/scratchpad workspaces are excluded by their real metadata:
    // Hyprland names them `special` or `special:<name>`. Never a sign test
    // on the id — non-consecutive and named ids are legal workspaces and
    // must survive the filter.
    function isSpecialWorkspace(ws) {
        if (!ws) {
            return false;
        }
        const n = String(ws.name);
        return n === "special" || n.indexOf("special:") === 0;
    }

    // Owning monitor of a workspace, read from its IPC metadata (the
    // `monitor` object also exists, but `lastIpcObject.monitor` is the
    // plain name string verified against hyprctl on this build).
    function monitorNameOf(ws) {
        const ipc = ws ? ws.lastIpcObject : null;
        return ipc && ipc.monitor !== undefined && ipc.monitor !== null ? String(ipc.monitor) : "";
    }

    // Workspaces owned by one monitor ("" = every monitor), specials
    // excluded, ordered by id — the order never follows focus history, so
    // switching windows can never reshuffle the list (plan §3).
    function workspacesForMonitor(monitorName) {
        const list = root.workspaces;
        const out = [];
        if (!list) {
            return out;
        }
        const scope = monitorName === undefined || monitorName === null ? "" : String(monitorName);
        for (let i = 0; i < list.length; i++) {
            const ws = list[i];
            if (root.isSpecialWorkspace(ws)) {
                continue;
            }
            if (scope !== "" && root.monitorNameOf(ws) !== scope) {
                continue;
            }
            out.push(ws);
        }
        out.sort((a, b) => a.id - b.id);
        return out;
    }

    // Scope from settings: "monitor" follows the focused monitor (the
    // focused workspace always lives on it), "all" lists every
    // non-special workspace — view-only, it never drags a remote
    // workspace onto this monitor (plan §11).
    readonly property var eligibleWorkspaces: {
        ManagerSettings.scope;
        const focused = root.focusedWorkspace;
        const scope = ManagerSettings.scope === "all" ? "" : root.monitorNameOf(focused);
        return root.workspacesForMonitor(scope);
    }

    // --- windows --------------------------------------------------------
    // Windows of a workspace in last-focus order (plan §3): the compositor
    // already records which window of that workspace was focused last
    // (`lastwindow`) and how recently each window was focused
    // (`focusHistoryID`, 0 = most recent), so the order is read from real
    // state instead of a shell-side cache that could drift. `toplevels`
    // exposes no change signal, so callers depend on eventSerial the same
    // way every other list view in the shell does.
    function normalizeAddress(address) {
        const raw = String(address === undefined || address === null ? "" : address);
        if (raw === "") {
            return "";
        }
        return raw.indexOf("0x") === 0 ? raw.slice(2) : raw;
    }

    function focusRank(t) {
        const ipc = t ? t.lastIpcObject : null;
        if (ipc && typeof ipc.focusHistoryID === "number") {
            return ipc.focusHistoryID;
        }
        return Number.MAX_SAFE_INTEGER;
    }

    function orderedWindows(workspace) {
        const list = root.windowsOf(workspace);
        if (list.length < 2) {
            return list;
        }
        const ipc = workspace ? workspace.lastIpcObject : null;
        const front = ipc && ipc.lastwindow !== undefined ? root.normalizeAddress(ipc.lastwindow) : "";
        const out = list.slice();
        out.sort((a, b) => {
            const aFront = front !== "" && root.normalizeAddress(a.address) === front;
            const bFront = front !== "" && root.normalizeAddress(b.address) === front;
            if (aFront !== bFront) {
                return aFront ? -1 : 1;
            }
            return root.focusRank(a) - root.focusRank(b);
        });
        return out;
    }

    function windowByAddress(address) {
        const want = root.normalizeAddress(address);
        if (want === "") {
            return null;
        }
        const list = root.workspaces;
        if (!list) {
            return null;
        }
        for (let i = 0; i < list.length; i++) {
            const tl = root.windowsOf(list[i]);
            for (let j = 0; j < tl.length; j++) {
                if (root.normalizeAddress(tl[j].address) === want) {
                    return tl[j];
                }
            }
        }
        return null;
    }

    function workspaceOfWindow(address) {
        const want = root.normalizeAddress(address);
        if (want === "") {
            return null;
        }
        const list = root.workspaces;
        if (!list) {
            return null;
        }
        for (let i = 0; i < list.length; i++) {
            const tl = root.windowsOf(list[i]);
            for (let j = 0; j < tl.length; j++) {
                if (root.normalizeAddress(tl[j].address) === want) {
                    return list[i];
                }
            }
        }
        return null;
    }

    function windowClass(toplevel) {
        const ipc = toplevel ? toplevel.lastIpcObject : null;
        return ipc && ipc.class !== undefined ? String(ipc.class) : "";
    }

    function isSensitiveWindow(toplevel) {
        const cls = root.windowClass(toplevel);
        if (cls === "") {
            return false;
        }
        const list = ManagerSettings.sensitiveExclusions;
        for (let i = 0; i < list.length; i++) {
            if (String(list[i]).toLowerCase() === cls.toLowerCase()) {
                return true;
            }
        }
        return false;
    }

    // --- preview geometry & identity (Shadow Spaces plan §5) ------------
    // Real window proportions for previews: Hyprland's own geometry
    // record ([w, h]) decides the shape, so a 16:9 window never gets
    // stretched into a card. The 16:10 fallback is used only until the
    // IPC record arrives for a freshly opened window.
    function windowAspect(toplevel) {
        const ipc = toplevel ? toplevel.lastIpcObject : null;
        const size = ipc && ipc.size && ipc.size.length === 2 ? ipc.size : null;
        const w = size ? Number(size[0]) : NaN;
        const h = size ? Number(size[1]) : NaN;
        if (isFinite(w) && isFinite(h) && w > 0 && h > 0) {
            return w / h;
        }
        return 16 / 10;
    }

    // Largest rect of that aspect fitting the given box.
    function fitWindow(toplevel, boxW, boxH) {
        const a = root.windowAspect(toplevel);
        let w = boxW;
        let h = boxW / a;
        if (h > boxH) {
            h = boxH;
            w = boxH * a;
        }
        return { width: Math.max(1, Math.round(w)), height: Math.max(1, Math.round(h)) };
    }

    // Desktop-entry icon for a window (preview fallback plate), the same
    // heuristic → exact-id → nothing chain the active-app pill uses.
    function iconUrlForWindow(toplevel) {
        const cls = root.windowClass(toplevel);
        if (cls === "") {
            return "";
        }
        try {
            const byHeuristic = DesktopEntries.heuristicLookup(cls);
            if (byHeuristic && byHeuristic.icon !== "") {
                return Quickshell.iconPath(byHeuristic.icon, "");
            }
            const byId = DesktopEntries.byId(cls);
            if (byId && byId.icon !== "") {
                return Quickshell.iconPath(byId.icon, "");
            }
        } catch (e) {
            // Unknown class — the initial below still identifies it.
        }
        return "";
    }

    // First class letter, shown when no desktop entry provides an icon.
    function initialForWindow(toplevel) {
        const cls = root.windowClass(toplevel);
        return cls !== "" ? cls.charAt(0).toUpperCase() : "";
    }

    function titleForWindow(toplevel) {
        const ipc = toplevel ? toplevel.lastIpcObject : null;
        if (ipc && ipc.title !== undefined && ipc.title !== null) {
            return String(ipc.title);
        }
        return toplevel ? String(toplevel.title) : "";
    }

    // --- operations with bounded confirmation (plan §10) ----------------
    // Requests are dispatched through the Lua IPC (verified syntax) and
    // then *observed*: completion means the compositor reports the new
    // state on its event stream, never "the request was sent". A request
    // that is still unconfirmed at the deadline fails loudly and
    // non-destructively — the model is never told a move succeeded.
    property var pendingActions: []
    signal actionFailed(string kind, string detail)

    function dispatchLua(expr) {
        try {
            Hyprland.dispatch(expr);
            return true;
        } catch (e) {
            console.warn("[voidshell] dispatch failed:", expr, String(e));
            root.actionFailed("dispatch", String(e));
            return false;
        }
    }

    function trackAction(kind, address, target, timeoutMs) {
        const list = root.pendingActions.slice();
        list.push({
            kind: kind,
            address: root.normalizeAddress(address),
            target: target,
            expires: Date.now() + timeoutMs
        });
        root.pendingActions = list;
        confirmTimer.restart();
    }

    function resolveAction(action) {
        if (action.kind === "move") {
            const ws = root.workspaceOfWindow(action.address);
            if (ws === null) {
                // The window disappeared before confirmation: that is a
                // failure to report, never a success to celebrate.
                return "gone";
            }
            return ws.id === action.target ? "done" : "pending";
        }
        if (action.kind === "focus") {
            const ws = root.focusedWorkspace;
            const ipc = ws ? ws.lastIpcObject : null;
            const focusedAddr = ipc && ipc.lastwindow !== undefined ? root.normalizeAddress(ipc.lastwindow) : "";
            if (action.address !== "") {
                if (focusedAddr === action.address) {
                    return "done";
                }
                // No address reported by the compositor yet: accept the
                // weaker workspace-level confirmation rather than fail a
                // focus that actually landed.
                if (focusedAddr === "") {
                    const cur = root.workspaceOfWindow(action.address);
                    if (cur !== null && ws !== null && cur.id === ws.id) {
                        return "done";
                    }
                }
                return "pending";
            }
            return "done";
        }
        return "done";
    }

    function checkPendingActions() {
        if (root.pendingActions.length === 0) {
            return;
        }
        const now = Date.now();
        const keep = [];
        for (let i = 0; i < root.pendingActions.length; i++) {
            const action = root.pendingActions[i];
            const state = root.resolveAction(action);
            if (state === "done") {
                continue;
            }
            if (state === "gone") {
                root.actionFailed(action.kind, "window closed before the compositor confirmed it");
                continue;
            }
            if (now >= action.expires) {
                root.actionFailed(action.kind, action.kind === "move" ? "workspace move not confirmed by the compositor" : "focus change not confirmed by the compositor");
                continue;
            }
            keep.push(action);
        }
        root.pendingActions = keep;
        if (keep.length === 0) {
            confirmTimer.stop();
        }
    }

    Timer {
        id: confirmTimer
        interval: 120
        repeat: true
        running: root.pendingActions.length > 0
        onTriggered: root.checkPendingActions()
    }

    // Activate a workspace: prefers the workspace object's own handle,
    // falls back to a validated Lua selector (numeric id, or a named
    // workspace whose name cannot break out of the literal).
    function activateWorkspace(target) {
        if (!target) {
            return false;
        }
        if (typeof target === "object") {
            if (typeof target.activate === "function") {
                target.activate();
                return true;
            }
            return root.goToWorkspace(String(target.name));
        }
        return root.goToWorkspace(String(target));
    }

    // Focus an exact window by address: validates existence first so a
    // stale preview can never retarget focus at a dead address.
    function activateWindow(address) {
        const addr = root.normalizeAddress(address);
        if (addr === "") {
            root.actionFailed("focus", "empty window address");
            return false;
        }
        if (root.windowByAddress(addr) === null) {
            root.actionFailed("focus", "window no longer exists");
            return false;
        }
        root.focusAddress(addr);
        const ws = root.workspaceOfWindow(addr);
        root.trackAction("focus", addr, ws ? ws.id : 0, 700);
        return true;
    }

    // Move one exact window to a workspace. `follow = false` is the
    // silent variant (verified against the installed compositor:
    // `hl.dsp.window.move({ workspace, follow = false, window })`) — the
    // current workspace never changes as a side effect of a move.
    function moveWindow(address, workspaceId, follow) {
        const addr = root.normalizeAddress(address);
        const target = Number(workspaceId);
        if (addr === "" || !isFinite(target)) {
            root.actionFailed("move", "invalid move arguments");
            return false;
        }
        if (root.windowByAddress(addr) === null) {
            root.actionFailed("move", "window no longer exists");
            return false;
        }
        const ws = root.workspaceById(target);
        if (ws === null) {
            root.actionFailed("move", "target workspace does not exist");
            return false;
        }
        const current = root.workspaceOfWindow(addr);
        if (current !== null && current.id === ws.id) {
            // Same-workspace drop is a no-op (plan §8).
            return true;
        }
        const expr = "hl.dsp.window.move({ workspace = " + target + ", follow = " + (follow === true) + ", window = \"address:0x" + addr + "\" })";
        if (!root.dispatchLua(expr)) {
            return false;
        }
        root.trackAction("move", addr, ws.id, 900);
        return true;
    }

    // --- Shell execution helpers (Lua IPC) -------------------------------
    // `hl.dsp.exec_cmd(...)` runs its argument through /bin/sh, so callers
    // build plain shell strings; luaQuote keeps the Lua literal valid.
    function luaQuote(value) {
        return '"' + String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
    }

    function shQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'";
    }

    // Fire-and-forget shell command (launcher openers, plugin actions).
    function execShell(command) {
        if (!command) {
            return;
        }
        Hyprland.dispatch("hl.dsp.exec_cmd(" + root.luaQuote(command) + ")");
    }
}
