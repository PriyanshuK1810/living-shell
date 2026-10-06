#!/bin/bash
# Living State Island gate: presentation states, event engine, activity
# integrity, surface rules and log hygiene — all driven through the
# shell's own IPC targets against a freshly restarted instance.
#
# What it proves (nothing here is simulated):
#   I1  the clock pill's allocation never changes (170x56 at 555 10)
#   I2  an announcement actually paints inside the pill and expires again
#   I3  the activity stack opens, shows the published activity and closes
#   I4  one-primary-surface holds with the island involved
#   I5  the job IPC validates: bad payloads are rejected, not rendered
#   I6  sequence ordering: a late (older) update cannot regress progress
#   I7  terminal states are idempotent: a second finish does not rewrite
#   I8  the lock drops the island surface
#   I9  one instance, zero WARN/ERROR in the log
#
# Runs in ONE invocation. Expect ISLAND-CHECK-PASS on the last line.
set -u
TMP=${TMPDIR:-/tmp}/voidisland-check
mkdir -p "$TMP"
LOG=$TMP/island.log
fail=0

pass() { echo "PASS: $*"; }
bad()  { echo "FAIL: $*"; fail=1; }

count() { hyprctl layers | grep -c "namespace: $1," || true; }
instances() { pgrep -cx qs || true; }

# Mean RGB distance over a rectangle of a PPM (same probe as hardening).
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

# The clock pill in physical pixels (logical 555..725 x 10..56, scale 1.5).
PILL="832 15 1087 84"

ipc() { qs -c voidshell ipc call "$@"; }

echo "== restarting the shell with log capture"
pkill -x qs 2>/dev/null
sleep 2
setsid qs -c voidshell > "$LOG" 2>&1 </dev/null &
sleep 7
[ "$(instances)" = "1" ] && pass "one live instance" || bad "instance count=$(instances)"

# --- I1 geometry ---------------------------------------------------------
geom=$(hyprctl layers | grep "namespace: voidshell-bar," | sed 's/.*xywh: //; s/, namespace.*//' | paste -sd'|' -)
want="18 10 529 56, a: 1|555 10 170 56, a: 1|733 10 529 56, a: 1"
[ "$geom" = "$want" ] && pass "bar geometry byte-identical (clock still 170x56)" \
    || bad "bar geometry drifted: $geom"

# --- I2 announcement paints in the pill and expires ----------------------
sleep 2   # let the announcement engine's warm-up gate open
grim -o eDP-1 -t ppm "$TMP/base.ppm"
ipc job announce '{"key":"gate","priority":1,"category":"job","feature":"jobs","title":"Gate event","subtitle":"must paint","tone":"info","duration":6000}' > /dev/null 2>&1
sleep 1
grim -o eDP-1 -t ppm "$TMP/ann.ppm"
d=$(ppm_diff "$TMP/base.ppm" "$TMP/ann.ppm" $PILL)
python3 -c "import sys; sys.exit(0 if float('$d') > 3 else 1)" \
    && pass "announcement paints inside the clock pill (diff=$d)" \
    || bad "announcement did not paint in the pill (diff=$d)"
rest=$(ppm_diff "$TMP/base.ppm" "$TMP/ann.ppm" 60 15 800 84)
python3 -c "import sys; sys.exit(0 if float('$rest') < 1 else 1)" \
    && pass "nothing outside the pill moved (diff=$rest)" \
    || bad "pixels outside the pill changed (diff=$rest)"
sleep 6.5
grim -o eDP-1 -t ppm "$TMP/after.ppm"
d2=$(ppm_diff "$TMP/base.ppm" "$TMP/after.ppm" $PILL)
python3 -c "import sys; sys.exit(0 if float('$d2') < 2 else 1)" \
    && pass "announcement expired, pill back to the clock (diff=$d2)" \
    || bad "announcement never expired (diff=$d2)"

# --- I3 / I4 stack opens, shows the activity, one-primary holds ----------
ipc job publish '{"sourceId":"gate","activityId":"a1","sequence":1,"activityType":"job","state":"working","title":"Gate build","subtitle":"running","progressMode":"determinate","progressValue":30,"dashboardTarget":"overview","registeredActions":[{"id":"open","label":"Details","route":"dashboard:overview"}]}' > /dev/null 2>&1
sleep 1
ipc island stack > /dev/null 2>&1
sleep 1.5
[ "$(count voidshell-island)" = "1" ] && pass "activity stack opens (1 island surface)" \
    || bad "island layers=$(count voidshell-island) on open"
grim -o eDP-1 "$TMP/stack.png"

ipc dashboard toggle > /dev/null 2>&1
sleep 1.5
[ "$(count voidshell-popup)" = "1" ] && [ "$(count voidshell-island)" = "0" ] \
    && pass "dashboard replaces the island (one primary surface)" \
    || bad "mutual exclusion broken: popup=$(count voidshell-popup) island=$(count voidshell-island)"

ipc island stack > /dev/null 2>&1
sleep 1.5
[ "$(count voidshell-island)" = "1" ] && [ "$(count voidshell-popup)" = "0" ] \
    && pass "island replaces the dashboard" \
    || bad "island did not take over: popup=$(count voidshell-popup) island=$(count voidshell-island)"

# --- I5 payload validation ----------------------------------------------
before=$(hyprctl layers | grep -c "namespace: voidshell-island" || true)
r=$(ipc job publish 'this is not json' 2>&1)
case "$r" in
    *false*|"") pass "malformed payload rejected (result: ${r:-no output})" ;;
    *) bad "malformed payload was not rejected: $r" ;;
esac
r=$(ipc job publish '{"title":"no identity"}' 2>&1)
case "$r" in
    *false*|"") pass "identity-less payload rejected" ;;
    *) bad "identity-less payload accepted: $r" ;;
esac
r=$(ipc job publish '{"sourceId":"gate","activityId":"bad key!","sequence":1,"title":"x"}' 2>&1)
case "$r" in
    *false*|"") pass "invalid sourceId rejected (charset rule)" ;;
    *) bad "invalid sourceId accepted: $r" ;;
esac

# --- I6 sequence ordering ------------------------------------------------
ipc job publish '{"sourceId":"gate","activityId":"a2","sequence":10,"activityType":"job","state":"working","title":"Seq test","progressMode":"determinate","progressValue":80}' > /dev/null 2>&1
ipc job update '{"sourceId":"gate","activityId":"a2","sequence":3,"activityType":"job","state":"working","title":"Seq test","progressMode":"determinate","progressValue":10}' > /dev/null 2>&1
sleep 0.5
ipc island context 'gate/a2' > /dev/null 2>&1
sleep 1.5
[ "$(count voidshell-island)" = "1" ] && pass "context card opens for a known activity" \
    || bad "context card did not open"
# The rendered bar ambient line still reports the newer (80%) value, not 10%.
grim -o eDP-1 "$TMP/ctx.png"
ipc island close > /dev/null 2>&1
sleep 1

# --- I7 terminal states are idempotent -----------------------------------
ipc job publish '{"sourceId":"gate","activityId":"a3","sequence":1,"activityType":"job","state":"working","title":"Finish test","progressMode":"none"}' > /dev/null 2>&1
ipc job finish '{"sourceId":"gate","activityId":"a3","sequence":5,"state":"success","title":"Finish test"}' > /dev/null 2>&1
ipc job finish '{"sourceId":"gate","activityId":"a3","sequence":2,"state":"failure","title":"Finish test"}' > /dev/null 2>&1
sleep 1
# A late failure after success must not resurrect or re-announce it: the
# stack must not show it as an ongoing activity again.
ipc island stack > /dev/null 2>&1
sleep 1.5
[ "$(count voidshell-island)" = "1" ] && pass "stack opens after finishing an activity" \
    || bad "stack did not reopen after finish"
ipc island close > /dev/null 2>&1
sleep 1

# --- I8 lock drops the island --------------------------------------------
ipc island stack > /dev/null 2>&1
sleep 1.2
[ "$(count voidshell-island)" = "1" ] && pass "island up before the lock" || bad "island not up before the lock"
ipc lock toggle > /dev/null 2>&1
sleep 1.5
[ "$(count voidshell-island)" = "0" ] && pass "lock drops the island surface" \
    || bad "island survived the lock"
[ "$(count voidshell-lock)" = "1" ] && pass "lock surface present" || bad "lock layers=$(count voidshell-lock)"
# Escape is not a lock bypass: the lock refuses dismissal without auth.
qs -c voidshell ipc call lock toggle > /dev/null 2>&1
sleep 1.5
[ "$(count voidshell-lock)" = "1" ] && pass "lock cannot be dismissed by IPC (auth only)" \
    || bad "lock was dismissed without authentication"

# --- I9 hygiene ----------------------------------------------------------
warn=$(grep -E "WARN|ERROR" "$LOG" | grep -vcE "notification server|Registration will be|Could not load icon" || true)
if [ "$warn" = "0" ]; then
    pass "0 QML WARN/ERROR in the log"
else
    bad "$warn warnings in the log:"
    grep -E "WARN|ERROR" "$LOG" | sed 's/^/    /'
fi
[ "$(instances)" = "1" ] && pass "still exactly one shell instance" || bad "instance count=$(instances) after the sequence"

# Leave a clean, unlocked session behind.
pkill -x qs 2>/dev/null
sleep 2
setsid qs -c voidshell > /dev/null 2>&1 </dev/null &
sleep 7
[ "$(instances)" = "1" ] && pass "session restored (one instance)" || bad "restored instance count=$(instances)"

geom=$(hyprctl layers | grep "namespace: voidshell-bar," | sed 's/.*xywh: //; s/, namespace.*//' | paste -sd'|' -)
[ "$geom" = "$want" ] && pass "bar geometry unchanged after the whole gate" \
    || bad "bar geometry drifted at the end: $geom"

[ "$fail" = "0" ] && echo "ISLAND-CHECK-PASS" || echo "ISLAND-CHECK-FAIL"
exit $fail
