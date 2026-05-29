#!/usr/bin/env bash
# update.sh — pull the latest Loom and reinstall, preserving your install choices.
#
# Run this from your cloned repo directory:
#   cd <your loom clone>
#   bash update.sh
#
# It will:
#   1. git pull the latest from your remote (origin)
#   2. read your saved install preferences (hooks / critic-gate / statusline)
#   3. re-run install.sh with exactly those flags (no re-prompting)
#   4. report the version change (old → new)
#
# If this directory is not a git clone, it prints how to re-clone.
# install.sh is idempotent, so re-running is always safe; your state/ (reflexion
# lessons, skills, checkpoints) is preserved.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DEST_DIR="${HOME}/.claude/skills/loom"

say()   { printf '\033[36m[loom]\033[0m %s\n' "$*"; }
warn()  { printf '\033[33m[loom]\033[0m %s\n' "$*" >&2; }
fatal() { printf '\033[31m[loom]\033[0m %s\n' "$*" >&2; exit 1; }
hr()    { printf '%s\n' "────────────────────────────────────────────────────────"; }

ASSUME_YES=0
[ "${1:-}" = "-y" ] || [ "${1:-}" = "--yes" ] && ASSUME_YES=1

hr; say "Loom updater"; hr

# ── Must be run from the git clone (where install.sh + .git live). ──
cd "${SCRIPT_DIR}"
if [ ! -d "${SCRIPT_DIR}/.git" ] || [ ! -f "${SCRIPT_DIR}/install.sh" ]; then
    warn "This directory is not a Loom git clone."
    warn "Re-clone and reinstall instead:"
    warn "  git clone <your loom repo url> loom && cd loom && bash install.sh"
    exit 1
fi

# ── Record the currently-installed version (if any). ──
OLD_VERSION="not-installed"
[ -f "${DEST_DIR}/VERSION" ] && OLD_VERSION="$(head -1 "${DEST_DIR}/VERSION" | tr -d '[:space:]')"

# ── Pull latest. ──
say "Pulling latest from origin…"
BEFORE_SHA="$(git rev-parse HEAD 2>/dev/null || echo none)"
if ! git pull --ff-only origin "$(git rev-parse --abbrev-ref HEAD)" 2>&1 | sed 's/^/  /'; then
    warn "git pull failed (local changes or network?). Resolve, then re-run."
    warn "If you have local edits you don't need: git stash && bash update.sh"
    exit 1
fi
AFTER_SHA="$(git rev-parse HEAD 2>/dev/null || echo none)"

NEW_VERSION="unknown"
[ -f "${SCRIPT_DIR}/VERSION" ] && NEW_VERSION="$(head -1 "${SCRIPT_DIR}/VERSION" | tr -d '[:space:]')"

if [ "${BEFORE_SHA}" = "${AFTER_SHA}" ] && [ "${OLD_VERSION}" = "${NEW_VERSION}" ]; then
    say "Already up to date (v${NEW_VERSION}). Reinstalling anyway to be safe."
fi

# ── Replay saved install preferences (default to safe values if absent). ──
PREFS="${DEST_DIR}/state/install_prefs"
PREF_HOOKS="yes"; PREF_CRITIC="no"; PREF_STATUS="yes"   # defaults match install.sh -y
if [ -f "${PREFS}" ]; then
    # shellcheck disable=SC1090
    . "${PREFS}" 2>/dev/null || true
    PREF_HOOKS="${LOOM_PREF_HOOKS:-${PREF_HOOKS}}"
    PREF_CRITIC="${LOOM_PREF_CRITIC_GATE:-${PREF_CRITIC}}"
    PREF_STATUS="${LOOM_PREF_STATUSLINE:-${PREF_STATUS}}"
    say "Using saved preferences: hooks=${PREF_HOOKS} critic-gate=${PREF_CRITIC} statusline=${PREF_STATUS}"
else
    say "No saved preferences found; using defaults: hooks=${PREF_HOOKS} critic-gate=${PREF_CRITIC} statusline=${PREF_STATUS}"
fi

# Map preferences → explicit install.sh flags (so nothing re-prompts and no
# default silently flips a setting the user had customized).
FLAGS=(-y)
[ "${PREF_HOOKS}" = "yes" ]  && FLAGS+=(--hooks)        || FLAGS+=(--no-hooks)
[ "${PREF_CRITIC}" = "yes" ] && FLAGS+=(--critic-gate)  || FLAGS+=(--no-critic-gate)
[ "${PREF_STATUS}" = "yes" ] && FLAGS+=(--statusline)   || FLAGS+=(--no-statusline)

# ── Reinstall. ──
hr
say "Reinstalling with: install.sh ${FLAGS[*]}"
bash "${SCRIPT_DIR}/install.sh" "${FLAGS[@]}"

hr
say "Update complete: v${OLD_VERSION} → v${NEW_VERSION}"
say "Restart any open Claude Code session to load changes."
hr
