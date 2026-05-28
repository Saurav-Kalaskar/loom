---
name: loom-envelope
description: Generate a ready-to-use SPARC stage prompt for a spawned agent (Loom Phase 6).
allowed-tools: Bash(*) Read
disable-model-invocation: true
---

# /loom-envelope

Direct slash entry into Loom's Phase 6: SPARC envelope generator. Builds
fully-formed Agent prompt bodies for each SPARC stage with a fixed
cognitive pattern and tool allowlist.

Same logic as `/loom envelope <subcommand> ...` from the parent loom
dispatcher — surfaced as its own slash command for autocomplete
discoverability.

## Usage

```
/loom-envelope stages
/loom-envelope pattern <stage>
/loom-envelope tools <stage>
/loom-envelope envelope <stage> "<task>"
```

`$ARGUMENTS` is the subcommand line. If empty, run `stages` to list the
five stages.

## Subcommands

- **`stages`** — list the five SPARC stages.
- **`pattern <stage>`** — emit the cognitive pattern for one stage.
- **`tools <stage>`** — emit the tool allowlist for one stage.
- **`envelope <stage> "<task>"`** — emit a full Agent prompt body. Pass it
  as the `prompt` field of an `Agent` call. Use `general-purpose` as the
  subagent type.

| SPARC Stage    | Cognitive Pattern | Tool allowlist                                |
|----------------|-------------------|-----------------------------------------------|
| specification  | abstract          | Read, Grep, Glob, WebSearch, WebFetch         |
| pseudocode     | systems           | Read, Grep, Glob                              |
| architecture   | divergent         | Read, Grep, Glob, WebSearch, WebFetch         |
| refinement     | critical          | Read, Grep, Edit, Write, Bash(test runners)   |
| completion     | convergent        | Read, Grep, Edit, Write, Bash(test runners)   |

**Bash narrowed at refinement and completion** to test runners only
(pytest, npm test, go test, dotnet test, cargo test, jest, mocha).

## Execution

Resolve the script path: `~/.claude/skills/loom/scripts/sparc_envelope.sh`.
Invoke via `Bash` with `$ARGUMENTS` tokens as positional args.

## Subcommand discipline

This skill is **single-phase**. For chained behavior, invoke
`/loom <task>` instead.
