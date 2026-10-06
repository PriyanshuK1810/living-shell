# VOID SHELL — Dependencies

Validated: 2026-09-15 (Phase 2: Dependency Validation).
Policy: official Arch packages only. No `-git` variants introduced.
Nothing was installed in this phase — every required capability already
resolved. Post-validation `qs --version`: Quickshell 0.3.1 (Arch).

## Required dependencies

| Required capability | Purpose in Void Shell | Installed Arch package | Optional? |
|---|---|---|---|
| Quickshell | Shell runtime (layer-shell windows, system services, IPC) | `quickshell 0.3.1-1` | No |
| QtQuick | QML scene graph for all UI | `qt6-declarative 6.11.2-2` | No |
| QtQuick.Shapes | Slanted parallelogram glass pills (`Shape`/`ShapePath`); probe file importing both modules passes `qmllint` clean under Qt 6.11.2 | `qt6-declarative 6.11.2-2` (ships `QtQuick/Shapes` plugin) | No |
| Qt SVG | SVG icon rendering (app/system icons) | `qt6-svg 6.11.2-1` | No |
| NetworkManager | Wi-Fi state and control (Quickshell `Networking` / `nmcli` fallback) | `networkmanager 1.58.1-1` | No |
| BlueZ | Bluetooth state and control (`bluetoothctl` verified active/powered) | `bluez 5.87-2`, `bluez-utils 5.87-2` | No |
| PipeWire / WirePlumber | Audio backend (sinks/sources/volume/mute; all user units active) | `pipewire 1:1.6.8-1`, `wireplumber 0.5.17-1` | No |
| JSON utility | Config/state parsing in scripts and services | `jq 1.8.2-1` | No |
| Outfit font | Primary UI typeface (`fc-match Outfit` → Outfit Regular) | user-local `Outfit[wght].ttf` | No |
| JetBrains Mono Nerd Font | Icons / mono (`fc-match` → Regular; 96 faces present) | `ttf-jetbrains-mono-nerd 3.5.1-2` | No |

## Optional dependencies (NOT installed)

| Package | Feature it would enable | Decision |
|---|---|---|
| `power-profiles-daemon` | Power-profile switching in quick settings | Deferred — install only if the feature is enabled in a later phase |
| `pacman-contrib` | Update-count widgets (e.g. `checkupdates`) | Deferred — same condition |
| `hyprsunset` | Night-light control | Deferred — same condition |
| Any `-git` variant | — | Rejected unless a verified unavoidable requirement appears |

## Notes

- `qtpaths6` is not on PATH; harmless — `qmake6` confirms Qt 6.11.2.
- No version conflicts detected; Qt / Quickshell / Hyprland 0.56.2 are
  the current Arch builds and interoperate (prototype bar runs clean).
