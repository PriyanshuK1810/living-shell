#!/usr/bin/env bash
# VOID SHELL — static check: lint every QML file and verify qmldir singletons.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

while IFS= read -r f; do
  out="$(qmllint "$f" 2>&1)"
  code="$?"
  if [ "$code" -ne 0 ] || [ -n "$out" ]; then
    echo "LINT-FAIL: $f"
    echo "$out"
    fail=1
  fi
done < <(find "$ROOT" -name '*.qml' | sort)

while IFS= read -r qmldir; do
  dir="$(dirname "$qmldir")"
  while IFS= read -r line; do
    case "$line" in
      singleton*)
        set -- $line
        if [ ! -f "$dir/$3" ]; then
          echo "QMLDIR-FAIL: $qmldir declares missing file: $3"
          fail=1
        fi
        ;;
    esac
  done < "$qmldir"
done < <(find "$ROOT" -name 'qmldir' | sort)

if [ "$fail" -eq 0 ]; then
  echo "CHECK-PASS: all QML files lint clean, all qmldir singletons resolve"
else
  echo "CHECK-FAIL"
fi
exit "$fail"
