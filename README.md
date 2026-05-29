# Loom

> Multi-agent orchestrator for Claude Code. Runs a task through a pipeline of
> parallel research and code agents with self-learning across runs. **v2.0**
> runs on Claude Code's native Dynamic-Workflow spine when available (parallel,
> deterministic, per-stage model routing) and falls back to a prose pipeline
> otherwise. Pure shell + python3, zero installs, dependency-free.

Invoke (inside Claude Code):

- `/loom <task>` — full pipeline (auto-selects Workflow spine or prose fallback)
- `/loom-<sub>` — jump straight to one phase (`/loom-research`, `/loom-grep`,
  `/loom-envelope`, `/loom-critic`, `/loom-recall`, `/loom-skills`,
  `/loom-checkpoint`, `/loom-workflow`)

---

## Install

```bash
git clone https://github.com/Saurav-Kalaskar/loom.git loom
cd loom
bash install.sh
```

Copies the skill + 8 sibling slash skills + workflow seeds into
`~/.claude/skills/`, then asks about Phase 11 lifecycle hooks (default Yes) and
the v2.0 deterministic critic gate (default No). Idempotent — safe to re-run.

```bash
bash install.sh -y                  # defaults: hooks on, critic gate off
bash install.sh --no-hooks          # scripts only, skip hooks
bash install.sh -y --critic-gate    # also enable the deterministic critic gate
```

**Requires:** Claude Code, `python3` ≥3.6, Bash, `shasum`. Optional `ripgrep`
(auto-discovers Claude Code's bundled `rg` if not on PATH). No pip/npm — works
behind a locked-down network with no PyPI/npm access. To share: clone + run
`bash install.sh`.

---

## Use

### Full pipeline

```
/loom <task description>
```

Loom first probes for the native Workflow runtime and picks a mode:

- **Workflow spine** (Claude Code ≥2.1.154) — a deterministic JS workflow fans
  out subagents in the background with per-stage model routing: Haiku
  researchers, Sonnet build, Opus critic. `recall → research → retrieve →
  build → critic → learn`.
- **Prose fallback** — the original 16-phase pipeline, run inline. Used when the
  Workflow runtime is unavailable or on older Claude Code.

Both call the same backing scripts and the same learning layer, so behavior is
equivalent; the spine is just deterministic and cheaper. Force a mode:

```
/loom --workflow build a rate limiter      # force the Workflow spine
/loom --prose build a rate limiter         # force the prose pipeline
/loom rename foo to bar                     # auto-skips web research (trivial)
```

Per-role models live in `~/.claude/skills/loom/state/config.json` (override any
role; `LOOM_CRITIC_MODEL` env wins for the critic). Check reachability with
`bash ~/.claude/skills/loom/scripts/loom_env.sh model_probe`.

### Seeing which phase is running

While a run is active, Loom shows the current phase two ways:

- **Status bar:** a `[LOOM:<phase>]` badge (e.g. `[LOOM:research]`, `[LOOM:critic]`).
  `install.sh` wires this and **composes** with any existing statusLine — if you
  use the caveman plugin, you'll see `[CAVEMAN] [LOOM:build]` side by side, nothing
  is replaced. Opt out with `--no-statusline`.
- **In chat:** a `▶ Loom: <phase> phase` line at each transition (always shown,
  no setup needed).

This works in both modes — the workflow seed and the prose pipeline both mark
every phase.

### Subcommands (single phase)

Each is its own slash command, so it shows up in Claude Code's `/`
autocomplete:

| Command            | Does                                              |
|--------------------|---------------------------------------------------|
| `/loom-research`   | Deep web research — 5 agents fan out → cited brief |
| `/loom-grep`       | Search local code — ranked ripgrep hits           |
| `/loom-envelope`   | Generate a SPARC stage prompt for an agent        |
| `/loom-critic`     | Build an adversarial diff-reviewer prompt         |
| `/loom-recall`     | Read/write Reflexion lessons from past attempts   |
| `/loom-skills`     | Save/find reusable skill recipes                  |
| `/loom-checkpoint` | Save/restore session state for long tasks         |
| `/loom-workflow`   | Run the v2.0 native Workflow spine directly       |

The legacy parent-dispatcher form (`/loom research <topic>`, `/loom menu`,
etc.) still works and routes to the same scripts.

Full phase-by-phase detail is in [`SKILL.md`](./SKILL.md).

---

## State & privacy

All state lives at `~/.claude/skills/loom/state/` (per-machine, never synced,
never inside a project). Reflexion lessons, skill library, research briefs,
and session checkpoints accumulate there.

If you opt into Phase 11 hooks, they log **metadata only** — file basenames +
sha256 hashes + byte sizes. File contents, full paths, and edit text are
**never** stored. Decline with `--no-hooks` at install if you don't want them.

The optional v2.0 critic gate (`--critic-gate`, default off) is a `SubagentStop`
hook that is a **strict no-op** unless a Loom run is active in the current
directory; when active it runs an adversarial critic (one `claude -p` call) and
forces iterate-until-pass, bounded by retries, fail-open on timeout. It persists
nothing.

Inspect anytime: `~/.claude/skills/loom/scripts/reflexion.sh stats`,
`tail ~/.claude/skills/loom/state/edits.jsonl`.

---

## Uninstall

```bash
bash uninstall.sh                # remove skill + 8 siblings + hooks (incl critic gate); keep state
bash uninstall.sh --purge        # also wipe state/
bash uninstall.sh --keep-hooks   # leave hooks in settings.json
```

Removes the sibling skills, workflow seeds, and any Loom-authored
`~/.claude/workflows/loom-*.js`. State is preserved by default. settings.json is
backed up before any edit.

---

## License

MIT — see [LICENSE](./LICENSE). Built on Reflexion (Shinn et al. 2023),
Voyager (Wang et al. 2023), and Anthropic's multi-agent research patterns.
