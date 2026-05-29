#!/usr/bin/env bash
# loom_env.sh — v2.0 environment probes. Decides orchestration mode and verifies
# model reachability so the skill degrades gracefully instead of crashing.
#
# Usage:
#   loom_env.sh workflow_probe        → emit "workflow" or "prose" on stdout
#   loom_env.sh cc_version            → emit detected Claude Code version (or "0")
#   loom_env.sh model_probe [role]    → check model reachability; with no role,
#                                       check all roles; auto-demote critic
#                                       opus→sonnet on failure (prints advisory)
#
# Mode-selection logic (workflow_probe), all must hold for "workflow":
#   1. Claude Code version >= 2.1.154  (Dynamic Workflows GA-preview minimum)
#   2. state/config.json .workflow_ok is not false  (kill-switch; default allow)
#   3. NOT forced to prose via env LOOM_FORCE_PROSE=1
# Any check failing (or undetectable) → "prose" (safe fallback).
#
# model_probe uses AWS Bedrock converse only when CLAUDE_CODE_USE_BEDROCK=1 and
# the aws CLI is present. Otherwise it is a no-op that reports "unverified" — it
# never blocks. It is meant for the install verification step and manual checks,
# NOT for hot-path use.

set -uo pipefail

STATE_DIR="${HOME}/.claude/skills/loom/state"
CONFIG_JSON="${STATE_DIR}/config.json"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIN_VERSION="2.1.154"

# Detect Claude Code version, normalized to "MAJOR.MINOR.PATCH" or "0" if unknown.
detect_cc_version() {
    local raw
    raw="$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    [ -n "${raw}" ] && echo "${raw}" || echo "0"
}

# Return 0 if $1 >= $2 (semver-ish, dotted numeric). Uses sort -V.
version_ge() {
    [ "$1" = "$2" ] && return 0
    local lowest
    lowest="$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)"
    [ "${lowest}" = "$2" ]
}

# Read .workflow_ok from config.json (true|false). Default true when absent.
config_workflow_ok() {
    [ -f "${CONFIG_JSON}" ] || { echo "true"; return 0; }
    python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        cfg = json.load(f)
    v = cfg.get("workflow_ok", True)
    print("false" if v is False else "true")
except Exception:
    print("true")
' "${CONFIG_JSON}"
}

cmd="${1:-}"
shift || true

case "${cmd}" in
    version)
        # Installed Loom version (VERSION file sits one level up from scripts/).
        vf="${HERE}/../VERSION"
        if [ -f "${vf}" ]; then
            head -1 "${vf}" | tr -d '[:space:]'
            echo
        else
            echo "unknown"
        fi
        ;;
    cc_version)
        detect_cc_version
        ;;
    workflow_probe)
        if [ "${LOOM_FORCE_PROSE:-0}" = "1" ]; then echo "prose"; exit 0; fi
        ver="$(detect_cc_version)"
        if [ "${ver}" = "0" ] || ! version_ge "${ver}" "${MIN_VERSION}"; then
            echo "prose"; exit 0
        fi
        if [ "$(config_workflow_ok)" = "false" ]; then echo "prose"; exit 0; fi
        echo "workflow"
        ;;
    model_probe)
        role="${1:-}"
        # Only meaningful on Bedrock with aws CLI; otherwise report unverified.
        if [ "${CLAUDE_CODE_USE_BEDROCK:-0}" != "1" ] || ! command -v aws >/dev/null 2>&1; then
            echo "model_probe: unverified (not Bedrock or aws CLI missing) — assuming reachable" >&2
            exit 0
        fi
        probe_one() {
            local mid="$1"
            AWS_PROFILE="${AWS_PROFILE:-default}" AWS_REGION="${AWS_REGION:-us-east-1}" \
                aws bedrock-runtime converse \
                --model-id "${mid}" \
                --messages '[{"role":"user","content":[{"text":"hi"}]}]' \
                --inference-config '{"maxTokens":1}' \
                --query 'output.message.role' --output text >/dev/null 2>&1
        }
        roles_to_check="${role:-$("${HERE}/loom_config.sh" roles)}"
        rc=0
        for r in ${roles_to_check}; do
            mid="$("${HERE}/loom_config.sh" model "${r}")"
            if probe_one "${mid}"; then
                echo "ok    ${r} → ${mid}"
            else
                echo "FAIL  ${r} → ${mid}" >&2
                rc=1
                if [ "${r}" = "critic" ]; then
                    echo "advisory: critic model unreachable — set LOOM_CRITIC_MODEL=claude-sonnet-4-6 to demote" >&2
                fi
            fi
        done
        exit "${rc}"
        ;;
    *)
        echo "Usage: $0 {version|workflow_probe|cc_version|model_probe [role]}" >&2
        exit 2
        ;;
esac
