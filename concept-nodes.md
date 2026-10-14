# Concept: Palette Nodes

Status: concept, not built. Written 2026-10-14. Nothing here is committed to the backlog yet.
Home when built: **cNodes**, its own page in the Studio window (decided 2026-10-14), drawn on Colorgain's own grid (`.claude/c_design_guide.md` applies in full). "cNodes" is the working name used in code and conversation, like cLab; user-facing text and Vector titles say "Palette Nodes".

---

## 1. One-line pitch

Build a palette the way a colourist builds a grade in DaVinci Resolve: a graph of small, single-purpose nodes joined by wires, read left to right, every node showing its own live result. Unlike any palette tool today, the graph is a **recipe**: deterministic, explainable, proofable against a press condition, and shareable as a file.

## 2. Why this, why Colorgain

- Every palette tool on the market is a one-shot generator (press a key, get five colours) or a panel of sliders. Neither can answer "how did we arrive at this colour?", and neither can be re-run next year with a new brand colour.
- Colorgain's promise is enterprise colour management and proofing (`COLOUR-MANAGEMENT.md`). A node graph is the natural place to put the things only we can do: press landing, substrate, tolerance, provenance.
- Resolve proved that professionals trust node graphs. The image above this concept (a serial and parallel node tree with layer mixers) is the reference for *feel*, not for looks.

### Non-goals

- Not a game, not a visual-programming toy. No bouncing wires, no skeuomorphic knobs.
- Not an image grader. Nodes act on palettes, not pixels. (Image nodes only *read* pixels.)
- Not a replacement for the palette page. The palette page stays; cNodes is its own page and its output lands in the same palettes.
- No bundled third-party colour systems (Pantone, RAL, NCS) or press ICC profiles. See section 14.

---

## 3. Outcomes

What success looks like, each with the proof that would show it.

| # | Outcome | Proof |
|---|---|---|
| O1 | A designer builds a brand palette from a single seed colour in under two minutes without typing a hex | Timed run in the self-test harness's scripted session; graph file produced |
| O2 | The same graph, given a new seed, regenerates the whole palette identically on every run | Self-test: same graph + same seed, 100 runs, byte-identical output |
| O3 | Any output colour can be traced back through every node that touched it | Why trace returns the ordered node path and each intermediate colour |
| O4 | A palette can be landed on a named print condition with a pass or fail per colour against the verified tolerance | Press Landing node output table matches a hand-computed reference set |
| O5 | A palette can be made accessible by declaring rules, not by hand-tuning | Must node output meets every declared contrast and distinctness rule, and moves each colour the minimum distance |
| O6 | One graph produces light, dark and high-contrast variants without three copies of the work | Fork node emits N named palettes from one graph |
| O7 | A graph is a catalogue asset: saved, shared, migrated and versioned like a palette | Round trip through `.colcat` link, share zip and import |
| O8 | A client or printer can open a recipe and understand it without Colorgain | Graph exports to a readable PDF or HTML recipe card |
| O9 | The graph feels professional: Swiss, quiet, fast | Design-guide review, and 60 fps panning at 200 nodes |

---

## 4. Who it is for

- **Brand designer**: starts from a logo colour, needs a full system that holds up in print and on screen.
- **Product designer**: needs tokens for light and dark, with contrast guaranteed.
- **Print production lead**: needs to know what survives the press and what does not, with numbers.
- **Colourist or motion designer**: thinks in nodes already; wants palettes derived from a frame.
- **Agency lead**: wants a recipe to hand a client, and to re-run for the next client.

---

## 5. Journeys

### J1 Brand system from one colour

1. New graph. Drop a **Seed** (the client's logo colour, picked from the Library or typed in Lab).
2. Wire to **Harmony** (split-complement), then to **Ramp** on each result (tints and shades, even in ΔE).
3. Wire to **Role** to name the entries: primary, secondary, accent, neutral.
4. Wire to **Must**: text on background at least 4.5:1, no two accents closer than ΔE 10.
5. Wire to **Output: Palette**. It lands in the catalogue as a palette with its graph attached.

Outcome: a palette that can say how it was made and can be remade from a different seed.

### J2 Palette from a photograph

1. **Image** node: choose a photo, set colour count and weighting (by area, by salience).
2. **Pull to Master** to bring the result toward the brand master hue by 30%.
3. **Vision-Safe** so the result stays separable under deuteranopia.
4. **Output: Palette**.

### J3 Will it survive the press?

1. Take any palette (**Catalogue** node).
2. **Substrate** (coated, uncoated, kraft; from measured paper white).
3. **Press Landing** against the chosen print condition. Each colour is stamped with the colour it will actually print as, ΔE, and a pass or fail.
4. A **Scope** on the wire shows the gamut plot with the failing colours circled.
5. **Pull In** nudges failing colours the shortest distance back into gamut; **Compare** shows before and after.
6. **Output: Press Set** (the landed values) and **Recipe Card**.

### J4 Light, dark and high contrast from one graph

1. Build the base palette.
2. **Fork** into three branches: Light, Dark, High Contrast. Each branch carries its own **Shift** and its own **Must** rules.
3. **Output: Tokens** emits CSS variables and a Swift colour set for all three.

### J5 Reuse for the next client

Open the saved graph, swap the **Seed**, press Run. Everything downstream recomputes. Colours the designer pinned (**Lock**) stay fixed; everything else regenerates.

### J6 Audit

A client asks why the CTA colour is that exact value. Click the swatch; **Why** lights the path through the graph and lists each step with its intermediate colour and the setting that moved it.

### J7 Explore

Use **Scatter** (seeded) to produce twelve candidate palettes from a rule set, star the ones you like, keep their seeds. Nothing is lost; any starred result can be reproduced from its seed.

---

## 6. The graph model

### 6.1 Wires

| Wire | Colour in UI | Carries |
|---|---|---|
| **Palette** | ink (green end-cap, as the reference) | An ordered list of **entries** |
| **Rule** | accent (blue end-cap) | A condition: a print condition, a contrast target, a vision mode, a tolerance set, an illuminant |
| **Number** | grey | A single scalar, for driving a setting from another node (optional, phase 3) |

Palette wires may fan out (one output to many inputs). An input accepts one wire, except **Merge** and **Blend**, which accept several. No cycles; the editor refuses a wire that would make one.

### 6.2 An entry

Every colour on a palette wire is an entry, not a bare value:

| Field | Meaning |
|---|---|
| `id` | UUID, stable across runs where the entry is the "same" slot |
| `value` | The colour in the working space, as a full colour record (never hex alone), per `COLOUR-MANAGEMENT.md` |
| `role` | Optional name: background, text, accent, neutral, or free text |
| `locked` | Pinned; downstream generators may not change it |
| `status` | Optional proof stamp: in gamut, ΔE, pass or fail, with the rule that set it |
| `history` | Ordered list of (node id, setting snapshot, value before, value after) |

`history` is what makes **Why** possible. It is stored, not recomputed.

### 6.3 Evaluation

- Pull-based, left to right, memoised per node on (inputs, settings, seed).
- Deterministic: same graph, same inputs, same seed gives the same output on every machine. Floating-point work uses one fixed colour pipeline.
- A node with an unconnected required input shows a quiet empty state and passes nothing on; it never errors loudly.
- Recompute is incremental: only nodes downstream of a change re-run.

### 6.4 Seeds

Any node with randomness exposes a visible **seed** field and a re-roll button. Re-roll changes the seed; it never changes the algorithm. A graph without hidden randomness is a recipe.

---

## 7. Node catalogue

Each entry: purpose, inputs, settings, outputs. "P" is a palette wire, "R" a rule wire.

### 7.1 Sources

| Node | Purpose | In | Settings | Out |
|---|---|---|---|---|
| **Seed** | One colour to start from | none | colour (picker, Lab, or from Library); optional name | P (1 entry) |
| **Master** | The catalogue's Master Colour | none | which master (project or collection) | P (1 entry) |
| **Catalogue** | A saved palette or a member's colours | none | palette or member reference | P |
| **Image** | Dominant colours from a photo | none | file, colour count, weighting (area, salience), ignore skin, ignore background | P |
| **Spectrum** | Start from measured reflectance | none | spectral file (CGATS or CSV), illuminant, observer | P |
| **Swatches** | Hand-entered list | none | rows of colours | P |
| **Gradient Sampler** | N colours sampled from a gradient | none | gradient stops, count, sampling space | P |

### 7.2 Generators (make colours from colours)

| Node | Purpose | In | Settings | Out |
|---|---|---|---|---|
| **Harmony** | Complement, split, triad, tetrad, analogous, square | P | scheme, angle spread, working space (OKLCH default), keep source | P |
| **Ramp** | Tints and shades, even in ΔE | P | steps, from and to lightness, curve, ΔE evenness on or off | P |
| **Paint Mix** | Real pigment mixing | P (2 or more) | ratio per input, pigment model (Kubelka-Munk) | P |
| **Interpolate** | Path between two or more colours | P | steps, space, path (straight, via chroma peak, gamut-aware) | P |
| **Complete** | Fill gaps: add the colours a palette is missing | P | target count, fill rule (even hue, fill neutral, fill lightness) | P |
| **Neutrals** | Derive greys tuned to the palette | P | count, undertone strength, lightness range | P |
| **Scatter** | Seeded candidate generation within rules | P?, R? | seed, count, hue range, chroma range, lightness range | P (many) |

### 7.3 Modifiers (change colours)

| Node | Purpose | In | Settings | Out |
|---|---|---|---|---|
| **Shift** | Lightness, chroma, hue offsets | P | amounts, space, target (all, role, selected) | P |
| **Temperature** | Chromatic adaptation to a new white | P | from white, to white, adaptation method | P |
| **Pull to Master** | Draw colours toward a master hue | P, P (master) | strength, hue only or full | P |
| **Quantise** | Snap to a set | P | set (own library, grid, N colours), distance metric | P |
| **Harmonise** | Even out chroma and lightness across a set | P | target spread | P |
| **Mute** | Reduce chroma by an amount | P | amount, protect neutrals | P |
| **Invert** | Perceptual inversion for dark themes | P | lightness map | P |
| **Lock** | Pin entries so downstream nodes leave them alone | P | which entries | P |

### 7.4 Rule-driven nodes (the professional core)

| Node | Purpose | In | Settings | Out |
|---|---|---|---|---|
| **Must** | Declarative solver: satisfy rules with the minimum movement | P | rules (contrast pairs with WCAG 2 or APCA, minimum ΔE between entries, lightness bands, chroma ceilings), which entries may move, priority | P, plus a report (met or unmet, how far each moved) |
| **Vision-Safe** | Keep entries separable under colour-vision deficiency | P | deficiency types, minimum separation | P |
| **Surround** | Adjust for simultaneous contrast and appearance | P, P (surround) | viewing conditions (CAM16 surround, adapting luminance) | P |
| **Fade** | Age by lightfastness | P | years, exposure, pigment data source | P |

### 7.5 Proofing

| Node | Purpose | In | Settings | Out |
|---|---|---|---|---|
| **Substrate** | Put the palette on paper | P | substrate (measured white, from the Library's profiles), coating | P (statuses added) |
| **Press Landing** | Land on a print condition and stamp pass or fail | P, R (condition) | print condition, rendering intent, tolerance set (values from the verified ISO 12647-7 reference, never typed from memory) | P (landed values and stamps) |
| **Pull In** | Bring out-of-gamut or failing entries back the shortest distance | P | method, keep hue | P |
| **Print Condition** | Supplies the condition to wire into Press Landing | none | condition from ColorSync's installed list or the Library | R |
| **Tolerance** | Supplies a tolerance set | none | set, custom limits | R |

### 7.6 Structure and flow

| Node | Purpose | In | Out |
|---|---|---|---|
| **Role** | Assign names and roles to entries | P | P |
| **Pick** | Choose entries by index, role or rule | P | P |
| **Merge** | Combine palettes, with duplicate handling | P (many) | P |
| **Fork** | Split into named branches (Light, Dark, High Contrast) | P | P (many, named) |
| **Blend** | Mix two branches by a fraction | P, P | P |
| **Compare** | A and B side by side with ΔE per slot | P, P | P (passes A through), report |
| **Group** | Collapse a sub-graph into one node you can reuse | any | any |
| **Comment** | A note on the canvas | none | none |

### 7.7 Outputs

| Node | Produces |
|---|---|
| **Palette** | A catalogue palette (`.colpal`) with the graph attached |
| **Tokens** | CSS variables, Swift colour set, JSON design tokens |
| **Swatch Book** | A printable or exportable swatch book |
| **Press Set** | Landed values, per condition, as CGATS or CSV |
| **Recipe Card** | A branded client deliverable (PDF or HTML): cover, logo slot, the client's colours and type, the palette and how it was made. See 8.8 |
| **Share** | A share asset (`.colshr`) carrying graph and palette |

### 7.8 Probes (not nodes; attach to any wire)

| Probe | Shows |
|---|---|
| **Strip** | The swatches on that wire (every node already shows this) |
| **Gamut** | Chromaticity or a-b plot with entries, the working space and the print condition outlines |
| **Lightness** | L histogram and ordering |
| **Distance** | Matrix of ΔE between all entries |
| **Contrast** | Matrix of contrast between all pairs |
| **Vision** | The wire's colours under each deficiency |

---

## 8. Tools and surfaces

### 8.0 The cNodes page

cNodes is a page of its own in the Studio window, a sibling of the palettes view, not a mode inside it. It is registered in `.codex/c_layout_registry.md` when built, using the canonical region names.

| Region | Holds |
|---|---|
| Rail1 (library rail) | A "Palette Nodes" entry beside the palettes view; opening it shows the catalogue's graphs |
| Rail2 (context rail) | The graph list for the current member, and the node inspector when a node is selected |
| Page | The canvas, with the node-add bar and the run, bypass and solo controls in its Actionbar |
| Page footer | The probe strip: scope for the selected wire, Why panel for a selected swatch |
| History rail | Snapshots and diffs of the graph |

Entry and exit points:

- **From the palette page**: an "Open as graph" action on any palette that was made by a graph opens it here; on any other palette it offers "Rebuild as graph" (a Catalogue source feeding an Output, ready to extend).
- **From the library rail**: new graph, open graph, recent graphs.
- **Launch flag**: `--cnodes` opens the Studio window on this page; `--cnodes "<graph name>"` opens that graph. Same pattern as `--palettes` and `--lab`.
- **Outputs** land in the palettes view as ordinary palettes with a link back to the graph.
- The page keeps its own view state (zoom, pan, selection, open probes) per graph, not in the graph file.

### 8.1 Canvas

- Infinite, pan and zoom, snap to the 12-column grid (`Design.App`).
- Wires are orthogonal with soft corners, never splines. Parallel wires bundle.
- Node = a small card: name, strip of live swatches, port dots, one headline setting. Selected node is outlined in the accent.
- Auto-layout button lays the graph out left to right in tidy columns. Manual layout always wins until asked.
- Keyboard first: add node by typing its name (palette of nodes), connect selected nodes, group, lock, run.

### 8.2 Inspector

Opens in the context rail for the selected node: all settings, the node's input and output strips at full size, notes, and a **seed** control where relevant. Same panel primitive as the rest of the app.

### 8.3 Why (provenance)

Click any swatch on any strip. The path from source to that swatch highlights; a panel lists each step as: node, setting that acted, value before, value after, ΔE of the step. Copy as text for a client email.

### 8.4 Run, bypass, solo

- Each node can be **bypassed** (passes input through) or **soloed** (graph evaluates only up to it).
- A global **Run** shows the output; live mode recomputes on every change.

### 8.5 Snapshots and versions

- Name a snapshot of the graph and its outputs; diff any two (settings changed, entries changed, ΔE per slot).
- Restores never overwrite: they create a branch.

### 8.6 Library of nodes and groups

- Saved **Groups** become reusable nodes ("Brand Core", "Accessible Neutrals") shared through the catalogue.
- **Starter graphs ship with the app (decided 2026-10-14).** Four, one per journey, each marked "Example", editable, and saved as the user's own copy on first edit so the shipped original never changes:
  1. Brand from one colour (J1)
  2. Palette from a photograph (J2)
  3. Will it survive the press? (J3)
  4. Light, dark and high contrast (J4)
- Each ships in the phase that delivers all its nodes (the first in Phase 1). Starter graphs are bundled with the app, not written into the user's catalogue until opened.
- **They are tests too:** the self-test runs every starter graph on every build and compares the output with a stored reference, so a node change that alters a shipped result fails the build.

### 8.7 Compare view

Two outputs side by side: swatches, ΔE per slot, contrast deltas, gamut overlay.

### 8.8 Export

Recipe card (PDF or HTML), tokens, press set, share package.

**The recipe card is a client deliverable (decided 2026-10-14), not a technical dump.** It is built from templates:

- A cover (project name, date, logo slot), the palette as large swatches with names and roles, a "How it was made" spread (the graph drawn small, the key decisions in plain words), proof stamps where Press Landing ran, and the accessibility results where Must ran.
- Branding comes from the member's information pack: logo, brand colours, type. A template with no branding set falls back to Colorgain's own Swiss look.
- The full technical record (every node, setting, seed and Why path) follows as appendix pages, so the card still works as an audit trail. The appendix can be switched off.
- Templates are catalogue assets, so an agency's house template travels with the catalogue and shares like any other asset. Colorgain ships one default template; more are Phase 3. Each export stamps the graph's id and the commit of the app that ran it.

---

### 8.9 Heritage: palettes remember their graph

Decided 2026-10-14. A palette made by a graph keeps its provenance wherever it goes.

- **Stored on the palette.** The palette asset (`.colpal`) gains an optional `heritage` block: the graph id, a hash of the graph as it ran, the app version, the run date, and an **embedded copy of the graph as it ran** (small plain JSON). Each entry already carries its own `history`. A palette without the block is unchanged and needs no migration.
- **Rebuildable anywhere.** "Rebuild" re-runs the embedded graph and reproduces the palette, even if the live graph asset is missing, was edited, or the palette arrived in a share on another Mac.
- **One source of truth.** The live graph asset is the one you edit; the embedded copy is a frozen record of the run. If the live graph has changed since, the palette says so and offers three actions: open the live graph, open the embedded one as a new graph, or rebuild from the embedded copy.
- **The wire-node icon.** Any palette with heritage shows a small wire-node mark (two nodes joined by a wire, drawn in the guide's line weight) beside its name in the Library rail, the palettes view and the palette's header. Tooltip: "Made in Palette Nodes". It is the only mark of heritage; palettes without it show nothing.
  - **Intact:** the mark in ink. The palette still matches what the graph produced.
  - **Edited since run:** the mark with a small dot. Entries were changed by hand after the graph ran; the Why trace is kept and flags the edited entries.
- **Why on the palettes page.** Select a swatch on a palette with heritage and "Why" opens the trace in the page's footer, with "Open as graph" to jump to the cNodes canvas on that graph, selection kept.
- **Rule:** a trace is never hidden or silently dropped. A hand edit adds a step ("edited by hand, value before, value after"); it does not erase the steps before it.
- **Exports:** the history travels in shares and the recipe card appendix in Phase 3 with Share; a palette exported as plain tokens carries no heritage.

## 9. File and catalogue

- The graph is an **asset**, plain JSON, like every other asset: extension `.colgph` (decided 2026-10-14), linked from `.colcat` by id, kind and path. The name carries no developer prefix.
- It stores nodes (type, id, position, settings, seed), wires, snapshots, notes, and the app version that last ran it. It does not store computed palettes beyond a cached output for fast open, which is verified against a recompute on load.
- Folders follow the structure: a graph sits with the member it belongs to, or in `Library/Graphs` for loose ones.
- Every entry and node has a UUID and a changed date (server sync later).
- A `.colshr` share carries the graph, the palette and the manifest of SHA-256s.
- A palette made by a graph carries a `heritage` block (section 8.9) with an embedded copy of the graph as it ran; the palette stays valid and readable without it.
- Never writes an earlier catalogue shape. Opening a catalogue that has no graphs is a no-op.

---

## 10. Design rules

Follow `.claude/c_design_guide.md` first; only the items below are specific to this page.

- Helvetica Neue, the ten text styles, sentence-case labels starting with a capital, no type under 11.
- Ink on warm paper. Colour appears only where it is data (swatches) or state (selection, rule wire).
- Node cards sit on the 12-column grid; ports align to the baseline.
- Dynamic words (node results, error text) get fixed-height boxes and are rewritten to fit; nothing beneath them moves.
- Buttons come only from `ButtonStyle` in `Buttons.swift`.
- Measure the running app from a screenshot before reporting any layout change; use `--snap`.

---

## 11. Phasing

### Phase 1 : prove the idea (the thin slice)
Canvas, wires, entries with history, evaluation, seeds. Nodes: Seed, Image, Harmony, Ramp, Shift, Role, Must, Press Landing, Print Condition, Output: Palette. **Why**. Strip probe. Save as asset. Starter graph 1 (Brand from one colour). Heritage on made palettes: stored graph, wire-node icon, Why on the palettes page.

### Phase 2 : professional depth
Substrate, Tolerance, Pull In, Compare, Fork, Merge, Vision-Safe, Surround, Lock, Group, Gamut and Distance probes, snapshots and diff, Tokens outputs, and the Recipe Card with one default branded template.

### Phase 3 : the unusual ones
Paint Mix, Fade, Spectrum, Scatter with starring, Number wires, reusable group library, Share, the remaining starter graphs as their nodes land, Swatch Book, more Recipe Card templates (house templates as catalogue assets).

### Phase 4 : scale
Performance (large graphs), templates per industry, scripting hooks, Windows port after Mac release.

---

## 12. Acceptance criteria (draft)

As proven by the self-test and a command Rick can re-run:

1. **Determinism**: a fixed graph and seed produces identical palettes across 100 runs and across a relaunch.
2. **History**: for each of 20 sample entries, the Why path ends at a source node and every step's before and after chain without gaps.
3. **Must**: for a set of 10 rule cases, every declared rule is met, no entry moves more than the minimum found by an exhaustive reference search, and locked entries do not move.
4. **Press Landing**: stamps match a reference table computed independently, and tolerance values are read from the verified reference file, not constants in code.
5. **Round trip**: save, close, reopen gives the same graph; share and import gives the same graph on another catalogue.
6. **No cycles**: the editor refuses a wire that would form one, with a clear message.
7. **Performance**: pan and zoom at 60 fps with 200 nodes; edit-to-result under 100 ms for graphs of 30 nodes on a typical laptop.
8. **Page**: `--cnodes` opens the Studio window on the cNodes page, `--cnodes "<name>"` opens that graph, and "Open as graph" on a graph-made palette lands on the same canvas with the same selection.
9. **Starter graphs**: each shipped graph runs in the self-test on every build and matches its stored reference; opening one for editing creates a copy and leaves the bundled original unchanged.
10. **Heritage**: a palette made by a graph carries the heritage block; deleting the live graph and pressing Rebuild reproduces the palette byte for byte from the embedded copy; the wire-node icon shows on every such palette and on none without one; editing an entry by hand changes the icon to its edited state and adds a hand-edit step to the trace without removing earlier steps.
11. **Design**: page passes the design-guide review and the measured layout check.

---

## 13. Risks and trade-offs

| Risk | Handling |
|---|---|
| Randomness undermines the "recipe" promise | Visible seed on every random node; re-roll changes the seed only |
| "Gamey" feel | Orthogonal wires, grid snap, quiet type, no animation except state; review against the design guide before anything ships |
| Solver (Must) can disagree with itself | Report unmet rules and how far; never silently relax a rule |
| Image extraction varies by method | Method named on the node; fixed algorithm and seed |
| Press accuracy claims | Only values from the verified standard and the user's own profiles; every stamp names the condition and tolerance set it used |
| Scope creep from 40 nodes | Phase 1 ships ten; each later node must earn its place by a journey |
| Store sandbox | Graph files and profile access go through security-scoped bookmarks; press conditions from ColorSync's list |

---

## 14. Licensing and platform constraints

- No bundled Pantone, RAL or NCS data; users may bring their own licensed libraries. See memory `project-third-party-colour-licensing`.
- No bundled press ICC profiles; conditions come from ColorSync's installed list or the user's own files.
- ISO 12647-7 tolerances are read from the verified reference, never from memory.
- Direct download is the product; Store compatibility is kept by flagging, not by design constraint.
- Windows port waits for the Mac release.

---

## 15. Questions for Rick (all five decided 2026-10-14)

1. ~~Own page or a mode of the palette page?~~ **Decided 2026-10-14: its own page, cNodes** (section 8.0), with "Open as graph" on the palette page.
2. ~~Recipe card: branded or plain?~~ **Decided 2026-10-14: branded client deliverable**, with the technical record as optional appendix pages (section 8.8).
3. ~~Starter graphs or an empty library?~~ **Decided 2026-10-14: ship four starter graphs** (section 8.6), run by the self-test on every build.
4. ~~Why outside the graph?~~ **Decided 2026-10-14: yes**, on any palette with heritage; the graph is stored with the palette so it can be rebuilt, and a wire-node icon marks it (section 8.9).
5. ~~Extension~~ **Decided 2026-10-14: `.colgph`** (graph), in the `.col` plus three letters family.

---

## 16. Suggested Vector home

New objective under runway PR-23 (never a new runway): **Palette Nodes** (not "cNodes": Vector refuses titles that look like code, as it did "cLab"), with themes for Graph Engine, Node Library, Proofing Nodes, Canvas And Tools, and Graph Files. Titles must not look like code; descriptions open "As a …"; each needs "As proven by …" acceptance criteria (section 12 is the source). Check that `PR-23` returns "MMFFDev - Colour Picker" before any write.
