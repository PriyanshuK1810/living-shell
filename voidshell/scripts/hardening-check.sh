#!/bin/bash
# Phase G gate: motion modes, lock release, disable switch, reload hygiene.
#
#   M — animation "full" / "reduced" / "off": every (re)start logs the
#       resolved motion line and the surfaces still work in that mode.
#   N — locking drops the overview and releases every preview capture
#       request (the lock path of PreviewController.clear()).
#   P — managerEnabled:false reverts the pill to the numbered strip,
#       keeps the bar geometry byte-identical, keeps the overview and
#       the dashboard available, and leaves the opt-in shelf inert.
#   O — one live instance, three bar layers, a clean log, one Super+W
#       and one Super+Shift+W binding, overview opens/closes once.
#
# It restarts the shell and rewrites ~/.local/share/voidshell/
# desktop-manager.json for the test, restoring whatever was there
# (including "does not exist") before it finishes — trap included, so
# an early exit cannot lose it. Run it while you do not mind a shell
# restart; expect PHASE-G-PROBE-PASS on the last line.
#
# Everything runs in ONE invocation (background processes do not survive
# across separate shell calls).
set -u
CFG=$HOME/.local/share/voidshell/desktop-manager.json
TMP=${TMPDIR:-/tmp}/voidhard-check
mkdir -p "$TMP"
fail=0

# Preserve the user's settings for the duration of the probe.
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
say()  { echo "== $*"; }
pass() { echo "PASS: $*"; }
bad()  { echo "FAIL: $*"; fail=1; }

count()  { hyprctl layers | grep -c "namespace: $1," || true; }
instances() { pgrep -cx qs || true; }

# --- second-workspace fixture -------------------------------------------
# The Stage shelf groups *other occupied* workspaces; with a single
# occupied workspace there is nothing to reveal and the shelf assertions
# would fail for a reason that has nothing to do with the shelf. The
# probe therefore provisions one temporary window on workspace 2 when
# the session has fewer than two occupied workspaces, and removes it
# again (by the exact pid it started) before the session comparison.
TEMP_PID=""
ensure_second_workspace() {
    local n orig
    n=$(hyprctl -j workspaces | python3 -c 'import json,sys; print(sum(1 for w in json.load(sys.stdin) if w.get("windows", 0) > 0))')
    [ "$n" -ge 2 ] && { say "second-workspace fixture: session already has $n occupied workspaces"; return 0; }
    command -v kitty > /dev/null || { say "second-workspace fixture: no kitty, shelf assertions skipped"; return 1; }
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
have_fixture=0
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

# Writes the settings the next restart should pick up:
#   write_settings <animation> <managerEnabled> <shelfEnabled>
write_settings() {
    mkdir -p "$(dirname "$CFG")"
    cat > "$CFG" <<JSON
{
  "version": 1,
  "managerEnabled": $2,
  "shelfEnabled": $3,
  "shelfSide": "left",
  "edgeReveal": false,
  "animation": "$1",
  "maxStackedPreviews": 3,
  "livePreviewBudget": 2,
  "scope": "monitor",
  "sensitiveExclusions": [],
  "fullscreenPolicy": "explicit-only",
  "islandAnnouncements": false
}
JSON
}

# restart_live <log>: stop every instance, start one fresh live shell.
restart_live() {
    pkill -x qs 2>/dev/null
    sleep 2
    setsid qs -c voidshell > "$1" 2>&1 </dev/null &
    sleep 6
}

# Log hygiene: the expected duplicate-notification-server notices when a
# second instance ran, quickshell's icon fallbacks — nothing else.
log_noise() {
    grep -E "WARN|ERROR" "$1" | grep -vE "notification server|Registration will be|Could not load icon" || true
}

# Surface toggles driven through the shell's own IPC targets.
overview() { qs -c voidshell ipc call overview toggle; }
shelf()    { qs -c voidshell ipc call shelf toggle; }
dashboard(){ qs -c voidshell ipc call dashboard toggle; }

# The three bar islands as plain geometry (surface ids and pids change
# on every restart — only the rectangles are the invariant).
bar_geometry() { hyprctl layers | grep "namespace: voidshell-bar," \
    | sed -E 's/Layer [0-9a-f]+: //; s/pid: .*//' | sort; }

# Pill / bar pixel probe: mean RGB distance over a rectangle of a PPM.
#   ppm_diff <a.ppm> <b.ppm> <x0> <y0> <x1> <y1>
ppm_diff() {
    python3 - "$1" "$2" "$3" "$4" "$5" "$6" <<'PY'
import sys
def load(p):
    d = open(p, 'rb').read().split(b'\n', 3)
    w, h = [int(x) for x in d[1].split()]
    return w, h, d[3]
w, h, a = load(sys.argv[1])
_, _, b = load(sys.argv[2])
x0, y0, x1, y1 = (int(v) for v in sys.argv[3:7])
tot = 0
for y in range(y0, y1):
    ra = a[y*w*3:(y+1)*w*3]
    rb = b[y*w*3:(y+1)*w*3]
    for x in range(x0, x1):
        i = x*3
        tot += abs(ra[i]-rb[i]) + abs(ra[i+1]-rb[i+1]) + abs(ra[i+2]-rb[i+2])
print(round(tot / max(1, (x1-x0)*(y1-y0)*3), 3))
PY
}

say "session before:"
hyprctl workspaces -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(" workspaces:", [(w["id"], w["name"]) for w in d])'
hyprctl activeworkspace -j | python3 -c 'import json,sys; print(" active:", json.load(sys.stdin)["name"])'
hyprctl clients -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(" clients:", [(c["workspace"]["name"], c["class"], c["address"]) for c in d])'
BEFORE_WS=$(hyprctl -j activeworkspace | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])')
BEFORE_CLIENTS=$(hyprctl -j clients | python3 -c 'import json,sys; print(sorted((c["workspace"]["name"], c["class"], c["address"]) for c in json.load(sys.stdin)))')
BAR_BEFORE=$(bar_geometry)
ensure_second_workspace && have_fixture=1 || have_fixture=0

# ---------------------------------------------------------------- M ----
say "M: motion modes (each restart must log its resolved motion line)"
declare -A WANT=(
    [full]="motion: mode=full pill=190 hover=140 shelf=210 card=200 fade=160 overview=220"
    [reduced]="motion: mode=reduced pill=0 hover=0 shelf=0 card=0 fade=120 overview=120"
    [off]="motion: mode=off pill=0 hover=0 shelf=0 card=0 fade=0 overview=0"
)
for mode in full reduced off; do
    write_settings "$mode" true true
    restart_live "$TMP/m-$mode.log"
    [ "$(instances)" = "1" ] && pass "[$mode] one live instance" || bad "[$mode] instance count=$(instances)"
    if grep -qF "${WANT[$mode]}" "$TMP/m-$mode.log"; then
        pass "[$mode] motion line: ${WANT[$mode]}"
    else
        bad "[$mode] motion line missing: $(grep -o 'motion: mode=.*' "$TMP/m-$mode.log" | head -1)"
    fi
    n=$(log_noise "$TMP/m-$mode.log")
    [ -z "$n" ] && pass "[$mode] clean log" || bad "[$mode] log noise: $n"

    overview; sleep 1.5
    [ "$(count voidshell-overview)" = "1" ] && pass "[$mode] overview opens" || bad "[$mode] overview did not open"
    overview; sleep 1.5
    [ "$(count voidshell-overview)" = "0" ] && pass "[$mode] overview closes" || bad "[$mode] overview stayed open"
    if [ "$have_fixture" = "1" ]; then
        shelf; sleep 1.5
        [ "$(count voidshell-shelf)" = "1" ] && pass "[$mode] shelf reveals" || bad "[$mode] shelf did not reveal"
        shelf; sleep 1.5
        [ "$(count voidshell-shelf)" = "0" ] && pass "[$mode] shelf hides" || bad "[$mode] shelf stayed up"
    else
        echo "SKIP: [$mode] shelf reveal/hide (session has one occupied workspace and no window to add)"
    fi
done

# ---------------------------------------------------------------- N ----
say "N: lock closes the overview and releases every capture request"
pkill -x qs; sleep 2
VOID_POPUP=overview timeout 40 qs -c voidshell > "$TMP/n-lock.log" 2>&1 </dev/null &
sleep 7
[ "$(instances)" = "1" ] && pass "single instance answers" || bad "instance count=$(instances)"
[ "$(count voidshell-overview)" = "1" ] && pass "overview open before lock" || bad "overview not open before lock"
# The isolated instance owns the overview; lock it through the same
# IPC target the Super bind would use on the live shell.
qs -c voidshell ipc call lock toggle
sleep 2
[ "$(count voidshell-overview)" = "0" ] && pass "overview dropped by the lock" || bad "overview survived the lock"
[ "$(count voidshell-lock)" = "1" ] && pass "lock surface present" || bad "lock layers=$(count voidshell-lock)"
grep -q "preview: released .* capture request(s)" "$TMP/n-lock.log" \
    && pass "capture requests released on lock: $(grep -o 'preview: released .*' "$TMP/n-lock.log")" \
    || bad "no 'preview: released' line in the lock log"
n=$(log_noise "$TMP/n-lock.log")
[ -z "$n" ] && pass "lock instance log clean" || bad "lock instance log noise: $n"
pkill -x qs 2>/dev/null; sleep 2

# ---------------------------------------------------------------- P ----
say "P: managerEnabled:false — legacy pill, same bar, surfaces still there"
write_settings full true false           # dash reference
restart_live "$TMP/p-dash.log"
hyprctl dispatch 'hl.dsp.focus({ workspace = 1 })' >/dev/null 2>&1
sleep 1
grim -o eDP-1 -t ppm "$TMP/p-dash.ppm"
BAR_DASH=$(bar_geometry)

write_settings full false true           # disabled, shelf opted in
restart_live "$TMP/p-legacy.log"
hyprctl dispatch 'hl.dsp.focus({ workspace = 1 })' >/dev/null 2>&1
sleep 1
grim -o eDP-1 -t ppm "$TMP/p-legacy.ppm"
BAR_OFF=$(bar_geometry)

# Pill island (physical px): logical x110..370 -> same at scale 1.5 of
# the left island; the rest of the bar (title pill, x400..820) is the
# control rectangle that must not move.
pill=$(ppm_diff "$TMP/p-dash.ppm" "$TMP/p-legacy.ppm" 110 15 370 99)
rest=$(ppm_diff "$TMP/p-dash.ppm" "$TMP/p-legacy.ppm" 400 15 820 99)
echo "  pill diff=$pill  rest-of-bar diff=$rest"
python3 -c "import sys; sys.exit(0 if float('$pill') > 5 else 1)" \
    && pass "pill painted differently (dash vs numbered strip)" \
    || bad "pill looks the same in both modes (diff=$pill)"
python3 -c "import sys; sys.exit(0 if float('$rest') < 3 else 1)" \
    && pass "rest of the bar pixel-identical" \
    || bad "rest of the bar changed (diff=$rest)"

[ "$BAR_DASH" = "$BAR_OFF" ] && pass "bar layer geometry identical in both modes" || bad "bar layers moved: $BAR_OFF"
[ "$(count voidshell-bar)" = "3" ] && pass "still exactly 3 bar layers" || bad "bar layers=$(count voidshell-bar)"

overview; sleep 1.5
[ "$(count voidshell-overview)" = "1" ] && pass "overview still opens with the manager disabled" || bad "overview dead with managerEnabled:false"
overview; sleep 1.5
[ "$(count voidshell-overview)" = "0" ] && pass "overview closes again" || bad "overview stayed open"
shelf; sleep 1.5
[ "$(count voidshell-shelf)" = "0" ] && pass "shelf inert although shelfEnabled:true (managerEnabled gates it)" || bad "shelf revealed with the manager disabled"
dashboard; sleep 1.5
[ "$(count voidshell-popup)" = "1" ] && pass "dashboard opens with the manager disabled" || bad "dashboard did not open"
dashboard; sleep 1.5
[ "$(count voidshell-popup)" = "0" ] && pass "dashboard closes" || bad "dashboard stayed open"
n=$(log_noise "$TMP/p-legacy.log")
[ -z "$n" ] && pass "disabled-mode log clean" || bad "disabled-mode log noise: $n"
grep -q "workspaces pill footprint changed" "$TMP/p-dash.log" "$TMP/p-legacy.log" \
    && bad "pill footprint drifted" || pass "pill footprint stable in both modes"

# ---------------------------------------------------------------- O ----
say "O: reload hygiene — one instance, three islands, clean log, both binds"
write_settings full true true
restart_live "$TMP/o.log"
[ "$(instances)" = "1" ] && pass "exactly one live instance" || bad "instance count=$(instances)"
[ "$(count voidshell-bar)" = "3" ] && pass "exactly 3 bar layers" || bad "bar layers=$(count voidshell-bar)"
[ "$BAR_BEFORE" = "$(bar_geometry)" ] \
    && pass "bar geometry matches the pre-probe session" || bad "bar geometry differs from the pre-probe session"
overview; sleep 1.5
[ "$(count voidshell-overview)" = "1" ] && pass "overview opens once" || bad "overview did not open"
overview; sleep 1.5
[ "$(count voidshell-overview)" = "0" ] && pass "overview closes clean" || bad "overview left a layer behind"
n=$(log_noise "$TMP/o.log")
[ -z "$n" ] && pass "restart log clean (0 WARN / 0 ERROR)" || bad "restart log noise: $n"
binds=$(python3 - <<'PY'
import subprocess
out = subprocess.check_output(["hyprctl", "binds"], text=True)
mod64 = mod65 = 0
for blk in out.split("bind\n")[1:]:
    key = mod = None
    for line in blk.splitlines():
        line = line.strip()
        if line.startswith("key: "): key = line[5:]
        elif line.startswith("modmask: "): mod = line[9:]
    if key == "W" and mod == "64": mod64 += 1
    if key == "W" and mod == "65": mod65 += 1
print(mod64, mod65)
PY
)
[ "$binds" = "1 1" ] && pass "exactly one Super+W and one Super+Shift+W" || bad "W binds (super, super+shift) = $binds"

# ------------------------------------------------------------ finish ----
say "restoring the user's settings and the live instance"
release_fixture
restore_cfg
if [ "$had_cfg" = "1" ]; then
    echo "  (restored the pre-probe desktop-manager.json)"
else
    echo "  (no pre-probe file: shipped default state, none on disk)"
fi
restart_live "$TMP/final.log"
[ "$(instances)" = "1" ] && pass "one live instance left" || bad "final instance count=$(instances)"
n=$(log_noise "$TMP/final.log")
[ -z "$n" ] && pass "final log clean" || bad "final log noise: $n"

AFTER_WS=$(hyprctl -j activeworkspace | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])')
AFTER_CLIENTS=$(hyprctl -j clients | python3 -c 'import json,sys; print(sorted((c["workspace"]["name"], c["class"], c["address"]) for c in json.load(sys.stdin)))')
[ "$BEFORE_WS" = "$AFTER_WS" ] && pass "active workspace unchanged ($AFTER_WS)" || bad "active workspace $BEFORE_WS -> $AFTER_WS"
[ "$BEFORE_CLIENTS" = "$AFTER_CLIENTS" ] && pass "window-to-workspace mapping unchanged" || bad "windows moved"
[ "$BAR_BEFORE" = "$(bar_geometry)" ] \
    && pass "bar geometry identical to the pre-probe session" || bad "bar geometry drifted"

say "session after:"
hyprctl workspaces -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(" workspaces:", [(w["id"], w["name"]) for w in d])'
hyprctl activeworkspace -j | python3 -c 'import json,sys; print(" active:", json.load(sys.stdin)["name"])'
hyprctl clients -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(" clients:", [(c["workspace"]["name"], c["class"]) for c in d])'

[ "$fail" = "0" ] && echo "PHASE-G-PROBE-PASS" || echo "PHASE-G-PROBE-FAIL"
exit $fail
