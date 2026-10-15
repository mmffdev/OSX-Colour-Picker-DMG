# Architecture — Handler File Management

Status: implemented; final target verification in progress. Baseline reviewed 2026-10-15 on `colorgain-main`, commit `21eac37`; plan committed and pushed first as `e61c06a`. This document records product architecture, source findings and acceptance tests; project working instructions remain in `.Codex/AGENTS.md`.

## 1. Agreed direction

One codebase, many UI/UX overlays. `Handler_File_Manager` is the spine; each format has a clearly named handler class in a matching Swift file under `FileHandlers/`. Existing implementations become adapters first, then move behind their handlers incrementally. Do not maintain two competing writers.

The manager coordinates discovery, opening, onboarding/import, validation, dependencies, saving, export, reconciliation, recovery, relocation, archival and removal. Format handlers understand their bytes and ownership contracts. UI overlays present plans and structured results; handlers never display alerts, file panels or permission prompts.

Retain the folder-based architecture, current extensions, colour precision and user-defined schemas. No blanket extension rename, database conversion or destructive migration is required.

## 2. Review scope and evidence

Reviewed production Swift sources for disk reads/writes, enumeration, moves, copies, deletion, file panels, alerts, bookmarks, watches, import/export and registry updates. Reviewed format models, existing self-test coverage, `Info.plist`, `Package.swift`, build scripts and Store source configuration. Generated build products were excluded. Sections 2–4 retain the original source findings. Implementation, failure-injection and native verification evidence appears in the sign-off ledger and section 14.

### Persistence and lifecycle touch points

| Source / symbols | Current responsibility | Migration destination |
|---|---|---|
| `AppData.swift`: `AppDataStore`, `AppPreferences` | Manifest read/update, settings, selected/default catalogue, old registry migration | App-data handler; preferences remain a consumer |
| `AppData.swift`: `KeyProfiles`, `AppHomeSeed` | Shortcut files; workspace seed and global assets | Key-profile handler; explicit manager creation plan |
| `AppData.swift`: `GlobalAssets`, `AssetTransaction` | Global/local composition, delta saves, snapshot journal/recovery | Manager scope coordination and transaction executor |
| `Sync.swift`: `Catalogues` | Registry, names, location, create/adopt/import, rename, home move, Bin | Manager catalogue lifecycle plans |
| `Sync.swift`: `SyncEngine`, `mergeLibraries` | Remote discovery, merge, push, backups/pruning | Manager I/O and conflict checks; retain merge domain logic |
| `Model.swift`: `LibraryStore` | Load, migration, reconciliation write-back, global composition, saves/mutations | Compatibility facade over manager |
| `CatalogueTree.swift`: `CatalogueTree`, document models | Scan/resolve, schema-to-folders, asset links, writes, removals | Catalogue handler; manager reconciliation/executor |
| `Catalogue.swift`, `ProjectFile.swift`, `LegacyTree.swift`, `Migration.swift` | Older documents, previous layouts, backups and conversion | Explicit legacy readers/migration adapters |
| `PaletteAssetHandler.swift` | Validated palette/typography codec, portable metadata | Palette and typography handlers sharing codec logic |
| `History.swift`, `FileVersion.swift` | History persistence, settings/history caches and file identity | History handler and shared revision tracking |
| `MetadataFilters.swift`: `MetadataFilterStore` | Catalogue filter data and manifest mirror | Catalogue/app-data handlers in one transaction |
| `Appbridge.swift`: `ASERegistry`, `AppbridgeStore` | Catalogue links, scanning, external ASE create/append/detach/delete, backup | ASE-registry handler plus ASE adapter |
| `ICCProfileLibrary.swift`, `ColourProfiles.swift`, `ColourEngine.swift` | Linked/system ICC records, resolving bytes, profile definitions and transforms | Profile handlers and ICC dependency adapter; retain colour maths |
| `PrintProfiles.swift`, `Proofing.swift` | Manifest print presets, `.colpro` exchange, `.colcal` configurations and embedded ICC | Print-profile/proof handlers |
| `Sharing.swift`, `Zip.swift` | Selection, staged archives, manifest/digest validation, import conflict handling | Share handler and archive infrastructure |
| `ColourQR.swift`, `SharingUI.swift` | QR/colour-file encodings, validation, insertion and UI file operations | QR handler; UI remains presenter |
| `Importers.swift`, `Exporters.swift`, `Helpers.swift`, `AdobeHelper.swift`, `helper/` | External colour formats, design packs, protected external destinations | External adapters; manager plans; preserve Store exclusions |
| `Bookmarks.swift`: `FolderAccess`; `Permissions.swift`, `PermissionGate.swift` | Machine-local grants and permission UI | Access provider; UI obtains requested grants |
| `WorkspaceStartup.swift`: `WorkspaceInventory`; `CatalogueOpen.swift` | Workspace validation, availability, initial sandbox folder grant | Manager inventory/open plan; startup overlay |
| `StartupSetup.swift`, `SetupAssistant.swift`, `SetupFrame.swift`, `StudioSplash.swift` | Workspace/catalogue creation, adoption and setup | Manager lifecycle consumers |
| `CatalogueWatch.swift`, `Controller.swift` | Watch events, reload, mutations, history, sync and alert presentation | Manager event/recovery coordination; controller consumes results |
| `main.swift`, `MainWindow.swift`, `SettingsWindow.swift` | Launch/document routing, menu and settings entry points | Typed manager dispatch |
| `StudioWindow.swift`, `StudioShare.swift`, `StudioSettings.swift`, `PrintProfileSelector.swift`, `ICCProfilePanel.swift`, `PrePress.swift`, `WorkspaceAnalysis.swift` | Catalogue actions, dialogs, sharing/profile/proof actions, image intake and sidecars | UI overlays over plans; domain actions stay behind handlers |
| `StudioWorkspace.swift`, `WorkspacePanels.swift`, `FormMemory.swift`, `Prefs.swift` | Image discovery/favourites, support state and preferences | Classify owned content versus transient/machine-local state before moving |
| `Projects.swift`, `Tags.swift`, `Typography.swift`, `Shortcuts.swift`, `ColourProfiles.swift` | Domain consumers of persisted library/settings | Retain domain logic; route resulting persistence through manager |
| `Info.plist`, `Package.swift`, `appstore/project.yml`, Xcode projects, build/signing scripts | Finder types, source inclusion, resources, target restrictions | Registry parity and both-target inclusion checks |

Peripheral disk uses (sampling snapshots, bundled help/reference resources, icon tools, diagnostics and UI prototypes) are not new `.col*` handlers. Inventory them as explicit infrastructure exceptions. Do not force rendering or colour-transform code into the manager.

## 3. Current file contracts and target handlers

| Format | Current owner / content | Planned class |
|---|---|---|
| `.coldata` | `AppDataStore`: workspace registry/settings; also historical project data | `Handler_File_App_Data` |
| `.colcat` | `CatalogueFile` v3; catalogue structure or global Assets index | `Handler_File_Catalogue` |
| `.colpal` | `PaletteDocument` v1; palette and referenced colour records | `Handler_File_Palette` |
| `.coltyp` | Palette codec with typography format and styles | `Handler_File_Typography` |
| `.colswa` | `SwatchesDocument` v1; loose colour pool | `Handler_File_Swatches` |
| `.colswatch` | `SwatchDocument`; individual portable colour | `Handler_File_Swatch` |
| `.colinf` | `InformationDocument` v1; member/project record | `Handler_File_Information` |
| `.colprf` | `ProfilesDocument` v1; colour channel-profile collection | `Handler_File_Colour_Profiles` |
| `.colpro` | `SavedPrintProfiles.Exchange` v1; print preset, ICC referenced rather than embedded | `Handler_File_Print_Profile` |
| `.colcal` | `ProofConfiguration` v1; session, measurements, embedded print ICC and optional simulation assumptions | `Handler_File_Proof` |
| `.colhis` | `HistoryStore.File` v2; catalogue/global operations | `Handler_File_History` |
| `.colkeys` | `KeyProfile` v1; shortcuts and quick keys | `Handler_File_Key_Profile` |
| `.colase` | `ASERegistry.Document` v1; linked/bundled ASE registry, not ASE colour bytes | `Handler_File_ASE_Registry` |
| `.colshr` | ZIP share; `ShareManifest` v2 and staged content | `Handler_File_Share` |
| `.colqr` | `ColourQR`: current XYZ file representation plus older document decoding | `Handler_File_QR` |
| `.colmanifest` | Internal share manifest | Owned by share handler; not a separate user workflow |

Legacy compatibility: `.colcatalogue`, `.colpalette`, `.colhistory`, `.colshare`, `.colspace`, `.colproject`, `.config`, `schema.colschema`, `library.json`, `library.history.json`, `catalogues.json`, and purpose files `.colweb`, `.colprint`, `.colphoto`, `.colvideo`, `.colcine`, `.col3d`. Keep readers needed by migration; write current formats only after verified conversion. Audit `.colsyncproject` / `.colsynccatalogue` Finder registrations against actual supported payloads before retaining or retiring them. Historical `.coldata` must be dispatched by contents, not mistaken for the workspace manifest.

`.colplt` in the recovery TODO is a typo, not an implemented palette format. Correct it when that code is migrated. Unknown `.col*` types must be reported as unsupported and preserved, never treated as arbitrary JSON.

External dependencies include ASE/ACO/GPL/CLR, ICC/ICM, images and sidecars, CGATS measurement inputs, ordinary exports and archives. Register adapters where workflows need them. Image intake exists, but do not claim a complete catalogue-owned image storage/transfer contract from its browsing UI: define persisted ownership before offering destructive image actions. No invented image `.col*` extension in this phase.

## 4. Findings to address

| Priority | Source finding | Required change / evidence |
|---|---|---|
| P0 | `CatalogueTree.remove` falls back from failed Bin to `removeItem` | No permanent-delete fallback in production; surface a recoverable failure |
| P0 | `Catalogues.bin` unregisters before `trashItem`; registry setter presents errors rather than throwing | Plan filesystem and registry work together; return failure without silently detaching |
| P0 | `CatalogueTree.names` maps enumeration failure to `[]`; resolution infers removals and one-missing/one-new renames | Typed scan failures, incomplete inventory, preserved references; require proven identity or user resolution |
| P0 | `LibraryStore.load` can seed ASE, migrate, write dirty reconciliation and perform global migration; fallback can quarantine/start/save a new library | Separate inspection from approved creation/migration/repair; no write from failed or degraded reads |
| P0 | `AssetTransaction.recover` deletes current contents before restoring snapshots; one fixed journal directory | Per-operation journal, affected-path scope, revision checks, idempotent recovery; preserve externally added files |
| P1 | Catalogue palette loads bypass `PaletteAssetHandler.read`; swatches/profiles use generic optional reads | One validated codec path per type; distinguish unreadable, unsupported, wrong identity and absent |
| P1 | Catalogue accepts `version >= 3`, history `version >= 2`; Codable rewrites may drop unknown fields | Explicit supported versions; block unsupported writes; define unknown-field retention per format |
| P1 | `HistoryStore.load` returns empty history on decoding failure | Unavailable history remains represented; block overwriting failed history |
| P1 | `Catalogues.registry` returns `[]` on failure; `AppDataStore.read` returns defaults when manifest absent | Throw on expected-but-unavailable manifest/registry; defaults only in explicit new-workspace creation |
| P1 | `AppDataStore.update` is read/modify/write without shared revision arbitration | Serialize in-process changes and reject/retry stale writes across processes; atomic replacement alone is insufficient |
| P1 | `MetadataFilterStore.read` writes manifest mirror; write rollback uses best-effort restore | Reads report mirror differences; repair in coordinated catalogue/manifest transaction |
| P1 | Controller reload continues history/watch/completion work after catching load error; `show` creates NSAlert | Stop dependent work after failure; shared incident stream and one recovery presenter |
| P1 | Watch callbacks reload; editing/picking can settle changes without deferred rescan | Coalesce events, queue deferred scans, do not acknowledge unresolved external revisions |
| P1 | `main.swift` opens only `urls.first` and routes documents to workspace chooser | Type-aware multi-document queue; format-specific import/open, including unsupported outcomes |
| P1 | Current registry entries are name/path; startup can probe UUID but registration is name-based | Migrate persistent registration identity to UUID while retaining paths/names and unknown manifest fields |
| P1 | Linked ICCs use content hashes; print-preset exchange references ICC by name | Preserve existing semantics; resolve exact dependency identity and disclose unavailable profiles, never substitute silently |
| P2 | Duplicate exported `.coldata` type identifiers; legacy copy and incomplete new-format routing | One canonical type per current format, intentional legacy aliases, registry/plist/routing parity tests |
| P2 | Format constants, file panels, codecs and source inclusion are scattered | Central registry and migration coverage checks; remove obsolete direct entry points after conversion |

P0/P1 are source risks, not claims that every path has already caused data loss. Reproduce with isolated fixtures before changing behaviour. Existing self-tests that expect Finder deletion to remove records must be revised deliberately; passing those old expectations is not the new acceptance criterion.

## 5. Responsibilities and shared contracts

`Handler_File_Manager` owns a registry of handlers, an access provider, a filesystem adapter, inventory/revision tracking, incident aggregation and transaction execution. Use a serialized mutation boundary (actor or dedicated serial executor selected during implementation). Scans/codecs run off the main thread; UI delivery is on the main thread. Coordinate with other processes using file coordination plus revision validation; do not assume an actor protects against other apps.

Each handler conforms to a shared protocol, with typed document codecs behind type-erased registration where necessary. Minimum contract:

- Descriptor: extensions/aliases, content identifier, supported versions, limits, import/open/export capabilities.
- Inspect/decode/validate: format, identity, owner, references, semantic constraints and dependency enumeration.
- Encode/migrate: explicit output version, migration proposal and preservation guarantees.
- Plan contributions: required writes/copies/relinks/removals and post-write validation. The manager alone authorizes and executes mutations.

Shared value types should cover `FileIdentity`, `FileReference`, `FileAvailability`, `FileIssue`, `FileInventory`, `FileOperationPlan`, `FileOperationResult` and `FileRevision`. Use the agreed `Handler_File_*` naming for classes/files; choose concise value-type names consistently at implementation. Do not create one generic untyped dictionary API for every document.

Reference fields: stable identity, kind, owner/scope, relative locator for owned content or external locator, dependency identity and last-known metadata. Content hash is required when byte identity matters (ICC, archive validation), not on every colour-edit redraw. `FileVersion` inode/date/size is a useful change hint, not a universal identity proof.

Availability states: available, missing, inaccessible, access-expired, volume-unavailable, corrupt, unsupported-version, identity-mismatch, ambiguous and unknown/not-yet-scanned. Preserve the underlying error for diagnosis; do not guess a disconnected drive from a missing-path result alone.

### Shared document header and provenance

Added at Rick's request during this review. Every newly created native `.col*` document must carry a common structured `header` object, generated by shared manager infrastructure and validated by its handler. JSON remains valid JSON: no comment lines or custom byte preamble. Put `header` near the beginning for readability where the encoder permits; readers must not rely on object-key order. Archives put it in their manifest. External standards (ASE, ICC, images and ordinary exports) must not receive arbitrary header bytes; retain provenance in an appropriate standards-defined metadata field or an owned registry/manifest instead.

Header schema version 1 should contain:

| Field | Meaning / source |
|---|---|
| `metadataVersion` | Version of this shared header, independent of the document format version |
| `documentID` | Stable document UUID, aligned with existing asset/catalogue identity where appropriate; define aggregate/history/registry IDs explicitly |
| `createdAt` | Original document creation timestamp, ISO 8601 UTC |
| `createdBy` | Creator display name and optional macOS account name; prefer explicit Colorgain creator identity, otherwise local account identity |
| `createdWith` | App bundle identifier, display name, marketing version, build number and optional build commit |
| `lastSavedAt` | Timestamp of the last successful content save |
| `lastSavedBy` | Identity responsible for that save |
| `lastSavedWith` | App identity/version/build responsible for that save |
| `derivedFrom` | Optional source document identity for an independent copy/import or migration; no private absolute paths |

Use `Bundle.main` for bundle identifier (`CFBundleIdentifier`, currently `com.mmffdev.mmffdevcolour3`), marketing version (`CFBundleShortVersionString`), build (`CFBundleVersion`) and existing `ColourBuildCommit`. This identifies the app product, not a unique installation or a licence. Bare development binaries/tests may lack bundle metadata: inject deterministic test values and use an explicit development/unknown fallback, never invent a release version. Do not add hardware IDs, Apple IDs, email addresses, licence tokens or installation tracking IDs.

Original creation fields survive ordinary edits, moves, relinks and renames. Last-saved fields change only when a document write succeeds, not on scans, previews or cache reads. An independent duplicate/import gets the identity appropriate to its domain and explicit derivation; preserve source authorship separately from the person importing it. Migration cannot reconstruct an original creator or timestamp reliably: retain existing trustworthy metadata and mark unknown values unknown, with separate migration provenance. Filesystem creation dates are observations, not proof of original authorship. Align header creation time with existing domain creation fields without overwriting domain history.

Creator names are descriptive provenance, not authentication or proof of approval. Provide a creator-identity setting and a share/export preview with the option to omit personal account names; retain non-personal app/version provenance. Local documents record the requested creator details. A migrated file should not suddenly claim the current user created its original content. Do not infer a human creator for unattended processes; record an explicit application/system actor and, where known, the initiating user separately.

Existing documents remain readable without a header. Add metadata on the next explicit successful save/migration under a defined backward-compatibility policy; no startup-wide rewrite. Audit old readers' unknown-field tolerance and version each affected format if necessary. Most current models have `generator`, and some have timestamps, but there is no uniform header with creator and full app identity. Preserve `format`/`version` and existing fields while adapters migrate; new header versions must not silently lose unknown metadata on resave.

Header acceptance tests: all native handlers emit the common schema; deterministic identity/time providers; bundle/dev fallbacks; created fields unchanged after edits; successful-save timestamps only; copy/import lineage; unknown legacy provenance; old-reader compatibility; unknown-field retention; archive manifest metadata; optional personal-name removal in exported copies without altering the source; no external-format corruption. Include metadata in integrity digests of the actual exported bytes. Update stage 1 shared contracts and stage 3 format adoption to include this work.

## 6. Authority and reconciliation

- `.coldata` owns workspace membership, portable settings and references to app-wide resources. Catalogue UUID identifies a registration; name/path can change.
- `.colcat` owns catalogue structure, placement/order and asset references. Global `Assets.colcat` has app scope; do not bin it with one catalogue.
- Asset handlers own content validity and embedded identity. A discrepancy between embedded owner and placement is a conflict to reconcile, not permission to overwrite either.
- Disk observation proves present content and access state. Absence is not proof of intentional deletion. Only an explicit confirmed removal creates deletion/tombstone semantics.
- Bookmarks, OS grants and machine bootstrap locations stay local. Persist last-known content metadata portably; keep transient availability/check times separate unless a specific portable field is justified.

Reconciliation sequence: read expected graph without writing → inspect root/access/volume → scan accessible scopes → compare IDs, paths and revisions → produce grouped issues/proposals → obtain any required UI decisions → revalidate → apply a transaction → publish updated references and inventory. A partial scan must carry `incomplete`; never produce an empty authoritative inventory.

Proven same-ID Finder moves can be reconciled under the agreed automatic policy when unambiguous, access is complete and the change is journalled. Heuristic renames require confirmation. Duplicate UUIDs must remain conflicts until resolved. Validate path containment, case/Unicode collisions, symlinks, nested/overlapping catalogue roots and unexpected traversal before writes.

Freeze writes only to affected/unavailable scopes; retain the last valid session as visibly stale/read-only. Unaffected work may continue. Recompute active/default catalogue, selection, profile dependencies, filter mirrors, history references and claimed-copy provenance only after successful recovery/removal. Never silently select or create Main as a remedy.

## 7. Recovery overlays and graceful failure

One incident per unavailable parent/identity and failure generation. Suppress child alerts under that parent, coalesce repeated watcher/reload reports and retain details in the recovery panel. Dismissing a panel acknowledges that generation; unchanged timers must not reopen it. A new meaningful state change may update/reopen appropriately. Re-probe on Retry, volume return, renewed grant and application activation with bounded backoff.

Present what happened, affected catalogue/location, verified versus last-known contents, whether edits are safe, and only applicable actions: Locate/Relink, Grant Access, Retry, Restore Backup, Remove From Workspace and Cancel. Restore validates backup identity/version and previews replacement; it is not an unconditional overwrite. No original-file quarantine, recreation or fallback to another profile during inspection.

Use existing `SwissFocusModal` and project panel/wizard primitives when implementing overlays; consult `.Codex/c_layout_registry.md` before changing UI. Native permission pickers remain UI responsibilities; normal manager errors must not call `NSApp.presentError`/`NSAlert` from storage code.

## 8. Catalogue removal wizard

1. **Inspect:** inventory catalogue assets and dependencies. Show per-kind verified and last-known counts, unique bytes, missing items, owned files, external links, shared/global dependencies and unrelated files inside the folder. Loose colour counts and colours embedded in palettes are separate measures; avoid double counting.
2. **Choose outcome:** detach and leave files; transfer selected content into another catalogue; create a new catalogue and transfer; archive and detach; or move explicitly selected owned content to Bin. Allow per-group retention choices where useful; none implicitly delete external originals or global assets.
3. **Map target schema:** show source collection/group/member/bucket against destination. Explain compatible roles, missing buckets, flattening/retained hierarchy, locked projects, duplicate identities/names, claims, tags, profiles and unsupported content. Offer explicit mapping or preservation choices; do not silently flatten a custom schema.
4. **Resolve dependencies:** select owned versus linked payloads, profiles, history, ASE, images once their ownership contract exists, and unavailable items. Preserve unknown files by default. Any archive omission is explicit; incomplete output cannot be labelled a complete backup.
5. **Review:** exact source/destination paths, mappings, retained originals, files to Bin, space requirements, unresolved items and effect on active/default catalogue. The UI accepts this immutable plan/revision, not a fresh name-only delete request.
6. **Execute:** stage, validate and verify destination/archive before source changes. Cross-volume moves are copy → verify → finalize → approved source removal. Keep recoverable staging until commit is durable. Detach-only skips content writes.
7. **Finish:** update registry/default/active references with the successful operation; refresh all views/watchers once. Report completed/retained/unresolved items and recovery path. Cancel before commit leaves original files/registrations intact.

Final Bin delivery is not assumed reversible programmatically. Journal actual Bin outcomes and support honest partial-completion recovery if a later operation fails. Never claim global filesystem atomicity across volumes, manifest files and Trash; design resumable phases so the user can recover. On destination/archive failure, do not detach or remove source content.

## 9. Transactions and extension policy

Plan → validate grants/identities/revisions/space → stage → validate encoded output → journal intent durably → publish payload/index changes in recoverable order → update registration/default references → mark commit → cleanup. For cross-catalogue operations include source, destination, global scope and manifest in the journal. History records one completed user operation; failure/cancellation does not masquerade as success.

Use per-operation IDs and touched-path before/after revisions. Recovery must be idempotent at every phase, retain conflicting externally edited files, and never restore an entire directory over unrelated changes. Prevent overlapping in-flight plans. Define recovery for a crash between every publish step, including registry finalization and non-reversible Bin results.

Adding a format requires a handler, descriptor registration, version/identity rules, dependency/ownership declarations, round-trip and failure tests, routing, Finder type/icon where applicable, build inclusion and UI capabilities. Retirement stops new writes while preserving supported legacy reads/migrations. Unknown fields must either survive edits or make the document explicitly read-only; never silently discard them.

## 10. Execution stages and exit gates

| Stage | Work | Exit gate |
|---|---|---|
| 0 — Baseline | Capture isolated current-format and legacy fixtures; reproduce deleted-folder alert cascade; record source touch-point inventory | Reproduction and baseline byte/identity snapshots; no real user data touched |
| 1 — Spine | Add manager, registry/protocol, filesystem/access abstraction, structured errors and fault injection | Descriptor uniqueness, unsupported dispatch and headless handler tests pass; both builds include new folder |
| 2 — First vertical slice | Adapt app-data, catalogue and palette handlers; make inventory/read-only open explicit; stop Bin fallback and unregister-before-success | Missing parent yields one incident, no data rewrite; cancellation preserves registry; normal palette save still works |
| 3 — Complete formats | Adapt remaining current handlers and legacy migration readers; route metadata mirrors, global stores and caches | Format matrix passes; all `.col*` reads/writes enter registered handlers |
| 4 — Reconciliation | Move watchers, startup/reload, document dispatch, bookmarks and incident presentation onto manager | Parent/child, offline/access, duplicate/move and multi-window scenarios pass without alert cascades |
| 5 — Transactions | Replace broad rollback, cover source/destination/global/manifest, revision conflicts and restart recovery | Inject failure/crash at every phase; no unrelated external file loss; plans are resumable/idempotent |
| 6 — Removal wizard | Implement inventory, retention options, schema mapping, verified archive/transfer and completion | All wizard outcome/cancellation/partial-failure scenarios pass; native review at minimum/reference sizes |
| 7 — Close migration | Route sync, sharing, setup, profile/proof/QR and external adapters; remove bypasses; fix Finder copy/types | Static bypass audit clean except documented infrastructure; both build/self-test suites and native QA pass |

Stages 2–4 use existing guarded operations or disable unsafe mutations until stage 5 supplies full transaction coverage. No wizard destructive action ships ahead of that gate. Do not rename every existing model and move all UI in one commit. Each stage leaves a working app and a documented compatibility facade; remove the facade only after every caller migrates.

Build integration: SwiftPM uses the root target; ensure `FileHandlers/` is compiled and support fixtures/docs excluded as needed. Store XcodeGen currently declares `includes: ["*.swift"]`; explicitly include the new directory and verify generated target membership. Check the direct Xcode definition too. Add this root Markdown document to package exclusions if SwiftPM reports it as an unhandled file during implementation. Read `.Codex/c_appstore_backlog.md` before Store-specific changes. Keep privileged Adobe/Sparkle behaviour outside Store paths.

## 11. Test plan

Use temporary workspace roots and isolated preferences/bookmark providers. `MMFFDEV_COLOUR3_HOME` is available, but `Catalogues.home` takes precedence: isolation must override/clear the bootstrap preference safely in a test-only suite. Never run destructive scenarios on Rick's workspace. Snapshot all fixture bytes, paths, IDs, registries and unknown fields before each test. Count presented incidents through an injected presenter, not actual blocking alerts in unit tests.

### Automated acceptance matrix

| Area | Scenarios | Required assertions |
|---|---|---|
| Every registered format | Valid round trip, bad/truncated payload, wrong extension/content, wrong owner/ID, old/current/future version, size/depth limits, unknown fields | Exact source/master precision and required metadata preserved; unsupported input unchanged; no silent partial decode |
| Missing data | Manifest, index, parent folder, palette, loose pool, profile, history, ASE registry/link, proof file | One grouped incident; expected references and valid in-memory session retained; no auto-seed or empty rewrite |
| Access/volume | Permission denied, stale/failed bookmark, revoked grant, offline/unmounted/remounted drive | Accurate state or explicit unknown; no deletion inference; correct grant/retry flow |
| Reconciliation | Proven rename/move, ambiguous empty rename, duplicate IDs, Finder copies, nested roots, case/Unicode variants | Only proven matches automatic; conflicts preserved; no ownership change from path alone |
| Manifest consistency | Rename/relink/detach, active/default removal, duplicate names, metadata mirrors, app-home move | UUID-linked graph correct after success; unrelated/unknown settings retained; failed writes leave recoverable state |
| Concurrency | Other process save, two windows, global-assets edits, watcher storms, editing/picking during events | Stale plans rejected/refreshed; no lost updates, repeated incidents, skipped scans or save/reload loops |
| Transactions | Failure at each write/move/copy/index/registry/journal/cleanup step, restart at each phase, external file arrives during recovery | No unrelated loss; recovery repeatable; commit state honest; cleanup failures do not undo a completed commit |
| Removal | Detach/leave, transfer existing/new catalogue, archive/detach, Bin; cancel every step | Retained originals byte-identical; correct target schema; source kept on failed destination; Bin failure never permanently deletes |
| Partial inventory | Missing assets, inaccessible subtree, unknown files, image links, shared profiles, claimed copies | Verified/last-known counts separated; no false complete archive; external/global assets protected |
| Sharing/archive | Digest mismatch, omitted dependencies, duplicate/traversal paths, symlinks, excessive expansion, corrupt ZIP, disk full | Validate before publish; original/destination unchanged on rejection; bounded resource use |
| Routing/build | Multi-URL open, all current/legacy types, unknown `.col*`, manifest/plist registry parity | Correct typed flow; no first-URL loss; both targets compile handlers and preserve sandbox behaviour |

Extend existing `runAppDataTests`, `runGlobalAssetsTests`, `runWorkspaceStartupTests`, catalogue/tree/migration and sync tests in `SelfTest.swift`, plus `PaletteAssetTests.swift`, `ICCProfileTests.swift`, `PrintProfileTests.swift`, `ColourQRTests.swift` and proof tests. Add manager/transaction/recovery/wizard-plan suites through the existing `--self-test` harness. Reuse historical fixtures and revise tests that intentionally encoded the superseded deletion policy.

### Native verification

In an isolated completed workspace, open two catalogues with different custom schemas, palettes, typography, loose colours, profiles, ASE links and known external dependencies. While open, remove a parent folder; remove individual children; rename/move a folder; revoke a grant; disconnect/reconnect a test volume. Check one recovery surface, usable unaffected work, stable selection, correct unavailable indicators, deferred recovery and no repeated OS alerts after dismissal.

Exercise every wizard outcome and cancellation boundary, including target conflicts, insufficient space, interrupted archive, Bin failure and removing the active/last catalogue. Inspect details/counts, mapping explanations, progress, keyboard/Escape, focus restoration, scrolling, minimum/reference window size and reduced motion. Restart to verify registrations, journal recovery and bookmark persistence. Repeat the access cases with the sandboxed target and a stable signing identity; ad hoc bookmark persistence has known limitations.

Run the appropriate full build/self-test command after implementation changes: direct `./build.sh`; Store `./make_appstore.sh` on its target branch. Follow the project commit/build rule when commits are requested. This documentation change needs no app installation. Record exact commands, results, native evidence and untested hardware/volume cases per stage rather than claiming coverage from a build alone.

## 12. Completion criteria and bounded decisions

Complete when all current `.col*` persistence routes through registered handlers; manager core is UI-independent; scans never mutate; missing/inaccessible is distinct from deleted; recovery is grouped; ownership/schema mapping is explicit; registry and disk changes are recoverable together; unsupported data is preserved; both builds and the matrix pass. No production hard-delete fallback, swallowed persistence error, unvalidated format bypass or name-only destructive catalogue operation remains.

Resolve during the relevant stage: exact persisted UUID registry migration; preservation strategy for unknown Codable fields; format-specific merge/clone identity rules; history retention on transfer; image ownership contract; ordinary ZIP versus `.colshr` archive presentation; permitted ICC packaging. These do not block the manager/recovery foundation. Treat the current XYZ-only QR writer as an explicit exchange contract: it does not retain every source/kind field of the in-memory QR document, despite the file header comment. Decide and test intended fidelity before advertising lossless QR transfer; do not change colour semantics as an incidental refactor.

No implementation, data migration, Vector write, commit, build or installation was performed as part of creating this plan.

## 13. Execution backlog and sign-off

Rick explicitly requested this backlog in this file on 2026-10-15. It is the execution checklist for this architecture; no Vector items have been created. Status: `[ ]` pending, `[-]` in progress, `[x]` verified complete. Keep incomplete tests and limitations visible. A code change alone does not complete an item.

For each completed item append a dated sign-off entry containing its ID, changed files/symbols, checks and actual results, any remaining limitations, and commit/build identity when available. Distinguish automated verification, native verification and Rick's product acceptance. Agent verification never implies Rick has approved the UI. No commits are authorized by this checklist itself.

### Planning baseline

- [x] HFM-001 — Review current persistence and lifecycle touch points; record concrete risks and the format inventory. Evidence: sections 2–4; source review at `21eac37`.
- [x] HFM-002 — Record the agreed manager spine, per-format handler names, recovery/removal flow, provenance header and test strategy. Evidence: sections 1 and 5–12.
- [x] HFM-003 — Add this dependency-ordered backlog and sign-off ledger. Evidence: section 13; document checks only.

### Stage 0 — Reproducible baseline

- [x] HFM-010 — Establish isolated workspace/preferences/access fixtures and byte/identity snapshots. Include two distinct catalogue schemas, global assets and linked dependencies. Depends: HFM-003.
- [x] HFM-011 — Reproduce the missing-parent/child alert cascade and record which entry points emit each incident. Verify no real workspace is used. Depends: HFM-010.
- [x] HFM-012 — Capture current-format/legacy round trips and identify tests that encode superseded Finder deletion assumptions. Record baseline suite results. Depends: HFM-010.

### Stage 1 — Manager, contracts and metadata

- [x] HFM-020 — Add `FileHandlers/`, `Handler_File_Manager`, shared handler protocol and registry, structured issues/results, injectable filesystem/access/time/identity providers. Depends: HFM-011, HFM-012.
- [x] HFM-021 — Define common header codec and creator settings contract; preserve creation provenance, update successful-save metadata and support development bundle fallbacks. Depends: HFM-020.
- [x] HFM-022 — Add descriptor/version/capability dispatch tests, unsupported-format preservation and deterministic provenance tests. Depends: HFM-020, HFM-021.
- [-] HFM-023 — Verify new directory membership in SwiftPM and both Xcode definitions; update XcodeGen inclusion and relevant exclusions without changing target restrictions. Depends: HFM-020.

### Stage 2 — First working vertical slice and immediate safety

- [x] HFM-030 — Adapt app-data, catalogue and palette handlers; retain compatibility facades with one writer per format. Depends: HFM-022, HFM-023.
- [x] HFM-031 — Make inspect/open inventory read-only; separate explicit create, migrate and repair plans from loading. Prevent failed/degraded loads from recreating or rewriting missing data. Depends: HFM-030.
- [x] HFM-032 — Remove permanent-delete fallback and prevent registration removal before successful chosen outcome. Cover Bin failure and registration-write failure with preservation tests. Depends: HFM-030.
- [x] HFM-033 — Route first missing-parent flow through grouped incidents; stop dependent reload/history/completion work after a failed load. Depends: HFM-031.
- [x] HFM-034 — Verify normal palette read/save, missing-parent/child cases, cancellation and byte-identical retained data. Gate further conversion on these results. Depends: HFM-031–033.

### Stage 3 — Complete format ownership

- [x] HFM-040 — Adapt typography, loose swatches, single swatch and information handlers; preserve schema-bucket and claim provenance. Depends: HFM-034.
- [x] HFM-041 — Adapt colour profiles, print profiles and proof handlers; retain exact ICC dependencies and scientific/session metadata. Depends: HFM-034.
- [x] HFM-042 — Adapt history, key-profile and ASE-registry handlers; preserve failed history and unavailable links. Depends: HFM-034.
- [x] HFM-043 — Adapt share/manifest and QR handlers; explicitly test current XYZ exchange fidelity and legacy decoding. Depends: HFM-040–042.
- [x] HFM-044 — Consolidate legacy migration readers, supported-version rules, header adoption and unknown-field preservation/read-only policies. No bulk startup rewrite. Depends: HFM-040–043.
- [x] HFM-045 — Route metadata-filter mirrors, global asset composition and persistence caches through handlers; remove read-side mirror writes. Depends: HFM-040–044.
- [x] HFM-046 — Pass the format/version/provenance matrix for all registered formats, including preserved colour source/master precision. Depends: HFM-044, HFM-045.

### Stage 4 — Disk reconciliation and graceful recovery

- [x] HFM-050 — Migrate catalogue registration identity to UUID with name/path compatibility; preserve unknown manifest fields and active/default references. Depends: HFM-046.
- [x] HFM-051 — Implement complete/incomplete inventory and typed availability; handle missing, denied, expired, offline, corrupt, unsupported and mismatched states. Depends: HFM-050.
- [x] HFM-052 — Replace heuristic destructive reconciliation; validate identities, duplicate conflicts, containment, symlinks, case and Unicode collisions. Depends: HFM-051.
- [x] HFM-053 — Coalesce watches and queue deferred scans during editing/picking; add stale-write arbitration across windows/processes. Depends: HFM-051, HFM-052.
- [x] HFM-054 — Route startup, document multi-open, Locate/Grant/Retry/Restore and dismissal through one incident coordinator and existing UI primitives. Depends: HFM-051–053.
- [ ] HFM-055 — Verify one parent incident, suppressed child alerts, no repeat on unchanged state, preserved session and unaffected work; test sandbox grants and volume recovery. Depends: HFM-054.

### Stage 5 — Recoverable operations

- [x] HFM-060 — Implement immutable revision-bound plans and per-operation journals for source, destination, global assets and manifest. Depends: HFM-055.
- [x] HFM-061 — Implement staged publish, verified cross-volume copy, conflict-aware/idempotent restart recovery and honest partial Bin outcomes. Preserve unrelated external changes. Depends: HFM-060.
- [x] HFM-062 — Inject failures/crashes at every transaction phase, including registration finalization and cleanup; verify no lost updates or unrelated deletion. Depends: HFM-061.

### Stage 6 — Catalogue removal wizard

- [x] HFM-070 — Build inventory summaries with verified/last-known counts, ownership, dependencies, unknown files and unique-byte estimates. Resolve image ownership before offering image moves/deletion. Depends: HFM-062.
- [x] HFM-071 — Implement detach/leave, existing/new-catalogue transfer, verified archive/detach and explicit owned-file Bin choices. Depends: HFM-070.
- [x] HFM-072 — Implement source-to-target schema mapping, duplicate/identity choices, linked/global asset retention and history/profile policy. Depends: HFM-070.
- [x] HFM-073 — Implement review/progress/completion overlays using the same plans; finalize registry/default/active state only after the selected outcome succeeds. Depends: HFM-071, HFM-072.
- [x] HFM-074 — Verify every outcome, cancellation boundary, target failure, incomplete archive and active/last catalogue removal; inspect native layout/accessibility at minimum/reference sizes. Depends: HFM-073.

### Stage 7 — Consolidation and release readiness

- [x] HFM-080 — Route remaining sync, setup, share, profile, proof, QR, external adapters and UI persistence entry points through the manager. Document infrastructure exceptions. Depends: HFM-074.
- [x] HFM-081 — Consolidate Finder declarations, document routing, labels/icons and legacy aliases; test registry/plist parity. Depends: HFM-080.
- [x] HFM-082 — Remove obsolete direct writers/facades and run static bypass audit; retain explicit migration readers. Depends: HFM-080, HFM-081.
- [ ] HFM-083 — Run full appropriate build/self-test suites and native regression matrix for both targets; record exact build identities and untested cases. Depends: HFM-082.
- [ ] HFM-084 — Review completion criteria against evidence, record remaining product decisions and present final results for Rick's acceptance. Depends: HFM-083.

### Sign-off ledger

| Date | Items | Verification | Limitations |
|---|---|---|---|
| 2026-10-15 | HFM-001, HFM-002 | Source review and architecture/format/recovery/provenance/test plan recorded | Runtime failures not reproduced; implementation pending |
| 2026-10-15 | HFM-003 | Backlog IDs, dependencies and completion evidence rules added; document structure and whitespace checked | Documentation sign-off only; no app build or user acceptance claimed |

Current gate: complete both target builds and record their actual outcomes, then finish the sandbox recovery check and final acceptance record. Earlier test totals below are milestones, not substitutes for the final build results.

Implementation evidence — 2026-10-15:

- HFM-010–012: `FileHandlerFixture` uses a unique temporary root, two different schemas, global Assets, external ASE links and byte snapshots. Baseline suite: 908 passed, 0 failed. Headless reproduction produces six repeated parent/filter errors; original native alert cascade remains a native QA case.
- HFM-020, HFM-022: manager registry, per-format classes, filesystem/metadata injection, typed issues and provenance codec are present. Manager tests cover duplicate/unknown types, immutable creation metadata, no-op saves, nested unknown fields, stale writes, future versions, legacy unknown provenance, path traversal, share redaction and injected disk-full failure. Foundation suite: 923 passed, 0 failed.
- HFM-030, HFM-033, HFM-040–042: app-data/catalogue/palette adapters and remaining domain codecs are connected; read preflight prevents inferred missing-member deletion, failed reload returns immediately, repeated incidents deduplicate, native storage writes preserve metadata. Latest full debug self-test: 924 passed, 0 failed. Updated former destructive-recovery expectations deliberately. History and full graceful UI are still part of later checks, not signed off by this result.
- Debug builds use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` because the selected Command Line Tools lack the existing AppKit preview macro plugin. Initial required release build was interrupted by a source edit and must be rerun; no successful installation is claimed yet.


## 14. Implemented behavior and verification boundaries

- `Handler_File_Manager` owns native read/write dispatch, metadata adoption, unknown-field retention, stale-write checks, coordinated publication and recoverable mutations. Fifteen format classes implement the registered native formats; compatibility facades retain domain-facing APIs.
- Existing catalogue opens and metadata-filter reads are read-only. A missing expected parent, child, key profile, global index or manifest never becomes an empty successful scan or a newly seeded replacement. Explicit legacy migration remains available through startup. Finder additions/moves produce revision-bound reconciliation proposals; editing and automatic sync wait for acceptance.
- Native headers carry application bundle ID/name/version/build/commit, UTC save/create timestamps, document identity and creator/account details. Existing creation facts survive saves; legacy facts stay unknown. The creator name is configurable in File Creator Details. Personal-name redaction is available in the codec. QR keeps its existing XYZ exchange contract. ASE/ICC, images and other standard formats retain their standard bytes.
- Incidents coalesce by root and state. Recovery offers Retry, eligible file restore, catalogue Locate, conditional folder access, detach and dismissal. Multiple eligible files have a selector. External ASE/ICC links retain their existing dedicated reconnect workflows. Archive bytes are not offered to the JSON restore action.
- The removal wizard inventories verified versus last-known counts, approximate unique bytes, ownership, unknown files and schema mapping. Detach retains originals. Transfers preserve source schemas alongside the destination, create independent conflicting copies and retain non-model payloads in a verified archive. Archive writes a checked share before detaching. Bin applies only to planned owned files; external/global originals and unowned artwork stay in place. A shared catalogue root cannot be binned through one alias.
- Plans bind source/index/manifest revisions and inventory membership; existing destination indices are checked against the mapping review. Per-operation journals retain only touched paths. Restart recovery is idempotent and preserves external conflicts. Workspace locks prevent simultaneous managed operations. Verified relocation rebases internal catalogue paths and retains the old workspace as a recovery copy. Copies are bounded to 256 MB per file; archives remain 40 MB per file/256 MB total.
- Cancellation is checked before execution and at mutation/commit boundaries. Successful output/registry changes commit together. A failed cleanup leaves a committed journal for later cleanup, never a rollback of committed user work. Failed Bin operations may leave recoverable duplicate copies in the system Bin while restoring originals.
- Finder multi-open keeps all supplied URLs in a queue. Workspaces/catalogues use startup validation; shares enter staged import; palettes, swatches, QR, print profiles, proofs and keyboard profiles have review/import routes. Internal support files explain their managed workflow. Finder declarations now have one current owner per native extension; unused sync registrations were retired and current aliases retained.

### Evidence recorded during implementation

| Area | Evidence |
|---|---|
| Native codec matrix | All fifteen handlers have creator/application headers and future-version preservation checks; canonical Finder extension ownership is checked. Existing scientific/QR suites retain source/master fidelity assertions. |
| Recovery and reconciliation | Missing child/parent, denied enumeration, deduplication, unchanged manifest/filter reads, explicit restore, wrong identity, read-only opens and accepted Finder reconciliation use disposable fixtures. |
| Operations | Tests cover stale plans, new files during review, detach/re-attach, archive verification/reopening, new-target transfer/schema preservation, Bin/finalization rollback, successful owned-file Bin, last catalogue detach, cancellation after archive publication, revision conflicts, restart/idempotency and verified workspace relocation. |
| Native UI | Isolated app/preferences/workspace; inventory → destination → schema mapping → review → existing-target transfer; missing-palette Locate/restore; reference 1440×900, Studio 1200×800 and classic 800×460. Keyboard focus/scrolling, nested restore Escape, parent recovery retention and toolbar restoration inspected. |
| UI review | Impeccable finish review and focused recheck; original six findings addressed. Archive eligibility was corrected after recheck. Native testing then found and fixed file-sheet dismissal of the parent recovery form. |

### Deliberate infrastructure/compatibility exceptions

Legacy readers in `Migration`, `LegacyTree` and `ProjectFile` read historical bytes only for explicit conversion. Legacy cloud transport/backups still use `library.json`; they are not advertised as new native document formats. ZIP extraction writes only to private staging directories; archive/journal snapshot infrastructure preserves existing bytes. Bookmark storage, diagnostics, transient form memory, bundled help/reference reads, scientific transforms, image sampling/rendering, system colour lists and the direct-download Adobe helper remain their established infrastructure rather than parallel `.col*` writers. Whole-catalogue import publication and registration now use the shared transaction instead of recursive failure deletion.

Images currently have no catalogue-owned editable asset contract. They remain unowned files, may be retained in an archive and are never offered as app-owned Bin assets. Individual linked ASE files can be materialized in portable archives; monitored ASE folder links require explicit conversion to individual files first. ICC dependencies remain references unless already embedded in proof configurations. History/proof/ASE and unknown source files retained by transfer are labelled archive-only, rather than immediately adopted into the target's active model. Hidden files, root Backups, other catalogues and app-wide Assets remain at their original locations; an archive is refused if this inventory cannot include an indexed asset.

### External verification limits

Actual removable-volume unplug/replug, expired production bookmarks, power loss and another computer's cloud provider are not claimed as physically exercised. Denied/missing paths, process locking, interrupted publication, conflicts and restart recovery are exercised using isolated fixtures. App Store distribution/archive submission and notarization are outside this local implementation verification. Build target/signature/self-test results are recorded below only after they complete.


Implementation sign-off before release builds: debug compilation succeeded and the full suite passed **1,024 checks, 0 failures**. This includes alias-safe containment, escaping-symlink rejection, stable-identity preservation of unknown colour metadata, source identity for independent palette copies, production-facade legacy provenance and UUID-based detach persistence after Finder renames. Native Finder reconciliation was accepted and its new collection verified in the saved index. Release builds and the corrected Store missing-file flow remain the final gate at this commit.

The optional personal-name redaction codec is implemented and tested. Normal exports retain the creator details Rick requested; a dedicated export privacy preview/control remains a future UX extension rather than an enabled preference. No claim of anonymising arbitrary asset content is made.


Post-commit verification at `fbf12d5`: the direct release build/self-test/sign/install succeeded (1,024 passed, 0 failed). The App Store target compiled and its self-test passed (1,020 passed, 0 failed; four direct-helper checks are excluded). A separate signed sandbox test identity verified denied external workspace access, explicit folder grant, persisted access after relaunch, precise missing-palette recovery and a return to Ready. The restored header reported that test app's bundle ID, version 3.0 and save commit `fbf12d5`. QA launchers/fixtures used separate identities and preferences; no production workspace or existing trial was reset. Startup bookmark resolution is additionally being hardened to suppress system UI/automatic mounting, followed by the final missing-bookmark relaunch check.
