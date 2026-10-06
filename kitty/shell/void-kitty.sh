# Living Kitty — shell helpers, sourced from ~/.bashrc.
#
# Everything here is optional: kitty itself never depends on this file,
# and no alias is required to launch a terminal (Super+Q in hyprland.lua
# already starts kitty directly).

# Helper scripts that ship with the config: kproject, kimg, kdiff, kssh,
# validate-config. Added once, at the front of PATH.
_kitty_scripts="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/scripts"
case ":${PATH}:" in
    *":${_kitty_scripts}:"*) ;;
    *) [ -d "${_kitty_scripts}" ] && PATH="${_kitty_scripts}:${PATH}" ;;
esac
unset _kitty_scripts

# kq — toggle the quick-access terminal (same surface as Super+grave).
kq() { kitten quick-access-terminal; }

# ksession <name> — start sessions/<name>.conf as a new kitty window.
ksession() {
    local dir="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/sessions"
    local name="${1:-}"
    if [ -z "${name}" ]; then
        {
            printf 'usage: ksession <name>\navailable sessions:\n'
            local f
            for f in "${dir}"/*.conf; do
                [ -e "${f}" ] && printf '  %s\n' "$(basename "${f}" .conf)"
            done
        } >&2
        return 2
    fi
    if [ ! -f "${dir}/${name}.conf" ]; then
        printf 'ksession: no such session: %s (looked in %s)\n' "${name}" "${dir}" >&2
        return 1
    fi
    kitty --session "${dir}/${name}.conf" --title "kitty:${name}"
}

# Tab-complete session names.
_ksession_completions() {
    local dir="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/sessions" names="" f
    for f in "${dir}"/*.conf; do
        [ -e "${f}" ] && names="${names} $(basename "${f}" .conf)"
    done
    COMPREPLY=($(compgen -W "${names}" -- "${COMP_WORDS[1]}"))
    return 0
}
complete -F _ksession_completions ksession 2>/dev/null || true
