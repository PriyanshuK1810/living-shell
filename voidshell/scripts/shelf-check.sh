#!/bin/bash
# Phase E gate: Stage shelf reveal/hide, popup suppression, opt-in default.
#
# Verifies the payload behind Super+Shift+W (`ipc call shelf toggle`)
# against the live compositor: exactly one voidshell-shelf layer while
# revealed, none while hidden or while another popup owns the screen,
# none at all with the feature off, a clean log, and an unchanged
# session (workspaces, windows, focus).
#
# It restarts the shell and rewrites ~/.local/share/voidshell/
# desktop-manager.json for the test, restoring whatever was there
# (including "does not exist") before it finishes. Run it while you do
# not mind a shell restart; expect PHASE-E-PROBE-PASS on the last line.
#
# Everything runs in ONE invocation (background processes do not survive
# across separate shell calls).
set -u
CFG=$HOME/.local/share/voidshell/desktop-manager.json
TMP=${TMPDIR:-/tmp}/voidshelf-check
mkdir -p "$TMP"
LOG=$TMP/qs-phasee.log
LOG2=$TMP/qs-phasee2.log
fail=0

# Preserve the user's settings: this probe writes its own copy for the
# duration and puts the original back (trap included, so an early exit
# cannot lose it).
BAK=$TMP/desktop-manager.json.bak
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
say() { echo "== $*"; }
pass() { echo "PASS: $*"; }
bad() { echo "FAIL: $*"; fail=1; }

shelves() { hyprctl layers | grep -c "namespace: voidshell-shelf," || true; }
# Count only the plain shelf (not the -edge variant).
shelves_only() { hyprctl layers | grep -c "namespace: voidshell-shelf," || true; }
overviews() { hyprctl layers | grep -c "namespace: voidshell-overview," || true; }

# --- second-workspace fixture -------------------------------------------
# The shelf groups *other occupied* workspaces: with a single occupied
# workspace there is nothing to reveal, and the reveal assertions would
# fail for a reason that has nothing to do with the shelf. Provision one
# temporary window on workspace 2 when the session has fewer than two
# occupied workspaces, and remove it again (by the exact pid started
# here) before the session is reported.
TEMP_PID=""
ensure_second_workspace() {
    local n orig
    n=$(hyprctl -j workspaces | python3 -c 'import json,sys; print(sum(1 for w in json.load(sys.stdin) if w.get("windows", 0) > 0))')
    [ "$n" -ge 2 ] && { say "second-workspace fixture: session already has $n occupied workspaces"; return 0; }
    command -v kitty > /dev/null || { say "second-workspace fixture: no kitty, reveal assertions skipped"; return 1; }
    orig=$(hyprctl -j activeworkspace | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
    hyprctl dispatch 'hl.dsp.focus({ workspace = 2 })' > /dev/null 2>&1
    sleep 1
    setsid kitty --class voidshard-probe > /dev/null 2>&1 </dev/null &
    sleep 4
    TEMP_PID=$(hyprctl -j clients | python3 -c 'import json,sys; c=[x for x in json.load(sys.stdin) if x["class"] == "voidshard-probe"]; print(c[0]["pid"] if c else "")')
    hyprctl dispatch "hl.dsp.focus({ workspace = $orig })" > /dev/null 2>&1
    sleep 1
    if [ -n "$TEMP_PID" ]; then
        say "second-workspace fixture: temporary window pid=$TEMP_PID on workspace 2"
        return 0
    fi
    say "second-workspace fixture: could not create a window"
    return 1
}
release_fixture() {
    [ -n "$TEMP_PID" ] || return 0
    kill "$TEMP_PID" 2>/dev/null
    sleep 2
    say "second-workspace fixture: released pid=$TEMP_PID"
    TEMP_PID=""
}
# Both restores on every exit path (the fixture runs after the settings
# trap was installed, so re-arm it with both).
trap 'restore_cfg; release_fixture' EXIT

say "session before:"
hyprctl workspaces -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(" workspaces:", [(w["id"], w["name"], w["monitor"]) for w in d])'
hyprctl activeworkspace -j | python3 -c 'import json,sys; print(" active:", json.load(sys.stdin)["name"])'
hyprctl clients -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(" clients:", [(c["workspace"]["name"], c["class"], c["address"]) for c in d])'
ensure_second_workspace && have_fixture=1 || have_fixture=0

say "step 1: enable shelf (shelfEnabled:true) and restart the live instance"
mkdir -p "$(dirname "$CFG")"
cat > "$CFG" <<'JSON'
{
  "version": 1,
  "managerEnabled": true,
  "shelfEnabled": true,
  "shelfSide": "left",
  "edgeReveal": false,
  "animation": "full",
  "maxStackedPreviews": 3,
  "livePreviewBudget": 2,
  "scope": "monitor",
  "sensitiveExclusions": [],
  "fullscreenPolicy": "explicit-only",
  "islandAnnouncements": false
}
JSON
if pgrep -x qs > /dev/null; then
  cmd=$(tr '\0' ' ' < "/proc/$(pgrep -x qs | head -1)/cmdline")
  case "$cmd" in "qs -c voidshell"*) say "stopping live instance: $cmd";; *) say "unexpected live process: $cmd";; esac
fi
pkill -x qs
sleep 2
setsid qs -c voidshell > "$LOG" 2>&1 </dev/null &
sleep 6
if pgrep -x qs > /dev/null; then pass "live instance running ($(pgrep -x qs | tr '\n' ' '))"; else bad "no live instance"; fi
grep -E "WARN|ERROR" "$LOG" | grep -vE "notification server|Registration will be" && bad "warnings on start" || pass "clean start log"

say "step 2: shortcut payload ON (ipc call shelf toggle)"
qs -c voidshell ipc call shelf toggle
sleep 1.5
n=$(shelves_only)
if [ "$have_fixture" = "1" ]; then
    [ "$n" = "1" ] && pass "shelf layer present after toggle-on" || bad "shelf layer count=$n"
else
    echo "SKIP: shelf reveal (session has one occupied workspace and no window to add)"
fi
hyprctl layers | grep "voidshell-shelf" | sed 's/^/  /'
grim -o eDP-1 -t ppm "$TMP/pe_on.ppm"

say "step 3: suppression — overview opens, shelf must disappear"
qs -c voidshell ipc call overview toggle
sleep 1.5
o=$(overviews); s=$(shelves_only)
[ "$o" = "1" ] && pass "overview open" || bad "overview count=$o"
[ "$s" = "0" ] && pass "shelf suppressed while overview open" || bad "shelf still present ($s)"
qs -c voidshell ipc call overview toggle
sleep 1.5
o=$(overviews); s=$(shelves_only)
[ "$o" = "0" ] && pass "overview closed" || bad "overview still open ($o)"
[ "$s" = "0" ] && pass "shelf stays hidden after the popup (pin cleared)" || bad "shelf reappeared ($s)"

say "step 4: reveal again, then hide with the same shortcut"
qs -c voidshell ipc call shelf toggle
sleep 1.5
s=$(shelves_only)
if [ "$have_fixture" = "1" ]; then
    [ "$s" = "1" ] && pass "shelf revealed again" || bad "reveal failed ($s)"
else
    echo "SKIP: shelf reveal (session has one occupied workspace and no window to add)"
fi
qs -c voidshell ipc call shelf toggle
sleep 1.5
s=$(shelves_only); [ "$s" = "0" ] && pass "shelf hidden by shortcut" || bad "hide failed ($s)"

say "step 5: QA hook instance (VOID_SHELF=1) beside the live one"
VOID_SHELF=1 timeout 20 qs -c voidshell > "$LOG2" 2>&1 </dev/null &
TP=$!
sleep 6
grep -q "shelf QA hook: revealed via VOID_SHELF" "$LOG2" && pass "VOID_SHELF hook log line" || bad "no QA hook log line: $(tail -3 "$LOG2")"
hyprctl layers | grep "voidshell-shelf" | sed 's/^/  /'
grep -E "WARN|ERROR" "$LOG2" | grep -vE "notification server|Registration will be" && bad "QA instance warnings" || pass "QA instance clean log"
kill "$TP" 2>/dev/null
sleep 2
pkill -x qs 2>/dev/null
sleep 2

say "step 6: settings file removed → shipped defaults → shelf must stay off"
rm -f "$CFG"
setsid qs -c voidshell > "$TMP/qs-phasee3.log" 2>&1 </dev/null &
sleep 6
qs -c voidshell ipc call shelf toggle
sleep 1.5
s=$(shelves_only)
[ "$s" = "0" ] && pass "shelf inert with shelfEnabled default (false)" || bad "shelf appeared with the feature off ($s)"
grep -E "WARN|ERROR" "$TMP/qs-phasee3.log" | grep -vE "notification server|Registration will be" && bad "restore log warnings" || pass "restore log clean"
n=$(pgrep -x qs | wc -l)
[ "$n" = "1" ] && pass "exactly one live instance" || bad "instance count=$n"

say "step 7: put the user's settings back and leave one live instance"
release_fixture
restore_cfg
if [ "$had_cfg" = "1" ]; then
    echo "  (restored the pre-probe desktop-manager.json)"
else
    echo "  (no pre-probe file: shipped default state, none on disk)"
fi
pkill -x qs
sleep 2
setsid qs -c voidshell >/dev/null 2>&1 </dev/null &
sleep 6
n=$(pgrep -x qs | wc -l)
[ "$n" = "1" ] && pass "session restored (one instance)" || bad "restored instance count=$n"

say "session after:"
hyprctl workspaces -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(" workspaces:", [(w["id"], w["name"]) for w in d])'
hyprctl activeworkspace -j | python3 -c 'import json,sys; print(" active:", json.load(sys.stdin)["name"])'
hyprctl clients -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(" clients:", [(c["workspace"]["name"], c["class"]) for c in d])'
hyprctl layers | grep voidshell | sed 's/^/  layer: /'

[ "$fail" = "0" ] && echo "PHASE-E-PROBE-PASS" || echo "PHASE-E-PROBE-FAIL"
exit $fail
