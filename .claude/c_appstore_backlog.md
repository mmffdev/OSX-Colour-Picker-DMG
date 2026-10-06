# App Store backlog, held here until Vector is reachable

Written 2026-10-06 from the sandbox audit of `osx-appstore-build`. Each item is in Vector's shape: Feature descriptions open "As a …", every acceptance criterion is "As proven by …", task descriptions are plain instructions. Create under the App Store theme (TH-257 in the PR-21 workspace, or a new objective under PR-23 once reachable). Tick items here as they land in Vector.

## Already in Vector (TH-257, PR-21 workspace)

- [x] FE-1659 Xcode project that builds a sandboxed, App Store-signed Colour 3. Done 2026-10-06: `appstore/project.yml`, `make_appstore.sh`. Criterion 2 (Apple Distribution identity) waits on the certificates; the ad hoc build carries the sandbox entitlement.
- [x] FE-1660 Sync and catalogue folders stay reachable under the sandbox. Done 2026-10-06 via `Bookmarks.swift` (see the bookmark feature below).
- [x] FE-1661 Design Pack git push: a sandbox-safe answer. Done 2026-10-06: `gitAvailable` is false in the Store build, the checkbox never shows, the pack is still written.
- [x] FE-1662 Pick sound without a helper process. Done 2026-10-06: `NSSound` on the same file, both editions.
- [x] FE-1663 Add to the Mac colour panel under the sandbox. Done 2026-10-06: the Store build asks once for the real `~/Library/Colors` through an open panel, remembers it, then writes straight in.
- [x] FE-1664 Bring in earlier libraries by choosing them. Done 2026-10-06: Import from MMFFDev Colour 2 opens a panel on the old folder in the Store build.
- [ ] FE-1665 Submit Colour 3 to the Mac App Store

## Features to add

### Store build carries no self-updater
Done 2026-10-06: Sparkle guarded by `#if !APPSTORE` in `main.swift`; the stamping phase strips the `SU` keys; `make_appstore.sh` fails if either returns.

As a publisher, I want the Store build free of Sparkle, so that App Review does not reject it for updating itself.
1. As proven by `otool -L` on the Store binary listing no Sparkle framework.
2. As proven by the Store build's property list holding no `SU` keys and its menu holding no Check for Updates item.
3. As proven by the direct-download build still offering Check for Updates.

Tasks:
- Guard the Sparkle import, the updater property and the menu item in `main.swift` behind a build flag the Store target does not set.
- Make the Sparkle link flags in `Package.swift` conditional on the same flag, or move them to the direct-download target.
- Strip `SUEnableAutomaticChecks`, `SUFeedURL`, `SUPublicEDKey`, `SUScheduledCheckInterval` from the Store target's property list.

### Store build has no root helper and asks for no password
Done 2026-10-06: `AdobeHelper.swift`, `runAsAdministrator` and the Adobe permission row are inside `#if !APPSTORE`; the Store binary holds none of the symbols; the first-open permissions sheet and the Settings panel are skipped when there is nothing to allow.

As a publisher, I want the Adobe helper, the administrator password dialog and the folder-unlock removed from the Store build, so that nothing in it tries to run with privileges the sandbox forbids.
1. As proven by the Store bundle containing no `Contents/Library/LaunchDaemons` and no helper binary.
2. As proven by a search of the Store target's sources finding no `NSAppleScript`, no `SMAppService.daemon` and no `acl_get_file`.
3. As proven by the Permissions panel in the Store build showing no Adobe row.

Tasks:
- Exclude `AdobeHelper.swift` and `helper/` from the Store target; keep `AdobeHelperRules.swift` only if the format writers need it.
- Remove `runAsAdministrator` and the administrator fall-through in `copyIntoFolder` from the Store build; `copyIntoFolder` writes directly or reports.
- Drop the Adobe row from `Permission.all` in the Store build.

### Palettes reach Adobe apps without writing into their bundles
Done 2026-10-06, by the existing fallback rather than a save panel: the Store build stages the files, opens the Adobe folder and the staged files in Finder, and says to drag them across. A save panel would fail the same way, since the powerbox cannot write to a root-owned folder. The spike on user-level preset folders is still open.

As a designer on the Store build, I want a palette saved in the right format for Photoshop, Illustrator or InDesign, so that I can load it there myself. The Adobe folders inside `/Applications` belong to the system and the sandbox cannot write there.
1. As proven by Add To Adobe Apps still listing each installed Adobe app and format, found by reading `/Applications`.
2. As proven by choosing one opening a save panel already pointed at that app's preset folder, with the file named and the format fixed.
3. As proven by the `.ase`, `.aco`, `.acb` and `.act` writers unchanged and still covered by the self-test.
4. As proven by the explanatory flash telling the user Finder will ask for a password.

Tasks:
- Replace `addToAdobe` in `Controller.swift` with a save panel flow using the same `AdobeDestination` and `writeExport`.
- Spike: confirm whether Photoshop and Illustrator 2026 load swatch libraries from a user-level Library folder; if so, offer that folder through an open panel and a bookmark so later saves need no panel.

### Every remembered folder is a bookmark
Done 2026-10-06 with a different shape from the criteria below: paths stay as paths everywhere (they sync and they are what the user reads), and `FolderAccess` in `Bookmarks.swift` keeps a per-Mac side table of security-scoped bookmarks keyed by path. Every panel that persists a folder calls `remember`; launch and pick mode call `restoreAll`, which opens every bookmark for the life of the process. Self-test covers the in-process round trip. NOT verified by hand: a relaunch resolving a bookmark outside the container.

Extends FE-1660. As a user, I want the app to keep reaching the folders I chose after a relaunch, so that sync, projects, a moved data home and a catalogue kept elsewhere all keep working under the sandbox.
1. As proven by `syncFolder`, `projectsFolder`, `appHome` and the entries in `catalogues.json` being stored as security-scoped bookmark data, not paths.
2. As proven by a project with an absolute `folder` resolving after a relaunch.
3. As proven by the entitlements file holding `files.user-selected.read-write` and `files.bookmarks.app-scope`.
4. As proven by the self-test round-tripping a bookmark for each kind of remembered folder.

Tasks:
- Add a `Bookmarked` helper: make bookmark from URL, resolve with stale check, start and stop access.
- Convert the four preference-backed folders in `Sync.swift` and `ProjectFile.swift`.
- Convert `Catalogues.Entry.path` and `Project.folder` absolute values; relative values stay as they are.
- Wrap sync, project writing and catalogue loading in scoped access.

### Data starts in the container and can be carried over
Partly done 2026-10-06: the setup assistant's catalogue default is the app's own Catalogues folder in the Store build, and Bring In opens on the download edition's old data folder so it can be adopted in place. A container migration manifest was rejected: it moves the folder, which would break the download edition on the same Mac.

As a user upgrading from the direct download, I want my catalogues, projects and settings to appear in the Store build, so that I do not start again.
1. As proven by a first launch of the Store build on a Mac with an existing `~/Library/Application Support/MMFFDev Colour 3` finding that data.
2. As proven by the setup assistant's default catalogue location being inside the container, with the open panel as the way to choose elsewhere.
3. As proven by the setup assistant never proposing `Documents` without a panel.

Tasks:
- Add a container migration manifest to the Store target's property list for the Application Support folder, or an import step in the setup assistant that opens a panel on the old folder.
- Change `catalogueParent` in `SetupAssistant.swift` to the container's Application Support for the Store build.

### Press profiles come from ColorSync
Done 2026-10-06: `ColorSyncIterateInstalledProfiles` first, folders after, same names as before.

As a print designer, I want every ICC profile installed on the Mac offered as a press condition, so that the Store build sees the same profiles the direct download does.
1. As proven by `PressProfiles` using `ColorSyncIterateInstalledProfiles` instead of scanning folders.
2. As proven by a profile in `~/Library/ColorSync/Profiles` appearing in the list under the sandbox.
3. As proven by the self-test still finding the system profiles.

Tasks:
- Replace the folder list in `ColourEngine.swift` near line 359 with the ColorSync iterator; keep the header parser.

### Pick from anywhere through Shortcuts
Done 2026-10-06: `PickIntent.swift`, an App Intent plus an `AppShortcutsProvider`; metadata is extracted in the Xcode build. NOT verified by hand in Shortcuts.

As a user, I want to pick a colour from any app with a key I choose, so that the hotkey route survives the Store build. The `--pick` mode works inside the container but a Store app should not ask people to bind a binary path.
1. As proven by an App Intent named Pick Colour appearing in Shortcuts, returning the hex and adding the pick to the library.
2. As proven by a Shortcuts hotkey running it while the app is not frontmost.
3. As proven by `--pick` still working in the direct-download build.

Tasks:
- Add an `AppIntent` that runs the sampler through `NSColorSampler` and stores the pick with `LibraryStore.standard.mutate`.
- Mention Shortcuts in the help page where the hotkey is described.

### Standard and Pro editions behind Apple's paywall
Mechanism done 2026-10-06: `Store.swift` with StoreKit 2 products, purchase, restore, entitlement refresh, `Store.allows(_:)` as the gate, and Settings ▸ Edition in the Store build. Product ids `com.mmffdev.mmffdevcolour3.standard` and `.pro` must be created in App Store Connect. No feature is gated yet: the split is Rick's decision. NOT verified against a sandbox tester account.

As a publisher, I want one Store listing with Standard and Pro unlocked through in-app purchase, so that both editions are sold through Apple. Price and the feature split are decided separately; this is the mechanism.
1. As proven by StoreKit products for Standard and Pro loading and purchasing in the sandbox environment.
2. As proven by entitlement state persisting across launches and restored through Restore Purchases.
3. As proven by a single gate function the rest of the app asks before showing a Pro feature.
4. As proven by the direct-download build treating every feature as unlocked.

Tasks:
- Add a `Store.swift` with StoreKit 2 product loading, purchase, restore and a current-entitlement check.
- Add an `Edition` gate (`standard`, `pro`) with one function the UI calls; direct-download returns `pro`.
- Decide and record the feature split (separate decision with Rick; candidates for Pro: press profiles and channels, Adobe formats, design packs, sync, typography, the pick intent).
- Add a purchase page to Settings and the first-run assistant.

### Store build removes git push
Covered by FE-1661. Note for that item: spawning `/usr/bin/git` inherits the sandbox and cannot read `~/.ssh` or `~/.gitconfig`, so the Store answer is to drop push and keep the folder export.

### Shutter sound through the system sound API
Covered by FE-1662. Note: `NSSound(contentsOfFile:)` on the same `Grab.aif` path; the file is readable under the sandbox.

## Verified fine under the sandbox, no item needed

Screen Sample through ScreenCaptureKit, `NSColorSampler`, every open and save panel, `NSWorkspace.open` on Font Book, folders and web links, Carbon `CopySymbolicHotKeys`, pasteboard, share sheet, `NSFontManager`, temp-dir staging, the self-test's throwaway folder, the trial preference suites, reading the `/Applications` listing.
