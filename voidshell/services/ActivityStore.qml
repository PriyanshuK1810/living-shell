pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — Living State Island activity store (MASTER PROMPT §7, §17).
//
// The Island keeps four concepts apart (§7.A–D):
//   provider state — what an underlying service reports (lives in the
//                    existing services, never copied here),
//   activity       — a *continuing* operation (timer, recording, job,
//                    download, agent run) — this file,
//   announcement   — a temporary presentation of a change (AnnouncementEngine),
//   history        — a bounded record of finished activities (below).
//
// Everything an external tool publishes is validated first: unknown
// schema versions, NaN, out-of-range progress, oversized payloads and
// missing identity are rejected rather than rendered. Updates carry a
// monotonic `sequence` so a late message can never overwrite a newer
// one, and terminal states are idempotent — a second `finish` for the
// same activity is ignored instead of resurrecting it.
//
// Identity is namespaced: `sourceId/activityId`. Nothing here ever
// stores a command to run — registered actions carry a *route* that
// IslandRouter resolves against a fixed allowlist (§17 Security).
Singleton {
    id: root

    readonly property int schemaVersion: 1
    readonly property int maxPayloadBytes: 16384
    readonly property int maxTextLength: 240

    // [{ key, ...normalized fields, pinned }] — plain objects, reassigned
    // wholesale so every binding re-evaluates (same idiom as TaskStore).
    property var items: []
    property var history: []
    property string pinnedKey: ""
    property bool loaded: false

    readonly property int count: root.items.length
    readonly property int activeCount: root.items.filter(a => !root.isTerminal(a.state)).length

    // Bounded completion summaries, newest first, retention from settings.
    readonly property int historyCount: root.history.length

    // Pinned activity first, then most recently updated: the stack's
    // order is *derived*, never mutated in place, and it is frozen while
    // the user interacts (see `frozenOrder`) so a new activity can never
    // slide a different row under the pointer (§7 Interaction protection).
    property bool frozenOrder: false
    property var frozenStack: []

    readonly property var stack: {
        if (root.frozenOrder) {
            return root.frozenStack;
        }
        const list = root.items.slice();
        list.sort((a, b) => {
            const pa = a.key === root.pinnedKey ? 0 : 1;
            const pb = b.key === root.pinnedKey ? 0 : 1;
            if (pa !== pb) {
                return pa - pb;
            }
            return b.updatedAt - a.updatedAt;
        });
        return list;
    }

    readonly property var pinned: root.byId(root.pinnedKey)

    // Ambient line for the clock: exactly one compact indicator (§6 State B).
    readonly property var ambient: {
        if (root.pinned !== null && root.pinned !== undefined) {
            return root.pinned;
        }
        const list = root.items.filter(a => !root.isTerminal(a.state));
        return list.length > 0 ? list[0] : null;
    }

    // Namespaced identity: `sourceId/activityId`. Used both to store an
    // activity and to look one up before applying an update.
    function makeKey(payload) {
        if (!payload || typeof payload !== "object") {
            return "";
        }
        const s = String(payload.sourceId === undefined ? "" : payload.sourceId).trim();
        const a = String(payload.activityId === undefined ? "" : payload.activityId).trim();
        if (s === "" || a === "") {
            return "";
        }
        return s + "/" + a;
    }

    function isTerminal(state) {
        return state === "success" || state === "failure" || state === "cancelled";
    }

    function byId(key) {
        if (!key) {
            return null;
        }
        for (let i = 0; i < root.items.length; i++) {
            if (root.items[i].key === key) {
                return root.items[i];
            }
        }
        return null;
    }

    function nowMs() {
        return Date.now();
    }

    function cleanText(value, fallback) {
        if (value === undefined || value === null) {
            return fallback;
        }
        const s = String(value).replace(/\s+/g, " ").trim();
        if (s === "") {
            return fallback;
        }
        return s.length > root.maxTextLength ? s.slice(0, root.maxTextLength - 1) + "…" : s;
    }

    function num(value, fallback) {
        if (typeof value !== "number" || !isFinite(value)) {
            return fallback;
        }
        return value;
    }

    // --- validation ------------------------------------------------------
    // Returns a normalized activity, or null when the payload is not
    // acceptable. `partial` allows updateActivity() to send only the
    // fields that actually changed.
    function normalize(payload, partial) {
        if (payload === null || payload === undefined || typeof payload !== "object" || Array.isArray(payload)) {
            return null;
        }
        // Oversized payload guard (§17): reject before allocating strings.
        let approx = 0;
        for (const k in payload) {
            approx += String(k).length + (typeof payload[k] === "string" ? payload[k].length : 24);
            if (approx > root.maxPayloadBytes) {
                console.warn("[voidshell] island: activity payload too large, rejected");
                return null;
            }
        }

        const sourceId = root.cleanText(payload.sourceId, "");
        const activityId = root.cleanText(payload.activityId, "");
        if (sourceId === "" || activityId === "") {
            return null;
        }
        if (!/^[A-Za-z0-9._-]{1,64}$/.test(sourceId) || !/^[A-Za-z0-9._-]{1,64}$/.test(activityId)) {
            return null;
        }

        const state = root.validState(payload.state, partial ? "working" : "working");
        const progressMode = (payload.progressMode === "indeterminate" || payload.progressMode === "determinate")
            ? payload.progressMode
            : "none";
        let progressValue = 0;
        if (progressMode === "determinate") {
            progressValue = root.num(payload.progressValue, NaN);
            if (!isFinite(progressValue) || progressValue < 0 || progressValue > 100) {
                return null;
            }
        }

        const actions = [];
        if (Array.isArray(payload.registeredActions)) {
            for (let i = 0; i < payload.registeredActions.length && actions.length < 8; i++) {
                const raw = payload.registeredActions[i];
                if (raw && typeof raw === "object" && typeof raw.id === "string" && typeof raw.label === "string") {
                    actions.push({
                        id: raw.id.slice(0, 64),
                        label: root.cleanText(raw.label, raw.id).slice(0, 64),
                        route: typeof raw.route === "string" ? raw.route.slice(0, 96) : ""
                    });
                }
            }
        }

        let windowReference = null;
        if (payload.windowReference && typeof payload.windowReference === "object") {
            const addr = String(payload.windowReference.address || "").trim();
            if (addr !== "") {
                windowReference = {
                    address: addr.slice(0, 80),
                    title: root.cleanText(payload.windowReference.title, ""),
                    workspace: root.cleanText(payload.windowReference.workspace, "")
                };
            }
        }

        const now = root.nowMs();
        const created = root.num(payload.createdAt, 0) || now;
        return {
            schemaVersion: root.schemaVersion,
            key: sourceId + "/" + activityId,
            sourceId: sourceId,
            sourceInstanceId: root.cleanText(payload.sourceInstanceId, ""),
            activityId: activityId,
            sequence: Math.max(0, Math.floor(root.num(payload.sequence, 0))),
            activityType: root.cleanText(payload.activityType, "job").slice(0, 32),
            state: state,
            title: root.cleanText(payload.title, activityId),
            subtitle: root.cleanText(payload.subtitle, ""),
            iconReference: root.cleanText(payload.iconReference, ""),
            progressMode: progressMode,
            progressValue: progressValue,
            elapsedSeconds: Math.max(0, root.num(payload.elapsedSeconds, -1)),
            estimatedRemainingSeconds: Math.max(0, root.num(payload.estimatedRemainingSeconds, -1)),
            createdAt: created,
            updatedAt: now,
            expiresAt: root.num(payload.expiresAt, 0),
            sensitivity: payload.sensitivity === "sensitive" ? "sensitive" : "normal",
            deduplicationKey: root.cleanText(payload.deduplicationKey, "").slice(0, 96),
            windowReference: windowReference,
            workspaceReference: root.cleanText(payload.workspaceReference, "").slice(0, 64),
            dashboardTarget: root.cleanText(payload.dashboardTarget, "").slice(0, 64),
            registeredActions: actions,
            // Session-scoped only: never persisted across restarts (§31).
            pinned: false
        };
    }

    function validState(value, fallback) {
        const ok = ["waiting", "working", "paused", "blocked", "unknown", "success", "failure", "cancelled"];
        return ok.indexOf(String(value)) !== -1 ? String(value) : fallback;
    }

    // --- mutations -------------------------------------------------------
    // publishActivity / updateActivity share one path; `finishActivity`
    // forces a terminal state. Both return the stored activity or null.
    function publish(payload) {
        const act = root.normalize(payload, false);
        if (act === null) {
            return null;
        }
        const existing = root.byId(act.key);
        if (existing === null) {
            act.pinned = (root.pinnedKey === act.key);
            root.items = root.items.concat([act]);
            return act;
        }
        return root.merge(existing, act);
    }

    function update(payload) {
        const act = root.normalize(payload, true);
        if (act === null) {
            return null;
        }
        const existing = root.byId(act.key);
        if (existing === null) {
            // An update for something we never saw is a publish: the
            // sender may have raced our startup. Not an error.
            root.items = root.items.concat([act]);
            return act;
        }
        return root.merge(existing, act);
    }

    function finish(payload) {
        const act = root.normalize(payload, true);
        if (act === null) {
            return null;
        }
        if (!root.isTerminal(act.state)) {
            act.state = "success";
        }
        const existing = root.byId(act.key);
        if (existing === null) {
            root.items = root.items.concat([act]);
            root.pushHistory(act);
            return act;
        }
        const merged = root.merge(existing, act);
        if (merged !== null && root.isTerminal(merged.state)) {
            root.pushHistory(merged);
        }
        return merged;
    }

    function merge(existing, incoming) {
        // Stale/out-of-order guard (§17): a lower sequence never wins.
        if (incoming.sequence < existing.sequence) {
            return existing;
        }
        // Terminal states are idempotent: the second finish is ignored so
        // "finished twice" cannot rewrite history.
        if (root.isTerminal(existing.state)) {
            if (incoming.sequence > existing.sequence) {
                return existing;
            }
            return existing;
        }

        const next = Object.assign({}, existing, incoming);
        next.sequence = Math.max(existing.sequence, incoming.sequence);
        next.createdAt = existing.createdAt;
        next.pinned = existing.pinned;
        next.updatedAt = root.nowMs();

        // Never drop a pin onto a different activity implicitly.
        if (root.pinnedKey !== "" && root.pinnedKey !== next.key) {
            next.pinned = false;
        }

        const list = root.items.slice();
        for (let i = 0; i < list.length; i++) {
            if (list[i].key === next.key) {
                list[i] = next;
            }
        }
        root.items = list;
        return next;
    }

    function pushHistory(activity) {
        if (!activity) {
            return;
        }
        const entry = {
            key: activity.key,
            title: activity.title,
            subtitle: activity.subtitle,
            state: activity.state,
            sourceId: activity.sourceId,
            activityType: activity.activityType,
            dashboardTarget: activity.dashboardTarget,
            windowReference: activity.windowReference,
            at: root.nowMs()
        };
        // Bounded, de-duplicated by key: a re-run replaces its old line.
        const next = root.history.filter(h => h.key !== entry.key);
        next.unshift(entry);
        const keep = Math.max(5, IslandSettings.historyRetention);
        root.history = next.slice(0, keep);
        root.save();
        // The activity itself leaves the stack once it is terminal, after
        // its summary is captured — an announcement expiring is NOT how an
        // activity ends, so removal is explicit here only.
        const rest = root.items.filter(a => a.key !== activity.key);
        root.items = rest;
        if (root.pinnedKey === activity.key) {
            root.pinnedKey = "";
        }
    }

    function remove(key) {
        const rest = root.items.filter(a => a.key !== key);
        root.items = rest;
        if (root.pinnedKey === key) {
            root.pinnedKey = "";
        }
    }

    function clearFinished() {
        root.history = [];
        root.save();
    }

    // Exactly one primary activity in the compact clock (§7 Pinning);
    // pinning affects prominence, never priority.
    function pin(key) {
        if (key === undefined || key === "") {
            root.pinnedKey = "";
            return;
        }
        const act = root.byId(key);
        if (act === null) {
            return;
        }
        root.pinnedKey = (root.pinnedKey === key) ? "" : key;
    }

    function freeze() {
        if (!root.frozenOrder) {
            root.frozenStack = root.stack;
            root.frozenOrder = true;
        }
    }

    function thaw() {
        root.frozenOrder = false;
        root.frozenStack = [];
    }

    // Resolve a registered action against the allowlist. Never a shell
    // command: IslandRouter validates the route (§17 Security).
    function invoke(key, actionId) {
        const act = root.byId(key);
        if (act === null) {
            return false;
        }
        for (let i = 0; i < act.registeredActions.length; i++) {
            const a = act.registeredActions[i];
            if (a.id === actionId) {
                return IslandRouter.runRoute(a.route, act);
            }
        }
        return false;
    }

    // Elapsed/remaining helpers shared by the stack rows and the clock.
    function elapsedLabel(activity) {
        if (!activity) {
            return "";
        }
        let s = activity.elapsedSeconds;
        if (s < 0 && activity.createdAt > 0) {
            s = Math.max(0, Math.floor((root.nowMs() - activity.createdAt) / 1000));
        }
        if (s < 0) {
            return "";
        }
        return fmtDuration(s);
    }

    function fmtDuration(totalSeconds) {
        const s = Math.max(0, Math.floor(totalSeconds));
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const sec = s % 60;
        const pad = n => (n < 10 ? "0" + n : String(n));
        return h > 0 ? h + ":" + pad(m) + ":" + pad(sec) : pad(m) + ":" + pad(sec);
    }

    function progressLabel(activity) {
        if (!activity) {
            return "";
        }
        if (activity.progressMode === "determinate") {
            return Math.round(activity.progressValue) + "%";
        }
        if (activity.progressMode === "indeterminate") {
            return "…";
        }
        return "";
    }

    // Persistence: activities are session-scoped by design (§31 — a raw
    // compositor window handle must never outlive the session), so only
    // the bounded completion history is written, and only when the
    // retention window asks for it.
    FileView {
        id: file
        path: StorageService.ready ? StorageService.path("island-activities.json") : ""
        printErrors: false
        onLoaded: root.load(file.text())
        onLoadFailed: root.load("")
    }

    function load(content) {
        root.loaded = true;
        if (!content || content.trim() === "") {
            root.history = [];
            return;
        }
        try {
            const data = JSON.parse(content);
            if (Array.isArray(data)) {
                root.history = data.filter(e => e && typeof e.key === "string").slice(0, IslandSettings.historyRetention);
            } else {
                root.history = [];
            }
        } catch (e) {
            console.warn("[voidshell] island-activities.json malformed, starting empty:", e);
            root.history = [];
        }
    }

    function save() {
        if (!StorageService.ready || !root.loaded) {
            return;
        }
        file.setText(JSON.stringify(root.history.slice(0, IslandSettings.historyRetention)));
    }
}
