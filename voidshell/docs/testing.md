# VOID SHELL — Testing

Implements PRD §43 (static / runtime / functional) and §45 (phase
gates). Every gate below is a script or an exact command — nothing is
suppressed, nothing is faked.

## 1. Static validation (§43.1)

```sh
./scripts/check.sh
# → CHECK-PASS: all QML files lint clean, all qmldir singletons resolve
```

- `qmllint` (Qt 6.11) over every `*.qml` — syntax, imports, unknown
  properties, undefined identifiers, type errors.
- `qmldir` audit: every `singleton` entry resolves to a real file and
  every file registers its `pragma Singleton` (catches broken singleton
  registration).
- Gate rule: **zero diagnostics**. Warnings are fixed, never masked
  with lint suppressions.

## 2. Runtime validation (§43.2)

```sh
./scripts/smoke-test.sh
# → SMOKE-PASS: configuration loaded with zero errors (qs exit 124)
```

Boots the real config for 12 s (`timeout` → expected exit 124) and
requires the log to contain **no** matches for
`error|warning|ReferenceError|TypeError|binding loop|failed|cannot
assign|module not installed`. `qmllint` misses some runtime-only
errors, so this log grep is the authoritative runtime gate. Any match
must be understood and fixed — never globally suppressed.

## 3. Functional gates (§43.3)

```sh
./scripts/popup-check.sh   # → POPUP-CHECK-PASS   (10/10 popups)
./scripts/tab-check.sh     # → TAB-CHECK-PASS     (5/5 dashboard tabs)
./scripts/coord-check.sh   # → PHASE-F-PROBE-PASS (one primary popup: 21/21)
./scripts/shelf-check.sh   # → PHASE-E-PROBE-PASS (Stage shelf: 15/15)
./scripts/hardening-check.sh # → PHASE-G-PROBE-PASS (motion/lock/disable/reload: 50)
./scripts/island-check.sh  # → ISLAND-CHECK-PASS  (Living State Island: 9 groups)
```

- `popup-check.sh` opens each primary popup through the startup hook
  (`VOID_POPUP=<name>`) and requires a clean log + expected lifetime
  for each.
- `tab-check.sh` does the same for every dashboard tab
  (`VOID_POPUP=dashboard VOID_TAB=<id>`).
- `shelf-check.sh` drives the Stage shelf through its real IPC payload
  (`ipc call shelf toggle`) against the live compositor and restores
  the settings file and the session afterwards — it restarts the shell,
  so run it when a restart is acceptable.
- `hardening-check.sh` is the Phase G gate: it writes
  `desktop-manager.json` for each `animation` mode and greps the
  resolved `motion:` log line, opens the overview then locks an
  isolated instance to prove `preview: released N capture request(s)`,
  screenshots the pill in dash vs `managerEnabled:false` mode (pixel
  diff inside the pill island, pixel-identical elsewhere), and finishes
  with the reload hygiene checks (one instance, three bar layers, one
  `Super+W`, one `Super+Shift+W`). It backs the settings file up and
  restores it from an `EXIT` trap; it restarts the shell repeatedly, so
  run it when restarts are acceptable.
- `island-check.sh` is the Living State Island gate (features §23): it
  restarts the shell with log capture, then asserts the pill geometry
  never changes (I1), that a real announcement paints inside the pill
  and expires back to the clock with **zero** change outside it (I2),
  that the activity stack and the contextual card open, render a
  published activity and close (I3), that one-primary-surface holds with
  `voidshell-island` involved (I4), that malformed/unidentified/badly
  keyed IPC payloads are rejected rather than rendered (I5), that a
  sequence-numbered update cannot regress progress (I6), that a second
  `finish` for the same activity is a no-op (I7), that the lock drops
  the island surface (I8), and that exactly one instance plus zero
  WARN/ERROR is left behind (I9). It never locks the session for real
  and never dispatches a power action.
- **Second-workspace fixture.** The shelf groups *other occupied*
  workspaces and the Island hook needs a workspace to switch to, so
  `hardening-check.sh`, `shelf-check.sh` and `coord-check.sh` start one
  temporary `kitty --class voidshard-probe` window on workspace 2 when
  the session has fewer than two occupied workspaces — and kill that
  exact pid before reporting the session (or skip the affected
  assertions with a printed `SKIP` if no window can be created). This
  keeps the probes reproducible on a freshly booted, single-window
  session instead of silently passing without exercising the path.

`popup-check.sh` and `tab-check.sh` run an **isolated instance** — stop
the daemon first (`kill <exact-pid>`), run the gates, restart:

```sh
kill "$(pgrep -ax qs | grep voidshell | awk '{print $1}')"
./scripts/check.sh && ./scripts/smoke-test.sh &&
./scripts/popup-check.sh && ./scripts/tab-check.sh
qs -d -c voidshell --no-duplicate
```

### 3b. Living Kitty integration (`docs/kitty.md`)

The terminal side of the desktop is validated separately, against the
installed kitty 0.49.2 — every claim below is a runtime measurement,
not a config parse. Probes live in `/tmp/opencode/kittytest/`
(`test-matrix.sh`, `test-git-tools.sh`, `test-watcher.sh`,
`test-qat.sh`); they drive a detached kitty instance through real
remote control (`kitten @ --to unix:$XDG_RUNTIME_DIR/kitty-<pid>`) and
real key injection (`hyprctl dispatch hl.dsp.send_shortcut`), never
`send-text` for keys and never another instance's socket.

| Area | Check |
|---|---|
| Config | `scripts/validate-config.py` → 0 problems, exit 0 (kitty's own loader, kitten option specs, session files, `bash -n`) |
| Keybindings | leader chains: tabs, layouts, splits/panes (focus moves both directions, resize widens), opacity up/down/default, readability ↔ glass palette, overlays open **and** close on Escape, broadcast + Ctrl+Escape, git/tools |
| Git views | `g>l`/`g>s` render commits and branch in a held tab in the repo dir (`--hold` keeps them readable; `--cwd=current` keeps the dir) |
| lazygit | `g>g` opens a `lazygit` tab in the repository; conf.d/95-tools.conf alone disables it |
| Custom shader | both panes painted the same red → inactive 239 vs active 255 (the 14% linear dim), and the values **swap** when focus swaps; fresh instance log is empty |
| Quick-access terminal | Super+grave → layer `kitty-quick-access` at 896×321 @192,146 logical; paints cell backgrounds over the bar; toggle-off returns to wallpaper, toggle-on restores; the Hyprland blur rule is visibly applied; `hide_on_focus_loss yes` does **not** prevent rendering (verified by comparing both variants pixel-wise) |
| Watcher → island | 14/14 E2E: unknown, fast and silent commands never reach the island; a build publishes at start, finishes and clears; `sudo` stand-in produces the right tab title and restore; `ssh` is now verified against the **real** openssh client (`kssh` prints ssh usage; `ssh build@192.0.2.1` ≥8 s → tab title `ssh: build@192.0.2.1`, `overridden=True`, island activity published, then title restore + activity clear on exit, dropped=0) |
| Notifications | `notify_on_cmd_finish invisible 8.0 notify`: a `sleep 10` finished in a **hidden** tab (focus moved away with `t>p`) raises a real `org.freedesktop.Notifications.Notify` with a sanitised body; the same command in a visible window stays silent |
| Fresh instance | stderr empty; `hyprctl configerrors` empty; all three kitty instances show the new config (`active_border_color #6e3acf`) |

Notes that tripped the probes (and are therefore worth knowing):
`kitten @ send-text` expands ANSI C escapes, so test payloads must come
from a file; kitty's confirmation dialogs need `ESCAPE`/`Y` (not
`ESC`); a confirmation dialog that has already closed swallows a stray
`Y` into the shell prompt line, which is why the probes clear the line
with `Ctrl+U` first and only press `Y` when the active tab title shows
`Close tab?`.

`docs/kitty.md` carries the full kitty documentation (keybinding map,
sessions, IPC and security decisions, omissions and limitations).

### Interactive checklist (PRD §43.3, verified across phases)

| Area | Check |
|---|---|
| Workspaces | click workspace buttons / `Super+N` → focus follows, pill highlights |
| Active app | focus another window → left app pill title updates |
| Launcher | type → fuzzy list, Enter launches, arrows navigate; `@` commands activate |
| Calendar | prev/next/today, event create/delete persists across restart |
| Media | with/without MPRIS player: controls live or state says no player — **environment-limited on this machine**: no readable player exists (`mpv` is built without MPRIS; brave/Chromium publishes the Player properties on the root path `/org/mpris/MediaPlayer2` instead of `/org/mpris/MediaPlayer2/Player`, and quickshell exposes no generic D-Bus API to bridge it). The pill/popups and the announcement engine are exercised by the gates; the live playback→pill announcement is **not** verified here (see `features.md` provider matrix) |
| Wi-Fi / Bluetooth | toggle + list reflect `nmcli` / `bluetoothctl`; adapters absent → disabled + reason |
| Volume / mic / brightness | sliders move real state (F1–F4, F11/F12 react live); no backlight → disabled + reason |
| DND | toggle suppresses toasts, history still collects |
| Notifications | send one (`notify-send`) → toast + history + badge; clear-all works |
| Dashboard | 5 tabs switch, graphs update while open |
| Task persistence | add/complete/delete → survives restart (`tasks.json`) |
| Focus timer | countdown runs, closing the popup doesn’t stop it, completion toasts |
| System stats | CPU/mem/net graphs move while the drawer is open |
| Task manager | process list refreshes at 3 s; kill asks first |
| Theme | every preset + dark/light repaints all surfaces, no per-module leftovers |
| Wallpaper | grid switch applies via `awww`, persists across restart |
| Dynamic palette | `@color` dynamic mode extracts real wallpaper tones, lock holds |
| Screenshot | full/region/output → file in `~/Pictures/Screenshots` + toast (needs `grim`) |
| Recording | start → bar indicator + elapsed; stop → indicator gone, no desync (needs `wf-recorder`) |
| Docker plugin | images/containers when CLI exists, disabled + reason otherwise |
| Git plugin | repos/branch/status from real `git` scans; never mutates |
| Multi-monitor | popups open on the source monitor, fall back sanely |
| Lock | lock surface → hyprlock → unlock returns; while locked nothing else opens |
| Overlay | four `@wp` modes render; `off` (default) shows nothing; silent → visualizer idle |
| Unavailable states | remove/hide a tool (grim, wf-recorder, docker, player) → control disabled with its written reason, shell still clean |
| Island clock | announcement paints **inside** the 170×56 pill, expires back to the clock, neighbours pixel-identical |
| Island stack | `Super + I` / right-click → five blocks switch; clipboard block re-reads history on open; long bodies scroll under the cap |
| Island context | activity row → contextual card with its registered actions; `Escape` closes the surface first |
| Island privacy | `strict` privacy redacts clipboard previews; lock drops the island; DND/fullscreen suppress non-P0 |

## 4. QA hooks

| Hook | Effect |
|---|---|
| `VOID_POPUP=<name>` | open one popup at startup (names: `launcher calendar media quickSettings notifications power dashboard taskManager overview lock`; invalid = ignored) |
| `VOID_TAB=<id>` | select a dashboard tab (`overview media weather alerts productivity`) |
| `VOID_LAUNCHER_QUERY='@git'` | prefill the launcher query (command plugins) |
| `VOID_SHELF=1` | reveal the Stage shelf at startup (needs `shelfEnabled: true`; features §18) |
| `VOID_OVERVIEW=<tokens>` | comma-separated overview tokens run the real click/drop paths (features §7, §20–§21): `expand:<workspace>`, `switch:<workspace>` (card click), `focus:<address>` (preview click), `move:<address>:<workspace>` (silent drop), `hit` (drop hit-test probe: answers `cardAt` directly — the focused card's centre and painted edge must hit, a slot point outside the painted surface must miss — because pointer motion cannot be injected on this machine; waits for the settled focus state through `Qt.callLater`, re-checked only on Hyprland events), `scroll` (slider probe: feeds one synthetic half-card pixel delta through the real `wheelStep` — must fold to exactly one detent, `steps=1 acc=0` — then drives the strip to its clamp end and logs `cards/viewport/content/range/x` plus the wheel-line, because no input device on this machine can inject a wheel event; the arrow-key Shortcuts are exercised separately through Hyprland's `hl.dsp.send_key_state` key injection). One-shot, no timers. The old `create` token (the rail's `+`) was retired with the rail in the Neon Purple pass |
| `VOID_POPUP=lock` | lock surface escape hatch for QA only (normal locked state cannot be dismissed by Escape/IPC) |
| `VOID_ISLAND_DEMO=1` | start `JobBridge`'s demo activity (one fake job + timer) so the Island stack has something to render in a capture; off by default, never publishes otherwise |

## 5. Screenshot recipe (DPMS-free)

```sh
VOID_POPUP=<name> timeout --signal=TERM -k 3 13 qs -c voidshell \
    > /tmp/qa.log 2>&1 &
sleep 8 && grim /tmp/qa-$(date +%H%M%S)-<tag>.png
wait   # then: grep -E "WARN|ERROR" /tmp/qa.log   → must be empty
```

- Never dispatch `dpms` to force a frame; verify freshness by comparing
  the in-frame clock against `date`.
- Never `pkill qs` — other Quickshell configs may run alongside; kill
  by exact PID.

## 6. Safety rules (§43.4)

Automated tests **must never**:

- dispatch suspend/hibernate/reboot/poweroff,
- kill processes other than the isolated test instance they started,
- lock the session for real (the lock surface is exercised via
  `VOID_POPUP=lock`; authentication itself is hyprlock’s, untouched),
- press the confirmation-backed destructive controls in the power menu,
- alter user data (`tasks.json`, `calendar.json`, wallpaper/theme
  state are restored to defaults after QA).

Scripts in this repo follow these rules; the power menu’s actions are
manual-only.

## 7. Phase gates used throughout

Each phase shipped with: `check.sh` clean → `smoke-test.sh` pass →
`popup-check.sh` + `tab-check.sh` pass → visual QA captures (bar clock
compared against `date`, popups/tabs/overlay/state verified) → git
commit. Phases E–G added their own probe scripts (`shelf-check.sh`,
`coord-check.sh`, `hardening-check.sh`) to that list, and the Living
State Island follow-up added `island-check.sh`.
`docs/performance.md` records the §36 measurements.
