# Living Kitty Terminal

A complete, modular kitty configuration for the Void Shell desktop
(Arch Linux + Hyprland + Quickshell). Ink-black translucent glass,
violet accents, compact slanted tabs, a leader-driven keybinding
system, a quick-access drop-down terminal, custom Slang shaders, and a
watcher that publishes command state to the **Living State Island** —
all validated at runtime against the installed kitty 0.49.2.

Everything here was written against what this machine actually has.
Nothing was copied from docs of a different version, and every feature
that ships was executed and verified before it was documented.

---

## Requirements

| Component | Version | Notes |
|---|---|---|
| Arch Linux | rolling | target platform |
| kitty | 0.49.2 | config is version-locked to what it was verified on |
| Hyprland | 0.56.2 (Lua config) | compositor, layer-shell, blur |
| Quickshell | 0.3.1 | Living State Island side (optional — see below) |
| shader-slang | any recent | `slangc` — custom shader compiler |
| lazygit | any recent | `leader g>g` only |
| fd | any recent | `kproject` session listing (find fallback exists) |
| openssh | 10.5p1 | `kssh` and SSH tab/island state |
| bash | 5.3 | shell integration (zsh is **not** used — intentional) |

**Optional, never required:** bat, eza, fzf, pygments
(python-pygments is *not* needed — kitty highlights with the Go
highlighter built into its kittens, verified on this machine).

The terminal launches and works with none of the optional tools
present. Nothing in the config hard-depends on a program that may be
absent.

---

## Install

```sh
# 1. back up anything you already have
mv ~/.config/kitty ~/.config/kitty.bak-$(date +%Y%m%d-%H%M%S) 2>/dev/null

# 2. clone or copy this config into place
git clone <THIS_REPO_URL> ~/.config/kitty

# 3. reload kitty (kitty watches its config, so this applies live)
#    or just start a new kitty window
```

If you use the Void Shell desktop, also wire the Hyprland side:

```sh
# from your dotfiles repo: the Super+grave bind and the blur rule
# live in hypr/.config/hypr/hyprland.lua — see "Hyprland integration"
```

And the shell helpers (`kq`, `ksession`, PATH entry):

```sh
# already handled: ~/.bashrc sources shell/void-kitty.sh
# (guarded, idempotent — safe to re-run)
```

---

## What's in the box

```
~/.config/kitty/
├── kitty.conf                  index + `globinclude conf.d/*.conf`
├── conf.d/
│   ├── 10-fonts.conf           font fallback chain, glyph coverage
│   ├── 20-colors.conf          ink/violet palette (sampled from the bar)
│   ├── 30-window.conf          glass, padding, cursor, chrome, shaders
│   ├── 40-tabs.conf            compact slanted tabs
│   ├── 50-layouts.conf         enabled_layouts tall,splits,stack
│   ├── 60-keymaps.conf         leader hierarchy (Ctrl+Shift+Space)
│   ├── 70-shell.conf           bash integration, scrollback, editor
│   ├── 80-notifications.conf   bell policy, long-command notify
│   ├── 90-integrations.conf    hyperlinks, clipboard, RC socket, watcher
│   └── 95-tools.conf           optional external tools (lazygit)
├── tab_bar.py                  slanted, content-width tab pills
├── shaders/
│   └── dim-inactive-panes.pipeline   Slang pipeline (needs slangc)
├── watchers/
│   └── desktop_state.py        command watcher → Living State Island
├── sessions/                   arch-desktop, default, development, server
├── scripts/                    kproject kimg kdiff kssh validate-config.py
├── shell/void-kitty.sh         sourced from ~/.bashrc (PATH, kq, ksession)
├── open-actions.conf           hyperlink/file opening policy
├── quick-access-terminal.conf  Super+grave drop-down terminal
├── choose-files.conf           kitten choose-files styling + previews
└── docs/kitty.md               full documentation
```

`open-actions.conf`, `quick-access-terminal.conf` and
`choose-files.conf` are **not** included by `kitty.conf` — they are
read by kittens with their own syntax. Including them would be a parse
error.

Each feature lives in one `conf.d/` file so a single file can be
deleted to disable it. That is how `95-tools.conf` is designed: remove
it and lazygit's binding disappears while git itself keeps working.

---

## Design language

Sampled from the Void Shell bar's dark tokens, so the terminal and the
bar are one visual system:

- **Surfaces** — ink-black translucent (`#0A0810`), opacity 0.91 with
  dynamic opacity enabled; blur is Hyprland's (`decoration.blur`), not
  kitty's — `background_blur 0` because Hyprland does not implement
  kitty's Wayland blur request.
- **Accents** — violet (`#653ABB` border, `#2A1A4D` active pill),
  with small gold/cyan/green used only where they mean something.
- **Text first** — parchment `#F0E8E1` on ink; no neon, no RGB, no
  decorative gradients, no fake macOS traffic lights (kitty's own
  decorations are hidden and Hyprland draws a 2px violet border,
  rounding 12, gaps 4/8).
- **Fonts** — `Maple Mono NF` → `JetBrainsMono NF` → `CaskaydiaCove` →
  `FiraCode`; only JetBrainsMono NF exists on this machine, which is
  what the chain resolves to.

---

## How the keybindings work

`Ctrl+Shift+Space` is a **prefix key**, not an action. Press it,
release, then type the command as letters — like typing a word.

```
Ctrl+Shift+Space    →  S    →  V
   (leader)          (splits)  (vertical)
```

Three separate presses, not a hold-combo. You never hold the leader
while pressing the letters.

- Press the leader and walk away → nothing happens, no delay, no menu.
- Press an unbound letter → nothing happens, no stuck state to clear.
- `map_timeout` is 0, so there is no invisible countdown.

### Group letters

| letter | think of it as | example chains |
|---|---|---|
| `s` | **s**plits — make panes | `s>v`, `s>h`, `s>c` |
| `w` | **w**indow pane — focus/size | `w>l`, `w>←`, `w>e` |
| `t` | **t**abs | `t>c`, `t>n`, `t>q` |
| `p` | **p**roject | `p>n`, `p>t` |
| `f` | **f**iles | `f>c`, `f>d` |
| `h` | **h**ints (label things on screen) | `h>u`, `h>c` |
| `o` | **o**pacity | `o>↑`, `o>r` |
| `l` | **l**ayout | `l>t`, `l>s` |
| `c` | **c**ommand palette | `c` (one letter only) |
| `b` | **b**roadcast | `b` (one letter only) |
| `g` | **g**it | `g>g`, `g>l`, `g>s` |

---

## Complete keybinding reference

### Splits — `leader s`
| Key | Action |
|---|---|
| `s s` | new window |
| `s v` | new vertical split |
| `s h` | new horizontal split |
| `s c` | close window |

### Panes — `leader w`
| Key | Action |
|---|---|
| `w h / l / k / j` | focus left / right / top / bottom |
| `w ← / → / ↑ / ↓` | resize narrower / wider / shorter / taller |
| `w e` | equalize all panes |
| `w m` | toggle stack layout |
| `w r` | reset window sizes |

### Tabs — `leader t`
| Key | Action |
|---|---|
| `t c` | new tab |
| `t n` | next tab |
| `t p` | previous tab |
| `t q` | close tab |

### Project — `leader p`
| Key | Action |
|---|---|
| `p n` | nvim in a new tab (current dir) |
| `p t` | new tab in current dir |
| `p s` | set tab title (prompts) |

### Files — `leader f`
| Key | Action |
|---|---|
| `f c` | choose-files kitten (files) |
| `f d` | choose-files --mode=dir |

### Hints — `leader h`
| Key | Action |
|---|---|
| `h u` | URL hints → open |
| `h p` | path hints → run on stdin |
| `h e` | path hints → open in nvim (new tab) |
| `h l` | line-number hints → stdin |
| `h f` | line-number hints (jump) |
| `h c` | commit-hash hints → `git show` in a held tab |
| `h w` | word hints → stdin |
| `h i` | IP-address hints → stdin |

### Opacity & readability — `leader o`
| Key | Action |
|---|---|
| `o ↑ / ↓` | opacity +0.05 / −0.05 |
| `o 0` | opacity back to default (0.91) |
| `o r` | **readability mode** — opacity 1, white-on-black |
| `o g` | **glass mode** — default opacity, restores the ink palette |

### Layouts — `leader l`
| Key | Action |
|---|---|
| `l t / s / k` | tall / splits / stack |
| `l n` | next layout |

### Broadcast — `leader b`
Takes over input and echoes it to every kitty window in this instance.
`Ctrl+Escape` gets your keyboard back.

### Git — `leader g`
| Key | Action |
|---|---|
| `g g` | lazygit in a new tab (current repo dir) |
| `g l` | `git log --oneline -30` in a held tab |
| `g s` | `git status --short --branch` in a held tab |

### Discovery — `leader c`
Command palette (also on kitty's default `Ctrl+Shift+F3`).

### Hyprland side
| Key | Action |
|---|---|
| `Super+Q` | launch a new kitty window |
| `Super+grave` (`) | toggle the quick-access terminal |

### Kitty defaults kept (deliberately not remapped)
```
Ctrl+Shift+C / V      copy / paste
Ctrl+Shift+Enter      new window
Ctrl+Shift+T / W / Q  new tab / close window / close tab
Ctrl+Shift+/          search scrollback
Ctrl+Shift+Z / X      previous / next prompt
Ctrl+Shift+H          show scrollback
Ctrl+Shift+G          last command output
Ctrl+Shift+E          URL hints
Ctrl+Shift+P>…        choose file / directory
Ctrl+Shift+A>…        opacity
Ctrl+Shift+[ / ]      previous / next window
Ctrl+Shift+← / →      previous / next tab
Ctrl+Shift+1…0        jump to window N
Ctrl+Shift+F3         command palette
Ctrl+Shift+F10 / F11  maximize / fullscreen
Alt+T                 set tab title
Ctrl+Shift+R          interactive resize
```

### Operational notes
- **Opacity uses arrows, not `+`/`-`** — kitty's key parser treats a
  bare `+` as a modifier separator, so a `+` binding would silently
  never fire.
- **kitty confirmation dialogs need `Escape`/`Y`** (not `ESC`).
- **`h>c` uses `--hold`** — without it `git show` exits instantly and
  the tab closes before the commit is readable.
- The inactive-pane dim shader has **no runtime toggle** (kitty reads
  `custom_shaders` at config load only); `o>r`/`o>g` switch opacity
  and colors but not the shader.

---

## Sessions

Four session files in `sessions/`:

| session | contents |
|---|---|
| `default` | one tab, one window — the plain terminal |
| `development` | nvim + build + git tabs in the project dir |
| `server` | ssh/log tabs |
| `arch-desktop` | the desktop shell session |

```sh
kitty --session ~/.config/kitty/sessions/development.conf
kproject          # fzf picker (fd for listing, find as fallback)
ksession dev      # helper from shell/void-kitty.sh
```

Session files accept **only** session commands — no shell commands, no
`kitty` invocations — so opening one cannot execute arbitrary text.

---

## Quick-access terminal (Super+grave)

- Panel namespace `kitty-quick-access`, instance group `quick-access`,
  so repeated presses reuse one panel.
- Measured on this machine: 896×321 logical at (192, 146) — it covers
  the bar's vertical span without covering the workspace strip.
- `hide_on_focus_loss yes` returns it to the bar when focus moves.
- Hyprland layer rule `kitty-quick-access-blur` applies the compositor
  blur to the panel.
- The kitten **blocks while the panel is open**, so it is launched
  detached (`setsid … </dev/null &`); a foreground launch would hang
  the launcher that started it.
- `--single-instance` is deliberately not used: with it, later `-o`
  overrides are ignored by an existing panel.
- Because the panel is a normal kitty window, the background shell, OSC
  integration and the island bridge all keep working inside it.

---

## Custom shaders (needs `shader-slang`)

kitty 0.49 compiles Slang shaders with `slangc`. `shaders/dim-inactive-panes.pipeline`
reuses kitty's shipped `focus-highlight` shader with the animation
stripped and the glow removed:

| pipeline value | setting | why |
|---|---|---|
| `animation_step` | `0` | static — redraws only when focus or content changes |
| `HIGHLIGHT_INTENSITY` | `0` | the focused pane is never brightened |
| `BORDER_WIDTH` | `0` | no edge glow anywhere |
| `INACTIVE_DIM` | `0.86` | 14% darker — focused pane reads as focused |
| `INACTIVE_DIM_COLOR` | linear `#0A0810` | dimming cools toward the palette, not grey |
| `DIM_CENTRAL_AREA_ONLY` | `true` | tab bar and frame stay outside the effect |
| `INCLUDE_WINDOW_PADDING` | `true` | focused pane keeps its padding undimmed |

**Verified:** both panes painted the same red, then focus swapped —
inactive 239 vs active 255 (exactly the 14% linear dim), and the values
**swap with focus**. Active panes stay exactly 255 (no brightening).

If `slangc` is missing, kitty logs one clear error and runs unshaded —
nothing else breaks.

---

## Notifications

```conf
enable_audio_bell            no
visual_bell_duration         0.0
notify_on_cmd_finish         invisible 8.0 notify
```

A command that took ≥ 8 s and finished while the window was
**unfocused and not visible** (e.g. in an inactive tab) raises a desktop
notification. Commands finishing in a visible window stay silent — the
island announces those as transient state instead.

**E2E verified:** a `sleep 10` in a hidden tab produced a real
`org.freedesktop.Notifications.Notify` with body
`Command sleep 10 finished with status: 0.` A window started with
`launch -- sleep 10` produces no notification — the option requires
shell-integration prompt marks, which a non-shell window never emits.

---

## Remote control, watcher and the island bridge

```conf
allow_remote_control  socket-only
listen_on             unix:${XDG_RUNTIME_DIR}/kitty-{kitty_pid}
watcher               watchers/desktop_state.py
```

**Security decisions:**

- **No TCP, ever.** `socket-only` means control via a tty (an SSH
  session, another local terminal) is refused outright. There is no
  password file, no port, no listening address outside the session
  runtime directory.
- **UNIX socket in `$XDG_RUNTIME_DIR`** (`/run/user/1000`, mode 0700)
  — only the session owner can open it. `{kitty_pid}` keeps a second
  kitty from stealing the socket name. `fd:` addresses are rejected:
  they are handed to the spawning process and cannot be used safely by
  a watcher, so only `unix:` addresses are accepted.
- **Children inherit `KITTY_LISTEN_ON`**, so scripts address *their own*
  kitty with `kitten @` without any secret.
- **The watcher sanitises everything it reports.** Command text is
  classified, truncated and stripped of anything that could be a secret
  (environment-style `KEY=value` patterns, long opaque tokens) before
  it reaches the island; the island never sees raw command lines.
- **No new daemons, packages or network listeners** were added: the
  watcher is a per-kitty process, and island traffic goes through the
  existing `qs -c voidshell ipc call job …` JobBridge IPC.

**Watcher behaviour** (`watchers/desktop_state.py`): observes command
start/end and title changes, classifies the command (git build ssh
other), and publishes to the Living State Island through the existing
JobBridge. Classification is conservative — unknown commands are `other`
and produce no island state — and state priority is deterministic, so a
command that changes title mid-run cannot regress a published activity.
Reports are detached, argument-only subprocesses; the watcher never
blocks.

---

## Validation

```sh
cd /tmp && python3 ~/.config/kitty/scripts/validate-config.py
# 0 problem(s), exit 0
```

Runtime matrix (fresh kitty instance, `kitten @` remote control, real
key injection through Hyprland's `send_shortcut`):

| area | result |
|---|---|
| Keybinding matrix | tabs, layouts, splits/panes, opacity, overlays, broadcast, git/tools — all verified |
| `g>g` lazygit / `g>l` git log / `g>s` git status / `p>t` | open in the right tab, in the repository |
| `kdiff` colour | renders coloured output with no pygments installed |
| `kproject` | fzf picker lists all sessions (fd branch) |
| Custom shader | 239 vs 255 pixel proof, dim follows focus |
| Quick-access terminal | layer mapped 896×321 @192,146; paints over the bar; returns to wallpaper on toggle-off; blur rule visibly applied |
| Watcher → island E2E | 14/14 (unknown/fast/silent commands never reach the island; build publishes at start, finishes and clears; ssh/root produce the right tab titles and restore) |
| SSH (real openssh) | `kssh` prints ssh usage; `ssh build@192.0.2.1` ≥8 s → tab title `ssh: build@192.0.2.1`, `overridden=True`, island activity published, then title restore + activity clear on exit |
| `notify_on_cmd_finish` | real D-Bus `Notify` for a hidden ≥8 s command |
| Fresh instance stderr | empty — no shader or config warnings |
| `hyprctl configerrors` | empty |

---

## Limitations

- Shader cannot be toggled at runtime (kitty reads `custom_shaders` at
  config load only).
- `kssh` is a thin `exec ssh "$@"` wrapper, not a session manager.
- `notify_on_cmd_finish` needs bash shell integration; a program run
  outside a shell (e.g. `launch -- cmd`) is never notified.
- The quick-access kitten blocks while its panel is open, so it must be
  launched detached; anything that foreground-launches it will hang.
- `fat` layout does not exist in kitty 0.49.2 — `enabled_layouts
  tall,splits,stack` lists what actually exists.
- zsh + starship are not used (intentional): bash 5.3 with kitty's
  `shell_integration enabled` gives prompt marks, cwd titles and
  command tracking — the same capabilities.
- `--debug-config` does not exist in kitty 0.49.2 — the validator
  drives kitty's own parsers instead.

---

## Future improvements

- Per-workspace shader profiles once kitty exposes a runtime shader API.
- A `bat`-backed `kdiff` preview mode (optional, `command -v` guarded).
- Session templates generated from a single source so the four session
  files cannot drift apart.

---

## Related repositories

| repo | contains |
|---|---|
| **this one** | kitty terminal config (Living Kitty) |
| `voidshell` | the Quickshell desktop shell + Living State Island |
| `dotfiles` | Hyprland config (Super+grave bind, blur rule), bashrc |

---

## License

MIT — do what you want with it. If it saves you time, that's the point.
