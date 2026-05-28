#!/usr/bin/env bash
# critic_stop.sh — v2.0 deterministic critic gate (SubagentStop / Stop hook).
#
# Fires on every SubagentStop (and optionally Stop) GLOBALLY, but is a STRICT
# NO-OP unless a Loom run is active for the current working directory. This is
# the safety contract: outside an explicit Loom run, the hook exits 0 instantly
# and changes nothing for any other Claude Code session on the machine.
#
# When a Loom run IS active (run_sentinel.sh armed for this cwd):
#   1. Read the live diff transiently (never persisted).
#   2. Run the critic via a one-shot `claude -p` with the configured critic model.
#   3. On REJECT (and retries remain): exit 2 with the critique on stderr — the
#      documented path that feeds stderr back to Claude as the error to fix,
#      preventing the stop and forcing another iteration.
#   4. On ACCEPT, on max-retries, on timeout, or on ANY error: exit 0 (fail-open).
#      The gate NEVER hard-blocks the user.
#
# Opt-in: this hook is installed by install.sh only if the user explicitly
# enables the critic gate (default No), because it shells out to `claude -p`.
#
# Privacy: stores nothing. Reads the diff into memory, passes it to the critic,
# discards it. The sentinel holds only {run_id, cwd_hash, started_epoch, retries}.

set -uo pipefail

STATE_DIR="${HOME}/.claude/skills/loom/state"
RUN_DIR="${STATE_DIR}/run"
SENTINEL="${RUN_DIR}/active.json"
RETRIES="${RUN_DIR}/critic_retries"
LOOM="${HOME}/.claude/skills/loom/scripts"
CONFIG_JSON="${STATE_DIR}/config.json"

# Consume hook stdin (we don't need it, but drain it so the harness doesn't block).
_unused_event="$(head -c 65536 2>/dev/null || true)"

# ── Gate 1: sentinel must exist AND match this cwd. Otherwise instant no-op. ──
if ! bash "${LOOM}/run_sentinel.sh" active 2>/dev/null; then
    exit 0
fi

# ── Read config knobs (fail-open defaults). ──
read_cfg_num() {  # key default
    local key="$1" def="$2"
    [ -f "${CONFIG_JSON}" ] || { echo "${def}"; return 0; }
    python3 -c '
import json,sys
try:
    v=json.load(open(sys.argv[2])).get(sys.argv[1], sys.argv[3])
    print(int(v))
except Exception:
    print(sys.argv[3])
' "${key}" "${CONFIG_JSON}" "${def}" 2>/dev/null || echo "${def}"
}
MAX_RETRIES="${LOOM_MAX_CRITIC_RETRIES:-$(read_cfg_num max_critic_retries 3)}"
TIMEOUT_SEC="${LOOM_CRITIC_TIMEOUT_SEC:-$(read_cfg_num critic_timeout_sec 90)}"

# ── Gate 2: retry budget. At max, fail-open + record an escalation lesson. ──
cur_retries="$(cat "${RETRIES}" 2>/dev/null || echo 0)"
case "${cur_retries}" in ''|*[!0-9]*) cur_retries=0 ;; esac
if [ "${cur_retries}" -ge "${MAX_RETRIES}" ]; then
    echo "[critic_stop] max retries (${MAX_RETRIES}) reached — escalating to human, releasing stop" >&2
    bash "${LOOM}/reflexion.sh" write \
        "$(bash "${LOOM}/run_sentinel.sh" status 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("run_id","unknown"))' 2>/dev/null || echo unknown)" \
        "${cur_retries}" fail "critic_max_retries" \
        "Critic gate hit max retries; released to human review." 2>/dev/null || true
    exit 0
fi

# ── Only gate when there is an actual diff to review. ──
diff_summary="$(git diff --stat 2>/dev/null | tail -40 || true)"
change_paths="$(git diff --name-only 2>/dev/null || true)"
if [ -z "${diff_summary}" ]; then
    # Nothing changed → nothing to reject.
    exit 0
fi

# ── Need claude + critic_gate to run the gate; if missing, fail-open. ──
command -v claude >/dev/null 2>&1 || exit 0
critic_model="$(bash "${LOOM}/loom_config.sh" model critic 2>/dev/null || echo "")"
critic_prompt="$(bash "${LOOM}/critic_gate.sh" prompt "${diff_summary}" "${change_paths}" 2>/dev/null || echo "")"
[ -n "${critic_prompt}" ] || exit 0

# ── Run the critic, bounded by timeout. Fail-open on timeout/error. ──
# Portable timeout: GNU `timeout`, Homebrew `gtimeout`, or a perl-alarm fallback
# (macOS ships perl but not timeout). Guarantees the hook can never hang.
model_flag=()
[ -n "${critic_model}" ] && model_flag=(--model "${critic_model}")

run_with_timeout() {  # secs -- cmd...
    local secs="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "${secs}" "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "${secs}" "$@"
    elif command -v perl >/dev/null 2>&1; then
        perl -e 'alarm shift; exec @ARGV' "${secs}" "$@"
    else
        "$@"   # last resort: no timeout available
    fi
}

verdict_out="$(printf '%s\n' "${critic_prompt}" | run_with_timeout "${TIMEOUT_SEC}" claude -p "${model_flag[@]}" 2>/dev/null || true)"

# Empty output (timeout/error) → fail-open.
[ -n "${verdict_out}" ] || { echo "[critic_stop] no critic output (timeout/error) — releasing stop" >&2; exit 0; }

# ── Parse the verdict block (text contract). REJECT anywhere in the last
#    "## Verdict" block → reject. ──
verdict_block="$(printf '%s\n' "${verdict_out}" | awk 'BEGIN{IGNORECASE=1} /## *Verdict/{f=1} f{print}')"
[ -n "${verdict_block}" ] || verdict_block="${verdict_out}"   # fall back to whole output

if printf '%s' "${verdict_block}" | grep -qiE 'REJECT'; then
    # Bump retry counter, then exit 2 with critique on stderr (fed back to Claude).
    printf '%s' "$((cur_retries + 1))" > "${RETRIES}" 2>/dev/null || true
    {
        echo "LOOM CRITIC GATE — REJECT (attempt $((cur_retries + 1))/${MAX_RETRIES}). Address these before stopping:"
        printf '%s\n' "${verdict_out}"
    } >&2
    exit 2
fi

# ACCEPT / ACCEPT-WITH-NOTES → release the stop, reset retries.
printf '0' > "${RETRIES}" 2>/dev/null || true
exit 0
