#!/usr/bin/env bash
# reflexion.sh — Phase 9 self-learning. Append/read post-mortems keyed by task hash.
#
# Usage:
#   reflexion.sh hash <task description>          → emit sha1 of trimmed task
#   reflexion.sh write <hash> <attempt> <pass|fail> <failure_mode> <lesson>
#   reflexion.sh read <hash> [n]                  → last n lessons (default 3) for hash
#   reflexion.sh stats                            → counts of pass/fail across all tasks
#
# State: ~/.claude/skills/loom/state/reflections.jsonl

set -euo pipefail

STATE_DIR="${HOME}/.claude/skills/loom/state"
JSONL="${STATE_DIR}/reflections.jsonl"
mkdir -p "${STATE_DIR}"
[ -f "${JSONL}" ] || : > "${JSONL}"

cmd="${1:-}"
shift || true

case "${cmd}" in
    hash)
        # Trim + lowercase first 200 chars for stable hashing across retries
        printf '%s' "$*" | tr '[:upper:]' '[:lower:]' | head -c 200 | shasum -a 1 | awk '{print $1}'
        ;;
    write)
        hash="${1:?hash required}"
        attempt="${2:?attempt required}"
        outcome="${3:?outcome required}"
        failure_mode="${4:-}"
        lesson="${5:-}"
        ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        # Use python for safe JSON encoding (handles quotes/newlines in lesson)
        python3 -c '
import json, sys
print(json.dumps({
    "ts": sys.argv[1],
    "task_hash": sys.argv[2],
    "attempt": int(sys.argv[3]),
    "outcome": sys.argv[4],
    "failure_mode": sys.argv[5],
    "lesson": sys.argv[6],
}))' "${ts}" "${hash}" "${attempt}" "${outcome}" "${failure_mode}" "${lesson}" >> "${JSONL}"
        echo "[reflexion] wrote attempt ${attempt} outcome=${outcome} hash=${hash:0:8}" >&2
        ;;
    read)
        hash="${1:?hash required}"
        n="${2:-3}"
        python3 -c '
import json, sys
hash, n, path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
matches = []
try:
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                obj = json.loads(line)
                if obj.get("task_hash") == hash:
                    matches.append(obj)
            except json.JSONDecodeError:
                continue
except FileNotFoundError:
    pass
for m in matches[-n:]:
    lesson = m.get("lesson", "").replace("\n", " ")
    attempt = m.get("attempt")
    outcome = m.get("outcome")
    print(f"[attempt {attempt}] {outcome}: {lesson}")
' "${hash}" "${n}" "${JSONL}"
        ;;
    stats)
        python3 -c '
import json, sys
from collections import Counter
c = Counter()
try:
    with open(sys.argv[1]) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                obj = json.loads(line)
                c[obj.get("outcome", "unknown")] += 1
            except json.JSONDecodeError:
                continue
except FileNotFoundError:
    pass
total = sum(c.values())
passes = c.get("pass", 0)
fails  = c.get("fail", 0)
other  = sum(v for k, v in c.items() if k not in ("pass", "fail"))
print(f"reflections total: {total}, pass: {passes}, fail: {fails}, other: {other}")
' "${JSONL}"
        ;;
    *)
        echo "Usage: $0 {hash|write|read|stats} [args...]" >&2
        exit 2
        ;;
esac
