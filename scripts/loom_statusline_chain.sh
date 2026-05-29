#!/usr/bin/env bash
# loom_statusline_chain.sh — composes multiple statusline badges into one line.
#
# Claude Code allows only ONE statusLine command. If another tool (e.g. the
# caveman plugin) already owns it, this wrapper runs BOTH so neither badge is
# lost: it emits the previously-configured statusline first, then the Loom badge.
#
# Install wires this as the statusLine command and records the prior command in
# the env var LOOM_PRIOR_STATUSLINE (set inline in the settings.json command
# string). If that var is empty, it auto-discovers the caveman badge script.
#
# Order: <prior/caveman badge> <space> <loom badge>. Each sub-script already
# self-hardens (symlink refusal, byte caps, sanitization); this wrapper only
# concatenates their stdout and never interprets it.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Claude Code passes session JSON on stdin to the statusline command. Capture it
# once and forward the same bytes to each child (they may or may not read it).
STDIN_DATA="$(cat 2>/dev/null || true)"

emit() {  # run a statusline command, feeding it the captured stdin
    local cmd="$1"
    [ -n "$cmd" ] || return 0
    printf '%s' "$STDIN_DATA" | bash -c "$cmd" 2>/dev/null || true
}

out=""

# 1. Prior statusline (explicit via env, else auto-discover caveman).
prior="${LOOM_PRIOR_STATUSLINE:-}"
if [ -z "$prior" ]; then
    # Auto-discover the caveman badge script (version dir is a glob — never hardcode).
    for c in "$HOME"/.claude/plugins/cache/caveman/caveman/*/src/hooks/caveman-statusline.sh; do
        [ -f "$c" ] && { prior="bash \"$c\""; break; }
    done
fi
prior_out="$(emit "$prior")"
[ -n "$prior_out" ] && out="$prior_out"

# 2. Loom badge.
loom_out="$(emit "bash \"$HERE/loom_status.sh\"")"
if [ -n "$loom_out" ]; then
    [ -n "$out" ] && out="$out $loom_out" || out="$loom_out"
fi

printf '%s' "$out"
