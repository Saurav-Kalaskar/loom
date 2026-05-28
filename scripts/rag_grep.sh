#!/usr/bin/env bash
# rag_grep.sh — Phase 7a local code retrieval.
#
# Pure ripgrep + TF-IDF-lite ranking. No vector embeddings, no extra installs.
# Complements web_research.sh: web_research = external knowledge,
# rag_grep = local-codebase grounding for spawned agents.
#
# Usage:
#   rag_grep.sh search <root_dir> <query> [n]   → top-n file:line hits, ranked
#   rag_grep.sh symbols <root_dir> <name>       → likely definitions of symbol
#   rag_grep.sh cite <root_dir> <query> [n]     → search but format as citations
#                                                 (one ##-headed block per hit)

set -euo pipefail

cmd="${1:-}"
shift || true

RG=""
require_rg() {
    # Prefer rg on PATH (works when run from interactive zsh).
    if command -v rg >/dev/null 2>&1; then
        # Sanity-check that it actually behaves like ripgrep — the user has a
        # zsh shell function shimming `rg` through Claude Code, but that shim
        # is zsh-only and won't be in scope under bash. `command -v` returns
        # the path of the underlying binary in that case anyway.
        if rg --version >/dev/null 2>&1; then
            RG="$(command -v rg)"
            return 0
        fi
    fi
    # Fall back to ripgrep vendored inside the Claude Code install (Claude Code
    # ships it for its own Grep tool). Pick the platform-matching binary.
    local arch
    arch="$(uname -m)"
    case "${arch}" in
        arm64) sub="arm64-darwin" ;;
        x86_64) sub="x64-darwin"  ;;
        *) sub="" ;;
    esac
    if [ -n "${sub}" ]; then
        # Search common Claude Code install locations
        local candidates=(
            "${HOME}/.nvm/versions/node/"*/lib/node_modules/@anthropic-ai/claude-code/vendor/ripgrep/${sub}/rg
            "${HOME}/.local/share/claude/versions/"*/vendor/ripgrep/${sub}/rg
        )
        for c in "${candidates[@]}"; do
            if [ -x "${c}" ]; then
                RG="${c}"
                return 0
            fi
        done
    fi
    echo "[error] ripgrep (rg) is required but not found on PATH or in Claude Code vendor dirs" >&2
    echo "[hint]  brew install ripgrep   (or restart inside zsh where rg is shimmed)" >&2
    exit 5
}

# Tokenize + filter: drop tokens shorter than 3 chars, drop common stopwords.
# Keeps identifier-like tokens which is what code search benefits from.
tokenize_query() {
    python3 -c '
import re, sys
STOP = {
    "the","and","for","with","this","that","have","from","but","not","are",
    "you","can","how","why","what","when","where","does","did","was","were",
    "use","using","used","will","would","could","should","into","over","about",
}
text = sys.argv[1].lower()
toks = re.findall(r"[a-z][a-z0-9_]{2,}", text)
toks = [t for t in toks if t not in STOP]
# Dedupe preserving order, cap at 8 tokens (rg perf)
seen = set()
out = []
for t in toks:
    if t not in seen:
        seen.add(t)
        out.append(t)
print(" ".join(out[:8]))
' "$1"
}

case "${cmd}" in
    search|cite)
        root="${1:?root dir required}"
        query="${2:?query required}"
        n="${3:-10}"
        require_rg
        if [ ! -d "${root}" ]; then
            echo "[error] not a directory: ${root}" >&2
            exit 3
        fi
        tokens="$(tokenize_query "${query}")"
        if [ -z "${tokens}" ]; then
            echo "[error] query produced no usable tokens (too short / all stopwords)" >&2
            exit 3
        fi
        # Build alternation: token1|token2|...
        pattern="$(printf '%s' "${tokens}" | tr ' ' '|')"
        # rg with --json gives us reliable parsing. Search common code/text exts only.
        # --max-count caps per-file to avoid swamping ranking.
        # NOTE: paths-only via --files-with-matches first, then re-grep with line nums,
        #       to keep total output bounded.
        files_hit="$("${RG}" --files-with-matches --no-messages --hidden \
            --ignore-case \
            --glob '!.git' --glob '!node_modules' --glob '!dist' --glob '!build' \
            --glob '!.venv' --glob '!__pycache__' --glob '!*.lock' \
            --type-add 'web:*.{html,css,scss}' \
            -t md -t py -t js -t ts -t web -t json -t yaml -t toml -t go -t rust -t java -t cs \
            -e "${pattern}" "${root}" 2>/dev/null | head -200 || true)"
        if [ -z "${files_hit}" ]; then
            echo "[info] no matches in ${root} for tokens: ${tokens}" >&2
            exit 0
        fi
        # For each candidate file, compute a score = unique-token-coverage * 100
        # + total-hit-count, then take top-n. Per-file inner search uses one rg
        # call per token. To prevent runaway on large repos (N tokens × M files
        # rg subprocesses), enforce a global wall-clock budget.
        python3 -c '
import subprocess, sys, time
root, tokens_csv, files_str, n, mode = sys.argv[1:6]
tokens = [t for t in tokens_csv.split(",") if t]
files = [f for f in files_str.split("\n") if f.strip()]
# Hard cap: 80 files. Combined with the head -200 in the file-finding step,
# this gives us at most 8 tokens × 80 files = 640 subprocesses worst case.
files = files[:80]
GLOBAL_BUDGET_SEC = 60
PER_RG_TIMEOUT = 3
deadline = time.monotonic() + GLOBAL_BUDGET_SEC
scored = []
for f in files:
    if time.monotonic() > deadline:
        print("[rag_grep] hit 60s wall-clock budget; truncating rescore", file=sys.stderr)
        break
    coverage = 0
    total = 0
    snippets = []
    for t in tokens:
        if time.monotonic() > deadline:
            break
        # Get up to 2 sample matches per token per file
        try:
            # Case-insensitive substring match. Avoid -w (whole word): camelCase
            # identifiers like "IUsageMetric" tokenize to "iusagemetric" lowercase
            # and -w would prevent it from matching the original mixed-case symbol.
            r = subprocess.run(
                [sys.argv[6], "--no-heading", "--line-number", "--max-count", "2",
                 "--ignore-case", t, f],
                capture_output=True, text=True, timeout=PER_RG_TIMEOUT
            )
        except subprocess.TimeoutExpired:
            continue
        lines = [ln for ln in r.stdout.splitlines() if ln.strip()]
        if lines:
            coverage += 1
            total += len(lines)
            snippets.extend(lines[:1])  # one per token
    score = coverage * 100 + total
    if score > 0:
        scored.append((score, coverage, total, f, snippets))
scored.sort(key=lambda r: -r[0])
n = int(n)
if mode == "cite":
    for score, cov, total, f, snips in scored[:n]:
        print("## " + f)
        print("score: {} (token-coverage={}/{}, total-hits={})".format(score, cov, len(tokens), total))
        for s in snips[:3]:
            # rg output is "path:line:content"
            parts = s.split(":", 2)
            if len(parts) == 3:
                print("  L{}: {}".format(parts[1], parts[2][:160]))
            else:
                print("  " + s[:160])
        print()
else:
    print("rank\tscore\tcoverage\thits\tfile")
    for i, (score, cov, total, f, _) in enumerate(scored[:n], 1):
        print("{}\t{}\t{}/{}\t{}\t{}".format(i, score, cov, len(tokens), total, f))
' "${root}" "${tokens// /,}" "${files_hit}" "${n}" "${cmd}" "${RG}"
        ;;

    symbols)
        root="${1:?root dir required}"
        name="${2:?symbol name required}"
        require_rg
        if [ ! -d "${root}" ]; then
            echo "[error] not a directory: ${root}" >&2
            exit 3
        fi
        # Heuristic: definitions usually have one of these prefixes.
        # ripgrep -e takes a regex; we glue patterns with alternation.
        # NOTE: we use \b for word boundary; verified to work in BSD rg / pcre.
        "${RG}" --no-heading --line-number --hidden \
            --glob '!.git' --glob '!node_modules' --glob '!dist' --glob '!build' \
            -e "(def|class|fn|func|function|interface|type|struct|impl|public[[:space:]]+(class|interface|enum|record)|private[[:space:]]+(class|interface)|export[[:space:]]+(class|interface|function|const)|const|let)[[:space:]]+${name}\b" \
            "${root}" 2>/dev/null | head -50 || echo "[info] no obvious definition of '${name}' found" >&2
        ;;

    *)
        cat >&2 <<EOF
Usage: $0 <subcommand> [args]

Subcommands:
  search <root> <query> [n]    top-n file matches by token coverage
  cite   <root> <query> [n]    same, formatted as ## citation blocks
  symbols <root> <name>        likely definitions of a symbol

Requires: ripgrep (rg) on PATH.
EOF
        exit 2
        ;;
esac
