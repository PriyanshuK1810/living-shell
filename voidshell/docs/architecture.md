# VOID SHELL — Architecture

## 1. Entry point

`shell.qml` (`ShellRoot`) is the only config root (`qs -c voidshell`):

1. **Services are instantiated eagerly, on purpose** —
   - the notification server must register the instant the shell starts
     or applications have nowhere to deliver notifications (PRD §15),
   - capability probes (brightness, locker, recorder, hibernate,
     battery, `grim`/`slurp`, Docker) run exactly once at launch instead
     of per widget (PRD §5.1),
   - stats/toast/task/weather state is shared, long-lived, single-
     sourced.
2. **Modules then bind to those singletons** — no widget polls on its
   own, no widget keeps a private copy of shell state.
3. A QA hook (`VOID_POPUP=<name>`) opens one popup at startup for
   automated runtime validation (PRD §43.2).

## 2. Layer surface map (Hyprland)

| Surface | Layer / anchor | Notes |
|---|---|---|
| Bar left/center/right | Top layer, three slanted pills | separate surfaces, `topMargin 10`; no background strip; namespace `voidshell-bar` (blur-exempt, design-system §2); each outer island capped to the width budget left of/right of the clock island; the **center island alone reserves `topMargin + barHeight` (64) as its exclusive zone** so windows no longer load underneath the bar — the outer islands pass `exclusiveZone: -1` (ignore other surfaces' zones) so avoidance never pushes them off `topMargin` |
| Popups (launcher, calendar, media, quick settings, notifications, power, dashboard, task manager, overview) | Top layer, anchored beneath their bar segment | one primary popup at a time, monitor-aware (`PopupManager.activeScreen` → fallback screen); namespaces `voidshell-popup` / `voidshell-launcher` / `voidshell-media` / `voidshell-overview` (blur-exempt) and `exclusiveZone: -1` so the bar's reservation never shifts a panel |
| Lock screen | Top layer, fullscreen | themed surface only; **hyprlock does the PAM authentication**; dismisses only when hyprlock exits 0 (PRD §25); namespace `voidshell-lock`, `exclusiveZone: -1` (fullscreen never shrinks) |
| Toasts | Top layer, bottom-right | never alter the bar (PRD §15.3); namespace `voidshell-toast`, `exclusiveZone: -1` |
| Wallpaper overlay | **Bottom** layer, fullscreen, empty input mask, `keyboardFocus: None` | behind windows *and* shell surfaces (PRD §29.1); click-through by construction; namespace `voidshell-wallpaper-overlay`, `exclusiveZone: -1` |
| PaletteGrab | offscreen transparent panel | exists only while `ThemeService` extracts a wallpaper tone (PRD §21.2); namespace `voidshell-palette-grab` |

## 3. Services catalog (`services/`, 26 singletons)

| Layer | Singletons |
|---|---|
| Orchestration | `PopupManager` (state machine + **IPC targets**), `HyprlandService` (event socket: workspaces, active window, monitors), `ToastService` |
| Device/system | `NetworkService`, `BluetoothService`, `AudioService`, `BrightnessService`, `PowerService`, `SystemStats`, `StorageService`, `KeyboardService` |
| Media/notifications | `MediaService` (MPRIS), `NotificationService` (**org.freedesktop.Notifications server** + history + DND), `RecordingService`, `ScreenshotService` |
| Content/stores | `TaskStore`, `EventStore` (calendar, local JSON), `WeatherService`, `FocusTimer`, `LauncherModel` (apps + `@commands` + actions), `GitService`, `DockerService` |
| Look | `ThemeService` (presets, dark/light, dynamic tone, persistence), `WallpaperService` (grid, apply via `awww`, tone lock, overlay mode), `VisualizerService` (FFT engine), `LyricsService` (local `.lrc`) |

Rules of thumb:

- **Event-driven first**: Hyprland socket, DBus signals, pipewire
  properties, MPRIS. Polling exists only where no event source exists,
  at PRD §36 intervals (stats 2 s *while displayed*, task list 3 s
  *while open*, weather ≥ 15 min, updates ≥ 60 s…).
- **Probes once at startup**, cached; absence → `available: false` and
  a written `unavailableReason` the UI renders (PRD §37).
- **Never fake data**: no placeholder metrics anywhere; unavailable
  means shown-as-unavailable.

## 4. Data flow

```text
hyprctl/Hyprland socket ─┐
pipewire (PwObjectTracker, peak taps) ─┤
DBus: NM · bluez · UPower · MPRIS · notifications server ─┤
/proc (stat, meminfo, net, uptime) · hwmon ─┤→  services  ─→ modules (bind)
subprocesses: nmcli/bluetoothctl/wpctl/brightnessctl/playerctl/awww/grim/
              wf-recorder/find/git/docker (gated, cached) ─┤
~/.local/share/voidshell/*.json (FileView, atomic writes) ─┘
```

- Modules never spawn processes; services own every subprocess with
  `available` gating (missing binary → disabled control + reason).
- Cross-service results surface through properties only — one source
  of truth per fact.

## 5. Popup discipline

`PopupManager` holds `activePopup` (string or `"none"`), the screen and
source item of the last open, and `locked` (lock surface owns the
screen while up):

- `open(name, screen, source)` closes the previous popup first — one
  primary popup at a time (PRD §13).
- Panels bind their visibility to `PopupManager`; none keeps its own
  boolean.
- Escape routes through `PopupManager.handleEscape()` (a singleton owns
  no window, so panels forward their key events).
- IPC: one `IpcHandler` per popup (`qs -c voidshell ipc call <name>
  toggle`) — every target funnels into the same `toggle()`, so the
  one-at-a-time and lock rules hold over IPC too. The `lock` target can
  open but `toggle()` refuses to dismiss while locked (PRD §25).

## 6. Persistence (PRD §35)

`~/.local/share/voidshell/` — `tasks.json`, `calendar.json`,
`settings.json`, `theme.json`, `wallpaper.json`, `weather.json`,
`location.json`, `git-index.json`, `git-roots.json`, `lyrics/`,
screenshots under `~/Pictures/Screenshots`.

- Missing file → defaults; malformed JSON → never crashes (parse
  guard + reset), never a QML error.
- Writes are safe-rewrite (temp file + rename) so a partial write can’t
  corrupt state.
- External fetch rules by construction: weather via a cached response
  only, **lyrics are local `.lrc` files only (no network)**, git/docker
  are local scans.

## 7. Look pipeline

```text
ThemeService  (presets, light/dark, dynamic tone from wallpaper pixels)
     ↑ binding
Colors.qml    (every token)   →  components  →  modules
WallpaperService (apply via awww, grid, tone lock, overlay mode)
VisualizerService (ffmpeg monitor → base64 lines → ring buffer → 512-pt
                   FFT → 24 log bands → 30 fps, audio-active only)
LyricsService (lazy local .lrc index → MPRIS-synced lines)
```

Dynamic tone: chroma-weighted extraction `(1-|2l-1|)·s`, threshold
0.15, sampled once per wallpaper change through the offscreen
`PaletteGrab` canvas — never continuous (PRD §36).

## 8. Performance architecture

- **Demand-driven everything**: stats sampler runs only while the
  task manager or dashboard is open; the visualizer’s 30 fps loop runs
  only while capture is audio-active and stops itself once decay
  flattens; the pipewire wake tap is disabled while the sink is muted
  (it could never hear anything through digital silence).
- Lazy work: expensive dashboard content is created per tab visibility,
  the lyric index is built once on first use, repo/container scans are
  cached with one-shot waits.
- Measured numbers and methodology: `docs/performance.md`.

## 9. Process & lifecycle

```sh
qs -d -c voidshell --no-duplicate   # start (autostart line in hyprland.lua)
kill <exact-pid>                    # stop — match 'qs -c voidshell' precisely
```

No hot reload in Quickshell 0.3.1 → restart to pick up QML edits.
Instance identity: `/run/user/1000/quickshell/by-id/<id>/log.qslog`.
Multiple instances must be avoided (`--no-duplicate`); while other
Quickshell configs run (e.g. a legacy shell), never `pkill qs`.

## 10. Testing architecture

- `scripts/check.sh` — qmllint across every QML file + `qmldir`
  singleton resolution (static gate, must print zero diagnostics).
- `scripts/smoke-test.sh` — boots the real config 12 s, requires exit
  124 (timeout) and zero `error/warning` lines (runtime gate).
- `scripts/popup-check.sh` / `scripts/tab-check.sh` — open each popup
  and each dashboard tab through the `VOID_POPUP`/`VOID_TAB` hooks,
  requiring clean logs (functional gate).
- Everything is read-only w.r.t. the system: no power dispatches, no
  process kills, no real session lock (PRD §43.4). See
  `docs/testing.md`.
