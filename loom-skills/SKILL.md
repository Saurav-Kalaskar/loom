---
name: loom-skills
description: Save or find reusable skill recipes by keyword across runs (Loom Phase 9b).
allowed-tools: Bash(*) Read
disable-model-invocation: true
---

# /loom-skills

Direct slash entry into Loom's Phase 9b: Voyager-style skill library.
Persistent reusable artifacts (scripts, prompt templates, refactor recipes)
retrieved by keyword overlap (no embeddings — keyword-only) and
auto-promoted/auto-retired based on success ratio.

State lives at `~/.claude/skills/loom/state/skills/<slug>/`.

Same logic as `/loom skills <subcommand> ...` from the parent loom
dispatcher — surfaced as its own slash command for autocomplete
discoverability.

## Usage

```
/loom-skills save <slug> "<description>" <code_path>
/loom-skills find "<query>" [n]
/loom-skills get <slug>
/loom-skills list
/loom-skills record <slug> <pass|fail>
/loom-skills promote <slug>
/loom-skills retire <slug>
```

`$ARGUMENTS` is the subcommand line. If empty, run `list`.

## Subcommands

- **`save <slug> "<desc>" <path>`** — persist a reusable artifact. Status
  starts at `pending`.
- **`find "<query>" [n]`** — return tab-separated `slug | overlap |
  success_ratio | status | description` for the top N matches.
- **`get <slug>`** — return the artifact code.
- **`list`** — list all saved skills (newest first).
- **`record <slug> pass|fail`** — record an outcome. Auto-promote
  `pending → active` after N=3 successes. Auto-retire on failure ratio
  > 0.4 (with ≥5 samples).
- **`promote <slug>`** / **`retire <slug>`** — manual override.

## Execution

Resolve the script path: `~/.claude/skills/loom/scripts/skill_library.sh`.
Invoke via `Bash` with `$ARGUMENTS` tokens as positional args. Return
stdout verbatim.

## Subcommand discipline

This skill is **single-phase**. For full pipeline auto-retrieval (find at
task start, record at task end), invoke `/loom <task>` instead.
