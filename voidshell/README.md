# VOID SHELL

A complete desktop shell for Hyprland, built on Quickshell, implemented to
the Void Shell PRD. Slanted-pill top bar (no background strip), ten
anchored popups with one-primary-at-a-time discipline, five-tab dashboard,
system monitor, theming (`@color`), wallpapers (`@wp`), local git/docker
launcher plugins, notifications server + history + DND, calendar with a
local event store, screenshot/recording, lock screen, and an optional
wallpaper overlay (audio visualizer, synced lyrics, big clock). The
centre clock doubles as the **Living State Island** — a dependable clock
that briefly speaks events, opens a compact activity stack
(`Super + I`) below itself and links into the Dashboard, without ever
changing the bar's geometry.

```text
PRD → https://github.com/… (source: Void_Shell_PRD.md)
Docs → docs/design-system.md · architecture.md · features.md
        performance.md · testing.md · dependencies.md
Env  → BUILD_ENVIRONMENT.md
Kitty → kitty/  (Living Kitty terminal — see kitty/README.md)
```

## Companion config — Living Kitty

This repository ships two things:

| directory | what it is |
|---|---|
| `voidshell/` (this folder) | the Quickshell desktop shell + Living State Island |
| `kitty/` | the Living Kitty terminal — ink-glass kitty config, leader keybindings, slanted tabs, Slang shader, quick-access terminal, island IPC watcher |

They are designed as one visual system (the terminal's palette is
sampled from the bar's dark tokens) and wired together: `Super + grave`
opens the kitty quick-access terminal, and kitty's watcher publishes
long-running command state to this shell's Living State Island through
the `job` IPC target. Full terminal documentation: [`kitty/README.md`](../kitty/README.md).

## Requirements

| Component | Version used | Why |
|---|---|---|
| Arch Linux | rolling | target platform |
| Hyprland | 0.56.2 (Lua config) | compositor, layer-shell |
| Quickshell | 0.3.1 | shell runtime, IPC, pipewire/DBus APIs |
| Qt (qt6-declarative / qt6-svg) | 6.11.2 | QML scene graph, SVG icons |
| Outfit + JetBrainsMono Nerd Font | any recent | UI typeface, icons/mono |

Recommended extras (features degrade gracefully, clearly labelled, when
missing — PRD §37): `grim` + `slurp` (screenshots), `wf-recorder`
(screen recording), `playerctl` (MPRIS media), `awww` (wallpaper apply),
`hyprlock` (lock auth), `hypridle`, `bluez` + `networkmanager`,
`pipewire` + `wireplumber`, `brightnessctl`, `jq`. Full matrix:
`docs/dependencies.md`.

## Install

```sh
git clone <this-repo> ~/.config/quickshell/voidshell   # or copy the tree
qs -c voidshell                                        # one-shot smoke run
```

Nothing is written outside `~/.config/quickshell/voidshell/` and
`~/.local/share/voidshell/` (state — see below).

## Start / stop / reload

```sh
qs -d -c voidshell --no-duplicate     # start (daemonized; --no-duplicate guards autostart)
qs -c voidshell ipc show              # verify: lists all IPC targets
kill "$(pgrep -ax qs | grep voidshell | awk '{print $1}')"   # stop (match the exact process; never pkill 'qs' while other Quickshell configs run)
```

Autostart is declared once, in `~/.config/hypr/hyprland.lua`:

```lua
hl.on("hyprland.start", function ()
    …
    hl.exec_cmd("qs -c voidshell --no-duplicate")
end)
```

Waybar is intentionally **not** started — Void Shell owns the bar layer
(PRD §1). Quickshell 0.3.1 does not hot-reload: after editing QML,
restart the process (state files survive).

## Keybinds

Shell popups (defined in `hyprland.lua`, all via IPC — see below):

| Bind | Action |
|---|---|
| `Super + Space` | Launcher |
| `Super + O` | Quick settings |
| `Super + D` | Notifications |
| `Super + Shift + A` | Media popup (not `Super + M` — see the note below) |
| `Super + Shift + D` | Dashboard (5 tabs) |
| `Super + Shift + M` | System monitor / task manager |
| `Super + W` | Workspace overview |
| `Super + I` | Living State Island — activity stack (`island toggle`) |

Media/volume/brightness (shell reacts live): `F7/F8/F9` playerctl,
`F1` sink mute, `F2/F3` volume, `F4` mic mute, `F11/F12` backlight.

> Note: media sits on `Super + Shift + A`, not `Super + M` — that key
> carries this Hyprland config's pre-existing exit binding
> (`hyprshutdown`). Void Shell moved its bind instead of touching the
> older one; verified `hyprctl binds` shows exactly one `Super + M`
> (exit) and one `Super + Shift + A` (media).

Everything else (`Super+Q/E/C/V/R/P/J/F/L`, arrows, `1-5`, `Super+Tab`,
…) is the untouched window-management layer of the user's Hyprland
config. Full list: `docs/features.md`.

## IPC

Every popup is addressable from scripts and binds:

```sh
qs -c voidshell ipc show                          # targets × toggle()
qs -c voidshell ipc call launcher toggle          # open/close a popup
qs -c voidshell ipc call taskManager toggle
qs -c voidshell ipc call island toggle            # Living State Island stack
qs -c voidshell ipc call island diagnostics       # capability matrix (JSON)
```

Targets: `launcher calendar media quickSettings notifications power
dashboard taskManager overview lock` plus `island`
(`toggle|stack|section|context|close|diagnostics`) and `job`
(`publish|update|finish|announce|pin|invoke`) for the Living State
Island. All
route through one state machine (`PopupManager`), so opening one closes
the others and the lock target can open but never dismiss itself.

## Customize

- **Color tokens** → `common/Colors.qml` (every value binds to
  `ThemeService`, so presets / dark-light / dynamic wallpaper tone
  repaint the whole shell from one place — PRD §7–10, §20).
- **Geometry, type, motion** → `common/Theme.qml` (radii, spacing, bar
  metrics, font names, durations). No module may scatter these numbers.
- **Reusable parts** → `common/components/` (SlantedPill, GlassCard,
  GlassPanel, ToggleTile, ShellSlider, PopupShell, …).
- **In-shell theming** → launcher `@color` (presets, dark/light, dynamic
  wallpaper tone) and `@wp` (wallpaper grid, tone lock, overlay mode).
- **State** lives in `~/.local/share/voidshell/` (`tasks.json`,
  `calendar.json`, `settings.json`, `theme.json`, `wallpaper.json`,
  `weather.json`, `git-index.json`, `location.json`, `lyrics/`,
  `island.json` — the Living State Island's feature flags, durations,
  privacy and threshold settings; missing/malformed → documented
  defaults). Missing
  or malformed files fall back to defaults; writes are atomic
  (write-then-rename) — PRD §35.

## Troubleshooting

| Symptom | Check / fix |
|---|---|
| `Target not found` from `ipc call` | no running instance → `qs -d -c voidshell --no-duplicate`, then `qs -c voidshell ipc show` |
| QML error on start | output of `qs -c voidshell`; must be zero warnings (gate: `scripts/check.sh` + `scripts/smoke-test.sh`) |
| Where are logs | stdout, plus `/run/user/1000/quickshell/by-id/<id>/log.qslog` |
| Popup won't open over a specific monitor | multi-monitor fallback logic in `PopupManager` (activeScreen → fallback); `hyprctl layers` shows where surfaces are |
| Waybar/old shell still drawn | other instances: `pgrep -ax qs` / `pgrep -ax waybar` — only `qs -c voidshell` should run; the legacy bars were removed 2026-10-02 |
| Screenshot tool greyed in launcher | `grim`/`slurp` not installed — launcher shows the unavailable reason (PRD §37) |
| Recording button dead | `wf-recorder` missing → install, then relaunch the shell |
| Battery/temperature widgets empty | hardware absent → widgets show the “unavailable” state, never fake numbers |

## Testing

```sh
./scripts/check.sh         # qmllint over every QML file + qmldir singleton resolution → CHECK-PASS
./scripts/smoke-test.sh    # boots the config for 12 s, requires exit 124 and zero errors → SMOKE-PASS
./scripts/popup-check.sh   # opens each of the 10 popups via VOID_POPUP, clean logs → POPUP-CHECK-PASS
./scripts/tab-check.sh     # visits each dashboard tab via VOID_TAB, clean logs → TAB-CHECK-PASS
./scripts/shelf-check.sh   # Stage shelf reveal/suppression/opt-in probe → PHASE-E-PROBE-PASS
./scripts/coord-check.sh   # one-primary-surface + Island-hook probe → PHASE-F-PROBE-PASS
./scripts/hardening-check.sh # motion modes, lock release, disable switch, reload → PHASE-G-PROBE-PASS
./scripts/island-check.sh   # Living State Island: pill geometry, announcements, stack, validation, lock → ISLAND-CHECK-PASS
```

`popup-check.sh` and `tab-check.sh` start their own instance — run them
with no other `qs` running (stop the daemon first), otherwise the
duplicate-notification-server warnings fail the gate. `island-check.sh`
restarts the shell itself and restores one live instance at the end.

QA hooks and the full static/runtime/functional methodology are
documented in `docs/testing.md` (PRD §43). Tests never dispatch power
actions, never kill processes, and never lock the session.

## Repository layout

```text
~/.config/quickshell/voidshell/
├── shell.qml               # entry point: eager services + module instances
├── common/                 # Colors.qml, Theme.qml + shared components
├── services/               # 40 singletons: state, probes, stores, IPC
│                           # (11 of them the Living State Island layer)
├── modules/                # Bar, Launcher, Calendar, Media, QuickSettings,
│                           # Notifications, PowerMenu, Toast, Dashboard,
│                           # TaskManager, WorkspaceOverview, LockScreen,
│                           # Wallpaper, WallpaperOverlay, Island
├── scripts/                # check.sh, smoke-test.sh, popup/tab/coord/
│                           # shelf/hardening/island QA gates
└── docs/                   # design-system, architecture, features,
                            # performance, testing, dependencies
```
