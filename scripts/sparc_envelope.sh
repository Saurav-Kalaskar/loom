#!/usr/bin/env bash
# sparc_envelope.sh — Phase 6 SPARC prompt envelope generator.
#
# Emits canonical Agent prompt bodies for each SPARC stage so the orchestrator
# can fan out the 5-stage cycle without hand-rolling the prompts each time.
# Each stage has a fixed cognitive pattern and tool allowlist.
#
# Usage:
#   sparc_envelope.sh stages                       → list the 5 stage slugs
#   sparc_envelope.sh envelope <stage> <task>      → emit prompt body to stdout
#   sparc_envelope.sh pattern <stage>              → emit cognitive pattern only
#   sparc_envelope.sh tools <stage>                → emit allowed tools (CSV)

set -euo pipefail

cmd="${1:-}"
shift || true

stages_list() {
    cat <<'EOF'
specification
pseudocode
architecture
refinement
completion
EOF
}

# Per-stage attributes
pattern_for() {
    case "$1" in
        specification) echo "abstract"   ;;
        pseudocode)    echo "systems"    ;;
        architecture)  echo "divergent"  ;;
        refinement)    echo "critical"   ;;
        completion)    echo "convergent" ;;
        *) echo "[error] unknown stage: $1" >&2; exit 2 ;;
    esac
}

tools_for() {
    # Bash is intentionally restricted to test/build runners. Refinement and
    # completion agents must NOT have unbounded shell access — that would let
    # them run rm -rf, git push, or hit external infra. The orchestrator spawns
    # these and is responsible for any broader Bash usage.
    case "$1" in
        specification) echo "Read,Grep,Glob,WebSearch,WebFetch" ;;
        pseudocode)    echo "Read,Grep,Glob"                    ;;
        architecture)  echo "Read,Grep,Glob,WebSearch,WebFetch" ;;
        refinement)    echo "Read,Grep,Edit,Write,Bash(pytest *),Bash(npm test *),Bash(npm run test*),Bash(go test *),Bash(dotnet test *),Bash(cargo test *),Bash(jest *),Bash(mocha *)" ;;
        completion)    echo "Read,Grep,Edit,Write,Bash(pytest *),Bash(npm test *),Bash(npm run test*),Bash(go test *),Bash(dotnet test *),Bash(cargo test *),Bash(jest *),Bash(mocha *)" ;;
        *) echo "[error] unknown stage: $1" >&2; exit 2 ;;
    esac
}

objective_for() {
    case "$1" in
        specification) echo "Produce a falsifiable, written specification of WHAT must be built and WHAT must not be built. No implementation." ;;
        pseudocode)    echo "Produce language-agnostic pseudocode showing the algorithmic shape of the solution. No syntax-specific code." ;;
        architecture)  echo "Produce 2-3 candidate architectures with trade-offs (cost, complexity, blast radius). Recommend one." ;;
        refinement)    echo "Adversarial test design (TDD red): given the architecture, find inputs and edge cases that should break it. Write failing tests for each. Then implement just enough code to make every test pass. Cognitive pattern is critical because the *test design* is adversarial — pretend you're the auditor trying to reject this implementation." ;;
        completion)    echo "Implement the chosen architecture against the green tests. Code must compile and pass all tests on first run." ;;
        *) echo "[error] unknown stage: $1" >&2; exit 2 ;;
    esac
}

case "${cmd}" in
    stages)
        stages_list
        ;;

    pattern)
        stage="${1:?stage required}"
        pattern_for "${stage}"
        ;;

    tools)
        stage="${1:?stage required}"
        tools_for "${stage}"
        ;;

    envelope)
        stage="${1:?stage required}"
        task="${2:?task required}"
        pattern="$(pattern_for "${stage}")"
        tools="$(tools_for "${stage}")"
        objective="$(objective_for "${stage}")"
        cat <<EOF
Cognitive pattern: ${pattern}.

SPARC stage: ${stage}.

Objective: ${objective}

Task being solved by this SPARC cycle:
${task}

Constraints:
- Stay within this stage's mandate. Do not bleed into the next stage.
- Output must be falsifiable: a reader should be able to point at it and say "right" or "wrong" without ambiguity.
- Cite every concrete claim either to a Read'd file (file:line) or to a retrieved web source (url + quoted_passage). Uncited claims are dropped.
- If you reach a point where you need information from a different SPARC stage, halt and emit a "next-stage: <stage>" line plus the question; do not guess.

Tools allowed: ${tools}.
Token budget: under 600 words.

Output format:
## ${stage} (cognitive pattern: ${pattern})

[your work here, structured as appropriate for this stage]

## Citations
- {file_or_url}: "{quoted_passage}" → "{claim}"

## Open questions for next stage
- (or "(none)" if all resolved)
EOF
        ;;

    *)
        cat >&2 <<EOF
Usage: $0 <subcommand> [args]

Subcommands:
  stages                       list the 5 SPARC stages, one per line
  envelope <stage> <task>      emit canonical Agent prompt body for the stage
  pattern <stage>              emit cognitive pattern (abstract|systems|divergent|critical|convergent)
  tools <stage>                emit comma-separated tool allowlist for the stage

Stages: specification, pseudocode, architecture, refinement, completion
EOF
        exit 2
        ;;
esac
