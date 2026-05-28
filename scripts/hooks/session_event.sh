#!/usr/bin/env bash
# session_event.sh — SessionStart and Stop hook handler.
#
# Reads JSON event from stdin, appends a single metadata-only JSON line to
# ~/.claude/skills/loom/state/events.jsonl. JSONL is the right
# shape for an append-only time-ordered log: no schema, no daemon, no lock
# contention, trivial to inspect with `tail` / `jq`.
#
# Usage (from the hooks block in ~/.claude/settings.json):
#   session_event.sh start
#   session_event.sh stop
#
# Failure mode: silent best-effort. Any error → exit 0. Hooks must NEVER
# bubble errors up to Claude Code or block the main flow.

set -u  # NOT -e: hooks are silently lossy by design.

cmd="${1:-stop}"
JSONL="${HOME}/.claude/skills/loom/state/events.jsonl"
mkdir -p "$(dirname "${JSONL}")" 2>/dev/null

# Read the event payload (capped at 64KB so a runaway client can't fill memory).
event="$(head -c 65536 || true)"

# Build a metadata-only line. cwd is hashed so project paths don't sit
# in plaintext in a user-scope log. The raw event payload is NEVER persisted.
python3 - "${cmd}" "${event}" >> "${JSONL}" 2>/dev/null <<'PY' || exit 0
import datetime, hashlib, json, os, sys
cmd, raw = sys.argv[1], sys.argv[2]
cwd = os.getcwd() if os.path.exists(".") else "?"
cwd_basename = os.path.basename(cwd)[:60] if cwd else ""
cwd_hash     = hashlib.sha256(cwd.encode("utf-8", "replace")).hexdigest()[:16] if cwd else ""
print(json.dumps({
    "ts":           datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "kind":         "session-" + cmd,
    "cwd_basename": cwd_basename,
    "cwd_hash":     cwd_hash,
    "event_bytes":  len(raw),
}))
PY
exit 0
