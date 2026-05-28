---
name: loom-critic
description: Build an adversarial reviewer prompt that tries to reject a diff before commit (Loom Phase 12).
allowed-tools: Bash(*) Read Agent
disable-model-invocation: true
---

# /loom-critic

Direct slash entry into Loom's Phase 12: critic-gate prompt builder. Emits
a canonical adversarial-reviewer prompt body whose only job is to find a
reason to reject the diff before commit.

Same logic as `/loom critic ...` from the parent loom dispatcher — surfaced
as its own slash command for autocomplete discoverability.

## Usage

```
/loom-critic agent_type
/loom-critic prompt "<diff summary>" "<change paths newline-separated>"
```

`$ARGUMENTS` is the subcommand line. If empty, print usage.

## Subcommands

- **`agent_type`** — emit the subagent type to use (currently
  `general-purpose`).
- **`prompt "<diff summary>" "<paths>"`** — emit the full critic prompt
  body. Capture stdout and feed it as the `prompt` field of an `Agent`
  call.

## Execution

Resolve the script path: `~/.claude/skills/loom/scripts/critic_gate.sh`.
Invoke via `Bash` with `$ARGUMENTS` tokens as positional args.

The diff summary and change paths are dynamic per-run; do **not** hardcode.
The orchestrator (or the user invoking `/loom-critic`) must compute them
from current working state and pass as quoted args.

## After running

If the critic returns REJECT or ACCEPT-WITH-NOTES, write the findings as
a new Reflexion lesson via `~/.claude/skills/loom/scripts/reflexion.sh
write` (see `/loom-recall`) and retry.

## Subcommand discipline

This skill is **single-phase**. For chained behavior, invoke
`/loom <task>` instead.
