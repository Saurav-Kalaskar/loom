// LOOM-REFERENCE-SCAFFOLD — DO NOT EXECUTE DIRECTLY.
// loom-research.reference.js — v2.0 standalone web-research fan-out seed.
//
// Adapt-at-runtime seed for a research-only workflow (the /loom-research phase
// as a native Workflow). Same rules as loom-orchestrate.reference.js: names are
// best-effort, structure + guarantees are fixed (see assets/workflow-contract.md).
// Model ids come from loom_config.sh emit_json — never hardcoded.

export const meta = {
  name: 'loom-research',
  description: 'Loom v2.0 web research: 5 parallel researchers → one cited brief',
  phases: [
    { title: 'fan-out',   detail: '5 researchers, distinct angles, WebSearch/WebFetch only' },
    { title: 'synthesize', detail: 'merge into one cited brief' },
  ],
}

const TOPIC = args?.topic ?? args ?? 'UNSPECIFIED TOPIC'
const LOOM = '~/.claude/skills/loom/scripts'

// Read model map once.
const MODEL = JSON.parse(await agent(
  `Run: bash ${LOOM}/loom_config.sh emit_json — return ONLY the JSON.`,
  { label: 'config:models', phase: 'fan-out' }
))

phase('fan-out')
const ANGLES = ['official_docs','community_qa','source_issues','recent_blogs','benchmarks_caseStudies']
const partials = await parallel(ANGLES.map(angle => () =>
  agent(
    `You are the "${angle}" web researcher for the topic: ${TOPIC}\n` +
    `Tools: WebSearch + WebFetch ONLY.\n` +
    `MANDATORY: never include private/internal proper nouns in any query — generalize to neutral technical terms.\n` +
    `Every claim must cite {url, quoted_passage, claim}. Uncited claims are dropped.\n` +
    `Report under 300 words.`,
    { label: `research:${angle}`, phase: 'fan-out', model: MODEL.researcher }
  )
))

phase('synthesize')
const brief = await agent(
  `Synthesize these ${partials.filter(Boolean).length} angle briefs into ONE cited brief on "${TOPIC}". ` +
  `Resolve contradictions by preferring official + more-recent + corroborated sources. ` +
  `Keep every claim's citation. Under 800 words.\n\n` +
  partials.filter(Boolean).join('\n\n---\n\n'),
  { label: 'synth', phase: 'synthesize', model: MODEL.synth }
)

return { topic: TOPIC, researchers: partials.filter(Boolean).length, brief }
