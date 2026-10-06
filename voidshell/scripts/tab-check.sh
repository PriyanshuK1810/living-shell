#!/usr/bin/env bash
# Phase QA: open the dashboard on each tab via VOID_TAB and require a clean log.
set -u
cd /home/Priyanshu/.config/quickshell/voidshell || exit 1
TABS="overview media weather alerts productivity"
fail=0
mkdir -p /tmp/voidqa
for t in $TABS; do
    log="/tmp/voidqa/tab-$t.log"
    VOID_POPUP=dashboard VOID_TAB="$t" timeout 15 qs -c voidshell > "$log" 2>&1 &
    pid=$!
    sleep 7
    wait "$pid"; rc=$?
    bad=$(grep -cE "WARN|ERROR|Binding loop" "$log")
    status="ok"
    [ "$rc" != "124" ] && { status="exit=$rc"; fail=1; }
    [ "$bad" != "0" ] && { status="$status issues=$bad"; fail=1; }
    echo "tab $t: $status"
done
if [ "$fail" = "0" ]; then echo "TAB-CHECK-PASS"; else echo "TAB-CHECK-FAIL"; fi
exit $fail
