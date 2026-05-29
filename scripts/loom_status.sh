#!/usr/bin/env bash
# loom_status.sh — statusline badge for Loom. Renders [LOOM] / [LOOM:<phase>]
# while a Loom run is active, nothing otherwise.
#
# Reads the flag file written by run_sentinel.sh (start/phase/stop). The flag
# holds ONLY a sanitized phase token; this script re-validates anyway.
#
# Usage in ~/.claude/settings.json (directly, or via the chained wrapper):
#   "statusLine": { "type": "command", "command": "bash /path/to/loom_status.sh" }
#
# Security: mirrors caveman-statusline.sh hardening. The flag could be planted
# by a local attacker, so: refuse symlinks, cap the read, strip everything
# outside [a-z0-9-], and only emit a fixed-format badge (never echo raw bytes).

FLAG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.loom-active"

# Refuse symlinks — a planted symlink could point the badge at arbitrary file
# bytes (including ANSI escapes) rendered every keystroke.
[ -L "$FLAG" ] && exit 0
[ ! -f "$FLAG" ] && exit 0

# Cap at 24 bytes, drop CR/LF, lowercase, strip to [a-z0-9-]. Blocks terminal
# escape injection / OSC hyperlink spoofing via flag contents.
PHASE=$(head -c 24 "$FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')

# Loom brand color: teal (256-color 37). Distinct from caveman's orange (172).
COLOR=$'\033[38;5;37m'
RESET=$'\033[0m'

if [ -z "$PHASE" ] || [ "$PHASE" = "active" ] || [ "$PHASE" = "starting" ]; then
    printf '%s[LOOM]%s' "$COLOR" "$RESET"
else
    # Known phases get the labeled badge; anything else still renders safely
    # (already sanitized to [a-z0-9-], so it can't break the terminal).
    printf '%s[LOOM:%s]%s' "$COLOR" "$PHASE" "$RESET"
fi
