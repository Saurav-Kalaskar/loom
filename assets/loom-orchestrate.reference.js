// LOOM-REFERENCE-SCAFFOLD — DO NOT EXECUTE DIRECTLY.
// loom-orchestrate.reference.js — v2.0 full-pipeline seed.
//
// This is a SEED, not a finished workflow. The /loom-workflow skill instructs
// Claude to ADAPT this into a complete script at runtime and run it via the
// Workflow tool, then save the adapted copy to ~/.claude/workflows/loom-orchestrate.js.
//
// The in-script Workflow API (agent/parallel/pipeline/phase/log + optional
// schema) is a research-preview surface; treat the FUNCTION NAMES as
// best-effort and the STRUCTURE + GUARANTEES (see assets/workflow-contract.md)
// as fixed. If a symbol differs in this Claude Code version, adapt syntax but
// preserve phase order, model routing, sentinel discipline, and the shell-call
// boundary (agents run Bash; the script only coordinates + log()).
//
// Model ids are NOT hardcoded: the script reads them from
//   bash ~/.claude/skills/loom/scripts/loom_config.sh emit_json
// via a recall-phase agent, then routes each stage by role.

export const meta = {
  name: 'loom-orchestrate',
  description: 'Loom v2.0 full pipeline: recall → research → retrieve → build → critic → learn',
  phases: [
    { title: 'recall',   detail: 'read prior Reflexion lessons + Voyager skills' },
    { title: 'research', detail: '5 web researchers + synth (skipped for trivial tasks)' },
    { title: 'retrieve', detail: 'local rag_grep grounding' },
    { title: 'build',    detail: 'SPARC stages; arms run sentinel' },
    { title: 'critic',   detail: 'adversarial review; loops to build on REJECT' },
    { title: 'learn',    detail: 'persist outcome; clears run sentinel' },
  ],
}

const TASK = args?.task ?? args ?? 'UNSPECIFIED TASK'
const LOOM = '~/.claude/skills/loom/scripts'

// Small helper: an agent that just runs one shell line and returns stdout.
// (Agents carry Bash; the script never shells out itself.)
const sh = (label, phase, cmdLine) =>
  agent(
    `Run exactly this shell command and return ONLY its stdout, nothing else:\n\n${cmdLine}`,
    { label, phase, model: MODEL.learn }
  )

// markPhase: announce the current phase to the user via BOTH the status-bar
// flag (run_sentinel.sh phase) and an in-chat line. Call at every transition so
// the user always sees which Loom phase is running. (Agent runs the shell; the
// JS only coordinates + log()s.)
const markPhase = (name) =>
  sh(`phase:${name}`, name,
     `bash ${LOOM}/run_sentinel.sh phase ${name} >/dev/null 2>&1; echo "▶ Loom: ${name} phase"`)

// ---- recall: arm the sentinel FIRST so the badge shows for the whole run ----
phase('recall')
await sh('sentinel:start', 'recall', `bash ${LOOM}/run_sentinel.sh start loom-run recall`)
await markPhase('recall')

// read the model map once (so nothing is hardcoded)
const mapJson = await agent(
  `Run: bash ${LOOM}/loom_config.sh emit_json — return ONLY the JSON it prints.`,
  { label: 'config:models', phase: 'recall' }
)
const MODEL = JSON.parse(mapJson) // { researcher, retrieve, learn, synth, sparc, critic }

// recall: prior learning
const HASH = (await sh('reflexion:hash', 'recall',
  `bash ${LOOM}/reflexion.sh hash ${JSON.stringify(TASK)}`)).trim()
const lessons = await sh('reflexion:read', 'recall',
  `bash ${LOOM}/reflexion.sh read ${HASH} 3`)
const recipes = await sh('skills:find', 'recall',
  `bash ${LOOM}/skill_library.sh find ${JSON.stringify(TASK)} 5`)
const SESSION_ID = (await sh('checkpoint:new', 'recall',
  `bash ${LOOM}/session_checkpoint.sh new`)).trim()
log(`recall: hash=${HASH.slice(0,8)} session=${SESSION_ID}`)

// ---- research: skip-gate, then 5 researchers + synth ----
phase('research')
await markPhase('research')
const skip = await agent(
  `Run: bash ${LOOM}/web_research.sh auto_skip ${JSON.stringify(TASK)}; ` +
  `then print "SKIP" if it exited 0, else "DO".`,
  { label: 'research:gate', phase: 'research', model: MODEL.researcher }
)
let brief = ''
if (!/SKIP/.test(skip)) {
  const ANGLES = ['official_docs','community_qa','source_issues','recent_blogs','benchmarks_caseStudies']
  const partials = await parallel(ANGLES.map(angle => () =>
    agent(
      `You are the "${angle}" web researcher for: ${TASK}\n` +
      `Use WebSearch + WebFetch ONLY. NEVER put private/internal proper nouns in queries — generalize.\n` +
      `Every claim cites {url, quoted_passage, claim}. Report under 300 words.`,
      { label: `research:${angle}`, phase: 'research', model: MODEL.researcher }
    )
  ))
  brief = await agent(
    `Synthesize these ${partials.filter(Boolean).length} research briefs into ONE cited brief. ` +
    `Prefer official + recent + corroborated sources. Resolve contradictions explicitly.\n\n` +
    partials.filter(Boolean).join('\n\n---\n\n'),
    { label: 'research:synth', phase: 'research', model: MODEL.synth }
  )
}

// ---- retrieve: local grounding ----
phase('retrieve')
await markPhase('retrieve')
const citations = await sh('rag:cite', 'retrieve',
  `bash ${LOOM}/rag_grep.sh cite ./ ${JSON.stringify(TASK)} 12 || true`)

// ---- build + critic loop ----
const MAX = 3
let attempt = 0, verdict = 'REJECT', critique = '', diffSummary = '', paths = ''
const sharedContext =
  `TASK: ${TASK}\n\nPRIOR LESSONS:\n${lessons}\n\nRECIPES:\n${recipes}\n\n` +
  `RESEARCH BRIEF:\n${brief}\n\nLOCAL CITATIONS:\n${citations}`

// Sentinel already armed in recall; just mark the phase. (The critic-gate hook
// only fires on SubagentStop WITH a diff — no diff exists until build edits, so
// arming early is safe.)
phase('build')
await markPhase('build')

while (attempt < MAX && /REJECT/.test(verdict)) {
  attempt++
  // Run SPARC stages sequentially — order is load-bearing.
  for (const stage of ['specification','pseudocode','architecture','refinement','completion']) {
    const envelope = await sh(`sparc:env:${stage}`, 'build',
      `bash ${LOOM}/sparc_envelope.sh envelope ${stage} ${JSON.stringify(TASK)}`)
    await agent(
      `${envelope}\n\n<context>\n${sharedContext}\n${critique ? 'PRIOR CRITIQUE TO ADDRESS:\n'+critique : ''}\n</context>`,
      { label: `build:${stage}:try${attempt}`, phase: 'build', model: MODEL.sparc }
    )
  }
  // Capture the actual diff for the critic (agent computes it).
  diffSummary = await sh('diff:summary', 'build', `git -C ./ diff --stat 2>/dev/null | tail -40 || echo "no git diff"`)
  paths       = await sh('diff:paths',   'build', `git -C ./ diff --name-only 2>/dev/null || echo ""`)

  phase('critic')
  await markPhase('critic')
  const criticBody = await sh('critic:prompt', 'critic',
    `bash ${LOOM}/critic_gate.sh prompt ${JSON.stringify(diffSummary)} ${JSON.stringify(paths)}`)
  // Optional schema; falls back to text contract (see workflow-contract.md).
  const review = await agent(criticBody, {
    label: `critic:try${attempt}`, phase: 'critic', model: MODEL.critic,
    schema: { type: 'object',
      properties: { verdict: { enum: ['ACCEPT','REJECT','ACCEPT-WITH-NOTES'] }, findings: { type: 'string' } },
      required: ['verdict'] },
  }).catch(async () => {
    // schema unsupported → re-run without it and parse the text verdict
    const txt = await agent(criticBody, { label: `critic:try${attempt}:text`, phase: 'critic', model: MODEL.critic })
    const m = txt.match(/##\s*Verdict[\s\S]*$/i)
    return { verdict: m && /REJECT/.test(m[0]) ? 'REJECT' : 'ACCEPT', findings: txt }
  })
  verdict  = (review.verdict || 'REJECT')
  critique = (review.findings || '')
  log(`critic try ${attempt}: ${verdict}`)
}

// ---- learn: ALWAYS runs (records outcome + clears sentinel + flag) ----
phase('learn')
await markPhase('learn')
const outcome = /REJECT/.test(verdict) ? 'fail' : 'pass'
const lesson  = /REJECT/.test(verdict)
  ? `Critic rejected after ${attempt} attempts: ${critique.slice(0,180)}`
  : `Passed critic in ${attempt} attempt(s).`
await sh('reflexion:write', 'learn',
  `bash ${LOOM}/reflexion.sh write ${HASH} ${attempt} ${outcome} "critic" ${JSON.stringify(lesson)}`)
await sh('checkpoint:write', 'learn',
  `bash ${LOOM}/session_checkpoint.sh write ${SESSION_ID} learn ${JSON.stringify(JSON.stringify({task: TASK, verdict, attempt}))}`)
await sh('sentinel:stop', 'learn', `bash ${LOOM}/run_sentinel.sh stop`)

return { verdict, attempt, outcome, session: SESSION_ID, briefPresent: !!brief }
