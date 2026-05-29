#!/usr/bin/env bash
# run_sentinel.sh — v2.0 active-run sentinel. Arms the deterministic critic-gate
# hook (critic_stop.sh) ONLY while a Loom run is in flight, so the global hook is
# a strict no-op for every unrelated Claude Code session.
#
# Usage:
#   run_sentinel.sh start [session_id]   → write state/run/active.json + flag
#   run_sentinel.sh stop                 → remove sentinel + reset retry counter + flag
#   run_sentinel.sh status               → print sentinel JSON (or "none")
#   run_sentinel.sh active               → exit 0 if active for THIS cwd, else 1
#   run_sentinel.sh phase <name>         → update current phase (for progress UI)
#
# Sentinel content is metadata-only: { run_id, cwd_hash, started_epoch, retries }.
# cwd_hash scopes the gate to the directory the run started in, so a Loom run in
# repo A never gates an unrelated SubagentStop in repo B.
#
# State: ~/.claude/skills/loom/state/run/{active.json,critic_retries}

set -uo pipefail

STATE_DIR="${HOME}/.claude/skills/loom/state"
RUN_DIR="${STATE_DIR}/run"
SENTINEL="${RUN_DIR}/active.json"
RETRIES="${RUN_DIR}/critic_retries"
# Status-bar flag: a tiny file the statusline script reads to render [LOOM:<phase>].
# Lives at config root (next to caveman's .caveman-active) so the statusline finds
# it without knowing the skill's state dir. Content: just the phase token (or "active").
FLAG="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/.loom-active"
mkdir -p "${RUN_DIR}" 2>/dev/null || true

# Write the status-bar flag with ONLY a sanitized phase token (lowercase, [a-z0-9-]).
# Mirrors caveman's hardening: no control bytes, capped, whitelist-friendly.
write_flag() {
    local p
    p="$(printf '%s' "${1:-active}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-' | head -c 24)"
    [ -n "${p}" ] || p="active"
    printf '%s' "${p}" > "${FLAG}" 2>/dev/null || true
}

cwd_hash() {
    local cwd
    cwd="$(pwd 2>/dev/null || echo '?')"
    printf '%s' "${cwd}" | shasum -a 256 2>/dev/null | awk '{print $1}' | cut -c1-16
}

cmd="${1:-}"
shift || true

case "${cmd}" in
    start)
        session_id="${1:-unknown}"
        init_phase="${2:-starting}"
        ch="$(cwd_hash)"
        epoch="$(date +%s)"
        python3 -c '
import json, sys
print(json.dumps({
    "run_id": sys.argv[1],
    "cwd_hash": sys.argv[2],
    "started_epoch": int(sys.argv[3]),
    "retries": 0,
    "current_phase": sys.argv[4],
    "phase_epoch": int(sys.argv[3]),
}))' "${session_id}" "${ch}" "${epoch}" "${init_phase}" > "${SENTINEL}" 2>/dev/null || true
        printf '0' > "${RETRIES}" 2>/dev/null || true
        write_flag "${init_phase}"
        echo "[run_sentinel] armed (run=${session_id} cwd_hash=${ch} phase=${init_phase})" >&2
        ;;
    stop)
        rm -f "${SENTINEL}" "${RETRIES}" "${FLAG}" 2>/dev/null || true
        echo "[run_sentinel] cleared" >&2
        ;;
    phase)
        name="${1:?phase name required}"
        # Update current_phase in the sentinel (if armed) and refresh the flag.
        if [ -f "${SENTINEL}" ]; then
            epoch="$(date +%s)"
            python3 -c '
import json, sys
path, name, epoch = sys.argv[1], sys.argv[2], int(sys.argv[3])
try:
    with open(path) as f:
        o = json.load(f)
except Exception:
    o = {}
o["current_phase"] = name
o["phase_epoch"] = epoch
with open(path, "w") as f:
    json.dump(o, f)
' "${SENTINEL}" "${name}" "${epoch}" 2>/dev/null || true
        fi
        write_flag "${name}"
        echo "[run_sentinel] phase=${name}" >&2
        ;;
    status)
        if [ -f "${SENTINEL}" ]; then cat "${SENTINEL}"; else echo "none"; fi
        ;;
    active)
        # Active only if sentinel exists AND its cwd_hash matches current cwd.
        [ -f "${SENTINEL}" ] || exit 1
        want="$(cwd_hash)"
        have="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("cwd_hash",""))' "${SENTINEL}" 2>/dev/null || echo "")"
        [ -n "${have}" ] && [ "${have}" = "${want}" ]
        ;;
    *)
        echo "Usage: $0 {start [session_id] [phase]|stop|status|active|phase <name>}" >&2
        exit 2
        ;;
esac
