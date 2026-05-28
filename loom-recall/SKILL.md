---
name: loom-recall
description: Read or write Reflexion lessons learned from past task attempts (Loom Phase 9).
allowed-tools: Bash(*) Read
disable-model-invocation: true
---

# /loom-recall

Direct slash entry into Loom's Phase 9: Reflexion self-learning loop.
Persistent post-mortem lessons keyed by task hash, accumulated across runs
to improve pass rate (Reflexion pattern, Shinn et al. 2023).

State lives at `~/.claude/skills/loom/state/reflections.jsonl` (user
scope, sourced from anywhere, never inside a project).

Same logic as `/loom recall <subcommand> ...` from the parent loom
dispatcher — surfaced as its own slash command for autocomplete
discoverability.

## Usage

```
/loom-recall hash "<task text>"
/loom-recall read <hash> [n]
/loom-recall write <hash> <attempt_n> <pass|fail> "<failure_mode>" "<lesson>"
/loom-recall stats
```

`$ARGUMENTS` is the subcommand line. If empty, run `stats` to summarize
the lesson log.

## Subcommands

- **`hash "<task>"`** — emit sha1 of the normalized task.
- **`read <hash> [n]`** — emit the last N lessons (default 3) for this
  task hash, formatted as `[attempt N] pass|fail: <lesson>`.
- **`write <hash> <attempt> <pass|fail> "<failure_mode>" "<lesson>"`** —
  append a post-mortem to JSONL.
- **`stats`** — summarize total lessons, pass/fail counts, top failure
  modes.

## Execution

Resolve the script path: `~/.claude/skills/loom/scripts/reflexion.sh`.
Invoke via `Bash` with `$ARGUMENTS` tokens as positional args. Return
stdout verbatim.

## Subcommand discipline

This skill is **single-phase**. For full pipeline auto-recall (read at
task start, write at task end), invoke `/loom <task>` instead.
