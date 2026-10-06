pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — local job activity interface (MASTER PROMPT §17, F30).
//
// A small, validated IPC surface for participating tools — terminal
// commands, builds, tests, renders, downloads, backups and coding-agent
// runs — not a universal command-execution API.
//
// Transport: the shell's own Quickshell IPC target (`qs -c voidshell ipc
// call job <fn> '<json>'`), which lives on the user's session socket
// only: no network listener, no extra file to protect, no credentials.
// Payloads are validated JSON strings, because that is what the
// installed IPC system accepts for a single argument (§17: "Adapt
// signatures to the installed IPC system's supported types").
//
// What an event can never do:
//   * carry a shell command — actions resolve through IslandRouter's
//     fixed allowlist;
//   * fabricate progress — `progressMode: "none"` is explicit and a
//     spinner is the correct rendering for unknown progress;
//   * masquerade as an existing activity — identities are namespaced
//     (`sourceId/activityId`) and updates carry a monotonic sequence so a
//     late message cannot overwrite a newer one.
//
// sourceId alone is not authentication: this is a same-user convenience
// interface, which is why it only ever accepts data and user-resolved
// actions, never execution.
Singleton {
    id: root

    // Development-only demonstration events stay behind this flag so a
    // normal session can never be filled with fake activity.
    readonly property bool demoMode: Quickshell.env("VOID_ISLAND_DEMO") === "1"

    function parse(jsonText) {
        if (typeof jsonText !== "string" || jsonText.length === 0) {
            return null;
        }
        try {
            const data = JSON.parse(jsonText);
            if (data === null || typeof data !== "object" || Array.isArray(data)) {
                return null;
            }
            return data;
        } catch (e) {
            // Deliberately not a WARN: a rejected payload is the API
            // working as designed (the caller gets `false`), and the
            // gates treat WARN/ERROR as shell breakage.
            console.log("[voidshell] job: invalid JSON payload rejected");
            return null;
        }
    }

    function publishActivity(payload) {
        const data = root.parse(payload);
        if (data === null) {
            return false;
        }
        const act = ActivityStore.publish(data);
        if (act === null) {
            return false;
        }
        root.announceTransition(act, "publish");
        return true;
    }

    function updateActivity(payload) {
        const data = root.parse(payload);
        if (data === null) {
            return false;
        }
        const before = ActivityStore.byId(ActivityStore.makeKey(data));
        const act = ActivityStore.update(data);
        if (act === null) {
            return false;
        }
        // A transition into "waiting"/"blocked" is exactly the
        // approval-required moment (§ F30) and is announced; progress
        // ticks inside a running job are not.
        if (act.state === "waiting" || act.state === "blocked") {
            if (before === null || before.state !== act.state) {
                AnnouncementEngine.announce({
                    key: "job:" + act.key,
                    priority: 1,
                    category: "job",
                    feature: "jobs",
                    title: "Approval required",
                    subtitle: act.title,
                    icon: 0xF00D,
                    tone: "warning",
                    activityKey: act.key,
                    target: "context:activity"
                });
            }
        }
        return true;
    }

    function finishActivity(payload) {
        const data = root.parse(payload);
        if (data === null) {
            return false;
        }
        const act = ActivityStore.finish(data);
        if (act === null) {
            return false;
        }
        const ok = act.state === "success";
        AnnouncementEngine.announce({
            key: "job:" + act.key,
            priority: 1,
            category: "job",
            feature: "jobs",
            title: jobResultTitle(act),
            subtitle: act.subtitle,
            icon: ok ? 0xF00C : 0xF00D,
            tone: ok ? "success" : "danger",
            activityKey: act.key,
            target: "dashboard:overview"
        });
        return true;
    }

    // Publishing an activity is a presentation event in its own right:
    // the clock briefly says what just started (P2 job event), and the
    // activity itself continues in the stack.
    function announceTransition(act, kind) {
        if (kind !== "publish") {
            return;
        }
        AnnouncementEngine.announce({
            key: "job:" + act.key,
            priority: 2,
            category: "job",
            feature: "jobs",
            title: act.title,
            subtitle: act.subtitle !== "" ? act.subtitle : "Started",
            icon: 0xF0450,
            tone: "info",
            activityKey: act.key,
            target: "context:" + act.key
        });
    }

    function jobResultTitle(act) {
        if (act.state === "success") {
            return act.title + " finished";
        }
        if (act.state === "failure") {
            return act.title + " failed";
        }
        if (act.state === "cancelled") {
            return act.title + " cancelled";
        }
        return act.title;
    }

    // A tool may announce something without creating an activity.
    function announceEvent(payload) {
        const data = root.parse(payload);
        if (data === null) {
            return false;
        }
        return AnnouncementEngine.announce({
            key: typeof data.key === "string" ? data.key : "",
            priority: typeof data.priority === "number" ? data.priority : 2,
            category: typeof data.category === "string" ? data.category : "job",
            feature: typeof data.feature === "string" ? data.feature : "jobs",
            title: String(data.title || ""),
            subtitle: String(data.subtitle || ""),
            icon: typeof data.icon === "number" ? data.icon : 0xF120,
            tone: typeof data.tone === "string" ? data.tone : "info",
            target: typeof data.target === "string" ? data.target : ""
        });
    }

    function pinActivity(key) {
        ActivityStore.pin(String(key || ""));
        return true;
    }

    function invokeRegisteredAction(activityId, actionId) {
        return ActivityStore.invoke(String(activityId || ""), String(actionId || ""));
    }

    // --- IPC surface -----------------------------------------------------
    IpcHandler {
        target: "job"

        function publish(payload: string): bool {
            return root.publishActivity(payload);
        }

        function update(payload: string): bool {
            return root.updateActivity(payload);
        }

        function finish(payload: string): bool {
            return root.finishActivity(payload);
        }

        function announce(payload: string): bool {
            return root.announceEvent(payload);
        }

        function pin(key: string): bool {
            return root.pinActivity(key);
        }

        function invoke(activityId: string, actionId: string): bool {
            return root.invokeRegisteredAction(activityId, actionId);
        }
    }
}
