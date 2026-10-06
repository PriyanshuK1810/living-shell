# Living Kitty — configuration notes

Ink-glass terminal for the Void Shell desktop (Arch + Hyprland +
Quickshell). Design reference: `~/Downloads/Ink-Wash Arch Terminal
Desktop.png` — slanted glass pills, violet borders, ink-wash
wallpaper, compact project-aware tabs.

Everything here was written against the **installed** kitty 0.49.2 and
verified at runtime; nothing was copied from docs of a different
version. Options this version does not have are listed under
*Omissions* rather than being set anyway.

**Reload:** kitty watches its config and included files, so edits
apply live. `kitty --config <file>` is for experiments only — the
shipped entry point is the default `~/.config/kitty/kitty.conf`.

---

## 1. Layout of the config

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
└── choose-files.conf           kitten choose-files styling + previews
```

`open-actions.conf`, `quick-access-terminal.conf` and `choose-files.conf`
are **not** included by `kitty.conf`: they are read by kittens with
their own syntax. Including them would be a parse error.

`kitty.conf` carries only the feature index; each feature lives in one
`conf.d/` file so a single file can be deleted to disable it. That is
how `95-tools.conf` is designed: remove it and lazygit's binding
disappears while git itself keeps working.

---

## 2. Design language

Sampled from the Void Shell bar's dark tokens (`services/ThemeService.qml`,
`common/Colors.qml`), so the terminal and the bar are one visual system:

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

## 3. Tabs

`conf.d/40-tabs.conf` + `tab_bar.py`:

- Compact tab bar, tabs sized to **content width** (not equal shares)
  using `extra_data.for_layout`, so a tab hugs its own title.
- Slanted right edge (the design reference's pill cut) drawn in Python.
- Active pill `#2A1A4D`, violet accent `#653ABB`; inactive tabs stay
  legible rather than dimming to nothing.
- Title classification: `git`, `lazygit`, `jj`, `tig`, `ssh`, `sudo`
  get a distinct marker, so an SSH session is recognisable at a glance
  without reading the title.

---

## 4. Keybindings

One leader, group letters, never random hotkeys. `map_timeout` is 0, so
a lone leader press is a no-op and chains never wait on you.

```
Ctrl+Shift+Space            leader (chain prefix)
  c             command palette
  s>s / v / h   new window / vsplit / hsplit
  s>c           close window
  w>h j k l     focus: left / bottom / top / right
  w>← ↑ ↓ →     resize: narrower / shorter / taller / wider
  w>e / m / r   equalize / toggle stack / reset sizes
  t>c / n / p / q   new tab / next / previous / close tab
  p>n / t / s   nvim tab / new tab with cwd / set tab title
  f>c / d       choose-files (files / dirs)
  h>u p e l f c w i   hints: url / path-open / path-nvim / line / linenum / hash / word / ip
  o>↑ ↓ 0 r g   opacity up / down / default / readability / glass
  l>t / s / k / n   layouts: tall / splits / stack / next
  b             broadcast to all windows
  g>g           lazygit (conf.d/95-tools.conf)
  g>l / g>s     git log / git status in a held tab
```

Notes that matter in practice:

- **Git views use `launch --hold --type=tab --cwd=current`.** Without
  `--hold` the command exits in milliseconds and kitty closes the tab
  it just opened, so the output flashes by unreadable. `--cwd=current`
  keeps the view in the directory you are working in.
- **`kitty --session` has no remote-control action**, so full sessions
  are launched from the shell (`kproject`, `ksession`, or
  `kitty --session <file>`); the leader+p keys only open
  project-oriented tabs in the current directory.
- **Opacity/readability are on arrows**, not `+`/`-`: kitty's key
  parser treats a bare `+` as a modifier separator, so a `+` binding
  would silently never fire. `o>r` sets opacity 1 with white-on-black;
  `o>g` restores the glass palette.
- The **shader cannot be toggled at runtime** — `custom_shaders` is
  read at config load only (see §8).
- kitty defaults are kept and documented in `60-keymaps.conf` rather
  than remapped (Ctrl+Shift+C/V copy/paste, Ctrl+Shift+T/W tab open and
  close, Ctrl+Shift+/ search, Ctrl+Shift+Z/X prompts, Ctrl+Shift+E url
  hints, Ctrl+Shift+A>… opacity, Ctrl+Shift+F3 palette, …). Hyprland
  binds only `Super+<key>`, so nothing here is swallowed.

---

## 5. Sessions

Four session files in `sessions/`, each a kitty session command file:

| session | contents |
|---|---|
| `default` | one tab, one window — the plain terminal |
| `development` | nvim + build + git tabs in the project dir |
| `server` | ssh/log tabs (needs openssh — now installed, see §11) |
| `arch-desktop` | the desktop shell session |

Session files accept **only** session commands — no shell commands, no
`kitty` invocations — so opening one cannot execute arbitrary text.

Launch paths:

```sh
kitty --session ~/.config/kitty/sessions/development.conf
kproject          # fzf picker (fd for listing, find as fallback)
ksession dev      # helper from shell/void-kitty.sh
```

`kproject` lists session files with `fd -e conf` when `fd` exists and
falls back to plain `find` otherwise; neither tool is a hard
dependency. Both branches produce identical basenames on this machine
(verified).

---

## 6. Quick-access terminal (Super+grave)

`quick-access-terminal.conf` + the Hyprland bind
(`~/dotfiles/hypr/.config/hypr/hyprland.lua`):

```lua
hl.bind(mainMod .. " + grave", hl.dsp.exec_cmd("kitten quick-access-terminal"))
```

- Panel namespace `kitty-quick-access`, instance group
  `quick-access`, so repeated presses reuse one panel.
- Measured on this machine: 896×321 logical at (192, 146) — it covers
  the bar's vertical span without covering the workspace strip.
- `hide_on_focus_loss yes` returns it to the bar when focus moves.
- Hyprland layer rule `kitty-quick-access-blur` applies the compositor
  blur to the panel (the blur is *visible* in screenshots — verified).
- The kitten **blocks while the panel is open**, so it is launched
  detached (`setsid … </dev/null &`); a foreground launch would hang
  the launcher that started it.
- `--single-instance` is deliberately not used: with it, later `-o`
  overrides are ignored by an existing panel.
- Because the panel is a normal kitty window, the background shell, OSC
  integration and the island bridge all keep working inside it.

---

## 7. Remote control, watcher and the island bridge

`conf.d/90-integrations.conf`:

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
JobBridge (`publish` / `update` / `finish` / `announce`). Classification
is conservative — unknown commands are `other` and produce no island
state — and state priority is deterministic, so a command that changes
title mid-run cannot regress a published activity. Reports are detached,
argument-only subprocesses; the watcher never blocks.

One real bug was found and fixed during verification: the watcher
addressed the **parent's** socket when kitty was launched from inside
another kitty (in-process, `KITTY_LISTEN_ON` still holds the parent's
address), so stale-address tab titles were being sent to the wrong
instance. The fix is `_socket_address(boss)` using `boss.listening_on`
only (rejecting non-`unix:` values) plus threading `boss` through
`_set_tab_title` / `_handle_start` / `_handle_end`.

---

## 8. Custom shaders (needs `shader-slang`)

kitty 0.49 compiles Slang shaders with `slangc`; `slangc` must be on
`PATH` (or `SLANGC` set). Install with `sudo pacman -S shader-slang`.

`shaders/dim-inactive-panes.pipeline` reuses kitty's shipped
`focus-highlight` shader with the animation stripped and the glow
removed:

| pipeline value | setting | why |
|---|---|---|
| `animation_step` | `0` | static — redraws only when focus or content changes, no per-frame cost |
| `HIGHLIGHT_INTENSITY` | `0` | the focused pane is never brightened (no glow) |
| `BORDER_WIDTH` | `0` | no edge glow anywhere |
| `INACTIVE_DIM` | `0.86` | 14% darker — focused pane reads as focused at a glance |
| `INACTIVE_DIM_COLOR` | `float3(0.00303, 0.00246, 0.00518)` | #0A0810 in **linear** RGB, so dimming cools toward the palette instead of grey |
| `DIM_CENTRAL_AREA_ONLY` | `true` | tab bar and frame stay outside the effect |
| `INCLUDE_WINDOW_PADDING` | `true` | the focused pane keeps its own padding undimmed |

**Verification (runtime, not just parsing):** both panes of a split were
painted the same red, then focus was swapped with `leader w>h`.

```
shot 1: left pane (inactive) 239,1,2   right pane (active) 255,0,0
shot 2: left pane (now active) 255,0,0 right pane (now inactive) 239,1,2
```

239/255 = 0.937 ≈ 0.86^(1/2.2) — exactly the linear-space dim, and it
**follows focus** (values swapped). Active panes stay exactly 255, i.e.
no brightening. A fresh instance starts with an empty log, so the
pipeline compiles without warnings; if `slangc` were missing, kitty logs
one clear error and runs unshaded — nothing else breaks.

**Limitation:** `custom_shaders` is read at config load only, so there
is no runtime toggle; the inactive-pane dim cannot be switched off
without a config reload. Documented in `conf.d/30-window.conf` and
`conf.d/60-keymaps.conf`.

---

## 9. Notifications

`conf.d/80-notifications.conf`:

```conf
enable_audio_bell            no
visual_bell_duration         0.0
notify_on_cmd_finish         invisible 8.0 notify
```

- No audio or visual bell: attention comes from tab activity and the
  Living State Island, which already reports state.
- `invisible 8.0 notify` = a command that took ≥ 8 s and finished while
  the window was **unfocused and not visible** (e.g. in an inactive
  tab) raises a desktop notification. Commands that finish in a visible
  window stay silent — the island announces those as transient state
  instead, so two surfaces never shout at once.
- **E2E verified:** a `sleep 10` started in a tab, then focus moved away
  with `leader t>p`, produced a real
  `org.freedesktop.Notifications.Notify` method call with body
  `Command sleep 10 finished with status: 0.` + "Click to focus."
  (sanitised: command name only). A window started with
  `launch -- sleep 10` produces no notification, correctly — the option
  requires shell-integration prompt marks, which a non-shell window
  never emits.

---

## 10. Optional tools (`conf.d/95-tools.conf`)

| tool | status on this machine | wired into kitty? |
|---|---|---|
| `lazygit` | installed | yes — `leader g>g`, bound in `95-tools.conf` |
| `bat` | installed | no — no kitty option consumes it; shell tool |
| `fd` | installed | yes — `kproject` lists sessions with `fd`, `find` fallback |
| `eza` | installed | no — never aliased over `ls`; config must launch on machines without it |
| `fzf` | present | `kproject`'s picker (numbered menu fallback) |
| `openssh` | installed (10.5p1) | `kssh` → `ssh`; SSH tab accent + island state verified E2E |
| `shader-slang` | installed | `custom_shaders` (§8) |
| `pygments` | **not needed** | see below |

`python-pygments` is deliberately **not** an install requirement: kitty
0.49's `kitten diff` and `choose-files` highlight with the Go highlighter
built into the kitten (chroma, with the `github-dark` style that
`choose-files.conf` sets) — no `import pygments` and no `pygmentize`
exist anywhere in the installed kitty. Verified empirically on this
machine: `kdiff` on two Python files renders coloured output with
nothing installed, and the kitty binary ships with zero pygments
references. The `*_pygments_style` options are legacy option names.

---

## 11. Omissions (deliberate, with reasons)

| not done | why |
|---|---|
| `fat` layout | kitty 0.49.2 has no `fat` layout — `enabled_layouts tall,splits,stack` lists what exists |
| zsh + starship | not installed; bash 5.3 with kitty's `shell_integration enabled` gives prompt marks, cwd titles and command tracking — the same capabilities. Intentional deviation, not an oversight |
| `--debug-config` in validation | kitty 0.49.2 has no such CLI flag; `scripts/validate-config.py` drives kitty's own parsers instead (0 problems, exit 0) |
| runtime shader toggle | `custom_shaders` is load-time only (§8) |
| CSD titlebar colour option | decorations are hidden (`hide_window_decorations yes`), so the option would do nothing |
| kitty's Wayland `background_blur` | Hyprland does not implement it; blur comes from the compositor rule |
| SSH tab state end-to-end | verified with the real openssh client: `kssh` (no args) prints ssh usage, and `ssh build@192.0.2.1` (≥8 s) produced tab title `ssh: build@192.0.2.1` with `overridden=True`, the island's "SSH session" activity, then title restore + activity clear on exit |
| hard dependencies on bat/eza | the terminal must launch on machines where they are absent |

---

## 12. Validation performed

```sh
cd /tmp/opencode && python3 ~/.config/kitty/scripts/validate-config.py
# 0 problem(s), exit 0 — kitty.conf parsed by kitty's own loader,
# tab_bar.py / desktop_state.py compiled, all four kitten conf files
# validated against their own option specs, sessions parsed, bash -n
# on every script
```

Runtime matrix (fresh kitty instance, `kitten @` remote control, real
key injection through Hyprland's `send_shortcut`):

| area | result |
|---|---|
| Keybinding matrix (tabs, layouts, splits/panes, opacity, overlays, broadcast, git/tools) | 28/31 first run — 3 failures were harness typing artifacts, re-run clean: 6/6 |
| `g>g` lazygit / `g>l` git log / `g>s` git status / `p>t` new tab | all open in the right tab, in the repository |
| `kdiff` colour | renders coloured output with no pygments installed |
| `kproject` | fzf picker lists all four sessions (fd branch) |
| Custom shader | 239 vs 255 pixel proof, dim follows focus (§8) |
| Quick-access terminal | layer `kitty-quick-access` mapped 896×321 @192,146; paints over the bar; returns to wallpaper on toggle-off and restores on toggle-on; blur rule visibly applied |
| Watcher → island E2E | 14/14 (unknown/fast/silent commands never reach the island; build publishes at start, finishes and clears; ssh/root produce the right tab titles and restore) |
| `notify_on_cmd_finish` | real D-Bus `Notify` for a hidden ≥8 s command (§9) |
| Fresh instance stderr | empty — no shader or config warnings |
| `hyprctl configerrors` | empty |
| voidshell gates | 8/8 PASS (check, smoke, popup, tab, coord, hardening, island, shelf) |

Test harnesses live in `/tmp/opencode/kittytest/` (`test-matrix.sh`,
`test-git-tools.sh`, `test-watcher.sh`, `test-qat.sh`,
`validate-config.py`); they are throwaway probes, not part of the
shipped config.

---

## 13. Limitations

- Shader cannot be toggled at runtime (§8).
- `kssh` is a thin `exec ssh "$@"` wrapper, not a session manager.
- `notify_on_cmd_finish` needs bash shell integration; a program run
  outside a shell (e.g. `launch -- cmd`) is never notified.
- The quick-access kitten blocks while its panel is open, so it must be
  launched detached; anything that foreground-launches it will hang.

## 14. Future improvements

- Per-workspace shader profiles once kitty exposes a runtime shader API.
- A `bat`-backed `kdiff` preview mode (optional, `command -v` guarded).
- Session templates generated from a single source so the four session
  files cannot drift apart.
