#!/usr/bin/env bash
# web_research.sh — Phase 7 deep research replacement.
#
# This script is the bookkeeping layer around a fan-out research pattern.
# Actual web fetching is done by Claude (orchestrator) via the Agent tool
# with WebSearch/WebFetch — this shell script does NOT perform HTTP itself.
#
# Responsibilities:
#   - Hash tasks for stable cache keys
#   - Persist job specs (tier, query, angles, timestamps) under state/research/<hash>/
#   - Emit per-tier parameters (researcher count, rounds, sources, budget, timeout)
#   - Tell the orchestrator where each researcher should write its partial file
#   - Decide whether to auto-skip trivial tasks
#   - Look up cached briefs (24h TTL, tier-monotonic)
#   - Finalize: compute completion %, label timeouts, return brief path
#
# Subcommands:
#   web_research.sh hash <task_text>
#   web_research.sh tier_params <lite|pro|ultra>
#   web_research.sh angles
#   web_research.sh start <hash> <tier> <query>
#   web_research.sh partial_path <hash> <angle>
#   web_research.sh brief_path <hash>
#   web_research.sh cache_lookup <hash> <tier>          (exit 0 = cache hit, prints path)
#   web_research.sh auto_skip <task_text>               (exit 0 = skip, exit 1 = research)
#   web_research.sh finalize <hash>                     (prints brief.md after labeling)
#   web_research.sh status <hash>                       (debug)

set -euo pipefail

STATE_DIR="${HOME}/.claude/skills/loom/state/research"
mkdir -p "${STATE_DIR}"

# Tier parameters. Same shape across tiers; only depth changes.
# Format: researchers|rounds|sources_per_round|word_budget|timeout_sec
tier_params_for() {
    case "$1" in
        lite)  echo "5|1|2|400|180"  ;;
        pro)   echo "5|2|3|600|360"  ;;
        ultra) echo "5|3|4|1000|600" ;;
        *) echo "[error] unknown tier: $1" >&2; exit 2 ;;
    esac
}

# Tier ordering for monotonic cache check. Higher = deeper.
tier_rank() {
    case "$1" in
        lite)  echo 1 ;;
        pro)   echo 2 ;;
        ultra) echo 3 ;;
        *) echo 0 ;;
    esac
}

# The five canonical research angles. Each researcher gets exactly one.
# Slugs are filename-safe.
ANGLES="official_docs community_qa source_issues recent_blogs benchmarks_caseStudies"

cmd="${1:-}"
shift || true

case "${cmd}" in
    hash)
        # Stable hash: lowercase, trim, first 200 chars. Same logic as reflexion.sh.
        printf '%s' "$*" | tr '[:upper:]' '[:lower:]' | head -c 200 | shasum -a 1 | awk '{print $1}'
        ;;

    tier_params)
        tier="${1:?tier required (lite|pro|ultra)}"
        # Pipe-delimited so jq isn't required; parse with cut in shell.
        tier_params_for "${tier}"
        ;;

    angles)
        # Newline-separated list; orchestrator iterates.
        printf '%s\n' ${ANGLES}
        ;;

    start)
        hash="${1:?hash required}"
        tier="${2:?tier required}"
        query="${3:?query required}"
        params="$(tier_params_for "${tier}")"
        researchers="$(echo "${params}" | cut -d'|' -f1)"
        rounds="$(echo "${params}"      | cut -d'|' -f2)"
        sources="$(echo "${params}"     | cut -d'|' -f3)"
        budget="$(echo "${params}"      | cut -d'|' -f4)"
        timeout="$(echo "${params}"     | cut -d'|' -f5)"
        ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        ts_epoch="$(date -u +%s)"
        job_dir="${STATE_DIR}/${hash}"
        mkdir -p "${job_dir}"
        # Clear all stale state from any prior run at this hash so the new tier
        # gets a clean directory. Same hash = same task text, so an in-flight retry
        # of the same question should not see partials/briefs from the aborted run.
        rm -f "${job_dir}"/researcher_*.partial.md \
              "${job_dir}"/researcher_*.partial.tmp \
              "${job_dir}/brief.md" \
              "${job_dir}/job.json" 2>/dev/null || true
        python3 -c '
import json, sys
print(json.dumps({
    "hash":        sys.argv[1],
    "tier":        sys.argv[2],
    "query":       sys.argv[3],
    "started_at":  sys.argv[4],
    "started_epoch": int(sys.argv[5]),
    "researchers": int(sys.argv[6]),
    "rounds":      int(sys.argv[7]),
    "sources_per_round": int(sys.argv[8]),
    "word_budget": int(sys.argv[9]),
    "timeout_sec": int(sys.argv[10]),
    "angles":      sys.argv[11].split(),
}, indent=2))
' "${hash}" "${tier}" "${query}" "${ts}" "${ts_epoch}" \
  "${researchers}" "${rounds}" "${sources}" "${budget}" "${timeout}" "${ANGLES}" \
  > "${job_dir}/job.json"
        echo "${ts_epoch}"
        ;;

    partial_path)
        hash="${1:?hash required}"
        angle="${2:?angle required}"
        # Validate angle is in the canonical list
        if ! printf '%s\n' ${ANGLES} | grep -qx "${angle}"; then
            echo "[error] unknown angle: ${angle}" >&2
            echo "[error] valid: ${ANGLES}" >&2
            exit 3
        fi
        echo "${STATE_DIR}/${hash}/researcher_${angle}.partial.md"
        ;;

    brief_path)
        hash="${1:?hash required}"
        echo "${STATE_DIR}/${hash}/brief.md"
        ;;

    cache_lookup)
        hash="${1:?hash required}"
        requested_tier="${2:?tier required}"
        brief="${STATE_DIR}/${hash}/brief.md"
        job="${STATE_DIR}/${hash}/job.json"
        if [ ! -f "${brief}" ] || [ ! -f "${job}" ]; then
            exit 1
        fi
        # 24h TTL using brief mtime (portable: stat -f on macOS, stat -c on Linux)
        if stat -f %m "${brief}" >/dev/null 2>&1; then
            mtime=$(stat -f %m "${brief}")
        else
            mtime=$(stat -c %Y "${brief}")
        fi
        now="$(date -u +%s)"
        age=$(( now - mtime ))
        if [ "${age}" -gt 86400 ]; then
            exit 1
        fi
        # Tier monotonic: cached tier must be >= requested
        cached_tier="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("tier",""))' "${job}")"
        if [ "$(tier_rank "${cached_tier}")" -lt "$(tier_rank "${requested_tier}")" ]; then
            exit 1
        fi
        echo "${brief}"
        ;;

    auto_skip)
        # Exit 0 → skip Phase 7. Exit 1 → run research.
        # Conservative rule: skip only when the task is short AND BEGINS with a
        # trivial-action verb. This avoids false positives where "rename" appears
        # mid-sentence in an architectural task. Bias is toward researching;
        # the user can always select Lite tier (3min) if they wanted speed.
        task="$*"
        # Force-research escape hatch
        if printf '%s' "${task}" | grep -qE -- '--research\b'; then
            exit 1
        fi
        # Word count
        word_count="$(printf '%s' "${task}" | wc -w | awk '{print $1}')"
        if [ "${word_count}" -ge 15 ]; then
            exit 1
        fi
        # Match only if a trivial keyword is in the first 3 words. This catches
        # "rename foo to bar" but NOT "design auth system that requires rename of...".
        first_three="$(printf '%s' "${task}" | awk '{print tolower($1), tolower($2), tolower($3)}')"
        if printf '%s' "${first_three}" | grep -qE '\b(rename|typo|reformat|format)\b'; then
            exit 0
        fi
        # Two-word patterns explicitly anchored to start
        if printf '%s' "${task}" | grep -qiE '^[[:space:]]*(fix indent|add log|add comment|remove import|delete unused|format code)\b'; then
            exit 0
        fi
        exit 1
        ;;

    finalize)
        hash="${1:?hash required}"
        job_dir="${STATE_DIR}/${hash}"
        job="${job_dir}/job.json"
        brief="${job_dir}/brief.md"
        if [ ! -f "${job}" ]; then
            echo "[error] no job for hash ${hash}" >&2
            exit 4
        fi
        # Count completed researchers (only .partial.md, ignore .tmp)
        total="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["angles"]))' "${job}")"
        completed=0
        for angle in ${ANGLES}; do
            if [ -f "${job_dir}/researcher_${angle}.partial.md" ]; then
                completed=$(( completed + 1 ))
            fi
        done
        # Check elapsed vs timeout
        started_epoch="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["started_epoch"])' "${job}")"
        timeout_sec="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["timeout_sec"])' "${job}")"
        now="$(date -u +%s)"
        elapsed=$(( now - started_epoch ))
        is_timeout=0
        if [ "${elapsed}" -gt "${timeout_sec}" ] && [ "${completed}" -lt "${total}" ]; then
            is_timeout=1
        fi
        # If brief.md doesn't exist yet, the orchestrator hasn't run the synthesizer.
        # finalize is then a status check; emit progress info on stderr and exit 5
        # so orchestrator knows to dispatch synthesizer Agent.
        if [ ! -f "${brief}" ]; then
            echo "[finalize] ${completed}/${total} researchers complete, elapsed=${elapsed}s, timeout=${timeout_sec}s, is_timeout=${is_timeout}" >&2
            exit 5
        fi
        # Brief exists. Prepend timeout banner if needed (idempotent).
        if [ "${is_timeout}" = "1" ] && ! head -1 "${brief}" | grep -q '^> \[TIMEOUT'; then
            tier="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tier"])' "${job}")"
            tmp="${brief}.banner.tmp"
            {
                printf '> [TIMEOUT — %d of %d researchers completed within %s budget. Brief is partial; weight downstream conclusions accordingly.]\n\n' \
                    "${completed}" "${total}" "${tier}"
                cat "${brief}"
            } > "${tmp}"
            mv "${tmp}" "${brief}"
        fi
        echo "${brief}"
        ;;

    status)
        hash="${1:?hash required}"
        job_dir="${STATE_DIR}/${hash}"
        job="${job_dir}/job.json"
        if [ ! -f "${job}" ]; then
            echo "no job for ${hash}" >&2
            exit 4
        fi
        echo "=== job ==="
        cat "${job}"
        echo
        echo "=== partials ==="
        ls -la "${job_dir}"/researcher_*.partial.md 2>/dev/null || echo "  (none)"
        echo "=== brief ==="
        if [ -f "${job_dir}/brief.md" ]; then
            wc -l "${job_dir}/brief.md"
        else
            echo "  (not yet synthesized)"
        fi
        ;;

    *)
        cat >&2 <<EOF
Usage: $0 <subcommand> [args]

Subcommands:
  hash <task>                 emit sha1 of normalized task text
  tier_params <tier>          emit "researchers|rounds|sources|budget|timeout"
  angles                      list the 5 research angles, one per line
  start <hash> <tier> <query> create job dir, write job.json, return start epoch
  partial_path <hash> <angle> emit canonical partial output path
  brief_path <hash>           emit canonical brief.md path
  cache_lookup <hash> <tier>  exit 0 + print brief if cache hit, exit 1 if miss
  auto_skip <task>            exit 0 if trivial (skip Phase 7), exit 1 otherwise
  finalize <hash>             emit brief path; exit 5 if synthesizer not yet run
  status <hash>               debug: dump job + partials + brief state
EOF
        exit 2
        ;;
esac
