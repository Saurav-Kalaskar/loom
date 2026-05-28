---
name: loom-workflow
description: Run a task through Loom's native Dynamic-Workflow spine — deterministic parallel fan-out with per-stage model routing (Loom v2.0). Authors and runs a workflow script.
allowed-tools: Bash(*) Read Write Edit Glob Grep Agent Workflow WebFetch WebSearch
disable-model-invocation: true
---

# /loom-workflow

Run a task through Loom's **native Dynamic-Workflow spine** — the v2.0
orchestration core. This is the deterministic, backgrounded, model-routed
replacement for the prose Phases 0–15. Use it when Claude Code supports
Workflows (v2.1.154+); otherwise the parent `/loom` skill auto-falls back to
the prose pipeline.

**Task:** $ARGUMENTS

## What this does

Authors (or refreshes) a workflow script at `~/.claude/workflows/loom-orchestrate.js`
and runs it. The script orchestrates a fan-out of subagents through six phases,
routing each phase to the cheapest capable model, with the learning layer
(Reflexion, Voyager, checkpoints) bracketing the run.

## How to run it

1. **Probe mode** — run:
   ```
   bash ~/.claude/skills/loom/scripts/loom_env.sh workflow_probe
   ```
   If it prints `prose`, STOP and tell the user to invoke `/loom <task>` (the
   workflow runtime is unavailable on this Claude Code version). If `workflow`,
   continue.

2. **Read the contract + seed** — read these two files now:
   - `~/.claude/skills/loom/assets/workflow-contract.md` (the stable contract)
   - `~/.claude/skills/loom/assets/loom-orchestrate.reference.js` (the seed scaffold)

3. **Read the model map** — run:
   ```
   bash ~/.claude/skills/loom/scripts/loom_config.sh emit_json
   ```
   This gives the role→model map. Use it to set each stage's `model`.

4. **Author the workflow** — adapt the seed scaffold into a complete workflow
   script for THIS task. The seed is a starting shape, not a finished script:
   you fill in the task, the research query, and the model routing from step 3.
   Follow `workflow-contract.md` exactly (phase order, output contracts,
   shell-call sites, sentinel handling). Then invoke the `Workflow` tool with
   your authored script.

   Save the authored script to `~/.claude/workflows/loom-orchestrate.js` (so it
   also becomes the `/loom-orchestrate` slash command and is reusable).

5. **Report** — when the workflow completes, surface: the synthesized brief
   path, the diff/artifacts produced, the critic verdict, and confirm the
   `learn` phase wrote a Reflexion lesson (`reflexion.sh stats` count should be
   higher).

## Critical rules

- **Do NOT hardcode model ids** in the script — read them from
  `loom_config.sh emit_json` so a model rename is a one-file change.
- **The JS does no shell I/O** beyond `log()`. Workflow *agents* carry Bash and
  call the `~/.claude/skills/loom/scripts/*.sh` helpers; the script captures
  their output into variables.
- **Sentinel discipline**: the `build` phase must write the run sentinel
  (`bash ~/.claude/skills/loom/scripts/run_sentinel.sh start`) and the `learn`
  phase must clear it (`run_sentinel.sh stop`). This arms the deterministic
  critic-gate hook only during the run. See `workflow-contract.md`.
- **Schema is optional**: if the Workflow runtime exposes a per-agent `schema`
  option, use it for the critic verdict; if not, the agent emits the verdict in
  the exact text format from the contract and you parse it. Never hard-depend on
  schema.
- **Restart caveat**: workflow resume only works within the same Claude Code
  session. The `recall`/`learn` phases use `session_checkpoint.sh` so a fresh
  restart can rehydrate conceptually.

## Subcommand discipline

Single entry point. For the prose fallback path, the user runs `/loom --prose
<task>`. For a single phase, the user runs the dedicated sibling skills
(`/loom-research`, etc.).
