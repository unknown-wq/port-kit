<h1 align="center">
  Minecraft 26.2 Port Kit
</h1>

<p align="center">
  <b>Field notes, recipes and tooling for porting a Minecraft mod to Fabric / Minecraft 26.2.</b><br>
  Assembled from eight real ports, each driven to a green dedicated server —
  NeoForge → Fabric, Forge → Fabric, and Yarn Fabric → Mojang-named Fabric.
</p>

<p align="center">
  <img alt="Minecraft 26.2" src="https://img.shields.io/badge/Target-Minecraft%2026.2-brightgreen?style=for-the-badge">
  <img alt="Fabric" src="https://img.shields.io/badge/Loader-Fabric-1976d2?style=for-the-badge">
  <img alt="Java 25" src="https://img.shields.io/badge/Java-25-orange?style=for-the-badge">
  <img alt="Docs in Russian" src="https://img.shields.io/badge/Docs-Russian-lightgrey?style=for-the-badge">
</p>

---

## What this is

Porting a mod to Minecraft 26.2 breaks in ways that no pre-2026 tutorial — and no language
model's training data — covers. `ResourceLocation` no longer exists. The game ships
unobfuscated, so there are no mappings and no Yarn. Java is 25, Gradle is 9.x, item models are
data-driven, the bake pipeline changed, and half the NeoForge hooks a mod relies on have no
counterpart anywhere.

This repository is the accumulated answer to all of that: **what actually breaks, what it becomes
in 26.2, and how it was verified** — collected while porting real mods rather than read off a
changelog. Every recipe here was paid for once already.

> **The documents are written in Russian.** They are working notes, kept verbatim rather than
> retranslated, because a mistranslated API signature is worse than no note at all. Code, symbols,
> file paths and commands — the part that matters — are language-neutral.

**Provenance.** The kit grew out of five ports: `Fabric-LuckyTNTMod` (Yarn Fabric 1.21 → 26.2),
`simple-planes` (NeoForge 1.21.1 → Fabric 26.2), `LostCities` (Forge 1.20 → a new Fabric mod),
`desolation` (Fabric 1.21.6 → 26.1.2 → 26.2) and
[Domum Ornamentum](https://github.com/unknown-wq/Domum-Ornamentum) (NeoForge 26.1 → Fabric 26.2).
It was then used, and extended, by the ports of
[BlockUI](https://github.com/unknown-wq/BlockUI),
[Structurize](https://github.com/unknown-wq/Structurize) and finally
[MineColonies](https://github.com/unknown-wq/minecolonies) — the largest of them, and the one whose
findings about runtime, production artefacts and false "no counterpart on Fabric" notes are the most
recent material here.

---

## Where to start

| If you want to… | Read |
|---|---|
| **Port a mod, start to finish** | [`PORTING-BUNDLE-26.2.md`](PORTING-BUNDLE-26.2.md) — the whole kit as one self-contained file |
| Read it in pieces instead | [`guides/PORT-ANY-MOD-26.2.md`](guides/PORT-ANY-MOD-26.2.md), then the rest of [`guides/`](guides/) |
| **Run a port with a team of agents** | [`prompts/`](prompts/) — orchestrator, four workers, integrator, sweeper |
| Start the port's own documents | [`templates/`](templates/) — `PORT-STATUS.md`, `PORT-GAPS.md`, findings, agent report |
| Fix one specific compile error | [`guides/PORT-CHEATSHEET.md`](guides/PORT-CHEATSHEET.md) |
| Know what breaks between two versions | [`guides/PORTING-GUIDE-26.2.md`](guides/PORTING-GUIDE-26.2.md) |
| Automate the mechanical renames | [`scripts/`](scripts/) |
| See how a finished port actually went | [`ports/`](ports/) |

Three facts that get lost most often, repeated here because they invalidate most existing advice:

1. The target is **`26.2`**, not "1.26.2" — since 2026 the scheme is `year.drop.hotfix`.
2. From 26.1 the game is **unobfuscated**: there is no `mappings` line in Gradle, Java is **25**,
   Gradle is 9.x. Forge/NeoForge sources are already on Mojang names, so nothing is renamed —
   the APIs themselves break instead.
3. **`ResourceLocation` does not exist** in 26.2. The class is
   `net.minecraft.resources.Identifier`, and the factory is `Identifier.fromNamespaceAndPath(...)`
   — `Identifier.of(...)` is a Yarn name and does not exist either.

**The only sources of truth are the decompiled game sources (`/opt/mc-src`) and mods already
ported to 26.2. Where they contradict these documents, they are right.**

---

## Layout

```
.
├── PORTING-BUNDLE-26.2.md   # the entire kit as one file — start here
├── guides/                  # the same material as separate documents
├── prompts/                 # ready-to-paste prompts for an agent team, one per role
├── templates/               # skeletons for the documents a port produces
├── scripts/                 # mass renames, import resolution, recipe conversion, type checking
├── findings/                # raw per-agent notes from a port, not yet folded into the guides
├── ports/                   # the record of each completed port: status, gaps, plan
└── ../gradle-dist/          # vendored Gradle 9.6.1 + toolchain installer, at the repo root
```

This copy of the kit lives inside the MineColonies port, because that is the port that extended it
last. The standalone home is [unknown-wq/port-kit](https://github.com/unknown-wq/port-kit).

### `guides/`

| File | What it is |
|---|---|
| **`PORT-ANY-MOD-26.2.md`** | **The plan.** Choosing a route, setting up the environment, freezing contracts, splitting the work, the degradation rule, acceptance criteria |
| `NEOFORGE-TO-FABRIC-26.2.md` | NeoForge → Fabric in one hop: build and runtime findings, lessons from working in parallel |
| `NOTES-A.md` | Core: entry points, registration, menus and containers, recipes, reload listeners, data JSON. Plus `setId` on blocks whose constructors take no `Properties`, the full NeoForge → Fabric datagen map, the missing `ExistingFileHelper`, and item models from 1.21.4 on — the most expensive break in the range |
| `NOTES-B.md` | Logic: entities, synched data, `ValueInput`/`ValueOutput`, upgrades, networking. Plus `RenderDataBlockEntity#getRenderData()`, `placementInfo()`, recipe synchronization, the table of dead NeoForge block/item hooks, and `PacketDistributor` → `PlayerLookup` |
| `NOTES-C.md` | Client: initialization, renderers and render states, models, screens, sounds, mixins. Plus `BakedModel` → `BlockStateModel`, `IGeometryLoader` → `ModelLoadingPlugin` (the JSON key is `fabric:type`, not `loader`), `ModelData` → `emitQuads`, `IQuadTransformer` → `QuadEmitter`, tints, render layers |
| `PORT-MOD-26.2.md` | Verified rename tables by area. Useful for a Forge source too — the right-hand column is simply the 26.2 name |
| `PORT-CHEATSHEET.md` | Ready fixes for the compile errors that survive mass renames |
| `PORTING-GUIDE-26.2.md` | Technical reference: why a naive port breaks, the per-version hit list from 1.21.2 to 26.2, the toolchain matrix |

### `prompts/`

The kit's plan made executable: one prompt per role, with the ownership rules, the confirmation
discipline and the traps of that specific zone already written in. See
[`prompts/README.md`](prompts/README.md) for how a port runs end to end.

| Prompt | Role | Gradle |
|---|---|---|
| `00-ORCHESTRATOR.md` | Environment, recon, contracts, `PORT-STATUS.md`, commits, hiring. Asks the user nothing | yes |
| `01-AGENT-A-core.md` | Build files, `fabric.mod.json`, entry points, registration, AccessWidener | yes, alone in the checkout |
| `02-AGENT-B-logic.md` | Blocks, items, block entities, world logic, networking, commands | no |
| `03-AGENT-C-client.md` | Renderers, models, screens, HUD, key mappings, mixins | no |
| `04-AGENT-D-datagen.md` | Data generators, diffed against the committed output as an oracle | no |
| `05-AGENT-INTEGRATOR.md` | Everything that still fails, full build, datagen, the single smoke test | yes |
| `06-SWEEPER.md` | A fresh agent per error list, with the right to degrade. Four cycles maximum | yes |
| `07-WEB-RECHECK.md` | Verifying a signature against live sources when no ported reference exists | no |

### `templates/`

| Template | What it is for |
|---|---|
| `PORT-STATUS-TEMPLATE.md` | The port's living document: toolchain, rules, contracts, ownership, checklist, deviations, disabled content, verification. Only the orchestrator writes it |
| `PORT-GAPS-TEMPLATE.md` | Every cut and degradation, with what it looks like in game, how to repair it, and a priority — plus the check list for the human on a live client |
| `FINDINGS-TEMPLATE.md` | The was → became → confirmed-at → caveat format. This is what becomes the next version of the guides |
| `AGENT-REPORT-TEMPLATE.md` | The seven sections every agent ends with. The report is an agent's only channel outward — it writes no shared document and makes no commits |

### `scripts/`

| Script | What it does |
|---|---|
| **`port-resolve-imports.py`** | Walks every `import net.minecraft.*`, looks the class up in the decompiled sources, and rewrites the import when it is found in exactly one package. Fixes every class that merely moved, with no manual edits. Ambiguous and missing ones are left for a human. Needs `/opt/mc-src` |
| `typecheck.sh` | Type-checks the tree with `javac` against Loom's cached jar — a fast error list without invoking Gradle. Supports filtering by package and a count-only mode |
| `fix-recipes.py` | Converts recipe JSON to the 26.2 shape: ingredients become flat strings (`{"item":"X"}` → `"X"`, `{"tag":"X"}` → `"#X"`) |
| `build-bundle.sh` | Rebuilds the appendix of `PORTING-BUNDLE-26.2.md` from `prompts/` and `templates/`, so the single-file kit stays in sync. Idempotent; touches nothing above the appendix marker |
| `port-rename*.sh`, `port-rename6.pl` | Mass renames. Written against a Yarn source; a NeoForge source needs a shorter set of its own — how to write it is in the plan. Two in the Perl one are universal: `.random` → `.getRandom()` and `.isClientSide` → `.isClientSide()` |
| `port-mechanical-renames.py` | The NeoForge → Fabric rename pass, written for this port: package moves and pointwise method renames rather than class names, which is what a Mojang-named source actually needs |
| `port-mc-imports.py` | `port-resolve-imports.py` specialised for a large tree: same lookup, batched over thousands of files |
| `mark-structurize.py` | Marks the call sites that depend on a library still being ported, so work can continue around a dependency that is not ready yet |

### `findings/`

Per-agent notes taken **during** a port, before they were folded into the guides — the rawest and
most recent material in the repository, and the reason this repository exists at all. Currently:

- [`findings/structurize/`](findings/structurize/) — seven files: six covering the foundation,
  networking and events, world logic, GUI, rendering and integration, plus the acceptance ladder —
  which is also where you will find how to prove a broken description id or a missing loot table
  **from a dedicated server console**, with no client at all.
- [`findings/blockui/`](findings/blockui/) — the **moment of mod init**: what exists when your entry
  point is called and what does not. Fabric invokes entrypoints from inside `Minecraft.<init>`, so
  `getInstance()` is non-null while its fields are not; and a crash in a shared library names the
  wrong mod in the report header. Also the headless-test half: which vanilla classes work in a test
  JVM and which quietly do not.
- [`findings/minecolonies/`](findings/minecolonies/) — the **runtime** layer specifically: twelve
  defects that compile cleanly and only appear when something actually runs. Item components are no
  longer bound at registration, and that one change alone breaks static initialisers, the whole of
  datagen, recipe decoding and every reload listener — in four places that each look like a separate
  bug. Read it before running a port's first `runDatagen`.
- [`findings/audit/`](findings/audit/) — the **port note itself**: a comment saying "this API has no
  counterpart on the target platform" is a claim, not a fact, and it is checkable against the dependency
  artefact in one `unzip -l`. In one port, 43 such claims across 37 files; the most frequent subject was a
  class that **five other files in the same tree already imported and used**. Three of those false claims
  had silently disabled working game logic — `if (false)`, a dropped `||` operand, a class-name heuristic
  standing in for `instanceof` — none of which a compiler can see. Also the two mirror failures: a note that
  is literally true and still wrong because the behaviour moved rather than vanished, and a note that
  overstates the loss and so regenerates the same audit forever. Read it before triaging a port's `DISABLED`
  markers.
- [`findings/environment/`](findings/environment/) — the **production artefact**: defects that
  survive a green `build`, a green `runDatagen` and a green `runServer`, and are only reachable by
  installing the jar in a real Fabric client. An access widener has a compile half and a runtime
  half, and dev exercises only the first; the decompiled vanilla dump lies about access modifiers
  because it was produced with the transitive widener already applied; a stale jar in `mods/`
  silently shadows the nested copy, whatever the versions are. Read it when the port is "done".

### `ports/`

The record of each completed port, kept as the worked examples the guides refer to:

| Port | Files | What is interesting about it |
|---|---|---|
| [`ports/domum-ornamentum/`](ports/domum-ornamentum/) | status, gaps | NeoForge 26.1 → Fabric 26.2. The custom model pipeline: a `ModelLoadingPlugin` plus a `BlockStateModel` wrapper replacing NeoForge geometry loaders; datagen reproducing 746 of 746 oracle files |
| [`ports/blockui/`](ports/blockui/) | status, plan | NeoForge 26.1.2 → Fabric 26.2 with **no mixins at all** — every hook found a real Fabric API; AccessTransformer → AccessWidener |
| [`ports/structurize/`](ports/structurize/) | status, gaps | The largest of the three, and the first with mod dependencies: a compat layer reconstructed from call sites that then matched the real library exactly |
| [`ports/minecolonies/`](ports/minecolonies/) | status, agent brief | The largest port so far — 2051 files, 9650 compile errors, three mod dependencies. Nine agents over three waves; the brief is the document each of them read first. Datagen verified file by file against the previous version's output, including 3481 generated textures compared by pixel |

### `../gradle-dist/`

Gradle 9.6.1, split into RAR parts, plus `install.sh` which reassembles it and installs OpenJDK 25.
It sits at the repository root rather than inside the kit, because the mod's own build needs it too.
It is vendored because the Gradle wrapper cannot download through a restricted egress proxy —
GitHub release assets return 403. Run it once per machine:

```sh
../gradle-dist/install.sh                      # → /opt/gradle-9.6.1 and OpenJDK 25
export JAVA_HOME=/usr/lib/jvm/java-25-openjdk-amd64
/opt/gradle-9.6.1/bin/gradle --version         # 9.6.1
```

---

## The ports this kit was built from

| Mod | Port | Upstream |
|---|---|---|
| Domum Ornamentum | [unknown-wq/Domum-Ornamentum](https://github.com/unknown-wq/Domum-Ornamentum) | [ldtteam/Domum-Ornamentum](https://github.com/ldtteam/Domum-Ornamentum) |
| BlockUI | [unknown-wq/BlockUI](https://github.com/unknown-wq/BlockUI) | [ldtteam/BlockUI](https://github.com/ldtteam/BlockUI) |
| Structurize | [unknown-wq/Structurize](https://github.com/unknown-wq/Structurize) | [ldtteam/Structurize](https://github.com/ldtteam/Structurize) |
| MineColonies | [unknown-wq/minecolonies-fabric](https://github.com/unknown-wq/minecolonies-fabric) | [ldtteam/minecolonies](https://github.com/ldtteam/minecolonies) |

The mods themselves are the work of their original authors — the LDTTeam mods above belong to
[LDTTeam](https://github.com/ldtteam). This repository contains no mod code: only notes about
porting it.

## License

This kit is released under the **[MIT License](LICENSE)** — take any of it, for anything, with or
without credit.

That covers the notes, recipes, prompts, templates and scripts in this repository, which are the
work of this project. It covers nothing else: the mods the kit was built from remain under their
own licences, held by their own authors, and none of their code is reproduced here.

## Contributing

Ported something to 26.2 and hit a break that is not written down here?
[Open an issue](https://github.com/unknown-wq/port-kit/issues) or a pull request — a finding with
a verified source line is worth more than a whole chapter of guesswork.
