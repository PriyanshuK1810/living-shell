# VOID SHELL — Build Environment

Recorded: 2026-09-15 (Phase 1: System Audit and Safe Baseline).
Updated: 2026-10-02 (final build — autostart switched to Void Shell,
waybar removed from autostart, tool inventory re-verified).
Machine: Loki (Dell laptop, AU Optronics eDP-1 panel).

## Platform versions

| Component | Version |
|---|---|
| OS | Arch Linux (rolling) |
| Hyprland | 0.56.2 (commit efb5099, tag v0.56.2) |
| Quickshell | 0.3.1-1 (Arch package) |
| Qt | 6.11.2 (`qmake6`: QMake 3.1, Qt 6.11.2 in /usr/lib) |
| qt6-declarative | 6.11.2-2 |
| qt6-svg | 6.11.2-1 |
| `qtpaths6` | NOT INSTALLED / not on PATH |

## Monitor configuration

- Single monitor: `eDP-1`, 1920x1080@60.006, position 0x0
- Scale: **1.5**, transform 0, VRR off, DPMS on
- Effective logical resolution: 1280x720
- Bar geometry in use: Void Shell’s three pill surfaces sit at
  `xywh 18,10 540×64` / `555,10 170×64` / `682,10 580×64` (layer
  coordinates as reported by `hyprctl layers`), with monitor reserved
  space `0 0 0 0` — the legacy bars are gone, so nothing pushes the
  islands down anymore.
- Wallpaper: `~/Pictures/wallpapers/void-purple.png` via `awww-daemon`

## Package inventory (shell-relevant)

Present: quickshell, qt6-declarative, qt6-svg, hyprland, networkmanager,
bluez, bluez-utils, pipewire 1.6.8, wireplumber 0.5.17, brightnessctl,
playerctl 2.4.1, jq 1.8.2, hyprlock, hypridle, waybar 0.15.0, grim,
slurp, awww, git.

Missing (optional): `wf-recorder` (screen recording — the launcher
action shows its unavailable reason until installed), `docker` (the
`@containers` plugin reports unavailable), `libnotify`/`notify-send`,
`pacman-contrib`, `power-profiles-daemon` (`powerprofilesctl`
unavailable), `hyprsunset`. Nothing was auto-installed — the shell
degrades gracefully per PRD §37.

## Fonts

- `fc-match Outfit` → Outfit Regular (`~/.local/share/fonts/Outfit[wght].ttf`)
- `fc-match "JetBrainsMono Nerd Font"` → JetBrainsMonoNerdFont Regular
  (96 JetBrains Nerd faces installed)

## Running services / conflicts

- Legacy bars fully removed 2026-10-02: `qs -c myshell` and `waybar`
  processes stopped (exact-PID SIGTERM), config files deleted
  (`~/.config/quickshell/myshell` stow symlink + `~/dotfiles/quickshell/`
  + empty `~/dotfiles/waybar/`; dotfiles commit `967e411`). The waybar
  package remains installed but no longer runs or autostarts.
- Notification daemons: NONE besides Void Shell (no mako, dunst,
  swaync) — Void Shell owns the org.freedesktop.Notifications layer.
- Hyprland autostart (`hl.on("hyprland.start")`) launches:
  awww-daemon + wallpaper, hyprpolkitagent, terminal, cliphist
  watcher, hypridle, **`qs -c voidshell --no-duplicate`**. The old
  `qs -c myshell` and `waybar` lines were removed 2026-10-02
  (`~/dotfiles` commit `1e5353f`); change takes effect at next login —
  `hyprland.start` does not re-fire on `hyprctl reload`.
- Keybinds now point at Void Shell IPC: Super+D/O/Space/M,
  Super+Shift+D (dashboard), Super+Shift+M (task manager),
  Super+W (overview). The previous `qs -c myshell ipc …` binds were
  dead — myshell registers no IPC targets.

## Hardware / service integrations available

| Integration | Backend | State |
|---|---|---|
| Audio | PipeWire 1.6.8 + WirePlumber (all active) | sink `Built-in Audio Analog Stereo` vol 1.00, currently MUTED |
| Wi-Fi | NetworkManager | connected (`Ravi 5G`) |
| Bluetooth | bluez 5.87, controller `Loki` B4:6B:FC:5E:6B:80 | service active, powered on |
| Battery | UPower `battery_BAT0` | discharging, 65%, ~2.9h empty |
| Backlight | `intel_backlight` via brightnessctl | 7500/7500 (100%) |
| MPRIS | playerctl | no players currently, service usable |
| Power profiles | — | UNAVAILABLE (`power-profiles-daemon` not installed) |

## Existing configs (preserved, not modified)

- `~/.config/hypr/hyprland.lua` + `config/{monitors,environment,permissions}.lua`
  + `hypridle.conf` — backed up to
  `~/dotfiles-backups/voidshell-baseline-20260915-154555/hypr/`
  (verified byte-identical after copy).
- `~/.config/quickshell/myshell` stow symlink and its `~/dotfiles`
  source tree — DELETED 2026-10-02 (dotfiles commit `967e411`;
  history retains the old files at `dfe7d37`).
- No `~/.config/waybar/` exists — nothing to back up.

## Project directory

- `~/.config/quickshell/voidshell/` — the production Void Shell build
  (git repository). Full deliverable set: `shell.qml`, `common/`,
  `services/` (26 singletons), `modules/` (14), `scripts/` (4 gates),
  `docs/` (design-system, architecture, features, performance,
  testing, dependencies), `README.md`, this file.
