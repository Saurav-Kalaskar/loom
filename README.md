# Loom

> Multi-agent orchestrator for Claude Code. Weaves parallel research and code
> agents into one coordinated output. Pure shell + python3, zero installs,
> corp-network-safe.

`/loom <task>` inside Claude Code. Done.

---

## What it does

Loom is a **16-phase skill** that turns a single Claude Code session into a
self-coordinating agent fan-out:

| Phase | What |
|---|---|
| 0 | Inject live git status / diff so plans are grounded in reality |
| 1 | Discover available skills, MCP servers, plugins |
| 2 | Cross-repo retrieval lanes (local + web) |
| 3 | Cloud-boundary / microservice topology checks |
| 4 | Pick a swarm topology (mesh, hierarchical, star, ring, adaptive) |
| 5 | **Fan-out**: 3–8 specialized subagents in one parallel `Agent` call |
| 6 | SPARC 5-stage cycle (specification → completion) when implementing |
| 7a | Local code retrieval via ripgrep + token-overlap ranking |
| 7b | **Deep web research**: 5 researchers × 3 tiers (lite / pro / ultra) |
| 8 | Daily sprint execution with Thought-Action-Observation scratchpad |
| 9 | **Reflexion** loop + **Voyager** skill library — compounds across runs |
| 10 | Session checkpoints for long-running work |
| 11 | Lifecycle hooks → metadata-only event log |
| 12 | Critic-agent gate before commit |
| 13 | Agile/DevOps guardrails |
| 14 | Persistent auto-learning at user-scope memory |
| 15 | Sprint health metrics |

The full breakdown is in [`SKILL.md`](./SKILL.md).

---

## Why use it (instead of just talking to Claude Code)

Three things compound across runs:

1. **Self-learning.** Every task attempt appends a lesson to
   `~/.claude/skills/loom/state/reflections.jsonl`. Re-running the same task
   prepends the last 3 lessons before fan-out. Pass rates measurably improve
   across iterations (Reflexion pattern, Shinn et al. 2023).
2. **Skill library.** Successful artifacts (scripts, prompts, recipes) get
   saved as named skills. Future tasks retrieve them by keyword overlap and
   adapt them. Auto-promote on N=3 successes; auto-retire on >40% failure.
3. **Parallel research.** Phase 7b spawns 5 web researchers in parallel, each
   on a different angle (official docs, community, source/issues, recent
   blogs, benchmarks), then synthesizes one cited brief. Three depth tiers:
   - **lite** — 1 round, ~3 min wall time
   - **pro** — 2 rounds, ~6 min (default)
   - **ultra** — 3 rounds, ~10 min

Plus a critic-agent gate (Phase 12) that adversarially reviews diffs before
commit, and a session-checkpoint system (Phase 10) for long sprints.

All of this runs natively in Claude Code's `Agent` tool. **Nothing is installed
into your network or shell.**

---

## Prerequisites

Required:

| Tool | Why | Verify |
|---|---|---|
| Claude Code | the host | `claude --version` |
| Python 3.6+ | embedded inside hooks/scripts | `python3 --version` |
| Bash 3.2+ | script interpreter | `bash --version` |
| `shasum` | stable task hashing | `shasum --version` |

Optional:

| Tool | What you lose without it |
|---|---|
| `ripgrep` | Phase 7a. Loom auto-discovers ripgrep bundled inside Claude Code if not on PATH; only fully missing if neither is present. |

Not needed (intentionally — replaced by the corp-safe scripts):

- ❌ `claude-flow` / `ruv-swarm` MCP servers
- ❌ `chromadb` / `sentence-transformers` (PyPI)
- ❌ `npm install` / `pip install` of any kind
- ❌ Internet to npm/pypi at runtime

---

## Install

```bash
git clone <this-repo-url> loom
cd loom
bash install.sh
```

The installer:
1. Verifies prerequisites
2. Copies scripts to `~/.claude/skills/loom/`
3. Asks once whether to install Phase 11 lifecycle hooks (default Yes)
4. Backs up `~/.claude/settings.json` before any merge
5. Verifies all scripts execute

To install non-interactively:

```bash
bash install.sh -y           # accept defaults (installs hooks)
bash install.sh --no-hooks   # install scripts only, skip hooks
bash install.sh --hooks      # install everything, no prompt
```

**Re-running `install.sh` is safe** — script files overwrite cleanly, and the
hooks merge skips entries that are already there.

---

## Use

Inside Claude Code:

```
/loom <task description>
```

Or invoke specific phases by talking to the orchestrator:

```
/loom build a notifications microservice — use SPARC, ultra-tier research
/loom investigate why the auth flow is dropping refresh tokens — pro-tier
/loom rename foo to bar          # auto-skips Phase 7 (trivial task)
```

The orchestrator decides which phases to run based on task shape. For
non-trivial tasks it will prompt you for the research tier (lite/pro/ultra).

---

## Uninstall

```bash
bash uninstall.sh
```

By default this:
- Removes `~/.claude/skills/loom/{SKILL.md,scripts}`
- Removes the hooks block from `~/.claude/settings.json` (with backup)
- **Preserves `~/.claude/skills/loom/state/`** (your reflections, sessions,
  research briefs, hooks log)

To wipe state too:

```bash
bash uninstall.sh --purge
```

To leave hooks in place (e.g., you're moving the install elsewhere):

```bash
bash uninstall.sh --keep-hooks
```

---

## What gets added to your machine

```
~/.claude/skills/loom/
├── SKILL.md                              # the prompt the orchestrator runs
├── scripts/
│   ├── reflexion.sh                      # Phase 9 self-learning
│   ├── session_checkpoint.sh             # Phase 10 session state
│   ├── critic_gate.sh                    # Phase 12 critic prompt
│   ├── web_research.sh                   # Phase 7b deep research
│   ├── skill_library.sh                  # Phase 9b Voyager
│   ├── sparc_envelope.sh                 # Phase 6 SPARC stages
│   ├── rag_grep.sh                       # Phase 7a local code retrieval
│   └── hooks/
│       ├── session_event.sh              # SessionStart/Stop hook
│       └── edit_event.sh                 # PreToolUse/PostToolUse Edit|Write
└── state/                                # created on first use
    ├── reflections.jsonl                 # Phase 9 lesson log
    ├── events.jsonl                      # Phase 11 session log (metadata only)
    ├── edits.jsonl                       # Phase 11 edit log (metadata only)
    ├── sessions/<id>/state.json          # Phase 10 checkpoints
    ├── research/<hash>/{job.json,brief.md,researcher_*.md}  # Phase 7b cache
    └── skills/<slug>/{skill.json,code.<ext>}                # Phase 9b library
```

Total static install: **~50 KB**. State grows as you use it (a few KB per
active hour — see Privacy below).

If you opt in to Phase 11 hooks, this block is appended to
`~/.claude/settings.json` (idempotent — re-installing won't duplicate):

```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "~/.claude/skills/loom/scripts/hooks/session_event.sh start", "timeout": 5 }]}],
    "Stop":         [{ "hooks": [{ "type": "command", "command": "~/.claude/skills/loom/scripts/hooks/session_event.sh stop",  "timeout": 5 }]}],
    "PreToolUse":   [{ "matcher": "Edit|Write", "hooks": [{ "type": "command", "command": "~/.claude/skills/loom/scripts/hooks/edit_event.sh pre",  "timeout": 5 }]}],
    "PostToolUse":  [{ "matcher": "Edit|Write", "hooks": [{ "type": "command", "command": "~/.claude/skills/loom/scripts/hooks/edit_event.sh post", "timeout": 5 }]}]
  }
}
```

---

## Privacy: what hooks log (and what they don't)

Phase 11 hooks fire on every Claude Code session and every Edit/Write tool
call across **every** project on your machine. To make this safe at scale:

**Stored in `state/edits.jsonl` per edit:**

| Field | Example | Note |
|---|---|---|
| `ts` | `2026-05-27T01:38:58Z` | UTC timestamp |
| `phase` | `pre` or `post` | hook lifecycle |
| `tool` | `Edit` or `Write` | tool name |
| `file_basename` | `secret.cs` | last path component, max 120 chars |
| `file_path_hash` | `a63a99fdb0bfca78` | sha256 of full path, truncated |
| `cwd_basename` | `my-project` | leaf dir name only |
| `cwd_hash` | `fd6d816f8b6b110a` | sha256 of full cwd, truncated |
| `edit_size_bytes` | `29` | length of new content |

**Never stored:**
- Full file paths (only basename + hash)
- Full working-directory paths (only basename + hash)
- File content
- `old_string` / `new_string` / `content` field contents
- Any portion of the raw tool input payload

The hash lets you correlate ("did another session touch the same file?")
without storing the path itself. Verified empirically: a hook fed
`/Users/x/Desktop/secret_project/secret.cs` containing `VERY_SENSITIVE_API_KEY_abc123`
produced **0 grep hits** in the JSONL for either the path component or the
content.

If you don't want hooks at all, install with `--no-hooks` or just say no at
the prompt. The skill works fine without them — you only lose Phase 11
cross-session coordination.

---

## Storage

All state is JSONL or JSON-document — no SQLite, no daemon, no schema
enforcement. Append-only logs are POSIX-safe for concurrent writers under
PIPE_BUF.

**Inspect at any time:**

```bash
# last 20 edits
tail -20 ~/.claude/skills/loom/state/edits.jsonl | jq

# session lifecycle
tail -10 ~/.claude/skills/loom/state/events.jsonl

# Reflexion stats
~/.claude/skills/loom/scripts/reflexion.sh stats

# skill library
~/.claude/skills/loom/scripts/skill_library.sh list

# session checkpoints
~/.claude/skills/loom/scripts/session_checkpoint.sh list
```

**Rotate logs (manual; no auto-rotation):**

```bash
cd ~/.claude/skills/loom/state
mv events.jsonl events.jsonl.$(date +%Y%m%d) && touch events.jsonl
mv edits.jsonl  edits.jsonl.$(date +%Y%m%d)  && touch edits.jsonl
```

---

## Troubleshooting

**`/loom` doesn't appear in Claude Code.**
The skill folder must be at `~/.claude/skills/loom/` (exactly that path) and
contain `SKILL.md`. Verify:
```bash
ls ~/.claude/skills/loom/SKILL.md
```
Restart Claude Code (skills are discovered at session start).

**Hooks don't seem to fire.**
SessionStart fires only on a *new* session — restart Claude Code. Verify the
hooks block landed in settings.json:
```bash
python3 -c "import json; print(json.dumps(json.load(open('$HOME/.claude/settings.json'))['hooks'], indent=2))"
```
After triggering one Edit, check:
```bash
tail ~/.claude/skills/loom/state/edits.jsonl
```
If empty, check that `python3` is on PATH for non-interactive shells.

**Phase 7a / `rag_grep.sh` errors with "ripgrep not found".**
Either install ripgrep (`brew install ripgrep` on macOS) or check that Claude
Code's bundled ripgrep is present at one of:
```
~/.nvm/versions/node/*/lib/node_modules/*/node_modules/@anthropic-ai/claude-code/vendor/ripgrep/<arch>-<os>/rg
~/.local/share/claude/versions/*/vendor/ripgrep/<arch>-<os>/rg
```

**Web research times out (Phase 7b).**
`lite` = 3 min, `pro` = 6 min, `ultra` = 10 min. On timeout the synthesizer
runs over partial researcher output and the brief is labeled `[TIMEOUT]`. To
bust the 24h cache and force fresh research, append `--research` to your
task or pick a higher tier (Ultra busts a Pro-cached brief).

**My corp network blocks `pip install` / `npm install`.**
That's by design. Loom is **dependency-free at runtime**. If you've installed
it and it still fails, you're hitting something else; check the prerequisites
above.

---

## Sharing with teammates

This skill is designed to be self-contained. To share:

1. They `git clone` this repo
2. They run `bash install.sh`
3. Done

No PyPI, no npm, no proxy config, no daemon. Same skill, same state location,
same prompts. Their state directory accumulates locally per-machine.

---

## License

MIT — see [LICENSE](./LICENSE).

---

## Credits

- Reflexion — Shinn et al., 2023
- Voyager — Wang et al., 2023
- Multi-agent research orchestration — Anthropic
- THOUGHT-ACTION-OBSERVATION scaffold — ReAct line of work
- SPARC methodology — community
