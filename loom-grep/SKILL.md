---
name: loom-grep
description: Search local code for a query — ranked ripgrep hits, citations, or symbol definitions (Loom Phase 7a).
allowed-tools: Bash(*) Read
disable-model-invocation: true
---

# /loom-grep

Direct slash entry into Loom's Phase 7a: local code retrieval. Ranked
ripgrep results with TF-IDF-lite scoring, suitable for grounding spawned
agents in the existing codebase.

Same logic as `/loom grep <subcommand> ...` from the parent loom dispatcher —
surfaced as its own slash command for autocomplete discoverability.

## Usage

```
/loom-grep search <root> "<query>" [n]
/loom-grep cite   <root> "<query>" [n]
/loom-grep symbols <root> <name>
```

`$ARGUMENTS` is the full subcommand line (one of `search`, `cite`,
`symbols` followed by its args). If empty, print usage and stop.

## Subcommands

- **`search <root> "<query>" [n]`** — return ranked `file:line:hits` (top
  N, default 20).
- **`cite <root> "<query>" [n]`** — same data formatted as `## file`
  blocks with snippet lines, suitable for direct injection into a Phase 5
  agent envelope as `<context>`.
- **`symbols <root> <name>`** — heuristically locate the definition of a
  named function / class / type.

## Execution

Resolve the script path: `~/.claude/skills/loom/scripts/rag_grep.sh`.
Invoke via `Bash` with `$ARGUMENTS` tokens passed as positional args.
Return stdout to the user verbatim.

## Notes

- Wall-clock cap: 60 s global budget, 80 files max, 3 s per rg call.
- If `rg` is not on PATH, the script falls back to Claude Code's bundled
  ripgrep at `vendor/ripgrep/<arch>-<os>/rg`.
- Skip if the working directory is not a code repo. Use a `git rev-parse`
  guard to detect.

## Subcommand discipline

This skill is **single-phase**. For chained behavior, invoke
`/loom <task>` instead.
