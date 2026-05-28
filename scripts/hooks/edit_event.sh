#!/usr/bin/env bash
# edit_event.sh — PreToolUse / PostToolUse Edit|Write hook handler.
#
# Appends one metadata-only JSON line per edit event to
# ~/.claude/skills/loom/state/edits.jsonl.
#
# Usage:
#   edit_event.sh pre
#   edit_event.sh post
#
# Privacy guarantee (verified by Phase B critic-gate review): file content,
# old_string, new_string, full file paths, and full cwd are NEVER persisted.
# Only:
#   - tool (Edit | Write)
#   - phase (pre | post)
#   - file_basename (last path component, max 120 chars)
#   - file_path_hash (sha256 truncated, 16 hex chars)
#   - cwd_basename, cwd_hash
#   - edit_size_bytes (length of new content / new_string, NOT the content itself)
#   - timestamp
#
# The hash lets you correlate ("did another session touch the same file?")
# without storing full paths or content.
#
# Failure mode: silent best-effort. Any error → exit 0.

set -u

phase="${1:-post}"
JSONL="${HOME}/.claude/skills/loom/state/edits.jsonl"
mkdir -p "$(dirname "${JSONL}")" 2>/dev/null

event="$(head -c 65536 || true)"

python3 - "${phase}" "${event}" >> "${JSONL}" 2>/dev/null <<'PY' || exit 0
import datetime, hashlib, json, os, sys
phase, raw = sys.argv[1], sys.argv[2]
tool = ""
file_basename  = ""
file_path_hash = ""
edit_bytes = 0
try:
    obj = json.loads(raw) if raw.strip() else {}
    tool = obj.get("tool_name", "") or ""
    ti   = obj.get("tool_input", {}) or {}
    fp   = ti.get("file_path", "") or ti.get("path", "") or ""
    if fp:
        file_basename  = os.path.basename(fp)[:120]
        file_path_hash = hashlib.sha256(fp.encode("utf-8", "replace")).hexdigest()[:16]
    if "content" in ti:
        edit_bytes = len(ti.get("content", "") or "")
    elif "new_string" in ti:
        edit_bytes = len(ti.get("new_string", "") or "")
except Exception:
    pass
cwd = os.getcwd() if os.path.exists(".") else "?"
cwd_basename = os.path.basename(cwd)[:60] if cwd else ""
cwd_hash     = hashlib.sha256(cwd.encode("utf-8", "replace")).hexdigest()[:16] if cwd else ""
print(json.dumps({
    "ts":              datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "phase":           phase,
    "tool":            tool,
    "file_basename":   file_basename,
    "file_path_hash":  file_path_hash,
    "cwd_basename":    cwd_basename,
    "cwd_hash":        cwd_hash,
    "edit_size_bytes": edit_bytes,
}))
PY
exit 0
