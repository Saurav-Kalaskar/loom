#!/usr/bin/env bash
# session_checkpoint.sh — Phase 10 conversational state checkpoints.
#
# Usage:
#   session_checkpoint.sh new                              → emit new session id
#   session_checkpoint.sh write <id> <phase> <state_json>  → checkpoint after a phase
#   session_checkpoint.sh read <id>                        → emit latest state for session
#   session_checkpoint.sh list                             → list all sessions newest-first
#   session_checkpoint.sh prune <days>                     → delete sessions older than N days
#
# State: ~/.claude/skills/loom/state/sessions/<id>/state.json

set -euo pipefail

STATE_DIR="${HOME}/.claude/skills/loom/state/sessions"
mkdir -p "${STATE_DIR}"

cmd="${1:-}"
shift || true

case "${cmd}" in
    new)
        # Date prefix + 6 hex chars = sortable, human-skimmable, collision-resistant
        printf '%s-%s' "$(date -u +%Y%m%d-%H%M%S)" "$(LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 6)"
        ;;
    write)
        id="${1:?session id required}"
        phase="${2:?phase required}"
        state_json="${3:?state json required}"
        sess_dir="${STATE_DIR}/${id}"
        mkdir -p "${sess_dir}"
        # Validate input JSON before writing; fail loud if malformed
        if ! printf '%s' "${state_json}" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
            echo "[checkpoint] ERROR: state json is not valid JSON" >&2
            exit 3
        fi
        ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        python3 -c '
import json, sys
ts, phase, raw = sys.argv[1], sys.argv[2], sys.argv[3]
state = json.loads(raw)
state["_meta"] = {"ts": ts, "phase": phase}
print(json.dumps(state, indent=2))
' "${ts}" "${phase}" "${state_json}" > "${sess_dir}/state.json"
        echo "[checkpoint] session ${id} phase ${phase} saved" >&2
        ;;
    read)
        id="${1:?session id required}"
        f="${STATE_DIR}/${id}/state.json"
        if [ -f "${f}" ]; then
            cat "${f}"
        else
            echo "[checkpoint] no session ${id}" >&2
            exit 4
        fi
        ;;
    list)
        # Newest first; show id + phase + ts
        for d in $(ls -1t "${STATE_DIR}" 2>/dev/null); do
            f="${STATE_DIR}/${d}/state.json"
            if [ -f "${f}" ]; then
                meta=$(python3 -c '
import json, sys
try:
    s = json.load(open(sys.argv[1])).get("_meta", {})
    phase = s.get("phase", "?")
    ts    = s.get("ts", "?")
    print(f"{phase}\t{ts}")
except Exception:
    print("?\t?")
' "${f}")
                printf '%s\t%s\n' "${d}" "${meta}"
            fi
        done
        ;;
    prune)
        days="${1:-30}"
        # macOS find: -mtime +N matches files older than N days
        find "${STATE_DIR}" -mindepth 1 -maxdepth 1 -type d -mtime "+${days}" -exec rm -rf {} + 2>/dev/null || true
        echo "[checkpoint] pruned sessions older than ${days} days" >&2
        ;;
    *)
        echo "Usage: $0 {new|write|read|list|prune} [args...]" >&2
        exit 2
        ;;
esac
