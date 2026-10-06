#!/usr/bin/env python3
"""Custom tab bar for the Void Shell ink-glass kitty.

kitty loads this file from the *config root* as ``tab_bar.py`` whenever
``tab_bar_style custom`` is set (kitty does not look in subdirectories —
that is why this file is not under tabs/, contrary to the project brief).

What it draws, matching the Void Shell Waybar language:

  * slanted separators (same E0BC/E0BE shapes kitty's own slant style
    uses), so tabs read as cut glass pills rather than rounded buttons
  * a role icon derived from the tab title: shell / editor / git /
    build / logs / server / ssh / root
  * state accents that stay readable without parsing the text:
        active tab   -> violet pill (bar accent #2A1A4D)
        inactive tab -> flat ink pill, muted text
        ssh session  -> cyan pill   (set by the desktop_state watcher)
        root session -> red pill    (set by the desktop_state watcher)
  * an amber dot on a tab that produced output while unfocused

Everything here is pure string/colour work: no subprocess, no filesystem
access, no per-frame cost beyond a handful of screen.draw() calls.
"""

from kitty.fast_data_types import Screen
from kitty.tab_bar import DrawData, ExtraData, TabBarData, as_rgb, draw_title
from kitty.utils import color_as_int

# --- palette (mirrors conf.d/20-colors.conf) ----------------------------
BAR_BG = 0x0C0912
ACTIVITY_DOT = 0xEABD59  # bar warning #EABD59

SSH_BG = 0x0E2A33  # deep cyan, quiet
SSH_FG = 0xA9F0FF  # textMuted-cyan partner of #67E8F9
ROOT_BG = 0x33141C  # danger #FF5B73 at pill depth
ROOT_FG = 0xFF8FA3

LEFT_SEP = ""
RIGHT_SEP = ""

# Nerd Font icons that JetBrainsMono NF is known to ship (all are from
# the stable nf-fa / nf-dev sets, not the riskier nf-md additions).
ICONS = {
    "shell": "",
    "editor": "",
    "git": "",
    "build": "",
    "logs": "",
    "serve": "",
    "ssh": "",
    "root": "",
}

_ROLE_KEYWORDS = (
    ("editor", ("nvim", " vim", "vim ", "neovide")),
    ("git", ("git", "lazygit", "jj ", "tig ")),
    ("build", ("make", "cargo", "cmake", "ninja", "npm", "pnpm", "yarn", "gradle", " meson", "gcc ", "g++")),
    ("logs", ("journalctl", "logs", "tail ", "less ")),
    ("serve", ("http.server", " vite", "serve", " dev")),
)


def _role(title: str) -> str:
    """Map a tab title to a role. The watcher writes plain-ASCII prefixes
    ('ssh: host', 'ROOT') so the stateful roles never depend on a glyph."""
    t = (title or "").strip()
    low = t.lower()
    if t.startswith("ROOT"):
        return "root"
    if low.startswith("ssh:") or low.startswith("ssh "):
        return "ssh"
    for role, words in _ROLE_KEYWORDS:
        for word in words:
            if word in low:
                return role
    return "shell"


def draw_tab(
    draw_data: DrawData,
    screen: Screen,
    tab: TabBarData,
    before: int,
    max_tab_length: int,
    index: int,
    is_last: bool,
    extra_data: ExtraData,
) -> int:
    bar_bg = as_rgb(color_as_int(draw_data.default_bg))
    tab_bg = as_rgb(draw_data.tab_bg(tab))
    tab_fg = as_rgb(draw_data.tab_fg(tab))

    role = _role(tab.title)
    if role == "root":
        tab_bg, tab_fg = as_rgb(ROOT_BG), as_rgb(ROOT_FG)
    elif role == "ssh":
        tab_bg, tab_fg = as_rgb(SSH_BG), as_rgb(SSH_FG)

    # kitty calls this twice per redraw: once with for_layout=True to
    # measure the tab's ideal width, then for real with that width as
    # the budget. Laying out to the *content* width (instead of filling
    # the budget) is what makes pills hug their titles, the Waybar way.
    layout = bool(getattr(extra_data, "for_layout", False))

    budget = max(0, max_tab_length)
    if budget < 8:
        screen.cursor.bg = tab_bg
        screen.cursor.fg = tab_fg
        screen.draw("…")
        screen.cursor.bg = bar_bg
        screen.cursor.fg = tab_bg
        screen.draw(RIGHT_SEP)
        return screen.cursor.x

    leading = 0
    if screen.cursor.x > 0:
        screen.cursor.bg = tab_bg
        screen.cursor.fg = bar_bg
        screen.draw(LEFT_SEP)
        leading = 1

    # pill interior: ' icon marker title '
    screen.cursor.bg = tab_bg
    screen.cursor.fg = tab_fg
    screen.draw(" ")
    leading += 1
    screen.draw(ICONS[role])
    leading += 1

    if tab.has_activity_since_last_focus and not tab.is_active:
        screen.cursor.fg = as_rgb(ACTIVITY_DOT)
        screen.draw("●")
    else:
        screen.draw(" ")
    leading += 1

    # trailing: padding space + right slant cell
    title_budget = max(1, budget - leading - 2)
    draw_title(draw_data, screen, tab, index, title_budget)

    limit = before + budget - 2
    if screen.cursor.x > limit:
        screen.cursor.x = max(before, limit)
        screen.draw("…")
    screen.cursor.bg = tab_bg
    screen.cursor.fg = tab_fg
    if layout:
        # Measurement pass: end at the content width, so kitty sizes the
        # pill to the title instead of stretching it across the bar.
        screen.draw(" ")
    else:
        while screen.cursor.x < limit:
            screen.draw(" ")
        screen.draw(" ")

    screen.cursor.bg = bar_bg
    screen.cursor.fg = tab_bg
    screen.draw(RIGHT_SEP)
    return screen.cursor.x
