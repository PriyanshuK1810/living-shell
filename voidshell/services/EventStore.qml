pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — local calendar event store (PRD 16.2).
// Real persisted events under ~/.local/share/voidshell/calendar.json.
// Production never fabricates events: an empty store renders an empty
// list, and a malformed file degrades to empty and is repaired on the
// next write. External calendars can later implement the same interface.
Singleton {
    id: root

    property var events: []
    property bool loaded: false
    property int nextId: 1

    readonly property int count: root.events.length

    FileView {
        id: file
        path: StorageService.ready ? StorageService.path("calendar.json") : ""
        printErrors: false
        onLoaded: root.parse(file.text())
    }

    function parse(content) {
        root.loaded = true;
        if (!content || content.trim() === "") {
            root.events = [];
            root.nextId = 1;
            return;
        }
        try {
            const data = JSON.parse(content);
            const list = Array.isArray(data) ? data : (Array.isArray(data.events) ? data.events : []);
            const clean = [];
            let maxId = 0;
            for (let i = 0; i < list.length; i++) {
                const e = list[i];
                if (!e || typeof e.title !== "string" || e.title.trim() === "") {
                    continue;
                }
                if (typeof e.start !== "number" || typeof e.end !== "number") {
                    continue;
                }
                clean.push({
                    id: typeof e.id === "number" ? e.id : i + 1,
                    title: e.title.trim(),
                    start: e.start,
                    end: e.end,
                    category: typeof e.category === "string" ? e.category : "default",
                    notes: typeof e.notes === "string" ? e.notes : ""
                });
                maxId = Math.max(maxId, clean[clean.length - 1].id);
            }
            clean.sort((a, b) => a.start - b.start);
            root.events = clean;
            root.nextId = maxId + 1;
        } catch (e) {
            console.warn("[voidshell] calendar.json malformed, starting empty:", e);
            root.events = [];
            root.nextId = 1;
        }
    }

    function save() {
        if (!StorageService.ready) {
            return;
        }
        file.setText(JSON.stringify({
            version: 1,
            events: root.events
        }, null, 2));
    }

    // start/end are epoch milliseconds (local time as authored by the UI).
    function add(title, start, end, category, notes) {
        const trimmed = (title || "").trim();
        if (trimmed === "" || typeof start !== "number") {
            return null;
        }
        const event = {
            id: root.nextId,
            title: trimmed,
            start: start,
            end: typeof end === "number" ? end : start + 3600000,
            category: category || "default",
            notes: notes || ""
        };
        root.nextId = root.nextId + 1;
        const list = root.events.slice();
        list.push(event);
        list.sort((a, b) => a.start - b.start);
        root.events = list;
        root.save();
        return event;
    }

    function remove(id) {
        const list = [];
        for (let i = 0; i < root.events.length; i++) {
            if (root.events[i].id !== id) {
                list.push(root.events[i]);
            }
        }
        if (list.length === root.events.length) {
            return;
        }
        root.events = list;
        root.save();
    }

    // Events whose start falls on the local calendar day of `dayStart`.
    function eventsOn(dayStart) {
        const dayEnd = dayStart + 86400000;
        const out = [];
        for (let i = 0; i < root.events.length; i++) {
            const e = root.events[i];
            if (e.start >= dayStart && e.start < dayEnd) {
                out.push(e);
            }
        }
        return out;
    }
}
