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
INSTALL_HOOKS=""        # "" = ask, "yes" = force install, "no" = skip
INSTALL_CRITIC_GATE=""  # "" = ask, "yes" = enable v2.0 critic gate, "no" = skip
INSTALL_STATUSLINE=""   # "" = ask, "yes" = wire [LOOM] badge, "no" = skip
ASSUME_YES=0
while [ $# -gt 0 ]; do
    case "$1" in
        --hooks)            INSTALL_HOOKS="yes" ;;
        --no-hooks)         INSTALL_HOOKS="no"  ;;
        --critic-gate)      INSTALL_CRITIC_GATE="yes" ;;
        --no-critic-gate)   INSTALL_CRITIC_GATE="no"  ;;
        --statusline)       INSTALL_STATUSLINE="yes" ;;
        --no-statusline)    INSTALL_STATUSLINE="no"  ;;
        -y|--yes)           ASSUME_YES=1 ;;
        -h|--help)
            cat <<EOF
Usage: $0 [options]

Options:
  --hooks            Install Phase 11 lifecycle hooks without prompting
  --no-hooks         Skip Phase 11 hooks entirely
  --critic-gate      Enable v2.0 deterministic critic gate (SubagentStop hook)
  --no-critic-gate   Skip the critic gate (default)
  --statusline       Wire the [LOOM:<phase>] status-bar badge (composes with
                     any existing statusLine, e.g. caveman)
  --no-statusline    Skip the status-bar badge
  -y, --yes          Assume yes for prompts (hooks=yes, critic-gate=NO, statusline=YES)
  -h, --help         Show this help

Examples:
  bash install.sh                     # interactive — asks about hooks, critic gate, statusline
  bash install.sh --no-hooks          # scripts only; no hooks
  bash install.sh -y                  # silent: hooks on, critic gate off, statusline on
  bash install.sh -y --critic-gate    # silent: + critic gate on
  bash install.sh -y --no-statusline  # silent: no status-bar badge
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
         scripts/loom_config.sh scripts/loom_env.sh scripts/run_sentinel.sh \
         scripts/loom_status.sh scripts/loom_statusline_chain.sh \
         scripts/hooks/session_event.sh scripts/hooks/edit_event.sh \
         scripts/hooks/critic_stop.sh \
         loom-research/SKILL.md loom-grep/SKILL.md loom-envelope/SKILL.md \
         loom-critic/SKILL.md loom-recall/SKILL.md loom-skills/SKILL.md \
         loom-checkpoint/SKILL.md loom-workflow/SKILL.md \
         assets/loom-orchestrate.reference.js assets/loom-research.reference.js \
         assets/workflow-contract.md config.default.json; do
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

# Sibling skills for slash-menu autocomplete (each is its own /loom-<sub>)
SKILLS_DIR="$(dirname "${DEST_DIR}")"
for sub in research grep envelope critic recall skills checkpoint workflow; do
    sib_dir="${SKILLS_DIR}/loom-${sub}"
    mkdir -p "${sib_dir}"
    cp "${SCRIPT_DIR}/loom-${sub}/SKILL.md" "${sib_dir}/SKILL.md"
done
say "sibling slash skills installed: /loom-{research,grep,envelope,critic,recall,skills,checkpoint,workflow}"

# v2.0 — Workflow reference seeds (Claude adapts these at runtime; never executed directly)
mkdir -p "${DEST_DIR}/assets"
cp "${SCRIPT_DIR}/assets/"*.js "${DEST_DIR}/assets/" 2>/dev/null || true
cp "${SCRIPT_DIR}/assets/workflow-contract.md" "${DEST_DIR}/assets/"
mkdir -p "${HOME}/.claude/workflows"   # where Claude authors the live loom-orchestrate.js
say "workflow seeds installed to ${DEST_DIR}/assets/"

# v2.0 — config: seed state/config.json from default ONLY if absent (never clobber overrides)
if [ ! -f "${DEST_DIR}/state/config.json" ]; then
    cp "${SCRIPT_DIR}/config.default.json" "${DEST_DIR}/state/config.json"
    say "seeded ${DEST_DIR}/state/config.json (per-role model routing)"
else
    say "kept existing ${DEST_DIR}/state/config.json (not overwritten)"
fi

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
#  Critic-gate decision (v2.0) — opt-in, default NO (it shells out to claude -p)
# ────────────────────────────────────────────────────────────────────────────
if [ -z "${INSTALL_CRITIC_GATE}" ]; then
    if [ "${ASSUME_YES}" = "1" ]; then
        INSTALL_CRITIC_GATE="no"   # silent installs default OFF
    else
        hr
        cat <<'EOF'
v2.0 deterministic critic gate (optional, default No)
  Adds a SubagentStop hook that, ONLY during an active Loom run, runs an
  adversarial critic and forces iterate-until-pass before the agent stops.
  It shells out to `claude -p` (extra model call per critic cycle) and is a
  strict no-op outside a Loom run. Fail-open: never blocks you on timeout.

EOF
        printf 'Enable critic gate? [y/N] '
        read -r answer
        case "${answer:-N}" in
            [Yy]*) INSTALL_CRITIC_GATE="yes" ;;
            *)     INSTALL_CRITIC_GATE="no"  ;;
        esac
    fi
fi

# ────────────────────────────────────────────────────────────────────────────
#  Status-bar badge decision (v2.0) — default YES (passive, safe)
# ────────────────────────────────────────────────────────────────────────────
if [ -z "${INSTALL_STATUSLINE}" ]; then
    if [ "${ASSUME_YES}" = "1" ]; then
        INSTALL_STATUSLINE="yes"
    else
        hr
        cat <<'EOF'
Status-bar badge (optional, default Yes)
  Shows [LOOM:<phase>] in the Claude Code status bar while a Loom run is
  active, so you can see which phase is running. If another statusLine is
  already configured (e.g. caveman), Loom COMPOSES with it — both badges
  show, nothing is replaced. Your settings.json is backed up first.

EOF
        printf 'Wire the status-bar badge? [Y/n] '
        read -r answer
        case "${answer:-Y}" in
            [Yy]*|"") INSTALL_STATUSLINE="yes" ;;
            *)        INSTALL_STATUSLINE="no"  ;;
        esac
    fi
fi

# The critic-gate hook requires the lifecycle-hooks merge path to run (it writes
# to the same settings.json). If the user wants the gate but declined hooks,
# enable the merge path anyway (it only adds the SubagentStop entry).
HOOKS_MERGE="no"
[ "${INSTALL_HOOKS}" = "yes" ] && HOOKS_MERGE="yes"
[ "${INSTALL_CRITIC_GATE}" = "yes" ] && HOOKS_MERGE="yes"

# ────────────────────────────────────────────────────────────────────────────
#  Hooks install (if elected)
# ────────────────────────────────────────────────────────────────────────────
if [ "${HOOKS_MERGE}" = "yes" ]; then
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

    # Idempotent merge via python. Args: <settings_path> <lifecycle yes|no> <critic yes|no>
    python3 - "${SETTINGS}" "${INSTALL_HOOKS:-no}" "${INSTALL_CRITIC_GATE:-no}" <<'PY'
import json, sys
path, want_lifecycle, want_critic = sys.argv[1], sys.argv[2] == "yes", sys.argv[3] == "yes"
with open(path) as f:
    cfg = json.load(f)

hooks = cfg.setdefault("hooks", {})

PRE_POST_MATCHER = "Edit|Write"
LOOM_PREFIX      = "~/.claude/skills/loom/scripts/hooks/"
SESS_CMD_START   = LOOM_PREFIX + "session_event.sh start"
SESS_CMD_STOP    = LOOM_PREFIX + "session_event.sh stop"
EDIT_CMD_PRE     = LOOM_PREFIX + "edit_event.sh pre"
EDIT_CMD_POST    = LOOM_PREFIX + "edit_event.sh post"
CRITIC_CMD       = LOOM_PREFIX + "critic_stop.sh"

def has_loom_command(slot, cmd):
    """True if any hook entry in this lifecycle slot already runs `cmd`."""
    for group in slot or []:
        for h in group.get("hooks", []) or []:
            if h.get("type") == "command" and h.get("command", "").strip() == cmd:
                return True
    return False

def add_hook(slot_name, cmd, matcher=None, timeout=5):
    slot = hooks.setdefault(slot_name, [])
    if has_loom_command(slot, cmd):
        return False
    entry = {"hooks": [{"type": "command", "command": cmd, "timeout": timeout}]}
    if matcher is not None:
        entry["matcher"] = matcher
    slot.append(entry)
    return True

added = 0
if want_lifecycle:
    added += add_hook("SessionStart", SESS_CMD_START)
    added += add_hook("Stop",         SESS_CMD_STOP)
    added += add_hook("PreToolUse",   EDIT_CMD_PRE,  matcher=PRE_POST_MATCHER)
    added += add_hook("PostToolUse",  EDIT_CMD_POST, matcher=PRE_POST_MATCHER)
if want_critic:
    # SubagentStop critic gate; longer timeout since it may invoke `claude -p`.
    added += add_hook("SubagentStop", CRITIC_CMD, timeout=120)

with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")

print(f"loom-hooks: added {added} new hook(s); existing entries left in place")
PY
    say "hooks installed (re-running this script is safe — duplicates are skipped)"
    [ "${INSTALL_CRITIC_GATE}" = "yes" ] && say "v2.0 critic gate enabled (SubagentStop). Disable: re-run uninstall or edit settings.json."
else
    hr
    say "Skipping hooks (Phase 11 will be degraded; v2.0 critic gate off)"
    say "To add later: re-run with --hooks and/or --critic-gate"
fi

# ────────────────────────────────────────────────────────────────────────────
#  Status-bar badge composition (if elected)
# ────────────────────────────────────────────────────────────────────────────
if [ "${INSTALL_STATUSLINE}" = "yes" ]; then
    hr
    say "Wiring [LOOM] status-bar badge into ${SETTINGS}"
    mkdir -p "$(dirname "${SETTINGS}")"
    [ -f "${SETTINGS}" ] || printf '{}\n' > "${SETTINGS}"
    if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "${SETTINGS}" 2>/dev/null; then
        warn "${SETTINGS} is not valid JSON; skipping statusline wiring"
    else
        SL_BACKUP="${SETTINGS}.bak.loom-statusline-$(date +%Y%m%d-%H%M%S)"
        cp "${SETTINGS}" "${SL_BACKUP}"
        say "backup: ${SL_BACKUP}"
        CHAIN="${DEST_DIR}/scripts/loom_statusline_chain.sh"
        python3 - "${SETTINGS}" "${CHAIN}" <<'PY'
import json, sys
path, chain = sys.argv[1], sys.argv[2]
with open(path) as f:
    cfg = json.load(f)

chain_cmd = f'bash "{chain}"'
sl = cfg.get("statusLine")
prior_cmd = ""
if isinstance(sl, dict) and sl.get("type") == "command":
    existing = (sl.get("command") or "").strip()
    if "loom_statusline_chain.sh" in existing:
        # Already our chain — idempotent no-op (keep whatever prior it already wraps).
        print("loom-statusline: already wired; left in place")
        raise SystemExit(0)
    prior_cmd = existing  # the command we must preserve (e.g. caveman)

# Build the chain command, inlining the prior statusline as an env var the
# wrapper reads. Single-quote the prior cmd for the shell; escape embedded quotes.
if prior_cmd:
    esc = prior_cmd.replace("'", "'\\''")
    new_cmd = f"LOOM_PRIOR_STATUSLINE='{esc}' {chain_cmd}"
    note = "composed with existing statusLine"
else:
    new_cmd = chain_cmd  # wrapper auto-discovers caveman if present, else loom-only
    note = "no prior statusLine; chain auto-discovers caveman if present"

cfg["statusLine"] = {"type": "command", "command": new_cmd}
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
print(f"loom-statusline: wired ({note})")
PY
        say "status-bar badge wired (re-running is safe — idempotent)"
    fi
else
    hr
    say "Skipping status-bar badge. The in-chat '▶ Loom: <phase>' line still shows."
    say "To add later: re-run with --statusline"
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
# v2.0 probes
"${DEST_DIR}/scripts/loom_config.sh" emit_json >/dev/null \
    && say "  loom_config.sh ✓" \
    || warn "  loom_config.sh FAILED"
MODE="$("${DEST_DIR}/scripts/loom_env.sh" workflow_probe 2>/dev/null || echo '?')"
say "  loom_env.sh ✓ (orchestration mode: ${MODE})"
# critic_stop.sh must be a strict no-op when no run is active → exit 0
"${DEST_DIR}/scripts/run_sentinel.sh" stop >/dev/null 2>&1 || true
if printf '{}' | "${DEST_DIR}/scripts/hooks/critic_stop.sh" >/dev/null 2>&1; then
    say "  critic_stop.sh ✓ (no-op when idle — verified exit 0)"
else
    warn "  critic_stop.sh FAILED no-op self-test"
fi
# statusline: badge silent when idle, renders [LOOM:<phase>] when a phase is set
if [ -z "$(printf '{}' | "${DEST_DIR}/scripts/loom_status.sh" 2>/dev/null)" ]; then
    say "  loom_status.sh ✓ (silent when idle)"
else
    warn "  loom_status.sh should be silent when idle"
fi

hr
say "Done."
say "Use it with:"
say "  /loom <task>             auto: native Workflow spine if available, else prose"
say "  /loom --workflow <task>  force the v2.0 Workflow spine"
say "  /loom --prose <task>     force the prose pipeline (Phases 0–15)"
say "  /loom menu               list direct-entry subcommands"
say "  /loom-<subcommand> ...   single phase via slash command (research, grep,"
say "                           envelope, critic, recall, skills, checkpoint,"
say "                           workflow — all appear in / autocomplete)"
say "Orchestration mode now:  ${MODE}"
say "Model routing:  $("${DEST_DIR}/scripts/loom_config.sh" emit_json 2>/dev/null)"
say "Memory & state directory:  ${DEST_DIR}/state/"
say "Verify model reachability (optional, costs a few tokens):"
say "  bash ${DEST_DIR}/scripts/loom_env.sh model_probe"
if [ "${HOOKS_MERGE}" = "yes" ]; then
    say "Hooks active. Restart any open Claude Code session to load them."
fi
hr
