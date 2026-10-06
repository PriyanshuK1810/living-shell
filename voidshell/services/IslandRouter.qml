pragma Singleton

import Quickshell
import QtQuick

// VOID SHELL — Living State Island action router (MASTER PROMPT §17, §21).
//
// One navigation interface with an optional item target. Two jobs:
//
//  1. Dashboard routing — time/date → Overview, calendar reminder →
//     Overview + date, weather → Overview's weather card, battery/system →
//     Overview, media → Media, notification/digest → Alerts,
//     timer/task/note/preset → Productivity. Nothing creates a new tab.
//
//  2. Action resolution — a registered action carries a *route string*
//     that is matched against a fixed allowlist. There is no generic
//     "run this" entry point anywhere in the Island: an event payload can
//     never name a command, and a URL or file path is only ever opened
//     after scheme/path validation on an explicit user click.
Singleton {
    id: root

    // Pending dashboard destination, consumed by Dashboard on open.
    property string tab: "overview"
    property string target: ""
    property int serial: 0

    readonly property var allowedTabs: ["overview", "media", "alerts", "productivity"]

    function normalizeTab(tab) {
        const t = String(tab || "");
        return root.allowedTabs.indexOf(t) !== -1 ? t : "overview";
    }

    // Open the dashboard on `tab`, optionally focusing `target`
    // (an event id, notification id, task id, date string…).
    function go(tab, target, screen, source) {
        root.tab = root.normalizeTab(tab);
        root.target = target === undefined || target === null ? "" : String(target);
        root.serial = root.serial + 1;
        PopupManager.open("dashboard", screen, source, "explicit");
        return true;
    }

    function goOverview(screen, source) {
        return root.go("overview", "", screen, source);
    }

    // --- route allowlist -------------------------------------------------
    // Route grammar: "<kind>:<argument>" where kind is one of the values
    // below and the argument is validated per kind. Anything else is
    // rejected and logged — never executed.
    function runRoute(route, activity) {
        const raw = String(route || "").trim();
        if (raw === "") {
            return false;
        }
        const idx = raw.indexOf(":");
        const kind = idx === -1 ? raw : raw.slice(0, idx);
        const arg = idx === -1 ? "" : raw.slice(idx + 1);

        switch (kind) {
        case "dashboard":
            return root.go(root.normalizeTab(arg), "", undefined, undefined);
        case "dashboardTarget":
            // "alerts" | "overview" | … plus the activity's own target.
            return root.go(root.normalizeTab(arg), activity ? activity.dashboardTarget : "", undefined, undefined);
        case "surface":
            return root.openSurface(arg);
        case "stack":
            return root.openStack();
        case "context":
            return root.openContext(arg);
        case "window":
            return root.focusWindow(activity);
        case "provider":
            return root.providerAction(arg, activity);
        default:
            console.warn("[voidshell] island: rejected unknown action route:", raw);
            return false;
        }
    }

    function openSurface(name) {
        // The lock surface is never reachable from an Island action.
        if (name === "lock" || !PopupManager.isPopup(name)) {
            return false;
        }
        return PopupManager.open(name, undefined, undefined, "explicit");
    }

    // A route may land on the Island itself (a card or the stack); the
    // controller owns that surface, this file only names the destination.
    function openStack() {
        return IslandController.openStack(undefined, undefined);
    }

    function openContext(key) {
        return IslandController.openContext("activity", String(key), undefined, undefined);
    }

    // "Return to work" (§31): focus the *exact* associated window, after
    // validating it still exists. Never matched by title, never a raw
    // handle persisted across sessions.
    function focusWindow(activity) {
        if (!activity || !activity.windowReference || !activity.windowReference.address) {
            return false;
        }
        return HyprlandService.activateWindow(activity.windowReference.address);
    }

    // --- trusted provider handlers ---------------------------------------
    function providerAction(arg, activity) {
        switch (arg) {
        case "dashboard-overview":
            return root.go("overview", "", undefined, undefined);
        case "audio-panel":
            return PopupManager.open("quickSettings", undefined, undefined, "explicit");
        case "bluetooth-panel":
            return PopupManager.open("quickSettings", undefined, undefined, "explicit");
        case "network-panel":
            return PopupManager.open("quickSettings", undefined, undefined, "explicit");
        case "notifications":
            return PopupManager.open("notifications", undefined, undefined, "explicit");
        case "alerts":
            return root.go("alerts", "", undefined, undefined);
        case "media":
            return root.go("media", "", undefined, undefined);
        case "productivity":
            return root.go("productivity", "", undefined, undefined);
        case "updates-refresh":
            SystemStats.refreshUpdates();
            return true;
        case "open-window-output":
            return root.openActivityOutput(activity);
        default:
            console.warn("[voidshell] island: rejected unknown provider action:", arg);
            return false;
        }
    }

    // Open an activity's declared output file: absolute path only, no
    // traversal, and opened through the desktop's default handler (a
    // file:// URL), never through a shell.
    function openActivityOutput(activity) {
        if (!activity || !activity.dashboardTarget) {
            return false;
        }
        return root.openPath(activity.dashboardTarget);
    }

    function openPath(path) {
        const p = String(path || "");
        if (!p.startsWith("/") || p.indexOf("..") !== -1 || p.indexOf("\n") !== -1 || p.length > 4096) {
            console.warn("[voidshell] island: rejected unsafe path in action");
            return false;
        }
        Qt.openUrlExternally("file://" + encodeURI(p));
        return true;
    }

    // URL schemes that may ever be opened from an Island action.
    function safeUrl(url) {
        const u = String(url || "").trim();
        if (u.length > 2048) {
            return "";
        }
        if (/^https?:\/\/[^\s"'<>]+$/i.test(u)) {
            return u;
        }
        return "";
    }

    function openUrl(url) {
        const u = root.safeUrl(url);
        if (u === "") {
            console.warn("[voidshell] island: rejected non-http(s) URL in action");
            return false;
        }
        Qt.openUrlExternally(u);
        return true;
    }
}
