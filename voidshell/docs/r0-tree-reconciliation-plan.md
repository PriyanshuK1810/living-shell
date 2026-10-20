# R0 tree reconciliation plan (dry-run)

- Document: LS-R0-RECON-001 · Companion to `r0-current-state-audit.md` §1
- Date: 2026-10-20 · Status: **proposed — awaiting approval**; Phases 0–3 never write to the live tree
- Goal: one authoritative code line. Repo (`~/living-shell`, GitHub `2c39b4d`) becomes a strict superset of the live runtime (`~/.config/quickshell/voidshell`), preserving the deployed tree's own history and all uncommitted work.

## 1. Evidence summary (why this direction)

| Fact | Evidence |
|---|---|
| Repo commit `2c39b4d` (Oct 6 21:03) is a **snapshot of the deployed working tree** | identical content for 146/155 shared paths; deployed continued evolving Oct 6–8 |
| Deployed working tree is **strictly newer** | 9 differing files, nearly pure additions: features.md +199/−1, Launcher.qml +163/−11, LauncherModel.qml +178/−10, BluetoothService +122/−0, qmldir +13/−0, shell.qml +30/−2, DeviceList +29/−15, DeviceMenu +4/−3, AppDetail +1/−1 |
| Every "removed" line is explained evolution, no lost repo functionality | matcher refactored into `matches()` which is a **superset** (adds execString, categories, keywords — deployed LauncherModel:189-203); "no BlueZ agent" comments removed because deployed **adds a pairing agent** (`bt-agent.c`); `servicesWarmed` count fixed 26→33; keycap hint Ctrl→Shift+Enter matches deployed handleKey (Launcher.qml:130-144) |
| 14 new deployed-only paths | `modules/Workbench/`, `services/{ApplicationStore,ContextActionRegistry,DesktopNavigationStore,GestureRouter,RofiBridge,RofiThemeSync,SurfaceCoordinator,WindowActions,WorkbenchController,WorkbenchSettings}.qml`, `scripts/bt-agent.c`, `scripts/bt-agent` (ELF binary), `scripts/workbench-check.sh` |
| Repo has **no content absent from deployed** except today's audit doc | `diff -rq` shows only `docs/r0-current-state-audit.md` repo-only |
| Live instance == deployed working tree | process started after last file write; no newer .qml |

## 2. Phase 0 — Safety backups (writes only to a new backup dir)

```bash
B=~/dotfiles-backups/voidshell-reconcile-$(date +%Y%m%d-%H%M%S); mkdir -p "$B"
# deployed repo history (all refs/objects) → bundle, read-only on source
git -C ~/.config/quickshell/voidshell bundle create "$B/deployed-history.bundle" --all
# deployed working tree bytes
tar -czf "$B/deployed-workingtree.tar.gz" -C ~/.config/quickshell voidshell
# repo history
git -C ~/living-shell bundle create "$B/living-shell-repo.bundle" --all
# checksums
( cd ~/.config/quickshell/voidshell && find . -type f -not -path './.git/*' -exec sha256sum {} + ) | sort > "$B/deployed.sha256"
( cd ~/living-shell && git ls-files -z | xargs -0 sha256sum ) | sort > "$B/repo.sha256"
```

## 3. Phase 1 — Import deployed history into repo (read-only on deployed)

```bash
git -C ~/living-shell fetch ~/.config/quickshell/voidshell/.git \
    'refs/heads/master:refs/heads/deployed-history'
```

Result: deployed's 40+ commits preserved as branch `deployed-history` (disjoint histories; no merge attempted — import is content-based, history kept for reference/archaeology).

## 4. Phase 2 — Reconciliation commit (writes only inside repo)

```bash
git -C ~/living-shell checkout -b reconcile/import-deployed-runtime
rsync -a --exclude='.git' --exclude='scripts/bt-agent' \
      ~/.config/quickshell/voidshell/ ~/living-shell/voidshell/
# expected diff-vs-deployed now: audit doc (repo-only) + scripts/bt-agent (excluded binary) only
diff -rq ~/living-shell/voidshell ~/.config/quickshell/voidshell
```

- `scripts/bt-agent` is a 27 KB **compiled ELF** — source `bt-agent.c` is committed; add `.gitignore` entry for the binary (plus `__pycache__/`, `*.qmlc`).
- Commit message: `Import live runtime state (Workbench/Rofi/Bluetooth-agent) — source ~/.config/quickshell/voidshell @8ad0244+wt 2026-10-08`.
- `master` is **not** advanced; the branch is reviewed and merged only on approval.

## 5. Phase 3 — Verification

1. `./voidshell/scripts/check.sh` on reconciled branch (static lint + qmldir) — must be CHECK-PASS (deployed tree already passed today).
2. `diff -rq` proof: only the two expected exceptions (audit doc, excluded binary).
3. Optional, needs explicit consent (disturbs live session): `smoke-test.sh`, then the UI gates — expect `tab-check.sh` (stale `weather` tab) and `popup-check.sh` (stale `calendar` popup) to need expectation fixes first (audit §4).

## 6. Phase 4 — Live-tree strategy (decision required; not executed by this plan)

| Option | Description | Risk |
|---|---|---|
| **A. Repo authoritative + deploy script (recommended)** | deployed tree stays exactly as-is; development happens in repo; `scripts/deploy.sh` (rsync repo → deployed, `--backup-dir` timestamped) run manually | lowest; live tree changes only on explicit deploy |
| B. Symlink `~/.config/quickshell/voidshell → ~/living-shell/voidshell` | single source, zero copy | must verify qs config resolution + `.git`/path assumptions on a live system; medium |
| C. Reset deployed to repo remote | fetch repo into deployed, `reset --hard` | deployed history preserved only in bundles/branch; live-tree write; highest |

## 7. Rollback

- Phases 0–3 touch only backups and the repo working copy; deleting the `reconcile/*` branch + restoring nothing else restores pre-plan state.
- Any later Phase-4 failure restores from `deployed-workingtree.tar.gz` / `deployed-history.bundle` byte-for-byte.

## 8. Consent gates

1. Approve Phases 0–3 (no live-tree writes).
2. Approve merge to `master` after check.sh + review.
3. Choose Phase-4 option; approve that separate execution.
