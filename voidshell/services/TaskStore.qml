pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — persistent task list (PRD 22.5, 35) backing the dashboard's
// Productivity tab. Malformed or missing files degrade to an empty list;
// writes are atomic through FileView, so a partial write cannot corrupt
// existing state.
Singleton {
    id: root

    property var tasks: []
    property bool loaded: false

    readonly property int count: root.tasks.length
    readonly property int activeCount: {
        let n = 0;
        for (let i = 0; i < root.tasks.length; i++) {
            if (!root.tasks[i].done) {
                n++;
            }
        }
        return n;
    }
    readonly property int doneCount: root.count - root.activeCount

    FileView {
        id: file
        path: StorageService.ready ? StorageService.path("tasks.json") : ""
        printErrors: false
        onLoaded: root.parse(file.text())
        // A missing file fires loadFailed, not loaded; treat it as the
        // empty list so loaded flips and the first save can create the
        // file (otherwise nothing ever persists on a fresh system).
        onLoadFailed: root.parse("")
    }

    function parse(content) {
        root.loaded = true;
        if (!content || content.trim() === "") {
            root.tasks = [];
            return;
        }
        try {
            const data = JSON.parse(content);
            const list = Array.isArray(data) ? data : (Array.isArray(data.tasks) ? data.tasks : []);
            const clean = [];
            for (let i = 0; i < list.length; i++) {
                const item = list[i];
                if (item && typeof item.title === "string" && item.title.trim() !== "") {
                    clean.push({
                        id: typeof item.id === "number" ? item.id : i + 1,
                        title: item.title,
                        done: item.done === true,
                        createdAt: typeof item.createdAt === "number" ? item.createdAt : 0
                    });
                }
            }
            root.tasks = clean;
        } catch (e) {
            // Never crash on malformed state: start empty, next save repairs it.
            console.warn("[voidshell] tasks.json malformed, starting empty:", e);
            root.tasks = [];
        }
    }

    function save() {
        if (!StorageService.ready || !root.loaded) {
            return;
        }
        file.setText(JSON.stringify({
            version: 1,
            tasks: root.tasks
        }, null, 2));
    }

    function nextId() {
        let max = 0;
        for (let i = 0; i < root.tasks.length; i++) {
            if (root.tasks[i].id > max) {
                max = root.tasks[i].id;
            }
        }
        return max + 1;
    }

    function add(title) {
        const text = String(title || "").trim();
        if (text === "") {
            return false;
        }
        const copy = root.tasks.slice();
        copy.push({
            id: root.nextId(),
            title: text,
            done: false,
            createdAt: Date.now()
        });
        root.tasks = copy;
        root.save();
        return true;
    }

    function toggle(id) {
        const copy = root.tasks.slice();
        for (let i = 0; i < copy.length; i++) {
            if (copy[i].id === id) {
                copy[i] = Object.assign({}, copy[i], {
                    done: !copy[i].done
                });
                root.tasks = copy;
                root.save();
                return;
            }
        }
    }

    function remove(id) {
        root.tasks = root.tasks.filter(t => t.id !== id);
        root.save();
    }

    function clearCompleted() {
        root.tasks = root.tasks.filter(t => !t.done);
        root.save();
    }
}
