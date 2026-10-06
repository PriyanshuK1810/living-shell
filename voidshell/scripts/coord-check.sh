#!/bin/bash
# Phase F gate: one primary popup at a time, untouched bar, clean log.
#
# Drives the shell's own IPC targets in sequence against a freshly
# restarted instance and asserts that opening one surface always closes
# the previous one (the one-primary-popup rule), that the three bar
# islands keep their exact geometry (clock untouched), and that a
# single-instance shell logs no warnings at all.
#
# Related gates: scripts/popup-check.sh (each popup alone),
# scripts/tab-check.sh (every dashboard tab),
# scripts/shelf-check.sh (Stage shelf suppression + opt-in).
#
# Everything runs in ONE invocation (background processes do not survive
# across separate shell calls). Expect PHASE-F-PROBE-PASS last.
set -u
TMP=${TMPDIR:-/tmp}/voidcoord-check
mkdir -p "$TMP"
LOG=$TMP/coord.log
fail=0

pass() { echo "PASS: $*"; }
bad()  { echo "FAIL: $*"; fail=1; }

# --- second-workspace fixture -------------------------------------------
# The Island-hook sub-gate needs a *second* workspace to switch to; on a
# session with a single occupied workspace it prints a skip instead.
# Provision one temporary window on workspace 2 when there is none, and
# remove it again (by the exact pid started here) before the session is
# reported, so the hook is exercised rather than skipped.
TEMP_PID=""
ensure_second_workspace() {
    local n orig
    n=$(hyprctl -j workspaces | python3 -c 'import json,sys; print(sum(1 for w in json.load(sys.stdin) if w.get("windows", 0) > 0))')
    [ "$n" -ge 2 ] && { echo "== second-workspace fixture: session already has $n occupied workspaces"; return 0; }
    command -v kitty > /dev/null || { echo "== second-workspace fixture: no kitty, Island sub-gate will skip"; return 1; }
    orig=$(hyprctl -j activeworkspace | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
    hyprctl dispatch 'hl.dsp.focus({ workspace = 2 })' > /dev/null 2>&1
    sleep 1
    setsid kitty --class voidshard-probe > /dev/null 2>&1 </dev/null &
    sleep 4
    TEMP_PID=$(hyprctl -j clients | python3 -c 'import json,sys; c=[x for x in json.load(sys.stdin) if x["class"] == "voidshard-probe"]; print(c[0]["pid"] if c else "")')
    hyprctl dispatch "hl.dsp.focus({ workspace = $orig })" > /dev/null 2>&1
    sleep 1
    if [ -n "$TEMP_PID" ]; then
        echo "== second-workspace fixture: temporary window pid=$TEMP_PID on workspace 2"
        return 0
    fi
    echo "== second-workspace fixture: could not create a window"
    return 1
}
release_fixture() {
    [ -n "$TEMP_PID" ] || return 0
    kill "$TEMP_PID" 2>/dev/null
    sleep 2
    echo "== second-workspace fixture: released pid=$TEMP_PID"
    TEMP_PID=""
}

count() { hyprctl layers | grep -c "namespace: $1," || true; }

# Every surface that may own the screen as the "primary" view: the
# PopupShell panels, the overview, the launcher, the media panel, the
# lock surface, the Stage shelf and the Living State Island. Invariant:
# at most one of them is ever up at a time (the shelf is suppressed
# rather than replaced — scripts/shelf-check.sh asserts that half in
# isolation).
primary_total() {
    echo $(( $(count voidshell-popup) + $(count voidshell-overview) \
            + $(count voidshell-launcher) + $(count voidshell-lock) \
            + $(count voidshell-media) + $(count voidshell-shelf) \
            + $(count voidshell-island) ))
}

expect_primary() {
    # expect_primary <expected-total> <expected-detail> <label>
    local want=$1 detail=$2 label=$3
    local got total
    got=$(primary_total)
    total=$got
    if [ "$total" != "$want" ]; then
        bad "$label: primary surfaces=$total, expected $want"
        hyprctl layers | grep voidshell | sed 's/^/    /'
        return
    fi
    if [ -n "$detail" ] && [ "$detail" != "any" ]; then
        local n
        n=$(count "$detail")
        if [ "$n" != "1" ]; then
            bad "$label: $detail layers=$n, expected 1"
            return
        fi
    fi
    pass "$label ($total primary, ${detail:-any})"
}

bar_geometry_ok() {
    local want="18 10 529 56, a: 1|555 10 170 56, a: 1|733 10 529 56, a: 1"
    local got
    got=$(hyprctl layers | grep "namespace: voidshell-bar," | sed 's/.*xywh: //; s/, namespace.*//' | paste -sd'|' -)
    if [ "$got" = "$want" ]; then
        pass "bar islands keep their exact geometry (left/clock/right untouched)"
    else
        bad "bar geometry drifted: $got"
    fi
}

echo "== restarting the shell with log capture"
if pgrep -x qs > /dev/null; then
    cmd=$(tr '\0' ' ' < "/proc/$(pgrep -x qs | head -1)/cmdline")
    case "$cmd" in
        "qs -c voidshell"*) say="stopping live instance"; echo "== $say: $cmd" ;;
        *) echo "== unexpected live process: $cmd"; bad "unexpected live process before the probe" ;;
    esac
fi
pkill -x qs
sleep 2
setsid qs -c voidshell > "$LOG" 2>&1 </dev/null &
sleep 6
n=$(pgrep -x qs | wc -l)
[ "$n" = "1" ] && pass "exactly one shell instance" || bad "instance count=$n"
ensure_second_workspace && have_fixture=1 || have_fixture=0

echo "== one primary popup at a time"
expect_primary 0 "" "baseline: nothing open"

qs -c voidshell ipc call dashboard toggle
sleep 1.2
expect_primary 1 voidshell-popup "dashboard open"

qs -c voidshell ipc call overview toggle
sleep 1.2
expect_primary 1 voidshell-overview "overview replaces the dashboard"

qs -c voidshell ipc call taskManager toggle
sleep 1.2
expect_primary 1 voidshell-popup "task manager replaces the overview"

qs -c voidshell ipc call taskManager toggle
sleep 1.2
expect_primary 0 "" "task manager closes"

qs -c voidshell ipc call launcher toggle
sleep 1.2
expect_primary 1 voidshell-launcher "launcher open"

qs -c voidshell ipc call overview toggle
sleep 1.2
expect_primary 1 voidshell-overview "overview replaces the launcher"

qs -c voidshell ipc call media toggle
sleep 1.2
expect_primary 1 voidshell-media "media replaces the overview"

qs -c voidshell ipc call launcher toggle
sleep 1.2
expect_primary 1 voidshell-launcher "launcher replaces the media panel"

qs -c voidshell ipc call launcher toggle
sleep 1.2
expect_primary 0 "" "everything closed"

echo "== Living State Island joins the one-primary rule"
qs -c voidshell ipc call island stack
sleep 1.2
expect_primary 1 voidshell-island "island activity stack opens"

qs -c voidshell ipc call dashboard toggle
sleep 1.2
expect_primary 1 voidshell-popup "dashboard replaces the island"

qs -c voidshell ipc call island stack
sleep 1.2
expect_primary 1 voidshell-island "island replaces the dashboard"

qs -c voidshell ipc call island context 'voidshell/none'
sleep 1.2
expect_primary 1 voidshell-island "island context card replaces the stack"

qs -c voidshell ipc call island close
sleep 1.2
expect_primary 0 "" "island closes"

echo "== bar + runtime"
bar_geometry_ok

grep -q "workspaces pill footprint changed" "$LOG" \
    && bad "workspaces pill footprint drifted" \
    || pass "workspaces pill footprint stable"

warn=$(grep -E "WARN|ERROR" "$LOG" | grep -vcE "notification server|Registration will be" || true)
if [ "$warn" = "0" ]; then
    pass "0 QML WARN/ERROR in the restart + sequence log"
else
    bad "$warn warnings in the log:"
    grep -E "WARN|ERROR" "$LOG" | sed 's/^/    /'
fi

dup=$(grep -c "Could not register notification server" "$LOG" || true)
[ "$dup" = "0" ] && pass "single notification server (no duplicate provider)" \
    || bad "notification server registered $dup times"

n=$(pgrep -x qs | wc -l)
[ "$n" = "1" ] && pass "still exactly one shell instance" || bad "instance count=$n after the sequence"

echo "== Island announcement hook (islandAnnouncements, default on)"
CFG=$HOME/.local/share/voidshell/desktop-manager.json
BAK=$TMP/desktop-manager.json.bak
LOGI=$TMP/island.log
had_cfg=0
restored=0
if [ -f "$CFG" ]; then
    cp -p "$CFG" "$BAK"
    had_cfg=1
fi
restore_cfg() {
    [ "$restored" = "1" ] && return 0
    restored=1
    if [ "$had_cfg" = "1" ] && [ -f "$BAK" ]; then
        cp -p "$BAK" "$CFG"
    else
        rm -f "$CFG"
    fi
}
trap restore_cfg EXIT

active_id=$(hyprctl activeworkspace -j | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
active_name=$(hyprctl activeworkspace -j | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])')
active_win=$(hyprctl activewindow -j | python3 -c 'import json,sys; print(json.load(sys.stdin).get("address",""))')
other=$(hyprctl workspaces -j | python3 -c "
import json, sys
want = $active_id
for w in json.load(sys.stdin):
    if w['id'] != want:
        print(str(w['id']) + ' ' + w['name'])
        break
")

if [ -z "$other" ]; then
    echo "  (only one workspace exists — nothing to switch to, hook not exercised)"
else
    other_id=${other%% *}
    other_name=${other#* }
    mkdir -p "$(dirname "$CFG")"
    cat > "$CFG" <<JSON
{
  "version": 1,
  "islandAnnouncements": true
}
JSON
    pkill -x qs
    sleep 2
    setsid qs -c voidshell > "$LOGI" 2>&1 </dev/null &
    sleep 6

    hyprctl dispatch "hl.dsp.focus({ workspace = $other_id })" >/dev/null
    sleep 1.5
    if grep -q "island hook: workspace announcement $other_name" "$LOGI"; then
        pass "announcement published for workspace $other_name when the setting is on"
    else
        bad "no announcement in the log for workspace $other_name"
        sed 's/^/    /' "$LOGI"
    fi

    # Put the session exactly back: workspace first, then the window
    # that had focus.
    hyprctl dispatch "hl.dsp.focus({ workspace = $active_id })" >/dev/null
    sleep 1
    if [ -n "$active_win" ] && [ "$active_win" != "null" ]; then
        hyprctl dispatch "hl.dsp.focus({ window = \"address:$active_win\" })" >/dev/null
        sleep 1
    fi
    now_ws=$(hyprctl activeworkspace -j | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])')
    now_win=$(hyprctl activewindow -j | python3 -c 'import json,sys; print(json.load(sys.stdin).get("address",""))')
    [ "$now_ws" = "$active_name" ] && pass "workspace restored ($now_ws)" || bad "workspace is $now_ws, expected $active_name"
    [ "$now_win" = "$active_win" ] && pass "focus restored ($now_win)" || bad "focus is $now_win, expected $active_win"
    warn=$(grep -E "WARN|ERROR" "$LOGI" | grep -vcE "notification server|Registration will be" || true)
    [ "$warn" = "0" ] && pass "island-hook instance log clean" || {
        bad "$warn warnings in the island log"
        grep -E "WARN|ERROR" "$LOGI" | sed 's/^/    /'
    }
fi
restore_cfg

# Leave the session as we found it: one live instance, output tidy.
release_fixture
pkill -x qs
sleep 2
setsid qs -c voidshell >/dev/null 2>&1 </dev/null &
sleep 6
n=$(pgrep -x qs | wc -l)
[ "$n" = "1" ] && pass "session restored (one instance)" || bad "restored instance count=$n"

echo "== session"
hyprctl activeworkspace -j | python3 -c 'import json,sys; print("  active workspace:", json.load(sys.stdin)["name"])'
hyprctl clients -j | python3 -c 'import json,sys; print("  clients:", [(c["workspace"]["name"], c["class"]) for c in json.load(sys.stdin)])'

[ "$fail" = "0" ] && echo "PHASE-F-PROBE-PASS" || echo "PHASE-F-PROBE-FAIL"
exit $fail
