---
name: loom-checkpoint
description: Save or restore session state to resume a long task across resets (Loom Phase 10).
allowed-tools: Bash(*) Read
disable-model-invocation: true
---

# /loom-checkpoint

Direct slash entry into Loom's Phase 10: filesystem session checkpoints
for long-running conversational workflows. Treat session state as a
first-class artifact so a long sprint can be rehydrated across context
resets.

State lives at `~/.claude/skills/loom/state/sessions/<id>/state.json`
(user scope, never inside a project).

Same logic as `/loom checkpoint <subcommand> ...` from the parent loom
dispatcher — surfaced as its own slash command for autocomplete
discoverability.

## Usage

```
/loom-checkpoint new
/loom-checkpoint write <id> <phase> '<state_json>'
/loom-checkpoint read <id>
/loom-checkpoint list
/loom-checkpoint prune <days>
```

`$ARGUMENTS` is the subcommand line. If empty, run `list`.

## Subcommands

- **`new`** — emit a date-prefixed sortable session id (e.g.
  `20260527-123045-a1b2c3`). Capture once at the start of a long sprint.
- **`write <id> <phase> '<state_json>'`** — write a checkpoint. The
  `<state_json>` must be a JSON object (e.g.,
  `{working_set, open_questions, scratchpad_ref, ...}`). The script
  validates JSON before persisting and stamps `_meta: {ts, phase}`.
- **`read <id>`** — emit the latest state JSON. Use to rehydrate after a
  context reset.
- **`list`** — newest-first; columns: id, latest phase, ts.
- **`prune <days>`** — delete session dirs older than N days.

## Execution

Resolve the script path: `~/.claude/skills/loom/scripts/session_checkpoint.sh`.
Invoke via `Bash` with `$ARGUMENTS` tokens as positional args.

## Subcommand discipline

This skill is **single-phase**. For full-pipeline auto-checkpointing
(write after every significant phase), invoke `/loom <task>` instead.
