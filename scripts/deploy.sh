#!/usr/bin/env bash
# VOID SHELL — deploy repo -> live tree (reconciliation plan Phase 4, Option A).
#
# The repository (this checkout) is the authoritative code line. The live
# Quickshell config at ~/.config/quickshell/voidshell only changes when this
# script is run explicitly with --apply. Default mode is a read-only check.
#
# Safety rules (LS-IN-04/05 spirit):
#   * never deletes anything in the target (target .git, compiled bt-agent
#     and any user-local files survive every deploy);
#   * --apply takes a timestamped tar backup of the target first and prints
#     its path;
#   * no sudo, no shell interpolation of paths into commands, fixed argv.
set -euo pipefail

usage() {
    cat <<'EOF'
usage: scripts/deploy.sh [--check | --apply] [--help]

  --check   (default) show which files differ between this repo's voidshell/
            and the live tree; makes no writes.
  --apply   back up the live tree, then copy this repo's voidshell/ over it.
  --help    this text.

Paths:
  source  <repo>/voidshell
  target  ${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/voidshell
  backup  ${XDG_STATE_HOME:-$HOME/.local/state}/voidshell/deploy/backups/<ts>.tar.gz
EOF
}

mode="check"
for arg in "$@"; do
    case "$arg" in
    --check) mode="check" ;;
    --apply) mode="apply" ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "deploy: unknown argument: $arg" >&2
        usage >&2
        exit 2
        ;;
    esac
done

src="$(cd "$(dirname "$0")/.." && pwd)/voidshell"
target="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/voidshell"

if [ ! -d "$src" ]; then
    echo "deploy: source not found: $src" >&2
    exit 1
fi

# Files that never differ-count: the target's own .git (deployed tree is its
# own repo) and the compiled bt-agent binary (source ships, binary stays local).
diff_list() {
    diff -rq \
        -x '.git' \
        -x 'bt-agent' \
        "$src" "$target" 2>/dev/null || true
}

if [ ! -d "$target" ]; then
    echo "deploy: target does not exist: $target" >&2
    echo "deploy: refusing to create it; install the config first (see voidshell/README.md)." >&2
    exit 1
fi

list="$(diff_list)"
if [ -z "$list" ]; then
    echo "deploy: in sync — no differences between repo and live tree."
    exit 0
fi

n="$(printf '%s\n' "$list" | wc -l)"
echo "deploy: $n path(s) differ between"
echo "  src:    $src"
echo "  target: $target"
printf '%s\n' "$list" | sed 's/^/  /'
echo

if [ "$mode" = "check" ]; then
    echo "deploy: check only — nothing written. Re-run with --apply to deploy."
    exit 0
fi

# ---- apply -----------------------------------------------------------------
bdir="${XDG_STATE_HOME:-$HOME/.local/state}/voidshell/deploy/backups"
ts="$(date +%Y%m%d-%H%M%S)"
bfile="$bdir/$ts.tar.gz"
mkdir -p "$bdir"
tar -czf "$bfile" -C "$(dirname "$target")" "$(basename "$target")"
chmod 600 "$bfile"
echo "deploy: target backed up to $bfile"

tar -cf - -C "$src" --exclude='.git' . | tar -xf - -C "$target"
echo "deploy: copied $src -> $target"

# The compiled helper is intentionally not in git; it must survive deploys.
if [ ! -x "$target/scripts/bt-agent" ]; then
    if [ -f "$target/scripts/bt-agent.c" ]; then
        echo "deploy: WARNING: scripts/bt-agent binary missing; Bluetooth pairing agent will not run."
        echo "deploy: build it manually:  cc -O2 -o scripts/bt-agent scripts/bt-agent.c  (in $target)"
    fi
fi

echo "deploy: done. Restart the shell to load the new code, e.g.:"
echo "  qs -c voidshell ipc call launcher toggle   # (then reload, or log out/in)"
echo "deploy: to roll back this deploy, restore $bfile"
