# Living Shell

A complete desktop environment for **Arch Linux + Hyprland**: a
Quickshell-based desktop shell with a Living State Island, and a
matching ink-glass **kitty** terminal — designed as one visual system,
wired together through local IPC.

```text
living-shell/
├── voidshell/    # the desktop shell  (Quickshell + QML)
│   ├── README.md # full shell documentation
│   └── …
└── kitty/        # the terminal       (kitty 0.49 config)
    ├── README.md # full terminal documentation
    └── …
```

| | **Void Shell** | **Living Kitty** |
|---|---|---|
| What | top bar, 10 popups, 5-tab dashboard, Living State Island, theming, notifications, calendar, media, lock screen | ink-glass terminal, leader keybindings, slanted tabs, Slang shader, quick-access drop-down, island watcher |
| Runtime | Quickshell 0.3.1 + Qt 6.11 | kitty 0.49.2 + Hyprland 0.56.2 |
| Docs | [`voidshell/README.md`](voidshell/README.md) | [`kitty/README.md`](kitty/README.md) |

## How they fit together

- **One palette.** The terminal's tokens (`#0A0810` ink, `#653ABB`
  violet, parchment text) are sampled from the shell's dark theme, so
  the bar and the terminal read as the same product.
- **One island.** kitty's watcher (`watchers/desktop_state.py`)
  classifies long-running commands and publishes them to the shell's
  **Living State Island** through the existing `job` IPC target — no
  second notification system, no new daemons.
- **One terminal surface.** `Super + grave` opens kitty's quick-access
  terminal as a blurred layer panel directly under the bar.
- **Verified together.** The shell's 8 QA gates and the terminal's
  runtime matrix were run on the same machine, against the same config.

## Quick start

```sh
# 1. the desktop shell
git clone <this-repo> /tmp/living-shell
cp -r /tmp/living-shell/voidshell ~/.config/quickshell/voidshell
qs -d -c voidshell --no-duplicate        # start the shell

# 2. the terminal
cp -r /tmp/living-shell/kitty ~/.config/kitty
# kitty watches its config — open a new kitty window and it applies
```

Hyprland integration (both sides) lives in your Hyprland config:
autostart for `qs -c voidshell`, the `Super + grave` bind, and the
`kitty-quick-access-blur` layer rule. See each project's README.

## Requirements

| Component | Version | Used by |
|---|---|---|
| Arch Linux | rolling | both |
| Hyprland | 0.56.2 (Lua config) | both |
| Quickshell | 0.3.1 | voidshell |
| Qt 6 (declarative + svg) | 6.11+ | voidshell |
| kitty | 0.49.2 | kitty |
| shader-slang | recent | kitty (Slang shaders) |
| bash | 5.3 | both (shell integration) |

Recommended extras — everything degrades gracefully and says so in the
UI when a tool is missing: `grim`/`slurp`, `wf-recorder`, `playerctl`,
`awww`, `hyprlock`, `hypridle`, `bluez`, `networkmanager`, `pipewire`,
`brightnessctl`, `jq`, `lazygit`, `fd`, `openssh`. Full matrix:
`voidshell/docs/dependencies.md` and `kitty/README.md`.

## Design principles

1. **Text readability first.** Ink-black surfaces, parchment text, no
   neon, no RGB, no fake macOS controls.
2. **No invented options.** Every config option was verified against
   the installed version; what the version lacks is documented as an
   omission, not faked.
3. **No hard dependencies.** The shell and the terminal launch and work
   on a machine without any of the optional tools.
4. **Honest state.** Missing integrations report `missing`/disabled
   with a reason; nothing pretends to work.
5. **Local-only IPC.** No TCP, no passwords in files — UNIX sockets in
   `$XDG_RUNTIME_DIR` and Quickshell's own IPC.
6. **Every claim tested.** 8 shell QA gates + the terminal's runtime
   matrix (keybindings, shader pixels, watcher E2E, notifications) were
   executed on this machine.

## Testing

```sh
# shell gates (run from voidshell/)
./scripts/check.sh && ./scripts/smoke-test.sh
./scripts/popup-check.sh && ./scripts/tab-check.sh
./scripts/coord-check.sh && ./scripts/shelf-check.sh
./scripts/hardening-check.sh && ./scripts/island-check.sh

# terminal validation
python3 ~/.config/kitty/scripts/validate-config.py   # 0 problems, exit 0
```

Methodology and the full checklist: `voidshell/docs/testing.md`
(includes the terminal/QAT section, §3b).

## Customizing

- **Shell colors/geometry** → `voidshell/common/Colors.qml`,
  `voidshell/common/Theme.qml` — every surface binds to one token set.
- **Terminal palette** → `kitty/conf.d/20-colors.conf` (sampled from
  the shell).
- **Terminal keybindings** → `kitty/conf.d/60-keymaps.conf` (leader =
  `Ctrl+Shift+Space` + group letters) and `kitty/conf.d/95-tools.conf`
  (optional tools; delete the file to disable them).

## Repository layout

Each project is self-contained with its own README, docs and test
scripts — clone either folder alone and it still works.

| path | contains |
|---|---|
| `voidshell/` | shell entry point, 40+ services, 14 modules, 8 QA gates, `docs/` |
| `kitty/` | modular `conf.d/` config, tab bar, shader, watcher, sessions, helpers |

## License

MIT — do what you want with it. If it saves you time, that's the point.
