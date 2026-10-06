# VOID SHELL — Design System

Authoritative sources: `common/Colors.qml` (color tokens) and
`common/Theme.qml` (geometry, type, motion). No module may hardcode
values that belong here (PRD §7–10, §11–14).

## 1. Color tokens (`common/Colors.qml`)

Every token is a **binding onto `ThemeService`**: preset (§20.1), dark/
light mode (§20.2) and the optional dynamic wallpaper tone (§21) all
resolve there, so one theme change repaints the shell. Dark values are
the exact PRD palette for the default “Void Wallpaper” preset; light
mode is a complete parchment palette, not inverted text.

### Surfaces

| Token | Dark | Light |
|---|---|---|
| `bgRoot` | `#0A0810` | `#EFE7DA` |
| `bgDeep` | `#0E0B14` | `#E5DAC8` |
| `bgElevated` | `#15111D` | `#F4EEE2` |

### Glass ladder (translucent, readable over bright and dark wallpaper)

| Token | Dark (rgba) | Light (rgba) |
|---|---|---|
| `glassBase` | 18/15/26 @ 0.80 | 252/249/242 @ 0.82 |
| `glassElevated` | 24/19/34 @ 0.79 | 255/253/247 @ 0.85 |
| `glassCard` | 31/25/43 @ 0.82 | 255/255/252 @ 0.88 |
| `glassHover` | 43/34/59 @ 0.88 | 255/255/255 @ 0.94 |
| `glassPressed` | 53/42/72 @ 0.92 | 247/243/235 @ 0.96 |

Verified 2026-09-15 against sampled wallpaper pixels: `glassBase` 0.80
keeps primary text ≥ 7:1 everywhere and muted text ≥ 4.5:1 on nested
surfaces. Nested layers composite over each other, never over raw
wallpaper.

### Text

| Token | Dark | Light |
|---|---|---|
| `textPrimary` | `#F0E8E1` | `#1B1526` |
| `textSecondary` | `#D6CCD8` | `#453D52` |
| `textMuted` | `#A89CAF` | `#6B6274` |
| `textDisabled` | `#746B7D` | `#9A93A6` |
| `textOnAccent` | `#FCF8FF` | `#FCF8FF` |

### Accent family (from preset or wallpaper tone)

`accentPrimary · accentLight · accentTint · accentStrong · accentDeep`
resolve from `ThemeService.tone.accent`; support colors
`plum · plumMuted · indigo · indigoDeep` from `tone.support`; warm
wallpaper support `parchment · parchmentMuted · goldMuted` (support
only — never dominant).

Presets: **Void Wallpaper** (default, hue delta 0), **Frost, Mint,
Solar, Rose, Ocean** — each carries an accent quintet + support
quadruple.

### Semantic (mode-scoped; never derived from wallpaper pixels)

| Token | Dark | Light |
|---|---|---|
| `success` | `#39CFA0` | `#0E7D5E` |
| `warning` | `#EABD59` | `#8F6210` |
| `danger` | `#FF5B73` | `#C42B49` |
| `dangerDeep` | `#BC354F` | `#A3203C` |
| `info` | `#7F8DFF` | `#3D4BD6` |

Filled danger buttons use `dangerDeep` (white text = 5.3:1); `danger`
is for text/icons/glow on dark glass.

### Borders, glow, shadow

- Borders: `borderSubtle`, `borderGlass`, `borderAccent`,
  `borderAccentStrong` — dark values are PRD triples rotated with the
  accent hue (`ThemeService.hueDelta`), light values are ink strokes.
- `highlightTop` — inner top highlight for glass depth (not a border).
- Glow: `glowSoft`, `glowAccent`, `glowStrong`, `glowDanger` — dark =
  exact PRD triples + hue delta; light = softer accent wash.
- Shadow: `shadowSoft`, `shadowMedium`, `shadowDeep` — always painted as a
  **blurred** falloff (`layer.enabled` + `MultiEffect { blurEnabled }`),
  never as bare Rectangles: those have hard edges, and the two nested
  steps used to draw two concentric rings around a panel that read as a
  halo along the border on light wallpapers.

## 2. Glass recipe

`common/components/GlassCard.qml` / `GlassPanel.qml` layer:

1. translucent `glass*` fill (table above),
2. `borderSubtle`/`borderGlass` 1 px stroke,
3. inner `highlightTop` top edge,
4. optional `GlowBorder` (accent glow, used on active/focused pills),
5. drop shadow from the shadow ladder (blurred in QML, see §1).

Backdrop blur would be compositor-side (Hyprland layer rules for the
quickshell namespace); Void Shell never receives it:
every surface declares a `voidshell-*` namespace — `voidshell-bar`,
`voidshell-popup`, `voidshell-launcher`, `voidshell-media`,
`voidshell-toast`, `voidshell-lock`, `voidshell-overview`,
`voidshell-palette-grab`, `voidshell-wallpaper-overlay` — so the
`quickshell-blur` rule (namespace `^quickshell`, `~/.config/hypr/hyprland.lua`)
matches none of them. Hyprland 0.56 blurs *every* pixel of a matched
surface, zero-alpha pixels included, and has no ignore-zero-alpha option
(`hyprctl getoptions decoration:blur:ignore_alpha` → no such option), so
a matched surface paints a white halo across its transparent areas —
measured around the bar pills, in the gaps between them and around the
app drawer's shadow gutter. The glass recipe above plus QML shadows
therefore carry the whole look: `GlassPanel` never leans on compositor
blur.

## 3. Type

| Aspect | Value |
|---|---|
| UI font | `Outfit` (`Theme.fontUi`) |
| Mono / icons | `JetBrainsMono Nerd Font` (`Theme.fontMono`) |
| Body/label scale | 10–14 px (11/12/13 dominate) |
| Titles, pills, clock | 15–20 px (bar clock 19, launcher title 20) |
| Display (dashboard headers, power actions) | 26–44 px |
| Hero (lock + overlay clock) | 64–148 px |
| Weights | `Font.Medium` labels, `Font.DemiBold` emphasis |

## 4. Spacing & radii (`common/Theme.qml`)

- Spacing scale: `space4 8 12 16 20 24 32 48 64`.
- Radii: `radiusXs 6 · radiusSm 10 · radiusMd 14 · radiusLg 18 ·
  radiusXl 22 · radiusPanel 20`.

## 5. Geometry (top bar)

| Token | Value | Meaning |
|---|---|---|
| `topMargin` | 10 | distance from screen top to bar |
| `sideMargin` | 18 | outer screen margin |
| `barHeight` | 46 | pill height |
| `pillGap` | 8 | gap between slanted pills |
| `slantDepth` | 16 | parallelogram slant depth (`ShapePath`) |
| `pillBorderWidth` | 1 | pill stroke |

Three separate layer surfaces — left (launcher + workspaces + app
pill), center (brand + clock + date), right (status tray + power) —
each a slanted pill (`SlantedPill.qml`), **no continuous background
strip** (PRD §1). Popups anchor beneath their bar segment; launcher
margin = `topMargin + barHeight + space8`.

**Island width budget.** The clock island is centered, so each outer
island may occupy at most `screenW/2 − ceil(centerW/2) − sideMargin −
pillGap` (529 px at 1280 logical). `Bar.qml` splits any shortfall
before it can reach the clock: the tray folds items, the media pill
elides text then shrinks artwork, and the status pill tightens content
padding, then segment gaps, then — last resort — the battery
percentage. Every pill reports `naturalWidth` plus its lever capacity,
so the split never clips content and never binds-loops.

## 6. Motion

| Token | Value |
|---|---|
| `durationFast` | 140 ms (hovers, presses) |
| `durationNormal` | 180 ms (in-place state) |
| `durationPanel` | 220 ms (popup enter/exit) |
| `pressedScale` | 0.985 (pressed feedback) |

Easing: standard `OutCubic`-class curves via `NumberAnimation`/
`Behavior` in components; no looping animations exist anywhere in the
shell (verified — every `repeat: true` timer is gated by real state,
see `docs/performance.md`).
