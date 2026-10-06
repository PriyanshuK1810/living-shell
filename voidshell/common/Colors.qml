pragma Singleton

import Quickshell
import QtQuick
import "../services"

// VOID SHELL — authoritative color tokens.
// Values live in ThemeService (PRD §20): presets, dark/light mode and the
// optional dynamic wallpaper tone resolve there, and every token below is
// a binding onto that state, so one theme change repaints the shell.
//
// Dark-mode values are the exact PRD §7–10 palette for the default
// "Void Wallpaper" preset (hue delta 0 keeps borders/glows byte-identical).
// Light mode is a complete parchment palette, not inverted text (§20.2).
Singleton {
    id: root

    // BASE
    readonly property color bgRoot: ThemeService.light ? "#EFE7DA" : "#0A0810"
    readonly property color bgDeep: ThemeService.light ? "#E5DAC8" : "#0E0B14"
    readonly property color bgElevated: ThemeService.light ? "#F4EEE2" : "#15111D"

    // GLASS (translucent base — readable over bright and dark wallpaper).
    // Dark values verified 2026-09-15 against sampled wallpaper pixels
    // (parchment #F2E7D2 / ink #151826 / smoke #2B0CB5): glassBase 0.80
    // keeps primary text >= 7:1 everywhere and muted text >= 4.5 on every
    // nested surface. Nested layers composite over each other, not raw
    // wallpaper. Light mode mirrors the ladder with warm paper whites.
    readonly property color glassBase: ThemeService.light ? Qt.rgba(252 / 255, 249 / 255, 242 / 255, 0.82) : Qt.rgba(18 / 255, 15 / 255, 26 / 255, 0.80)
    readonly property color glassElevated: ThemeService.light ? Qt.rgba(255 / 255, 253 / 255, 247 / 255, 0.85) : Qt.rgba(24 / 255, 19 / 255, 34 / 255, 0.79)
    readonly property color glassCard: ThemeService.light ? Qt.rgba(255 / 255, 255 / 255, 252 / 255, 0.88) : Qt.rgba(31 / 255, 25 / 255, 43 / 255, 0.82)
    readonly property color glassHover: ThemeService.light ? Qt.rgba(255 / 255, 255 / 255, 255 / 255, 0.94) : Qt.rgba(43 / 255, 34 / 255, 59 / 255, 0.88)
    readonly property color glassPressed: ThemeService.light ? Qt.rgba(247 / 255, 243 / 255, 235 / 255, 0.96) : Qt.rgba(53 / 255, 42 / 255, 72 / 255, 0.92)

    // TEXT (dark ladder is PRD-exact; light ladder is warm ink-on-paper)
    readonly property color textPrimary: ThemeService.light ? "#1B1526" : "#F0E8E1"
    readonly property color textSecondary: ThemeService.light ? "#453D52" : "#D6CCD8"
    readonly property color textMuted: ThemeService.light ? "#6B6274" : "#A89CAF"
    readonly property color textDisabled: ThemeService.light ? "#9A93A6" : "#746B7D"
    readonly property color textOnAccent: "#FCF8FF"

    // ACCENT FAMILY (from the active preset or wallpaper dynamic tone)
    readonly property color accentPrimary: ThemeService.colorOf(ThemeService.tone.accent.primary)
    readonly property color accentLight: ThemeService.colorOf(ThemeService.tone.accent.light)
    readonly property color accentTint: ThemeService.colorOf(ThemeService.tone.accent.tint)
    readonly property color accentStrong: ThemeService.colorOf(ThemeService.tone.accent.strong)
    readonly property color accentDeep: ThemeService.colorOf(ThemeService.tone.accent.deep)

    // PLUM / INDIGO SUPPORT (per preset)
    readonly property color plum: ThemeService.colorOf(ThemeService.tone.support.plum)
    readonly property color plumMuted: ThemeService.colorOf(ThemeService.tone.support.plumMuted)
    readonly property color indigo: ThemeService.colorOf(ThemeService.tone.support.indigo)
    readonly property color indigoDeep: ThemeService.colorOf(ThemeService.tone.support.indigoDeep)

    // WARM WALLPAPER SUPPORT (support only — never dominant)
    readonly property color parchment: ThemeService.light ? "#FBF6EC" : "#E8DED2"
    readonly property color parchmentMuted: ThemeService.light ? "#D9CDBB" : "#BEB1A5"
    readonly property color goldMuted: ThemeService.light ? "#8F6E33" : "#B99A66"

    // SEMANTIC (mode-scoped; never derived from wallpaper pixels)
    // Dark: filled danger buttons use dangerDeep (white text = 5.3:1);
    // danger itself is for text/icons/glow on dark glass.
    readonly property color success: ThemeService.light ? "#0E7D5E" : "#39CFA0"
    readonly property color warning: ThemeService.light ? "#8F6210" : "#EABD59"
    readonly property color danger: ThemeService.light ? "#C42B49" : "#FF5B73"
    readonly property color dangerDeep: ThemeService.light ? "#A3203C" : "#BC354F"
    readonly property color info: ThemeService.light ? "#3D4BD6" : "#7F8DFF"

    // BORDERS (dark = exact PRD triples rotated with the accent hue;
    // light = ink strokes, accent borders follow the accent family)
    readonly property color borderSubtle: ThemeService.light ? Qt.rgba(64 / 255, 50 / 255, 86 / 255, 0.16) : ThemeService.rgba(ThemeService.rotateTriple([210, 193, 230], ThemeService.hueDelta), 0.14)
    readonly property color borderGlass: ThemeService.light ? Qt.rgba(76 / 255, 60 / 255, 102 / 255, 0.26) : ThemeService.rgba(ThemeService.rotateTriple([190, 158, 255], ThemeService.hueDelta), 0.24)
    readonly property color borderAccent: ThemeService.light ? ThemeService.rgba(ThemeService.hexToRgb(ThemeService.tone.accent.strong), 0.55) : ThemeService.rgba(ThemeService.rotateTriple([178, 132, 255], ThemeService.hueDelta), 0.56)
    readonly property color borderAccentStrong: ThemeService.light ? ThemeService.rgba(ThemeService.hexToRgb(ThemeService.tone.accent.strong), 0.75) : ThemeService.rgba(ThemeService.rotateTriple([186, 143, 255], ThemeService.hueDelta), 0.78)

    // Inner top highlight for glass depth (not a border token)
    readonly property color highlightTop: ThemeService.light ? Qt.rgba(255 / 255, 255 / 255, 255 / 255, 0.70) : ThemeService.rgba(ThemeService.rotateTriple([240, 232, 255], ThemeService.hueDelta), 0.10)

    // GLOW (dark = exact PRD triples + hue delta; light = softer accent wash)
    readonly property color glowSoft: ThemeService.light ? ThemeService.rgba(ThemeService.hexToRgb(ThemeService.tone.accent.primary), 0.14) : ThemeService.rgba(ThemeService.rotateTriple([118, 73, 215], ThemeService.hueDelta), 0.18)
    readonly property color glowAccent: ThemeService.light ? ThemeService.rgba(ThemeService.hexToRgb(ThemeService.tone.accent.primary), 0.22) : ThemeService.rgba(ThemeService.rotateTriple([148, 91, 255], ThemeService.hueDelta), 0.32)
    readonly property color glowStrong: ThemeService.light ? ThemeService.rgba(ThemeService.hexToRgb(ThemeService.tone.accent.primary), 0.30) : ThemeService.rgba(ThemeService.rotateTriple([165, 108, 255], ThemeService.hueDelta), 0.46)
    readonly property color glowDanger: ThemeService.light ? ThemeService.rgba(ThemeService.hexToRgb(root.danger), 0.25) : Qt.rgba(255 / 255, 91 / 255, 115 / 255, 0.28)

    // SHADOW
    readonly property color shadowSoft: ThemeService.light ? Qt.rgba(46 / 255, 34 / 255, 64 / 255, 0.14) : Qt.rgba(0, 0, 0, 0.28)
    readonly property color shadowMedium: ThemeService.light ? Qt.rgba(46 / 255, 34 / 255, 64 / 255, 0.22) : Qt.rgba(3 / 255, 1 / 255, 8 / 255, 0.40)
    readonly property color shadowDeep: ThemeService.light ? Qt.rgba(46 / 255, 34 / 255, 64 / 255, 0.30) : Qt.rgba(3 / 255, 1 / 255, 8 / 255, 0.55)

    // LAUNCHER GLASS POPUP (macOS-inspired launcher redesign).
    // Dark values are the launcher spec's exact rgba; light mode mirrors
    // the same translucency on parchment so the popup still follows
    // ThemeService instead of staying dark on a light shell.
    readonly property color launcherSurface: ThemeService.light ? Qt.rgba(255 / 255, 253 / 255, 247 / 255, 0.72) : Qt.rgba(35 / 255, 29 / 255, 48 / 255, 0.72)
    readonly property color launcherSurfaceBorder: ThemeService.light ? Qt.rgba(166 / 255, 120 / 255, 255 / 255, 0.35) : Qt.rgba(166 / 255, 120 / 255, 255 / 255, 0.45)
    readonly property color launcherTile: Qt.rgba(170 / 255, 120 / 255, 255 / 255, 0.12)
    readonly property color launcherTileBorder: ThemeService.light ? Qt.rgba(190 / 255, 150 / 255, 255 / 255, 0.30) : Qt.rgba(190 / 255, 150 / 255, 255 / 255, 0.20)
}
