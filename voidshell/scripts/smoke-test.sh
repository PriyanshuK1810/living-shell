#!/usr/bin/env bash
# VOID SHELL — smoke test: launch `qs -c voidshell` briefly and fail on
# any QML parser/import/binding error. Timeout-kill (124) is the PASS path.
set -u
LOG="$(mktemp /tmp/voidshell-smoke-XXXXXX.log)"
timeout 8 qs -c voidshell >"$LOG" 2>&1
code="$?"

if grep -qiE "ERROR|ReferenceError|TypeError|is not defined|Failed to load" "$LOG"; then
  echo "SMOKE-FAIL: errors in quickshell log:"
  grep -iE "ERROR|ReferenceError|TypeError|is not defined|Failed to load" "$LOG"
  rm -f "$LOG"
  exit 1
fi

if ! grep -q "Configuration Loaded" "$LOG"; then
  echo "SMOKE-FAIL: config never reported loaded. Full log:"
  cat "$LOG"
  rm -f "$LOG"
  exit 1
fi

echo "SMOKE-PASS: configuration loaded with zero errors (qs exit $code)"
rm -f "$LOG"
exit 0
