# Simple catalogues and setup

## Canonical level references

Rick, 19 October 2026: use these fixed internal names in discussions, specifications and implementation references. User-selected display wording does not change a level's identity.

| Level | Internal name |
|---|---|
| lvl0 | Workspace |
| lvl1 | Catalogue |
| lvl2 | Clients |
| lvl3 | Projects |
| lvl4 | Assets |

For example, Customer is display wording for lvl2 (Clients); Work Order is display wording for lvl3 (Projects).

Agreed 18 October 2026. `SimpleCatalogue.swift` owns the fixed semantic structure, new setup, native Catalogue Structure settings and standalone catalogue import. Existing file handlers and My Library remain shared authorities.

- `CatalogueFile.structure` / `SchemaFile.structure` identify `client-work-assets` version 1. `SchemaCollection` is the backing client record; each client stores singular wording in its root stack and `workItemPlural` separately. Optional `structure.clientLabel` stores lvl2 display wording; older catalogues default to Client. Work items retain existing project IDs and schema places. New clients have no intermediate folders. Work-item categories sit inside a single Assets container; Information and Tags remain record companions.
- `Assets/my_library.collib.libraryAssetTypes` configures My Library. The workspace manifest references that index; legacy `Assets.colcat` and manifest category choices migrate together with a recovery copy and unchanged library UUID. The first setup checklist also seeds the first catalogue's `structure.assetTypes`; subsequent catalogues retain independent category choices. Custom asset families and types are stored in `.coldata` for later client/catalogue forms and in `.colcat` for portable schema identity. Selected custom types create My Library destinations and appear under the owning client. Existing populated categories are retained when disabled. Category presence does not claim an import adapter exists.

New setup choices are limited to Documents, Palettes, Fonts, Typography Packs, ASE, LUTs, ICC Profiles and CSS, in one Import group. Existing broad and custom category IDs remain readable in saved catalogues but are no longer offered to a new setup. Typography Packs uses the existing `typography` ID and native Typography bucket. CSS is a new category; colour extraction is planned, not yet an importer. The Header Import menu follows the same eight choices and disables types without a connected importer.
- Empty simplified catalogues open a Welcome checklist and a pending client node. After client creation the pending work node becomes the next prompt. House blue (#53A1E9) pulses with white/dark text, or stays steady for reduced motion. Pending nodes are navigation prompts, not stored records or drop destinations. My Library lists its enabled categories independently.
- `SimpleSetupController` replaces the old nesting journey on first creation: unnumbered Welcome, then Workspace, Catalogue, Clients, Projects, Assets, Clients so far and Review. Clients so far can loop back to a fresh client/project/asset branch without reloading the page; each completed branch becomes a real client and work record at the one final transaction. The Assets page is one scrollable list of always-visible families, with inline unlimited custom types per family and custom families at the bottom. Drafts are machine-local (`simpleSetupDraftV2`); no `.coldata` write occurs before final creation. The approved HTML is embedded in `ApprovedSetupHTML.swift`, hosted by a local WKWebView; native messages select/open folders and invoke the transactional creation handler. No localhost server or network connection is required. Catalogue import is not a setup page. Opening/recovering an existing workspace is separate.
- `SimpleSetupController.requestKey` is a machine-local start-wizard flag. It remains set until successful creation; presenting setup does not reset or delete existing workspaces. `--migrate-simple-catalogue <folder> --app-data <workspace>` performs the conservative backed-up migration without opening the app.
- Both File > Import Catalogue and Catalogues + call `SimpleCatalogueImport`. Accept a catalogue index/containing folder or verified catalogue `.colshr`; originals are retained. Keep incoming labels by default or explicitly choose local terminology. Already-registered catalogue IDs are refused rather than duplicated. Flexible schemas with extra ownership levels need reviewed migration; unsupported versions are refused.
- Catalogue exports can optionally bundle My Library palettes/typography inside `Support/Shared Library` in the existing manifest/digest-checked archive. Import asks whether to add those assets, reuses exact matches and explicitly keeps existing conflicts or imports independent copies. Linked external asset records remain references; owned imported payloads travel with the archive. Bundled transport payloads never become another registered catalogue.
- Migration retains client, member, bucket and palette IDs, snapshots the full original, and moves entire bucket folders by ID. Deep legacy hierarchy is refused rather than silently flattened. Native Settings > Library & Data > Catalogue Structure edits the fixed structure; legacy in-page schema routes redirect there.

Validation: `runSimpleCatalogueTests` exercises isolated creation, terminology round trip, repeat/collision protection, migration backup and IDs, catalogue import/source preservation and shared archive import. Native wizard/layout verification is required before declaring the build ready.

Installed verification, 18 October 2026: build 357 (`06e4b29+`), 23:28 BST; 1,365 self-tests passed. Native checks covered all four setup pages, checkbox contrast, migrated tree, File import and Catalogues + import review. The user walkthrough and later import remain pending. Master Colorgain has a complete pre-conversion recovery copy under its workspace Backups/Simple Structure; its portable archive is on the Desktop.

Approved wizard, 19 October 2026: fixed logo, left description and control origins; no numbered prefix or redundant right title; My Library and catalogue trees side by side, with yellow independent scrollbars ending at the primary action line. Connected child elbows begin below parent folder icons. Review edits live beside tree nodes. The static background uses 50 pt #DFDFDF bands / 30 pt transparent gaps, fading diagonally. Welcome and completion use the same anchors; welcome actions align with other pages. Audio Clips joins the asset category registry.

## Client and work creation, 19 October 2026

`CatalogueJourneyView` shares `SwissFocusModal` forms between the Welcome checklist, tree add controls and Settings > Library & Data > Catalogue Structure. Forms use the shared square card, blurred backdrop and Escape/focus restoration, and return to their presenting surface. The separate Projects settings tab is removed. Catalogue Structure lists clients and their work with edit/add actions, plus catalogue defaults and My Library category choices. Campaign is a supported work name.

Client profiles live in optional `SchemaCollection.profile` and travel in the catalogue. A client sheet starts with a name and optional organisation/contact fields, followed by its work terminology and asset categories. Work sheets contain name, description, start/deadline and ordered custom fields. Definitions are stored as `details.customForm`, answers as `details.custom.<id>`. `structure.formPresets` contains only field IDs, labels, types and order; applying a preset creates fresh IDs and copies no answers.

Persistence coverage includes profile round-trip, custom definitions/answers and reusable preset definitions. Existing catalogues decode without these optional properties.

Isolated native verification: client creation updates the checklist and pending work node; work saves description and custom answers; Settings edits return to Catalogue Structure; presets persist definitions only and apply with blank answers. Tests used `/tmp/colorgain-journey-qa`, not the user catalogue.

## Personal mode and standalone library

`structure.personalMode` controls presentation independently of future edition availability. A stable `personalCollectionID` owns newly created personal work; existing client profiles, work IDs and placements are retained. Personal navigation flattens work items and redirects client routes to the catalogue. Welcome and Catalogue Structure share the reversible switch. Light will omit client capabilities; Studio retains the switch.

`MyLibraryFile` exports a folder containing `my_library.collib` plus payloads. Import merges palettes and owned/reference assets, reuses exact content, and remaps library group members to the receiving library UUID. External references retain their locations. Import/export entry points are Catalogue Structure and the Library root context menu. A `.collib` is not a client catalogue.

Onboarding uses the chosen client wording in its tab title, with Personal Onboarding in personal mode. Its viewport title, actionbar/footer and tab page controls are hidden.

Workspace opening/recovery now uses `ApprovedWorkspaceHTML`, which takes its shell directly from `ApprovedSetupHTML`; the former native chooser drawing/layout is removed. File validation and recovery remain in `WorkspaceStartupView`. Setup and recovery both handle L through the shared appearance presets, excluding text-entry targets.

## Verification — 19 October 2026

Installed direct build at 04:28 BST: 1,380 self-tests passed, zero failed. Native isolated walkthrough covered fresh setup (Customer/Campaign/Audio Clips), optional customer profile, work metadata, definition-only presets, personal mode on/off, Library export/import, and Settings edit/save with immediate refresh. Fresh setup and recovery both switch appearance with L. Fixed export directory detection, Settings toolbar resize crash, and pin/add overlap found during this walkthrough.

Restored the canonical installed app to the real workspace afterwards. Cookra/Colorgain catalogue bytes and both library payload checksums match their pre-test snapshots; standalone-library migration backups exist. Light/Studio edition packaging remains future work; personal mode supplies the shared behaviour.
