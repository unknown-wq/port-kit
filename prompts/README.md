# prompts/

Ready-to-paste prompts for running a Minecraft 26.2 port with a team of coding agents: one
orchestrator and four to six workers, each owning a disjoint list of files.

The prompt bodies are in Russian, like the rest of the kit — they are operational text, meant to be
copied verbatim into an agent, and a mistranslated rule is a broken port. This index is in English
so the pack stays navigable.

## The shape of a port

```
Orchestrator (00)  ── step 0: environment, recon, route, contracts, PORT-STATUS.md, rename script
       │
       ├── phase 1 ── Agent A (01)          alone; everyone depends on the skeleton
       │
       ├── phase 2 ── Agent B (02) ─┐       parallel, disjoint files, no Gradle
       │              Agent C (03) ─┤
       │              Agent D (04) ─┘
       │
       ├── phase 3 ── Integrator (05)       compileJava → build → runDatagen → one runServer
       │                  └── Sweeper (06)  fresh agent per error list, max 4 cycles
       │
       └── phase 4 ── the human, on a live client: rendering and GUI
```

Read [`../guides/PORT-ANY-MOD-26.2.md`](../guides/PORT-ANY-MOD-26.2.md) before running any of this
— the prompts are the executable surface of that plan, not a replacement for it.

## Files

| Prompt | Role | Gradle | Runs |
|---|---|---|---|
| [`00-ORCHESTRATOR.md`](00-ORCHESTRATOR.md) | Owns the environment, contracts, `PORT-STATUS.md`, commits, and hiring. Never asks the user anything | yes | once, top level |
| [`01-AGENT-A-core.md`](01-AGENT-A-core.md) | Build files, `fabric.mod.json`, entry points, registration, AccessWidener, resources | yes (alone in the checkout) | phase 1, alone |
| [`02-AGENT-B-logic.md`](02-AGENT-B-logic.md) | Blocks, items, block entities, world logic, networking, commands | **no** | phase 2 |
| [`03-AGENT-C-client.md`](03-AGENT-C-client.md) | Renderers, models, screens, HUD, key mappings, mixins | **no** | phase 2 |
| [`04-AGENT-D-datagen.md`](04-AGENT-D-datagen.md) | Data generators, diffed against the committed output as an oracle | **no** | phase 2 |
| [`05-AGENT-INTEGRATOR.md`](05-AGENT-INTEGRATOR.md) | Whatever still fails to compile, full build, datagen, the single smoke test | yes | phase 3 |
| [`06-SWEEPER.md`](06-SWEEPER.md) | A fresh agent handed one error list and the right to degrade | yes | up to 4 cycles |
| [`07-WEB-RECHECK.md`](07-WEB-RECHECK.md) | Verifying a signature against live sources when no ported reference exists | no | on demand |

Companion documents the prompts refer to live in [`../templates/`](../templates/): the
`PORT-STATUS.md` and `PORT-GAPS.md` skeletons, the findings format, and the report format every
agent ends with.

## Four rules that make the difference

Everything else is detail; these are what separate a port that finishes from one that burns a
budget and stops.

1. **Split by file, never by package.** Every `*Model` / `*Renderer` / `*Screen` belongs to the
   client agent wherever it physically lives. Overlapping ownership is the one failure that cannot
   be recovered from without redoing work.
2. **Only the orchestrator writes `PORT-STATUS.md`.** Agents hand their material over in the final
   report. Two parallel agents writing one document is a lost report.
3. **Two honest attempts, then degrade.** Disable the registration line, keep the original code in
   a comment, log it in three places. A green build matters more than feature completeness — and
   every cut is recoverable precisely because it was logged.
4. **A capped loop.** Each sweep must either reduce the error count or apply a cut; four sweeps
   maximum, then the orchestrator stops and writes down what is left. Hiring fresh agents forever
   is the main way a port consumes an entire token budget and delivers nothing.
