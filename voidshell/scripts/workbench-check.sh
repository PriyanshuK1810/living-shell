#!/usr/bin/env bash
# VOID SHELL — Workbench gate (Workbench plan §verification).
#
# Static half : house lint gate, Lua syntax, hyprland.lua wiring (the
#               native workspace swipe must stay the file's only
#               hl.gesture), and a three-way threshold cross-check —
#               `gesture config` (the shell's WorkbenchSettings) ↔
#               workbench.json (the file) ↔ /tmp/voidshell-gestures.loaded
#               (what gestures.lua actually parsed at config load).
#               All three must agree: one threshold table everywhere.
# Runtime half: one exact-PID shell restart with log capture (this gate
#               never pkills qs), the dock's surfaces and the gesture
#               router driven end to end over IPC (no input injection
#               exists in this environment — the physical touchpad
#               checks are printed at the end), a VOID_WORKBENCH=preview
#               QA pass, the house coord-check for the one-primary rule,
#               and a WARN-free scan of every log it collects.
# Repos       : current git status minus the saved baseline must contain
#               only the paths this plan touched (both repos).
#
# Run: scripts/workbench-check.sh   (needs the Hyprland session env:
#                                    HYPRLAND_INSTANCE_SIGNATURE, …)
# Expect WORKBENCH-GATE-PASS last.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HYPR="$HOME/dotfiles/hypr/.config/hypr"
BASE="${WORKBENCH_BASELINE:-/tmp/opencode/plans/workspace-1a0d8158/baseline}"
TMP=${TMPDIR:-/tmp}/voidworkbench-check
MARKER=${TMPDIR:-/tmp}/voidshell-gestures.loaded
JSON="$HOME/.local/share/voidshell/workbench.json"
mkdir -p "$TMP"
LOG=$TMP/main.log
fail=0

pass() { echo "PASS: $*"; }
bad()  { echo "FAIL: $*"; fail=1; }

if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    echo "FAIL: no Hyprland session in the environment (source it first)"
    exit 1
fi

# --- helpers -------------------------------------------------------------
# count <namespace> — instances of one layer namespace. The trailing
# comma keeps voidshell-workbench from matching voidshell-workbench-edge.
count() { hyprctl layers | grep -c "namespace: $1," || true; }

# The exact pid of THE `qs -c voidshell` process — the only process this
# gate ever kills (plan: never pkill qs).
shell_pid() {
    local p
    for p in $(pgrep -x qs 2>/dev/null); do
        if tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q '^qs -c voidshell'; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

count_shell() {
    local p c=0
    for p in $(pgrep -x qs 2>/dev/null); do
        if tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q '^qs -c voidshell'; then
            c=$((c + 1))
        fi
    done
    echo "$c"
}

stop_shell() {
    local pid waited=0
    pid=$(shell_pid || true)
    [ -n "$pid" ] || return 0
    echo "    stopping shell pid=$pid (cmdline verified)"
    kill "$pid" 2>/dev/null
    while [ "$waited" -lt 10 ] && kill -0 "$pid" 2>/dev/null; do
        sleep 0.5
        waited=$((waited + 1))
    done
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
    sleep 1
}

# `--` before the positionals: quickshell's CLI swallows a bare `show`
# function name otherwise (it prints the target's function list instead
# of calling it); every other name works with or without the separator.
ipc() { qs -c voidshell ipc call -- "$@" 2>&1; }

# The preview strip needs at least one real window to capture; spawn a
# temporary kitty only when the session has none (released at the end).
FIX_PID=""
have_window=0
ensure_window() {
    local n
    n=$(hyprctl -j clients | python3 -c 'import json,sys; print(sum(1 for c in json.load(sys.stdin) if c.get("mapped", True)))')
    if [ "$n" -gt 0 ]; then
        have_window=1
        echo "== window fixture: session already has $n mapped windows"
        return 0
    fi
    command -v kitty > /dev/null || { echo "== window fixture: none, no kitty"; return 1; }
    setsid kitty --class voidwb-probe > /dev/null 2>&1 </dev/null &
    sleep 4
    FIX_PID=$(hyprctl -j clients | python3 -c 'import json,sys; c=[x for x in json.load(sys.stdin) if x["class"]=="voidwb-probe"]; print(c[0]["pid"] if c else "")')
    [ -n "$FIX_PID" ] && have_window=1 && echo "== window fixture: pid=$FIX_PID"
    [ "$have_window" = "1" ]
}

release_window() {
    [ -n "$FIX_PID" ] || return 0
    kill "$FIX_PID" 2>/dev/null
    sleep 2
    echo "== window fixture: released pid=$FIX_PID"
    FIX_PID=""
}

# log_clean <file> <label> — zero WARN/ERROR (house exclusion list).
log_clean() {
    local n
    n=$(grep -E "WARN|ERROR" "$1" 2>/dev/null | grep -vcE "notification server|Registration will be" || true)
    if [ "$n" = "0" ]; then
        pass "0 QML WARN/ERROR in $2 log"
    else
        bad "$n warnings in $2 log:"
        grep -E "WARN|ERROR" "$1" | sed 's/^/    /'
    fi
}

json_ok() { # json_ok <json> <python-expr over s> — assertion helper
    echo "$1" | python3 -c "import json,sys; s=json.load(sys.stdin); raise SystemExit(0 if ($2) else 1)"
}

# ==========================================================================
echo "== static: house lint gate"
if "$ROOT/scripts/check.sh" > "$TMP/check.out" 2>&1; then
    pass "check.sh — every QML lints clean, every qmldir singleton resolves"
else
    bad "check.sh failed:"
    tail -25 "$TMP/check.out" | sed 's/^/    /'
fi

echo "== static: lua syntax + hyprland.lua wiring"
if luac5.4 -p "$HYPR/hyprland.lua" "$HYPR"/config/*.lua; then
    pass "luac5.4 -p: hyprland.lua + config/*.lua"
else
    bad "lua syntax error"
fi

grep -q 'require("config.gestures")' "$HYPR/hyprland.lua" \
    && pass "hyprland.lua requires config.gestures" \
    || bad 'require("config.gestures") missing'

# The plan's hard rule: the compositor's native 3-finger horizontal
# workspace swipe is untouched and remains the only hl.gesture in the
# main config (config/gestures.lua registers the rest).
n=$(grep -c 'hl\.gesture' "$HYPR/hyprland.lua" || true)
if [ "$n" = "1" ] \
        && grep -q 'direction = "horizontal"' "$HYPR/hyprland.lua" \
        && grep -q 'action = "workspace"' "$HYPR/hyprland.lua"; then
    pass "native 3-finger horizontal workspace swipe intact (sole hl.gesture)"
else
    bad "native workspace gesture missing/duplicated (hl.gesture count=$n)"
fi

g_line=$(grep -n 'require("config.gestures")' "$HYPR/hyprland.lua" | head -1 | cut -d: -f1)
n_line=$(grep -n 'direction = "horizontal"' "$HYPR/hyprland.lua" | head -1 | cut -d: -f1)
if [ -n "$g_line" ] && [ -n "$n_line" ] && [ "$g_line" -gt "$n_line" ]; then
    pass "gestures.lua is required after the native gesture (line $g_line > $n_line)"
else
    bad "require order: gestures=$g_line native=$n_line"
fi

n=$(grep -c 'SHIFT + Space' "$HYPR/hyprland.lua" || true)
[ "$n" = "1" ] && pass "Super+Shift+Space bound exactly once (workbench keyboard)" \
    || bad "SHIFT+Space bind count=$n"

grep -q 'mainMod .. " + Space", hl.dsp.exec_cmd("qs -c voidshell ipc call launcher toggle")' "$HYPR/hyprland.lua" \
    && pass "Super+Space launcher bind untouched" || bad "launcher bind drifted"

grep -q 'for i = 1, 10 do' "$HYPR/hyprland.lua" \
    && pass "Super+1..0 workspace digit binds untouched (loop present)" \
    || bad "digit workspace bind loop missing"

# ==========================================================================
echo "== compositor: gestures.lua load marker"
rm -f "$MARKER"
if hyprctl reload > /dev/null 2>&1; then
    sleep 1
    if [ -f "$MARKER" ]; then
        pass "gestures.lua ran in the config state: $(cat "$MARKER")"
    else
        bad "marker missing after hyprctl reload — gestures.lua did not run or io is unavailable"
    fi
else
    bad "hyprctl reload failed"
fi

# ==========================================================================
echo "== runtime: exact-PID shell restart with log capture"
stop_shell
setsid qs -c voidshell > "$LOG" 2>&1 </dev/null &
sleep 6
[ "$(count_shell)" = "1" ] && pass "exactly one shell instance" \
    || bad "instance count=$(count_shell)"

echo "== runtime: IPC probes"
[ "$(ipc workbench ping)" = "pong" ] && pass "workbench ping" \
    || bad "workbench ping → $(ipc workbench ping)"
[ "$(ipc gesture ping)" = "pong" ] && pass "gesture ping" \
    || bad "gesture ping → $(ipc gesture ping)"

state=$(ipc workbench state)
echo "    workbench state: $state"
if out=$(json_ok "$state" 's["screen"] != "" and s["pins"] >= 1 and s["slots"] >= s["pins"] and "shown" in s and "mode" in s and "keyboard" in s' 2>&1); then
    pass "state JSON: screen/pins/slots/flags present"
else
    bad "state JSON: $state ${out:+($out)}"
fi

if json_ok "$state" 's["mode"] == "autoHide"'; then
    pass "visibility defaults to autoHide (plan default)"
else
    bad "mode != autoHide: $state"
fi

echo "== cross-check: gesture config ↔ workbench.json ↔ load marker"
blob=$(ipc gesture config)
marker=$(cat "$MARKER" 2>/dev/null || true)
echo "    gesture config: $blob"
if out=$(python3 - "$blob" "$marker" "$JSON" 2>&1 <<'PY'
import json, re, sys

blob = json.loads(sys.argv[1])
marker = sys.argv[2]
path = sys.argv[3]

try:
    text = open(path, encoding="utf-8").read()
except OSError:
    text = ""

def fnum(key, default):
    m = re.search('"%s"\\s*:\\s*(-?[0-9.]+)' % re.escape(key), text)
    return float(m.group(1)) if m else float(default)

def fstr(key, default):
    m = re.search('"%s"\\s*:\\s*"([^"]+)"' % re.escape(key), text)
    return m.group(1) if m else default

# marker keys are short: activation/commit/velocity/cooldown/profile/armed
short = {"activationDistance": "activation", "commitThreshold": "commit",
         "velocityThreshold": "velocity", "cooldown": "cooldown"}
mk = dict(re.findall(r"([A-Za-z_][A-Za-z0-9_]*)=([-\w.,]+)", marker))
errs = []

for jkey, mkey in short.items():
    fv = fnum(jkey, blob[jkey])   # file value; a missing file defaults to the shell value
    if abs(float(blob[jkey]) - fv) > 1e-6:
        errs.append("shell %s=%s vs file %s" % (jkey, blob[jkey], fv))
    if marker and mkey in mk and abs(float(mk[mkey]) - fv) > 1e-6:
        errs.append("lua %s=%s vs file %s" % (mkey, mk[mkey], fv))

fprofile = fstr("gestureProfile", blob["profile"])
if blob["profile"] != fprofile:
    errs.append("shell profile=%s vs file %s" % (blob["profile"], fprofile))
if marker and "profile" in mk and mk["profile"] != fprofile:
    errs.append("lua profile=%s vs file %s" % (mk["profile"], fprofile))

if marker and "armed" in mk:
    armed = [x == "true" for x in mk["armed"].split(",")]
    want = [bool(blob["enable"][k]) for k in ("stage", "dashboard", "special", "zoom")]
    if armed != want:
        errs.append("lua armed=%s vs shell enable=%s" % (armed, want))

if errs:
    print("\n".join(" MISMATCH: " + e for e in errs))
    sys.exit(1)
print("    all three agree: activation=%s commit=%s velocity=%s cooldown=%s profile=%s"
      % (blob["activationDistance"], blob["commitThreshold"],
         blob["velocityThreshold"], blob["cooldown"], fprofile))
PY
); then
    pass "one threshold table across shell, file and compositor"
    [ -n "$out" ] && echo "$out"
else
    bad "threshold cross-check failed"
    [ -n "$out" ] && echo "$out"
fi

echo "== runtime: layer baseline (autoHide at rest)"
if json_ok "$state" 's["fullscreen"]'; then
    echo "    (fullscreen focused — resting edge/dock assertions skipped)"
else
    [ "$(count voidshell-workbench-edge)" = "1" ] \
        && pass "edge reveal strip present (visible accent line, never an invisible blocker)" \
        || bad "edge strip count=$(count voidshell-workbench-edge)"
    [ "$(count voidshell-workbench)" = "0" ] \
        && pass "resting dock hidden (autoHide)" \
        || bad "dock visible at rest: $(count voidshell-workbench)"
fi
if [ "$(count voidshell-workbench-preview)" = "0" ] && [ "$(count voidshell-workbench-palette)" = "0" ]; then
    pass "no subview layers at rest"
else
    bad "subview layers at rest: preview=$(count voidshell-workbench-preview) palette=$(count voidshell-workbench-palette)"
fi

ensure_window || echo "    (no window available — preview assertions degrade to bounded refusal)"

# ==========================================================================
echo "== runtime: dock reveal / hide (IPC)"
ipc workbench show > /dev/null
sleep 1
[ "$(count voidshell-workbench)" = "1" ] && pass "show → dock layer up" \
    || bad "dock layer after show: $(count voidshell-workbench)"
s=$(ipc workbench state)
if json_ok "$s" 's["shown"] and s["source"] == "ipc"'; then
    pass "state.shown=true source=ipc"
else
    bad "state after show: $s"
fi
ipc workbench hide > /dev/null
sleep 1
[ "$(count voidshell-workbench)" = "0" ] && pass "hide → dock layer gone" \
    || bad "dock survived hide"
grep -q "workbench: dock shown (source=ipc)" "$LOG" \
    && pass "dock reveal logged (source=ipc)" || bad "dock reveal log line missing"

echo "== runtime: preview strip + dismiss (router closes it)"
if [ "$have_window" = "1" ]; then
    ret=$(ipc workbench preview)
    sleep 1.2
    if [ "$(count voidshell-workbench-preview)" = "1" ]; then
        pass "preview strip opens its layer (ret=$ret)"
        [ "$(count voidshell-workbench)" = "1" ] \
            && pass "dock stays up while a subview is open (engaged)" \
            || bad "dock gone under an open preview"
        grep -q "workbench: preview strip shown" "$LOG" \
            && pass "preview strip logged" || bad "preview log line missing"
        ipc gesture commit dismiss > /dev/null
        sleep 0.8
        [ "$(count voidshell-workbench-preview)" = "0" ] \
            && pass "gesture commit dismiss retires the strip" \
            || bad "strip survived dismiss"
        sleep 1.7
        [ "$(count voidshell-workbench)" = "0" ] \
            && pass "released hold retreats the dock after hideDelay" \
            || bad "dock did not retreat after dismiss"
    else
        bad "preview layer missing (ret=$ret): $(ipc workbench state)"
    fi
else
    ipc workbench preview > /dev/null
    sleep 1
    [ "$(count voidshell-workbench-preview)" = "0" ] \
        && pass "preview bounded: refuses to open with no windows" \
        || bad "preview opened with no windows"
fi

echo "== runtime: action palette"
ret=$(ipc workbench menu)
sleep 1.2
if [ "$(count voidshell-workbench-palette)" = "1" ]; then
    pass "palette opens its layer (ret=$ret)"
    grep -q "workbench: action palette shown" "$LOG" \
        && pass "palette logged" || bad "palette log line missing"
    ipc workbench hide > /dev/null
    sleep 1
    if [ "$(count voidshell-workbench-palette)" = "0" ] && [ "$(count voidshell-workbench)" = "0" ]; then
        pass "hide retires palette and dock together"
    else
        bad "palette/dock survived hide: palette=$(count voidshell-workbench-palette) dock=$(count voidshell-workbench)"
    fi
else
    bad "palette layer missing (ret=$ret) — favorites must expose real desktop actions"
fi

echo "== runtime: keyboard mode (Super+Shift+Space target)"
ipc workbench keyboard > /dev/null
sleep 0.8
s=$(ipc workbench state)
if json_ok "$s" 's["keyboard"]'; then
    pass "keyboard mode engaged (dock holds Exclusive focus, arrows drive it)"
else
    bad "keyboard flag false: $s"
fi
[ "$(count voidshell-workbench)" = "1" ] && pass "dock up in keyboard mode" \
    || bad "dock missing in keyboard mode"
ipc workbench keyboard > /dev/null
sleep 0.5
s=$(ipc workbench state)
if json_ok "$s" 'not s["keyboard"]'; then
    pass "second call exits keyboard mode"
else
    bad "keyboard stuck: $s"
fi
ipc workbench hide > /dev/null   # deterministic cleanup for the gesture section
sleep 0.6

echo "== runtime: gesture router end to end (committed intents only)"
ipc gesture commit overview > /dev/null
sleep 1
[ "$(count voidshell-overview)" = "1" ] && pass "commit overview → overview opens" \
    || bad "overview=$(count voidshell-overview) after commit"

ipc gesture commit workbench > /dev/null
sleep 1
ov=$(count voidshell-overview); dk=$(count voidshell-workbench)
[ "$ov" = "0" ] && [ "$dk" = "1" ] \
    && pass "commit workbench over an open overview: overview closed, dock up (atomic, never stacked)" \
    || bad "atomicity broken: overview=$ov dock=$dk"

ipc gesture commit workbenchHide > /dev/null
sleep 1
[ "$(count voidshell-workbench)" = "0" ] && pass "commit workbenchHide retreats the dock" \
    || bad "dock survived workbenchHide"

ipc gesture commit overview > /dev/null
sleep 1
[ "$(count voidshell-overview)" = "1" ] && pass "commit overview again opens it" \
    || bad "overview did not reopen"
ipc gesture commit overview > /dev/null
sleep 1
[ "$(count voidshell-overview)" = "0" ] && pass "next overview commit toggles it closed" \
    || bad "overview stuck open"

ipc gesture commit stageNext > /dev/null
sleep 0.8
grep -q "stage intent ignored (shelf disabled)" "$LOG" \
    && pass "stageNext refused while shelf disabled (never faked)" \
    || bad "stage refusal not logged"

ipc gesture commit bogus > "$TMP/bogus.out" 2>&1
sleep 0.5
grep -q "refused unknown intent 'bogus'" "$LOG" \
    && pass "unknown intent refused and logged" \
    || bad "unknown intent not refused"
grep -q "workbench: dock shown (source=gesture)" "$LOG" \
    && pass "gesture-sourced reveal logged" || bad "gesture reveal log line missing"

gs=$(ipc gesture state)
echo "    gesture state: $gs"
if json_ok "$gs" 's["commits"] >= 6 and s["retargets"] == 0'; then
    pass "commit counter advanced (>=6), no spurious retargets"
else
    bad "gesture state: $gs"
fi

echo "== runtime: main log"
log_clean "$LOG" "restart+sequence"

# ==========================================================================
echo "== runtime: VOID_WORKBENCH=preview QA hook"
stop_shell
setsid env VOID_WORKBENCH=preview qs -c voidshell > "$TMP/qa.log" 2>&1 </dev/null &
sleep 7
[ "$(count_shell)" = "1" ] && pass "QA: exactly one instance" \
    || bad "QA instance count=$(count_shell)"
[ "$(count voidshell-workbench)" = "1" ] && pass "QA: dock revealed on start" \
    || bad "QA: dock=$(count voidshell-workbench)"
s=$(ipc workbench state)
if json_ok "$s" 's["previewKey"] != ""'; then
    [ "$(count voidshell-workbench-preview)" = "1" ] \
        && pass "QA: preview strip up (qaHold keeps it past hideDelay)" \
        || bad "QA: preview=$(count voidshell-workbench-preview)"
else
    echo "    (no previewable slot — QA preview layer not asserted: $s)"
fi
log_clean "$TMP/qa.log" "QA"
release_window

# ==========================================================================
echo "== integration: house coord-check (one-primary rule with Workbench loaded)"
if "$ROOT/scripts/coord-check.sh" > "$TMP/coord.out" 2>&1; then
    if grep -q "PHASE-F-PROBE-PASS" "$TMP/coord.out"; then
        pass "coord-check: PHASE-F-PROBE-PASS"
    else
        bad "coord-check exited 0 without its PASS marker"
    fi
else
    bad "coord-check failed:"
    tail -30 "$TMP/coord.out" | sed 's/^/    /'
fi

# ==========================================================================
echo "== repos: current status minus the saved baseline"
INTENDED_QS='^(modules/Workbench/|services/WorkbenchSettings\.qml|services/WindowActions\.qml|services/DesktopNavigationStore\.qml|services/ApplicationStore\.qml|services/ContextActionRegistry\.qml|services/WorkbenchController\.qml|services/SurfaceCoordinator\.qml|services/GestureRouter\.qml|scripts/workbench-check\.sh)$'
INTENDED_HYPR='^(hypr/.config/hypr/hyprland\.lua|hypr/.config/hypr/config/gestures\.lua)$'

if [ -f "$BASE/voidshell-status.txt" ]; then
    git -C "$ROOT" status --porcelain | sed 's/^...//' | LC_ALL=C sort -u > "$TMP/qs.now"
    sed 's/^...//' "$BASE/voidshell-status.txt" | LC_ALL=C sort -u > "$TMP/qs.base"
    LC_ALL=C comm -13 "$TMP/qs.base" "$TMP/qs.now" > "$TMP/qs.new"
    stray=$(grep -Ev "$INTENDED_QS" "$TMP/qs.new" || true)
    if [ -z "$stray" ]; then
        pass "voidshell repo: only plan paths changed ($(grep -c . "$TMP/qs.new") new paths)"
    else
        bad "voidshell repo changed outside the plan:"
        echo "$stray" | sed 's/^/    /'
    fi
    missing=""
    for p in "modules/Workbench/" services/WorkbenchSettings.qml services/WindowActions.qml \
             services/DesktopNavigationStore.qml services/ApplicationStore.qml \
             services/ContextActionRegistry.qml services/WorkbenchController.qml \
             services/SurfaceCoordinator.qml services/GestureRouter.qml \
             scripts/workbench-check.sh; do
        grep -qxF "$p" "$TMP/qs.new" || missing="$missing $p"
    done
    [ -z "$missing" ] && pass "every intended voidshell path present in status" \
        || bad "missing from status:$missing"
else
    bad "baseline voidshell status not found at $BASE"
fi

if [ -f "$BASE/hypr-status.txt" ]; then
    git -C "$HOME/dotfiles" status --porcelain | sed 's/^...//' | LC_ALL=C sort -u > "$TMP/hy.now"
    sed 's/^...//' "$BASE/hypr-status.txt" | LC_ALL=C sort -u > "$TMP/hy.base"
    LC_ALL=C comm -13 "$TMP/hy.base" "$TMP/hy.now" > "$TMP/hy.new"
    stray=$(grep -Ev "$INTENDED_HYPR" "$TMP/hy.new" || true)
    if [ -z "$stray" ]; then
        pass "dotfiles repo: only plan paths changed ($(grep -c . "$TMP/hy.new") new paths)"
    else
        bad "dotfiles repo changed outside the plan:"
        echo "$stray" | sed 's/^/    /'
    fi
    grep -qxF "hypr/.config/hypr/config/gestures.lua" "$TMP/hy.new" \
        && pass "gestures.lua present as a new path" \
        || bad "gestures.lua missing from status"
else
    bad "baseline hypr status not found at $BASE"
fi

# ==========================================================================
echo "== final: clean session restore"
stop_shell
setsid qs -c voidshell > "$TMP/final.log" 2>&1 </dev/null &
sleep 6
[ "$(count_shell)" = "1" ] && pass "exactly one instance, no QA env" \
    || bad "final instance count=$(count_shell)"
log_clean "$TMP/final.log" "final"
[ "$(ipc workbench ping)" = "pong" ] && pass "final instance serves workbench IPC" \
    || bad "final workbench IPC dead"
[ "$(ipc gesture ping)" = "pong" ] && pass "final instance serves gesture IPC" \
    || bad "final gesture IPC dead"
[ "$(count voidshell-workbench)" = "0" ] && pass "dock left hidden after restore" \
    || bad "dock visible after restore"

echo "== physical verification (needs your touchpad — no input injection here)"
cat <<'NOTES'
  1. 3-finger swipe left/right → workspace changes with the native animation.
  2. 3-finger swipe up → overview; down → dock reveals; keep pushing down →
     keyboard mode; release → dock stays ~hideDelay then retreats;
     pull back to the start → hides. Never auto-launches anything.
  3. Two-finger scroll → scrolls, never switches workspaces.
  4. Edge strip → hover the bottom-centre line: dock reveals after
     edgeRevealDelay; with nothing hovered it retreats after hideDelay.
  5. Hover slots → subtle magnify + tooltip after 450ms; left click focuses
     (MRU/cycle), middle click new instance, right click real-action palette.
  6. Drag a pin past 14px → placeholder ring → drop persists (dockOrder in
     workbench.json); Escape mid-drag reverts; dropping never unpins.
  7. Super+Shift+Space → keyboard mode; ←/→ move, Enter activates,
     ↑ opens previews, ↓ opens the palette, Escape exits the layer.
  8. gestureProfile=power in workbench.json + hyprctl reload:
     4-finger L/R steps projects, 4-finger up toggles Dashboard,
     4-finger down toggles the magic special workspace, 2-finger pinch
     zooms the cursor. The default minimal profile keeps all four off.
  9. Fullscreen app → resting dock and edge strip stay suppressed; a
     deliberate Super+Shift+Space reveal still appears; pointer-locked
     games keep their lock; the Dashboard gesture stays refused.
 10. Multi-monitor: the dock follows the focused monitor; only one
     Workbench exists at a time.
NOTES

[ "$fail" = "0" ] && echo "WORKBENCH-GATE-PASS" || echo "WORKBENCH-GATE-FAIL"
exit "$fail"
