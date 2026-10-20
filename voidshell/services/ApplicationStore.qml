pragma Singleton

import Quickshell
import QtQuick

// VOID SHELL — ApplicationStore (Workbench plan §architecture).
//
// The Workbench dock's model: which slots exist, in which order, and
// what state each one is in. One facade over the two services that
// already own this data — no second window model:
//
//   pins    → LauncherModel's favorites (real DesktopEntry ids from
//             launcher.json; a profile with no favorites falls back to
//             the launcher's documented pinned list), reordered by
//             WorkbenchSettings.dockOrder after a drag.
//   groups  → every toplevel on every workspace, keyed by app. The key
//             is the desktop-entry id when a real entry matches the
//             window (exact app_id first, then the same heuristic the
//             launcher's running-dot uses), else `class:<class>`. The
//             window *title* is never used to infer an app.
//   order   → pinned slots first (favorites order), then running apps
//             that are not pinned, in MRU order (the compositor's own
//             focus history — a shell-side cache could only drift).
//
// Every slot is a plain JS snapshot rebuilt off HyprlandService.eventSerial:
// { key, entry, name, icon, pinned, windows[], count, here, elsewhere,
//   urgent, focused } — `here` = windows on the focused workspace,
//   `elsewhere` = windows on any other workspace (specials included:
//   a window in the scratchpad is running, not closed).
Singleton {
    id: root

    // --- pins (favorites → desktop entries, drag order applied) ---------
    readonly property var pins: {
        LauncherModel.favoriteIds;
        LauncherModel.pinnedIds;
        WorkbenchSettings.dockOrder;
        const ids = LauncherModel.favoriteIds.length > 0 ? LauncherModel.favoriteIds : LauncherModel.pinnedIds;
        const out = [];
        for (let i = 0; i < ids.length; i++) {
            const e = LauncherModel.entryById(ids[i]);
            if (e !== null && e !== undefined && !e.noDisplay && e.name) {
                out.push(e);
            }
        }
        return root.applyOrder(out);
    }

    // WorkbenchSettings.dockOrder is the persisted drag result; ids
    // that no longer resolve are dropped, and anything not mentioned
    // (a freshly favorited app) keeps its relative order at the end.
    function applyOrder(entries) {
        const order = WorkbenchSettings.dockOrder;
        if (order.length === 0) {
            return entries;
        }
        const keyed = {};
        for (let i = 0; i < entries.length; i++) {
            keyed[String(entries[i].id)] = entries[i];
        }
        const out = [];
        for (let j = 0; j < order.length; j++) {
            const k = String(order[j]);
            if (keyed[k] !== undefined) {
                out.push(keyed[k]);
                delete keyed[k];
            }
        }
        for (let m = 0; m < entries.length; m++) {
            const k2 = String(entries[m].id);
            if (keyed[k2] !== undefined) {
                out.push(keyed[k2]);
            }
        }
        return out;
    }

    // --- window → app key ------------------------------------------------
    function keyForWindow(t) {
        if (t === null || t === undefined) {
            return "";
        }
        const appId = t.appId !== undefined && t.appId !== null ? String(t.appId) : "";
        if (appId !== "") {
            try {
                const exact = DesktopEntries.byId(appId);
                if (exact !== null && exact !== undefined) {
                    return String(exact.id);
                }
            } catch (e) {
                // Fall through to the class-based lookup below.
            }
        }
        const cls = HyprlandService.windowClass(t);
        if (cls === "") {
            return "";
        }
        try {
            const h = DesktopEntries.heuristicLookup(cls);
            if (h !== null && h !== undefined) {
                return String(h.id);
            }
            const b = DesktopEntries.byId(cls);
            if (b !== null && b !== undefined) {
                return String(b.id);
            }
        } catch (e) {
            // No desktop entry for this class: group under the class
            // itself rather than inventing an app name.
        }
        return "class:" + cls.toLowerCase();
    }

    // --- groups: every window, keyed by app, MRU inside each group -------
    readonly property var groups: {
        DesktopNavigationStore.serial;
        DesktopNavigationStore.focusedWorkspace;
        const focusId = DesktopNavigationStore.focusedWorkspace !== null
            && DesktopNavigationStore.focusedWorkspace !== undefined
            ? DesktopNavigationStore.focusedWorkspace.id : -1;
        const map = {};
        const list = DesktopNavigationStore.workspaces;
        for (let i = 0; i < list.length; i++) {
            const ws = list[i];
            const tl = HyprlandService.windowsOf(ws);
            for (let j = 0; j < tl.length; j++) {
                const t = tl[j];
                const key = root.keyForWindow(t);
                if (key === "") {
                    continue;
                }
                let g = map[key];
                if (g === undefined) {
                    g = { key: key, windows: [], here: 0, elsewhere: 0, urgent: false, best: Number.MAX_SAFE_INTEGER };
                    map[key] = g;
                }
                g.windows.push(t);
                if (ws.id === focusId) {
                    g.here = g.here + 1;
                } else {
                    g.elsewhere = g.elsewhere + 1;
                }
                if (ws.urgent === true) {
                    g.urgent = true;
                }
                const rank = HyprlandService.focusRank(t);
                if (rank < g.best) {
                    g.best = rank;
                }
            }
        }
        for (const k in map) {
            map[k].windows.sort((a, b) => HyprlandService.focusRank(a) - HyprlandService.focusRank(b));
        }
        return map;
    }

    // --- slots: the dock's row ------------------------------------------
    // Pinned first (favorites order, drag order applied), then every
    // running app that is not pinned, in MRU order.
    //
    // Identity-stable: the bindings above recompute on *every* Hyprland
    // event (eventSerial ticks on rawEvent — window titles, focus,
    // layer map/unmap including the dock's own), which used to publish
    // a fresh array each time and churn every consumer of `slots`. A
    // recomputation whose content is deep-equal now returns the
    // *previous* array instance, so the notify never fires and the row
    // is left untouched; only a real change — window opened/closed,
    // focus, urgency, order — produces a new array. The cache slot is
    // mutated in place, so reading it here adds no reactive dependency
    // (no binding loop).
    readonly property var _slotCache: ({ value: null })

    readonly property var slots: {
        root.pins;
        root.groups;
        DesktopNavigationStore.activeAddress;
        const out = [];
        const pinnedKeys = {};
        for (let i = 0; i < root.pins.length; i++) {
            const e = root.pins[i];
            pinnedKeys[String(e.id)] = true;
            out.push(root.makeSlot(String(e.id), e, root.groups[String(e.id)], true));
        }
        const rest = [];
        for (const k in root.groups) {
            if (pinnedKeys[k] !== true) {
                rest.push(k);
            }
        }
        rest.sort((a, b) => root.groups[a].best - root.groups[b].best);
        for (let j = 0; j < rest.length; j++) {
            out.push(root.makeSlot(rest[j], root.entryFor(rest[j]), root.groups[rest[j]], false));
        }
        if (root.slotsEqual(root._slotCache.value, out)) {
            return root._slotCache.value;
        }
        root._slotCache.value = out;
        return out;
    }

    // Deep equality for slot rows: order, every displayed field, and
    // the per-slot window address sequence (MRU order matters for
    // activation). Window titles are live toplevel references — they
    // are not part of this comparison because they are read through
    // the shared objects, not copied into the slot.
    function slotsEqual(a, b) {
        if (a === null || a === undefined) {
            return false;
        }
        if (a === b) {
            return true;
        }
        if (a.length !== b.length) {
            return false;
        }
        for (let i = 0; i < a.length; i++) {
            const x = a[i];
            const y = b[i];
            if (x.key !== y.key || x.name !== y.name || x.icon !== y.icon
                    || x.pinned !== y.pinned || x.count !== y.count
                    || x.here !== y.here || x.elsewhere !== y.elsewhere
                    || x.urgent !== y.urgent || x.focused !== y.focused) {
                return false;
            }
            const xe = x.entry !== null && x.entry !== undefined ? String(x.entry.id) : "";
            const ye = y.entry !== null && y.entry !== undefined ? String(y.entry.id) : "";
            if (xe !== ye) {
                return false;
            }
            if (x.windows.length !== y.windows.length) {
                return false;
            }
            for (let j = 0; j < x.windows.length; j++) {
                if (x.windows[j].address !== y.windows[j].address) {
                    return false;
                }
            }
        }
        return true;
    }

    function makeSlot(key, entry, g, pinned) {
        const windows = g !== undefined ? g.windows : [];
        const active = DesktopNavigationStore.activeAddress;
        let focused = false;
        for (let i = 0; i < windows.length; i++) {
            if (HyprlandService.normalizeAddress(windows[i].address) === active) {
                focused = true;
                break;
            }
        }
        return {
            key: key,
            entry: entry,
            name: entry !== null && entry !== undefined ? String(entry.name) : root.nameForClass(key),
            icon: root.iconFor(key, entry, windows),
            pinned: pinned === true,
            windows: windows,
            count: windows.length,
            here: g !== undefined ? g.here : 0,
            elsewhere: g !== undefined ? g.elsewhere : 0,
            urgent: g !== undefined && g.urgent === true,
            focused: focused
        };
    }

    function nameForClass(key) {
        if (key.indexOf("class:") !== 0) {
            return key;
        }
        const cls = key.slice(6);
        return cls === "" ? "" : cls.charAt(0).toUpperCase() + cls.slice(1);
    }

    // Real icon or nothing: desktop entry → the window's own entry
    // lookup → "" (the view falls back to the class initial).
    function iconFor(key, entry, windows) {
        if (entry !== null && entry !== undefined && entry.icon !== undefined && String(entry.icon) !== "") {
            return Quickshell.iconPath(String(entry.icon), "");
        }
        if (windows !== undefined && windows.length > 0) {
            return HyprlandService.iconUrlForWindow(windows[0]);
        }
        return "";
    }

    // The desktop entry behind a non-pinned key (group keys that came
    // from a real entry are that entry's id); class groups have none.
    function entryFor(key) {
        if (key.indexOf("class:") === 0) {
            return null;
        }
        return LauncherModel.entryById(key);
    }

    // --- lookups the dock and the keyboard mode use ----------------------
    function windowsFor(key) {
        const g = root.groups[key];
        return g === undefined ? [] : g.windows;
    }

    function countFor(key) {
        return root.windowsFor(key).length;
    }

    function mruWindow(key) {
        const w = root.windowsFor(key);
        return w.length > 0 ? w[0] : null;
    }

    function slotIndex(key) {
        const list = root.slots;
        for (let i = 0; i < list.length; i++) {
            if (list[i].key === key) {
                return i;
            }
        }
        return -1;
    }

    function slotByKey(key) {
        const idx = root.slotIndex(key);
        return idx === -1 ? null : root.slots[idx];
    }

    // App key of the active window ("" = desktop) — keyboard mode starts
    // its selection on the app you are working in.
    function focusedKey() {
        const t = DesktopNavigationStore.activeToplevel;
        return t === null || t === undefined ? "" : root.keyForWindow(t);
    }
}
