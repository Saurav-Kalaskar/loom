---
name: loom-research
description: Deep web research on a topic — 5 parallel agents fan out, synthesize one cited brief (Loom Phase 7b).
allowed-tools: Bash(*) Read Write Agent WebFetch WebSearch
disable-model-invocation: true
---

# /loom-research

Direct slash entry into Loom's Phase 7b: web fan-out research. Five parallel
researchers each work a distinct angle (official_docs, community_qa,
source_issues, recent_blogs, benchmarks_caseStudies) and one synthesizer
merges the partial briefs into a single cited brief.

This is the same logic as `/loom research <topic>` from the parent loom
dispatcher — surfaced as its own slash command for autocomplete
discoverability.

## Usage

```
/loom-research <topic>
```

`$ARGUMENTS` is the research topic. If empty, ask the user what to research.

## Pipeline

Use the existing helper at `~/.claude/skills/loom/scripts/web_research.sh`:

1. **Auto-skip check** — `web_research.sh auto_skip "$ARGUMENTS"` (exit 0 →
   topic is too small; ask the user whether to force `--research`).
2. **Hash + cache** — `web_research.sh hash "$ARGUMENTS"` then
   `web_research.sh cache_lookup <hash> <tier>`. On hit, return cached
   brief and stop.
3. **Tier prompt** — on cache miss, call `AskUserQuestion` with three
   options (lite / pro / ultra). Pro is the recommended default. Surface
   the wall timeout in the question text (3 / 6 / 10 min).
4. **Start** — `web_research.sh start <hash> <tier> "<query>"` writes the
   job spec.
5. **Read tier params** — `web_research.sh tier_params <tier>` returns
   `researchers|rounds|sources|budget|timeout` (pipe-delimited).
6. **Fan out** — single message with five `Agent` calls (one per angle),
   tools allowed: `WebSearch`, `WebFetch` only. Each researcher writes to
   the canonical partial path from `web_research.sh partial_path <hash> <angle>`.
   Mandatory query-scrubbing rule: never include private/internal proper nouns in
   WebSearch queries. Citation rule: every claim emits
   `{url, quoted_passage, claim}`.
7. **Synthesize** — one `Agent` (cognitive pattern: convergent, tools:
   `Read` only) reads the five partials and emits
   `~/.claude/skills/loom/state/research/<hash>/brief.md`.
8. **Finalize** — `web_research.sh finalize <hash>` checks completion vs
   timeout and prepends a `[TIMEOUT]` banner if needed.
9. **Return** — print the brief path and a short summary.

## Subcommand discipline

This skill is **single-phase**. It does not chain into Phases 0–15. For
chained behavior (research → fan-out → SPARC → critic), invoke
`/loom <task>` instead.
