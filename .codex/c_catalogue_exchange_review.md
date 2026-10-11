# Catalogue storage and exchange review

2026-10-11. Discussion proposal; no engine, UI or user-data changes made by this review.

## Clarification after discussion

Rick confirmed he had compared the app-home tree with the exported catalogue tree. Catalogue A and Catalogue B are independent systems of work; matching stream names or asset content across them is legitimate, not a duplicate problem.

Revised recommendation: whole-catalogue import creates/registers a separate catalogue by default, with no cross-catalogue content deduplication. Handle only destination folder/name collisions and explicit reopen/copy decisions. Retain conflict review solely for an explicitly chosen merge into an existing catalogue or partial asset import. The earlier master duplicate proposal below applies to that merge journey, not normal standalone catalogue import.

Current code does NOT yet implement this separation: `Sharing.everyPlacement` offers only “This catalogue” for whole-catalogue imports, and `LibraryController.bringIn` merges into the active library/schema.

Whole-catalogue export currently carries selected unassigned palettes/typography from THAT catalogue, plus its loose colours and profiles; it does not export the app-home registry, other catalogues or Keys. Collection/member exports omit unrelated unassigned palettes, carrying selected work and its supporting data. A self-contained catalogue can include its own global Assets without sharing ownership with other catalogues.

All requested UX corrections remain in scope. No decision to migrate Library to Assets or implement the engine has been made during this discussion.

## Verified against Rick's files

Compared `/Users/rick/Desktop/Colorgain New Build/Catalogues/MMFFDev - 001` with `MMFFDev - 001.colshr` in the app home, without extracting over or modifying either.

- Export contains 165 catalogue files plus `manifest.colmanifest`. All 165 paths exist in the live catalogue. The only additional live file (excluding Finder metadata) is `MMFFDev - 001.colhis`.
- Both version-3 indexes have identical `collections` and `libraryAssets`. Unassigned palettes are already at `Library/Palettes/*.colpal` in both. This particular archive does not demonstrate a different physical schema.
- Index differences are `id`, `createdAt`, `changedAt`, `activePalette`. All 165 common files differ bytewise; exporting rebuilds a catalogue in a fresh staging directory, giving it a new catalogue identity. Raw file hashes therefore cannot establish semantic duplicates.
- The zip holds files only, so empty directories such as Typography are absent when unzipped. Live writing creates all four Library pools. This explains another visible folder-tree difference.

The concern is nevertheless valid: the UI selection, ownership rules and conflict handling do not consistently express the disk model.

## Current implementation and defects

| Area | Evidence | Consequence |
|---|---|---|
| One canonical disk writer | `Model.swift:1096`, `CatalogueTree.swift:597`, `Sharing.swift:250` | Live saves and staged exports already use CatalogueTree.write. Extend this common layer; do not create a second export layout. |
| Global assets | `CatalogueTree.swift:760` | Library means assets in this catalogue with no member, plus loose colours and catalogue profiles. It is not an app-wide library shared by every catalogue. |
| Selection leaks | `Sharing.swift:209–220`, `:665–671` | Catalogue export includes unused colours and all profiles independently of the visible palette ticks. Catalogue import also appends colours, profiles and templates without applying all corresponding selection decisions. The chooser only exposes two Library pools. |
| Nested groups | `Sharing.swift:128–131`, `:176–191`; compare `Schema.swift:66–79` | Chooser renders the flat folder array as siblings. Work-group cuts keep the selected folder and directly placed members, not its complete descendant tree and ancestor chain. Full export can preserve a schema that the chooser displays incorrectly. |
| Duplicate classification | `Sharing.swift:453–495` | Priority is same UUID, then a SET of colour keys, then same name in a destination. Colour order/repetition, notes, profiles, purposes and typography fonts/sizes are not compared. Same UUID with edited content is not distinguished from an identical item. Only the first match is recorded. |
| Batch policy exists but is obscure | `StudioShare.swift:272–279` | “For every twin” chooses a fallback action. It is not a clear master panel, and per-item overrides remain separate. Default is Keep Both. |
| Skipping containers loses new descendants | `Sharing.swift:587–631` | Skip on an existing collection/member stops processing its descendants. “Only import new assets” cannot safely be implemented by applying Skip to every duplicate. Existing containers must be matched and traversed. |
| Replacing a member is destructive | `Sharing.swift:633–645` | Deletes all existing member palettes before processing incoming child decisions, including a partial import. Separate merge and explicit replacement semantics are essential. |
| Nested ID remapping | `Sharing.swift:604–610` | Keep Both regenerates group IDs but does not remap their parent IDs. Copies of nested structures need a complete identity map. |
| Profiles on partial import | `Sharing.swift:665–671` | Profiles are appended only in the catalogue branch, although export can carry dependencies for a member or collection. These imports can retain references without adding their profiles. |
| Save/result coupling | `StudioShare.swift:586`, `Controller.swift:148` | Import reports an outcome and advances even though apply handles save errors internally rather than returning success. Schema is replaced before apply. Confirmation must reflect successful persistence. |
| Atomicity | `CatalogueTree.swift:786–825` | Individual files and the final index use atomic writes; the entire multi-file change is not an atomic transaction. A failure partway through needs recovery. |
| Journey wording | `StudioWindow.swift:893`, `StudioShare.swift:243–279` | Shared title is “Share”; empty import creates an inert row; single-choice export gets an unnecessary selector; no Cancel button. |

## Proposed canonical layout

Keep Assets **per catalogue**, available globally within that catalogue, unless we explicitly decide to introduce an app-wide shared asset store.

```text
App Home/
  colorgain.coldata
  Keys/default.colkeys
  Catalogues/<Catalogue>/                 # or a separately chosen catalogue location
    <Catalogue>.colcat
    <Catalogue>.colhis
    Assets/
      Palettes/*.colpal
      Typography/*.coltyp
      Swatches/*.colswa
      Profiles/*.colprf
    <Schema collection>/<nested groups>/<member>/<schema asset groups>/...
```

Assets replaces the reserved Library folder. Assigned palettes remain inside their schema member. Do not duplicate them into Assets. Shared profiles required to interpret selected work travel even when optional global Assets are excluded; show these separately as “Required supporting assets”.

A .colshr contains this same catalogue-relative structure plus its manifest. Empty-directory handling must be explicit: either include directory entries or record the required directories and reconstruct them during import. History, app preferences, keys and migration backups are not included in a normal content export. Label this distinction; a portable export is not a complete backup.

Preserve source catalogue identity as provenance in the manifest. Define the staged document identity deliberately rather than generating a fresh identity as a side effect of writing. Compare semantic content, never catalogue-envelope timestamps or raw serialization alone.

## Shared engine

Use one asset inventory and path resolver for live writes, setup, migration and packaging. Build an immutable export/import plan before touching destination data.

1. Snapshot source/destination revision and inventory IDs, ownership, relative paths and dependencies.
2. Resolve selected schema descendants recursively, retaining necessary ancestors. Add optional Assets and mandatory dependency closure separately.
3. Validate archive, supported versions, unique safe paths, references and bounded sizes. Current manifest checks reject old versions but do not reject unknown future versions.
4. Choose destination BEFORE classifying matches. Compute all candidate matches, not only the first.
5. Apply batch policies and explicit overrides to a plan. Show totals and changes. Recompute if source/destination changes.
6. Prepare files and index in staging; journal the transaction and preserve rollback data. Commit with a recoverable multi-file protocol; update memory/history and report success only after persistence succeeds.

### Matching rules

| Classification | Meaning | Default proposal |
|---|---|---|
| Identical content, same name | Full semantic payload matches | Reuse/skip redundant asset |
| Identical content, different name | Same payload, alternate label | Separate review group; retain incoming name unless user chooses reuse |
| Same identity, changed content | Same UUID, divergent payload | Conflict; keep existing unless explicitly resolved |
| Same name, different content | Naming collision only | Import separately with a unique filename; never auto-replace |
| Similar colours | Same colour set but different order/styling/metadata | Optional similarity information, not a duplicate |
| Matching container | Existing collection/group/member | Merge selected descendants without replacing its schema or skipping new children |

Use versioned canonical semantic hashes per asset kind. Exclude identity, file paths, envelope dates and display name from the content hash. Preserve palette order/repeated entries and meaningful colour definitions, profiles, purposes, notes and tags; typography must include font/style/size/pairing data. Resolve referenced dependencies by semantic content rather than UUID alone. A secondary visual-similarity hash can group suggestions but must never trigger destructive deduplication.

Ownership is separate: the current model permits one member per palette. Reusing an asset found in another member must not move it. Until shared references are supported, create an independent owned copy when a different member needs it. This constraint also applies to same-content/different-name decisions.

### Master import panel

After destination and contents selection, show:

“This catalogue includes global Assets: palettes, typography and loose colours not assigned to a member.”

Assets choice: **Only assets I don't already have / All included assets / Don't import global Assets**. Required supporting assets remain visible and explained.

Duplicate policy: **Skip identical duplicates** (recommended), **Keep all as separate copies**, or **Review matches**. Separate changed-identity conflicts and same-content/different-name groups. Never label a broad destructive operation “Accept all”. Replacement is explicit and shows affected items. Each policy shows counts; per-item overrides are optional and can be reset to the master policy.

Finish with a preview of destination paths and counts for new, reused, renamed, conflicting and excluded items. No mandatory file-by-file questioning.

## Journey corrections

- Export title: Export. Import title: Import. Keep proper grid anchors and row primitives.
- Single available export level: fixed selected summary, no checkbox, hover ribbon or fake action. Multiple levels choose export scope; actual independent contents use checkboxes. Keep the required root fixed; do not force the first optional child to be included.
- Import before file selection: short explanation, Choose File and Cancel. No empty tree/ribbon. Render a contents tree only after a file is validated.
- Provide Cancel throughout both wizards before commit, restoring the launching page (current onLeave always returns to catalogue). Clear staging on cancellation.
- Selection ribbons appear only on controls with meaningful actions. Audit preview trees separately from editable trees.
- Export adds “Include global Assets” with plain explanation and counts. Selected work's dependencies must remain complete even when unchecked.

## Setup and compatibility

Reviewed first-open create/build and existing-catalogue adoption in `StartupSetup.swift:31–61`, `StudioSplash.swift:245–300`; earlier assistant migration/open flow in `SetupAssistant.swift:692`; storage save in `Model.swift:1096`; legacy conversion in `Migration.swift`.

- New setup already uses the common writer. Updating its layout updates new catalogues as well.
- Existing catalogue adoption validates before opening; older layouts offer migration with backup. Add an explicit versioned Library-to-Assets migration here, and to normal storage loading.
- Reserve Assets against schema naming collisions. If both Library and Assets exist, reconcile by identity/content with a report; never blindly replace either folder. Preserve unknown user files.
- Keep reading legacy Library archives. Normalize imported paths through the common resolver.
- Update move-home/copy/watch/reconciliation paths and reserved-name tests, not just the main writer.
- Retire obsolete assistant wording referring to .colcatalogue/library.json as the main formats.
- App manifest and Keys stay at app-home level. .colcat, asset documents and .colhis remain separate catalogue data. Thus colorgain.coldata is not the only file created/maintained by setup.

## Delivery and proof

First agree ownership and duplicate semantics. Then implement common inventory/plans and regression fixtures; migrate layout; wire the new wizard; verify native journeys with the grid. No live migration should be performed merely to test the proposal.

Required fixtures: nested groups of at least three levels; partial subtree export; identical content under different names/IDs; same ID with edits; reordered/repeated colours; different typography using the same colours; global Assets excluded; required profiles included; skipped existing collection with new descendants; same-content assets belonging to different members; Keep Both parent-ID remapping; partial member import preserving unselected work; old Library archive; conflicting Library/Assets folders; failed save/recovery; import cancel; unknown format version; missing/tampered files.

Prove live → export → fresh import gives equal ownership, schema and semantic payload at the same relative paths, except explicitly excluded data and documented identity decisions. Also prove repeated import with “new only” adds nothing on the second run.

## Decisions for discussion

1. Recommendation: Assets is catalogue-wide, not shared across all catalogues. An app-wide store would require a separate ownership/reference design.
2. Recommendation: exclude optional global Assets by default when exporting a selected member/collection; offer inclusion for whole-catalogue export with a clear count.
3. Recommendation: treat same-content/different-name items as a separate group and preserve their labels by default; allow explicit reuse where ownership permits.
4. Recommendation: merging an existing member never deletes work absent from a partial import. Full replacement belongs behind a separate, explicit action.
