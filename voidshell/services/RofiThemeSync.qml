pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../common"

// VOID SHELL — rofi's half of the app drawer (SUPER+R).
//
// voidshell ships two drawers on purpose: SUPER+R runs `rofi -show drun`,
// SUPER+Space runs the shell's own launcher, and they are meant to read as
// one surface. That splits cleanly in two, and neither half may drift into
// the other:
//
//   ~/.config/rofi/config.rasi     structure and behaviour — geometry,
//                                  fonts, widget rules. Hand-editable, and
//                                  it carries a fallback palette so rofi
//                                  still paints correctly before the shell
//                                  starts (the clipboard picker is bound
//                                  to `rofi -dmenu` too, and has to work
//                                  either way).
//   ~/.config/rofi/voidshell.rasi  GENERATED — this file. Colour only.
//
// Every name config.rasi reads is re-exported from common/Colors.qml, so
// the export is a binding, not a snapshot: change preset, flip light/dark,
// or let WallpaperService push a dynamic wallpaper tone and the tokens
// below move, `rasi` re-renders, and the handler writes the file back out.
// The next rofi invocation is on the new theme with no manual step.
//
// Two deliberate choices:
//  * outside ~/.config/quickshell/ — quickshell watches its own tree, so
//    writing there would reload the shell on every theme change, and the
//    reload would change the theme again: a loop;
//  * `?import` in config.rasi rather than `@import` — the file only exists
//    once the shell has started, and config.rasi must keep parsing until
//    then.
Singleton {
    id: root

    // The same absolute path config.rasi imports.
    readonly property string path: StorageService.home + "/.config/rofi/voidshell.rasi"

    // The generated body. One binding over Colors: it re-evaluates the
    // moment any token underneath it moves, which is what makes this live.
    readonly property string rasi: root.render()

    // Last body handed to FileView. Collapses the redundant write when the
    // initial binding and Component.onCompleted both fire, and stops an
    // unchanged theme from rewriting the file. Cleared on save failure so
    // the next change retries instead of believing it landed.
    property string last: ""

    // True once the file has actually been written. shell.qml references
    // this so the singleton is instantiated eagerly rather than on first
    // use — a theme export nothing reads would otherwise never be made.
    property bool written: false

    property bool started: false

    FileView {
        id: out
        path: root.path
        printErrors: false
        onSaved: root.written = true
        onSaveFailed: error => {
            root.written = false;
            root.last = "";
            console.warn("[voidshell] could not write rofi theme", root.path, "error", error);
        }
    }

    function write() {
        const body = root.rasi;
        if (body === root.last) {
            return;
        }
        root.last = body;
        out.setText(body);
    }

    onRasiChanged: if (root.started) root.write()

    Component.onCompleted: {
        root.started = true;
        root.write();
    }

    // #RRGGBBAA — alpha last, which is rofi's byte order and Qt's own, so
    // nothing has to be shuffled. Built byte by byte because a colour's
    // string form is #AARRGGBB and would come out transposed.
    function hexByte(v) {
        const n = Math.max(0, Math.min(255, Math.round(v * 255)));
        return (n < 16 ? "0" : "") + n.toString(16).toUpperCase();
    }

    function hex(c) {
        return "#" + root.hexByte(c.r) + root.hexByte(c.g) + root.hexByte(c.b) + root.hexByte(c.a);
    }

    function render() {
        const clear = "#00000000";

        // voidshell's names — exactly the set config.rasi's fallback block
        // declares, so this file overrides it name for name.
        const panel = root.hex(Colors.launcherSurface);
        const panelBorder = root.hex(Colors.launcherSurfaceBorder);
        const field = root.hex(Colors.glassCard);
        const fieldBorder = root.hex(Colors.borderSubtle);
        const fieldBorderFocus = root.hex(Colors.borderAccent);
        const text = root.hex(Colors.textPrimary);
        const textSecondary = root.hex(Colors.textSecondary);
        const textMuted = root.hex(Colors.textMuted);
        const textDisabled = root.hex(Colors.textDisabled);
        const accent = root.hex(Colors.accentPrimary);
        const accentLight = root.hex(Colors.accentLight);
        const accentStrong = root.hex(Colors.accentStrong);
        const onAccent = root.hex(Colors.textOnAccent);
        const tile = root.hex(Colors.launcherTile);
        const tileBorder = root.hex(Colors.launcherTileBorder);
        const tileHover = root.hex(Colors.glassHover);
        const deep = root.hex(Colors.bgDeep);
        const elevated = root.hex(Colors.bgElevated);
        const danger = root.hex(Colors.danger);
        const success = root.hex(Colors.success);
        const warning = root.hex(Colors.warning);

        // rofi's own palette slots, redirected onto the same tokens: these
        // are what `element normal/selected/urgent/active` inherit from.
        const pairs = [
            ["background", panel],
            ["foreground", text],
            ["background-color", clear],
            ["normal-background", clear],
            ["normal-foreground", text],
            ["alternate-normal-background", clear],
            ["alternate-normal-foreground", text],
            ["selected-normal-background", tile],
            ["selected-normal-foreground", text],
            ["urgent-background", danger],
            ["urgent-foreground", onAccent],
            ["alternate-urgent-background", danger],
            ["alternate-urgent-foreground", onAccent],
            ["selected-urgent-background", danger],
            ["selected-urgent-foreground", onAccent],
            ["active-background", accent],
            ["active-foreground", onAccent],
            ["alternate-active-background", accent],
            ["alternate-active-foreground", onAccent],
            ["selected-active-background", accent],
            ["selected-active-foreground", onAccent],
            ["separatorcolor", fieldBorder],
            ["lightbg", textSecondary],
            ["lightfg", textMuted],

            ["panel", panel],
            ["panel-border", panelBorder],
            ["field", field],
            ["field-border", fieldBorder],
            ["field-border-focus", fieldBorderFocus],
            ["text", text],
            ["text-secondary", textSecondary],
            ["text-muted", textMuted],
            ["text-disabled", textDisabled],
            ["accent", accent],
            ["accent-light", accentLight],
            ["accent-strong", accentStrong],
            ["on-accent", onAccent],
            ["tile", tile],
            ["tile-border", tileBorder],
            ["tile-hover", tileHover],
            ["deep", deep],
            ["elevated", elevated],
            ["danger", danger],
            ["success", success],
            ["warning", warning]
        ];

        let body = "/*\n"
            + " * GENERATED by voidshell services/RofiThemeSync.qml — do not edit.\n"
            + " *\n"
            + " * Re-exported from common/Colors.qml on every theme change (preset,\n"
            + " * light/dark, wallpaper tone). Colour only: structure and behaviour\n"
            + " * live in ~/.config/rofi/config.rasi, which `?import`s this file.\n"
            + " */\n"
            + "* {\n";

        for (let i = 0; i < pairs.length; i++) {
            const name = pairs[i][0];
            const pad = Math.max(1, 30 - name.length);
            body += "    " + name + ":" + " ".repeat(pad) + pairs[i][1] + ";\n";
        }

        return body + "}\n";
    }
}
