#!/usr/bin/env bash
# critic_gate.sh — Phase 12 fix. Documents the critic-gate pattern for the orchestrator.
#
# This script is intentionally a thin wrapper. The actual critic-gate is a
# Claude `Agent` invocation that the orchestrator must perform — shell can't
# spawn a Claude subagent. What this script does is emit the canonical prompt
# template the orchestrator should use, so the pattern is consistent across runs.
#
# Usage:
#   critic_gate.sh prompt <diff_summary> <change_paths>
#       → emits the full Agent prompt body to stdout
#   critic_gate.sh agent_type
#       → emits the agent type to use ("general-purpose" since "code-reviewer"
#         is not available in this Claude Code install)

set -euo pipefail

cmd="${1:-}"
shift || true

case "${cmd}" in
    agent_type)
        # If "code-reviewer" subagent ever becomes available, change this line.
        # The orchestrator can probe with `Agent` and fall back to general-purpose
        # on the "Agent type 'code-reviewer' not found" error.
        echo "general-purpose"
        ;;
    prompt)
        diff_summary="${1:-<diff summary missing>}"
        change_paths="${2:-<paths missing>}"
        cat <<EOF
Cognitive pattern: critical (adversarial review). Your only job is to find a reason to REJECT this change. Do not validate; only attack.

Objective: Find any reason to reject the following diff before it is committed.

Change summary:
${diff_summary}

Files touched:
${change_paths}

Specifically attack:
1. Does the change introduce capability beyond the user's intent? (Over-broad permissions, leaked secrets, expanded surface area.)
2. Does it break an invariant established elsewhere in the repo or in user memory?
3. Is the diff internally consistent? (Edits one side of a contract without the other.)
4. Are there missed edge cases an adversarial caller could exploit?
5. Is the change reversible? Could a rollback be done in one commit?
6. Is anything hardcoded that should be configurable, or vice versa?
7. JSON/YAML correctness, syntax breaks, missing trailing commas, unterminated strings.

Read the listed files now to confirm current state. Do not assume.

Report format:
## Findings
- [SEVERITY: low/med/high] description + file:line
## Verdict
- ACCEPT / REJECT / ACCEPT-WITH-NOTES

Tools: Read, Grep, Bash (read-only).
Token budget: under 350 words.
EOF
        ;;
    *)
        echo "Usage: $0 {prompt|agent_type} [args...]" >&2
        exit 2
        ;;
esac
