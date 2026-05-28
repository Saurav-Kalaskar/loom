# Loom Workflow Contract (v2.0)

This is the **stable contract** every Loom-authored workflow script must
satisfy. The in-script Workflow API (`agent`, `parallel`, `pipeline`, `phase`,
`log`, and a possible per-agent `schema`) is a research-preview surface and may
change; this contract is what stays constant. When the API and this contract
disagree, follow the API for *syntax* but preserve the *structure and
guarantees* below.

## Phase order (load-bearing)

1. **recall** — read prior learning. One agent runs:
   - `reflexion.sh hash "<task>"` → `$HASH`
   - `reflexion.sh read "$HASH" 3` → prior lessons
   - `skill_library.sh find "<task>" 5` → reusable recipes
   - `session_checkpoint.sh new` → `$SESSION_ID` (mint once, thread through)
   Inject results into the shared context for later phases.
   Model role: `learn` (haiku).

2. **research** — external knowledge (skip if task is trivial; gate with
   `web_research.sh auto_skip "<task>"`). Five researcher agents in parallel,
   one synthesizer. Reuse `web_research.sh` exactly as the prose Phase 7b does.
   Model roles: `researcher` (haiku) ×5, `synth` (sonnet) ×1.

3. **retrieve** — local grounding. One agent runs `rag_grep.sh cite <root>
   "<query>"`. Skip if not in a code repo. Model role: `retrieve` (haiku).

4. **build** — implement. FIRST action: arm the sentinel with
   `run_sentinel.sh start "$SESSION_ID"`. Then run SPARC stages in order
   (specification → pseudocode → architecture → refinement → completion), each
   agent's prompt body from `sparc_envelope.sh envelope <stage> "<task>"`.
   Model role: `sparc` (sonnet).

5. **critic** — adversarial review. One agent runs the body from
   `critic_gate.sh prompt "<diff summary>" "<paths>"`. It MUST emit a verdict in
   the exact format in the "Output contract" section below. If REJECT and
   retries remain, loop back to **build** with the critique injected. Bound the
   loop by `max_critic_retries` from `loom_config.sh`-adjacent config (default
   3). Model role: `critic` (opus, configurable).

6. **learn** — persist outcome. One agent runs:
   - `reflexion.sh write "$HASH" <attempt> <pass|fail> "<failure_mode>" "<lesson>"`
   - `skill_library.sh record <slug> <pass|fail>` (if a recipe was used/created)
   - `session_checkpoint.sh write "$SESSION_ID" learn '<state_json>'`
   LAST action: clear the sentinel with `run_sentinel.sh stop`.
   Model role: `learn` (haiku).
   This phase MUST run even if `build`/`critic` failed (use a finally-style
   guard) so the sentinel is always cleared and the failure is recorded.

## Output contract (critic verdict)

If the runtime exposes a per-agent `schema`, use:
```json
{ "type": "object",
  "properties": { "verdict": {"enum": ["ACCEPT","REJECT","ACCEPT-WITH-NOTES"]},
                  "findings": {"type": "string"} },
  "required": ["verdict"] }
```
If schema is unavailable, the critic agent MUST end its output with exactly:
```
## Verdict
- ACCEPT
```
(or `REJECT` / `ACCEPT-WITH-NOTES`). Parse with a regex on the last
`## Verdict` block: `REJECT` anywhere in that block → reject; else accept.
Never assume schema is present.

## Model routing

Read the role→model map ONCE at startup:
```
bash ~/.claude/skills/loom/scripts/loom_config.sh emit_json
```
Set each stage's `model` from that map by role. Do NOT hardcode model ids in
the script. If a model is unreachable, `loom_env.sh model_probe` will have
demoted critic opus→sonnet via `LOOM_CRITIC_MODEL`; honor whatever `emit_json`
returns.

## Sentinel discipline (arms the critic-gate hook)

- `build` first action: `run_sentinel.sh start "$SESSION_ID"`
- `learn` last action (always): `run_sentinel.sh stop`
- The sentinel file `state/run/active.json` is what makes the global
  `critic_stop.sh` hook a no-op outside a Loom run. If you forget to clear it,
  the hook will keep gating; the hook self-protects with a max-retry fail-open,
  but ALWAYS clear it.

## Shell I/O boundary

The workflow script (JS) does no filesystem or shell access beyond `log()`.
Only workflow **agents** run Bash. The script coordinates agents and captures
their stdout into variables. This matches the documented Workflow runtime model.

## Privacy

The helper scripts already store metadata-only. Do not add steps that persist
file contents, full paths, or diffs to disk. The critic reads the diff
transiently via the agent; nothing is written except the metadata-only
Reflexion/checkpoint records.
