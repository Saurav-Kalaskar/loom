#!/usr/bin/env bash
# install.sh — install Loom into ~/.claude/skills/loom/
#
# Idempotent: safe to re-run. Backs up settings.json before touching it.
# Hooks block is opt-in (prompt at install time, default Yes).

set -euo pipefail

# ────────────────────────────────────────────────────────────────────────────
#  Paths
# ────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DEST_DIR="${HOME}/.claude/skills/loom"
SETTINGS="${HOME}/.claude/settings.json"
SKILL_NAME="loom"

# ────────────────────────────────────────────────────────────────────────────
#  Utilities
# ────────────────────────────────────────────────────────────────────────────
say()   { printf '\033[36m[loom]\033[0m %s\n' "$*"; }
warn()  { printf '\033[33m[loom]\033[0m %s\n' "$*" >&2; }
fatal() { printf '\033[31m[loom]\033[0m %s\n' "$*" >&2; exit 1; }
hr()    { printf '%s\n' "────────────────────────────────────────────────────────"; }

require() {
    command -v "$1" >/dev/null 2>&1 || fatal "missing required command: $1"
}

# ────────────────────────────────────────────────────────────────────────────
#  CLI flags
# ────────────────────────────────────────────────────────────────────────────
INSTALL_HOOKS=""   # "" = ask, "yes" = force install, "no" = skip
ASSUME_YES=0
while [ $# -gt 0 ]; do
    case "$1" in
        --hooks)     INSTALL_HOOKS="yes" ;;
        --no-hooks)  INSTALL_HOOKS="no"  ;;
        -y|--yes)    ASSUME_YES=1 ;;
        -h|--help)
            cat <<EOF
Usage: $0 [options]

Options:
  --hooks       Install Phase 11 lifecycle hooks without prompting
  --no-hooks    Skip Phase 11 hooks entirely
  -y, --yes     Assume yes for all prompts (defaults: install hooks)
  -h, --help    Show this help

Examples:
  bash install.sh             # interactive — asks about hooks
  bash install.sh --hooks     # install everything including hooks
  bash install.sh --no-hooks  # install scripts only; skip hooks
  bash install.sh -y          # full silent install
EOF
            exit 0
            ;;
        *) warn "unknown flag: $1"; exit 2 ;;
    esac
    shift
done

# ────────────────────────────────────────────────────────────────────────────
#  Prerequisite checks
# ────────────────────────────────────────────────────────────────────────────
hr
say "Loom installer"
hr

require bash
require python3
require shasum
PYTHON_VERSION="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
PY_MAJOR="$(printf '%s' "$PYTHON_VERSION" | cut -d. -f1)"
PY_MINOR="$(printf '%s' "$PYTHON_VERSION" | cut -d. -f2)"
if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 6 ]; }; then
    fatal "python3 ${PYTHON_VERSION} is too old; need 3.6+"
fi
say "python3: ${PYTHON_VERSION} ✓"

if ! command -v claude >/dev/null 2>&1; then
    warn "claude CLI not found on PATH. Loom will install but won't be usable until Claude Code is installed."
fi

if ! command -v rg >/dev/null 2>&1; then
    # Phase 7a auto-discovers ripgrep inside Claude Code's vendor dir; this is fine.
    say "ripgrep (rg): not on PATH — Phase 7a will use bundled rg from Claude Code if available"
else
    say "ripgrep: $(command -v rg) ✓"
fi

# ────────────────────────────────────────────────────────────────────────────
#  Sanity check: scripts present
# ────────────────────────────────────────────────────────────────────────────
for f in SKILL.md \
         scripts/reflexion.sh scripts/session_checkpoint.sh scripts/critic_gate.sh \
         scripts/web_research.sh scripts/skill_library.sh scripts/sparc_envelope.sh \
         scripts/rag_grep.sh \
         scripts/hooks/session_event.sh scripts/hooks/edit_event.sh; do
    [ -f "${SCRIPT_DIR}/${f}" ] || fatal "package incomplete: missing ${f}"
done
say "package files present ✓"

# ────────────────────────────────────────────────────────────────────────────
#  Install scripts
# ────────────────────────────────────────────────────────────────────────────
hr
say "Installing skill files to: ${DEST_DIR}"
mkdir -p "${DEST_DIR}/scripts/hooks" "${DEST_DIR}/state"
# rsync would be nicer but cp is more portable
cp "${SCRIPT_DIR}/SKILL.md" "${DEST_DIR}/SKILL.md"
cp "${SCRIPT_DIR}/scripts/"*.sh "${DEST_DIR}/scripts/"
cp "${SCRIPT_DIR}/scripts/hooks/"*.sh "${DEST_DIR}/scripts/hooks/"
chmod +x "${DEST_DIR}/scripts/"*.sh "${DEST_DIR}/scripts/hooks/"*.sh
say "skill installed at ${DEST_DIR}"

# ────────────────────────────────────────────────────────────────────────────
#  Hooks decision
# ────────────────────────────────────────────────────────────────────────────
if [ -z "${INSTALL_HOOKS}" ]; then
    if [ "${ASSUME_YES}" = "1" ]; then
        INSTALL_HOOKS="yes"
    else
        hr
        cat <<'EOF'
Phase 11 lifecycle hooks
  Loom can install 4 hooks into ~/.claude/settings.json so it can record
  session/edit events to a local append-only log at:
      ~/.claude/skills/loom/state/{events,edits}.jsonl

  Privacy: hooks store ONLY metadata (file basenames + sha256 hashes +
  byte sizes). File contents, full paths, and edit text are NEVER persisted.

  Without hooks, the skill still works — only Phase 11 (cross-session
  coordination) is degraded.

EOF
        printf 'Install hooks? [Y/n] '
        read -r answer
        case "${answer:-Y}" in
            [Yy]*|"") INSTALL_HOOKS="yes" ;;
            *)        INSTALL_HOOKS="no"  ;;
        esac
    fi
fi

# ────────────────────────────────────────────────────────────────────────────
#  Hooks install (if elected)
# ────────────────────────────────────────────────────────────────────────────
if [ "${INSTALL_HOOKS}" = "yes" ]; then
    hr
    say "Installing hooks block into ${SETTINGS}"
    mkdir -p "$(dirname "${SETTINGS}")"
    if [ ! -f "${SETTINGS}" ]; then
        printf '{}\n' > "${SETTINGS}"
        say "created empty settings.json"
    fi
    # Validate it's parseable JSON before touching
    if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "${SETTINGS}" 2>/dev/null; then
        fatal "${SETTINGS} is not valid JSON; refusing to merge hooks. Fix it first."
    fi
    BACKUP="${SETTINGS}.bak.loom-install-$(date +%Y%m%d-%H%M%S)"
    cp "${SETTINGS}" "${BACKUP}"
    say "backup: ${BACKUP}"

    # Idempotent merge via python.
    python3 - "${SETTINGS}" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    cfg = json.load(f)

hooks = cfg.setdefault("hooks", {})

PRE_POST_MATCHER = "Edit|Write"
LOOM_PREFIX      = "~/.claude/skills/loom/scripts/hooks/"
SESS_CMD_START   = LOOM_PREFIX + "session_event.sh start"
SESS_CMD_STOP    = LOOM_PREFIX + "session_event.sh stop"
EDIT_CMD_PRE     = LOOM_PREFIX + "edit_event.sh pre"
EDIT_CMD_POST    = LOOM_PREFIX + "edit_event.sh post"

def has_loom_command(slot, cmd):
    """True if any hook entry in this lifecycle slot already runs `cmd`."""
    for group in slot or []:
        for h in group.get("hooks", []) or []:
            if h.get("type") == "command" and h.get("command", "").strip() == cmd:
                return True
    return False

def add_hook(slot_name, cmd, matcher=None):
    slot = hooks.setdefault(slot_name, [])
    if has_loom_command(slot, cmd):
        return False
    entry = {"hooks": [{"type": "command", "command": cmd, "timeout": 5}]}
    if matcher is not None:
        entry["matcher"] = matcher
    slot.append(entry)
    return True

added = 0
added += add_hook("SessionStart", SESS_CMD_START)
added += add_hook("Stop",         SESS_CMD_STOP)
added += add_hook("PreToolUse",   EDIT_CMD_PRE,  matcher=PRE_POST_MATCHER)
added += add_hook("PostToolUse",  EDIT_CMD_POST, matcher=PRE_POST_MATCHER)

with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")

print(f"loom-hooks: added {added} new hook(s); existing entries left in place")
PY
    say "hooks installed (re-running this script is safe — duplicates are skipped)"
else
    hr
    say "Skipping hooks (Phase 11 will be degraded)"
    say "To add hooks later: re-run with --hooks"
fi

# ────────────────────────────────────────────────────────────────────────────
#  Verification
# ────────────────────────────────────────────────────────────────────────────
hr
say "Verifying install…"
"${DEST_DIR}/scripts/reflexion.sh" hash "loom install verification" >/dev/null \
    && say "  reflexion.sh ✓" \
    || warn "  reflexion.sh FAILED"
"${DEST_DIR}/scripts/web_research.sh" tier_params pro >/dev/null \
    && say "  web_research.sh ✓" \
    || warn "  web_research.sh FAILED"
"${DEST_DIR}/scripts/sparc_envelope.sh" stages >/dev/null \
    && say "  sparc_envelope.sh ✓" \
    || warn "  sparc_envelope.sh FAILED"
"${DEST_DIR}/scripts/critic_gate.sh" agent_type >/dev/null \
    && say "  critic_gate.sh ✓" \
    || warn "  critic_gate.sh FAILED"
"${DEST_DIR}/scripts/skill_library.sh" list >/dev/null \
    && say "  skill_library.sh ✓" \
    || warn "  skill_library.sh FAILED"
"${DEST_DIR}/scripts/session_checkpoint.sh" list >/dev/null \
    && say "  session_checkpoint.sh ✓" \
    || warn "  session_checkpoint.sh FAILED"

hr
say "Done."
say "Use it with:  /loom <task>  inside Claude Code."
say "Memory & state directory:  ${DEST_DIR}/state/"
if [ "${INSTALL_HOOKS}" = "yes" ]; then
    say "Hooks active. Restart any open Claude Code session to load SessionStart hook."
fi
hr
