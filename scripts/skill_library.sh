#!/usr/bin/env bash
# skill_library.sh — Phase 9b. Voyager-style reusable skill recipes.
#
# Persists named code/prompt artifacts to ~/.claude/skills/loom/state/skills/<slug>/.
# Retrieval is keyword-based with TF-IDF-like ranking (no embeddings, no extra
# installs). Promote on N=3 successes; retire on failure ratio > 0.4.
#
# Usage:
#   skill_library.sh save <slug> <description> <code_path>
#   skill_library.sh find <query> [n]            → top-n by keyword overlap
#   skill_library.sh get <slug>                  → emit skill.json + code path
#   skill_library.sh list [--active|--retired]   → list with success/failure counts
#   skill_library.sh record <slug> <pass|fail>   → bump counter, auto-promote/retire
#   skill_library.sh promote <slug>              → manually mark active
#   skill_library.sh retire <slug>               → manually mark retired

set -euo pipefail

STATE_DIR="${HOME}/.claude/skills/loom/state/skills"
mkdir -p "${STATE_DIR}"

# Promotion / retirement thresholds
PROMOTE_AT=3              # successes to auto-promote a 'pending' skill to 'active'
RETIRE_RATIO_BPS=4000     # failure ratio threshold in basis points (4000 = 0.4)

cmd="${1:-}"
shift || true

slugify() {
    # Lowercase, replace non-alphanumeric with -, squeeze, trim leading/trailing -
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | head -c 60
}

case "${cmd}" in
    save)
        slug_in="${1:?slug required}"
        description="${2:?description required}"
        code_path="${3:?code path required}"
        slug="$(slugify "${slug_in}")"
        if [ -z "${slug}" ]; then
            echo "[error] slug normalized to empty string" >&2
            exit 3
        fi
        if [ ! -f "${code_path}" ]; then
            echo "[error] code path not found: ${code_path}" >&2
            exit 3
        fi
        skill_dir="${STATE_DIR}/${slug}"
        mkdir -p "${skill_dir}"
        # Preserve original extension if present
        ext="${code_path##*.}"
        if [ "${ext}" = "${code_path}" ]; then ext="txt"; fi
        cp "${code_path}" "${skill_dir}/code.${ext}"
        ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        # Build skill.json
        python3 -c '
import json, sys
slug, desc, ts, ext = sys.argv[1:5]
existing = {}
import os
meta_path = sys.argv[5]
if os.path.exists(meta_path):
    try:
        existing = json.load(open(meta_path))
    except json.JSONDecodeError:
        existing = {}
out = {
    "slug":        slug,
    "description": desc,
    "code_file":   f"code.{ext}",
    "created_at":  existing.get("created_at", ts),
    "updated_at":  ts,
    "status":      existing.get("status", "pending"),
    "success_count": existing.get("success_count", 0),
    "failure_count": existing.get("failure_count", 0),
}
print(json.dumps(out, indent=2))
' "${slug}" "${description}" "${ts}" "${ext}" "${skill_dir}/skill.json" \
  > "${skill_dir}/skill.json.tmp"
        mv "${skill_dir}/skill.json.tmp" "${skill_dir}/skill.json"
        echo "${slug}"
        ;;

    find)
        query="${1:?query required}"
        n="${2:-5}"
        # Tokenize query once. TF-IDF-lite: rank candidates by count of unique
        # query tokens that appear in (description + slug). Tie-break by
        # success ratio.
        python3 -c '
import json, os, re, sys
state_dir, query, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
def toks(s):
    return set(re.findall(r"[a-z0-9]+", s.lower()))
qtoks = toks(query)
if not qtoks:
    sys.exit(0)
results = []
if not os.path.isdir(state_dir):
    sys.exit(0)
for slug in os.listdir(state_dir):
    meta_path = os.path.join(state_dir, slug, "skill.json")
    if not os.path.isfile(meta_path):
        continue
    try:
        meta = json.load(open(meta_path))
    except json.JSONDecodeError:
        continue
    if meta.get("status") == "retired":
        continue
    haystack = toks(meta.get("description", "") + " " + meta.get("slug", ""))
    overlap = len(qtoks & haystack)
    if overlap == 0:
        continue
    s = meta.get("success_count", 0)
    f = meta.get("failure_count", 0)
    success_ratio = s / max(s + f, 1)
    results.append((overlap, success_ratio, meta))
# Sort: most overlap first, then highest success ratio
results.sort(key=lambda r: (-r[0], -r[1]))
for overlap, ratio, meta in results[:n]:
    s    = meta.get("slug", "")
    st   = meta.get("status", "")
    desc = meta.get("description", "")[:80]
    print(f"{s}\t{overlap}\t{ratio:.2f}\t{st}\t{desc}")
' "${STATE_DIR}" "${query}" "${n}"
        ;;

    get)
        slug_in="${1:?slug required}"
        slug="$(slugify "${slug_in}")"
        skill_dir="${STATE_DIR}/${slug}"
        if [ ! -f "${skill_dir}/skill.json" ]; then
            echo "[error] no skill: ${slug}" >&2
            exit 4
        fi
        echo "=== skill.json ==="
        cat "${skill_dir}/skill.json"
        echo
        echo "=== code path ==="
        # Recover code file via the code_file field
        code_file="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("code_file",""))' "${skill_dir}/skill.json")"
        echo "${skill_dir}/${code_file}"
        ;;

    list)
        filter="${1:-}"
        python3 -c '
import json, os, sys
state_dir, filt = sys.argv[1], sys.argv[2]
if not os.path.isdir(state_dir):
    sys.exit(0)
rows = []
for slug in sorted(os.listdir(state_dir)):
    meta_path = os.path.join(state_dir, slug, "skill.json")
    if not os.path.isfile(meta_path):
        continue
    try:
        meta = json.load(open(meta_path))
    except json.JSONDecodeError:
        continue
    status = meta.get("status", "pending")
    if filt == "--active" and status != "active":   continue
    if filt == "--retired" and status != "retired": continue
    rows.append((slug, status, meta.get("success_count",0), meta.get("failure_count",0), meta.get("description","")[:60]))
header = "{:<30} {:<10} {:>4} {:>4}  description".format("slug", "status", "pass", "fail")
print(header)
print("-" * 90)
for r in rows:
    print("{:<30} {:<10} {:>4} {:>4}  {}".format(r[0], r[1], r[2], r[3], r[4]))
' "${STATE_DIR}" "${filter}"
        ;;

    record)
        slug_in="${1:?slug required}"
        outcome="${2:?outcome required (pass|fail)}"
        slug="$(slugify "${slug_in}")"
        meta_path="${STATE_DIR}/${slug}/skill.json"
        if [ ! -f "${meta_path}" ]; then
            echo "[error] no skill: ${slug}" >&2
            exit 4
        fi
        if [ "${outcome}" != "pass" ] && [ "${outcome}" != "fail" ]; then
            echo "[error] outcome must be pass|fail" >&2
            exit 3
        fi
        ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        python3 -c '
import json, sys
meta_path, outcome, ts, promote_at, retire_bps = sys.argv[1:6]
promote_at = int(promote_at)
retire_bps = int(retire_bps)
meta = json.load(open(meta_path))
if outcome == "pass":
    meta["success_count"] = meta.get("success_count", 0) + 1
else:
    meta["failure_count"] = meta.get("failure_count", 0) + 1
meta["updated_at"] = ts
s = meta.get("success_count", 0)
f = meta.get("failure_count", 0)
total = s + f
# Auto-promote: pending → active after PROMOTE_AT successes
if meta.get("status") == "pending" and s >= promote_at:
    meta["status"] = "active"
# Auto-retire: failure ratio > threshold and we have enough samples
if total >= 5 and (f * 10000) // max(total, 1) > retire_bps:
    meta["status"] = "retired"
print(json.dumps(meta, indent=2))
' "${meta_path}" "${outcome}" "${ts}" "${PROMOTE_AT}" "${RETIRE_RATIO_BPS}" \
  > "${meta_path}.tmp"
        mv "${meta_path}.tmp" "${meta_path}"
        # Emit final status for caller
        python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))
print("{}\t{}\tpass={}\tfail={}".format(m["slug"], m["status"], m["success_count"], m["failure_count"]))
' "${meta_path}"
        ;;

    promote)
        slug_in="${1:?slug required}"
        slug="$(slugify "${slug_in}")"
        meta_path="${STATE_DIR}/${slug}/skill.json"
        [ -f "${meta_path}" ] || { echo "[error] no skill: ${slug}" >&2; exit 4; }
        python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); m["status"]="active"; print(json.dumps(m,indent=2))' "${meta_path}" > "${meta_path}.tmp"
        mv "${meta_path}.tmp" "${meta_path}"
        echo "${slug} → active"
        ;;

    retire)
        slug_in="${1:?slug required}"
        slug="$(slugify "${slug_in}")"
        meta_path="${STATE_DIR}/${slug}/skill.json"
        [ -f "${meta_path}" ] || { echo "[error] no skill: ${slug}" >&2; exit 4; }
        python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); m["status"]="retired"; print(json.dumps(m,indent=2))' "${meta_path}" > "${meta_path}.tmp"
        mv "${meta_path}.tmp" "${meta_path}"
        echo "${slug} → retired"
        ;;

    *)
        cat >&2 <<EOF
Usage: $0 <subcommand> [args]

Subcommands:
  save <slug> <description> <code_path>   persist a reusable artifact
  find <query> [n]                         top-n active skills by keyword overlap
  get <slug>                               emit skill.json and code path
  list [--active|--retired]                tabular listing
  record <slug> <pass|fail>                bump counter; auto-promote/retire
  promote <slug>                           force status=active
  retire <slug>                            force status=retired

Auto-promote: pending → active after ${PROMOTE_AT} successes.
Auto-retire:  failure ratio > $((RETIRE_RATIO_BPS / 100))% (with >=5 samples).
EOF
        exit 2
        ;;
esac
