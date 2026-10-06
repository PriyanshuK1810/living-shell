#!/usr/bin/env bash
# Phase QA: open each primary popup via VOID_POPUP and require a clean log.
set -u
cd /home/Priyanshu/.config/quickshell/voidshell || exit 1
POPUPS="launcher calendar media quickSettings notifications power dashboard taskManager overview lock"
fail=0
mkdir -p /tmp/voidqa
for p in $POPUPS; do
    log="/tmp/voidqa/popup-$p.log"
    VOID_POPUP="$p" timeout 15 qs -c voidshell > "$log" 2>&1 &
    pid=$!
    sleep 7
    wait "$pid"; rc=$?
    bad=$(grep -cE "WARN|ERROR|Binding loop" "$log")
    status="ok"
    [ "$rc" != "124" ] && { status="exit=$rc"; fail=1; }
    [ "$bad" != "0" ] && { status="$status issues=$bad"; fail=1; }
    echo "popup $p: $status"
done
if [ "$fail" = "0" ]; then echo "POPUP-CHECK-PASS"; else echo "POPUP-CHECK-FAIL"; fi
exit $fail
