#!/usr/bin/env python3
"""kitty watcher: Living State Island bridge + session tab titles.

Loaded in-process by kitty (option `watcher` in conf.d/90-integrations.conf).
It observes command start/end and republishes classified state to the
Void Shell island through the shell's *existing* validated IPC surface:

    qs -c voidshell ipc call job <publish|finish> '<json>'

Design rules (this file runs inside the compositor-facing kitty process):

  * never block, never raise: every outbound call is a detached child
    with stdin/stdout/stderr on /dev/null, started with start_new_session
    so it cannot delay a frame or a keypress;
  * never send the raw command line: only a program name, an allow-listed
    verb and a sanitised host name travel over IPC, so argv secrets stay
    in this process;
  * no polling and no state files: the island is event-driven from
    kitty's own command marks, so there is nothing to keep in sync;
  * no desktop notifications: the island already announces these events,
    adding notify-send here would duplicate them.

Conservative by design: an unknown command reports nothing at start, and
only becomes a "finished" event if it ran long enough to be interesting.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import time

# --- thresholds ----------------------------------------------------------
MIN_FINISH_SECONDS = 8.0   # unknown/short commands only announce if longer
MIN_FAILURE_SECONDS = 4.0  # ... failures get a slightly lower bar

# --- classification ------------------------------------------------------
ROOT_PROGS = {"sudo", "su", "doas", "ksu"}
SSH_PROGS = {"ssh", "mosh", "mosh-client"}
PKG_PROGS = {"yay", "paru", "pacman", "apt", "apt-get", "dnf", "zypper", "pamac"}
BUILD_PROGS = {
    "make", "gmake", "cmake", "ninja", "meson", "cargo", "rustc", "go",
    "gradle", "mvn", "javac", "gcc", "g++", "clang", "clang++", "dotnet",
    "pytest", "pyinstaller", "configure",
}
GIT_PROGS = {"git", "jj", "gh"}
XFER_PROGS = {"rsync", "scp", "sftp", "rclone", "curl", "wget"}
SYSTEM_PROGS = {"systemctl", "journalctl"}
DEV_PROGS = {"npm", "pnpm", "yarn", "bun", "deno"}

PKG_INSTALL_VERBS = {"install", "add", "ci", "in"}
PKG_UPGRADE_HINTS = ("syu", "upgrade", "update", "full-upgrade", "dist-upgrade", "refresh", "sync")
GIT_ANNOUNCE_VERBS = {"clone", "fetch", "pull", "push", "rebase"}
GIT_VERBS = GIT_ANNOUNCE_VERBS | {
    "checkout", "switch", "merge", "cherry-pick", "stash", "reset", "add",
    "commit", "revert", "bisect", "worktree", "submodule", "init", "remote",
    "diff", "log", "status", "show", "tag", "branch",
}
SERVICE_VERBS = {"start", "stop", "restart", "enable", "disable", "mask", "status", "reload"}
# ssh flags that take a separate value; their value is never a host name
SSH_VALUE_FLAGS = set("piolFJLRDwbc mQW".replace(" ", "")) | {"P", "S", "E", "C"}

_SAFE = re.compile(r"[^A-Za-z0-9._@:~-]")

# --- state ---------------------------------------------------------------
_ACTIVE: dict[int, dict] = {}
_COUNTER = [0]


def _new_activity_id() -> str:
    _COUNTER[0] += 1
    return "k{}-{}".format(os.getpid(), _COUNTER[0])


def _split(cmdline: str) -> list[str]:
    """kitty hands us the shell-quoted command line; recover argv safely."""
    if not cmdline:
        return []
    for splitter in (shlex.split, str.split):
        try:
            argv = splitter(cmdline)
        except Exception:
            continue
        if argv:
            return [a for a in argv if a]
    return []


def _clean(value: str, limit: int = 48) -> str:
    """Whitelist scrub: host names and verbs only, never raw arguments."""
    return _SAFE.sub("", value)[:limit]


def _ssh_host(argv: list[str]) -> str:
    skip_next = False
    for tok in argv[1:]:
        if skip_next:
            skip_next = False
            continue
        if tok.startswith("-"):
            flag = tok.lstrip("-")
            if len(flag) == 1 and flag in SSH_VALUE_FLAGS:
                skip_next = True
            continue
        return _clean(tok)
    return ""


def _classify(argv: list[str]) -> dict | None:
    """Return a conservative event description, or None to stay silent."""
    if not argv:
        return None
    prog = os.path.basename(argv[0])
    args = argv[1:]
    low_args = [a.lower() for a in args]
    first_verb = next((a for a in args if not a.startswith("-")), "").lower()

    def ev(kind: str, atype: str, title: str, subtitle: str = "", on_start: bool = True, tab_title: str | None = None) -> dict:
        return {
            "kind": kind, "type": atype, "title": title,
            "subtitle": _clean(subtitle) if subtitle else "",
            "on_start": on_start, "tab_title": tab_title, "prog": prog,
        }

    if prog in ROOT_PROGS:
        # argv is deliberately dropped: what a root shell does is not
        # island business, only that it is open.
        return ev("root", "terminal.root", "Root shell", "", True, "ROOT")

    if prog in SSH_PROGS:
        host = _ssh_host(argv)
        return ev("ssh", "terminal.ssh", "SSH session", host or prog, True,
                  "ssh: {}".format(host or prog))

    if prog in PKG_PROGS or (prog in DEV_PROGS and first_verb in PKG_INSTALL_VERBS):
        if any(h in " ".join(low_args) for h in PKG_UPGRADE_HINTS):
            title = "Updating packages"
        elif first_verb in PKG_INSTALL_VERBS:
            title = "Installing packages"
        else:
            title = "Package operation"
        return ev("package", "terminal.package", title, prog)

    if prog in DEV_PROGS:
        # npm/pnpm/yarn/bun are never "build" until they say build: a dev
        # server and a package install are different island states.
        if first_verb in PKG_INSTALL_VERBS:
            return ev("package", "terminal.package", "Installing packages", prog)
        if first_verb in {"dev", "start", "serve"} or "http.server" in low_args or "vite" in low_args:
            return ev("dev", "terminal.dev", "Dev server", prog)
        if first_verb in {"build", "run"}:
            return ev("build", "terminal.build", "Build", prog)
        return None

    if prog in BUILD_PROGS:
        return ev("build", "terminal.build", "Build", prog)

    if prog in GIT_PROGS:
        if prog == "git" and first_verb in GIT_VERBS:
            announce = first_verb in GIT_ANNOUNCE_VERBS
            return ev("git", "terminal.git", "Git {}".format(first_verb), prog, announce)
        return ev("git", "terminal.git", "Git operation", prog, False)

    if prog in XFER_PROGS:
        return ev("transfer", "terminal.transfer", "Transferring", prog)

    if prog in SYSTEM_PROGS:
        if prog == "journalctl":
            return ev("logs", "terminal.logs", "Reading logs", prog)
        if first_verb in SERVICE_VERBS:
            return ev("service", "terminal.service", "Service {}".format(first_verb), prog)
        return ev("service", "terminal.service", "Service operation", prog)

    # Unknown command: silent at start, may still report a completion.
    return ev("command", "terminal.command", "Command", prog, on_start=False)


# --- outbound (never blocking, never raising) ----------------------------
def _spawn(argv: list[str]) -> None:
    try:
        subprocess.Popen(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
            close_fds=True,
        )
    except Exception:
        pass


def _socket_address(boss) -> str:
    """Address of *this* kitty instance's remote control socket.

    The KITTY_LISTEN_ON environment variable must not be trusted here: it
    is written into *children* when they are spawned, never into kitty's
    own environment, so inside this process it still holds the address of
    whatever kitty launched us. Start kitty from inside another kitty
    window and that value names the parent — a tab title sent there would
    rename a tab in the wrong instance (found the hard way: an in-window
    test wrote to the parent's socket while its own tab stayed untouched).

    boss.listening_on is the address this instance really listens on, so
    it is the only value worth using. Empty means remote control is off
    for this instance, and then the honest thing is to do nothing.
    """
    addr = (getattr(boss, "listening_on", "") or "").strip()
    # `fd:...` addresses are handed to the spawning process and cannot be
    # reused here; anything else (including "") means no unix listener.
    return addr if addr.startswith("unix:") else ""


def _island(fn: str, payload: dict) -> None:
    try:
        text = json.dumps(payload, separators=(",", ":"), ensure_ascii=True)
    except Exception:
        return
    _spawn(["qs", "-c", "voidshell", "ipc", "call", "job", fn, text])


def _set_tab_title(window, title: str | None, boss) -> None:
    """Mark SSH/root sessions in the tab bar; None restores auto-title."""
    addr = _socket_address(boss)
    if not addr:
        return
    wid = getattr(window, "id", 0)
    argv = ["kitten", "@", "--to", addr, "set-tab-title",
            "--match", "window_id:{}".format(wid)]
    argv.append("" if title is None else title)
    _spawn(argv)


# --- event handlers ------------------------------------------------------
def _payload(run: dict, state: str, sequence: int, elapsed: float | None) -> dict:
    body = {
        "sourceId": "kitty",
        "activityId": run["id"],
        "sourceInstanceId": str(os.getpid()),
        "sequence": sequence,
        "activityType": run["ev"]["type"],
        "state": state,
        "title": run["ev"]["title"],
        "subtitle": run["ev"]["subtitle"],
        "progressMode": "none",
        "deduplicationKey": "kitty/{}".format(run["id"]),
        "sensitivity": "normal",
    }
    if elapsed is not None:
        body["elapsedSeconds"] = round(elapsed, 1)
    return body


def on_cmd_startstop(boss, window, data) -> None:
    try:
        if data.get("is_start"):
            _handle_start(window, data, boss)
        else:
            _handle_end(window, data, boss)
    except Exception:
        # A watcher must never take kitty down; fail silent by design.
        pass


def _handle_start(window, data, boss) -> None:
    ev = _classify(_split(data.get("cmdline") or ""))
    if ev is None:
        return
    run = {
        "id": _new_activity_id(),
        "ev": ev,
        "t0": time.monotonic(),
        "window_id": getattr(window, "id", 0),
        "published": False,
    }
    _ACTIVE[run["window_id"]] = run
    if ev["tab_title"]:
        _set_tab_title(window, ev["tab_title"], boss)
    if ev["on_start"]:
        run["published"] = True
        _island("publish", _payload(run, "working", 1, None))


def _handle_end(window, data, boss) -> None:
    run = _ACTIVE.pop(getattr(window, "id", 0), None)
    if run is None:
        return
    if run["ev"]["tab_title"]:
        _set_tab_title(window, None, boss)

    duration = max(0.0, time.monotonic() - run["t0"])
    ok = int(data.get("exit_status", 0) or 0) == 0

    if run["published"]:
        _island("finish", _payload(run, "success" if ok else "failure", 2, duration))
        return

    # Not announced at start: only surface commands that were long enough
    # (or that failed while doing something), so `ls` never reaches the
    # island.
    if duration >= MIN_FINISH_SECONDS or (not ok and duration >= MIN_FAILURE_SECONDS):
        _island("finish", _payload(run, "success" if ok else "failure", 1, duration))
