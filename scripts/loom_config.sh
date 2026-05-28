#!/usr/bin/env bash
# loom_config.sh — v2.0 per-role model routing. Single source of truth for
# which Claude model each orchestration role uses.
#
# Usage:
#   loom_config.sh model <role>     → emit the model id for a role
#   loom_config.sh emit_json        → emit the full role→model map as JSON
#                                      (the workflow reads this at startup)
#   loom_config.sh roles            → list known roles
#
# Roles and defaults:
#   researcher  → haiku   (cheap web fan-out)
#   retrieve    → haiku   (local rag_grep)
#   learn       → haiku   (reflexion/skill_library/checkpoint writes)
#   synth       → sonnet  (synthesize researcher briefs)
#   sparc       → sonnet  (SPARC build stages — does edits)
#   critic      → opus    (adversarial review — highest reasoning; CONFIGURABLE)
#
# Resolution order for any role (highest wins):
#   1. env var  LOOM_MODEL_<ROLE>   (e.g. LOOM_MODEL_CRITIC, LOOM_CRITIC_MODEL alias)
#   2. state/config.json  ->  .models.<role>
#   3. built-in default below
#
# The script never assumes a provider — it just emits the configured string.
# Keep every model id HERE so a model rename is a one-file change, never
# hardcoded into a workflow .js. On Amazon Bedrock, set the inference-profile
# ids (e.g. us.anthropic.claude-...) in state/config.json instead.

set -euo pipefail

STATE_DIR="${HOME}/.claude/skills/loom/state"
CONFIG_JSON="${STATE_DIR}/config.json"

# Built-in defaults (used when neither env nor config.json overrides).
default_model_for() {
    case "$1" in
        researcher|retrieve|learn) echo "claude-haiku-4-5" ;;
        synth|sparc)               echo "claude-sonnet-4-6" ;;
        critic)                    echo "claude-opus-4-8" ;;
        *)                         echo "" ;;
    esac
}

ROLES="researcher retrieve learn synth sparc critic"

# Read a role's model from state/config.json (.models.<role>), or empty if
# absent / unparseable. Pure python3, no jq dependency.
config_model_for() {
    local role="$1"
    [ -f "${CONFIG_JSON}" ] || { echo ""; return 0; }
    python3 -c '
import json, sys
role, path = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        cfg = json.load(f)
    v = (cfg.get("models", {}) or {}).get(role, "")
    print(v if isinstance(v, str) else "")
except Exception:
    print("")
' "${role}" "${CONFIG_JSON}"
}

# Resolve one role to a model id, honoring env > config.json > default.
resolve_model() {
    local role="$1"
    local upper env_specific env_alias

    # 1. env var LOOM_MODEL_<ROLE> (uppercased role)
    upper="$(printf '%s' "${role}" | tr '[:lower:]' '[:upper:]')"
    eval "env_specific=\${LOOM_MODEL_${upper}:-}"
    if [ -n "${env_specific:-}" ]; then echo "${env_specific}"; return 0; fi

    # 1b. friendly alias for the most-tuned role
    if [ "${role}" = "critic" ] && [ -n "${LOOM_CRITIC_MODEL:-}" ]; then
        echo "${LOOM_CRITIC_MODEL}"; return 0
    fi

    # 2. state/config.json
    local from_cfg
    from_cfg="$(config_model_for "${role}")"
    if [ -n "${from_cfg}" ]; then echo "${from_cfg}"; return 0; fi

    # 3. default
    default_model_for "${role}"
}

cmd="${1:-}"
shift || true

case "${cmd}" in
    model)
        role="${1:?role required (one of: ${ROLES})}"
        out="$(resolve_model "${role}")"
        [ -n "${out}" ] || { echo "[loom_config] unknown role: ${role}" >&2; exit 2; }
        echo "${out}"
        ;;
    emit_json)
        # Emit the resolved role→model map as one JSON object.
        printf '{'
        first=1
        for r in ${ROLES}; do
            m="$(resolve_model "${r}")"
            [ "${first}" = 1 ] || printf ','
            first=0
            # role and model are safe identifiers/ids, but JSON-encode defensively
            python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.argv[1])+":"+json.dumps(sys.argv[2]))' "${r}" "${m}"
        done
        printf '}\n'
        ;;
    roles)
        echo "${ROLES}"
        ;;
    *)
        echo "Usage: $0 {model <role>|emit_json|roles}" >&2
        exit 2
        ;;
esac
