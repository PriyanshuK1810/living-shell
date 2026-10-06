pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — docker/containers state (PRD §27) backing the `@containers`
// launcher plugin. Detection distinguishes "CLI missing" from "daemon not
// reachable", lists are read with machine-readable --format output, and
// only non-destructive baseline actions exist (start / stop / restart /
// refresh). Nothing here removes containers, images or volumes, and no
// action runs unless the user presses its button.
Singleton {
    id: root

    // checking | unavailable | ready
    property string state: "checking"
    property string reason: ""
    property bool loading: false
    property bool acting: false
    property bool copyAvailable: false
    property string lastError: ""
    property string activeTab: "containers"

    property var containers: [] // [{id, name, image, state, status, project, ports}]
    property var images: [] // [{id, repo, tag, size, created}]
    property var volumes: [] // [{name, driver, scope}]

    readonly property int runningCount: {
        let n = 0;
        for (let i = 0; i < root.containers.length; i++) {
            if (root.containers[i].state === "running") {
                n++;
            }
        }
        return n;
    }

    function shellQuote(value) {
        return HyprlandService.shQuote(value);
    }

    // Called when the plugin opens or its header refresh is pressed.
    function ensureDetected() {
        if (root.state === "checking") {
            detect.running = true;
        }
    }

    function refresh(tab) {
        if (tab !== undefined && tab !== null) {
            root.activeTab = tab;
        }
        if (root.state !== "ready") {
            root.ensureDetected();
            return;
        }
        root.loading = true;
        root.lastError = "";
        if (root.activeTab === "images") {
            listImages.running = true;
        } else if (root.activeTab === "volumes") {
            listVolumes.running = true;
        } else {
            listContainers.running = true;
        }
    }

    function startContainer(name) {
        root.act("start", name);
    }

    function stopContainer(name) {
        root.act("stop", name);
    }

    function restartContainer(name) {
        root.act("restart", name);
    }

    function act(verb, name) {
        if (root.acting || !name) {
            return;
        }
        root.acting = true;
        HyprlandService.execShell("docker " + verb + " " + root.shellQuote(name));
        actTimer.restart();
    }

    Timer {
        id: actTimer
        interval: 1400
        onTriggered: {
            root.acting = false;
            root.refresh();
        }
    }

    // --- Detection: CLI first, then daemon reachability -----------------
    Process {
        id: detect
        command: ["sh", "-c", "command -v docker >/dev/null 2>&1 && docker info --format '{{.ServerVersion}}' 2>/dev/null"]
        stdout: StdioCollector {
            id: detectOut
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                root.state = "ready";
                root.reason = "";
                root.refresh();
            } else {
                // Distinguish a missing CLI from a stopped daemon so the
                // plugin can say which one (PRD §37).
                cliCheck.running = true;
            }
        }
    }

    Process {
        id: cliCheck
        command: ["sh", "-c", "command -v docker >/dev/null 2>&1"]
        onExited: exitCode => {
            root.state = "unavailable";
            root.reason = exitCode === 0 ? "Docker daemon is not reachable" : "Docker is not installed on this system";
        }
    }

    // Clipboard availability for the copy-id row action (PRD §37: the
    // button only exists when wl-copy does).
    Process {
        id: detectCopy
        command: ["sh", "-c", "command -v wl-copy >/dev/null 2>&1"]
        running: true
        onExited: exitCode => root.copyAvailable = exitCode === 0
    }

    // --- Listing --------------------------------------------------------
    Process {
        id: listContainers
        command: ["docker", "ps", "-a", "--format", "{{json .}}"]
        stdout: StdioCollector {
            id: containersOut
        }
        onExited: exitCode => {
            root.loading = false;
            if (exitCode !== 0) {
                root.lastError = "Could not list containers";
                return;
            }
            root.containers = root.parseContainerLines(containersOut.text);
        }
    }

    Process {
        id: listImages
        command: ["docker", "images", "--format", "{{json .}}"]
        stdout: StdioCollector {
            id: imagesOut
        }
        onExited: exitCode => {
            root.loading = false;
            if (exitCode !== 0) {
                root.lastError = "Could not list images";
                return;
            }
            root.images = root.parseImageLines(imagesOut.text);
        }
    }

    Process {
        id: listVolumes
        command: ["docker", "volume", "ls", "--format", "{{json .}}"]
        stdout: StdioCollector {
            id: volumesOut
        }
        onExited: exitCode => {
            root.loading = false;
            if (exitCode !== 0) {
                root.lastError = "Could not list volumes";
                return;
            }
            root.volumes = root.parseVolumeLines(volumesOut.text);
        }
    }

    // --- Parsing --------------------------------------------------------
    function eachJsonLine(text, fn) {
        const lines = String(text || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            if (line === "") {
                continue;
            }
            try {
                const obj = JSON.parse(line);
                fn(obj);
            } catch (e) {
                // Skip unparseable rows rather than dropping the whole list.
            }
        }
    }

    function parseContainerLabels(labels) {
        const out = {};
        if (typeof labels !== "string" || labels === "") {
            return out;
        }
        const pairs = labels.split(",");
        for (let i = 0; i < pairs.length; i++) {
            const eq = pairs[i].indexOf("=");
            if (eq > 0) {
                out[pairs[i].slice(0, eq)] = pairs[i].slice(eq + 1);
            }
        }
        return out;
    }

    function parseContainerLines(text) {
        const out = [];
        root.eachJsonLine(text, obj => {
            const labels = root.parseContainerLabels(obj.Labels || "");
            out.push({
                id: String(obj.ID || "").slice(0, 12),
                name: String(obj.Names || "").replace(/^\//, ""),
                image: String(obj.Image || ""),
                state: String(obj.State || "").toLowerCase(),
                status: String(obj.Status || ""),
                project: labels["com.docker.compose.project"] || "",
                ports: String(obj.Ports || "")
            });
        });
        out.sort((a, b) => {
            if (a.project !== b.project) {
                if (a.project === "") return 1;
                if (b.project === "") return -1;
                return a.project.localeCompare(b.project);
            }
            return a.name.localeCompare(b.name);
        });
        return out;
    }

    function parseImageLines(text) {
        const out = [];
        root.eachJsonLine(text, obj => {
            out.push({
                id: String(obj.ID || "").slice(0, 12),
                repo: String(obj.Repository || "<none>"),
                tag: String(obj.Tag || "<none>"),
                size: String(obj.Size || ""),
                created: String(obj.CreatedSince || "")
            });
        });
        out.sort((a, b) => (a.repo + a.tag).localeCompare(b.repo + b.tag));
        return out;
    }

    function parseVolumeLines(text) {
        const out = [];
        root.eachJsonLine(text, obj => {
            out.push({
                name: String(obj.Name || ""),
                driver: String(obj.Driver || ""),
                scope: String(obj.Scope || ""),
                mountpoint: String(obj.Mountpoint || "")
            });
        });
        out.sort((a, b) => a.name.localeCompare(b.name));
        return out;
    }
}
