# VOID SHELL — Features & Keybinds

Everything below is backed by real system state. Controls for hardware
or services that don’t exist are **present but disabled with a written
reason** — never fake data (PRD §37).

## 1. Top bar (PRD §1–4)

Three slanted glass pills, no background strip:

| Segment | Contents |
|---|---|
| Left | launcher pill (`A`), workspace dash pill (§17; numbered strip when the manager is off), active-app title pill (updates on focus change) |
| Center | `VOID SHELL` brand pill, clock pill (local time), date pill |
| Right | status tray — mic/DND state, battery, Wi-Fi, Bluetooth, volume, brightness, bell (notifications), recording indicator, power pill |

- Recording indicator shows a dot + elapsed while `wf-recorder` runs
  and disappears when it stops (no desync — PRD §12.5).
- Clock/date update on the minute; nothing ticks per second at idle.
- The centre clock is also the **Living State Island** renderer —
  events crossfade *inside* the same 170×56 pill and the stack opens on
  a separate surface below it (§23).
- The islands sit on the compositor's **Bottom** layer: a fullscreen
  app covers them like any other surface instead of living permanently
  in their shadow.

## 2. Popups (PRD §5–13) — one primary at a time

Anchored beneath their bar segment, monitor-aware (opens on the screen
of the source item, falls back to the primary screen). **Escape closes
any open popup** from a window-scope handler on every panel; transient
children (the Wi-Fi password dialog, the device context menu) take
Escape first, then the panel. Key delivery is real: quickshell defaults
layer surfaces to `WlrKeyboardFocus.None`, so every interactive surface
(popups, launcher, media, overview, dialog, menu) explicitly takes
**Exclusive** keyboard focus while mapped — without it no keystroke ever
reached the shell (typing, arrows, Enter and Escape were all dead).
Hyprland returns focus to the previously focused app when a surface
unmaps. The lock surface is the only exception —
only authentication dismisses it (PRD §13.1, §25), and it still runs at
the default `None` (its password field is decorative — hyprlock owns
auth — so its Enter-to-launch-hyprlock path needs keys and remains a
known, deliberately untouched same-root-cause gap).

| Popup | What’s inside |
|---|---|
| **Launcher** | fuzzy app search + keyboard launch, `@commands`, runnable actions (see §4) |
| **Calendar** | merged into the dashboard **Overview** tab (§3): month grid, prev/next/today navigation, local event store (`~/.local/share/voidshell/calendar.json`), day agenda, new-event form; the clock pill and the `calendar` IPC target open the dashboard there |
| **Media** | MPRIS artwork, title/artist/album, seek, prev/play-pause/next, shuffle/repeat, playlist when the player provides it; clear no-player state when no MPRIS player exists |
| **Quick settings** | Wi-Fi tile + saved/available networks, Bluetooth tile + paired/discovered devices, airplane tile; brightness slider reads/writes the real backlight (re-probed while the panel is open, so it tracks Fn-key changes), volume slider + mute. Expandable tiles carry a chevron in the state pill's spot — their subtitle states on/off, no separate On button. The dropdown lists are **fixed five-row viewports**: scan results update in place — the panel never resizes while devices stream in — and longer lists scroll behind a draggable scrollbar. Clicking a secured, unsaved network opens a **password dialog centered on the screen**, backed by `WifiNetwork.connectWithPsk` (a wrong key comes back as `connectionFailed(NoSecrets)` and renders inline). Right-click (two-finger tap) a paired Bluetooth row opens a **context menu at the pointer** — connect/disconnect, block/unblock, forget behind a two-step confirm; unpaired rows stay inert because quickshell registers no BlueZ agent to run pairing with (PRD §17.3). QA: `VOID_QS=list|dialog|menu` (+ `VOID_QS_POS=x,y` to pin the menu) |
| **Notifications** | server + history + DND; grouped cards, per-notification dismiss, clear-all, unread badge in the bar |
| **Power** | lock, logout, suspend, hibernate, reboot, poweroff — each **enabled only if the capability probe found a working backend**; confirmation step; tests never press these |
| **Dashboard** | four tabs, heading centered (§3) |
| **Task manager** | system monitor drawer (§6) |
| **Overview** | workspace overview (§7) |
| **Lock** | themed surface; authentication is performed by **hyprlock** (PAM). The surface dismisses only when hyprlock exits 0 (PRD §25) |

## 3. Dashboard tabs (PRD §22)

`overview · media · alerts · productivity` — switched from the tab
row (or `VOID_TAB=<id>` for QA); the heading is centered in every
tab.

**Reference-matched chrome**: the panel carries a violet glow edge
(`GlowBorder`) and an **ink-wash artwork texture** — five bundled
purple sumi-e scenes in `assets/dashboard/ink-1..5.jpg` (compressed
from the user's reference set, ~1.5 MB total), never the live
wallpaper: the panel carries the 4:3 scene and each Overview card
frames a **curated region** of its own scene — `InkTexture` gained
`focusX`/`focusY`/`zoom` (artwork point at the host's centre + cover
zoom, exposed as `GlassCard.textureFocusX/Y`/`textureZoom`), so the
five near-identical panoramas read as five distinct motifs (moon,
river, waterfall, comet, valley) instead of one centred crop in every
card. Artwork comes in through the new
`InkTexture.source` / `textureSource` pass-through on
PopupShell/GlassPanel/GlassCard (empty = live wallpaper fallback);
strength/veil are tuned for the dark assets (measured white-text
contrast >= 11:1 over every card, the clock moon kept clear of the
glyph column). The texture is
`common/components/InkTexture.qml`: QML `clip` is rectangular on this
Qt build (verified in an isolated quickshell instance), so it rides in
a layer masked by a rounded white rect — opt-in via
`GlassPanel.texture` / `GlassCard.texture` (default off; the popups
listed below opt in explicitly). The header shows a real weather glyph
pinned
left of the centered heading (fetched whenever the dashboard is open,
still hidden when the service has no data), and the tab row is a
centered **segmented pill bar**: icon + label, active pill filled
violet with a restrained glow, real unread badge on Alerts.

**Session-random panel textures** (`services/InkArt.qml`): the same
five scenes are also dealt to the other popup surfaces — quick
settings, notifications, power menu, task manager, the media popup,
the workspace-overview backdrop, the app drawer, and the wifi/device
dialogs. The singleton Fisher-Yates-shuffles the pool at shell start
and deals it round-robin over the panel keys, so every surface frames
its own region of a scene, the mapping stays stable for the whole
session and re-rolls on restart (no persistence, by choice — picked
in this session's QA). The bar, lock screen, toasts and wallpaper
overlay stay texture-free; the dashboard keeps its hand-curated
framing. Measured white-text contrast across the seven IPC-openable
surfaces: 5.4–15.8:1 (the two apparent near-misses resolved honestly —
the red Shut Down label is 5.5:1 under per-channel WCAG maths, and
Clear All reads 4.46:1 only in its disabled state, which WCAG
exempts). The wifi password dialog and device menu ride the same
`GlassPanel.texture` path as the verified media popup but were not
re-probed: the `VOID_QS=dialog` hook needs the network cache ready at
its fixed 1.9 s timer, and the device menu needs a paired Bluetooth
device (none on this box).

Overview is the home surface: clock, the **merged calendar**
(month grid, prev/next/today navigation, day agenda, event store — the
clock pill and the `calendar` IPC target open the dashboard here, and
closing resets to Overview) now **inside a glass card** like the rest
of the grid, the live weather card (≥15 min refresh), a compact media
card (artwork, title/artist, round glowing play button + transport,
real volume slider with mute), and a system identity card with an
outline glyph per row (user, OS, WM, kernel, host, uptime); media
mirrors MPRIS; alerts is the notification history view; productivity
holds the focus timer and task list. Expensive tab content is created
per visibility (§36).

## 4. Launcher commands & actions (PRD §6)

| Input | Result |
|---|---|
| *(text)* | fuzzy app search, Enter launches, arrows navigate |
| `@git [query]` | **local** repository browser: staged/unstaged/branch log per repo from the cached index — never commits, never mutates |
| `@containers` | Docker view (images/containers) when the Docker CLI exists; otherwise disabled with reason |
| `@color` | theme manager: presets, dark/light, dynamic wallpaper tone, reset |
| `@wp` | wallpaper manager: thumbnail grid from `~/Pictures/wallpapers`, tone lock, overlay mode row (Off/Visualizer/Clock/Clock+Lyrics) |
| `@web …` | web search / URL open (xdg-open) |
| runnable actions | System Monitor, Dashboard, Workspace Overview, Quick Settings, Screenshot — full/region/output, Screen Recording start/stop — each greyed out with its reason when the tool (`grim`/`slurp`/`wf-recorder`) is missing |

## 5. Theme & wallpaper (PRD §20–21)

- Presets: **Void Wallpaper** (default), Frost, Mint, Solar, Rose,
  Ocean; dark/light; complete parchment light palette.
- **Dynamic wallpaper tone**: chroma-weighted extraction of wallpaper
  pixels (one grab per wallpaper change) → accent family + rotated
  borders/glows; lockable.
- Applying a wallpaper runs `awww img …`; grid scans
  `~/Pictures/wallpapers` (maxdepth 2, common formats).
- Everything persists (`theme.json`, `wallpaper.json`) and survives
  restarts; malformed files fall back to defaults.

## 6. System monitor / task manager (PRD §23)

CPU % + history, memory + history, network up/down + history,
temperature (when `hwmon` exposes it), disk usage, uptime, package
update count (≥60 s cadence), and a **live process table** (3 s
refresh, sortable, per-process kill with confirmation — the only kill
in the shell, gated to this view). Stats poll at 2 s **only while the
drawer/dashboard is visible**.

## 7. Workspace overview (PRD §24) — Shadow Spaces form (Phase B)

A **label-free card strip of real window previews** on a fully
transparent backdrop: one card per eligible workspace (Hyprland's list,
specials excluded by metadata, monitor-scoped per `scope`), identified
by its previews alone — no text labels, no badges, no chips (the two
exceptions are states, not identity: an urgent workspace keeps its
bang glyph, an empty one says *Empty*). Each card lives in a fixed
340 × 176 slot and is painted 328 × 164 when focused (idle cards sit
back at 0.94 scale), framed on one thin, ink-washed panel with the
indicator pills centred under it — the frame is a fixed-size slider
window that scrolls horizontally, see *Neon Purple slider window*
below.

- **Real previews.** Every window is rendered from a Wayland screencopy
  of its toplevel (`ScreencopyView` ← `HyprlandToplevel.wayland`), so
  what a card shows is what that window actually looks like — including
  windows on workspaces that are not visible. No fake tiles, no previews
  written to disk, no polling and no per-frame processes.
- **Honest fallback chain** (per preview): a live stream if it holds one
  of `livePreviewBudget` slots (default **2**) → otherwise the single
  still its capture session took when it was created → otherwise a
  neutral plate with the app icon or its initial. Windows on the
  `sensitiveExclusions` list are **never handed to the capturer**: they
  get a lock plate and the word *Hidden* (and, in the expanded view,
  are labelled by class instead of title).
- **Budgeted capture.** `services/PreviewController.qml` grants live
  slots in priority order (expanded view → focused workspace card → the
  rest) and re-computes grants only when a preview requests or releases
  one; previews are destroyed with the overlay, so a closed overview
  leaves no capture sessions behind.
- **Stacking.** Up to `maxStackedPreviews` (default **3**) windows per
  card, stepped down-right so the ones behind peek out, in the
  compositor's own focus order (`lastwindow` + `focusHistoryID`); the
  rest are reachable through the expanded view, urgency keeps its bang
  glyph, an empty workspace says *Empty*.
- **Interaction.** Click a card → that workspace; click a preview →
  focus **that** window and dismiss; double-click → the **expanded
  view**: every window of the workspace as a large preview with its
  title, in a panel that sizes itself to its content (measured 1000 ×
  336 logical for two windows), and back/close/Escape return to the
  strip first, then the overview closes.
- **Browsing the strip (input).** The whole panel is one scroll
  surface — cards, pills and padding: the wheel takes the dominant
  axis from `pixelDelta` first (Wayland touchpads deliver pixels with
  a zero `angleDelta`, which is what made an angle-only handler dead
  under two fingers) and falls back to `angleDelta` for mouse notches;
  both fold into detents — 120 angle units or half a card (182 px) of
  finger travel is one step — so a trackpad's stream of tiny deltas
  can never blast through the row, and one notch still steps exactly
  one card. Arrow keys (**←/↑** earlier, **→/↓** later) share the
  same path through window-scope `Shortcut`s at application scope (a
  focused preview cannot swallow them; they rest while the expanded
  view covers the strip). When every card fits the frame there is
  nothing to scroll, so every one of these inputs walks focus across
  workspaces instead (`goToRelativeWorkspace`, the dash pill's rule) —
  no input is ever inert; with overflow, steps are consumed silently
  at the clamp ends (no wrap).
- **Fullscreen policy (§3):** under `fullscreenPolicy: "explicit-only"`
  the overlay opens only for a deliberate invocation —
  `PopupManager.openReason` records how it was opened and the overview
  refuses a `reveal` opener while the policy says explicit-only.
- **QA hook:** `VOID_POPUP=overview` opens the strip and
  `VOID_OVERVIEW=expand:<workspace>` opens it on that workspace's
  expanded view (this environment has no pointer or wheel injection
  for clicks/hover/scroll — clicks are driven through the tokens,
  scroll through a synthetic delta in the `scroll` token, and arrow
  keys through Hyprland's `hl.dsp.send_key_state` key injection;
  full token list in testing §tokens).

### Purple Ink concept form (superseded)

> **Superseded by the Neon Purple form below.** The measurements here
> (212 × 176 slots, 200 × 164 cards, badge/chip chrome, the thumbnail
> rail and the `+`) describe the phase it recorded, not the current
> code; its behaviour rows — hit-testing, QA hooks — still stand.

The strip was re-cut to the *Purple Ink* concept
(`~/Downloads/Purple Ink Desktop Concept.png`) without touching any
behaviour above: same real previews, same budget, same label-free
cards, same drag hit-testing, same expanded view, same Escape order
and QA hooks. What changed is the frame around them.

- **One glass panel.** Cards, indicator pills and the rail sit on a
  single rounded translucent panel over the ink art (radius 24, fill
  `rgba(18,14,28,0.62)`, 1 px `borderGlass`), sized from its content
  and centred — measured **564 × 244** logical for two workspaces,
  **1224 × 428** for six. Clicks on the frame itself are swallowed;
  only the backdrop *outside* it dismisses.
- **Focus carousel.** Every card sits in a fixed 212 × 176 slot; the
  painted card is 200 × 164. The focused card is full size with an
  accent bloom (the card's own rounded shape drawn into a layer padded
  by exactly `blurMax: 16` and blurred — one static layer, shown only
  while it has something to render); idle cards sit back at
  `scale 0.82` / `opacity 0.86`. Slots keep the row still when focus
  moves — only the emphasis animates: `durationCard` 200 ms (movement,
  so 0 under `reduced`) for the scale, `durationFade` for the dim.
- **Indicator pills.** One pill per workspace under the card row
  (focused 40 × 8 accent, others 14 × 6 dim, 6 px gaps), centred under
  the widest row. Clicking one runs exactly a card click.
- **Thumbnail rail.** 76 px column right of the cards: one 64 × 40
  thumbnail per workspace showing a **real capture of its front window**
  (`priority: 20` — the rail is the cheapest tier and never takes a
  live slot from a card or the expanded view; `draggable: false` — the
  rail navigates, the cards carry), the workspace number badge, and an
  accent border on the focused one. A rail that outruns the screen
  clips inside the frame instead of growing past it.
- **The `+`.** Under the last thumbnail: jump to the smallest positive
  id no workspace is using. The compositor creates a workspace the
  moment you switch to one (verified on this build:
  `hl.dsp.focus({ workspace = 9 })` created ws9, which was reaped when
  focus left), so this needs no extra dispatcher and invents nothing —
  it is exactly "go to a fresh workspace", closing the overview the way
  a card click does. `VOID_OVERVIEW=create` runs the same path.
- **Drop hit-testing follows the paint.** `cardAt` no longer tests the
  slot rectangle: it maps the card to scene space and intersects the
  *painted* surface (`surfaceItem` at `width × scale`, centred in the
  slot), so a carried preview lands where the pointer sees the card —
  including on a scaled-back idle card.

Measured this session (pixel scans of `grim` captures on eDP-1,
1920 × 1080 @ scale 1.5):

| # | Check | Result |
|---|---|---|
| **R.1** | Frame where the math says it: panel left edge logical x 358 for two cards (predicted 358) and x 28 for six (predicted 28); pills span x 564..623 (predicted 564..624); bloom starts at x 588 (predicted 588) | **PASS** |
| **R.2** | Six workspaces wrap 5 + 1: panel 1224 × 428, exactly six pills (40-wide active + five 14-wide), rail = six thumbnails + `+`, second-row card present | **PASS** — header/pill/rail-border run detection |
| **R.3** | Cards stay label-free with real previews: badge + count chips + captures only, active card ringed by the bloom | **PASS** — full-res crop inspected |
| **R.4** | Rail `+` is real: `VOID_OVERVIEW=create` logged `add path → workspace 3`, workspaces went `[1, 2]` → `[1, 2, 3]` with 3 focused, and ws3 was reaped when focus left; four probe windows from R.2 killed afterwards, session back to `[1, 2]` with the user's windows untouched | **PASS** — first attempt computed `workspace 1` because the model had not synced yet, so the path now waits for the list instead of guessing |
| **R.5** | Drop hit-testing follows the paint: `VOID_OVERVIEW=hit` (pointer motion cannot be injected here, so the probe answers `cardAt` directly) logged `card1(focused) centre=hit painted-edge=hit slot-margin=miss painted=200x164 \| card0(idle) centre=hit painted-edge=hit slot-margin=miss painted=164x134` with focus on workspace 2 — the slot point the old slot-rect test claimed misses on **both** scale states — and screenshots before/after a real focus switch show the emphasis moving with it (full-size + bloom + lit pill + rail border follow the focused workspace) | **PASS** — probe run + captures |

> The Phase B rows below record the original equal-card strip (216 ×
> 176 cards, no panel/pills/rail) and the Purple Ink rows above the
> intermediate chrome (badges, chips, the rail). Their behaviour rows
> still stand; their geometry rows are superseded by the subsection
> below.

### Neon Purple concept form (superseded frame)

> **Frame superseded by the slider window below.** The card form this
> pass cut — wide 2:1 slots, neon ring, thin panel chrome, pills,
> edge-to-edge previews, no rail/badges/chips — is still current; what
> the slider pass re-cut is the frame around it (content-derived
> sizing, dim backdrop, no horizontal scrolling) and the input.

The strip was re-cut a third time to *Neon Purple Anime Workspace
Overview* (`~/Downloads/Neon Purple Anime Workspace Overview.png`).
Behaviour untouched: real previews, capture budget, drag
hit-testing, expanded view, Escape order, QA hooks, all gates. The
reference card is preview only, so the chrome went with the frame:

- **No rail, no `+`, no badges, no chips** (the three decisions for
  this pass). The thumbnail rail and its `+` — the overview's only
  workspace-create affordance — are gone, and `VOID_OVERVIEW=create`
  retired with them; cards carry only their previews (number badge
  and count chip removed; urgency survives as its bang glyph, an
  empty workspace still says *Empty*). Identity is preview +
  indicator pills.
- **Wide 2:1 cards.** Fixed slot **340 × 176**, painted surface
  **328 × 164**, idle cards at `scale 0.94` / `opacity 0.86` — the
  reference's focused card is only ~6 % larger, so the ring carries
  the emphasis instead of the size jump (1.0 / 0.94 replaces the
  carousel's 1.0 / 0.82).
- **Neon ring and halo.** The focused card draws a 3 px
  `accentStrong` ring over the violet halo (the same `blurMax: 16`
  padded layer); idle cards get a hairline `borderGlass`, hover
  `borderAccent`, urgent `danger`, drop-hover keeps its 2 px accent
  outline. The header row (badge, chips, hover expand button) is
  gone — expansion is double-click and the QA token.
- **Thin panel.** Radius 36, fill `rgba(16,12,26,0.42)` — the
  wallpaper reads straight through — a 1.5 px near-white edge
  (`rgba(240,236,255,0.30)`), padding 36, card gap 24. Sized from its
  content as before.
- **Pills.** 26 × 9 lit `accentStrong`, 16 × 9 dim, 8 px gaps,
  centred under the widest row — clicking one is still a card click.
- **Preview to the edges.** The stage (and the empty plate) inset
  12 px on every side instead of sitting under the header.

Measured this session (pixel scans of `grim` captures on eDP-1,
1920 × 1080 @ scale 1.5):

| # | Check | Result |
|---|---|---|
| **N.1** | Frame where the math says it: three workspaces → panel edges logical x 70 / 1209, y 220 / 499 — i.e. **1140 × 280** (predicted 1140 × 280 at x 70); focused-card ring x 476..803, y 264..422 (predicted 476..804 / 264..423); lit pill x 629..651 (predicted 627..653) | **PASS** — border/ring/pill run detection |
| **N.2** | Reference chrome gone: no rail, `+`, badge or count chip anywhere in the capture; exactly one lit + two dim pills; focused card ringed with its halo, idle cards hairline-bordered at 0.94 scale; wallpaper visible through panel and card glass | **PASS** — full-res crops inspected |
| **N.3** | Drop hit-testing follows the paint at the new geometry: `VOID_OVERVIEW=hit` logged `card1(focused) centre=hit painted-edge=hit slot-margin=miss painted=328x164 \| card0(idle) centre=hit painted-edge=hit slot-margin=miss painted=308x154` with focus on workspace 2 — centre and painted edge hit, slot margin misses on **both** scale states | **PASS** — probe run |
| **N.4** | Retired paths stay dead: no `railW` / `plusBtn` / `createWorkspace` / `qaCreate` / `nextFree` left in the module, `check.sh` clean, 0 WARN / 0 ERROR on restart | **PASS** — grep + lint + startup log |

### Neon Purple slider window (current)

> **Current frame.** The Neon Purple card form above is unchanged —
> what this pass re-cut is the frame: the panel became a fixed-size
> slider window that scrolls extra workspaces in sideways, the ink
> wash moved onto the panel itself, the dim backdrop went fully
> transparent, and the wheel/touchpad/arrow input arrived.

- **Fixed slider frame.** The panel never grows with the workspace
  count: the viewport holds one slot-row's worth of slots for this
  output — `viewportCap = floor((win.w − 32 − 2 × 36 + 24) / 364)`,
  which on eDP-1 (1920 × 1080 @ 1.5 → 1280 × 720 logical) is **3
  slots / 1068 px** — and cards beyond it scroll in sideways (never
  wrapping, never reflowing the frame). `scrollX` clamps to
  `[viewportW − cardsW, 0]`, always an exact multiple of the 364 px
  card pitch, and every navigation animates one `durationCard` step.
- **Ink-wash panel, transparent backdrop.** The panel keeps the
  Neon Purple chrome (radius 36, `rgba(16,12,26,0.42)` base, 1.5 px
  `rgba(240,236,255,0.30)` edge, padding 36) with an `InkTexture`
  (`InkArt.sourceFor("overview")`) laid over the base; everything
  outside the panel is fully transparent — the desktop behind is not
  dimmed at all.
- **Input** (§7 *Browsing the strip*): `pixelDelta`-first dominant
  axis with detent accumulation for wheel and touchpad, window-scope
  arrow `Shortcut`s at application scope, focus-walk fallback while
  every card fits, silent consumption at the clamp ends.
- **Pills** re-centre under the fixed viewport — they mark the
  workspaces, not the scroll position.
- **QA:** `VOID_OVERVIEW=scroll` feeds one synthetic half-card pixel
  delta through the real `wheelStep` (it must fold to exactly one
  detent), then parks the strip at its clamp end and logs the
  geometry.

Measured this session (eDP-1, 1920 × 1080 @ scale 1.5, five
workspaces):

| # | Check | Result |
|---|---|---|
| **S.1** | Fixed frame: with **5** workspaces the probe logs `cards=5 viewport=1068 content=1796 range=[-728,0] x=-728` — the panel stays 1140 × 280 logical (the same it measured with three); ink strip over the panel reads mean RGB (31, 25, 47) where the closed baseline shows desktop (109, 113, 100) | **PASS** — QA log + ffmpeg pixel means |
| **S.2** | Transparent backdrop: the strip left of the panel reads (37, 40, 42) closed and (37, 40, 42) open — zero dimming outside the panel | **PASS** — ffmpeg pixel means |
| **S.3** | Touchpad path, function level: one synthetic 182 px pixel delta through `wheelStep` logs `wheel pixels=182 steps=1 acc=0` — exactly one detent, accumulator drained (the old angle-only handler saw `angleDelta = 0` for this stream, which is why two-finger scroll was dead) | **PASS** — `VOID_OVERVIEW=scroll` run |
| **S.4** | Arrow keys under real key injection (`hl.dsp.send_key_state`): **Left** moved the card row by exactly one card pitch (row profile best-alignment −55 bins ≈ −546 physical px = 364 × 1.5, mean ‖Δ‖ 58.39), **Right** returned **byte-identical** to the start (same md5, profile Δ 0.00), active workspace stayed `2` throughout (no key leakage) | **PASS** — injection run + ffmpeg forensics |
| **S.5** | Hygiene: `check.sh` CHECK-PASS; clean restart = 1 instance, overview closed, 0 WARN / 0 ERROR | **PASS** — lint + startup log |

### Phase B — acceptance results

| # | Gate | Result |
|---|---|---|
| **B.1** | Real previews: cards render actual window captures, checked against `hyprctl clients` state at capture time (kitty / Brave / VSCode windows all recognizable in the capture) | **PASS** — screenshots at 12:21, 12:28, 12:54, 13:01 |
| **B.2** | Fallback chain + sensitive exclusion: non-live previews keep their still, no-frame windows fall back to the icon/initial plate; `isSensitiveWindow` gates `captureSource` to null before any capture can start | **PASS** (code path + neutral plate rendered); *no sensitive window existed to capture — that branch is implemented-untested at runtime* |
| **B.3** | Budget: at most `livePreviewBudget` (2) previews stream; grants recomputed only on request/release; no timers, no spawned processes | **PASS** (single source in `PreviewController`) |
| **B.4** | Stacking: workspace 3 held two windows during the probe → count chip read **2**, two previews instantiated with the back one peeking (green scrollbar edge visible) | **PASS** — compositor reported `ws3 windows=2` at capture; probe screenshot 13:01 |
| **B.5** | Counts/state match the compositor: chip values equal `hyprctl workspaces` windows counts; active card follows real focus (never reorders the list) | **PASS** — probe run: compositor 1/1/2 ↔ chips 1/1/2 |
| **B.6** | Label-free cards: number badge + count/urgency glyphs only, no per-card text | **PASS** (measured card box 216 × 176 logical) |
| **B.7** | Expanded view: real previews + titles for every window of the workspace; panel auto-height | **PASS** — measured content bbox logical x141..1139 (≈1000 wide), y192..528 (≈336 tall), backdrop level 10.7 (0.94 overlay) vs 35.1 for the card strip |
| **B.8** | Overlay lifecycle: previews exist only while the overview is open (`Loader` bound to visibility), `PreviewController.clear()` on close; fullscreen gate reads `fullscreenPolicy` | **PASS** (no overview layer survives close — `hyprctl layers` empty afterwards) |
| **B.9** | Clean gates: `scripts/check.sh` → `CHECK-PASS`, `scripts/smoke-test.sh` → `SMOKE-PASS`, every overview open/close probe logged **0** QML WARN/ERROR (only the expected duplicate-instance notification-server notice); strip centred at logical 300..980 for three cards | **PASS** |

**Not exercised live:** hover, single/double click and the preview →
focus click (no pointer injection in this environment: no `wtype`,
`ydotool`, or writable `/dev/input`). The focus dispatch those clicks
call (`hl.dsp.focus({ window = "address:0x…" })`) **was** exercised
through `hyprctl` during the probes and focused the intended window.

## 8. Notifications (PRD §15)

Void Shell is the `org.freedesktop.Notifications` server: ingestion
from any app, toast popup (bottom-right, auto-dismiss, doesn’t move
the bar), history store, per-app grouping, unread badge, DND toggle
(toasts suppressed while DND, history still collects).

## 9. Media & audio (PRD §16–17)

- MPRIS via `playerctl`/Qt interface: state, artwork, position,
  controls; bar media pill when playing.
- Volume/mute/mic/brightness: pipewire + `brightnessctl`, live bind
  reaction (F1–F4, F11/F12), graceful “unavailable” when the device
  doesn’t exist (no laptop backlight → slider says so).

## 10. Screenshot & recording (PRD §18)

- Screenshot: full / region / output via `grim`(+`slurp`), saved to
  `~/Pictures/Screenshots`, copied to clipboard (cliphist-compatible),
  success/failure toast.
- Recording: `wf-recorder` start/stop with state machine (starting →
  recording → stopping), bar indicator + elapsed, single source of
  truth so indicator and recorder can’t desync.
- *Environment note:* `wf-recorder` is not installed on this machine —
  the action shows its unavailable reason until it is.

## 11. Wallpaper overlay (PRD §29–30) — **off by default**

Four modes (persisted as `overlay` in `wallpaper.json`, chosen in the
`@wp` popup’s Overlay row):

| Mode | Shows |
|---|---|
| `off` (default) | nothing — the finalized design |
| `visualizer` | 24-bar waveform (real FFT of the sink monitor) + synced lyrics |
| `clock` | big central clock + date |
| `clock+lyrics` | clock + waveform + lyrics |

- Window sits on the **Bottom** layer with an empty input mask and
  `keyboardFocus: None`: behind windows and shell, fully click-through.
- Visualizer: `ffmpeg` monitor capture → base64 line frames → 512-pt
  radix-2 FFT → 24 log bands (40 Hz–8 kHz, −52 dB floor,
  fast-attack/slow-decay). Runs **only while audio is active**; stops
  after 4.2 s of silence; wakes on real audio (pipewire peak tap —
  disabled while the sink is muted, where it could never fire — or
  MPRIS play). No network, no simulated data.
- Lyrics: **local `.lrc` only** (lazy index over
  `~/.local/share/voidshell/lyrics` + `~/Music`), matched to the MPRIS
  track, position extrapolated from the player’s reports; with no
  player it shows its minimal unavailable state.

## 12. Lock screen (PRD §25)

Themed Void Shell surface (clock, date, user, hostname) with hyprlock
behind it doing PAM authentication; the surface disappears only when
hyprlock exits successfully. While locked, `PopupManager` refuses every
other popup and IPC lock-toggle cannot dismiss it.

## 13. Tasks & focus (PRD §26–27)

Task list (create/complete/delete/reorder) persisted to `tasks.json`;
focus timer (focus/break cycles) as a shell singleton so a countdown
survives popup close; completion publishes a toast.

## 14. Keybinds (all defined in `~/.config/hypr/hyprland.lua`)

| Bind | Action |
|---|---|
| `Super + Space` | launcher toggle |
| `Super + O` | quick settings toggle |
| `Super + D` | notifications toggle |
| `Super + Shift + A` | media popup toggle |
| `Super + Shift + D` | dashboard |
| `Super + Shift + M` | system monitor / task manager |
| `Super + W` | workspace overview |
| `Super + Shift + W` | Stage shelf reveal / hide (§18) |
| `Super + I` | Living State Island — activity stack (§23) |
| `F7 / F8 / F9` | prev / play-pause / next (locked sessions too) |
| `F1` `F2` `F3` | sink mute, volume −/+ |
| `F4` | mic mute |
| `F11` `F12` | backlight −/+ |

Every popup is also reachable from the launcher’s action list and from
scripts:

```sh
qs -c voidshell ipc call <launcher|calendar|media|quickSettings|notifications|power|dashboard|taskManager|overview|lock> toggle
qs -c voidshell ipc call island <toggle|stack|section|context|close|diagnostics>   # Living State Island (§23)
```

> **Keybind note (resolved):** `Super + M` used to be bound twice in
> `hyprland.lua` — this config’s older exit binding (`hyprshutdown`/
> exit, line 257) *and* the media popup. Void Shell now uses
> **`Super + Shift + A`** for media and leaves the pre-existing exit
> binding untouched, so each key has exactly one meaning. Verified with
> `hyprctl binds`: exactly one `Super + M` (exit) and one
> `Super + Shift + A` (media), `hyprctl configerrors` empty.

## 15. Multi-monitor (PRD §11, §31)

Popups open on the monitor of their source segment and fall back to
the primary screen; workspace/app state is per-Hyprland (global);
overlay and lock render on the focused output; the bar’s segments are
per-output layer surfaces (single-output setups run the default
layout).

## 16. Graceful degradation (PRD §37, §40)

Every capability has a probe and a reason string: missing `grim`/
`slurp`, missing `wf-recorder`, no Docker, no MPRIS player, no
backlight, no temperature sensor, no battery, no Bluetooth adapter,
empty lyrics library, offline weather. UI shows a disabled control with
that reason or an EmptyState card — it never invents values, and
unavailable state is tested explicitly (§43).

## 17. Shadow Spaces — workspace dash (Phase A)

The desktop-manager surface, **on by default** (`managerEnabled` in
`~/.local/share/voidshell/desktop-manager.json`; malformed/missing file
falls back to the documented defaults). Shortcuts stay where every other
binding lives — `~/.config/hypr/hyprland.lua` — so `Super + W` (§14) is
untouched.

**Dash strip** (`modules/Bar/WorkspacesPill.qml` + `WorkspaceButton`):

- Five fixed 30 px slots inside the **same 218 × 46 pill footprint** the
  numbered strip occupied — the bar does not reflow, and the invariant
  is runtime-enforced: `checkFootprint()` emits
  `workspaces pill footprint changed` when the width drifts, and the QA
  gates grep for `WARN`.
- Each slot shows a glass **count chip** — the real window count of that
  workspace (`HyprlandService.windowCountOf`) — plus the workspace's real
  urgent state; the focused slot carries a **28 × 4 underline that slides**
  between slots instead of jumping.
- The visible window of the strip is **bounded**: it never wraps and
  never reorders — `slotOffset ∈ [0, workspaces − 5]`, re-clamped on every
  Hyprland event, so adding/removing workspaces slides the strip rather
  than pushing the focus mark off the pill. Focus changes never reorder
  the workspace list.
- Only **eligible** workspaces are listed: specials are filtered from
  Hyprland's metadata (never by a negative-id sign test), and every
  count comes from the event-driven `HyprlandService` — no polling, no
  per-frame processes.
- **Interactions:** click a slot → that workspace (bounded dispatch,
  silent when nothing is wrong); wheel over the pill → relative
  workspace move (unchanged from the numbered strip); right-click
  (two-finger tap) → toggles the overview.
- **Legacy fallback:** `managerEnabled: false` restores the previous
  numbered 1–5 strip — same box, same neighbours, only the pill's
  contents change.
- Commit `f5db16a` contains exactly the five Phase A files
  (`WorkspacesPill.qml`, `WorkspaceButton.qml`, `HyprlandService.qml`,
  `ManagerSettings.qml`, `services/qmldir`); the three baseline WIP files
  (`common/Colors.qml`, `modules/Launcher/AppDelegate.qml`,
  `modules/Launcher/Launcher.qml`) stay untouched and uncommitted on top
  of `46933d6`.

### Phase A — acceptance results

| # | Gate | Result |
|---|---|---|
| **A.1** | Pill footprint unchanged: nominal 218 × 46; screenshot probe measures painted width **214** (±6 tolerance for rounded corners + glow), slot pitch **32**, content inset **29–30**, underline **27–28** | **PASS** — `PROBE-STRUCT-PASS`, QML-measured `width=218 height=46 mode=dash` |
| **A.2** | No bar reflow: dash vs legacy screenshots show a pixel-identical pill box and pixel-identical neighbour edges | **PASS** (A/B capture, earlier session) |
| **A.3** | Real data: count chips match Hyprland's workspace/window state (3 chips for the 3 live workspaces) | **PASS** — probe found 3 chips, `hyprctl` 3 workspaces |
| **A.4** | Bounded scroll with more workspaces than slots: 7-workspace run slides the strip to ws3…ws7 with the underline parked on the last slot, no wrap, no reorder | **PASS** (earlier session capture); *wheel-input path itself implemented-untested — no pointer/keyboard injection in this environment* |
| **A.5** | Legacy restore: `managerEnabled:false` renders the numbered 1–5 strip with the focus fill | **PASS** — screenshot verified, 0 warn/error in the restart log |
| **A.6** | Clean runtime: restart log has **0 WARN / 0 ERROR**; `scripts/check.sh` → `CHECK-PASS`; `scripts/smoke-test.sh` → `SMOKE-PASS`; overview popup opens via `VOID_POPUP=overview` with no binding loops (the only warnings are quickshell's notification-server re-registration notices, expected when a second instance runs beside the live one) | **PASS** |
| **A.7** | Baseline preserved: `46933d6` history plus the three WIP files remain uncommitted and byte-identical | **PASS** — `git status` shows only the three WIP files |

**Not exercised in this session** (environment limits, stated rather
than implied): pointer-only paths (right-click → overview, wheel scroll)
were read and code-reviewed but never clicked live — no input injection
tooling exists here; they inherit the same dispatch helpers the
keyboard-driven paths use. Phases B–G (real window previews, exact
focus, drag-to-move, the Stage shelf, popup coordination, motion
hardening) are not part of this section.

## 18. Stage shelf — Shadow Spaces (Phase E)

An **opt-in** side column of the same workspace groups, real window
previews and activation actions the overview uses
(`modules/StageShelf/StageShelf.qml`), default **left** (`shelfSide:
"right"` flips it without touching data or behaviour), **off** by
default (`shelfEnabled`).

- **Scope.** One small overlapping stack per *other* occupied workspace
  on the monitor `scope` selects, in the model's own id order — never
  focus order, never a second workspace system, and the workspace you
  are on is your main working area so it is not listed. Clamped to six
  stacks so the column always fits the screen. No permanent labels:
  the number and count chips appear on hover only, urgency is a glyph.
- **Reveal.** `Super + Shift + W` → `qs -c voidshell ipc call shelf
  toggle` (the one binding this phase adds, §14). The optional edge
  reveal (`edgeReveal`, **off by default**) needs a deliberate 550 ms
  dwell and is refused outright while the focused workspace holds a
  fullscreen window.
- **Interaction.** Hovering a group fans its stack wider without
  activating anything; a background click activates that workspace, a
  preview click focuses exactly that window — both then hide the shelf.
  Both dispatches are the same validated helpers the pill and the
  overview cards use.
- **Hide.** The pointer dwelling 1.2 s away from the shelf auto-hides
  it (a shelf pinned by the shortcut stays until toggled again), any
  popup/overview/dashboard opening hides it and clears the pin, and
  while hidden there is **no surface at all**: no invisible
  input-blocking strip, no reserved screen area (`exclusiveZone: -1`
  reserves nothing and the bar keeps its exact geometry), no fullscreen
  scrim, and no keyboard focus grab — the shelf can never swallow a key.
  The one narrow input zone that ever exists is the 4 px dwell strip
  that `edgeReveal` opts into.
- **Captures** follow §7's budget and fallback chain unchanged: the
  preview items are instantiated only while the shelf is revealed, so
  hiding it destroys every `ScreencopyView` and releases its live slot
  and its still. Nothing is written to disk, nothing polls.
- **QA hook:** `VOID_SHELF=1 qs -c voidshell` reveals the shelf at
  startup once `shelfEnabled` is true (this environment has no pointer
  or key injection), and it waits for the settings store instead of
  reading a default — `StorageService` creates the state directory with
  a process, so the first read always lands on the defaults.

### Phase E — acceptance results

| # | Gate | Result |
|---|---|---|
| **E.1** | Stage shelf uses the same groups and hides without leaving input blockers: with `shelfEnabled: true` the shortcut payload (`qs -c voidshell ipc call shelf toggle`) produced exactly one `voidshell-shelf` layer at `xywh 10 251 136 218` (centred, 136 × 218 logical, two stacks for the two other occupied workspaces), the same payload hid it — surface gone, not made transparent — opening the overview suppressed it and cleared the pin, and with `desktop-manager.json` removed the identical payload produced no surface at all | **PASS** — probe `scripts/shelf-check.sh`, 15/15 assertions, screenshot saved by the probe as `/tmp/voidshelf-check/pe_on.ppm` (two real previews, Brave ws2 / Brave ws3, at the left edge) |
| **E.2** | Bind registered, no config damage: `hyprctl reload` → `hyprctl configerrors` empty; `hyprctl binds` lists exactly one `key: W` with `modmask: 65` (Super + Shift + W) next to the untouched `modmask: 64` (Super + W) | **PASS** |
| **E.3** | Suppression + bar untouched: the shelf layer is absent whenever `PopupManager.activePopup != "none"`, and the three bar layers keep their exact geometry (`18 10 529 56`, `555 10 170 56`, `733 10 529 56`) before, during and after every reveal | **PASS** |
| **E.4** | Opt-in default + clean runtime: settings file absent ⇒ `shelfEnabled` false ⇒ reveal is inert; start/restore logs carry **0** WARN/0 ERROR beyond quickshell's expected duplicate-instance notification notices; `scripts/check.sh` → CHECK-PASS; `scripts/smoke-test.sh` → SMOKE-PASS; exactly one live `qs` instance left running | **PASS** |
| **E.5** | Session integrity: workspaces, window-to-workspace mapping and the focused workspace are byte-identical before and after the probe (kitty ws1, Brave ws2/ws3, active ws1) | **PASS** |

**Not exercised live** (no pointer/keyboard injection in this
environment): the hover fan and hover-only chips, click → switch, click
→ focus, the 1.2 s auto-hide dwell, the 550 ms edge dwell and the
keypress itself. The IPC payload behind `Super + Shift + W` was run
verbatim, and the dispatch helpers those clicks call
(`goToWorkspace`, `activateWindow`) were exercised through `hyprctl`
during the Phase C/D probes. When only the current workspace is
occupied the shelf shows nothing (there is nothing to switch to) — by
design, and it leaves no surface behind.

## 19. Coordination (Shadow Spaces — Phase F)

One visibility coordinator: `PopupManager` decides which surface owns
the screen, every primary surface binds to it, and the Stage shelf is
*suppressed* by that decision instead of competing with it.

- **One primary popup.** `dashboard`, `overview`, `launcher`, `media`,
  `taskManager`, `notifications`, `quickSettings`, `power` are all
  entries of `PopupManager.popups`, so opening one closes the previous
  one by construction. Runtime proof: `scripts/coord-check.sh` drives
  dashboard → overview → task manager → launcher → media → launcher in
  sequence and asserts exactly one manager surface exists after every
  step, and zero once everything is closed.
- **The shelf is never a popup.** It hides and drops its pin the moment
  `activePopup` leaves `"none"` (§18), and `coord-check.sh` counts it
  in the same "at most one" total so a shelf can never coexist with a
  popup.
- **No duplicate providers.** Services are singletons instantiated once
  in `shell.qml`: a single-instance start and the whole probe sequence
  log **0** WARN/0 ERROR and exactly one `qs` process. The
  "could not register notification server" notice appears only when a
  second QA instance runs beside the live one (which is why
  `popup-check.sh` / `tab-check.sh` are run with the daemon stopped).
- **Island hook + renderer.** `HyprlandService.announcement` +
  `announcementSerial` publish a workspace switch, but only when
  `islandAnnouncements` is on (**default on** — flipped with the Living
  State Island) and only on a real focused-workspace change —
  event-driven, never a timer.
  `modules/Bar/ClockPill.qml` is the renderer: while an announcement
  is fresh the clock column fades out and the island shows the
  announced workspace in accent over the word *workspace*; a one-shot
  dwell timer (2.4 s — it only ends the display, it polls nothing and
  drives no data) fades the time back. Both columns share the island's
  two-line shape, so nothing jumps, and the island's geometry
  (`555 10 170 56`, centre position) never changes. With the setting
  off nothing renders: forcing `{"islandAnnouncements": false}` and
  restarting logged **0** announcement lines across two real switches
  (the off path is now forced, not shipped). Verified from `grim`
  captures (see *Island renderer* below).
- **Live timer countdown.** While a countdown (`timers`) or a focus
  session (`timer`) is running, the pill leaves the clock and shows the
  exact remaining time — `TimerStore.fmt`-padded `mm:ss` (`h:mm:ss`
  past an hour) in accent over the timer's name — recomputed every
  second from that timer's own `endsAt`, i.e. the same value the shelf,
  dashboard and activity stack read, never a second counter of its own.
  It outranks the ambient line (it is the only state that repaints
  every second) and is outranked by every announcement: a workspace or
  event dwell takes the pill and the countdown returns when the dwell
  ends; at zero the completion announcement takes over and the pill
  falls back to the clock. Paused timers are not real-time and stay on
  the ambient line. Verified live from the store's own persistence: a
  seeded 120 s countdown read `01:45` and exactly `01:38` seven seconds
  later, then completed on its own (`running:false completed:1
  announced:true`) with the pill back on the clock, 0 WARN/0 ERROR.
- **Clock untouched.** The three bar islands keep their exact geometry
  (`18 10 529 56` left, `555 10 170 56` clock, `733 10 529 56` right)
  through every popup/overview/shelf transition, and the workspaces pill
  never logs `workspaces pill footprint changed`.

### Phase F — acceptance results

| # | Gate | Result |
|---|---|---|
| **F.1** | Opening Dashboard (or any manager overlay) closes the others and every Dashboard tab still works: `coord-check.sh` shows a single manager surface after each of dashboard → overview → task manager → launcher → media → launcher and 0 at rest; `popup-check.sh` → POPUP-CHECK-PASS (10/10), `tab-check.sh` → TAB-CHECK-PASS (5/5) with the daemon stopped as documented | **PASS** |
| **F.2** | Bar and clock preserved: bar layer geometry byte-identical before/during/after the whole sequence, no `workspaces pill footprint changed` in the log | **PASS** |
| **F.3** | No duplicate providers: one `qs` instance before and after, one notification server, 0 WARN/0 ERROR in the restart + sequence log | **PASS** |
| **F.4** | Island hook publishes only when asked: with `islandAnnouncements: true` the switch to workspace *n* logged `island hook: workspace announcement n`; workspace and focus were restored to their pre-probe values afterwards; the settings file is removed at the end of the probe, so the hook returns to the shipped default (on) | **PASS** — Phase F shipped the hook only (its UI was honestly reported as remaining scope); **the renderer landed in the follow-up below** and is verified there |

### Island renderer (design follow-up)

The announcement now draws inside the clock island — same window,
same geometry, nothing else moved. Probe recipe: write
`{"islandAnnouncements": true}` to
`~/.local/share/voidshell/desktop-manager.json`, restart, switch
workspace, capture within the dwell; delete the file and restart to
return to shipped defaults.

| # | Check | Result |
|---|---|---|
| **I.1** | With the setting on, a real switch to workspace 3 logged `island hook: workspace announcement 3` and the island captured as accent **`3`** over the muted **`workspace`** label, inside the unchanged slanted pill | **PASS** — `grim` crop inspected |
| **I.2** | 3.5 s later the same island showed `20:34` / `Mon Oct 5` again; the two frames differ in **7.1%** of the island's pixels while the left and right islands were **bit-identical (0.0%)** — so the change is the island's own content, not the wallpaper behind it | **PASS** — per-pixel diff of two captures |
| **I.3** | Off path — **re-earned after the default flipped to on**: with `{"islandAnnouncements": false}` written and the shell restarted, two real workspace switches logged **0** announcement lines, one clean instance, 0 WARN/0 ERROR; deleting the file and restarting logged the announcement again (1 hook line) | **PASS** — the off path is now forced, the on path is shipped |
| **I.4** | Bar geometry unchanged throughout — `18 10 529 56` / `555 10 170 56` / `733 10 529 56` still asserted by `coord-check.sh` and `hardening-check.sh` in the same gate sweep | **PASS** |

**Not exercised live:** the pointer/keyboard paths listed in §7/§18.

## 20. Exact focus and exact switch (Phase C)

A click on a preview must focus *that* window; a click on a card must
open *that* workspace — never "the workspace of" a window, never a
reorder by focus (plan §6, commit `32e6942`).

- **One path per action.** `WorkspaceCard` no longer switches on its
  own: it emits `switchRequested` and `WorkspaceOverview` runs
  `switchToWorkspace()` → `HyprlandService.goToWorkspace()` +
  `PopupManager.closeAll()`. The preview click runs `focusWindow()` →
  `HyprlandService.activateWindow(address)` + `closeAll()`. Both are
  the same bounded, validated helpers the dash pill uses — the QA hook
  and the click path are one function, so a probe cannot pass while the
  click is broken.
- **Existence is re-checked** before focusing, so a stale preview can
  never retarget focus at a dead address; the workspace is resolved by
  name through `HyprlandService` (specials excluded by metadata, never
  by a sign test), and focus never reorders any list.
- **QA hook:** `VOID_OVERVIEW=expand:<ws>`, `switch:<ws>`,
  `focus:<address>` (comma-separated, one-shot, re-checked only on
  `HyprlandService.eventSerial` — no timers), because this environment
  has no pointer/keyboard injection.

### Phase C — acceptance results

| # | Gate | Result |
|---|---|---|
| **C.1** | Card-click path: `VOID_OVERVIEW=switch:2` opened the overview and switched the compositor to workspace 2 — logged `overview QA: card-click path → workspace 2`, `hyprctl activeworkspace` reported `2` | **PASS** — probe 2026-10-05, `/tmp/opencode/cd-probe/c-switch.log` |
| **C.2** | Preview-click path: `VOID_OVERVIEW=focus:<address>` focused *that exact window* — the active window was `(voidprobe, 0x56077845a680, workspace 2)`, address and class asserted against `hyprctl clients`, logged `overview QA: preview-click path → window …` | **PASS** — probe 2026-10-05, `/tmp/opencode/cd-probe/c-focus.log` |
| **C.3** | Clean gates + session: `check.sh` → CHECK-PASS, `smoke-test.sh` → SMOKE-PASS; after the probe the window-to-workspace mapping and focus were byte-identical to the pre-probe state and exactly one `qs` instance was left | **PASS** |

**Not exercised live:** the physical clicks (no input injection in
this environment). The functions those clicks call were run end to end
by the hook, and their dispatch helpers are shared with the pill's
keyboard/click path.

## 21. Drag a preview between cards (Phase D)

A preview carried off its card and released over another card moves
that one window to that one workspace — silently, with the overview
staying open so several windows can be moved in a row (plan §8, commit
`de203a7`).

- **Manual hit-testing, not QML DnD.** The drop target is resolved
  from live scene coordinates (`cardAt` / `trackDrop` / `dropPreview`
  on the strip) instead of the DropArea protocol, whose z-order and
  ancestry resolution would hand the drag back to the source card.
- **`carrier` carries the picture.** In `WindowPreview` a `carrier`
  Item is the MouseArea's `drag.target`, so the dragged image follows
  the pointer while the card keeps its slot position; the carrier
  resets to (0,0) on release/cancel. `wasDragged` is set on drag start
  and only cleared on the *next* press — a drag can never be read as a
  focus click, and a drop onto nothing simply snaps back.
- **Silent move.** `moveWindowTo(address, ws)` calls the existing
  `HyprlandService.moveWindow(…, false)` (`follow:false`): neither the
  current workspace nor the focused window changes as a side effect of
  relocating a window, and the workspace list is never reordered by
  focus. **QA token:** `VOID_OVERVIEW=move:<address>:<ws>` runs exactly
  this function.

### Phase D — acceptance results

| # | Gate | Result |
|---|---|---|
| **D.1** | Silent move — current workspace: with the session on workspace 1, `VOID_OVERVIEW=move:<addr>:2` moved the window and `hyprctl activeworkspace` still reported `1` | **PASS** — probe 2026-10-05 |
| **D.2** | Silent move — focus: the focused window was still the main kitty `(0x5607784cb0a0, ws1)` after the move | **PASS** — probe 2026-10-05 |
| **D.3** | The moved window's workspace changed in `hyprctl clients` (`ws3 → ws2`) and no other client's workspace changed; logged `overview QA: drop path → move … to workspace 2` | **PASS** — probe 2026-10-05, `/tmp/opencode/cd-probe/d-move.log` |
| **D.4** | Session integrity: after the probe windows were removed, `hyprctl clients` was byte-identical to the pre-probe mapping, workspaces were `[1]`, focus was back on the main kitty and exactly one `qs` instance remained | **PASS** — probe 2026-10-05 |

The commit-time probe additionally asserted `ASSERT-MOVE`, `WS-STABLE`
and `FOCUS-STABLE` with **0** QML warnings.

**Not exercised live:** the pointer drag itself (no input injection
here). The drop path it ends in — hit-test → `moveWindowTo` → silent
dispatch — was run end to end by the QA token.

## 22. Motion and hardening (Phase G)

One motion model, one disable switch, and the lock/reload edges
(plan §12, §16, §18).

- **One source for durations.** `ManagerSettings` owns every value and
  logs the resolved configuration on each (re)load:
  `[voidshell] motion: mode=… pill=… hover=… shelf=… card=… fade=… overview=…`,
  so a silently "off" mode is visible in the log and the gate greps it
  instead of guessing.
  - `full` — pill 190, hover 140, shelf 210, card 200, fade 160,
    overview 220 ms.
  - `reduced` — **fades only**: movement (pill underline slide, shelf
    fan, hover lift, shelf slide, the overview's active-card scale) is
    **0**, so nothing travels across the screen; the colour fade
    (160 → 120), shelf chip fades (→ 120) and the overview's
    backdrop/body fade (220 → 120) stay.
  - `off` — every duration 0; nothing animates.
  `durationSettle` was removed as dead code — no component referenced
  it.
- **`managerEnabled:false`** reverts the pill to the numbered strip
  *and* gates the Stage shelf off (the shelf is part of the manager).
  The **overview stays available**: it is the PRD §24 surface behind
  `Super + W`, and the legacy fallback must not kill that binding —
  documented deliberately rather than silently.
- **Lock releases every capture.** `PreviewController` now clears on
  `PopupManager.lockedChanged` and logs
  `preview: released N capture request(s)` — no still survives a lock
  (acceptance G.3). Closing the overview still clears it as before.
- **Gate:** `scripts/hardening-check.sh` (M/N/P/O below) in one
  invocation, with a settings backup and an `EXIT` trap.

### Phase G — acceptance results

| # | Gate | Result |
|---|---|---|
| **G.1** | Motion modes: three restarts (`animation: full`, `reduced`, `off`) each logged exactly the expected motion line (`mode=full pill=190 hover=140 shelf=210 card=200 fade=160 overview=220` / `mode=reduced pill=0 hover=0 shelf=0 card=0 fade=120 overview=120` / `mode=off pill=0 hover=0 shelf=0 card=0 fade=0 overview=0`), the overview opened and closed and the shelf revealed and hid **in every mode**, and every log was clean | **PASS** — `hardening-check.sh` M (21 assertions) |
| **G.2** | Reduced motion is *fades only*: the movement durations read 0 while `fade`/`overview` keep 120 ms, and `off` zeroes them too — asserted from the resolved values the surfaces actually bind (`durationPill`, `durationHover`, `durationShelf`, `durationCard`, `durationFade`, `durationOverview`) | **PASS** — code + G.1 log lines |
| **G.3** | Lock drops the overview and releases captures: an isolated instance with the overview open answered `qs -c voidshell ipc call lock toggle` (only it was running) — the overview layer disappeared, exactly one `voidshell-lock` layer appeared, and the log recorded `preview: released 3 capture request(s)`; the log stayed clean | **PASS** — `hardening-check.sh` N (6 assertions) |
| **G.4** | Disable switch: with `managerEnabled:false` the pill painted differently from dash mode (mean RGB distance **9.63** over the pill island vs **0.00** over the rest of the bar), the three bar layers kept byte-identical geometry, the overview and the dashboard both still opened, the shelf stayed inert although `shelfEnabled:true`, and no `workspaces pill footprint changed` appeared | **PASS** — `hardening-check.sh` P (11 assertions) |
| **G.5** | Reload hygiene: exactly one `qs` instance, exactly 3 bar layers matching the pre-probe geometry, 0 WARN/0 ERROR in the restart log, overview opens once and closes clean, and `hyprctl binds` lists exactly one `key: W` with `modmask: 64` and one with `modmask: 65` | **PASS** — `hardening-check.sh` O (7 assertions) |
| **G.6** | Session integrity: active workspace and the window-to-workspace mapping byte-identical before/after the whole probe, settings file restored to its pre-probe state, one live instance left | **PASS** — `hardening-check.sh` finish (5 assertions) |

Full run: **PHASE-G-PROBE-PASS** (50/50), alongside `CHECK-PASS`,
`SMOKE-PASS`, `POPUP-CHECK-PASS` (10/10), `TAB-CHECK-PASS` (5/5),
`PHASE-E-PROBE-PASS` (15/15) and `PHASE-F-PROBE-PASS` (21/21) re-run
against this commit.

**Not exercised live:** moving the animation setting through the UI
(no pointer injection) — the modes were written to
`desktop-manager.json` and read back through the shell's own settings
store; the reduced/off surfaces were verified for *function* (they
still open/close) and for *values*, not for frame timing.

## 23. Living State Island (MASTER PROMPT §4–§7, §14, §17, §21)

The centre clock pill is still a clock first: **170 × 46 px at
`555 10 170 56`**, the same slanted pill, the same neighbours, the same
bar geometry — asserted byte-for-byte by `coord-check.sh` and
`island-check.sh` (I1). Nothing ever pushes a neighbour or grows the
reserved area. Everything that needs more room opens on a **separate
anchored surface directly below the clock** (`namespace
voidshell-island`, `WlrLayer.Overlay`, `exclusiveZone: -1`, centred —
so it aligns under the pill without a hard-coded x).

### Presentation states

| State | Where it draws | Trigger |
|---|---|---|
| **A** Idle | clock face inside the pill | no announcement, no ambient item |
| **B** Ambient | second line: pinned activity > any activity > DND > warning | persistent condition (never a transient event) |
| **C** Temporary event | crossfade **inside the pill** (announcement title/subtitle + duration bar) | `AnnouncementEngine` presents an event |
| **D** Contextual card | island surface, one activity + its registered actions | `island context <key>` / row click |
| **E** Activity stack | island surface, segmented body (Activities / Controls / Timers / Presets / Clipboard) | `Super + I`, clock right-click, `island stack` |
| **F** Dashboard open | existing Dashboard (5 tabs, unchanged) | `Super + Shift + D`, clock left-click, routed actions |
| **G** Locked | island surface dropped, announcement paused | `PopupManager.locked` |

- **Presentation order & dwell** — control 1.2 s, track/device 3 s,
  notification/job/timer 4 s, workspace 0.8 s (`island.json`
  `duration*` keys). Queue limit 20 with coalescing by key; a newer
  event for the same key replaces the queued one. P0–P4 priorities:
  P0 also raises a *persistent* warning (survives the dwell),
  P4 never interrupts an interaction.
- **Protection** — `IslandController.interacting` freezes announcements
  and the stack order while a pointer button is down or the surface has
  focus; DND suppresses non-P0 categories (`dndSuppress`), a fullscreen
  window keeps only P0/P1 (`fullscreenPolicy: "quiet"`); hover preview
  is opt-in (`hoverPreview: false` by default) and never takes keyboard
  focus.
- **Reduced motion** — the Island binds `IslandSettings.durationCrossfade`
  / `durationRow` / `durationSurface`, which collapse to 0 in
  `animation: "off"` and to fades-only in `"reduced"` (Phase G §22).

### Clock clicks

| Input | Result |
|---|---|
| left click | Dashboard → Overview (`IslandRouter.goOverview`) |
| right click | activity stack (state E) |
| middle click | close the island surface |
| `Super + I` | `qs -c voidshell ipc call island toggle` |
| `Escape` | closes the island surface first, then any popup beneath |

### Stack blocks (one surface, five segments — never five popups)

| Block | Contents | Feature key |
|---|---|---|
| Activities | running/finished activity rows, pinned first, with progress + registered actions | `jobs` |
| Controls | DND, keep-awake, volume, brightness (reuses `NotificationService`, `KeepAwake`, `VolumeService`, `BrightnessService`) | `volume` |
| Timers | 5/10/25 min presets + stopwatch, per-timer start/reset/remove | `timers` |
| Presets | saved arrangements + "save current snapshot" (allowlisted actions only: dnd / volume / mute / brightness) | `presets` |
| Clipboard | on-demand `cliphist` history, previews, strict-privacy redaction; refreshed only when the block opens | `clipboard` |

A block whose feature is off is not offered; a block whose provider is
missing still renders, honestly disabled with its written reason. The
body is capped at `min(560, 62 % of screen height)` and scrolls inside
the panel — the layer surface never grows past the output.

### Event pipeline

`JobBridge` (typed IPC) → `ActivityStore` (validated, sequence-ordered,
terminal states idempotent) → `AnnouncementEngine` (priority, dwell,
queue, DND/fullscreen/interaction gates) → `ClockPill` (state C) and
`IslandSurface` (states D/E). Dashboard routing goes through
`IslandRouter`, whose route grammar is a fixed allowlist — an event
payload can never name a command.

IPC (all typed, all allowlisted):

```sh
qs -c voidshell ipc call island toggle            # open/close the stack
qs -c voidshell ipc call island stack             # open the stack
qs -c voidshell ipc call island section timers    # acts|ctrl|timers|presets|clip
qs -c voidshell ipc call island context 'src/id'  # one activity's card
qs -c voidshell ipc call island close
qs -c voidshell ipc call island diagnostics       # JSON capability matrix
qs -c voidshell ipc call job publish '<json>'     # activity/event publishing
```

### Configuration (`~/.local/share/voidshell/island.json`)

Missing or malformed → documented defaults; every write is atomic.

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `true` | master switch for the whole Island |
| `features` | see `IslandSettings.defaultFeatures` | per-feature enable (`peek`, `progressEdge`, `levelAccent` default **off**; `workspace` default **on**) |
| `announce` | `"all"` (`"important"` for power/dnd/digest/presets/keepAwake/microphone/updates/storage/phone, `"none"` for clipboard) | per-feature announcement policy |
| `durationControl` / `durationTrack` / `durationDevice` / `durationNotification` / `durationJob` / `durationTimer` / `durationWorkspace` | 1200 / 3000 / 3000 / 4000 / 4000 / 4000 / 800 ms | dwell per category |
| `queueLimit` | `20` | max queued announcements |
| `hoverPreview`, `hoverDelayMs` | `false`, `400` | opt-in read-only hover preview |
| `animation` | `"inherit"` | `inherit` \| `full` \| `reduced` \| `off` (falls back to `ManagerSettings`) |
| `privacy` | `"standard"` | `standard` \| `strict` — strict redacts clipboard previews entirely |
| `dndSuppress`, `fullscreenPolicy`, `monitorPolicy` | `true`, `"quiet"`, `"invoking"` | suppression rules |
| `batteryLow/Critical/Hysteresis`, `tempWarning/Hysteresis/CooldownMinutes` | 15 / 5 / 2, 80 / 3 / 10 | P0/P1 thresholds with hysteresis |
| `updateCheckMinutes` | `360` | SystemStats update cadence (was 15 min hard-coded) |
| `showSeconds` | `false` | optional seconds in the clock |
| `clipboardMaxEntries`, `historyRetention`, `reminderLeadMinutes`, `completionSound` | 60, 50, 10, `false` | misc |

Shortcuts are **not** stored here — they live in
`~/.config/hypr/hyprland.lua` like every other binding.

### Provider / permission requirements

`island diagnostics` reports the live matrix using the §21 vocabulary
(`ready | disabled | needs-config | missing | denied | unsupported |
stale | error`). On this machine:

| Provider | State | Why / what it needs |
|---|---|---|
| `clock`, `volume`, `audioDevices`, `bluetooth`, `battery`, `network`, `brightness`, `notifications`, `dnd`, `digest`, `timer`, `timers`, `calendar`, `tasks`, `presets`, `keepAwake`, `weather`, `microphone`, `screenshot`, `clipboard`, `updates`, `hardware`, `jobs` | **ready** | present — `wl-copy`/`wl-paste` + `cliphist`, `systemd-inhibit`, `playerctl` all installed |
| `updates` | **ready** (`pacman -Qu`) | `checkupdates` absent → official repos only, **AUR not checked** (labelled in diagnostics) |
| `powerProfiles` | **missing** | `powerprofilesctl` not installed |
| `recording` | **missing** | `wf-recorder` not installed |
| `phone` | **missing** | `kdeconnect-cli` not installed |
| `storage` | **missing** | no storage probe backend available |
| `media` | **ready** (service) | MPRIS service present, but no player this build can read: `mpv` is compiled without MPRIS and brave/Chromium publishes the Player properties on the root path `/org/mpris/MediaPlayer2` instead of `/org/mpris/MediaPlayer2/Player`, so brave playback never reaches `MediaService` and no playback announcement is produced |
| `brightnessNightLight` | **missing** | `hyprsunset` not installed — no night-light backend |
| `workspace` | **ready** | announcement on by default (flipped with the Living State Island); the off path is forced with `islandAnnouncements: false` |
| `peek`, `progressEdge`, `levelAccent` | **disabled** | opt-in features, default off |

Nothing above is simulated: a missing provider disables its control
with the written reason, it never shows a fake success.

### Island gate — `scripts/island-check.sh`

Proves I1 pill allocation never changes · I2 an announcement actually
paints in the pill and expires (pixel diff inside, 0 outside) · I3 the
stack opens, shows the published activity and closes · I4
one-primary-surface holds with the island involved · I5 bad payloads
are rejected, not rendered · I6 a late update cannot regress progress ·
I7 terminal states are idempotent · I8 lock drops the island · I9 one
instance, 0 WARN/0 ERROR.

### Living State Island — acceptance results

| # | Check | Result |
|---|---|---|
| **L.1** | Clock allocation untouched: `555 10 170 56` asserted during every island state, `coord-check.sh` `primary_total` still 3 bar layers + `voidshell-island` | **PASS** — `PHASE-F-PROBE-PASS`, `ISLAND-CHECK-PASS` I1 |
| **L.2** | Announcement paints inside the pill and returns to the clock; nothing outside the pill moves (diff 0.000 on the neighbours) | **PASS** — `island-check.sh` I2 |
| **L.3** | Stack shows published activity, context card renders Pin / Return-to-work / Dashboard actions, close is clean | **PASS** — `island-check.sh` I3, runtime capture |
| **L.4** | Five segmented blocks render with section-aware headers; clipboard refreshes on open; body scrolls under the 62 %-screen cap | **PASS** — runtime capture of all five sections |
| **L.5** | Validation & ordering: malformed / unidentified / badly-keyed payloads rejected; sequence regression blocked; double-finish idempotent | **PASS** — `island-check.sh` I5–I7 |
| **L.6** | Lock drops the surface; lock cannot be dismissed by IPC | **PASS** — `island-check.sh` I8 |
| **L.7** | Full sweep in one run: `check` · `smoke-test` · `popup-check` (10/10) · `tab-check` (5/5) · `coord-check` · `hardening-check` · `island-check`, one instance, 0 WARN/0 ERROR | **PASS** |

**Not exercised live:** pointer hover previews and wheel scrolling
(no input injection on this machine) — verified by code + the scroll cap
geometry, not by a synthetic event; `powerprofilesctl` / `hyprsunset` /
`kdeconnect-cli` / `wf-recorder` paths could not be run because the
binaries are absent (reported as `missing`, not faked).
