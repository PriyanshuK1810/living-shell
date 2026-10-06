#!/usr/bin/env python3
"""Validate the whole Living Kitty configuration with kitty's own parsers.

kitty 0.49.2 has no `--debug-config` CLI flag (debug_config is an in-app
action), so this harness drives the exact code the app uses:

  * kitty.conf            -> kitty.config.parse_config (unknown keys,
                             invalid choices, missing includes, bad maps)
  * tab_bar.py            -> compile()
  * watchers/*.py         -> compile()
  * quick-access-terminal.conf / choose-files.conf -> the kitten's own
                             Definition (option names + choice values)
  * open-actions.conf     -> kitty.open_actions.parse + parse_key_action
                             (catches silently-ignored criteria keys)
  * sessions/*.conf       -> kitty.session.parse_session (unknown
                             commands are a hard error there)
  * scripts/*.sh|k*       -> bash -n

Run it from anywhere:

    python3 scripts/validate-config.py [config-dir]

Exit status: 0 = clean, 1 = problems found.
"""

from __future__ import annotations

import glob
import importlib
import os
import re
import subprocess
import sys

CFG_DIR = os.path.abspath(os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/.config/kitty"))

# kitty's pure-python modules live here on Arch; fast_data_types.so is
# built for CPython 3.14, which is the python3 on this machine.
sys.path.insert(0, "/usr/lib/kitty")
# Outside the kitty launcher, kitty.constants has no run data and would
# fall back to a throwaway temp config dir — pin it to the real one so
# include/globinclude resolve exactly as they do in a live kitty.
sys.kitty_run_data = {"config_dir": CFG_DIR, "extensions_dir": ""}

PROBLEMS = 0


def bad(msg: str) -> None:
    global PROBLEMS
    PROBLEMS += 1
    print(f"BAD  {msg}")


def good(msg: str) -> None:
    print(f"ok   {msg}")


def run_capturing_stderr(fn):
    """Run fn() while capturing stderr — kitty reports unknown keys and
    ignored shortcuts through log_error (stderr), not through bad_lines."""
    import tempfile

    tmp = tempfile.TemporaryFile(mode="w+")
    saved = os.dup(2)
    try:
        sys.stderr.flush()
        os.dup2(tmp.fileno(), 2)
        result = fn()
    finally:
        sys.stderr.flush()
        os.dup2(saved, 2)
        os.close(saved)
    tmp.seek(0)
    text = tmp.read()
    tmp.close()
    return result, text


def flag_log_problems(text: str, where: str) -> None:
    for line in text.splitlines():
        if any(s in line for s in ("Ignoring", "Shortcut:", "not a valid choice", "Failed to load")):
            bad(f"{where}: {line.strip()}")


def load_options():
    """Load kitty.conf exactly like a startup would: includes resolved,
    shortcuts normalized, unknown keys reported."""
    from kitty.config import load_config

    path = os.path.join(CFG_DIR, "kitty.conf")
    if not os.path.isfile(path):
        bad(f"{path} not found")
        return None, {}
    bad_lines: list = []
    options, logs = run_capturing_stderr(lambda: load_config(path, accumulate_bad_lines=bad_lines))
    opts = dict(options._asdict())
    for line in bad_lines:
        bad(f"{getattr(line, 'file', '?')}:{getattr(line, 'number', '?')}: {line}")
    flag_log_problems(logs, "kitty.conf")
    if not bad_lines and "Ignoring" not in logs and "Shortcut:" not in logs:
        good(f"kitty.conf: loaded via kitty.config.load_config, 0 bad lines, {len(opts)} settings")
    return options, opts


def check_py_files() -> None:
    for rel in ("tab_bar.py", "watchers/desktop_state.py"):
        path = os.path.join(CFG_DIR, rel)
        if not os.path.isfile(path):
            bad(f"missing {rel}")
            continue
        try:
            compile(open(path, encoding="utf-8").read(), path, "exec")
            good(f"{rel} compiles")
        except SyntaxError as err:
            bad(f"{rel} syntax error: {err}")


def check_kitten_conf(filename: str, module_name: str) -> None:
    """Validate a kitten conf file against the kitten's own option Definition."""
    path = os.path.join(CFG_DIR, filename)
    if not os.path.isfile(path):
        print(f"warn absent: {filename}")
        return
    try:
        module = importlib.import_module(module_name)
    except Exception as err:  # pragma: no cover - import layout changed
        print(f"warn cannot import {module_name}: {err}")
        return
    definition = getattr(module, "definition", None)
    if definition is None:
        print(f"warn {module_name} exposes no Definition")
        return

    count = 0
    for lineno, raw in enumerate(open(path, encoding="utf-8"), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^([A-Za-z0-9_+-]+)\s+(.*)$", line)
        if m is None:
            bad(f"{filename}:{lineno}: not `key value`: {line}")
            continue
        key, value = m.group(1), m.group(2).strip()
        opt = definition.option_map.get(key)
        if opt is None:
            bad(f"{filename}:{lineno}: unknown option `{key}` (kitten would ignore it)")
            continue
        if opt.choices and value not in opt.choices:
            bad(f"{filename}:{lineno}: `{value}` not in choices for {key}: {opt.choices}")
            continue
        try:
            opt.parser_func(value)
        except Exception as err:
            bad(f"{filename}:{lineno}: {key}={value}: {err}")
            continue
        count += 1
    good(f"{filename}: {count} options validated against {module_name}")


def check_open_actions(options) -> None:
    path = os.path.join(CFG_DIR, "open-actions.conf")
    if not os.path.isfile(path):
        print("warn absent: open-actions.conf")
        return

    # open-actions needs initialized options (it expands $EDITOR/$SHELL).
    from kitty.fast_data_types import set_options
    from kitty.open_actions import parse
    from kitty.options.utils import MapType, parse_key_action

    if options is None:
        bad("cannot validate open-actions.conf: kitty.conf failed to load")
        return
    set_options(options)

    known = {"protocol", "url", "fragment_matches", "mime", "ext", "file", "path", "action", "action_alias"}
    seen_action = False
    for lineno, raw in enumerate(open(path, encoding="utf-8"), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(maxsplit=1)
        if len(parts) != 2:
            bad(f"open-actions.conf:{lineno}: not `key value`: {line}")
            continue
        key = parts[0].lower()
        if key not in known:
            bad(f"open-actions.conf:{lineno}: `{key}` is not a criteria/action key "
                f"(kitty 0.49.2 silently ignores it). Use one of: {sorted(known)}")
            continue
        if key == "action":
            seen_action = True
            try:
                parse_key_action(parts[1], MapType.OPEN_ACTION)
            except Exception as err:
                bad(f"open-actions.conf:{lineno}: bad action {parts[1]!r}: {err}")

    try:
        entries, logs = run_capturing_stderr(lambda: tuple(parse(open(path, encoding="utf-8"))))
    except Exception as err:
        bad(f"open-actions.conf: parse failed: {err}")
        return
    flag_log_problems(logs, "open-actions.conf")
    if not entries:
        bad("open-actions.conf: parsed 0 entries (criteria/actions never paired — blank-line separated?)")
    else:
        good(f"open-actions.conf: {len(entries)} entries, actions parsed"
             + ("" if seen_action else " (no `action` lines found!)"))


def check_sessions(options) -> None:
    """Session files reject any non-session command with ValueError."""
    from kitty.fast_data_types import set_options
    from kitty.session import parse_session

    if options is None:
        bad("cannot validate sessions: kitty.conf failed to load")
        return
    set_options(options)

    files = sorted(glob.glob(os.path.join(CFG_DIR, "sessions", "*.conf")))
    if not files:
        bad("no session files under sessions/")
        return
    for path in files:
        name = os.path.basename(path)
        try:
            sessions = list(parse_session(open(path, encoding="utf-8").read(), options, session_path=path))
        except Exception as err:
            bad(f"sessions/{name}: {err}")
            continue
        tabs = sum(len(s.tabs) for s in sessions)
        windows = sum(len(t.windows) for s in sessions for t in s.tabs)
        good(f"sessions/{name}: {len(sessions)} os-window group(s), {tabs} tab(s), {windows} window(s)")


def check_shell_scripts() -> None:
    for path in sorted(glob.glob(os.path.join(CFG_DIR, "scripts", "*"))):
        name = os.path.basename(path)
        if not os.path.isfile(path):
            continue
        try:
            with open(path, "rb") as fh:
                head = fh.read(64)
        except OSError as err:
            bad(f"scripts/{name}: {err}")
            continue
        if head.startswith(b"#!") and b"bash" in head.splitlines()[0]:
            proc = subprocess.run(["bash", "-n", path], capture_output=True, text=True)
            if proc.returncode:
                bad(f"scripts/{name}: {proc.stderr.strip()}")
            else:
                good(f"scripts/{name}: bash -n clean")
        elif head.startswith(b"#!"):
            good(f"scripts/{name}: shebang present")
        else:
            print(f"warn scripts/{name}: no shebang (data file?)")


def main() -> int:
    options, opts = load_options()
    check_py_files()
    check_kitten_conf("quick-access-terminal.conf", "kittens.quick_access_terminal.main")
    check_kitten_conf("choose-files.conf", "kittens.choose_files.main")
    check_open_actions(options)
    check_sessions(options)
    check_shell_scripts()

    # Cross-checks the parser cannot do for us.
    for key in ("font_family", "tab_bar_style", "shell_integration", "allow_remote_control", "watcher"):
        if opts and opts.get(key) in (None, {}, (), ""):
            bad(f"{key} did not resolve from conf.d/ (include chain broken?)")
    if opts.get("watcher"):
        for rel in opts["watcher"]:
            resolved = rel if os.path.isabs(rel) else os.path.join(CFG_DIR, rel)
            if not os.path.isfile(resolved):
                bad(f"watcher file missing: {resolved}")
    if opts.get("tab_bar_style") == "custom" and not os.path.isfile(os.path.join(CFG_DIR, "tab_bar.py")):
        bad("tab_bar_style custom but tab_bar.py is missing")

    print(f"--- {PROBLEMS} problem(s)")
    return 1 if PROBLEMS else 0


if __name__ == "__main__":
    raise SystemExit(main())
