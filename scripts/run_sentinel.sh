#!/usr/bin/env bash
# run_sentinel.sh — v2.0 active-run sentinel. Arms the deterministic critic-gate
# hook (critic_stop.sh) ONLY while a Loom run is in flight, so the global hook is
# a strict no-op for every unrelated Claude Code session.
#
# Usage:
#   run_sentinel.sh start [session_id]   → write state/run/active.json
#   run_sentinel.sh stop                 → remove sentinel + reset retry counter
#   run_sentinel.sh status               → print sentinel JSON (or "none")
#   run_sentinel.sh active               → exit 0 if active for THIS cwd, else 1
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
mkdir -p "${RUN_DIR}" 2>/dev/null || true

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
        ch="$(cwd_hash)"
        epoch="$(date +%s)"
        python3 -c '
import json, sys
print(json.dumps({
    "run_id": sys.argv[1],
    "cwd_hash": sys.argv[2],
    "started_epoch": int(sys.argv[3]),
    "retries": 0,
}))' "${session_id}" "${ch}" "${epoch}" > "${SENTINEL}" 2>/dev/null || true
        printf '0' > "${RETRIES}" 2>/dev/null || true
        echo "[run_sentinel] armed (run=${session_id} cwd_hash=${ch})" >&2
        ;;
    stop)
        rm -f "${SENTINEL}" "${RETRIES}" 2>/dev/null || true
        echo "[run_sentinel] cleared" >&2
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
        echo "Usage: $0 {start [session_id]|stop|status|active}" >&2
        exit 2
        ;;
esac
