import AppKit
import CoreGraphics

// Run with: MMFFDevColour3 --self-test
// Exercises the library logic against a throwaway folder. Never touches real data.

func runSelfTest() -> Never {
    var passed = 0, failed = 0
    func check(_ ok: Bool, _ what: String) {
        if ok { passed += 1; print("  ok    \(what)") }
        else { failed += 1; print("  FAIL  \(what)") }
    }

    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("mmffdev-colour3-selftest-\(UUID().uuidString)")
    let v1Dir = root.appendingPathComponent("v1")
    let v2Dir = root.appendingPathComponent("v2")
    try! fm.createDirectory(at: v1Dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    let v1File = v1Dir.appendingPathComponent("library.json")
    let v1JSON = """
    [
      { "hex" : "#FF0000", "pickedAt" : "2026-03-03T10:00:00Z" },
      { "hex" : "#00ff00", "pickedAt" : "2026-02-02T10:00:00Z" },
      { "hex" : "#0000FF", "pickedAt" : "2026-01-01T10:00:00Z" },
      { "hex" : "not-a-colour", "pickedAt" : "2026-01-01T09:00:00Z" }
    ]
    """
    try! v1JSON.write(to: v1File, atomically: true, encoding: .utf8)
    let v1Before = try! Data(contentsOf: v1File)

    print("import from v1")
    let store = LibraryStore(directory: v2Dir, legacyURL: v1File)
    var lib = try! store.load()
    check(lib.colours.count == 3, "first launch imports the 3 valid v1 colours")
    check(lib.colours.contains { $0.hex == "#00FF00" }, "imported hex is normalised to uppercase")
    check(lib.swatches.isEmpty && lib.activeSwatchID == nil, "starts with no swatches")
    check(fm.fileExists(atPath: store.url.path), "v2 library file is created")

    print("swatches")
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var first: UUID!, second: UUID!
    lib = try! store.mutate { first = $0.createSwatch(at: t0) }
    check(lib.swatch(first)?.name == "Palette 1", "first swatch is named \"Palette 1\"")
    check(lib.activeSwatchID == first, "a new swatch becomes the pick target")
    lib = try! store.mutate { second = $0.createSwatch(at: t0.addingTimeInterval(1)) }
    check(lib.swatch(second)?.name == "Palette 2", "second swatch is named \"Palette 2\"")

    lib = try! store.mutate { $0.renameSwatch(first, to: "  Brand  ") }
    check(lib.swatch(first)?.name == "Brand", "rename trims and saves")
    lib = try! store.mutate { $0.renameSwatch(first, to: "   ") }
    check(lib.swatch(first)?.name == "Brand", "blank rename is rejected")
    check(lib.nextDefaultSwatchName() == "Palette 3", "default names keep counting up after a rename")

    print("picking")
    lib = try! store.mutate { lib in
        lib.activeSwatchID = first
        lib.addPick("#ff6600", at: t0.addingTimeInterval(10))
        lib.addPick("#FF0000", at: t0.addingTimeInterval(20))
        lib.addPick("#0033FF", at: t0.addingTimeInterval(30))
        lib.addPick("#FF0000", at: t0.addingTimeInterval(40))
    }
    check(lib.colours.count == 5, "new picks join the catalogue, existing ones are not duplicated")
    check(lib.swatch(first)?.entries.count == 3, "picks land in the active swatch once each")
    check(lib.swatch(second)?.entries.isEmpty == true, "other swatches are untouched")
    check(lib.colours.first { $0.hex == "#FF0000" }?.pickedAt == ISO8601DateFormatter().date(from: "2026-03-03T10:00:00Z"),
          "re-picking keeps the colour's original date")

    lib = try! store.mutate { lib in
        lib.activeSwatchID = nil
        lib.addPick("#123456", at: t0.addingTimeInterval(50))
    }
    check(lib.colours.count == 6 && lib.swatch(first)?.entries.count == 3,
          "with no target, picks go to the library only")

    print("ordering and copy")
    check(lib.hexes(inSwatch: first, by: .oldest) == ["#FF6600", "#FF0000", "#0033FF"], "oldest first")
    check(lib.hexes(inSwatch: first, by: .newest) == ["#0033FF", "#FF0000", "#FF6600"], "newest first")
    check(lib.hexes(inSwatch: first, by: .colour) == ["#FF0000", "#FF6600", "#0033FF"], "colour order: red, orange, blue")
    check(hexList(lib.hexes(inSwatch: first, by: .oldest)) == "#FF6600, #FF0000, #0033FF",
          "copy-all gives a comma separated list")
    check(lib.catalogueHexes(by: .newest).first == "#123456" && lib.catalogueHexes(by: .oldest).first == "#0000FF",
          "catalogue sorts by date made")
    let rainbow = sortedHexes(["#808080", "#0000FF", "#FFFFFF", "#00FF00", "#800000", "#FF0000", "#FFFF00", "#000000"]
        .map { ($0, t0) }, by: .colour)
    check(rainbow == ["#FF0000", "#800000", "#FFFF00", "#00FF00", "#0000FF", "#FFFFFF", "#808080", "#000000"],
          "colour order groups hues light to dark, greys last")

    print("removing")
    lib = try! store.mutate { $0.remove(["#FF6600"], fromSwatch: first) }
    check(lib.swatch(first)?.entries.count == 2 && lib.colours.contains { $0.hex == "#FF6600" },
          "removing from a swatch keeps the colour in the library")
    lib = try! store.mutate { $0.deleteColours(["#FF0000"]) }
    check(!lib.colours.contains { $0.hex == "#FF0000" } && lib.swatch(first)?.entries.map { $0.hex } == ["#0033FF"],
          "deleting from the library removes it from swatches too")
    lib = try! store.mutate { $0.activeSwatchID = first; $0.deleteSwatch(first) }
    check(lib.swatch(first) == nil && lib.activeSwatchID == nil && lib.colours.contains { $0.hex == "#0033FF" },
          "deleting a swatch keeps its colours and clears the pick target")

    print("persistence and safety")
    let reopened = try! LibraryStore(directory: v2Dir, legacyURL: v1File).load()
    check(reopened == lib, "library survives a reload from disk")
    var merged = 0
    lib = try! store.mutate { merged = $0.mergeLegacy(store.loadLegacy()) }
    check(merged == 1 && lib.colours.contains { $0.hex == "#FF0000" }, "re-import from v1 only adds what is missing")
    check((try! Data(contentsOf: v1File)) == v1Before, "the v1 library file is never modified")

    try! "{ this is not json".write(to: store.url, atomically: true, encoding: .utf8)
    let recovered = try! store.load()
    check(recovered.colours.count == 3, "an unreadable library is replaced by a fresh one")
    if let aside = store.quarantinedFile {
        check((try? String(contentsOf: aside, encoding: .utf8)) == "{ this is not json",
              "the unreadable file is kept aside, not overwritten")
    } else {
        check(false, "the unreadable file is kept aside, not overwritten")
    }


    print("naming")
    check(filesystemName("  Brand / Web: v2  ") == "Brand - Web- v2", "file names drop path separators and colons")
    check(filesystemName("   ") == "Untitled", "a blank name becomes Untitled")
    check(uniqueName("Brand", among: ["Brand", "Brand 2"]) == "Brand 3", "duplicate names count up")
    check(uniqueName("Fresh", among: ["Brand"]) == "Fresh", "unused names are kept as-is")

    print("export")
    var exportLib = Library()
    let brand = exportLib.createSwatch(at: t0)
    exportLib.renameSwatch(brand, to: "Brand")
    exportLib.add(["#FF0000", "#0033FF"], toSwatch: brand, at: t0)
    let dup = exportLib.createSwatch(at: t0.addingTimeInterval(1))
    exportLib.renameSwatch(dup, to: "Brand")
    exportLib.add(["#00FF00"], toSwatch: dup, at: t0)
    exportLib.createSwatch(at: t0.addingTimeInterval(2)) // empty, should not be exported
    let files = exportLib.exportFiles(by: .oldest)
    check(files.map { $0.name } == ["All Colours.txt", "Brand.txt", "Brand 2.txt"],
          "export writes All Colours plus one file per non-empty swatch, names made unique")
    check(files[1].contents == "#FF0000, #0033FF\n", "swatch files hold the comma separated list")
    check(files[0].contents == "#FF0000, #0033FF, #00FF00\n", "All Colours follows the chosen sort")

    let exportRoot = root.appendingPathComponent("export")
    try! fm.createDirectory(at: exportRoot, withIntermediateDirectories: true)
    let out1 = try! writeExport(exportLib, to: exportRoot, by: .oldest)
    let out2 = try! writeExport(exportLib, to: exportRoot, by: .oldest)
    check(out1.lastPathComponent == "\(Brand.name) Export" && out2.lastPathComponent == "\(Brand.name) Export 2",
          "each export gets its own folder, never overwriting an earlier one")
    let written = Set((try? fm.contentsOfDirectory(atPath: out1.path)) ?? [])
    check(written == ["library.json", "All Colours.txt", "Brand.txt", "Brand 2.txt"], "export folder holds json and text files")
    let roundTrip = try? JSONDecoder.library.decode(Library.self, from: Data(contentsOf: out1.appendingPathComponent("library.json")))
    check(roundTrip == exportLib, "exported library.json reads back identically")

    print("palette from image")
    var paletteLib = Library()
    let pal = paletteLib.createSwatch(named: "Sunset.jpg", hexes: ["#FF0000", "#ff0000", "#0033FF"], at: t0)
    check(paletteLib.swatch(pal)?.name == "Sunset.jpg" && paletteLib.swatch(pal)?.entries.count == 2,
          "a named swatch is created with de-duplicated colours")
    check(paletteLib.activeSwatchID == pal, "the new palette swatch becomes the pick target")
    paletteLib.createSwatch(named: "Sunset.jpg", hexes: ["#111111"], at: t0)
    check(paletteLib.swatches.map { $0.name } == ["Sunset.jpg", "Sunset.jpg 2"], "palette swatch names are made unique")

    let twoTone = testImage(width: 64, height: 64) { x, _ in x < 32 ? (255, 0, 0) : (0, 0, 255) }
    let colours = extractPalette(from: twoTone, count: 2)
    check(colours.count == 2 && colours.contains { near($0, "#FF0000") } && colours.contains { near($0, "#0000FF") },
          "k-means finds the two colours in a two-tone image: \(colours)")
    let solid = testImage(width: 16, height: 16) { _, _ in (0, 255, 0) }
    let solidColours = extractPalette(from: solid, count: 6)
    check(solidColours.count == 1 && near(solidColours[0], "#00FF00"), "near-duplicate clusters collapse: \(solidColours)")
    check(extractPalette(from: twoTone, count: 0).isEmpty, "asking for zero colours gives none")

    // Mid-tones catch gamma mistakes that pure red/green/blue cannot.
    let midTone = testImage(width: 64, height: 64) { x, _ in x < 40 ? (0xEC, 0xEC, 0xEC) : (0x75, 0x50, 0x7B) }
    let mids = extractPalette(from: midTone, count: 4)
    check(mids.count == 2 && near(mids[0], "#ECECEC") && near(mids[1], "#75507B"),
          "mid-tone colours come back exact, biggest area first: \(mids)")

    // A dialog-like image: big grey panel, purple surround, a small red button (~1% of the area).
    let dialog = testImage(width: 200, height: 100) { x, y in
        if (90..<110).contains(x) && (70..<80).contains(y) { return (0xB3, 0x25, 0x2F) }
        if (10..<190).contains(x) && (10..<90).contains(y) { return (0xEC, 0xEC, 0xEC) }
        return (0x75, 0x50, 0x7B)
    }
    let accents = extractPalette(from: dialog, count: 8)
    check(accents.count == 3 && accents.contains { near($0, "#B3252F") },
          "a small accent colour is kept and lookalikes are not padded in: \(accents)")

    runSyncTests(in: root, check: check)
    runColourTests(in: root, check: check)
    runHaloTests(check: check)
    runShortcutTests(check: check)
    runProjectTests(check: check)
    runImportTests(check: check)
    runColourSpaceTests(check: check)
    runTagTests(check: check)
    runNameTests(check: check)
    runSwatchNameTests(check: check)
    runTagScopeTests(check: check)
    runLabTests(check: check)
    runOrderTests(check: check)
    runContrastTests(check: check)
    runTypographyTests(check: check)
    runSetupTests(check: check)

    print("\n\(passed) passed, \(failed) failed")
    exit(failed == 0 ? 0 : 1)
}

// ---------- Test helpers ----------

private func near(_ a: String, _ b: String, tolerance: Double = 4 / 255) -> Bool {
    guard let x = rgbComponents(a), let y = rgbComponents(b) else { return false }
    return abs(x.r - y.r) <= tolerance && abs(x.g - y.g) <= tolerance && abs(x.b - y.b) <= tolerance
}

private func testImage(width: Int, height: Int, pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let (r, g, b) = pixel(x, y)
            let i = (y * width + x) * 4
            bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b
        }
    }
    // The provider keeps its own copy of the pixels, so the image outlives `bytes`.
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                   provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                   shouldInterpolate: false, intent: .defaultIntent)!
}

// ---------- Sync, merge and catalogues ----------
//
// Two Macs ("work" and "home") sharing one cloud folder, all inside the throwaway test folder.

private func runSyncTests(in root: URL, check: (Bool, String) -> Void) {
    let fm = FileManager.default
    let cloud = root.appendingPathComponent("cloud")
    try! fm.createDirectory(at: cloud, withIntermediateDirectories: true)
    let workStore = LibraryStore(directory: root.appendingPathComponent("work"), legacyURL: nil)
    let homeStore = LibraryStore(directory: root.appendingPathComponent("home"), legacyURL: nil)
    let work = SyncEngine(store: workStore, chosenFolder: cloud, catalogue: "Main", machine: "Work Mac")
    let home = SyncEngine(store: homeStore, chosenFolder: cloud, catalogue: "Main", machine: "Home Mac")
    let b = Date(timeIntervalSince1970: 1_760_000_000)
    func at(_ s: TimeInterval) -> Date { b.addingTimeInterval(s) }
    func hexes(_ l: Library) -> Set<String> { Set(l.colours.map { $0.hex }) }
    func plan(_ e: SyncEngine) -> SyncPlan? {
        switch try? e.check() {
        case .quiet(let p)?, .incoming(let p)?: return p
        default: return nil
        }
    }
    func isIncoming(_ e: SyncEngine) -> Bool { if case .incoming? = try? e.check() { return true }; return false }
    func isQuiet(_ e: SyncEngine) -> Bool { if case .quiet? = try? e.check() { return true }; return false }
    func isInSync(_ e: SyncEngine) -> Bool { if case .inSync? = try? e.check() { return true }; return false }

    print("sync: first use")
    var brand: UUID!
    try! workStore.mutate { lib in
        lib.addPick("#111111", at: at(10))
        lib.addPick("#222222", at: at(20))
        brand = lib.createSwatch(at: at(30))
        lib.renameSwatch(brand, to: "Brand", at: at(31))
        lib.add(["#111111"], toSwatch: brand, at: at(40))
    }
    if case .firstSync? = try? work.check() { check(true, "an empty sync folder is recognised as a first sync") }
    else { check(false, "an empty sync folder is recognised as a first sync") }
    try! work.push(try! workStore.load())
    check(fm.fileExists(atPath: cloud.appendingPathComponent("MMFFDev Colour 3 Sync/Main/library.json").path),
          "the library is saved under MMFFDev Colour 3 Sync/<catalogue>")
    check(isInSync(work), "straight after saving, the Mac is in sync")

    check(isQuiet(home), "a Mac that has never used the catalogue takes the synced copy without asking")
    try! home.settle(plan(home)!)
    check(canonical(try! homeStore.load()) == canonical(try! workStore.load()), "home now matches work")

    print("sync: both Macs change things")
    try! homeStore.mutate { lib in
        lib.activeSwatchID = brand
        lib.addPick("#333333", at: at(100))
        lib.deleteColours(["#222222"], at: at(110))
        lib.renameSwatch(brand, to: "Brand 2026", at: at(120))
    }
    check(isQuiet(home), "changes made only on this Mac are sent without asking")
    try! home.settle(plan(home)!)
    try! workStore.mutate { $0.addPick("#444444", at: at(105)) } // work was offline

    check(isIncoming(work), "work sees that the synced copy has changed")
    let p = plan(work)!
    check(p.incoming.coloursAdded == 1 && p.incoming.coloursRemoved == 1 && p.incoming.swatchesChanged == 1 && p.incoming.swatchesAdded == 0,
          "the summary lists what home did: 1 new colour, 1 deleted, 1 changed swatch")
    check(p.outgoing.coloursAdded == 1, "and what work will contribute: 1 new colour")
    let before = work.backups(in: work.remoteBackups).count
    try! work.perform(.merge, plan: p, at: at(130))
    let merged = try! workStore.load()
    check(hexes(merged) == ["#111111", "#333333", "#444444"], "merge keeps new colours from both Macs and honours the deletion")
    check(merged.swatch(brand)?.name == "Brand 2026", "the newer swatch name wins")
    check(Set(merged.swatch(brand)?.entries.map { $0.hex } ?? []) == ["#111111", "#333333", "#444444"],
          "swatch contents are combined")
    check(work.backups(in: work.remoteBackups).count == before + 2 && work.backups(in: work.localBackups).count == 2,
          "both sides are backed up before merging, in the sync folder and on this Mac")
    let savedBefore = work.backups(in: work.localBackups)
        .compactMap { try? JSONDecoder.library.decode(Library.self, from: Data(contentsOf: $0)) }
    check(savedBefore.contains { hexes($0).contains("#222222") }, "a backup still holds the colour that was deleted")

    check(isIncoming(home), "home then sees work's colour")
    try! home.perform(.merge, plan: plan(home)!, at: at(140))
    check(canonical(try! homeStore.load()) == canonical(try! workStore.load()) && isInSync(home) && isInSync(work),
          "after both have synced the two Macs are identical")

    print("sync: deleting and re-adding")
    try! workStore.mutate { $0.addPick("#222222", at: at(50)) } // clock says earlier than the deletion
    try! work.settle(plan(work)!)
    try! home.perform(.merge, plan: plan(home)!, at: at(150))
    check(hexes(try! homeStore.load()).contains("#222222"), "a colour picked again after being deleted comes back everywhere")
    try! homeStore.mutate { $0.remove(["#333333"], fromSwatch: brand, at: at(160)) }
    try! home.settle(plan(home)!)
    try! work.perform(.merge, plan: plan(work)!, at: at(170))
    let afterRemove = try! workStore.load()
    check(afterRemove.swatch(brand)?.entries.contains { $0.hex == "#333333" } == false && hexes(afterRemove).contains("#333333"),
          "removing from a swatch syncs, and the colour stays in the library")
    var temp: UUID!
    try! workStore.mutate { temp = $0.createSwatch(at: at(180)) }
    try! work.settle(plan(work)!)
    try! home.perform(.merge, plan: plan(home)!, at: at(185))
    try! homeStore.mutate { $0.deleteSwatch(temp, at: at(190)) }
    try! home.settle(plan(home)!)
    try! work.perform(.merge, plan: plan(work)!, at: at(195))
    check((try! workStore.load()).swatch(temp) == nil, "deleting a swatch syncs")

    print("sync: conflicted copies and choices")
    var stray = Library()
    stray.addPick("#999999", at: at(200))
    let strayURL = work.folder.appendingPathComponent("library (Home Mac's conflicted copy).json")
    try! JSONEncoder.library.encode(stray).write(to: strayURL)
    check(isIncoming(work), "a conflicted copy left by the cloud service is noticed")
    try! work.perform(.merge, plan: plan(work)!, at: at(210))
    check(hexes(try! workStore.load()).contains("#999999"), "its colours are merged in")
    check(!fm.fileExists(atPath: strayURL.path)
          && work.backups(in: work.remoteBackups).contains { $0.lastPathComponent.contains("conflicted copy") },
          "and the file is moved to Backups, not deleted")

    try! home.perform(.merge, plan: plan(home)!, at: at(220))
    try! homeStore.mutate { $0.addPick("#777777", at: at(230)) }
    try! home.settle(plan(home)!)
    try! work.perform(.keepLocal, plan: plan(work)!, at: at(240))
    check(!hexes(try! workStore.load()).contains("#777777"), "\"Keep This Mac's\" leaves this Mac as it was")
    try! home.perform(.merge, plan: plan(home)!, at: at(250))
    check(!hexes(try! homeStore.load()).contains("#777777"), "and the choice holds when the other Mac syncs")
    try! homeStore.mutate { $0.deleteColours(["#111111"], at: at(245)) }
    try! home.settle(plan(home)!)
    try! work.perform(.keepLocal, plan: plan(work)!, at: at(246))
    try! home.perform(.merge, plan: plan(home)!, at: at(247))
    check(hexes(try! homeStore.load()).contains("#111111") && hexes(try! workStore.load()).contains("#111111"),
          "\"Keep This Mac's\" also holds on to something the other Mac had deleted")
    check(work.backups(in: work.remoteBackups)
            .compactMap { try? JSONDecoder.library.decode(Library.self, from: Data(contentsOf: $0)) }
            .contains { hexes($0).contains("#777777") },
          "what was set aside is still in a backup")

    try! workStore.mutate { $0.addPick("#ABCDEF", at: at(260)) }
    try! work.settle(plan(work)!)
    try! homeStore.mutate { $0.addPick("#FEDCBA", at: at(265)) }
    try! home.perform(.useSynced, plan: plan(home)!, at: at(270))
    let homeNow = hexes(try! homeStore.load())
    check(homeNow.contains("#ABCDEF") && !homeNow.contains("#FEDCBA"), "\"Use Synced Library\" replaces this Mac's copy")

    print("sync: when things go wrong")
    let good = try! Data(contentsOf: work.remoteURL)
    let workBefore = try! Data(contentsOf: workStore.url)
    try! "{ not json".write(to: work.remoteURL, atomically: true, encoding: .utf8)
    var refused = false
    do { _ = try work.check() } catch SyncError.unreadable { refused = true } catch {}
    check(refused && (try! String(contentsOf: work.remoteURL, encoding: .utf8)) == "{ not json"
          && (try! Data(contentsOf: workStore.url)) == workBefore,
          "an unreadable synced file stops the sync and nothing is overwritten")
    try! good.write(to: work.remoteURL)

    let gone = SyncEngine(store: workStore, chosenFolder: root.appendingPathComponent("unplugged"),
                          catalogue: "Main", machine: "Work Mac")
    var missing = false
    do { _ = try gone.check() } catch SyncError.folderMissing { missing = true } catch {}
    check(missing, "a sync folder that isn't there is reported, not recreated somewhere else")

    work.backupsToKeep = 3
    work.prune()
    check(work.backups(in: work.remoteBackups).count == 3 && work.backups(in: work.localBackups).count == 3,
          "only the newest backups are kept, up to the limit")
    work.backupsToKeep = 0
    try! work.backup(Library(), label: "extra", at: at(300))
    work.prune()
    check(work.backups(in: work.localBackups).count == 4, "a limit of 0 keeps every backup")

    let inside = SyncEngine(store: workStore, chosenFolder: cloud.appendingPathComponent("MMFFDev Colour 3 Sync"),
                            catalogue: "Main", machine: "Work Mac")
    check(inside.remoteURL == work.remoteURL, "choosing the sync folder itself works the same as choosing its parent")

    print("catalogues")
    let cats = Catalogues(root: root.appendingPathComponent("cats"), legacyURL: nil)
    check(cats.names() == ["Main"], "a fresh install has just Main")
    _ = try! cats.store(for: "Main").load() // as the app does on first launch
    let client = try! cats.create("Client / Web")
    check(client == "Client - Web" && cats.names() == ["Main", "Client - Web"], "a new catalogue gets a safe folder name")
    check((try! cats.create("Client / Web")) == "Client - Web 2", "duplicate catalogue names count up")
    check((try! cats.store(for: client).load()) == Library(), "a new catalogue starts empty, without the v1 colours")
    try! cats.store(for: client).mutate { $0.addPick("#123123", at: at(10)) }
    check((try! cats.store(for: "Main").load()).colours.isEmpty, "catalogues are separate from each other")
    let exported = try! writeExport(try! workStore.load(), to: root.appendingPathComponent("export"), by: .oldest)
    let opened = try! cats.importFile(exported.appendingPathComponent("library.json"), named: "From Export")
    check(canonical(try! cats.store(for: opened).load()) == canonical(try! workStore.load()),
          "a library file from an export or backup opens as a catalogue")

    let clientSync = SyncEngine(store: cats.store(for: client), chosenFolder: cloud, catalogue: client, machine: "Work Mac")
    try! clientSync.push(try! cats.store(for: client).load())
    check(Set(SyncEngine.catalogues(in: cloud)) == ["Main", "Client - Web"], "each catalogue syncs to its own folder")
    check(hexes(try! JSONDecoder.library.decode(Library.self, from: Data(contentsOf: work.remoteURL))).contains("#123123") == false,
          "syncing one catalogue never touches another")

    print("renaming catalogues")
    let renameRoot = root.appendingPathComponent("rename")
    let mine = Catalogues(root: renameRoot.appendingPathComponent("work"), legacyURL: nil)
    let theirs = Catalogues(root: renameRoot.appendingPathComponent("home"), legacyURL: nil)
    let shared = renameRoot.appendingPathComponent("cloud")
    try! fm.createDirectory(at: shared, withIntermediateDirectories: true)
    try! mine.store(for: "Main").mutate { $0.addPick("#AA0000", at: at(10)) }
    let mainSync = SyncEngine(store: mine.store(for: "Main"), chosenFolder: shared, catalogue: "Main", machine: "Work")
    try! mainSync.push(try! mine.store(for: "Main").load())
    try! theirs.store(for: "Main").save(try! mine.store(for: "Main").load()) // home has synced it too
    check(mine.names() == ["Main"], "before renaming there is just Main")

    try! SyncEngine.rename(in: shared, from: "Main", to: "Studio")
    let studio = try! mine.rename("Main", to: "Studio")
    check(studio == "Studio" && mine.names() == ["Studio"], "Main can be renamed, and then there is no Main")
    check((try! mine.store(for: "Studio").load()).colours.map { $0.hex } == ["#AA0000"], "the renamed catalogue keeps its colours")
    check(CatalogueFiles.index(in: mine.root) == nil && !fm.fileExists(atPath: mine.root.appendingPathComponent(CatalogueFiles.unfiled).path)
          && fm.fileExists(atPath: mine.directory(for: "Studio").appendingPathComponent("Studio.colcat").path),
          "Main's files move into a folder of their own, and the catalogue's file takes the catalogue's name")
    check(Set(SyncEngine.catalogues(in: shared)) == ["Studio"], "the sync folder is renamed too, and the old name no longer lists")
    check(SyncEngine.renamedName(in: shared, of: "Main") == "Studio", "the old sync folder says where it went")
    check((try! mine.store(for: "Main").load()) == Library(), "a Main made after a rename starts empty, not seeded again")

    let homeMain = SyncEngine(store: theirs.store(for: "Main"), chosenFolder: shared, catalogue: "Main", machine: "Home")
    if case .renamed(let to)? = try? homeMain.check() { check(to == "Studio", "the other Mac is told to follow the rename") }
    else { check(false, "the other Mac is told to follow the rename") }
    try! theirs.rename("Main", to: "Studio")
    check(theirs.names() == ["Studio"] && isInSync(SyncEngine(store: theirs.store(for: "Studio"), chosenFolder: shared, catalogue: "Studio", machine: "Home")),
          "after following, the other Mac is in sync under the new name")

    var taken = false
    try! theirs.create("Client")
    do { try theirs.rename("Studio", to: "client") } catch CatalogueError.nameTaken { taken = true } catch {}
    check(taken, "renaming to a name already in use is refused, whatever the case")
    check((try! theirs.rename("Client", to: "Client / 2026")) == "Client - 2026", "renamed folders get safe names")
    var syncTaken = false
    try! SyncEngine(store: theirs.store(for: "Client - 2026"), chosenFolder: shared, catalogue: "Client - 2026", machine: "Home")
        .push(try! theirs.store(for: "Client - 2026").load())
    do { try SyncEngine.rename(in: shared, from: "Studio", to: "Client - 2026") } catch CatalogueError.nameTaken { syncTaken = true } catch {}
    check(syncTaken, "a rename that would collide in the sync folder is refused")
    try! SyncEngine.rename(in: shared, from: "Never synced", to: "Whatever")
    check(!fm.fileExists(atPath: SyncEngine.root(in: shared).appendingPathComponent("Whatever").path),
          "renaming a catalogue that was never synced leaves the sync folder alone")

    print("projects, order and tags")
    var org = Library()
    let web = org.createSwatch(named: "Web", hexes: ["#111111"], at: at(1))
    let print_ = org.createSwatch(named: "Print", hexes: ["#222222"], at: at(2))
    _ = org.createSwatch(named: "Loose", hexes: ["#333333"], at: at(3))
    let proj = org.createProject(named: "My Project", at: at(10))
    check(org.createProject(named: "My Project", at: at(11)) != proj && org.projects.map { $0.name } == ["My Project", "My Project 2"],
          "project names are made unique")
    let second = org.projects[1].id
    org.move(web, to: proj, index: 0, at: at(20))
    org.move(print_, to: proj, index: 1, at: at(21))
    check(org.palettes(in: proj).map { $0.name } == ["Web", "Print"] && org.palettes(in: nil).map { $0.name } == ["Loose"],
          "palettes go into a project in the order given; the rest stay loose")
    org.move(print_, to: proj, index: 0, at: at(22))
    check(org.palettes(in: proj).map { $0.name } == ["Print", "Web"], "a palette can be moved up within its project")
    org.move(web, to: second, index: 0, at: at(23))
    check(org.palettes(in: proj).map { $0.name } == ["Print"] && org.palettes(in: second).map { $0.name } == ["Web"],
          "a palette can be dragged to another project")
    check(org.renameProject(proj, to: "Client A", at: at(24)) && org.project(proj)?.name == "Client A", "projects can be renamed")
    org.placeProjects([second, proj], at: at(25))
    check(org.orderedProjects.map { $0.name } == ["My Project 2", "Client A"], "projects can be reordered")
    org.setTags(ofPalette: web, ["Brand", " brand ", "dark", ""], at: at(30))
    org.setTags(ofColour: "#222222", ["print", "CMYK"], at: at(31))
    check(org.swatch(web)?.tagList == ["Brand", "dark"] && org.allTags == ["Brand", "CMYK", "dark", "print"],
          "tags are trimmed and de-duplicated, and listed across swatches and palettes")
    check(org.hexes(tagged: "brand") == ["#111111"] && org.hexes(tagged: "cmyk") == ["#222222"],
          "a tag finds swatches tagged directly and those in a tagged palette")
    let saved = try? JSONDecoder.library.decode(Library.self, from: JSONEncoder.library.encode(org))
    check(saved == org, "projects, positions and tags survive saving")

    var elsewhere = org
    elsewhere.deleteProject(second, at: at(40))
    elsewhere.setTags(ofPalette: web, ["light"], at: at(41))
    var here = org
    here.renameProject(second, to: "Renamed here", at: at(39))
    here.setTags(ofColour: "#222222", ["print"], at: at(42))
    let joined = mergeLibraries(local: here, remote: elsewhere)
    check(joined.project(second) == nil && joined.swatch(web)?.projectID == nil,
          "a project deleted on one Mac stays deleted, and its palettes fall back to the loose list")
    check(joined.swatch(web)?.tagList == ["light"] && joined.colours.first { $0.hex == "#222222" }?.tags == ["print"],
          "the newer tags win on each side")
    check(change(from: here, to: joined).projectsRemoved == 1, "the merge summary mentions deleted projects")
    let kept = replacing(elsewhere, with: here, at: at(50))
    check(kept.project(second) != nil && mergeLibraries(local: kept, remote: elsewhere).project(second) != nil,
          "\"Keep This Mac's\" keeps a project the other side deleted")

    print("design pack")
    let pack = org.designPack(named: "Client A", owner: "MMFFDev", licence: DesignPack.defaultLicence, at: at(100))
    check(pack.folderName == "Client A Design Pack" && pack.projects.map { $0.name } == ["My Project 2", "Client A", "Palettes"],
          "a catalogue pack has a folder per project and one for loose palettes, in sidebar order")
    let printPalette = pack.projects[1].palettes[0]
    check(printPalette.folder == "client-a/print" && printPalette.css == "client-a/print/print.css"
          && printPalette.swatches[0].file == "client-a/print/swatches/01-\(slug(colourName("#222222")))-222222.png",
          "files are named after the palette and swatch, numbered in order: \(printPalette.swatches[0].file)")
    check(printPalette.swatches[0].tags == ["print", "CMYK"], "swatch tags travel with the pack")
    let files = pack.textFiles(options: ExportOptions())
    check(files.map { $0.path }.prefix(3) == ["README.md", "pack.json", "LICENSE.md"] && files.contains { $0.path == "client-a/print/print.css" },
          "the pack holds a README, the JSON, the licence and a CSS file per palette")
    let cssText = files.first { $0.path == "client-a/print/print.css" }!.text
    check(cssText.contains(":root {") && cssText.contains("  --swatch-\(slug(colourName("#222222"))): #222222;"), "each CSS file is a :root block of --swatch tokens")
    let packJSON = (try? JSONSerialization.jsonObject(with: pack.json().data(using: .utf8)!)) as? [String: Any]
    let firstProject = (packJSON?["projects"] as? [[String: Any]])?.first
    let firstSwatch = (((firstProject?["palettes"] as? [[String: Any]])?.first?["swatches"]) as? [[String: Any]])?.first
    check(packJSON?["format"] as? String == "mmffdev-colour-pack" && firstProject?["name"] as? String == "My Project 2"
          && firstSwatch?["hex"] as? String == "#111111" && (firstSwatch?["rgb"] as? [Int]) == [17, 17, 17]
          && (firstSwatch?["file"] as? String)?.hasSuffix(".png") == true,
          "pack.json parses and describes projects, palettes and swatches")
    check(pack.licence().contains("\u{00A9} \(Calendar.current.component(.year, from: at(100))) MMFFDev") && pack.licence().contains("\"Client A\""),
          "the licence names the owner, the year and the pack")
    check(pack.readme().contains("### Print") && pack.readme().contains("| 1 | \(colourName("#222222")) | #222222 |"), "the README lists every swatch")
    let onePalette = org.designPack(named: "Web", palettes: [web], owner: "", licence: "x", at: at(100))
    check(onePalette.projects.count == 1 && onePalette.projects[0].palettes[0].folder == "web" && onePalette.licence() == "x\n",
          "a single-palette pack keeps the palette folder at the top level")

    print("older files")
    let old = """
    { "version": 2, "colours": [ { "hex": "#FF0000", "pickedAt": "2026-03-03T10:00:00Z" } ],
      "swatches": [ { "id": "11111111-2222-3333-4444-555555555555", "name": "Old", "createdAt": "2026-03-03T10:00:00Z",
                      "entries": [ { "hex": "#FF0000", "addedAt": "2026-03-03T10:00:00Z" } ] } ] }
    """
    let decoded = try? JSONDecoder.library.decode(Library.self, from: old.data(using: .utf8)!)
    check(decoded?.colours.count == 1 && decoded?.swatches.first?.name == "Old" && decoded?.deleted.isEmpty == true,
          "a library saved before sync existed still opens")
}

// ---------- Colour formats, names, contrast, harmonies, exports ----------

private func runColourTests(in root: URL, check: (Bool, String) -> Void) {
    print("colour formats")
    let fiji = "#4F8093"
    check(ColourFormat.hex.text(fiji) == "#4F8093" && ColourFormat.hex.text(fiji, lowercase: true) == "#4f8093", "hex, either case")
    check(ColourFormat.hexBare.text(fiji) == "4F8093", "hex without the hash")
    check(ColourFormat.rgb.text(fiji) == "79, 128, 147" && ColourFormat.cssRGB.text(fiji) == "rgb(79 128 147)", "RGB and CSS rgb()")
    check(ColourFormat.hsv.text(fiji) == "197, 46%, 58%", "HSV: \(ColourFormat.hsv.text(fiji))")
    check(ColourFormat.hsl.text(fiji) == "197, 30%, 44%" && ColourFormat.cssHSL.text(fiji) == "hsl(197 30% 44%)",
          "HSL: \(ColourFormat.hsl.text(fiji))")
    PrintCondition.current = PrintCondition.fallback
    let fijiInks = PrintBuild.of(RGBSpace.srgb.master(of: [79.0 / 255, 128.0 / 255, 147.0 / 255]), press: PressProfiles.generic, intent: .relative)?.inks.map { "\(Int(($0 * 100).rounded()))" } ?? []
    check(fijiInks.count == 4 && ColourFormat.cmyk.fields(fiji) == fijiInks && ColourFormat.cmyk.text(fiji) == fijiInks.joined(separator: ", ") && ColourFormat.cmyk.text(fiji) != "46, 13, 0, 42",
          "CMYK is the build for the press in force, not the old sum: \(ColourFormat.cmyk.text(fiji))")
    check(ColourFormat.float.text(fiji) == "0.310, 0.502, 0.576", "float RGB: \(ColourFormat.float.text(fiji))")
    check(ColourFormat.linear.text("#808080") == "0.216, 0.216, 0.216", "linear RGB: \(ColourFormat.linear.text("#808080"))")
    check(ColourFormat.swiftUI.text("#FF0000") == "Color(red: 1.000, green: 0.000, blue: 0.000)", "SwiftUI")
    check(ColourFormat.cmyk.text("#FFFFFF") == "0, 0, 0, 0" && ColourFormat.cmyk.fields("#000000").count == 4 && ColourFormat.hsl.text("#FFFFFF") == "0, 0%, 100%",
          "white takes no ink, black gives a build, and neither divides by zero")
    PrintCondition.current = ProfileChannel(space: ProfileChannel.print, press: "No Such Press", intent: .relative)
    check(ColourFormat.cmyk.fields(fiji) == ["\u{2014}"] && PrintCondition.name() == "No Such Press, Relative Colorimetric", "a press that is not on this Mac gives a dash, never a made-up build")
    PrintCondition.current = PrintCondition.fallback
    check(ColourFormat.rgb.fields(fiji) == ["79", "128", "147"] && ColourFormat.cmyk.fields(fiji).count == 4,
          "card rows split into columns")
    check(ColourFormat.allCases.allSatisfy { !$0.text("#123456").isEmpty && !$0.title.isEmpty }, "every format produces text")
    // Oklab's reference: white is L 1, a and b 0; sRGB red is L 0.628, C 0.258, h 29.2.
    check(ColourFormat.oklch.fields("#FFFFFF") == ["1.000", "0.000", "0.0"] && ColourFormat.oklch.fields("#FF0000") == ["0.628", "0.258", "29.2"]
          && ColourFormat.oklab.fields("#FFFFFF") == ["1.000", "0.000", "0.000"],
          "OKLCH and Oklab come from the master and match Ottosson's reference values")
    // CIELAB against the published values: the D50 white is L 100, a and b 0; sRGB red adapted to D50 by Bradford is L 54.3, a 80.8, b 69.9,
    // and as CIELCh, C 106.8 at h 40.9; CIELUV puts the white at 100, 0, 0 too.
    check(ColourFormat.lab.fields("#FFFFFF") == ["100.0", "0.0", "0.0"] && ColourFormat.lab.fields("#FF0000") == ["54.3", "80.8", "69.9"]
          && ColourFormat.lch.fields("#FF0000") == ["54.3", "106.8", "40.9"] && ColourFormat.luv.fields("#FFFFFF") == ["100.0", "0.0", "0.0"],
          "CIELAB, CIELCh and CIELUV come from the master against the D50 white and match the published values")

    print("round trips")
    let samples = ["#4F8093", "#FF6600", "#0033FF", "#C22832", "#76507A", "#101010", "#EEEEEE", "#00FF7F"]
    check(samples.allSatisfy { h in
        let v = ColourValues(h)!.hslUnit
        return ColourValues(hexFrom(h: v.h, s: v.s, l: v.l)).map { abs($0.r - ColourValues(h)!.r) <= 1
            && abs($0.g - ColourValues(h)!.g) <= 1 && abs($0.b - ColourValues(h)!.b) <= 1 } ?? false
    }, "hex to HSL and back lands on the same colour")

    print("names and groups")
    check(colourName("#FF0000") == "Red" && colourName("#4682B4") == "Steel Blue", "exact CSS colours get their name")
    check(colourName("#4580B2") == "Steel Blue", "a near miss gets the nearest name: \(colourName("#4580B2"))")
    check(Set(namedColours.map { $0.hex }).count == namedColours.filter { !["Aqua", "Fuchsia"].contains($0.name) }.count
          || namedColours.allSatisfy { normaliseHex($0.hex) != nil }, "the name table holds valid hex values")
    check(namedColours.allSatisfy { normaliseHex($0.hex) == $0.hex }, "every named colour is a valid uppercase hex")
    check(colourGroup("#FF0000") == .reds && colourGroup("#FF8800") == .oranges && colourGroup("#FFEE00") == .yellows
          && colourGroup("#00AA00") == .greens && colourGroup("#0044FF") == .blues && colourGroup("#8800CC") == .purples
          && colourGroup("#FF44AA") == .pinks && colourGroup("#00AAAA") == .teals, "hues fall into the expected groups")
    check(colourGroup("#808080") == .neutrals && colourGroup("#FFFFFF") == .neutrals && colourGroup("#000000") == .neutrals
          && colourGroup("#6B4423") == .browns, "greys are neutrals and dark oranges are browns")
    check(slug("Steel Blue") == "steel-blue" && slug("  Brand / Web: v2 ") == "brand-web-v2" && slug("!!!") == "colour"
          && slug("Café Crème") == "cafe-creme", "names become safe identifiers")

    print("contrast")
    check(abs(contrastRatio("#000000", "#FFFFFF") - 21) < 0.01 && abs(contrastRatio("#FFFFFF", "#FFFFFF") - 1) < 0.01,
          "black on white is 21:1, a colour on itself is 1:1")
    check(abs(contrastRatio("#767676", "#FFFFFF") - 4.54) < 0.01, "#767676 on white is the well-known 4.54:1")
    check(contrastGrade(7.1) == "AAA" && contrastGrade(4.5) == "AA" && contrastGrade(3.2) == "AA large" && contrastGrade(2) == "fail",
          "ratios map to WCAG grades")
    check(readableText(on: "#101010") == "#FFFFFF" && readableText(on: "#F5F5F5") == "#000000" && readableText(on: "#FFFF00") == "#000000",
          "card text is white on dark colours and black on light ones")

    print("harmonies")
    check(Harmony.complementary.colours(from: "#FF0000") == ["#FF0000", "#00FFFF"], "complement of red is cyan")
    check(Harmony.triadic.colours(from: "#FF0000") == ["#FF0000", "#00FF00", "#0000FF"], "triad of red is red, green, blue")
    check(Harmony.analogous.colours(from: "#FF0000").count == 3 && Harmony.tetradic.colours(from: fiji).count == 4
          && Harmony.splitComplementary.colours(from: fiji).count == 3, "each harmony gives the right number of colours")
    let scale = Harmony.scale.colours(from: fiji)
    let lum = scale.compactMap { ColourValues($0)?.luminance }
    check(scale.count == 11 && zip(lum, lum.dropFirst()).allSatisfy { $0 > $1 }, "the 50–950 scale runs light to dark")
    let tints = Harmony.tintsAndShades.colours(from: fiji)
    check(tints.count == 9 && tints[4] == fiji, "tints and shades keep the original colour in the middle")

    print("finding colours in text")
    check(hexColours(in: "color: #ff6600; background:#FFF; border: 1px solid #12345678; x: #12; y: #GGGGGG; z: #ff6600")
          == ["#FF6600", "#FFFFFF", "#123456"], "hex colours are found in pasted CSS, short and alpha forms included")
    check(hexColours(in: "issue #1234 and #abcdefg are not colours").isEmpty, "things that only look like colours are ignored")

    print("exports")
    let brand = ExportPalette(name: "Brand 2026", colours: [
        ExportColour(name: "Steel Blue", hex: "#4F8093"), ExportColour(name: "Orange Red", hex: "#FF6600"),
        ExportColour(name: "Steel Blue", hex: "#4682B4"),
    ])
    func text(_ f: ExportFormat, _ p: [ExportPalette] = [], _ o: ExportOptions = ExportOptions()) -> String {
        String(data: f.data(p.isEmpty ? [brand] : p, options: o)!, encoding: .utf8)!
    }
    let css = text(.css)
    check(css.contains(":root {") && css.contains("  --swatch-steel-blue: #4f8093;") && css.contains("  --swatch-orange-red: #ff6600;"),
          "tokens.css declares --swatch-<name> variables")
    check(css.contains("  --swatch-steel-blue-2: #4682b4;"), "two colours with the same name get distinct variables")
    var numbered = ExportOptions(); numbered.naming = .numbers; numbered.prefix = "brand"; numbered.lowercaseHex = false
    check(text(.css, [], numbered).contains("  --brand-1: #4F8093;") && text(.css, [], numbered).contains("  --brand-3: #4682B4;"),
          "prefix, numbering and hex case follow the options")
    let ui = ExportPalette(name: "UI", colours: [ExportColour(name: "Red", hex: "#FF0000")])
    check(text(.css, [brand, ui]).contains("  --swatch-brand-2026-steel-blue: #4f8093;") && text(.css, [brand, ui]).contains("  --swatch-ui-red: #ff0000;"),
          "several palettes in one file are told apart by palette name")
    check(text(.scss).contains("$swatch-steel-blue: #4f8093;"), "SCSS variables")
    check(text(.tailwind4).contains("@theme {") && text(.tailwind4).contains("  --color-steel-blue: #4f8093;"), "Tailwind v4 @theme")
    check(text(.tailwind3).contains("'brand-2026': {") && text(.tailwind3).contains("'orange-red': '#ff6600',"), "Tailwind v3 config")
    func token(_ f: ExportFormat, _ name: String) -> [String: Any]? {
        let root = (try? JSONSerialization.jsonObject(with: text(f).data(using: .utf8)!)) as? [String: Any]
        return (root?["brand-2026"] as? [String: Any])?[name] as? [String: Any]
    }
    let value = token(.tokens, "steel-blue")?["$value"] as? [String: Any]
    let parts = value?["components"] as? [Double]
    check(token(.tokens, "orange-red")?["$type"] as? String == "color" && value?["colorSpace"] as? String == "srgb"
          && value?["hex"] as? String == "#4f8093" && parts?.count == 3 && abs((parts?[0] ?? 0) - 0.3098) < 0.0001,
          "design tokens follow the 2025.10 format: colour space, components and hex")
    check(token(.tokensLegacy, "steel-blue")?["$value"] as? String == "#4f8093", "the older token format keeps a plain hex value")

    let aco = ExportFormat.aco.data([brand])!
    func a16(_ at: Int) -> Int { aco[at..<(at + 2)].reduce(0) { $0 << 8 | Int($1) } }
    let v2 = 4 + 3 * 10
    check(a16(0) == 1 && a16(2) == 3 && a16(4) == 0 && a16(6) == 79 * 257 && a16(8) == 128 * 257 && a16(10) == 147 * 257,
          "ACO version 1 section holds 16-bit RGB")
    check(a16(v2) == 2 && a16(v2 + 2) == 3 && a16(v2 + 4 + 10) == 0 && a16(v2 + 4 + 12) == "Steel Blue".utf16.count + 1,
          "ACO version 2 section follows with names")
    var end = v2 + 4
    for c in brand.colours { end += 10 + 4 + (c.name.utf16.count + 1) * 2 }
    check(end == aco.count, "ACO file is exactly as long as its records")
    check(text(.swift).contains("enum Brand2026Colours {") && text(.swift).contains("static let steelBlue = Color(red: 0.310, green: 0.502, blue: 0.576)"),
          "Swift colours")
    check(text(.android).contains("<color name=\"swatch_steel_blue\">#4f8093</color>"), "Android colors.xml")
    let gpl = text(.gpl)
    check(gpl.hasPrefix("GIMP Palette\nName: Brand 2026\n") && gpl.contains(" 79 128 147\tSteel Blue"), "GIMP palette")
    check(text(.text) == "#4f8093, #ff6600, #4682b4\n", "plain hex list")

    let ase = ExportFormat.ase.data([brand])!
    func be32(_ at: Int) -> Int { ase[at..<(at + 4)].reduce(0) { $0 << 8 | Int($1) } }
    func be16(_ at: Int) -> Int { ase[at..<(at + 2)].reduce(0) { $0 << 8 | Int($1) } }
    check(String(data: ase[0..<4], encoding: .ascii) == "ASEF" && be16(4) == 1 && be16(6) == 0 && be32(8) == 5,
          "ASE header: signature, version 1.0, five blocks for three colours in a group")
    var at = 12, blocks: [Int] = [], sound = true
    while at < ase.count {
        guard at + 6 <= ase.count else { sound = false; break }
        blocks.append(be16(at)); at += 6 + be32(at + 2)
    }
    check(sound && at == ase.count && blocks == [0xC001, 1, 1, 1, 0xC002], "ASE blocks are well formed and end exactly at the file's end")
    let first = 12 + 6 + be32(14) // first colour block
    let nameUnits = be16(first + 6)
    let model = first + 6 + 2 + nameUnits * 2
    check(String(data: ase[model..<(model + 4)], encoding: .ascii) == "RGB "
          && abs(Float(bitPattern: UInt32(be32(model + 4))) - 79.0 / 255) < 0.0001, "ASE colours are RGB floats")
    let long = ExportPalette(name: "Long", colours: (0..<31).map { ExportColour(name: "C\($0)", hex: String(format: "#%02X0000", $0 * 8)) })
    let act = ExportFormat.act.data([brand])!
    check(act.count == 772 && Array(act[0..<6]) == [79, 128, 147, 255, 102, 0] && Array(act[9..<12]) == [0, 0, 0]
          && Array(act[768...]) == [0, 3, 0xFF, 0xFF], "Adobe colour table is 256 RGB slots, then the count in use and no transparent colour")
    check(ExportFormat.act.data([long, long, long, long, long, long, long, long, long])!.count == 772, "a colour table stops at 256 colours")
    let acb = ExportFormat.acb.data([brand])!
    func b16(_ at: Int) -> Int { acb[at..<(at + 2)].reduce(0) { $0 << 8 | Int($1) } }
    func b32(_ at: Int) -> Int { acb[at..<(at + 4)].reduce(0) { $0 << 8 | Int($1) } }
    var cursor = 8
    var strings: [String] = []
    func acbText() -> String {
        let n = b32(cursor)
        let units = (0..<n).map { UInt16(b16(cursor + 4 + $0 * 2)) }
        cursor += 4 + n * 2
        return String(utf16CodeUnits: units, count: n)
    }
    for _ in 0..<4 { strings.append(acbText()) }
    check(String(data: acb[0..<4], encoding: .ascii) == "8BCB" && b16(4) == 1 && b16(6) >= 3000 && strings[0] == "Brand 2026"
          && b16(cursor) == 3 && b16(cursor + 2) == 3 && b16(cursor + 6) == 0,
          "Adobe colour book header: signature, version 1, an id clear of Adobe's own, title, three RGB colours")
    cursor += 8
    var book: [String] = []
    for _ in 0..<3 {
        let name = acbText()
        book.append("\(name)|\(String(data: acb[cursor..<(cursor + 6)], encoding: .ascii) ?? "")|\(acb[cursor + 6]),\(acb[cursor + 7]),\(acb[cursor + 8])")
        cursor += 9
    }
    check(book == ["Steel Blue|1     |79,128,147", "Orange Red|2     |255,102,0", "Steel Blue|3     |70,130,180"] && String(data: acb[cursor...], encoding: .ascii) == "spflproc",
          "each colour in the book has its name, a six-character code and RGB bytes, and the book ends by saying it holds process colours")
    let jsx = text(.afterEffects)
    check(jsx.contains("{ name: \"Brand 2026\", colours: [") && jsx.contains("[\"Steel Blue\", 0.3098, 0.5020, 0.5765],")
          && jsx.contains("[\"Steel Blue 2\", 0.2745, 0.5098, 0.7059]") && jsx.contains("addProperty(\"ADBE Color Control\")")
          && ExportFormat.afterEffects.fileName(for: [brand]) == "brand-2026-after-effects.jsx",
          "After Effects script lists each colour once by name as 0 to 1 components and builds colour controls")
    check(crc32(Data("123456789".utf8)) == 0xCBF4_3926, "zip checksum matches the standard check value")
    let procreate = ExportFormat.procreate.data([brand, long])!
    func le(_ at: Int, _ n: Int) -> Int { (0..<n).reduce(0) { $0 | Int(procreate[at + $1]) << (8 * $1) } }
    let body = le(18, 4), nameLength = le(26, 2)
    check(le(0, 4) == 0x04034B50 && le(8, 2) == 0 && String(data: procreate[30..<(30 + nameLength)], encoding: .utf8) == "Swatches.json"
          && le(30 + nameLength + body, 4) == 0x02014B50 && le(procreate.count - 22, 4) == 0x06054B50
          && le(procreate.count - 6, 4) == 30 + nameLength + body,
          "Procreate file is a zip holding Swatches.json, stored, with a directory that points at it")
    let swatchJSON = procreate[(30 + nameLength)..<(30 + nameLength + body)]
    check(UInt32(le(14, 4)) == crc32(Data(swatchJSON)), "the zip entry's checksum is its contents'")
    let sets = (try? JSONSerialization.jsonObject(with: Data(swatchJSON))) as? [[String: Any]] ?? []
    let orange = (sets.first?["swatches"] as? [[String: Any]])?[1]
    check(sets.map { $0["name"] as? String } == ["Brand 2026", "Long", "Long 2"]
          && sets.map { ($0["swatches"] as? [Any])?.count } == [3, 30, 1],
          "Procreate palettes hold 30 colours; a longer one carries on in a second")
    check(abs((orange?["hue"] as? Double ?? 0) - 24.0 / 360) < 0.0001 && orange?["saturation"] as? Double == 1
          && orange?["brightness"] as? Double == 1 && orange?["alpha"] as? Double == 1, "Procreate colours are hue, saturation and brightness from 0 to 1")
    let sketch = (try? JSONSerialization.jsonObject(with: ExportFormat.sketch.data([brand])!)) as? [String: Any]
    let sketchColours = sketch?["colors"] as? [[String: Any]]
    check(sketch?["compatibleVersion"] as? String == "2.0" && sketchColours?.count == 3 && sketchColours?[0]["name"] as? String == "Steel Blue"
          && abs((sketchColours?[0]["red"] as? Double ?? 0) - 79.0 / 255) < 0.00001 && sketchColours?[1]["alpha"] as? Double == 1,
          "Sketch palette lists named colours as 0 to 1 components")
    let paintNet = text(.paintNet, [long, long, long, long]).split(separator: "\n").filter { !$0.hasPrefix(";") }
    check(text(.paintNet).contains("\nFF4F8093\nFFFF6600\n") && paintNet.count == 96, "Paint.NET palette is opaque AARRGGBB lines, 96 at most")
    check(text(.jasc) == "JASC-PAL\r\n0100\r\n3\r\n79 128 147\r\n255 102 0\r\n70 130 180\r\n", "JASC palette counts its colours and uses Windows line endings")
    check(text(.hexFile) == "4f8093\nff6600\n4682b4\n", "hex file is one bare colour per line")
    check(ExportFormat.clr.data([brand]) == nil && ExportFormat.png.data([brand]) == nil, "the drawn formats are left to the app")
    check(ExportFormat.css.fileName(for: [brand]) == "brand-2026-tokens.css" && ExportFormat.css.fileName(for: [brand, ui]) == "tokens.css"
          && ExportFormat.ase.fileName(for: [brand]) == "brand-2026.ase" && ExportFormat.procreate.fileName(for: [brand]) == "brand-2026.swatches"
          && ExportFormat.paintNet.fileName(for: [brand]) == "brand-2026-paint-net.txt", "file names follow the palette")

    print("adobe folders")
    let fm = FileManager.default
    let apps = fm.temporaryDirectory.appendingPathComponent("mmffdev-colour3-adobe-\(UUID().uuidString)")
    for path in ["Adobe Photoshop 2025/Presets/Color Books", "Adobe Photoshop 2026/Presets/Color Books",
                 "Adobe Photoshop 2026/Presets/Color Swatches", "Adobe Illustrator 2026/Presets.localized/en_GB/Swatches",
                 "Adobe InDesign 2026/Presets", "Adobe Photoshop Elements"] {
        try! fm.createDirectory(at: apps.appendingPathComponent(path), withIntermediateDirectories: true)
    }
    let adobe = AdobeDestination.installed(in: apps)
    check(adobe.map { $0.title } == ["Photoshop 2026 \u{2014} Colour Book", "Photoshop 2026 \u{2014} Swatches", "Illustrator 2026 \u{2014} Swatch Library"],
          "the newest year of each Adobe app is offered, and only where its library folder exists")
    check(adobe.map { $0.format } == [.acb, .aco, .ase] && adobe[2].folder.path.hasSuffix("Adobe Illustrator 2026/Presets.localized/en_GB/Swatches")
          && adobe[0].fileName(for: brand) == "Brand 2026.acb", "each Adobe folder gets the kind of file it lists, named for the palette")
    check(AdobeDestination.installed(in: apps.appendingPathComponent("nowhere")).isEmpty, "no Adobe apps, nothing offered")
    let bookFile = apps.appendingPathComponent("Brand 2026.acb")
    try! ExportFormat.acb.data([brand])!.write(to: bookFile)
    try! Data("old".utf8).write(to: adobe[0].folder.appendingPathComponent("Brand 2026.acb"))
    let copied = try? copyIntoFolder([bookFile], adobe[0].folder, prompt: "")
    check(copied == .copied && (try? Data(contentsOf: adobe[0].folder.appendingPathComponent("Brand 2026.acb"))) == ExportFormat.acb.data([brand])
          && (try? fm.contentsOfDirectory(atPath: adobe[0].folder.path))?.count == 1,
          "a folder the user may write to is copied into without a password, replacing the earlier file")
    try? fm.removeItem(at: apps)
    func refused(_ name: String, _ folder: String, _ bytes: Int = 100) -> Bool { AdobeHelperRules.refusal(name: name, folder: folder, bytes: bytes) != nil }
    let books = "/Applications/Adobe Photoshop 2026/Presets/Color Books"
    check(!refused("Brand 2026.acb", books) && !refused("Brand.aco", "/Applications/Adobe Photoshop 2026/Presets/Color Swatches")
          && !refused("Brand.ase", "/Applications/Adobe Illustrator 2026/Presets.localized/en_GB/Swatches")
          && !refused("Brand.ACB", "/Applications/Adobe InDesign 2026/Presets/Swatch Libraries"),
          "the helper serves the four Adobe library folders")
    check(["/Applications/Adobe Photoshop 2026/Presets/Scripts", "/Applications/Adobe Photoshop 2026/Presets/Color Books/../Scripts",
           "/Applications/Adobe Photoshop 2026/Presets/Color Books/", "/Applications/Adobe Photoshop 2026", "/Applications/Other/Presets/Color Books",
           "/Users/x/Applications/Adobe Photoshop 2026/Presets/Color Books", "/Applications/Adobe Photoshop x026/Presets/Color Books",
           "/Applications/Adobe Illustrator 2026/Presets.localized/../Swatches", "/etc", "Applications/Adobe Photoshop 2026/Presets/Color Books", ""]
        .allSatisfy { refused("Brand.acb", $0) }, "the helper refuses every other folder, however it is spelt")
    check(["Brand.jsx", "Brand", ".acb", "../Brand.acb", "a/b.acb", "Brand.acb\0.sh", "Brand\n.acb", "", String(repeating: "a", count: 300) + ".acb"]
        .allSatisfy { refused($0, books) }, "the helper refuses anything not named as a swatch file")
    check(refused("Brand.acb", books, 0) && refused("Brand.acb", books, AdobeHelperRules.maxBytes + 1) && !refused("Brand.acb", books, AdobeHelperRules.maxBytes),
          "the helper refuses an empty file and one too large to be a swatch file")
    #if !APPSTORE
    check(AdobeHelper.state != .on || Bundle.main.bundlePath.hasPrefix("/Applications/"), "the helper is never on for a copy of the app outside Applications")
    let rules = "!#acl 1\nuser:BC476802-9355-40E5-862A-6A6DC80FA551:rick:501:allow,file_inherit,directory_inherit:write,delete_child\n"
    check(AdobeAccess.grantsAdding(rules, user: "rick", uid: 501) && !AdobeAccess.grantsAdding(rules, user: "rick", uid: 502)
          && !AdobeAccess.grantsAdding(rules, user: "ricky", uid: 501) && !AdobeAccess.grantsAdding("", user: "rick", uid: 501)
          && !AdobeAccess.grantsAdding(rules.replacingOccurrences(of: "allow", with: "deny"), user: "rick", uid: 501)
          && !AdobeAccess.grantsAdding(rules.replacingOccurrences(of: ",delete_child", with: ""), user: "rick", uid: 501),
          "a folder counts as unlocked only when its rules let this very account add and replace files")
    check(AdobeAccess.state == .nothingToDo || !AdobeAccess.folders.isEmpty, "Adobe access has nothing to set up where no Adobe app is installed")
    let permissionTitles = Permission.all.map { $0.title }
    check(permissionTitles == ["Screen Recording"], "the setup asks up front for Screen Recording alone; Documents is asked on the catalogue step")
    #else
    let kept = fm.temporaryDirectory.appendingPathComponent("mmffdev-colour3-kept-\(UUID().uuidString)")
    try! fm.createDirectory(at: kept, withIntermediateDirectories: true)
    FolderAccess.remember(kept)
    check(FolderAccess.covers(kept) && FolderAccess.covers(kept.appendingPathComponent("inside/deeper")) && !FolderAccess.covers(fm.temporaryDirectory),
          "a folder the user chose is kept hold of, and everything inside it with it")
    FolderAccess.forget(kept)
    check(!FolderAccess.covers(kept), "a folder let go of is not kept")
    try? fm.removeItem(at: kept)
    check(Store.allows(.none) && !Store.allows(.standard) && !Store.allows(.pro), "the Store build starts with no edition until one is bought")
    #endif
    #if !APPSTORE
    check(Store.allows(.pro) && Store.edition == .pro, "the direct download is Pro throughout")
    #endif
    check(Edition.none < .standard && .standard < .pro && Store.edition(of: Store.proID) == .pro && Store.edition(of: "x") == .none,
          "Pro includes Standard, and an unknown product gives nothing")

    print("the tree on disk")
    TreeFiles.removedGoesToBin = false
    let tcat = Date(timeIntervalSince1970: 1_770_000_000)
    let treeDir = root.appendingPathComponent("tree/Studio")
    let treeStore = LibraryStore(directory: treeDir, legacyURL: nil, name: "Studio")
    var treeLib = Library()
    let jobA = treeLib.createProject(named: "Job A", at: tcat), jobB = treeLib.createProject(named: "Job B", at: tcat), acmeWeb = treeLib.createProject(named: "Acme Web", at: tcat)
    let inA = treeLib.createSwatch(at: tcat), inB = treeLib.createSwatch(at: tcat.addingTimeInterval(1)), looseOne = treeLib.createSwatch(at: tcat.addingTimeInterval(2))
    _ = treeLib.renameSwatch(inA, to: "Autumn"); _ = treeLib.renameSwatch(inB, to: "Winter"); _ = treeLib.renameSwatch(looseOne, to: "Scratch")
    treeLib.add(["#AA0000", "#00AA00"], toSwatch: inA, at: tcat)
    treeLib.add(["#0000AA"], toSwatch: inB, at: tcat)
    treeLib.add(["#111111"], toSwatch: looseOne, at: tcat)
    treeLib.activeSwatchID = nil   // a pick into the library alone, into no palette
    treeLib.addPick("#EEEEEE", at: tcat.addingTimeInterval(3))
    treeLib.move(inA, to: jobA, index: 0, at: tcat)
    treeLib.move(inB, to: jobB, index: 0, at: tcat)
    let typeA = treeLib.createTypography(named: "Headings", in: jobA, at: tcat)
    treeLib.setTag("brand", colour: "#FF8800", project: nil, at: tcat)
    treeLib.setTag("client", colour: nil, project: jobA, at: tcat)
    treeLib.setTags(ofPalette: inA, ["brand", "client"], at: tcat)
    treeLib.setPurpose(.print, on: true, ofPalette: inA, at: tcat)
    treeLib.setProfile(ColourProfiles.starters[1], ofPalette: inA, at: tcat)
    treeLib.choosePurpose(.print, ofPalette: inA, at: tcat.addingTimeInterval(2))
    treeLib.choosePurpose(.video, ofPalette: looseOne, at: tcat.addingTimeInterval(2))
    treeLib.deleteSwatch(treeLib.createSwatch(at: tcat), at: tcat.addingTimeInterval(4))
    // The schema: Projects holds Job A and Job B; Clients, grouped by Client, holds Acme Web under Acme.
    let acme = SchemaFolder(name: "Acme")
    let clients = SchemaCollection(name: "Clients", folderName: "Client", folders: [acme], stack: SchemaTrial.start)
    var treeSchema = SchemaTrial.SchemaFile.fresh
    treeSchema.collections.append(clients)
    treeSchema.places[acmeWeb.uuidString] = SchemaPlace(collection: clients.id, folder: acme.id)
    try! treeStore.save(treeLib, schema: treeSchema)
    let treeBack = try! treeStore.load()
    if canonical(treeBack) != canonical(treeLib) {
        print("        projects \(treeBack.projects == treeLib.projects)  swatches \(canonical(treeBack).swatches == canonical(treeLib).swatches)  colours \(canonical(treeBack).colours == canonical(treeLib).colours)  tags \(canonical(treeBack).tagInfo == canonical(treeLib).tagInfo)  profiles \(treeBack.colourProfiles == treeLib.colourProfiles)  deleted \(treeBack.deleted == treeLib.deleted)  version \(treeBack.version == treeLib.version)")
        for s in canonical(treeLib).swatches { if let b = treeBack.swatch(s.id), b != s { print("        differs: \(s.name)"); print("          was \(s)"); print("          now \(b)") } else if treeBack.swatch(s.id) == nil { print("        missing: \(s.name)") } }
        for p in treeLib.projects where treeBack.project(p.id) != p { print("        member differs: \(p)\n          now \(String(describing: treeBack.project(p.id)))") }
    }
    check(canonical(treeBack) == canonical(treeLib), "a catalogue written as its structure file and assets reads back whole: members, palettes, typography, tags, colours and profiles")
    check(treeBack.swatch(inA)?.purpose == .print && treeBack.swatch(looseOne)?.purpose == .video && treeBack.swatch(inA)?.purposeList == [.print] && treeBack.swatch(inA)?.profile == ColourProfiles.starters[1].id,
          "a palette's purposes, the one it is turned to, and its profile come back with it")
    check(treeStore.schema.collections == treeSchema.collections && treeStore.schema.places[acmeWeb.uuidString] == treeSchema.places[acmeWeb.uuidString]
          && treeStore.schema.places[jobA.uuidString]?.collection == SchemaTrial.firstCollection && treeStore.schema.stacks == nil,
          "the schema comes back from the structure file: the collections, where every member sits, and that each follows its Master Template")
    let projectsDir = treeDir.appendingPathComponent("Projects"), jobADir = projectsDir.appendingPathComponent("Job A")
    func exists(_ path: String) -> Bool { fm.fileExists(atPath: treeDir.appendingPathComponent(path).path) }
    func anywhere(_ ext: String, under dir: URL) -> Bool { ((fm.enumerator(atPath: dir.path)?.allObjects as? [String]) ?? []).contains { ($0 as NSString).pathExtension == ext } }
    check(treeStore.url.lastPathComponent == "Studio.colcat" && exists("Studio.colcat")
          && ["Information", "Palettes", "Typography", "Tags"].allSatisfy { exists("Projects/Job A/" + $0) }
          && exists("Projects/Job A/Palettes/Autumn.colpal") && exists("Projects/Job A/Typography/Headings.coltyp") && exists("Projects/Job A/Information/Job A.colinf")
          && exists("Clients/Acme/Acme Web/Information/Acme Web.colinf")
          && exists("Library/Palettes/Scratch.colpal") && exists("Library/Swatches/Studio Swatches.colswa") && exists("Library/Profiles/Studio Profiles.colprf")
          && !exists("Templates") && ![LegacyTree.collection, LegacyTree.workGroup, LegacyTree.assets, LegacyTree.template, ColourFiles.legacyPalette].contains { anywhere($0, under: treeDir) },
          "the catalogue is one structure file and its assets: every collection, level between, member and group a folder named as the user named it, holding only assets")
    let d = ColourFiles.decoder()
    let treeCat = CatalogueTree.catalogue(in: treeDir)
    let autumnDoc = try? d.decode(PaletteDocument.self, from: Data(contentsOf: jobADir.appendingPathComponent("Palettes/Autumn.colpal")))
    let headingsDoc = try? d.decode(PaletteDocument.self, from: Data(contentsOf: jobADir.appendingPathComponent("Typography/Headings.coltyp")))
    let jobAInfo = try? d.decode(InformationDocument.self, from: Data(contentsOf: jobADir.appendingPathComponent("Information/Job A.colinf")))
    let swatchesDoc = try? d.decode(SwatchesDocument.self, from: Data(contentsOf: treeDir.appendingPathComponent("Library/Swatches/Studio Swatches.colswa")))
    let profilesDoc = try? d.decode(ProfilesDocument.self, from: Data(contentsOf: treeDir.appendingPathComponent("Library/Profiles/Studio Profiles.colprf")))
    let projectsEntry = treeCat?.collections.first { $0.id == SchemaTrial.firstCollection }
    let jobAEntry = projectsEntry?.members.first { $0.id == jobA }
    check(autumnDoc?.palette.purposes?.map { $0.purpose } == [.print] && autumnDoc?.palette.purpose == nil && autumnDoc?.file == "Autumn" && autumnDoc?.project == jobA
          && autumnDoc?.catalogue == treeCat?.id && headingsDoc?.format == "colour-typography" && jobAInfo?.member == jobA && jobAInfo?.record.name == "Job A" && jobAInfo?.catalogue == treeCat?.id,
          "every asset carries itself whole and says which catalogue and member it belongs to: a palette its settings, a typography palette its own format, a member's information pack its record")
    check(treeCat?.version == 3 && treeCat?.collections.map { $0.id } == [SchemaTrial.firstCollection, clients.id] && projectsEntry?.members.map { $0.id } == [jobA, jobB]
          && projectsEntry?.template == treeSchema.collections[0].stack && jobAEntry?.schema == nil && jobAEntry?.assets.map { $0.id } == [inA, typeA]
          && jobAEntry?.assets.map { $0.kind } == [.palette, .typography] && jobAEntry?.assets.first?.file == "Projects/Job A/Palettes/Autumn.colpal"
          && jobAEntry?.buckets.count == 4 && jobAEntry?.turned?.first?.purpose == .print && jobAEntry?.information == "Projects/Job A/Information/Job A.colinf"
          && treeCat?.collections.last?.groups.map { $0.name } == ["Acme"] && treeCat?.collections.last?.groups.first?.members.map { $0.id } == [acmeWeb]
          && treeCat?.libraryAssets.map { $0.id } == [looseOne] && Set(treeCat?.tags.map { $0.name } ?? []) == ["brand", "client"],
          "the structure file holds the whole tree and an index of every asset: collections with their Master Templates, levels between, members with their groups' folders and palettes in order, the Library, the tags")
    check(swatchesDoc?.colours.map { $0.hex } == ["#EEEEEE"] && profilesDoc?.profiles.map { $0.id } == [ColourProfiles.starters[1].id],
          "the Library's loose colours and its profiles are files of their own, named for the catalogue")
    // Renamed in the app: the folder or file takes the new name at once. Moved to another collection: the folder moves.
    var renamedLib = treeBack
    _ = renamedLib.renameProject(jobA, to: "Job A Plus", at: tcat.addingTimeInterval(5))
    _ = renamedLib.renameSwatch(inA, to: "Autumn Range", at: tcat.addingTimeInterval(5))
    try! treeStore.save(renamedLib)
    let plusDir = projectsDir.appendingPathComponent("Job A Plus")
    check(exists("Projects/Job A Plus/Palettes/Autumn Range.colpal") && !exists("Projects/Job A") && !exists("Projects/Job A Plus/Palettes/Autumn.colpal")
          && exists("Projects/Job A Plus/Information/Job A Plus.colinf") && !exists("Projects/Job A Plus/Information/Job A.colinf")
          && (try? treeStore.load())?.project(jobA)?.name == "Job A Plus",
          "renaming a member or a palette in the app renames its folder, its information pack or its file the same instant, and nothing is left under the old name")
    var movedSchema = treeStore.schema
    movedSchema.places[jobB.uuidString] = SchemaPlace(collection: clients.id, folder: acme.id)
    try! treeStore.save(renamedLib, schema: movedSchema)
    _ = try! treeStore.load()
    check(exists("Clients/Acme/Job B/Palettes/Winter.colpal") && !exists("Projects/Job B"), "placing a member in another collection, or under a client, moves its folder there with everything in it")
    check(SchemaTrial.folder(of: jobB, among: treeStore.schema.collections, places: treeStore.schema.places) == acme.id, "and the tree read back says where it is now")
    movedSchema = treeStore.schema
    movedSchema.collections[1].name = "Customers"
    movedSchema.collections[1].folders[0].name = "Acme Ltd"
    try! treeStore.save(renamedLib, schema: movedSchema)
    check(exists("Customers/Acme Ltd/Job B/Palettes/Winter.colpal") && !exists("Clients") && CatalogueTree.catalogue(in: treeDir)?.collections.last?.folder == "Customers",
          "renaming a collection or a level between renames its folder, and the structure file says so")
    var shaped = treeStore.schema
    var ownTree = SchemaTrial.start
    ownTree.children[1].name = "Colourways"
    shaped.stacks = [jobA.uuidString: ownTree]
    try! treeStore.save(renamedLib, schema: shaped)
    check(exists("Projects/Job A Plus/Colourways/Autumn Range.colpal") && !exists("Projects/Job A Plus/Palettes")
          && CatalogueTree.catalogue(in: treeDir)?.collections.first?.members.first { $0.id == jobA }?.schema?.children[1].name == "Colourways" && treeStore.schema.stacks?[jobA.uuidString] == ownTree,
          "renaming a group in a member's own schema renames its folder, palettes and all, and the structure file keeps the member's own tree")
    // Renamed in Finder: the app takes the new name, and the structure file catches up.
    try! fm.moveItem(at: plusDir, to: projectsDir.appendingPathComponent("Job Alpha"))
    let alphaDir = projectsDir.appendingPathComponent("Job Alpha")
    let afterFinder = try! treeStore.load()
    check(afterFinder.project(jobA)?.name == "Job Alpha" && CatalogueTree.catalogue(in: treeDir)?.collections.first?.members.first { $0.id == jobA }?.folder == "Job Alpha"
          && exists("Projects/Job Alpha/Information/Job Alpha.colinf") && afterFinder.palettes(in: jobA).count == 2,
          "a member folder renamed in Finder gives the member its new name, keeps its palettes, and the structure file catches up")
    var dropped = Swatch(id: UUID(), name: "Dropped", createdAt: tcat, entries: [SwatchEntry(hex: "#ABCDEF", addedAt: tcat)])
    dropped.projectID = nil
    let droppedDoc = PaletteDocument(project: nil, palette: dropped, colours: [Colour(hex: "#ABCDEF", pickedAt: tcat)], file: "Dropped")
    try! ColourFiles.encoder().encode(droppedDoc).write(to: alphaDir.appendingPathComponent("Colourways/Dropped.colpal"))
    let adopted = try! treeStore.load()
    check(adopted.swatch(dropped.id)?.projectID == jobA && adopted.colours.contains { $0.hex == "#ABCDEF" }
          && CatalogueTree.catalogue(in: treeDir)?.collections.first?.members.first { $0.id == jobA }?.assets.contains { $0.id == dropped.id } == true,
          "a palette file dropped into a member's folder in Finder is taken in, and the structure file lists it")
    // Moved in Finder, out of its client: known by its palettes, it sits where it was put.
    try! fm.moveItem(at: treeDir.appendingPathComponent("Customers/Acme Ltd/Job B"), to: treeDir.appendingPathComponent("Customers/Job B"))
    let afterMove = try! treeStore.load()
    check(afterMove.project(jobB)?.name == "Job B" && afterMove.swatch(inB)?.projectID == jobB && treeStore.schema.places[jobB.uuidString] == SchemaPlace(collection: clients.id, folder: nil),
          "a member folder moved in Finder is known by the assets inside it, and the member sits where it was put, palettes and all")
    try! fm.moveItem(at: treeDir.appendingPathComponent("Customers"), to: treeDir.appendingPathComponent("Clients Ltd"))
    let afterCollectionRename = try! treeStore.load()
    check(treeStore.schema.collections.map { $0.name } == ["Projects", "Clients Ltd"] && treeStore.schema.collections[1].id == clients.id && afterCollectionRename.project(jobB) != nil
          && treeStore.schema.collections[1].folders.map { $0.name } == ["Acme Ltd"],
          "a collection folder renamed in Finder renames the collection, and everything in it stays")
    try! fm.removeItem(at: treeDir.appendingPathComponent("Clients Ltd/Job B"))
    let afterDelete = try! treeStore.load()
    check(afterDelete.project(jobB) == nil && afterDelete.swatch(inB) == nil && afterDelete.project(jobA) != nil,
          "a member folder deleted in Finder is gone from the catalogue, with its palettes, and nothing else is touched")
    // Added in Finder: a folder in a collection is a new member; a folder at the root is a new collection, its folders its members.
    try! fm.createDirectory(at: treeDir.appendingPathComponent("Clients Ltd/Newco"), withIntermediateDirectories: true)
    try! fm.createDirectory(at: treeDir.appendingPathComponent("Archive/Old Work"), withIntermediateDirectories: true)
    let afterAdd = try! treeStore.load()
    let newco = afterAdd.projects.first { $0.name == "Newco" }, oldWork = afterAdd.projects.first { $0.name == "Old Work" }
    let archive = treeStore.schema.collections.first { $0.name == "Archive" }
    check(newco != nil && oldWork != nil && archive != nil && treeStore.schema.places[newco?.id.uuidString ?? ""]?.collection == clients.id
          && treeStore.schema.places[oldWork?.id.uuidString ?? ""]?.collection == archive?.id && exists("Clients Ltd/Newco/Information/Newco.colinf") && exists("Archive/Old Work/Palettes")
          && !exists("Clients Ltd/Newco 2") && !exists("Archive 2"),
          "a folder made in Finder inside a collection is taken in as a member, one at the root as a collection, and each gets its groups' folders where it is")
    // Copied in from elsewhere: a member's folder brings its information pack, and with it the member's id and details.
    let visitor = UUID()
    var visitorRecord = Project(id: visitor, name: "Visitor", createdAt: tcat)
    visitorRecord.details = ["studio": "Elsewhere"]
    let visitorDir = treeDir.appendingPathComponent("Clients Ltd/Visitor")
    try! fm.createDirectory(at: visitorDir.appendingPathComponent("Information"), withIntermediateDirectories: true)
    try! fm.createDirectory(at: visitorDir.appendingPathComponent("Palettes"), withIntermediateDirectories: true)
    try! ColourFiles.encoder().encode(InformationDocument(catalogue: UUID(), member: visitor, record: visitorRecord)).write(to: visitorDir.appendingPathComponent("Information/Visitor.colinf"))
    var guest = Swatch(id: UUID(), name: "Guest", createdAt: tcat, entries: [SwatchEntry(hex: "#0A0B0C", addedAt: tcat)])
    guest.projectID = visitor
    try! ColourFiles.encoder().encode(PaletteDocument(project: visitor, palette: guest, colours: [Colour(hex: "#0A0B0C", pickedAt: tcat)], file: "Guest"))
        .write(to: visitorDir.appendingPathComponent("Palettes/Guest.colpal"))
    let afterCopy = try! treeStore.load()
    check(afterCopy.project(visitor)?.details?["studio"] == "Elsewhere" && afterCopy.swatch(guest.id)?.projectID == visitor && !exists("Clients Ltd/Visitor 2"),
          "a member's folder copied in from another catalogue keeps its id and details, and its palettes come with it")
    // Deleted in the app: the file or folder goes.
    var fewer = afterCopy
    fewer.deleteSwatch(dropped.id, at: tcat.addingTimeInterval(9))
    fewer.deleteProject(acmeWeb, at: tcat.addingTimeInterval(9))
    try! treeStore.save(fewer)
    check(!exists("Projects/Job Alpha/Colourways/Dropped.colpal") && !exists("Clients Ltd/Acme Ltd/Acme Web") && exists("Clients Ltd/Acme Ltd"),
          "a palette or a member deleted in the app loses its file or folder, and the level above stays")
    let signatureBefore = CatalogueTree.signature(root: treeDir)
    try! treeStore.mutate { $0.addPick("#123456", at: tcat.addingTimeInterval(10)) }
    check(signatureBefore != CatalogueTree.signature(root: treeDir) && CatalogueTree.signature(root: treeDir) == CatalogueTree.signature(root: treeDir),
          "the tree's signature changes when anything in it does, and not otherwise")
    // Templates are the structure file's own.
    var withTemplate = treeStore.schema
    withTemplate.templates = [SchemaTemplate(name: "Agency Job", about: "For agencies", stack: ownTree, changedAt: tcat)]
    try! treeStore.save(fewer, schema: withTemplate)
    _ = try! treeStore.load()
    check(treeStore.schema.templates?.map { $0.name } == ["Agency Job"] && treeStore.schema.templates?.first?.stack == ownTree
          && CatalogueTree.catalogue(in: treeDir)?.templates.first?.about == "For agencies" && !exists("Templates"),
          "a template is held in the structure file, with no file or folder of its own, and reads back")
    // No collection at all is a catalogue too; the first member brings the first collection back.
    let bareDir = root.appendingPathComponent("tree/Bare")
    let bareStore = LibraryStore(directory: bareDir, legacyURL: nil, name: "Bare")
    var bare = Library()
    _ = bare.createSwatch(at: tcat)
    try! bareStore.save(bare, schema: SchemaTrial.SchemaFile(collections: [], places: [:]))
    var bareBack = try! bareStore.load()
    check(bareStore.schema.collections.isEmpty && CatalogueTree.subfolders(of: bareDir).map { $0.lastPathComponent } == ["Library"] && CatalogueTree.catalogue(in: bareDir)?.collections.isEmpty == true
          && bareBack.swatches.count == 1,
          "a catalogue may hold no collection: no folder is made for one, and none is invented when it is read")
    let firstMember = bareBack.createProject(named: "First", at: tcat)
    try! bareStore.save(bareBack, schema: bareStore.schema)
    bareBack = try! bareStore.load()
    check(bareStore.schema.collections.map { $0.id } == [SchemaTrial.firstCollection] && bareBack.project(firstMember) != nil
          && fm.fileExists(atPath: bareDir.appendingPathComponent("Projects/First/Information/First.colinf").path),
          "a member made in a catalogue with no collection brings the first collection back to hold it")
    check(filesystemName("Red/Blue 50:50?") == "Red-Blue 50-50-" && filesystemName("aux") == "aux_" && filesystemName("COM1.old") == "COM1.old_"
          && filesystemName("Final. ") == "Final" && filesystemName("e\u{0301}") == "\u{00E9}" && filesystemName("...") == "Untitled",
          "a file name is safe on Windows and Linux as well as the Mac: no forbidden characters, no reserved names, no trailing dot")
    if let one = SwatchDocument("#AA0000", in: inA, of: treeLib), let oneData = try? one.data() {
        check((try? SwatchDocument.read(oneData)) == one && one.colour.hex == "#AA0000" && SwatchDocument.fileName("Fire / Red") == "Fire - Red.colswatch",
              "one colour travels as a file of its own, and reads back as it was")
    } else { check(false, "a palette's colour can be made into a swatch file") }
    check(Purpose.allCases.map { $0.fileExtension } == ["colweb", "colprint", "colphoto", "colvideo", "colcine", "col3d"] && Purpose.of(fileExtension: "COLPRINT") == .print,
          "each purpose has a file extension of its own that says what it is")
    let joined = Library.merged(treeLib.swatch(inA)?.purposes, [PurposeConfig(id: UUID(), purpose: .web, changedAt: tcat.addingTimeInterval(9)), PurposeConfig(id: UUID(), purpose: .cine, changedAt: tcat)])
    check(joined?.filter { $0.isLive }.map { $0.purpose } == [.web, .print, .cine] && Library.merged(nil, nil) == nil,
          "two Macs' purposes join, each purpose as it was last changed")

    print("bringing an earlier layout across")
    let e = ColourFiles.encoder()
    let oldDir = root.appendingPathComponent("tree/Earlier")
    var oldLib = Library()
    let oldJob = oldLib.createProject(named: "Old Job", at: tcat)
    let oldPal = oldLib.createSwatch(at: tcat); _ = oldLib.renameSwatch(oldPal, to: "Spring"); oldLib.add(["#101010", "#202020"], toSwatch: oldPal, at: tcat); oldLib.move(oldPal, to: oldJob, index: 0, at: tcat)
    oldLib.setTag("global", colour: "#00FF00", project: nil, at: tcat)
    let loosePal = oldLib.createSwatch(at: tcat); _ = oldLib.renameSwatch(loosePal, to: "Loose"); oldLib.add(["#303030"], toSwatch: loosePal, at: tcat)
    // Written by hand as the earlier version wrote it: the index, a member under Projects with a channel file, Unfiled,
    // a schema file, a snapshot history, and a member folder the index never listed.
    let oldJobDir = oldDir.appendingPathComponent("Projects/Old Job")
    for sub in ["Space", "Config", "Palettes", "Channels"] { try! fm.createDirectory(at: oldJobDir.appendingPathComponent(sub), withIntermediateDirectories: true) }
    for sub in ["Unfiled/Config", "Unfiled/Palettes", "Projects/Client 3/Space", "Projects/Client 3/Palettes"] { try! fm.createDirectory(at: oldDir.appendingPathComponent(sub), withIntermediateDirectories: true) }
    try! e.encode(ProjectDocument(project: oldLib.project(oldJob)!, palettes: [oldPal], colours: ["#101010", "#202020"], turned: [TurnedPalette(palette: oldPal, purpose: .print, changedAt: tcat)]))
        .write(to: oldJobDir.appendingPathComponent("Space/Old Job.colspace"))
    try! e.encode(DataDocument(project: oldJob, tags: [TagInfo(name: "mine", colour: nil, projectID: oldJob, removed: nil, changedAt: tcat)], profiles: []))
        .write(to: oldJobDir.appendingPathComponent("Config/Old Job.coldata"))
    try! e.encode(PaletteDocument(project: oldJob, palette: oldLib.swatch(oldPal)!, colours: oldLib.colours.filter { ["#101010", "#202020"].contains($0.hex) }))
        .write(to: oldJobDir.appendingPathComponent("Palettes/Spring.colpalette"))
    try! e.encode(PurposeDocument(palette: oldPal, paletteName: "Spring", settings: PurposeConfig(id: UUID(), purpose: .print, changedAt: tcat)))
        .write(to: oldJobDir.appendingPathComponent("Channels/Spring.colprint"))
    try! e.encode(DataDocument(project: nil, colours: [Colour(hex: "#404040", pickedAt: tcat)], tags: oldLib.tagInfo, profiles: []))
        .write(to: oldDir.appendingPathComponent("Unfiled/Config/Unfiled.coldata"))
    try! e.encode(PaletteDocument(project: nil, palette: oldLib.swatch(loosePal)!, colours: oldLib.colours.filter { $0.hex == "#303030" }))
        .write(to: oldDir.appendingPathComponent("Unfiled/Palettes/Loose.colpalette"))
    try! e.encode(CatalogueDocument(library: 2, projects: [ProjectRef(id: oldJob, name: "Old Job", createdAt: tcat, folder: "Projects/Old Job")], palettes: [oldPal, loosePal],
                                    colours: ["#101010", "#202020", "#303030", "#404040"], tags: [TagKey(name: "global", project: nil), TagKey(name: "mine", project: oldJob)], deleted: []))
        .write(to: oldDir.appendingPathComponent("Earlier.colcatalogue"))
    try! JSONEncoder().encode(SchemaTrial.SchemaFile(collections: [SchemaCollection(id: SchemaTrial.firstCollection, name: "Jobs", stack: SchemaTrial.start)], places: [:]))
        .write(to: oldDir.appendingPathComponent("schema.colschema"))
    try! Data(repeating: 0x20, count: 50_000).write(to: oldDir.appendingPathComponent("library.history.json"))
    let orphanID = UUID()
    var orphanPal = Swatch(id: UUID(), name: "Lost", createdAt: tcat, entries: [SwatchEntry(hex: "#505050", addedAt: tcat)])
    orphanPal.projectID = orphanID
    try! e.encode(ProjectDocument(project: Project(id: orphanID, name: "Client 3", createdAt: tcat), palettes: [orphanPal.id], colours: ["#505050"]))
        .write(to: oldDir.appendingPathComponent("Projects/Client 3/Space/Client 3.colspace"))
    try! e.encode(PaletteDocument(project: orphanID, palette: orphanPal, colours: [Colour(hex: "#505050", pickedAt: tcat)]))
        .write(to: oldDir.appendingPathComponent("Projects/Client 3/Palettes/Lost.colpalette"))
    let oldMeasure = Migration.measure(oldDir)
    check(Migration.needed(in: oldDir) && !Migration.needed(in: treeDir), "a catalogue in the earlier layout is seen as one to bring across, and one already a tree is not")
    let migratedStore = LibraryStore(directory: oldDir, legacyURL: nil, name: "Earlier")
    let brought = try! migratedStore.load()
    let backups = ((try? fm.contentsOfDirectory(atPath: root.appendingPathComponent("tree").path)) ?? []).filter { $0.hasPrefix("Earlier Before Migration ") }
    check(backups.count == 1 && Migration.measure(root.appendingPathComponent("tree").appendingPathComponent(backups[0])) == oldMeasure,
          "the old folders are copied whole into a folder named for the catalogue and the date beside it, every file and byte, before anything changes")
    check(brought.project(oldJob)?.name == "Old Job" && brought.swatch(oldPal)?.projectID == oldJob && brought.swatch(oldPal)?.purpose == .print && brought.swatch(oldPal)?.purposeList == [.print]
          && brought.swatch(loosePal)?.projectID == nil && brought.colours.contains { $0.hex == "#404040" } && brought.info(forTag: "global")?.colour == "#00FF00" && brought.project(ofTag: "mine") == oldJob,
          "every member, palette, tag, colour and channel comes across")
    check(brought.project(orphanID) == nil && brought.swatch(orphanPal.id)?.projectID == nil && fm.fileExists(atPath: oldDir.appendingPathComponent("Library/Palettes/Lost.colpal").path),
          "a member folder the index never listed sends its palettes to the Library")
    check(fm.fileExists(atPath: oldDir.appendingPathComponent("Earlier.colcat").path) && fm.fileExists(atPath: oldDir.appendingPathComponent("Jobs/Old Job/Information/Old Job.colinf").path)
          && fm.fileExists(atPath: oldDir.appendingPathComponent("Jobs/Old Job/Palettes/Spring.colpal").path)
          && !fm.fileExists(atPath: oldDir.appendingPathComponent("schema.colschema").path) && !fm.fileExists(atPath: oldDir.appendingPathComponent("library.history.json").path)
          && !fm.fileExists(atPath: oldDir.appendingPathComponent("Unfiled").path) && !fm.fileExists(atPath: oldDir.appendingPathComponent("Projects").path)
          && migratedStore.schema.collections.map { $0.name } == ["Jobs"] && !Migration.needed(in: oldDir) && (try? migratedStore.load()).map { canonical($0) } == canonical(brought),
          "the schema's collection becomes the folder the member sits in, nothing of the old layout is left, and the catalogue reads back as version 3 from then on")
    let report = migratedStore.takeMigration()
    if report?.orphans != ["Client 3 in Projects/Client 3"] { print("        report: \(String(describing: report))") }
    check(report?.orphans == ["Client 3 in Projects/Client 3"] && report?.members == 1 && migratedStore.takeMigration() == nil, "what was done is reported, once")
    let oneDir = root.appendingPathComponent("tree/One")
    try! fm.createDirectory(at: oneDir, withIntermediateDirectories: true)
    try! JSONEncoder.library.encode(oldLib).write(to: oneDir.appendingPathComponent("library.json"))
    let oneLib = try! LibraryStore(directory: oneDir, legacyURL: nil, name: "One").load()
    check(oneLib.project(oldJob) != nil && oneLib.swatch(oldPal)?.entries.count == 2 && fm.fileExists(atPath: oneDir.appendingPathComponent("One.colcat").path)
          && !fm.fileExists(atPath: oneDir.appendingPathComponent("library.json").path)
          && ((try? fm.contentsOfDirectory(atPath: root.appendingPathComponent("tree").path)) ?? []).contains { $0.hasPrefix("One Before Migration ") },
          "a catalogue an earlier version kept in one file comes across the same way")
    // Version 2, the tree of folders each with a file of its own, comes across in place.
    let secondDir = root.appendingPathComponent("tree/Second")
    let secondMember = UUID(), secondCollection = UUID(), secondGroup = UUID(), secondTemplate = UUID()
    var secondPal = Swatch(id: UUID(), name: "Dawn", createdAt: tcat, entries: [SwatchEntry(hex: "#123123", addedAt: tcat)])
    secondPal.projectID = secondMember
    let secondLoose = Swatch(id: UUID(), name: "Dusk", createdAt: tcat, entries: [SwatchEntry(hex: "#321321", addedAt: tcat)])
    let secondStack = SchemaTrial.start
    let secondMemberDir = secondDir.appendingPathComponent("Studios/North/Harbour")
    for sub in ["Information", "Palettes", "Typography", "Tags"] { try! fm.createDirectory(at: secondMemberDir.appendingPathComponent(sub), withIntermediateDirectories: true) }
    for sub in ["Library/Palettes", "Library/Typography", "Library/Swatches", "Library/Profiles", "Templates"] { try! fm.createDirectory(at: secondDir.appendingPathComponent(sub), withIntermediateDirectories: true) }
    try! e.encode(CollectionDocument(id: secondCollection, name: "Studios", about: "", folder: "Studios", groupName: "Region", template: secondStack, templateID: nil, members: [secondGroup], changedAt: tcat))
        .write(to: secondDir.appendingPathComponent("Studios/Studios.colcollection"))
    try! e.encode(WorkGroupDocument(id: secondGroup, name: "North", folder: "North", kind: .group, members: [secondMember], changedAt: tcat))
        .write(to: secondDir.appendingPathComponent("Studios/North/North.colworkgroup"))
    try! e.encode(WorkGroupDocument(id: secondMember, name: "Harbour", folder: "Harbour", kind: .member, project: Project(id: secondMember, name: "Harbour", createdAt: tcat), schema: secondStack,
                                    followsTemplate: true, tags: [TagInfo(name: "harbour", colour: nil, projectID: secondMember, removed: nil, changedAt: tcat)], palettes: [secondPal.id],
                                    colours: ["#123123"], buckets: Dictionary(uniqueKeysWithValues: secondStack.children.map { ($0.id.uuidString, $0.name) }), changedAt: tcat))
        .write(to: secondMemberDir.appendingPathComponent("Harbour.colworkgroup"))
    try! e.encode(PaletteDocument(project: secondMember, palette: secondPal, colours: [Colour(hex: "#123123", pickedAt: tcat)], file: "Dawn")).write(to: secondMemberDir.appendingPathComponent("Palettes/Dawn.colpalette"))
    try! e.encode(PaletteDocument(project: nil, palette: secondLoose, colours: [Colour(hex: "#321321", pickedAt: tcat)], file: "Dusk")).write(to: secondDir.appendingPathComponent("Library/Palettes/Dusk.colpalette"))
    try! e.encode(AssetsDocument(pool: "Palettes", items: [secondLoose.id], changedAt: tcat)).write(to: secondDir.appendingPathComponent("Library/Palettes/Palettes.colassets"))
    try! e.encode(AssetsDocument(pool: "Swatches", colours: [Colour(hex: "#999999", pickedAt: tcat)], changedAt: tcat)).write(to: secondDir.appendingPathComponent("Library/Swatches/Swatches.colassets"))
    try! e.encode(AssetsDocument(pool: "Profiles", profiles: [], changedAt: tcat)).write(to: secondDir.appendingPathComponent("Library/Profiles/Profiles.colassets"))
    try! e.encode(TemplateDocument(id: secondTemplate, name: "Agency", about: "", file: "Agency", stack: secondStack, changedAt: tcat)).write(to: secondDir.appendingPathComponent("Templates/Agency.coltemplate"))
    try! e.encode(CatalogueIndex(id: UUID(), name: "Second", createdAt: tcat, changedAt: tcat, library: 2, collections: [secondCollection], templates: [secondTemplate],
                                 colours: ["#123123", "#321321", "#999999"], tags: [], activePalette: nil, deleted: [], about: "Notes kept"))
        .write(to: secondDir.appendingPathComponent("Second.colcatalogue"))
    try! Data("brief".utf8).write(to: secondMemberDir.appendingPathComponent("Information/Brief.pdf"))
    try! Data("{}".utf8).write(to: secondDir.appendingPathComponent("Second.colhistory"))
    let secondMeasure = Migration.measure(secondDir)
    check(Migration.needed(in: secondDir) && Migration.isVersion2(secondDir), "a version 2 tree, each level with a file of its own, is seen as one to bring across")
    let secondStore = LibraryStore(directory: secondDir, legacyURL: nil, name: "Second")
    let secondLib = try! secondStore.load()
    let secondBackups = ((try? fm.contentsOfDirectory(atPath: root.appendingPathComponent("tree").path)) ?? []).filter { $0.hasPrefix("Second Before Migration ") }
    check(secondBackups.count == 1 && Migration.measure(root.appendingPathComponent("tree").appendingPathComponent(secondBackups[0])) == secondMeasure,
          "a version 2 tree is copied whole beside itself, every file and byte, before anything changes")
    check(secondLib.project(secondMember)?.name == "Harbour" && secondLib.swatch(secondPal.id)?.projectID == secondMember && secondLib.swatch(secondLoose.id)?.projectID == nil && secondLib.colours.contains { $0.hex == "#999999" }
          && secondLib.project(ofTag: "harbour") == secondMember && secondStore.schema.collections.map { $0.name } == ["Studios"] && secondStore.schema.collections.first?.folders.map { $0.name } == ["North"]
          && SchemaTrial.folder(of: secondMember, among: secondStore.schema.collections, places: secondStore.schema.places) == secondGroup && secondStore.schema.templates?.map { $0.name } == ["Agency"]
          && CatalogueTree.catalogue(in: secondDir)?.about == "Notes kept",
          "every collection, level between, member, palette, tag, colour and template comes across, with the catalogue's notes")
    func inSecond(_ p: String) -> Bool { fm.fileExists(atPath: secondDir.appendingPathComponent(p).path) }
    check(inSecond("Second.colcat") && !inSecond("Second.colcatalogue") && inSecond("Second.colhis") && !inSecond("Second.colhistory")
          && inSecond("Studios/North/Harbour/Palettes/Dawn.colpal") && !inSecond("Studios/North/Harbour/Palettes/Dawn.colpalette") && inSecond("Studios/North/Harbour/Information/Harbour.colinf")
          && inSecond("Studios/North/Harbour/Information/Brief.pdf") && inSecond("Library/Palettes/Dusk.colpal") && inSecond("Library/Swatches/Second Swatches.colswa")
          && !inSecond("Studios/Studios.colcollection") && !inSecond("Studios/North/North.colworkgroup") && !inSecond("Studios/North/Harbour/Harbour.colworkgroup")
          && !inSecond("Library/Palettes/Palettes.colassets") && !inSecond("Library/Swatches/Swatches.colassets") && !inSecond("Templates")
          && !Migration.needed(in: secondDir) && (try? secondStore.load()).map { canonical($0) } == canonical(secondLib),
          "in place: each asset takes its new name where it lies, the old file of every level goes, the user's own files stay, and it reads back as version 3 from then on")
    let lockedParent = root.appendingPathComponent("locked"), lockedDir = lockedParent.appendingPathComponent("Stuck")
    try! fm.createDirectory(at: lockedDir, withIntermediateDirectories: true)
    try! JSONEncoder.library.encode(oldLib).write(to: lockedDir.appendingPathComponent("library.json"))
    try! fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: lockedParent.path)
    let stuck = try? LibraryStore(directory: lockedDir, legacyURL: nil, name: "Stuck").load()
    try! fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedParent.path)
    check(stuck == nil && fm.fileExists(atPath: lockedDir.appendingPathComponent("library.json").path) && !fm.fileExists(atPath: lockedDir.appendingPathComponent("Stuck.colcat").path),
          "when the backup cannot be written nothing is brought across and the catalogue is left exactly as it was")

    print("sharing: zip, manifest, staging, twins, bringing in")
    let zipDir = root.appendingPathComponent("zip")
    try! fm.createDirectory(at: zipDir, withIntermediateDirectories: true)
    let bigBlob = Data(repeating: 0x41, count: 90_000) + Data("end".utf8)
    let zipEntries = [Zip.Entry(path: "Clients/Clients.colcollection", data: Data("{\"a\":1}".utf8)), Zip.Entry(path: "Clients/Acmé/Été.colpalette", data: bigBlob), Zip.Entry(path: "empty.txt", data: Data())]
    let zipFile = zipDir.appendingPathComponent("round.zip")
    try! Zip.write(zipEntries, to: zipFile, at: tcat)
    let zipBack = try? Zip.read(zipFile)
    let zipBytes = try! Data(contentsOf: zipFile)
    check(zipBack == zipEntries && zipBytes.count < 2_000, "the app's own zip writes files with names in any script, packs what packs, and reads them back whole")
    var broken = zipBytes
    broken[62] ^= 0xFF   // inside the first entry's data, after its 30-byte header and 29-byte name
    try! broken.write(to: zipDir.appendingPathComponent("broken.zip"))
    try! Data(repeating: 7, count: 300).write(to: zipDir.appendingPathComponent("junk.zip"))
    check((try? Zip.read(zipDir.appendingPathComponent("broken.zip"))) == nil && (try? Zip.read(zipDir.appendingPathComponent("junk.zip"))) == nil,
          "a zip with a byte changed, or a file that is no zip, is refused rather than read wrong")
    // A collection goes out: a small catalogue of its own, every member and palette in it, and a manifest naming each file's digest.
    let catalogueNamed = ShareManifest.Named(id: CatalogueTree.catalogue(in: treeDir)!.id, name: "Studio")
    let shareLib = try! treeStore.load(), shareSchema = treeStore.schema
    let projectsID = SchemaTrial.firstCollection
    let shareFile = zipDir.appendingPathComponent("Projects.colshr")
    let manifest = try! Sharing.export(level: .collection, subject: projectsID, from: shareLib, schema: shareSchema, catalogue: catalogueNamed, to: shareFile, now: tcat)
    let shareTree = Sharing.tree(level: .collection, subject: projectsID, in: shareLib, schema: shareSchema, catalogueName: "Studio")
    if !Set(manifest.files.map { $0.path }).isSuperset(of: ["Projects.colcat", "Projects/Job Alpha/Colourways/Autumn Range.colpal"]) { print("        share files: \(manifest.files.map { $0.path })") }
    check(manifest.level == .collection && manifest.subject.name == "Projects" && manifest.version == 2
          && Set(manifest.files.map { $0.path }).isSuperset(of: ["Projects.colcat", "Projects/Job Alpha/Colourways/Autumn Range.colpal", "Projects/Job Alpha/Typography/Headings.coltyp", "Projects/Job Alpha/Information/Job Alpha.colinf"])
          && manifest.files.allSatisfy { $0.sha256.count == 64 } && shareTree.palettes == 2 && shareTree.children.map { $0.name } == ["Job Alpha"]
          && shareTree.flattened.map { $0.node.kind }.contains(.bucket) && shareTree.node(inA.uuidString)?.name == "Autumn Range",
          "a collection exports as one zip holding a catalogue of its own, with a manifest listing every file and its digest, and the tree of what it holds comes from the structure")
    let inspected = try! Sharing.inspect(shareFile)
    check(inspected.ok && inspected.manifest == manifest && inspected.tree.name == "Projects" && inspected.tree.palettes == 2, "the share checks clean: manifest, digests, shape, and the tree is read from the zip before anything is written")
    // One byte changed inside a file: the check names it.
    var tampered = try! Zip.read(shareFile)
    if let at = tampered.firstIndex(where: { $0.path.hasSuffix("Autumn Range.colpal") }) { var d2 = tampered[at].data; d2[d2.count / 2] ^= 1; tampered[at] = Zip.Entry(path: tampered[at].path, data: d2) }
    try! Zip.write(tampered, to: zipDir.appendingPathComponent("tampered.zip"))
    let badCheck = try? Sharing.inspect(zipDir.appendingPathComponent("tampered.zip"))
    check(badCheck?.ok == false && badCheck?.problems.first?.contains("Autumn Range.colpal") == true, "a share with one byte changed stops at the check, naming the file")
    try! Zip.write(tampered.filter { $0.path != ShareManifest.fileName }, to: zipDir.appendingPathComponent("nomanifest.zip"))
    check((try? Sharing.inspect(zipDir.appendingPathComponent("nomanifest.zip"))) == nil && (try? Sharing.inspect(zipFile)) == nil, "a zip without a manifest is not a share")
    // Ticks: a palette left out is absent from the zip; what is ticked goes with the member and collection above it.
    let partial = zipDir.appendingPathComponent("partial.zip")
    let colourways = shareTree.flattened.first { $0.node.kind == .bucket && $0.node.name == "Colourways" }?.node.id ?? ""
    let ticks: Set<String> = [projectsID.uuidString, jobA.uuidString, colourways, inA.uuidString]
    let partialManifest = try! Sharing.export(level: .collection, subject: projectsID, from: shareLib, schema: shareSchema, catalogue: catalogueNamed, ticked: ticks, to: partial, now: tcat)
    check(!partialManifest.files.contains { $0.path.hasSuffix("Headings.coltyp") } && partialManifest.files.contains { $0.path.hasSuffix("Autumn Range.colpal") }
          && partialManifest.files.contains { $0.path == "Projects.colcat" } && (try? Sharing.inspect(partial))?.ok == true,
          "unticking a palette leaves it out of the zip, a ticked palette goes with the member and collection above it, and the result still checks clean")
    // Bringing in: staged, read as a catalogue, placed, written into another catalogue as one change.
    let intoDir = root.appendingPathComponent("tree/Into")
    let intoStore = LibraryStore(directory: intoDir, legacyURL: nil, name: "Into")
    var intoLib = try! intoStore.load()
    var intoSchema = intoStore.schema
    let staging = try! Sharing.stage(inspected)
    let staged = try! Sharing.read(staging: staging, level: .collection)
    check(staged.library.projects.map { $0.name } == ["Job Alpha"] && staged.library.swatches.count == 2 && staged.schema.collections.map { $0.name } == ["Projects"] && staged.paths[jobA] == jobA.uuidString,
          "a staged collection reads as a catalogue of its own, by the same reader as any other")
    check(Sharing.placements(for: .collection, in: intoLib, schema: intoSchema).map { $0.0 } == [.catalogue] && Sharing.placements(for: .palette, in: intoLib, schema: intoSchema).first?.0 == .pool
          && Sharing.placements(for: .workGroup, in: intoLib, schema: intoSchema).count == 1,
          "a share may land only where its level fits: a collection in the catalogue, a palette in the Library or a member, a work group in a collection")
    // Every catalogue's first collection shares one fixed id, so a share of it is a twin of the one here: Replace folds it in.
    let firstTwin = Sharing.duplicates(in: staged, ticked: nil, into: intoLib, schema: intoSchema, placement: .catalogue)
    let firstIn = Sharing.commit(staged, choices: Sharing.Choices(ticked: nil, placement: .catalogue, resolutions: [SchemaTrial.firstCollection: .replace]), into: &intoLib, schema: &intoSchema, at: tcat)
    try! intoStore.save(intoLib, schema: intoSchema)
    let intoBack = try! intoStore.load()
    if !fm.fileExists(atPath: intoDir.appendingPathComponent("Projects/Job Alpha/Colourways/Autumn Range.colpal").path) {
        print("        stacks staged: \(staged.schema.stacks?.keys.map { $0 } ?? []) into: \(intoSchema.stacks?.keys.map { $0 } ?? [])  places: \(intoSchema.places)")
        if let e = fm.enumerator(atPath: intoDir.path) { for case let f as String in e { print("          \(f)") } }
    }
    check(firstTwin.map { $0.kind } == [.collection] && firstIn.members == 1 && firstIn.palettes == 2 && firstIn.added == 3 && firstIn.replaced == 1 && intoBack.project(jobA)?.name == "Job Alpha" && intoBack.palettes(in: jobA).count == 2
          && intoStore.schema.collections.map { $0.name } == ["Projects"] && intoStore.schema.stacks?[jobA.uuidString]?.children[1].name == "Colourways"
          && fm.fileExists(atPath: intoDir.appendingPathComponent("Projects/Job Alpha/Colourways/Autumn Range.colpal").path),
          "into a fresh catalogue a collection lands whole: its member with its own tree, its palettes in their folders, the first collection folded into the one every catalogue starts with")
    // The same share again: every piece is a twin, by id; each answer does what it says.
    let twins = Sharing.duplicates(in: staged, ticked: nil, into: intoBack, schema: intoStore.schema, placement: .catalogue)
    check(twins.map { $0.kind } == [.collection, .member, .palette, .palette] && twins.allSatisfy { $0.why == .sameID } && twins.contains { $0.name == "Autumn Range" && $0.existing == "Autumn Range" },
          "bringing the same share in again finds the collection, the member and the palettes by id")
    var skipLib = intoBack, skipSchema = intoStore.schema
    let skipped = Sharing.commit(staged, choices: Sharing.Choices(ticked: nil, placement: .catalogue, otherwise: .skip), into: &skipLib, schema: &skipSchema, at: tcat)
    check(skipped.skipped == 1 && skipLib == intoBack && skipSchema == intoStore.schema, "Skip on the collection leaves the catalogue exactly as it was")
    var bothLib = intoBack, bothSchema = intoStore.schema
    let both = Sharing.commit(staged, choices: Sharing.Choices(ticked: nil, placement: .catalogue, otherwise: .keepBoth), into: &bothLib, schema: &bothSchema, at: tcat)
    check(both.added == 4 && bothSchema.collections.map { $0.name } == ["Projects", "Projects 2"] && bothLib.projects.count == 2 && bothLib.swatches.count == 4 && Set(bothLib.swatches.map { $0.id }).count == 4
          && bothLib.projects.filter { $0.name == "Job Alpha" }.count == 2,
          "Keep Both brings the share in beside what is there, under new ids, the collection told apart by its name")
    var replaceLib = intoBack, replaceSchema = intoStore.schema
    var changed = staged
    if let at = changed.library.swatches.firstIndex(where: { $0.id == inA }) { changed.library.swatches[at].name = "Autumn Range Revised" }
    let replaced = Sharing.commit(changed, choices: Sharing.Choices(ticked: nil, placement: .catalogue, otherwise: .replace), into: &replaceLib, schema: &replaceSchema, at: tcat)
    check(replaced.replaced == 4 && replaceLib.projects.count == 1 && replaceLib.swatches.count == 2 && replaceLib.swatch(inA)?.name == "Autumn Range Revised" && replaceSchema.collections.count == 1,
          "Replace puts the share's version in the place of what was there, id for id")
    var renameLib = intoBack, renameSchema = intoStore.schema
    let renamed = Sharing.commit(staged, choices: Sharing.Choices(ticked: nil, placement: .catalogue, resolutions: [jobA: .rename, inA: .rename, typeA: .rename], otherwise: .skip), into: &renameLib, schema: &renameSchema, at: tcat)
    check(renamed.skipped == 1 && renamed.renamed == 0 && renameLib.projects.count == 1, "an answer for each thing is kept to: with the collection skipped nothing beneath it comes in")
    let renamedIn = Sharing.commit(staged, choices: Sharing.Choices(ticked: nil, placement: .catalogue, resolutions: [jobA: .rename, inA: .rename, typeA: .rename], otherwise: .replace), into: &renameLib, schema: &renameSchema, at: tcat)
    check(renamedIn.renamed == 3 && renameLib.projects.map { $0.name }.sorted() == ["Job Alpha", "Job Alpha 2"] && renameLib.swatches.contains { $0.name == "Autumn Range 2" },
          "Rename brings a twin in under the next free name, beside the original")
    // A palette on its own: one file; the same colours under another name are a twin; it lands in a member or the Library.
    let paletteShare = zipDir.appendingPathComponent("Autumn.colshr")
    let paletteManifest = try! Sharing.export(level: .palette, subject: inA, from: intoBack, schema: intoStore.schema, catalogue: catalogueNamed, to: paletteShare, now: tcat)
    let paletteInspected = try! Sharing.inspect(paletteShare)
    let paletteStaging = try! Sharing.stage(paletteInspected)
    var paletteStaged = try! Sharing.read(staging: paletteStaging, level: .palette)
    paletteStaged.palette = paletteStaged.palette.map { pair in var p = pair.0; p.name = "Autumn Again"; return (Sharing.renamedCopyForTest(p), pair.1) }
    let colourTwin = Sharing.duplicates(in: paletteStaged, ticked: nil, into: intoBack, schema: intoStore.schema, placement: .pool)
    var poolLib = intoBack, poolSchema = intoStore.schema
    let intoPool = Sharing.commit(paletteStaged, choices: Sharing.Choices(ticked: nil, placement: .pool, otherwise: .keepBoth), into: &poolLib, schema: &poolSchema, at: tcat)
    check(paletteInspected.ok && paletteInspected.manifest.level == .palette && paletteInspected.tree.kind == .palette && paletteManifest.files.map { $0.path } == ["Autumn Range.colpal"]
          && paletteManifest.origin?.member?.name == "Job Alpha" && colourTwin.map { $0.why } == [.sameColours] && colourTwin.first?.existing == "Autumn Range"
          && intoPool.added == 1 && poolLib.palettes(in: nil).map { $0.name } == ["Autumn Again"],
          "a palette shares as its one file and says whose it was; the same colours under another name are seen as a twin; Keep Both puts it in the Library")
    // A work group on its own says where it sat: that place is offered first, and it lands wherever it is pointed.
    let memberShare = zipDir.appendingPathComponent("JobAlpha.colshr")
    _ = try! Sharing.export(level: .workGroup, subject: jobA, from: intoBack, schema: intoStore.schema, catalogue: catalogueNamed, to: memberShare, now: tcat)
    let memberInspected = try! Sharing.inspect(memberShare)
    let memberStaged = try! Sharing.read(staging: try! Sharing.stage(memberInspected), level: .workGroup)
    var wgLib = try! treeStore.load(), wgSchema = treeStore.schema
    let clientsLtd = wgSchema.collections.first { $0.name == "Clients Ltd" }!
    let blueprint = Sharing.placements(for: .workGroup, in: wgLib, schema: wgSchema, origin: memberInspected.manifest.origin)
    let underAcme = Sharing.commit(memberStaged, choices: Sharing.Choices(ticked: nil, placement: .collection(clientsLtd.id, clientsLtd.folders[0].id), otherwise: .keepBoth), into: &wgLib, schema: &wgSchema, at: tcat)
    try! treeStore.save(wgLib, schema: wgSchema)
    let landed = wgLib.projects.first { $0.name == "Job Alpha" && $0.id != jobA }
    check(memberInspected.ok && memberInspected.manifest.level == .workGroup && memberInspected.manifest.origin?.collection?.name == "Projects" && blueprint.first?.0 == .collection(SchemaTrial.firstCollection, nil)
          && memberStaged.library.projects.count == 1 && underAcme.members == 1 && underAcme.palettes == 2
          && landed != nil && SchemaTrial.folder(of: landed!.id, among: wgSchema.collections, places: wgSchema.places) == clientsLtd.folders[0].id
          && fm.fileExists(atPath: treeDir.appendingPathComponent("Clients Ltd/Acme Ltd/Job Alpha/Colourways/Autumn Range.colpal").path),
          "a work group shares as a catalogue of its own and says where it sat: that place is offered first, and it lands wherever it is pointed, under a client, with its own tree and its palettes")
    for dir in [staging, paletteStaging] { Sharing.discard(dir) }
    check(!fm.fileExists(atPath: staging.path), "a staging folder is gone once the share is in or set aside")

    print("the splash builds the tree")
    func answered(_ who: String?, _ streams: [String], _ make: String, kinds: [String] = [], groups: [String]? = nil, clients: [String], members: [String]) -> (SchemaTrial.SchemaFile, Library) {
        let d = SplashDraft(); d.who = who; d.streams = streams; d.oneKind = streams.isEmpty; d.kinds = kinds.isEmpty ? [make] : kinds; d.clients = clients; d.members = members
        if let g = groups { d.groups = g }
        var f = SchemaTrial.SchemaFile(collections: [], places: [:]), l = Library()
        d.build(into: &f, library: &l, at: tcat)
        return (f, l)
    }
    let (withStreams, wsLib) = answered("Clients", ["Web", "Print"], "Projects", clients: ["Acme"], members: ["Spring Launch"])
    let acmeF = withStreams.collections[0].folders.first { $0.name == "Acme" }, webF = withStreams.collections[0].folders.first { $0.name == "Web" }
    check(withStreams.collections.map { $0.name } == ["Clients"] && withStreams.collections[0].levels == ["Client", "Stream"] && acmeF?.parent == nil && webF?.parent == acmeF?.id
          && withStreams.collections[0].folders.map { $0.name } == ["Acme", "Web", "Print"] && wsLib.projects.map { $0.name } == ["Spring Launch"]
          && withStreams.places[wsLib.projects[0].id.uuidString] == SchemaPlace(collection: withStreams.collections[0].id, folder: webF?.id)
          && withStreams.collections[0].stack.name == "Project" && withStreams.collections[0].stack.children.map { $0.role } == SchemaRole.allCases.map { Optional($0) },
          "Clients with two streams build Clients, a client with both streams inside it, and the first project in the first stream, holding the four groups")
    let (oneKind, okLib) = answered("Customers", [], "Jobs", clients: ["Acme"], members: ["Fit Out"])
    check(oneKind.collections[0].levels == ["Customer"] && oneKind.collections[0].folders.map { $0.name } == ["Acme"] && oneKind.places[okLib.projects[0].id.uuidString]?.folder == oneKind.collections[0].folders[0].id
          && SchemaTrial.memberName(of: oneKind.collections[0]) == "Job", "Customers with one kind of work build one level, the customer, with the first job in it")
    let (own, ownLib) = answered(SplashDraft.ownWork, [], "Products", clients: [], members: ["Driftwood Star"])
    check(own.collections[0].name == "My Products" && own.collections[0].levels.isEmpty && own.collections[0].folders.isEmpty && own.places[ownLib.projects[0].id.uuidString]?.folder == nil,
          "Our own work with one kind builds My Products with the first product straight in it")
    let (ownStreams, osLib) = answered(SplashDraft.ownWork, ["Web", "Print"], "Ranges", clients: [], members: ["Autumn 27"])
    check(ownStreams.collections[0].levels == ["Stream"] && ownStreams.collections[0].folders.map { $0.parent } == [nil, nil] && ownStreams.places[osLib.projects[0].id.uuidString]?.folder == ownStreams.collections[0].folders[0].id,
          "Our own work with streams builds the streams as the one level, the first range in the first stream")
    check(SplashDraft.singular("Clients") == "Client" && SplashDraft.singular("Ranges") == "Range" && SplashDraft.singular("Companies") == "Company" && SplashDraft.singular("Campaigns") == "Campaign",
          "the word for one of them comes from the word for many")
    let (twoKinds, tkLib) = answered("Clients", ["Web"], "", kinds: ["Products", "Projects"], groups: ["Palettes", "Assets", "Props"], clients: ["Acme"], members: ["Driftwood"])
    let tkFolders = twoKinds.collections[0].folders, tkWeb = tkFolders.first { $0.name == "Web" }, tkProducts = tkFolders.first { $0.name == "Products" }
    check(twoKinds.collections[0].levels == ["Client", "Stream", "Kind"] && tkFolders.map { $0.name } == ["Acme", "Web", "Products", "Projects"]
          && tkProducts?.parent == tkWeb?.id && tkFolders.first { $0.name == "Projects" }?.parent == tkWeb?.id
          && twoKinds.places[tkLib.projects[0].id.uuidString]?.folder == tkProducts?.id && twoKinds.collections[0].stack.name == "Product"
          && twoKinds.collections[0].stack.children.map { $0.role } == [.palettes, nil, nil] && twoKinds.collections[0].stack.children.map { $0.kind } == ["Palettes", "Assets", "Props"],
          "two kinds made are a level of their own under the stream, the first product in the first kind, and a custom group is a typed folder with no role")
    // The tree on disk nests the levels: Clients/Acme/Web/Spring Launch, and reads back with the same parents.
    let splashDir = root.appendingPathComponent("tree/Splash")
    let splashStore = LibraryStore(directory: splashDir, legacyURL: nil, name: "Splash")
    try! splashStore.save(wsLib, schema: withStreams)
    let splashBack = try! splashStore.load()
    check(fm.fileExists(atPath: splashDir.appendingPathComponent("Clients/Acme/Web/Spring Launch/Palettes").path) && fm.fileExists(atPath: splashDir.appendingPathComponent("Clients/Acme/Print").path)
          && splashBack.project(wsLib.projects[0].id) != nil && splashStore.schema.collections[0].folders.first { $0.name == "Web" }?.parent == acmeF?.id
          && splashStore.schema.collections[0].levels == ["Client", "Stream"] && SchemaTrial.folder(of: wsLib.projects[0].id, among: splashStore.schema.collections, places: splashStore.schema.places) == webF?.id,
          "the levels nest on disk, Clients/Acme/Web/Spring Launch, and read back with their parents and the member in the deepest")
    try! fm.moveItem(at: splashDir.appendingPathComponent("Clients/Acme/Web"), to: splashDir.appendingPathComponent("Clients/Acme/Online"))
    _ = try! splashStore.load()
    check(splashStore.schema.collections[0].folders.first { $0.id == webF?.id }?.name == "Online" && splashStore.schema.collections[0].folders.first { $0.id == webF?.id }?.parent == acmeF?.id
          && (try? splashStore.load())?.project(wsLib.projects[0].id) != nil,
          "a nested level renamed in Finder keeps its place under its parent, and the member inside it")

    print("where catalogues and their members are kept")
    let homeDir = root.appendingPathComponent("home"), awayDir = root.appendingPathComponent("awayDir")
    let cats = Catalogues(root: homeDir, legacyURL: nil)
    let inside = try! cats.create("Inside")
    let outside = try! cats.create("Outside", under: awayDir)
    check(cats.directory(for: inside) == homeDir.appendingPathComponent("Catalogues/Inside") && cats.directory(for: outside) == awayDir.appendingPathComponent("Outside")
          && fm.fileExists(atPath: awayDir.appendingPathComponent("Outside/Outside.colcat").path) && Set(cats.names()).isSuperset(of: ["Inside", "Outside"]),
          "a catalogue is made under Catalogues in the app's home, or under any folder the user chose, and both are listed")
    let adoptedName = try! Catalogues(root: root.appendingPathComponent("home2"), legacyURL: nil).adopt(awayDir.appendingPathComponent("Outside/Outside.colcat"))
    check(adoptedName == "Outside" && Catalogues(root: root.appendingPathComponent("home2"), legacyURL: nil).directory(for: "Outside") == awayDir.appendingPathComponent("Outside"),
          "a .colcat file chosen from anywhere is opened where it is, under its own name, with nothing copied")
    try! "{}".write(to: awayDir.appendingPathComponent("Outside/Outside.colhis"), atomically: true, encoding: .utf8)
    let renamedOut = try! cats.rename("Outside", to: "Outer")
    check(renamedOut == "Outer" && cats.directory(for: "Outer") == awayDir.appendingPathComponent("Outer") && fm.fileExists(atPath: awayDir.appendingPathComponent("Outer/Outer.colcat").path),
          "a catalogue kept awayDir is renamed where it is, folder and file alike")
    check(fm.fileExists(atPath: awayDir.appendingPathComponent("Outer/Outer.colhis").path) && !fm.fileExists(atPath: awayDir.appendingPathComponent("Outer/Outside.colhis").path),
          "the history beside the catalogue's file takes the new name with it")
    try! Catalogues(root: homeDir, legacyURL: nil).store(for: "Inside").mutate { lib in _ = lib.createProject(named: "Cookra") }
    check(fm.fileExists(atPath: homeDir.appendingPathComponent("Catalogues/Inside/Projects/Cookra/Information/Cookra.colinf").path)
          && (try? Catalogues(root: homeDir, legacyURL: nil).store(for: "Inside").load().projects.first?.name) == "Cookra",
          "a member made in a catalogue is a folder inside its collection's folder, and reads back")

    print("purposes on the page")
    var tabLib = Library()
    let tabPalette = tabLib.createSwatch(at: tcat)
    tabLib.add(["#808080", "#00FF00"], toSwatch: tabPalette, at: tcat)
    tabLib.setPurpose(.print, on: true, ofPalette: tabPalette, at: tcat)
    tabLib.setPurpose(.web, on: true, ofPalette: tabPalette, at: tcat)
    let onScreen = tabLib.verdict(on: ["#808080", "#00FF00"], for: Purpose.web.starter)
    let inPrint = tabLib.verdict(on: ["#808080", "#00FF00"], for: Purpose.print.starter)
    check(onScreen.holds && onScreen.tag == "All 2 Hold" && tabLib.verdict(on: [], for: Purpose.web.starter).holds,
          "a purpose whose profile holds every colour says so")
    if PressProfiles.space(named: PressProfiles.generic) != nil {
        check(!inPrint.holds && inPrint.tag == "1 Of 2 Out Of Range" && inPrint.detail.contains("cannot hold 1"), "a purpose says how many colours its channels cannot hold, and which channels")
    }
    check(Purpose.allCases.map { $0.starter.name } == ["Screen And Web", "Print", "Photography", "Video", "Cinema And VFX", "Rendering And Effects"]
          && Purpose.print.starterLabels.contains(.cmyk) && Purpose.threeD.starter.holds(RGBSpace.linearSRGB.rawValue),
          "each purpose starts with a profile and a set of values that suit it")
    tabLib.setProfile(ColourProfiles.starters[4], for: .print, ofPalette: tabPalette, at: tcat.addingTimeInterval(1))
    tabLib.setPurposeSettings(.print, ofPalette: tabPalette, at: tcat.addingTimeInterval(2)) { $0.labels = ["cmyk"] }
    tabLib.setProfile(ColourProfiles.starters[2], for: .cine, ofPalette: tabPalette, at: tcat)
    let printSettings = tabLib.swatch(tabPalette)?.config(for: .print)
    check(printSettings?.profile == ColourProfiles.starters[4].id && printSettings?.labels == ["cmyk"] && printSettings?.changedAt == tcat.addingTimeInterval(2)
          && tabLib.swatch(tabPalette)?.config(for: .web)?.profile == nil && tabLib.swatch(tabPalette)?.config(for: .cine) == nil
          && tabLib.profileRecord(ColourProfiles.starters[4].id) != nil && tabLib.swatch(tabPalette)?.profile == nil,
          "a purpose keeps a profile and a set of values of its own, apart from the palette's and from other purposes'")

    print("copy to project")
    var copyLib = Library()
    let tc = Date(timeIntervalSince1970: 1_760_000_000)
    let srcProject = copyLib.createProject(named: "Source", at: tc)
    let dstProject = copyLib.createProject(named: "Client", at: tc)
    let srcPalette = copyLib.createSwatch(at: tc)
    _ = copyLib.renameSwatch(srcPalette, to: "Brand")
    _ = copyLib.add(["#FF0000", "#0033FF"], toSwatch: srcPalette, at: tc)
    copyLib.setName("Fire", of: "#FF0000", in: srcPalette, at: tc)
    copyLib.move(srcPalette, to: srcProject, index: 0, at: tc)
    // The same steps the app takes for Copy To Project, in the model.
    let dup = copyLib.createSwatch(at: tc.addingTimeInterval(1))
    _ = copyLib.renameSwatch(dup, to: "Brand (Client)")
    _ = copyLib.add(copyLib.hexes(inSwatch: srcPalette, by: .oldest), toSwatch: dup, at: tc)
    copyLib.setName("Fire", of: "#FF0000", in: dup, at: tc)
    copyLib.move(dup, to: dstProject, index: Int.max, at: tc)
    _ = copyLib.add(["#00FF00"], toSwatch: dup, at: tc)
    check(copyLib.palettes(in: srcProject).map { $0.name } == ["Brand"] && copyLib.palettes(in: dstProject).map { $0.name } == ["Brand (Client)"]
          && copyLib.hexes(inSwatch: srcPalette, by: .oldest) == ["#FF0000", "#0033FF"] && copyLib.hexes(inSwatch: dup, by: .oldest).count == 3
          && copyLib.name(of: "#FF0000", in: dup) == "Fire",
          "a palette copied to a project is a second palette there, named for its new home, keeping colour names, and the original is left alone")

    print("locked projects")
    var lockLib = Library()
    let lp = lockLib.createProject(named: "Locked", at: tc)
    let lpal = lockLib.createSwatch(at: tc); _ = lockLib.add(["#123456"], toSwatch: lpal, at: tc); lockLib.move(lpal, to: lp, index: 0, at: tc)
    lockLib.setProjectLocked(lp, true)
    var attempt = lockLib; _ = attempt.add(["#654321"], toSwatch: lpal, at: tc)
    check(lockLib.lockedProjectChanged(by: attempt) == "Locked", "adding a colour to a palette in a locked project is refused by name")
    attempt = lockLib; _ = attempt.renameProject(lp, to: "Other", at: tc)
    check(lockLib.lockedProjectChanged(by: attempt) == "Locked", "renaming a locked project is refused")
    attempt = lockLib; attempt.deleteProject(lp, at: tc)
    check(lockLib.lockedProjectChanged(by: attempt) == "Locked", "deleting a locked project is refused")
    attempt = lockLib; attempt.setProjectLocked(lp, false)
    check(lockLib.lockedProjectChanged(by: attempt) == nil, "unlocking is the one change a locked project allows")
    attempt = lockLib; let elsewhere = attempt.createSwatch(at: tc); _ = attempt.add(["#ABCDEF"], toSwatch: elsewhere, at: tc)
    check(lockLib.lockedProjectChanged(by: attempt) == nil, "work outside the locked project goes on as normal")
    let lockStore = LibraryStore(directory: root.appendingPathComponent("tree/Locked"), legacyURL: nil, name: "Locked")
    try! lockStore.save(lockLib)
    check((try? lockStore.load())?.project(lp)?.isLocked == true, "the lock travels in the member's file")

    print("history")
    var hist = StepHistory()
    var hLib = Library()
    let th = Date(timeIntervalSince1970: 1_760_000_000)
    hist.record("Opened", library: hLib, before: nil, limit: 0, at: th)
    let hLib0 = hLib
    let hp = hLib.createProject(named: "Client", at: th)
    hist.record("New Project", library: hLib, before: hLib0, limit: 0, at: th)
    let hLib1 = hLib
    let hs = hLib.createSwatch(at: th); hLib.add(["#FF0000"], toSwatch: hs, at: th); hLib.move(hs, to: hp, index: 0, at: th)
    hist.record("Add Colours", library: hLib, before: hLib1, limit: 0, at: th)
    let hLib2 = hLib
    let hs2 = hLib.createSwatch(at: th.addingTimeInterval(1)); hLib.add(["#00FF00"], toSwatch: hs2, at: th)
    hist.record("New Palette", library: hLib, before: hLib2, limit: 0, at: th)
    check(hist.steps.map { $0.title } == ["Opened", "New Project", "Add Colours", "New Palette"] && hist.current == 3,
          "every change is a step, newest last, and the library matches the last one")
    check(hist.steps.map { $0.project } == [nil, hp, hp, nil], "a step that touched one project is marked with it; a loose palette is not")
    check(hist.steps(in: hp).count == 2 && hist.steps(changing: hs).map { $0.title } == ["Add Colours"],
          "a project's steps and a palette's own changes can be picked out")
    let fresh = SchemaTrial.SchemaFile.fresh
    let backTo = hist.go(to: 1, from: hLib, schema: fresh)
    check(backTo?.library == hLib1 && hist.current == 1 && hist.steps.count == 4, "going back to a step gives the library as it was then, worked out from the changes, and keeps the later steps")
    let forward = hist.go(to: 3, from: backTo!.library, schema: fresh)
    check(forward?.library == hLib && hist.current == 3, "going forward again gives back exactly what there was")
    _ = hist.go(to: 1, from: hLib, schema: fresh)
    var hRenamed = hLib1
    _ = hRenamed.renameProject(hp, to: "Customer", at: th)
    hist.record("Rename Project", library: hRenamed, before: hLib1, limit: 0, at: th)
    check(hist.steps.map { $0.title } == ["Opened", "New Project", "Rename Project"] && hist.current == 2,
          "a new step taken from an earlier one cuts off the steps after it")
    hist.delete(at: 1)
    check(hist.steps.map { $0.title } == ["Opened", "Rename Project"] && hist.current == 1 && hist.go(to: 0, from: hRenamed, schema: fresh)?.library == hLib0,
          "a step can be deleted; its change folds into the step after it, so going back still lands where it did")
    _ = hist.go(to: 1, from: hLib0, schema: fresh)
    var hist3 = StepHistory()
    var cLib = Library()
    hist3.record("Opened", library: cLib, before: nil, limit: 0, at: th)
    let cLib0 = cLib
    let cs = cLib.createSwatch(at: th); cLib.add(["#FF2400", "#00FF00"], toSwatch: cs, at: th)
    hist3.record("Add Colours", library: cLib, before: cLib0, limit: 0, at: th)
    let cLib1 = cLib
    cLib.remove(["#00FF00"], fromSwatch: cs, at: th)
    hist3.record("Remove Colours", library: cLib, before: cLib1, limit: 0, at: th)
    check(hist3.change(at: 1) == StepChange(added: ["#FF2400", "#00FF00"], removed: []) && hist3.change(at: 2) == StepChange(added: [], removed: ["#00FF00"])
          && hist3.change(at: 0).isEmpty, "a step knows which colours it brought in or took out")
    check(stepSymbol(for: "Pick Colour") == "eyedropper" && stepSymbol(for: "Delete Palette") == "trash" && stepSymbol(for: "Rename Tag") == "pencil"
          && stepSymbol(for: "Sync") == "arrow.triangle.2.circlepath" && stepSymbol(for: "Something Else") == "circle", "each kind of step has a symbol")
    for i in 0..<5 { hist.record("Step \(i)", library: hRenamed, before: hRenamed, limit: 3, at: th) }
    check(hist.steps.count == 3 && hist.steps.last?.title == "Step 4" && hist.current == 2, "a limit keeps only the newest steps")
    var withSchema = StepHistory()
    withSchema.record("Opened", library: hLib, before: nil, limit: 0, at: th)
    var changedSchema = fresh
    changedSchema.collections[0].name = "Clients"
    withSchema.record("Change Schema", library: hLib, before: hLib, schema: (fresh, changedSchema), limit: 0, at: th)
    let backSchema = withSchema.go(to: 0, from: hLib, schema: changedSchema)
    check(backSchema?.schema == fresh && withSchema.go(to: 1, from: hLib, schema: fresh)?.schema == changedSchema && withSchema.steps[1].delta.schema != nil,
          "a change to the schema is a step, undone and redone with the rest")
    let hIndex = root.appendingPathComponent("history/Hist.colcat")
    try! fm.createDirectory(at: hIndex.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! HistoryStore.save(hist, beside: hIndex)
    check(HistoryStore.load(beside: hIndex) == hist && HistoryStore.url(beside: hIndex).lastPathComponent == "Hist.colhis",
          "history is kept in a file of its own beside the catalogue's index and reads back whole")
    check(HistoryStore.load(beside: root.appendingPathComponent("nowhere/x.colcat")).isEmpty, "no file, no history")
    var big = StepHistory()
    var bLib = Library()
    big.record("Opened", library: bLib, before: nil, limit: 0, at: th)
    for i in 0..<200 {
        let before = bLib
        _ = bLib.createSwatch(named: "Palette \(i)", hexes: [String(format: "#%06X", i * 70_000 + 1)], at: th)
        big.record("New Palette", library: bLib, before: before, limit: 0, at: th)
    }
    let bigData = try! ColourFiles.encoder().encode(HistoryStore.File(steps: big.steps, current: big.current))
    var rewound = big
    let atStart = rewound.go(to: 0, from: bLib, schema: fresh)
    if atStart?.library != Library() { print("        rewound: \(atStart?.library.swatches.count ?? -1) swatches, \(atStart?.library.colours.count ?? -1) colours, active \(String(describing: atStart?.library.activeSwatchID))") }
    print("        \(big.steps.count) steps take \(bigData.count) bytes")
    check(bigData.count < 1_000_000 && atStart?.library == Library() && rewound.go(to: 200, from: atStart!.library, schema: fresh)?.library == bLib,
          "two hundred steps take under a megabyte, because a step holds its change and not the whole library, and undoing them all gives back the start")

    print("favourites and custom palettes")
    var lib = Library()
    let t = Date(timeIntervalSince1970: 1_760_000_000)
    let a = lib.createSwatch(named: "Picked", hexes: ["#111111"], at: t)
    let b = lib.createSwatch(named: "Built", hexes: ["#111111", "#222222"], custom: true, at: t)
    check(lib.swatch(a)?.custom == false && lib.swatch(b)?.custom == true, "built palettes are marked custom")
    lib.setFavourite(a, true, at: t.addingTimeInterval(10))
    check(lib.swatch(a)?.favourite == true && lib.swatch(b)?.favourite == false, "a palette can be starred")
    let round = try? JSONDecoder.library.decode(Library.self, from: JSONEncoder.library.encode(lib))
    check(round == lib, "stars and the custom mark survive saving")
    var other = lib
    other.setFavourite(a, false, at: t.addingTimeInterval(20))
    other.setFavourite(b, true, at: t.addingTimeInterval(20))
    let merged = mergeLibraries(local: lib, remote: other)
    check(merged.swatch(a)?.favourite == false && merged.swatch(b)?.favourite == true && merged.swatch(b)?.custom == true,
          "the newer star choice wins a sync, and custom palettes stay custom")
    check(change(from: lib, to: merged).isEmpty, "a change of star alone does not interrupt with a merge prompt")
    let exported = merged.exportPalette(b, by: .oldest)
    check(exported?.name == "Built" && exported?.colours.map { $0.hex } == ["#111111", "#222222"] && exported?.colours.first?.name == colourName("#111111"),
          "a palette exports with its colours named")

    print("upgrade from version 2")
    let v2Dir = root.appendingPathComponent("was-v2"), v3Dir = root.appendingPathComponent("now-v3")
    try! FileManager.default.createDirectory(at: v2Dir, withIntermediateDirectories: true)
    let v2File = v2Dir.appendingPathComponent("library.json")
    try! JSONEncoder.library.encode(lib).write(to: v2File)
    let v2Before = try! Data(contentsOf: v2File)
    let upgraded = try! LibraryStore(directory: v3Dir, legacyURL: nil, previousURL: v2File).load()
    check(upgraded.swatches.count == 2 && upgraded.colours.count == 2, "first launch brings in the version 2 palettes and colours")
    check((try! Data(contentsOf: v2File)) == v2Before, "the version 2 library is only read")
    let real = Catalogues.standard
    check(real.previousURL?.path.hasSuffix("/MMFFDev Colour 2/library.json") == true
          && real.legacyURL?.path.hasSuffix("/MMFFDev Colour/library.json") == true
          && real.previousURL?.path.hasPrefix(real.root.path + "/") == false,
          "the app looks for earlier libraries in the version 1 and version 2 folders, not its own")
    // On a scratch root, never the real home: a store made here would leave a folder in the user's catalogues.
    var scratch = Catalogues(root: v3Dir.appendingPathComponent("scratch-home"), legacyURL: nil)
    scratch.previousURL = v2File
    check(scratch.store(for: Catalogues.mainName).previousURL == v2File && scratch.store(for: "Some other catalogue").previousURL == nil,
          "only Main is seeded from an earlier version")
}

func runHaloTests(check: (Bool, String) -> Void) {
    print("halo")
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let under = HaloGeometry.frame(below: CGRect(x: 700, y: 600, width: 40, height: 20), in: screen)
    check(under == CGRect(x: 548, y: 248, width: 344, height: 344), "the dial opens centred under its trigger, 8 points clear")
    let corner = HaloGeometry.frame(below: CGRect(x: 1420, y: 10, width: 20, height: 20), in: screen)
    check(corner == CGRect(x: 1088, y: 8, width: 344, height: 344), "near a screen edge the dial stays 8 points inside it")
    let small = HaloGeometry.frame(below: CGRect(x: 100, y: 100, width: 20, height: 20), in: CGRect(x: 0, y: 0, width: 300, height: 260))
    check(small.width == 244 && small.height == 244 && small.minY == 8, "on a small screen the dial shrinks to fit")
    let over = HaloGeometry.frame(over: CGPoint(x: 700, y: 450), reach: 116, in: screen)
    check(over == CGRect(x: 528, y: 278, width: 344, height: 344), "a halo opened over its button has its centre on the button")
    let edge = HaloGeometry.frame(over: CGPoint(x: 1430, y: 890), reach: 116, in: screen)
    check(edge.midX == 1440 - 172 - 116 - 8 && edge.midY == 900 - 172 - 116 - 8, "near a screen edge it moves in far enough for its outer rings too")
    let tight = HaloGeometry.frame(over: CGPoint(x: 10, y: 10), reach: 116, in: CGRect(x: 0, y: 0, width: 500, height: 500))
    check(tight.minX == 8 && tight.minY == 8 && tight.width == 344, "on a screen too small for the outer rings the dial itself stays in")
    let second = HaloGeometry.band(of: 1, diameter: 344), third = HaloGeometry.band(of: 2, diameter: 344)
    check(second.near == 174 && second.far == 230 && third.near == 232 && third.far == 288 && HaloGeometry.reach(rings: 2) == 116,
          "each outer ring is a band of its own, a hair clear of the ring inside it")
    check(HaloGeometry.orbit(of: 0, diameter: 344) == HaloGeometry.orbitRadius(344) && HaloGeometry.orbit(of: 1, diameter: 344) == 202,
          "an outer ring's glyphs ride the middle of its band")
    check(HaloGeometry.level(at: 150, rings: 3, diameter: 344) == 0 && HaloGeometry.level(at: 200, rings: 3, diameter: 344) == 1
          && HaloGeometry.level(at: 260, rings: 3, diameter: 344) == 2 && HaloGeometry.level(at: 50, rings: 3, diameter: 344) == nil
          && HaloGeometry.level(at: 200, rings: 1, diameter: 344) == nil, "a press is placed on the ring it lands on, and on no ring in the centre")
    check(HaloGeometry.halfWedge(of: 1, diameter: 344, count: 2) < HaloGeometry.halfWedge(of: 0, diameter: 344, count: 2)
          && HaloGeometry.halfWedge(of: 1, diameter: 344, count: 60) == .pi / 60, "an outer ring's cursor is as wide as its glyph, never more than one place")
    check(Theme.haloDefaultIsText("ring2.background") && !Theme.haloDefaultIsText("ring2.text") && !Theme.haloDefaultIsText("ring2.cursorBackground")
          && Theme.haloDefaultIsText("ring2.cursorText") && !Theme.haloDefaultIsText("centre.background") && Theme.haloDefaultIsText("centre.text"), "unset, a halo ring is the button colours turned round, and its cursor and centre are the button colours")
    // A catalogue's schema lives in its folder: written there on a change, read back from there, and another folder has its own.
    let schemaHomeA = FileManager.default.temporaryDirectory.appendingPathComponent("colorgain-schema-a-\(UUID().uuidString)")
    let schemaHomeB = FileManager.default.temporaryDirectory.appendingPathComponent("colorgain-schema-b-\(UUID().uuidString)")
    for d in [schemaHomeA, schemaHomeB] { try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
    SchemaTrial.use(directory: schemaHomeA)
    SchemaTrial.collections = [SchemaCollection(name: "Clients", folderName: "Client", stack: SchemaTrial.start)]
    let schemaMember = UUID()
    SchemaTrial.place(schemaMember, in: SchemaTrial.collections[0].id, folder: nil)
    let schemaOnDisk = try? CatalogueTree.read(root: schemaHomeA, palettes: false).schema
    let placedInMemory = SchemaTrial.places[schemaMember.uuidString] != nil
    SchemaTrial.use(directory: schemaHomeB)
    let schemaFreshElsewhere = SchemaTrial.collections.map { $0.name } == ["Projects"] && SchemaTrial.places.isEmpty
    SchemaTrial.use(directory: schemaHomeA)
    check(schemaOnDisk?.collections.map { $0.name } == ["Clients"] && CatalogueTree.catalogue(in: schemaHomeA)?.collections.map { $0.folder } == ["Clients"] && CatalogueTree.isFolder(schemaHomeA.appendingPathComponent("Clients")) && placedInMemory && schemaFreshElsewhere
          && SchemaTrial.collections.map { $0.name } == ["Clients"] && SchemaTrial.read(in: schemaHomeB).collections.map { $0.name } == ["Projects"],
          "a catalogue's schema is written into its tree of folders, read back from it, and a catalogue without one starts fresh")
    // A tag on a level-1 group is worn inside the members in that group and nowhere else; a colour change or a rename keeps the group.
    var groupLib = Library()
    let inGroup = groupLib.createProject(named: "Acme Web"), outside = groupLib.createProject(named: "Elsewhere")
    let acme = SchemaFolder(name: "Acme")
    SchemaTrial.changeCollection(SchemaTrial.collections[0].id) { $0.folders = [acme] }
    SchemaTrial.place(inGroup, in: SchemaTrial.collections[0].id, folder: acme.id)
    let wornIn = groupLib.createSwatch(named: "In", hexes: ["#111111"]), wornOut = groupLib.createSwatch(named: "Out", hexes: ["#222222"])
    for (s, p) in [(wornIn, inGroup), (wornOut, outside)] { if let i = groupLib.swatches.firstIndex(where: { $0.id == s }) { groupLib.swatches[i].projectID = p } }
    groupLib.setTag("Acme Only", colour: "#2F5FD6", project: nil, group: .some(acme.id))
    groupLib.setTags(ofPalette: wornIn, ["Acme Only"]); groupLib.setTags(ofPalette: wornOut, ["Acme Only"])
    groupLib.setTag("Acme Only", colour: "#D9452B", project: nil)
    let groupKept = groupLib.group(ofTag: "Acme Only") == acme.id && groupLib.info(forTag: "Acme Only")?.colour == "#D9452B"
    let groupRead = (try? JSONDecoder.library.decode(Library.self, from: try! JSONEncoder.library.encode(groupLib)))?.info(forTag: "Acme Only")?.groupID == acme.id
    let scopeMenu = TagScopes.menu(groupLib, within: [inGroup])
    groupLib.renameTag("Acme Only", to: "Acme Brand")
    check(groupKept && groupRead && groupLib.scope(ofTag: "Acme Brand") == .group(acme.id) && groupLib.swatch(wornIn)?.tagList == ["Acme Brand"] && groupLib.swatch(wornOut)?.tagList == []
          && groupLib.tags(offeredIn: inGroup).contains("Acme Brand") && !groupLib.tags(offeredIn: outside).contains("Acme Brand") && !groupLib.tags(offeredIn: nil).contains("Acme Brand")
          && scopeMenu.scopes.compactMap { $0 } == [.global, .group(acme.id), .member(inGroup)],
          "a tag on a group is worn only inside its members, keeps its group through a colour change, a rename and the file, and the halo offers Global, the group and the member")
    for d in [schemaHomeA, schemaHomeB] { try? FileManager.default.removeItem(at: d) }

    let schema = SchemaTrial.start, schemaOne = SchemaTrial.addingChild(to: schema.id, in: schema)
    let schemaTwo = SchemaTrial.addingSibling(after: schemaOne.added ?? UUID(), in: schemaOne.tree)
    let schemaThree = SchemaTrial.addingChild(to: schemaTwo.added ?? UUID(), in: schemaTwo.tree)
    check(SchemaTrial.rows(of: schemaThree.tree).map { $0.level } == [1, 2, 2, 2, 2, 2, 2, 3] && SchemaTrial.rows(of: schemaThree.tree).map { $0.node.name } == ["Project", "Information", "Palettes", "Typography", "Tags", "Assets", "Characters", "Palettes"]
          && SchemaTrial.addingSibling(after: schema.id, in: schema).added == nil, "a schema nests groups to any depth, each new one taking the first name its level has free, and the main group has no siblings")
    check(SchemaTrial.rows(of: SchemaTrial.removing(schemaTwo.added ?? UUID(), from: schemaThree.tree)).count == 6 && SchemaTrial.removing(schema.id, from: schemaThree.tree) == schemaThree.tree
          && SchemaTrial.changing(schemaThree.added ?? UUID(), in: schemaThree.tree) { $0.name = "Trees" }.children[5].children[0].name == "Trees"
          && SchemaTrial.title(forLevel: 1) == "Level 1: Primary Group" && SchemaTrial.title(forLevel: 2) == "Level 2: Secondary Group",
          "removing a schema group takes what is inside it and never the main group, and a group is renamed wherever it sits")
    let moved = SchemaTrial.moving(schemaTwo.added ?? UUID(), to: 0, in: schemaThree.tree)
    check(moved.children.map { $0.name } == ["Characters", "Information", "Palettes", "Typography", "Tags", "Assets"] && moved.children[0].children.count == 1
          && SchemaTrial.moving(schemaOne.added ?? UUID(), to: 99, in: schemaThree.tree).children.last?.name == "Assets"
          && SchemaTrial.moving(schemaTwo.added ?? UUID(), to: 6, in: schemaThree.tree) == schemaThree.tree
          && SchemaTrial.moving(schemaTwo.added ?? UUID(), to: 5, in: schemaThree.tree) == schemaThree.tree,
          "a group is dragged to a place among its siblings, keeping what is inside it; past the end means last, and its own slot leaves it where it is")
    check(SchemaTrial.start.children.map { SchemaTrial.role(of: $0) } == [.information, .palettes, .typography, .tags]
          && SchemaTrial.role(of: SchemaNode(name: "Colourways", role: .palettes)) == .palettes && SchemaTrial.role(of: SchemaNode(name: "Tags")) == .tags
          && SchemaTrial.role(of: SchemaNode(name: "Trees")) == nil, "the schema starts as the app's own structure, a group keeps its role when it is renamed, and any other group is a label")
    let clients = SchemaCollection(name: "Clients", folderName: "Client", folders: [SchemaFolder(name: "Acme")], stack: SchemaNode(name: "Contract"))
    let first = SchemaCollection(id: SchemaTrial.firstCollection, name: "Projects", stack: SchemaTrial.start), lone = UUID(), placed = UUID(), stray = UUID()
    let spots = [placed.uuidString: SchemaPlace(collection: clients.id, folder: clients.folders[0].id), stray.uuidString: SchemaPlace(collection: UUID(), folder: UUID())]
    check(SchemaTrial.collection(of: lone, among: [first, clients], places: spots).id == first.id && SchemaTrial.collection(of: placed, among: [first, clients], places: spots).id == clients.id
          && SchemaTrial.folder(of: placed, among: [first, clients], places: spots) == clients.folders[0].id && SchemaTrial.folder(of: lone, among: [first, clients], places: spots) == nil
          && SchemaTrial.collection(of: stray, among: [first, clients], places: spots).id == first.id && SchemaTrial.folder(of: stray, among: [first, clients], places: spots) == nil
          && SchemaTrial.memberName(of: clients) == "Contract" && SchemaTrial.title(forLevel: 0) == "Level 0: Collection",
          "a project is in the first collection until it is placed in another, in a folder only where its collection has it, and back in the first when its collection has gone")
    check(SchemaTrial.plural("Project") == "Projects" && SchemaTrial.plural("Company") == "Companies" && SchemaTrial.plural("Class") == "Classes"
          && SchemaTrial.plural("Brand") == "Brands" && SchemaTrial.plural("Survey") == "Surveys", "the main group's name is made plural for the heading over them")
    check(Theme.next(after: nil) == 0 && Theme.next(after: 0) == 1 && Theme.next(after: 1) == 2 && Theme.next(after: 2) == 3 && Theme.next(after: 3) == nil
          && Theme.lights == ["#242424", "#000000", "#FFFFFF", "#F2F2F2"] && !Theme.takesLightText(on: Theme.light),
          "L turns the background charcoal, then black, then white, then off-white with dark text, then back to the theme")
    check(Theme.light == "#F2F2F2" && colorFromHex(Theme.light) != nil, "light is a neutral off-white, not pure white")
    check(Theme.takesLightText(on: "#000000") && !Theme.takesLightText(on: "#FFFFFF") && !Theme.takesLightText(on: "#808080")
          && Theme.takesLightText(on: "#404040") && Theme.takesLightText(on: "#7A0019") && !Theme.takesLightText(on: "#F5C542"),
          "on a background of the user's own, automatic text is the one of black and white that reads better")
    let grey = ColourDefinition.of(hex: "#4F8093")!, red = ColourDefinition.displayP3([1, 0, 0])
    let asHex = NewColourSheet.convert(grey, to: .hex, press: PressProfiles.generic)
    let noHex = NewColourSheet.convert(red, to: .hex, press: PressProfiles.generic)
    check(asHex?.kind == .hex && asHex?.values == ["#4F8093"] && noHex?.kind == .p3 && noHex?.values == ["255", "0", "0"],
          "a pick turned into a hex stays a hex when sRGB holds it, and becomes Display P3 when it does not")
    let asLab = NewColourSheet.convert(red, to: .lab, press: PressProfiles.generic)
    let labBack = asLab.flatMap { NewColourSheet.read($0.kind, $0.values, press: "") }?.colour
    check(labBack.map { deltaE2000($0.master.lab, red.master.lab) < 0.05 } == true && (asLab?.working.count ?? 0) == 6,
          "a pick turned into Lab reads back as the same colour, and shows its working step by step")
    let wide = NewColourSheet.convert(grey, to: .prophoto, press: PressProfiles.generic)
    let wideBack = wide.flatMap { NewColourSheet.read($0.kind, $0.values, press: "") }?.colour
    check(wideBack.map { deltaE2000($0.master.lab, grey.master.lab) < 0.05 } == true, "a pick turned into ProPhoto reads back as the same colour")
    if let inks = NewColourSheet.convert(red, to: .cmyk, press: PressProfiles.generic) {
        check(inks.values.count == 4 && inks.working.last?.how.hasPrefix("Beyond this press") == true,
              "a pick turned into inks says when the press cannot print it")
    }
    func close(_ a: Double, _ b: Double, _ slack: Double = 0.001) -> Bool { abs(a - b) <= slack }
    let redXY = GamutMaths.corners(of: .srgb, in: .xy), whiteXY = GamutMaths.xy(RGBSpace.srgb.master(of: [1, 1, 1]))
    check(close(redXY[0].x, 0.640) && close(redXY[0].y, 0.330) && close(redXY[1].x, 0.300) && close(redXY[1].y, 0.600) && close(redXY[2].x, 0.150) && close(redXY[2].y, 0.060),
          "on the 1931 map pure red, green and blue sit on the published corners of sRGB")
    check(close(whiteXY.x, 0.3127) && close(whiteXY.y, 0.3290) && GamutMaths.xy(XYZ(x: 0, y: 0, z: 0)) == GamutMaths.white, "white sits on the D65 white point, and black is put there too")
    let whiteUV = GamutMaths.uv(GamutMaths.white), round = GamutMaths.xy(fromUV: whiteUV)
    check(close(whiteUV.x, 0.1978) && close(whiteUV.y, 0.4683) && close(round.x, 0.3127, 1e-9) && close(round.y, 0.3290, 1e-9), "the 1976 map places white where the standard says, and converts back exactly")
    check(GamutMaths.visible(xy: GamutMaths.white) && !GamutMaths.visible(xy: GamutPoint(x: 0.05, y: 0.05)) && !GamutMaths.visible(xy: GamutPoint(x: 0.7, y: 0.7)),
          "the white point is inside the horseshoe; places beyond the spectrum are not")
    let narrow = GamutMaths.slice(lightness: 55) { $0.fits(.srgb) }, wider = GamutMaths.slice(lightness: 55) { $0.fits(.displayP3) }
    check(narrow.count == GamutMaths.hueSteps && zip(narrow, wider).allSatisfy { hypot($0.x, $0.y) <= hypot($1.x, $1.y) + 0.5 }
          && zip(narrow, wider).contains { hypot($1.x, $1.y) - hypot($0.x, $0.y) > 10 },
          "cut at one lightness, Display P3 holds everything sRGB holds and reaches well beyond it in places")
    let edgeRed = RGBSpace.srgb.master(of: [1, 0, 0]).lab, hueRed = atan2(edgeRed.b, edgeRed.a) * 180 / .pi
    check(close(GamutMaths.strongest(hue: hueRed, lightness: edgeRed.l) { $0.fits(.srgb) }, hypot(edgeRed.a, edgeRed.b), 1.0),
          "the edge of sRGB at pure red's hue and lightness is pure red")
    let widest = GamutMaths.outline(of: .srgb, lightness: nil), cut = GamutMaths.outline(of: .srgb, lightness: 55)
    check(widest.count == GamutMaths.hueSteps && zip(widest, cut).allSatisfy { hypot($0.x, $0.y) >= hypot($1.x, $1.y) - 6 } && widest.allSatisfy { hypot($0.x, $0.y) > 20 },
          "a gamut at its widest is never narrower than the same gamut cut at one lightness")
    let labRed = GamutMaths.point(RGBSpace.srgb.master(of: [1, 0, 0]), in: .lab)
    check(close(labRed.x, edgeRed.a, 1e-9) && close(labRed.y, edgeRed.b, 1e-9) && GamutMaths.cubeFaces(2).count == 54, "the round map places a colour by its a* and b*")
    let lin = RGBSpace.linearSRGB.values(of: RGBSpace.srgb.master(of: [146.0 / 255, 209.0 / 255, 0]))
    check(close(lin[0], RGBSpace.srgb.linear(146.0 / 255), 1e-9) && close(lin[1], RGBSpace.srgb.linear(209.0 / 255), 1e-9) && close(lin[2], 0, 1e-9)
          && close(lin[0], 0.2874, 0.0005) && close(lin[1], 0.6376, 0.0005) && RGBSpace.linearSRGB.master(of: lin) == RGBSpace.linearSRGB.master(of: lin)
          && RGBSpace.linearSRGB.text([0.5, 0.25, 1]) == "0.5000, 0.2500, 1.0000" && RGBSpace.linearSRGB.channel == "Rendering",
          "Linear sRGB is sRGB with its curve taken off: the same colour, written as amounts of light")
    check(Prefs.apcaGrade(80).verdict == .pass && Prefs.apcaGrade(62).grade == "Text" && Prefs.apcaGrade(50).verdict == .partial && Prefs.apcaGrade(20).grade == "Fail",
          "an APCA contrast is put in words: body, text, large only, or a fail")
    check(HaloGeometry.wheelStep(speed: 1) == 44 && HaloGeometry.wheelStep(speed: 2) == 22 && HaloGeometry.wheelStep(speed: 0.5) == 88,
          "a faster wheel setting turns the ring in less travel, a slower one in more")
    let letters = HaloSettingsPanel.letters(back: {})
    let ringTwo = letters.first { $0.id == "up0" }?.children?() ?? [], ringThree = ringTwo.first { $0.id == "up1" }?.children?() ?? []
    check(letters.map { $0.label }.joined() == "ABCDEFGHIUpX" && ringTwo.map { $0.label }.joined() == "JKLMNOPQRUp" && ringThree.map { $0.label }.joined() == "STUVWXYZ",
          "the test halo spreads the alphabet over three rings, all but the last with a way up")
    let backed = HaloMenu.withBack(ringThree)
    check(backed.count == ringThree.count + 1 && backed.last?.id == HaloMenu.backID && HaloMenu.withBack(backed).count == backed.count,
          "every outer ring ends with one way back to the ring inside it")
    check(HaloGeometry.wrap(-1, 6) == 5 && HaloGeometry.wrap(13, 6) == 1 && HaloGeometry.wrap(3, 0) == 0, "positions wrap round the ring in both directions")
    check(abs(HaloGeometry.orbitRadius(344) - 142.54) < 0.001, "glyphs ride midway across the band")
    check(HaloGeometry.targetSize(344, count: 6) == 40 && HaloGeometry.targetSize(344, count: 40) == 24, "glyph targets stay between 24 and 40 points")
    check(HaloGeometry.sector(count: 3) == 36 && HaloGeometry.sector(count: 12) == 30 && HaloGeometry.sector(count: 30) == 20, "the wedge narrows as actions are added, within limits")
    let top = HaloGeometry.offset(of: 2, count: 6, turn: 2, radius: 100)
    check(abs(top.x) < 0.0001 && abs(top.y + 100) < 0.0001, "the selected action sits at twelve o'clock")
    let off = [false, true, true, false]
    check(HaloGeometry.step(from: 0, direction: 1, disabled: off) == 3 && HaloGeometry.step(from: 0, direction: -1, disabled: off) == -1,
          "turning skips actions that are switched off")
    check(HaloGeometry.step(from: 0, direction: 1, disabled: [true, true]) == nil && HaloGeometry.step(from: 0, direction: 1, disabled: []) == nil,
          "a ring with nothing to choose does not turn")
    check(HaloGeometry.opening(disabled: [true, false, false], checked: [nil, nil, true], showPositions: false) == 1
          && HaloGeometry.opening(disabled: [true, false, false], checked: [nil, nil, true], showPositions: true) == 2,
          "the dial opens on the first usable action, or on the ticked one when positions are shown")
    check(HaloGeometry.nudge(0.3, by: 1) == 0.4 && HaloGeometry.nudge(0.95, by: 1) == 1 && HaloGeometry.nudge(0, by: -1) == 0,
          "arrow keys slide the confirmation a tenth at a time and stop at the ends")
}

func runShortcutTests(check: (Bool, String) -> Void) {
    print("shortcuts")
    let newPalette = Shortcut(key: "N", modifiers: .command)
    check(newPalette.key == "n" && Shortcut(encoded: newPalette.encoded) == newPalette, "a shortcut survives being saved and read back")
    check(Shortcut(encoded: "") == nil && Shortcut(encoded: "x") == nil && Shortcut(encoded: "1:") == nil, "a damaged saved shortcut is ignored")
    check(Shortcut(key: "n", modifiers: [.command, .shift, .option, .control]).display == "\u{2303}\u{2325}\u{21E7}\u{2318}N"
          && Shortcut(key: " ", modifiers: .command).display == "\u{2318}Space" && Shortcut(key: "\u{F704}", modifiers: .control).display == "\u{2303}F1",
          "shortcuts are written the way the menu bar writes them")

    let reserved = Shortcuts.standard + [(Shortcut(key: "c", modifiers: .command), "Copy")]
    let assigned = [(id: "newPalette", title: "New Palette", shortcut: newPalette), (id: "exportShown", title: "Export", shortcut: Shortcut(key: "e", modifiers: .command))]
    let system = [(keyCode: 20, modifiers: ShortcutModifiers([.command, .shift]))]
    func problem(_ key: String, _ modifiers: ShortcutModifiers, keyCode: Int? = nil, for id: String = "newPalette") -> ShortcutProblem? {
        Shortcuts.problem(with: Shortcut(key: key, modifiers: modifiers), keyCode: keyCode, for: id, reserved: reserved, system: system, assigned: assigned)
    }
    check(problem("c", .command) == .reserved("Copy"), "\u{2318}C cannot be taken from Copy")
    check(problem("w", .command) == .reserved("Close Window") && problem("\t", .command) == .reserved("switch apps"),
          "shortcuts every Mac app shares cannot be taken")
    check(problem("n", .shift) == .needsModifier && problem("n", .option) == .needsModifier && problem("n", .control) == nil,
          "a shortcut must hold \u{2318} or \u{2303}")
    check(problem("3", [.command, .shift], keyCode: 20) == .system && problem("3", [.command, .shift], keyCode: 21) == nil
          && problem("3", .command, keyCode: 20) == nil, "a shortcut macOS has switched on for itself cannot be taken")
    check(problem("e", .command) == .taken("Export") && problem("e", .command, for: "exportShown") == nil,
          "a shortcut on another command cannot be taken, but a command may keep its own")
    check(problem("k", [.command, .option]) == nil, "a free shortcut is accepted")
    check(ShortcutProblem.reserved("Copy").message(for: Shortcut(key: "c", modifiers: .command)).hasPrefix("\u{2318}C is Copy"),
          "the refusal says what the shortcut already does")
}

func runProjectTests(check: (Bool, String) -> Void) {
    print("project details and templates")
    check(Set(ProjectField.allCases.map { $0.rawValue }).count == ProjectField.allCases.count
          && ProjectField.Section.allCases.allSatisfy { s in
              let titles = ProjectField.fields(in: s).map { $0.title }
              return !titles.isEmpty && Set(titles).count == titles.count },
          "every section of the form has fields, and no two in a section share a label")
    let answers = ["clientCompany": "  Acme Ltd ", "clientEmail": "jo@acme.com", "description": "Rebrand", "notes": "   ", "made-up": "x"]
    check(ProjectField.tidy(answers) == ["clientCompany": "Acme Ltd", "clientEmail": "jo@acme.com", "description": "Rebrand"],
          "answers are trimmed, and blank or unknown ones dropped")
    check(ProjectField.problem(name: " ", values: [:]) == "Give the project a name."
          && ProjectField.problem(name: "A", values: ["clientEmail": "jo.acme.com"]) != nil
          && ProjectField.problem(name: "A", values: ["ownerEmail": "jo@acme"]) != nil
          && ProjectField.problem(name: "A", values: ["clientEmail": "jo@acme.com", "ownerEmail": ""]) == nil,
          "the form asks for a name and for emails that look like emails")

    var templates = ProjectTemplate.saving(answers, named: "Acme", into: [])
    check(templates.count == 1 && templates[0].values == ["clientCompany": "Acme Ltd", "clientEmail": "jo@acme.com"],
          "a template keeps who the client and studio are, not the one job's description")
    templates = ProjectTemplate.saving(["ownerCompany": "MMFFDev"], named: "Studio", into: templates)
    templates = ProjectTemplate.saving(["clientCompany": "Acme Group"], named: "acme", into: templates)
    check(templates.map { $0.name } == ["acme", "Studio"] && templates[0].values == ["clientCompany": "Acme Group"],
          "saving under an existing name replaces that template; the list stays in name order")
    let filled = templates[0].filling(["clientCompany": "Old", "description": "Rebrand", "clientPhone": "0161"])
    check(filled == ["clientCompany": "Acme Group", "description": "Rebrand", "clientPhone": "0161"],
          "filling from a template replaces what the template holds and leaves the rest")

    let t = Date(timeIntervalSince1970: 1_800_000_000)
    var lib = Library()
    let id = lib.createProject(named: "Client A", at: t)
    lib.setProjectDetails(id, ["clientCompany": "Acme", "notes": " "], at: t.addingTimeInterval(10))
    check(lib.project(id)?.details == ["clientCompany": "Acme"] && lib.project(id)?.detailsChangedAt == t.addingTimeInterval(10),
          "a project keeps its details")
    lib.setProjectDetails(id, ["clientCompany": "Acme"], at: t.addingTimeInterval(15))
    check(lib.project(id)?.detailsChangedAt == t.addingTimeInterval(10), "saving the same details again changes nothing")
    var other = lib
    other.setProjectDetails(id, ["clientCompany": "Acme Ltd"], at: t.addingTimeInterval(20))
    check(mergeLibraries(local: lib, remote: other).project(id)?.details == ["clientCompany": "Acme Ltd"]
          && mergeLibraries(local: other, remote: lib).project(id)?.details == ["clientCompany": "Acme Ltd"],
          "the newer details win a sync, whichever Mac holds them")
    let old = try! JSONEncoder.library.encode(lib)
    let stripped = String(data: old, encoding: .utf8)!
    check(stripped.contains("\"details\"") && (try? JSONDecoder.library.decode(Library.self, from: old)) == lib,
          "details are saved in the library file and read back")
    var plain = Library()
    plain.createProject(named: "No details", at: t)
    check(!String(data: try! JSONEncoder.library.encode(plain), encoding: .utf8)!.contains("\"details\""),
          "a project without details saves as it always did")
}

func runColourSpaceTests(check: (Bool, String) -> Void) {
    print("wider colour spaces")
    func f(_ format: ColourFormat, _ hex: String) -> String { format.text(hex) }
    check(f(.p3, "#FFFFFF") == "255, 255, 255" && f(.adobeRGB, "#FFFFFF") == "255, 255, 255" && f(.rec2020, "#FFFFFF") == "255, 255, 255"
          && f(.p3, "#000000") == "0, 0, 0" && f(.lab, "#000000") == "0.0, 0.0, 0.0",
          "white and black are the same in every space")
    let white = ColourValues("#FFFFFF")!.lab
    check(abs(white.l - 100) < 0.01 && abs(white.a) < 0.05 && abs(white.b) < 0.05, "white is L* 100 with no colour")
    check(f(.p3, "#FF0000") == "234, 51, 35", "sRGB red in Display P3: \(f(.p3, "#FF0000"))")
    check(f(.adobeRGB, "#FF0000") == "219, 0, 0" && f(.adobeRGB, "#00FF00") == "144, 255, 60",
          "sRGB red and green in Adobe RGB: \(f(.adobeRGB, "#FF0000")) / \(f(.adobeRGB, "#00FF00"))")
    check(f(.rec2020, "#FF0000") == "202, 59, 19", "sRGB red in BT.2020: \(f(.rec2020, "#FF0000"))")
    let red = ColourValues("#FF0000")!.lab
    check(abs(red.l - 54.29) < 0.05 && abs(red.a - 80.81) < 0.05 && abs(red.b - 69.89) < 0.05,
          "sRGB red in L*a*b* under D50: \(f(.lab, "#FF0000"))")
    check(f(.p3, "#808080") == "128, 128, 128" && abs(ColourValues("#808080")!.lab.a) < 0.05, "a grey stays grey")
    check(ColourFormat.defaultCardRows == [.hex, .rgb, .hsl, .hsv, .cmyk] && ColourFormat.cardRows.count == 9,
          "cards keep their five rows until more are switched on")
}

func runTagTests(check: (Bool, String) -> Void) {
    print("tags: colour, scope, rename, delete")
    let t = Date(timeIntervalSince1970: 1_800_000_000)
    var lib = Library()
    lib.addPick("#111111", at: t)
    lib.addPick("#222222", at: t)
    let palette = lib.createSwatch(named: "Web", hexes: ["#111111"], at: t)
    let project = lib.createProject(named: "Client A", at: t)
    lib.setTags(ofColour: "#111111", ["Brand", "dark"], at: t)
    lib.setTags(ofPalette: palette, ["brand"], at: t)
    check(lib.allTags == ["Brand", "dark"] && lib.info(forTag: "Brand") == nil, "tags in use need no record of their own")

    lib.setTag("Print", colour: "#ff6600", project: project, at: t.addingTimeInterval(1))
    check(lib.allTags == ["Brand", "dark", "Print"] && lib.info(forTag: "print")?.colour == "#FF6600" && lib.project(ofTag: "Print") == project,
          "a tag can be made before anything wears it, with a colour and a project")
    check(lib.tags(offeredIn: nil) == ["Brand", "dark"] && lib.tags(offeredIn: project) == ["Brand", "dark", "Print"],
          "a project tag is offered only inside its project; global tags everywhere")

    lib.setTag("Brand", colour: "#00AA88", project: nil, at: t.addingTimeInterval(2))
    lib.renameTag("brand", to: "Identity", at: t.addingTimeInterval(3))
    check(lib.colours.first { $0.hex == "#111111" }?.tags == ["Identity", "dark"] && lib.swatch(palette)?.tagList == ["Identity"]
          && lib.allTags == ["dark", "Identity", "Print"] && lib.info(forTag: "Identity")?.colour == "#00AA88",
          "renaming a tag changes it on every swatch and palette and keeps its colour")
    lib.renameTag("dark", to: "Identity", at: t.addingTimeInterval(4))
    check(lib.colours.first { $0.hex == "#111111" }?.tags == ["Identity"] && lib.allTags == ["Identity", "Print"],
          "renaming onto an existing tag merges the two")
    let uses = lib.uses(ofTag: "identity")
    check(uses.swatches == ["#111111"] && uses.palettes.map { $0.id } == [palette] && lib.hexes(tagged: "Identity") == ["#111111"],
          "a tag knows which swatches and palettes wear it")

    var other = lib
    other.setTag("Print", colour: "#0000FF", project: nil, at: t.addingTimeInterval(10))
    check(mergeLibraries(local: lib, remote: other).info(forTag: "Print")?.colour == "#0000FF"
          && mergeLibraries(local: other, remote: lib).project(ofTag: "Print") == nil,
          "the newer colour and scope win a sync")
    lib.deleteTag("Identity", at: t.addingTimeInterval(20))
    check(lib.allTags == ["Print"] && lib.colours.allSatisfy { ($0.tags ?? []).isEmpty } && lib.swatch(palette)?.tagList == [],
          "deleting a tag takes it off everything")
    check(mergeLibraries(local: lib, remote: other).allTags == ["Print"] && mergeLibraries(local: other, remote: lib).allTags == ["Print"],
          "a deleted tag's record does not come back from the other Mac")
    lib.deleteProject(project, at: t.addingTimeInterval(30))
    check(lib.project(ofTag: "Print") == nil && lib.tags(offeredIn: nil) == ["Print"], "a tag whose project is gone becomes global")
    let data = try! JSONEncoder.library.encode(lib)
    check((try? JSONDecoder.library.decode(Library.self, from: data)) == lib, "tag records are saved in the library file and read back")
    var plain = Library()
    plain.addPick("#333333", at: t)
    check(!String(data: try! JSONEncoder.library.encode(plain), encoding: .utf8)!.contains("\"tags\" : ["), "a library with no tag records saves as it always did")
}

// ---------- cLab: the perceptual engine, the wheel and its rules ----------

func runLabTests(check: (Bool, String) -> Void) {
    print("perceptual colour engine")
    let samples = ["#FFFFFF", "#000000", "#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#4F8093", "#808080", "#10288C", "#F2E9D8"]
    check(samples.allSatisfy { hexFrom(ColourValues($0)!.oklch) == $0 }, "a colour survives the trip into OKLCH and back unchanged")
    let white = ColourValues("#FFFFFF")!.oklch, red = ColourValues("#FF0000")!.oklch
    check(abs(white.l - 1) < 0.001 && white.c < 0.001, "white is lightness 1 with no chroma")
    check(abs(red.l - 0.628) < 0.002 && abs(red.c - 0.2577) < 0.002 && abs(red.h - 29.23) < 0.1,
          "sRGB red is the published OKLCH value: \(red)")
    let tooStrong = OKLCH(l: 0.7, c: 0.39, h: 145)
    let fitted = ColourValues(hexFrom(tooStrong))!.oklch
    check(!displayable(tooStrong) && abs(fitted.h - 145) < 1.5 && abs(fitted.l - 0.7) < 0.01 && fitted.c < 0.39,
          "a colour too strong for the screen keeps its hue and lightness and loses chroma: \(fitted)")
    check(maxChroma(l: 0, h: 20) == 0 && maxChroma(l: 1, h: 20) == 0 && maxChroma(l: 0.6, h: 30) > 0.15,
          "black and white have no room for chroma; a mid red has plenty")

    print("wheel positions")
    func near(_ a: String, _ b: String) -> Bool {
        guard let x = ColourValues(a), let y = ColourValues(b) else { return false }
        return abs(x.r - y.r) <= 1 && abs(x.g - y.g) <= 1 && abs(x.b - y.b) <= 1
    }
    let moved = samples.filter { !near(LabNode(hex: $0)!.hex, $0) }.map { "\($0) became \(LabNode(hex: $0)!.hex)" }
    check(moved.isEmpty, "a colour placed on the wheel reads back as itself \(moved)")
    let grey = LabNode(hex: "#808080")!, vivid = LabNode(hex: "#FF0000")!
    check(grey.s < 0.01 && vivid.s > 0.99, "grey sits at the centre and a pure primary on the rim")
    let p = LabNode(h: 90, s: 0.5, v: 0.6).point, back = LabNode.polar(x: p.x, y: p.y)
    check(abs(p.x) < 1e-9 && abs(p.y - 0.5) < 1e-9 && abs(back.h - 90) < 1e-6 && abs(back.s - 0.5) < 1e-9,
          "hue is the angle and strength the distance from the centre")
    check(LabNode.polar(x: 3, y: 0).s == 1, "a drag beyond the rim stays on it")

    print("harmony rules")
    let base = LabNode(hex: "#10288C")!
    func hues(_ r: LabRule) -> [Int] { r.arrangement(around: base)!.nodes.map { Int((($0.h - base.h + 360).truncatingRemainder(dividingBy: 360)).rounded()) % 360 } }
    check(LabRule.allCases.filter { $0 != .custom }.allSatisfy { r in
        let a = r.arrangement(around: base)!
        return a.nodes.count == 5 && near(a.nodes[a.base].hex, "#10288C")
    }, "every rule gives five colours and keeps the base as it was")
    check(LabRule.custom.arrangement(around: base) == nil, "custom has no arrangement")
    check(hues(.analogous) == [330, 345, 0, 15, 30], "analogous: neighbours 15 and 30 degrees either side")
    check(hues(.complementary).prefix(2) == [0, 180], "complementary: the opposite hue")
    check(hues(.splitComplementary).prefix(3) == [0, 150, 210], "split complementary: either side of the opposite")
    check(hues(.triad).prefix(3) == [0, 120, 240], "triad: thirds of a turn")
    check(hues(.square).prefix(4) == [0, 90, 180, 270], "square: quarter turns")
    check(hues(.compound).prefix(4) == [0, 30, 165, 195], "compound: a neighbour and the pair round the opposite")
    check(Set(hues(.shades)) == [0] && Set(hues(.monochromatic)) == [0], "shades and monochromatic stay on one hue")
    check(LabNode(h: 0, s: 1, v: 1).hex == "#FF0000" && LabNode(h: 120, s: 1, v: 1).hex == "#FFFF00" && LabNode(hex: "#0000FF")!.h > 270
          && LabNode(hex: "#0000FF")!.h < 280 && LabNode(h: 200, s: 0, v: 1).hex == "#FFFFFF",
          "the artists\u{2019} wheel: red, then yellow a third of the way round, blue past two thirds, white at the centre")
    func opposite(_ hex: String) -> ColourGroup { colourGroup(LabNode(hex: hex)!.turn(180).hex) }
    check(opposite("#FF0000") == .greens && opposite("#FFFF00") == .purples && [.oranges, .yellows].contains(opposite("#0000FF")),
          "opposites are the painters\u{2019} pairs: red and green, yellow and violet, blue and orange")
    check((0..<360).allSatisfy { abs(wheelAngle(ofHue: screenHue(atWheel: Double($0))) - Double($0)) < 1e-9 },
          "wheel angle and screen hue convert back and forth exactly")
    check(LabNode(h: 50, s: 0.8, v: 0).hex == "#000000", "brightness runs down to black")
    let companions = LabRule.splitComplementary.arrangement(around: LabNode(hex: "#0000FF")!)!.nodes
    check(companions[1].s == 1 && companions[1].v == 1 && companions[2].s == 1 && companions[2].v == 1,
          "a base on the rim gets companions on the rim: \(companions.prefix(3).map { $0.hex })")
    let shades = LabRule.shades.arrangement(around: LabNode(h: 264, s: 0.9, v: 0.6))!.nodes
    check(Set(shades.map { $0.hex }).count == 5 && Set(shades.map { $0.s }).count == 1 && shades.map({ $0.v }) == [0.6, 1.0, 0.82, 0.46, 0.28],
          "shades are one colour at five brightnesses, the base among them")

    print("the wheel in use")
    var state = LabState(rule: .triad, base: base)
    check(state.nodes.count == 5 && state.base == 0 && near(state.hexes[0], "#10288C"), "a new wheel is arranged by its rule")
    state.move(0, h: base.h + 40, s: 0.5)
    check(abs(state.nodes[1].h - LabNode(h: base.h + 160, s: 0, v: 0).h) < 1e-6 && abs(state.nodes[1].s - 0.5) < 1e-9,
          "dragging the base carries the rest round with it")
    let before = state.nodes[0].h
    state.move(1, h: state.nodes[1].h + 10, s: state.nodes[1].s)
    check(abs(state.nodes[0].h - LabNode(h: before + 10, s: 0, v: 0).h) < 1e-6, "dragging any other colour turns the whole arrangement")
    state.toggleLock(2)
    let held = state.nodes[2]
    state.move(0, h: 200, s: 0.9)
    check(state.nodes[2] == held, "a locked colour stays put while the others move")
    var seed = 0.0
    state.randomise { seed += 0.137; return seed.truncatingRemainder(dividingBy: 1) }
    check(state.nodes[2] == held && state.rule == .triad, "a locked colour survives a random roll")
    state.setRule(.custom)
    let others = state.nodes
    state.move(4, h: 10, s: 0.3)
    check(state.nodes.prefix(4) == others.prefix(4) && abs(state.nodes[4].h - 10) < 1e-9, "under custom a colour moves alone")
    state.remove(0)
    check(state.nodes.count == 4 && state.base == 0, "removing the base hands the role to the first colour")
    state.add()
    check(state.nodes.count == 5 && state.rule == .custom, "a colour can be added back")
    for _ in 0..<10 { state.add() }
    check(state.nodes.count == LabState.most, "the strip stops at \(LabState.most) colours")
    state.makeBase(3)
    check(state.base == 3, "any colour can be made the base")
    state.setRule(.square)
    check(state.nodes.count == 5 && state.base == 0, "choosing a rule rebuilds five colours round the base")
    let saved = try? JSONDecoder().decode(LabState.self, from: JSONEncoder().encode(state))
    check(saved == state, "the wheel survives being saved and read back")

    print("undo and redo")
    var history = LabHistory()
    let a = LabState(rule: .triad, base: base), b = LabState(rule: .square, base: base)
    history.record(a, now: a)
    check(!history.canUndo, "a change that changed nothing is not remembered")
    history.record(a, now: b)
    let undone = history.undo(from: b)
    check(undone == a && history.canRedo && !history.canUndo, "undo goes back one step")
    check(history.redo(from: a) == b && history.canUndo && !history.canRedo, "redo comes forward again")
    history.record(b, now: a)
    check(!history.canRedo, "a new change clears what could be redone")
}

func runNameTests(check: (Bool, String) -> Void) {
    print("colour names")
    check(colourName("#000000") == "Black" && colourName("#FFFFFF") == "White" && colourName("#FF0000") == "Red"
          && colourName("#0000FF") == "Blue" && colourName("#FFFF00") == "Yellow",
          "the plain colours are called what they are")
    check(colourName("#152229") != "Black" && colourName("#390015") != "Black" && colourName("#152229") != colourName("#390015"),
          "a dark blue-grey and a dark maroon are not both called Black: \(colourName("#152229")), \(colourName("#390015"))")
    check(Set(["#434C6A", "#283855", "#334949"].map(colourName)).count == 3, "different dark slates get different names")
    check(colourName("#2F4F4F") == "Dark Slate Grey" && colourName("#FA8072") == "Salmon", "a colour that is exactly a web colour keeps its web name")
    check(allNamedColours.count > 1600 && allNamedColours.allSatisfy { normaliseHex($0.hex) == $0.hex && !$0.name.isEmpty && !$0.name.contains("Gray") },
          "the name table is large, valid, and spelt the British way")
}

func runSwatchNameTests(check: (Bool, String) -> Void) {
    print("a colour's own name in a palette")
    let t = Date(timeIntervalSince1970: 1_800_000_000)
    var lib = Library()
    lib.addPick("#F55805", at: t)
    let brand = lib.createSwatch(named: "Brand", hexes: ["#F55805"], at: t)
    let web = lib.createSwatch(named: "Web", hexes: ["#F55805"], at: t)
    let standard = colourName("#F55805")
    lib.setName("  Brand Orange ", of: "#F55805", in: brand, at: t.addingTimeInterval(1))
    check(lib.name(of: "#F55805", in: brand) == "Brand Orange" && lib.name(of: "#F55805", in: web) == standard && lib.name(of: "#F55805", in: nil) == standard,
          "a colour renamed in one palette keeps its standard name everywhere else")
    check(lib.exportPalette(brand, by: .oldest)?.colours.first?.name == "Brand Orange" && lib.exportPalette(web, by: .oldest)?.colours.first?.name == standard,
          "a palette exports its colours under the names it gives them")
    var other = lib
    other.setName("Sunset", of: "#F55805", in: brand, at: t.addingTimeInterval(5))
    check(mergeLibraries(local: lib, remote: other).name(of: "#F55805", in: brand) == "Sunset"
          && mergeLibraries(local: other, remote: lib).name(of: "#F55805", in: brand) == "Sunset", "the newer name wins a sync")
    lib.setName("", of: "#F55805", in: brand, at: t.addingTimeInterval(10))
    check(lib.customName(of: "#F55805", in: brand) == nil && lib.name(of: "#F55805", in: brand) == standard, "a blank name puts the standard name back")
    check(mergeLibraries(local: lib, remote: other).customName(of: "#F55805", in: brand) == nil, "resetting a name is kept by a sync")
    lib.setName(standard, of: "#F55805", in: web, at: t.addingTimeInterval(11))
    check(lib.customName(of: "#F55805", in: web) == nil, "typing the standard name is not a rename")

    print("a colour's description in a palette")
    var noted = Library()
    noted.addPick("#F55805", at: t)
    let client = noted.createProject(named: "Client", at: t)
    let np = noted.createSwatch(named: "Brand", hexes: ["#F55805"], at: t)
    noted.move(np, to: client, index: 0, at: t)
    let nweb = noted.createSwatch(named: "Web", hexes: ["#F55805"], at: t)
    var steps = StepHistory()
    steps.record("Opened", library: noted, before: nil, limit: 0, at: t)
    var notedBefore = noted
    noted.setNote("  The call to action. Warm, never red. ", of: "#F55805", in: np, at: t.addingTimeInterval(1))
    steps.record("Describe Colour", library: noted, before: notedBefore, limit: 0, at: t.addingTimeInterval(1))
    check(noted.note(of: "#F55805", in: np) == "The call to action. Warm, never red." && noted.note(of: "#F55805", in: nweb) == nil,
          "a colour described in one palette has no description in another")
    let notedStore = LibraryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("colorgain-noted-\(UUID().uuidString)"), legacyURL: nil, name: "Noted")
    try! notedStore.save(noted)
    check((try? notedStore.load())?.swatch(np)?.entries.first?.note == "The call to action. Warm, never red.", "the description travels in the palette's file")
    try? FileManager.default.removeItem(at: notedStore.root)
    var elsewhere = noted
    elsewhere.setNote("Buttons only.", of: "#F55805", in: np, at: t.addingTimeInterval(5))
    check(mergeLibraries(local: noted, remote: elsewhere).note(of: "#F55805", in: np) == "Buttons only."
          && mergeLibraries(local: elsewhere, remote: noted).note(of: "#F55805", in: np) == "Buttons only.", "the newer description wins a sync")
    notedBefore = noted
    noted.setName("Brand Orange", of: "#F55805", in: np, at: t.addingTimeInterval(6))
    steps.record("Rename Colour", library: noted, before: notedBefore, limit: 0, at: t.addingTimeInterval(6))
    notedBefore = noted
    noted.setNote("", of: "#F55805", in: np, at: t.addingTimeInterval(10))
    steps.record("Describe Colour", library: noted, before: notedBefore, limit: 0, at: t.addingTimeInterval(10))
    check(noted.note(of: "#F55805", in: np) == nil && mergeLibraries(local: noted, remote: elsewhere).note(of: "#F55805", in: np) == nil,
          "a blank description removes it, and a sync keeps it removed")
    notedBefore = noted
    noted.remove(["#F55805"], fromSwatch: np, at: t.addingTimeInterval(11))
    steps.record("Remove Colours", library: noted, before: notedBefore, limit: 0, at: t.addingTimeInterval(11))
    let told = steps.steps(changing: "#F55805", in: np)
    check(told.map { $0.what } == ["Description Written", "Renamed \u{201C}Brand Orange\u{201D}", "Description Removed", "Removed"]
          && told.last?.entry == nil && told[1].entry?.name == "Brand Orange",
          "a colour's own history lists what happened to it in a palette, in order, with how it stood after each step")
    check(steps.steps(changing: "#F55805", in: nweb).isEmpty, "and says nothing for a palette where nothing happened to it")


    print("what the project form remembers")
    var memory = FormMemory()
    memory.remember(["clientCompany": " ACME Company ", "clientContact": "Wile E.", "clientEmail": "wile@acme.com", "status": "Active", "ownerCompany": "MMFFDev", "notes": ""], at: t)
    check(memory.remembered(for: .clientCompany) == ["ACME Company"] && memory.remembered(for: .clientEmail) == ["wile@acme.com"]
          && memory.remembered(for: .status).isEmpty && memory.remembered(for: .notes).isEmpty,
          "each field typed into is remembered under that field; a fixed choice and a blank are not")
    check(memory.records(for: .client).map { $0.name } == ["ACME Company"] && memory.records(for: .client).first?.values == ["clientCompany": "ACME Company", "clientContact": "Wile E.", "clientEmail": "wile@acme.com"]
          && memory.records(for: .studio).map { $0.name } == ["MMFFDev"] && memory.records(for: .project).isEmpty,
          "each section is kept whole under its leading field's value; the job's own section is not kept")
    let acme = memory.records(for: .client)[0].id
    memory.remember(["clientCompany": "ACME Company 2", "clientContact": "Road Runner"], at: t.addingTimeInterval(1))
    memory.remember(["clientCompany": "acme company", "clientContact": "Wile E. Coyote", "clientPhone": "555"], at: t.addingTimeInterval(2))
    check(memory.records(for: .client).map { $0.name } == ["acme company", "ACME Company 2"] && memory.records(for: .client)[0].id == acme
          && memory.records(for: .client)[0].values["clientPhone"] == "555" && memory.records(for: .client)[0].values["clientEmail"] == nil
          && memory.records(for: .client)[0].savedAt == t.addingTimeInterval(2),
          "a section saved again under the same name replaces what was kept and keeps its id; another name is another record")
    check(memory.remembered(for: .clientCompany) == ["acme company", "ACME Company 2", "ACME Company"] && memory.remembered(for: .clientContact).first == "Wile E. Coyote",
          "a field lists its values newest first")
    let filled = memory.filling(["clientCompany": "Old", "clientEmail": "old@old.com", "ownerCompany": "MMFFDev", "description": "Job"], with: memory.records(for: .client)[1], in: .client)
    check(filled["clientCompany"] == "ACME Company 2" && filled["clientContact"] == "Road Runner" && filled["clientEmail"] == "" && filled["ownerCompany"] == "MMFFDev" && filled["description"] == "Job",
          "filling a section from a record sets its fields, clears those the record lacks, and leaves the other sections alone")
    memory.forget("ACME Company", for: .clientCompany)
    memory.forget(record: acme, in: .client)
    check(memory.remembered(for: .clientCompany) == ["acme company", "ACME Company 2"] && memory.records(for: .client).map { $0.name } == ["ACME Company 2"],
          "a value and a record can each be forgotten")
    let memoryFolder = FileManager.default.temporaryDirectory.appendingPathComponent("mmffdev-colour3-memory-\(UUID().uuidString)")
    let memoryFile = memoryFolder.appendingPathComponent("form-memory.json")
    try? FormMemoryStore.save(memory, to: memoryFile)
    defer { try? FileManager.default.removeItem(at: memoryFolder) }
    check(FormMemoryStore.load(from: memoryFile) == memory && FormMemoryStore.load(from: memoryFolder.appendingPathComponent("none.json")) == FormMemory(),
          "the memory reads back from its file as it was written, and a missing file is an empty memory")

    check(ProjectField.fields(in: .studio).map { $0.title } == ["Studio", "Department", "Project owner", "Contact name", "Job title", "Email", "Phone", "Extension",
                                                                 "Mobile number", "Website", "Address line 1", "Address line 2", "Town / city", "County / state", "Postcode", "Country", "Company number", "VAT / tax number"]
          && ProjectField.tidy(["ownerDepartment": " Design ", "ownerMobile": "07", "nonsense": "x"]) == ["ownerDepartment": "Design", "ownerMobile": "07"],
          "the Studio section holds the organisation's fields in order, and the new ones are kept like the rest")

    print("the colour engine: masters, renderings and proofs")
    func near(_ a: Double, _ b: Double, _ slack: Double = 0.0005) -> Bool { abs(a - b) <= slack }
    func close(_ p: XYZ, _ x: Double, _ y: Double, _ z: Double, _ slack: Double = 0.0005) -> Bool { near(p.x, x, slack) && near(p.y, y, slack) && near(p.z, z, slack) }
    let redMaster = RGBSpace.srgb.master(of: [1, 0, 0]), whiteMaster = RGBSpace.srgb.master(of: [1, 1, 1])
    check(close(redMaster, 0.4360747, 0.2225045, 0.0139322) && close(whiteMaster, XYZ.d50.x, XYZ.d50.y, XYZ.d50.z),
          "sRGB red and white give the published D50 masters")
    check(close(RGBSpace.displayP3.master(of: [1, 0, 0]), 0.5151, 0.2412, -0.0011) && RGBSpace.allCases.allSatisfy { close($0.master(of: [1, 1, 1]), XYZ.d50.x, XYZ.d50.y, XYZ.d50.z, 0.001) },
          "Display P3 red matches the system engine's figure, and every space's white is the one D50 white")
    check(RGBSpace.allCases.allSatisfy { space in
        let given = [0.92, 0.2, 0.14], back = space.values(of: space.master(of: given))
        return zip(given, back).allSatisfy { near($0, $1, 1e-9) }
    }, "a colour goes to its master and back in every space without loss")
    let someLab = LabD50(l: 52.1, a: 68.3, b: 47.9)
    check(near(whiteMaster.lab.l, 100, 0.01) && near(whiteMaster.lab.a, 0, 0.01) && near(whiteMaster.lab.b, 0, 0.01)
          && near(someLab.xyz.lab.l, 52.1, 1e-9) && near(someLab.xyz.lab.a, 68.3, 1e-9) && near(someLab.xyz.lab.b, 47.9, 1e-9),
          "white is L 100 with no colour, and Lab converts to the master and back exactly")
    // Published CIEDE2000 check pairs (Sharma, Wu and Dalal).
    check(near(deltaE2000(LabD50(l: 50, a: 2.6772, b: -79.7751), LabD50(l: 50, a: 0, b: -82.7485)), 2.0425, 0.0001)
          && near(deltaE2000(LabD50(l: 50, a: 3.1571, b: -77.2803), LabD50(l: 50, a: 0, b: -82.7485)), 2.8615, 0.0001)
          && near(deltaE2000(LabD50(l: 50, a: 2.8361, b: -74.0200), LabD50(l: 50, a: 0, b: -82.7485)), 3.4412, 0.0001)
          && deltaE2000(someLab, someLab) == 0
          // The house's other methods: CIE76 is the plain distance; CIE94 and CMC from a grey reference are worked by hand
          // (S_C and S_H are 1 for CIE94 at C 0; for CMC at L 50, S_L is 1.0883 and S_C 0.638); the asymmetric ones differ swapped.
          && near(DifferenceMethod.cie76.difference(LabD50(l: 50, a: 0, b: 0), LabD50(l: 53, a: 4, b: 0)), 5, 0.0001)
          && near(DifferenceMethod.cie94.difference(LabD50(l: 50, a: 0, b: 0), LabD50(l: 50, a: 10, b: 0)), 10, 0.0001)
          && near(DifferenceMethod.cie94.difference(LabD50(l: 50, a: 0, b: 0), LabD50(l: 60, a: 0, b: 0)), 10, 0.0001)
          && near(DifferenceMethod.cmc11.difference(LabD50(l: 50, a: 0, b: 0), LabD50(l: 60, a: 0, b: 0)), 10 / 1.08831, 0.001)
          && near(DifferenceMethod.cmc21.difference(LabD50(l: 50, a: 0, b: 0), LabD50(l: 60, a: 0, b: 0)), 5 / 1.08831, 0.001)
          && near(DifferenceMethod.cmc11.difference(LabD50(l: 50, a: 0, b: 0), LabD50(l: 50, a: 0, b: 6.38)), 10, 0.001)
          && DifferenceMethod.cie94.difference(LabD50(l: 50, a: 40, b: 10), LabD50(l: 50, a: 10, b: 10)) != DifferenceMethod.cie94.difference(LabD50(l: 50, a: 10, b: 10), LabD50(l: 50, a: 40, b: 10))
          && DifferenceMethod.cmc21.difference(LabD50(l: 50, a: 40, b: 10), LabD50(l: 50, a: 10, b: 40)) != DifferenceMethod.cmc21.difference(LabD50(l: 50, a: 10, b: 40), LabD50(l: 50, a: 40, b: 10))
          && DifferenceMethod.allCases.allSatisfy { $0.difference(someLab, someLab) == 0 }
          && DifferenceMethod.ciede2000.difference(LabD50(l: 50, a: 2.6772, b: -79.7751), LabD50(l: 50, a: 0, b: -82.7485)) == deltaE2000(LabD50(l: 50, a: 2.6772, b: -79.7751), LabD50(l: 50, a: 0, b: -82.7485)),
          "the colour difference matches the published CIEDE2000 figures, CIE76, CIE94 and CMC match figures worked by hand with the master as the reference, and a colour differs from itself by nothing under every method")
    check(Illuminant.allCases.count == 12 && Illuminant.named("d65-10")?.label == "D65 \u{00B7} 10\u{00B0}" && XYZ.d50.adapted(to: .d50) == XYZ.d50
          && Illuminant.allCases.allSatisfy { ill in
              let w = XYZ.d50.adapted(to: ill), lab = w.lab(under: ill)
              return near(w.x, ill.white.x, 1e-4) && near(w.y, 1, 1e-6) && near(w.z, ill.white.z, 1e-4) && near(lab.l, 100, 1e-6) && abs(lab.a) < 1e-6 && abs(lab.b) < 1e-6
          }
          && someLab.xyz.lab(under: .d50) == someLab.xyz.lab
          && { let d65 = Illuminant.named("d65-2")!, under = someLab.xyz.adapted(to: d65).lab(under: d65)
               return near(under.l, 51.2366, 0.001) && near(under.a, 67.4450, 0.001) && near(under.b, 46.0526, 0.001) }(),
          "the twelve illuminants each carry the D50 white to their own by Bradford and read it as L 100 with no colour, D50 is left as it is, and a red reads under D65 as worked out independently")
    check(ColourSource(space: "srgb", values: [1, 0, 0]).whiteName == "D65 \u{00B7} 2\u{00B0}" && ColourSource(space: "prophoto", values: [1, 0, 0]).whiteName == "D50 \u{00B7} 2\u{00B0}"
          && ColourSource(space: "cmyk", values: [0, 1, 1, 0], press: "Generic CMYK").whiteName == "D50 \u{00B7} 2\u{00B0}" && ColourSource(space: "lab", values: [50, 0, 0]).whiteName == "D50 \u{00B7} 2\u{00B0}"
          && RGBSpace.allCases.allSatisfy { !$0.whiteName.isEmpty },
          "a source names the white its numbers came in under: D65 for sRGB, D50 for ProPhoto, a press build and a typed L*a*b*")
    let steel = ColourDefinition.of(hex: "#4F8093")!
    let steelOnScreen = Rendering.of(steel, in: ProfileChannel(space: "srgb"))
    check(steel.source.space == "srgb" && steel.kind == .surface && steel.sourceText == "sRGB  #4F8093"
          && steelOnScreen.value == "#4F8093   79, 128, 147" && steelOnScreen.inRange && (steelOnScreen.difference ?? 9) < 0.001,
          "a colour known by its hex has the hex as its source, and renders to sRGB as itself")
    let vividRed = ColourDefinition(source: ColourSource(space: "displayP3", values: [1, 0, 0]), master: RGBSpace.displayP3.master(of: [1, 0, 0]), kind: .surface)
    let inSRGB = Rendering.of(vividRed, in: ProfileChannel(space: "srgb")), inP3 = Rendering.of(vividRed, in: ProfileChannel(space: "displayP3"))
    let in2020 = Rendering.of(vividRed, in: ProfileChannel(space: "rec2020"))
    check(!inSRGB.inRange && inSRGB.value == "#FF0000   255, 0, 0" && (inSRGB.difference ?? 0) > Rendering.visible && inP3.inRange && (inP3.difference ?? 9) < 0.001 && in2020.inRange,
          "a Display P3 red is outside sRGB, which shows its nearest red and says how far off it is; P3 and Rec. 2020 hold it")
    // A palette's colour under a key, not a hex, as Palette 139's orange was on 2026-10-09: anything that takes a colour as a hex goes
    // through sRGBHex, which answers the hex the key shows as, so the contrast pickers take it and the pair's maths holds.
    let keyedRed = ColourKeys.make()
    ColourKeys.register(keyedRed, vividRed)
    check(sRGBHex(keyedRed) == "#FF0000" && sRGBHex("#abcdef") == "#ABCDEF" && sRGBHex("c:nobody") == nil && displayHex("c:nobody") == "c:nobody"
          && ContrastPair(ink: sRGBHex(keyedRed)!, paper: "#FFFFFF").ratio == contrastRatio(keyedRed, "#FFFFFF"),
          "a colour kept under a key is taken as the sRGB it shows as, a hex as itself, an unknown key not at all; the pair's maths is the same either way")
    let twiceWhite = XYZ(x: XYZ.d50.x * 2, y: 2, z: XYZ.d50.z * 2)
    let bright = Rendering.of(ColourDefinition(source: ColourSource(space: "xyz", values: [twiceWhite.x, 2, twiceWhite.z]), master: twiceWhite, kind: .light), in: ProfileChannel(space: "acescg"))
    let brightOnPaper = Rendering.of(ColourDefinition(source: ColourSource(space: "xyz", values: [twiceWhite.x, 2, twiceWhite.z]), master: twiceWhite, kind: .surface), in: ProfileChannel(space: "srgb"))
    check(bright.inRange && (bright.difference ?? 9) < 0.001 && (bright.value ?? "").hasPrefix("2.0") && !brightOnPaper.inRange && brightOnPaper.value == "#FFFFFF   255, 255, 255",
          "a light twice as bright as white is held whole in a rendering space, and is out of range for a screen")
    let generic = ProfileChannel(space: ProfileChannel.print, press: PressProfiles.generic, intent: .relative)
    let greenInk = Rendering.of(ColourDefinition.of(hex: "#00FF00")!, in: generic), greyInk = Rendering.of(ColourDefinition.of(hex: "#808080")!, in: generic)
    check(PressProfiles.all.contains { $0.name == PressProfiles.generic } && greenInk.value != nil && !greenInk.inRange
          && (greenInk.difference ?? 0) > (greyInk.difference ?? 9) && greenInk.detail.contains("Total Ink") && greenInk.detail.contains("Relative Colorimetric"),
          "a vivid screen green is out of range in print and shifts more than a mid grey; a print value names its intent and total ink")
    let nowhere = Rendering.of(steel, in: ProfileChannel(space: ProfileChannel.print, press: "No Such Press"))
    check(nowhere.value == nil && !nowhere.inRange && nowhere.detail.contains("not on this Mac"), "a press profile that is not on this Mac gives no value and says why")
    if let paper = PrintBuild.master(ofInks: [0, 0, 0, 0], press: PressProfiles.generic), let solid = PrintBuild.master(ofInks: [0, 0, 0, 1], press: PressProfiles.generic) {
        check(close(paper, XYZ.d50.x, XYZ.d50.y, XYZ.d50.z, 0.02) && solid.y < 0.1 && (PrintBuild.of(whiteMaster, press: PressProfiles.generic, intent: .relative)?.totalInk ?? 99) < 1,
              "no ink is paper white, solid black is dark, and white needs no ink")
    } else { check(false, "a build typed in by hand has a master through its press profile") }

    check(RGBSpace.videoCode(0, legal: true) == 64 && RGBSpace.videoCode(1, legal: true) == 940 && RGBSpace.videoCode(0, legal: false) == 0 && RGBSpace.videoCode(1, legal: false) == 1023
          && (Rendering.of(steel, in: ProfileChannel(space: "rec709", legal: true)).value ?? "").hasSuffix("(10-bit, legal range)")
          && (Rendering.of(steel, in: ProfileChannel(space: "rec709")).value ?? "").hasSuffix("(10-bit, full range)"),
          "video black and white read 64 and 940 in legal range, 0 and 1023 in full range, and every video value names its range")
    let blackMaster = XYZ(x: 0, y: 0, z: 0), darkMaster = RGBSpace.srgb.master(of: [0.06, 0.06, 0.06])
    if let plainWhite = PrintBuild.of(whiteMaster, press: PressProfiles.generic, intent: .relative, blackPoint: true),
       let lifted = PrintBuild.of(darkMaster, press: PressProfiles.generic, intent: .relative, blackPoint: true),
       let clipped = PrintBuild.of(darkMaster, press: PressProfiles.generic, intent: .relative),
       let deepest = PrintBuild.of(blackMaster, press: PressProfiles.generic, intent: .relative, blackPoint: true) {
        let level = PressProfiles.blackLevel(of: PressProfiles.generic)
        check(plainWhite.totalInk < 1 && level > 0 && level < 0.2 && lifted.printed.y >= clipped.printed.y && near(deepest.printed.y, level, 0.01),
              "with black point compensation white still takes no ink, black lands on the press's darkest black, and a dark colour is no darker than without it")
    } else { check(false, "black point compensation gives a build") }
    var icc = Data(count: 128)
    func bytes(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
    icc.append(contentsOf: bytes(1) + bytes(0x77747074) + bytes(144) + bytes(20) + bytes(0x58595A20) + bytes(0) + bytes(UInt32(0.90 * 65536)) + bytes(UInt32(0.95 * 65536)) + bytes(UInt32(0.80 * 65536)))
    let readWhite = PressProfiles.mediaWhite(inProfile: icc)
    check(readWhite.map { near($0.x, 0.90, 0.0001) && near($0.y, 0.95, 0.0001) && near($0.z, 0.80, 0.0001) } == true && PressProfiles.mediaWhite(inProfile: Data(count: 60)) == nil,
          "the paper white is read from a press profile's own data, and data that is no profile gives none")
    let paper2 = PressProfiles.paperWhite(of: PressProfiles.generic)
    if let onPaper = PrintBuild.of(whiteMaster, press: PressProfiles.generic, intent: .absolute), let against = PrintBuild.of(whiteMaster, press: PressProfiles.generic, intent: .relative) {
        check(paper2.y > 0.5 && paper2.y <= 1.01 && onPaper.totalInk < 1 && close(onPaper.printed, against.printed.x * paper2.x / XYZ.d50.x, against.printed.y * paper2.y / XYZ.d50.y, against.printed.z * paper2.z / XYZ.d50.z, 0.001)
              && PressProfiles.paperWhite(of: "No Such Press") == XYZ.d50,
              "an absolute proof shows white as the paper itself, with no ink; a profile that is not here is taken as a perfect white")
    } else { check(false, "an absolute colorimetric proof gives a build") }
    let typedBuild = ColourDefinition(source: ColourSource(space: "cmyk", values: [0, 0.9, 0.85, 0], press: PressProfiles.generic),
                                      master: PrintBuild.master(ofInks: [0, 0.9, 0.85, 0], press: PressProfiles.generic) ?? XYZ.d50, kind: .surface)
    let asGiven = Rendering.of(typedBuild, in: generic), otherPress = Rendering.of(typedBuild, in: ProfileChannel(space: ProfileChannel.print, press: "No Such Press"))
    check(asGiven.value == "C 0  M 90  Y 85  K 0" && asGiven.difference == 0 && asGiven.inRange && asGiven.detail.hasPrefix("As Given") && asGiven.detail.contains("Total Ink 175%") && otherPress.value == nil,
          "a build typed for a press is delivered to that press exactly as given, with its total ink")
    check(RenderingIntent.allCases.map { $0.name } == ["Relative Colorimetric", "Absolute Colorimetric", "Perceptual"]
          && Rendering.of(steel, in: ProfileChannel(space: ProfileChannel.print, press: PressProfiles.generic, intent: .relative, blackPoint: true)).detail.contains("Black Point Compensation"),
          "three rendering intents are on offer, and a print value says when black point compensation is on")

    print("colour identity: a colour is more than its hex")
    var wideLib = Library()
    let vivid = ColourDefinition.displayP3([1, 0, 0]), plainRGB = ColourDefinition.of(hex: "#4F8093")!
    let vividKey = wideLib.addColour(vivid, at: t) ?? "", plainKey = wideLib.addColour(plainRGB, at: t) ?? ""
    check(ColourKeys.isKey(vividKey) && plainKey == "#4F8093" && wideLib.addColour(vivid, at: t) == vividKey && wideLib.colours.count == 2 && !vivid.fitsSRGB && plainRGB.fitsSRGB,
          "a colour sRGB cannot hold gets a key of its own, a plain sRGB colour keeps its hex, and the same colour twice is one colour")
    check(wideLib.definition(of: vividKey) == vivid && displayHex(vividKey) == "#FF0000" && colourKey(vividKey) == vividKey && colourKey("c:nothing") == nil && colourKey("4f8093") == "#4F8093"
          && ColourKeys.label(vividKey) == "P3 " + RGBSpace.displayP3.text([1, 0, 0]) && ColourKeys.label("#4F8093") == "#4F8093",
          "the key gives back the whole definition, shows as its nearest sRGB, and is labelled by its source: \(ColourKeys.label(vividKey))")
    check(ColourFormat.p3.fields(vividKey) == ["255", "0", "0"] && ColourFormat.p3.fields("#FF0000") != ["255", "0", "0"] && ColourFormat.rgb.fields(vividKey) == ["255", "0", "0"]
          && ColourValues(vividKey)?.hex == "#FF0000" && colorFromHex(vividKey)?.colorSpace == .displayP3,
          "its Display P3 values are its own, not those of the sRGB red it shows as, and it is drawn in Display P3")
    let widePalette = wideLib.createSwatch(named: "Wide", hexes: [vividKey, plainKey], at: t)
    check(wideLib.hexes(inSwatch: widePalette, by: .oldest) == [vividKey, plainKey], "a palette holds a colour with a key of its own beside plain ones")
    let wideCopy = wideLib.copyPalette(widePalette, to: nil, withNotes: false, at: t.addingTimeInterval(1))
    check(wideCopy.map { wideLib.hexes(inSwatch: $0, by: .oldest) } == [vividKey, plainKey], "and a copy of the palette holds the same colour")
    let wideCoder = JSONEncoder(), wideDecoder = JSONDecoder()
    wideCoder.dateEncodingStrategy = .millisecondsSince1970; wideDecoder.dateDecodingStrategy = .millisecondsSince1970
    let wideBack = (try? wideCoder.encode(wideLib)).flatMap { try? wideDecoder.decode(Library.self, from: $0) }
    check(wideBack?.definition(of: vividKey) == vivid && wideBack?.colours.first { $0.hex == plainKey }?.source == nil && wideBack?.hexes(inSwatch: widePalette, by: .oldest) == [vividKey, plainKey],
          "saved and read back, the colour keeps its source and master; a plain colour's record is as it always was")
    var otherMac = Library()
    otherMac.addPick("#111111", at: t)
    let wideMerged = mergeLibraries(local: otherMac, remote: wideLib)
    check(wideMerged.definition(of: vividKey) == vivid && wideMerged.hexes(inSwatch: widePalette, by: .oldest) == [vividKey, plainKey] && mergeLibraries(local: wideLib, remote: otherMac).definition(of: vividKey) == vivid,
          "a sync carries the colour whole, whichever side has it")
    let widePack = wideLib.designPack(named: "Wide", palettes: [widePalette], owner: "", licence: "", at: t, house: ColourProfiles.starters, houseDefault: nil).projects[0].palettes[0]
    check(widePack.swatches.map { $0.hex } == ["#FF0000", "#4F8093"] && widePack.swatches.allSatisfy { $0.cmyk?.count == 4 } && widePack.press == "Generic CMYK, Relative Colorimetric"
          && widePack.export.colours.first?.hex == "#FF0000",
          "an export that only knows sRGB gets the colour as sRGB shows it, with a build for the palette's press, named")
    if let typed = ColourDefinition.cmyk([0, 0.9, 0.85, 0], press: PressProfiles.generic), let typedKey = wideLib.addColour(typed, at: t) {
        check(ColourKeys.isKey(typedKey) && ColourFormat.cmyk.text(typedKey) == "0, 90, 85, 0" && ColourKeys.label(typedKey) == "C 0  M 90  Y 85  K 0" && typed.source.press == PressProfiles.generic,
              "a build typed for a press is a colour in its own right, and its CMYK for that press is the build as typed")
    } else { check(false, "a typed build becomes a colour") }
    let typedLab = ColourDefinition.lab(52, 60, 40)
    check(near(typedLab.master.lab.l, 52, 0.001) && near(typedLab.master.lab.a, 60, 0.001) && ColourDefinition.cmyk([0, 0, 0, 0], press: "No Such Press") == nil
          && wideLib.addColour(typedLab, at: t).map { ColourFormat.lab.fields($0) } == ["52.0", "60.0", "40.0"],
          "a colour given as Lab keeps those very values; a build for a press that is not here is refused")
    let plainPick = ColourDefinition.picked(NSColor(srgbRed: 79.0 / 255, green: 128.0 / 255, blue: 147.0 / 255, alpha: 1))
    let plainPickKey = plainPick.flatMap { wideLib.addColour($0, at: t) }
    check(ColourDefinition.picked(NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1))?.source.space == RGBSpace.displayP3.rawValue
          && plainPick?.source.space == RGBSpace.displayP3.rawValue && plainPickKey == "#4F8093"
          && wideLib.colours.first { $0.hex == "#4F8093" }?.source?.space == RGBSpace.displayP3.rawValue,
          "a pick is kept whole as the Display P3 the screen showed; one sRGB can hold is keyed by its hex, as ever, with its exact values on the record")
    check(vivid.master.display.colorSpace == .displayP3 && near(Double(vivid.master.display.redComponent), 1, 0.001) && near(Double(vivid.master.display.greenComponent), 0, 0.001)
          && vivid.master.fits(.displayP3) && !vivid.master.fits(.srgb) && !RGBSpace.rec2020.master(of: [0, 1, 0]).fits(.displayP3) && plainRGB.master.shows(on: nil) && !vivid.master.shows(on: nil),
          "a proof chip is painted in Display P3, so a colour beyond sRGB is not flattened; a colour beyond the screen is known to be so")
    let readP3 = NewColourSheet.read(.p3, ["255", "0", "0", ""], press: PressProfiles.generic), readInks = NewColourSheet.read(.cmyk, ["0", "90%", "85", "0"], press: PressProfiles.generic)
    check(readP3.colour == vivid && readInks.colour?.source.values == [0, 0.9, 0.85, 0] && NewColourSheet.read(.lab, ["52", "\u{2212}60", "40"], press: "").colour == ColourDefinition.lab(52, -60, 40)
          && NewColourSheet.read(.hex, ["4f8093"], press: "").colour == plainRGB,
          "New Colour reads Display P3, a build, Lab and a hex as typed")
    check(NewColourSheet.read(.p3, ["256", "0", "0"], press: "").colour == nil && NewColourSheet.read(.cmyk, ["", "", "", ""], press: PressProfiles.generic).problem == "Type at least one value."
          && NewColourSheet.read(.p3, ["255", "", ""], press: "").colour == vivid && NewColourSheet.read(.p3, ["255", "x", ""], press: "").problem == "Each value is a number."
          && NewColourSheet.read(.cmyk, ["0", "0", "0", "0"], press: "No Such Press").problem.contains("not on this Mac") && NewColourSheet.read(.hex, ["nope"], press: "").colour == nil,
          "and says what is wrong with a value out of range, a gap, a press that is not here, or a bad hex")
    print("palette groups and filters")
    var mixed = Library()
    let mixedKeys = ["#FF0000", "#808080", "#0000FF", "#F2F2FF"].compactMap { mixed.addColour(ColourDefinition.of(hex: $0)!, at: t) }
        + [mixed.addColour(vivid, at: t), ColourDefinition.cmyk([0.56, 0, 0, 0], press: PressProfiles.generic).flatMap { mixed.addColour($0, at: t) }, mixed.addColour(ColourDefinition.lab(52, 60, 40), at: t)].compactMap { $0 }
    let screenOnly = ColourProfiles.starters[0], withPrint = ColourProfiles.starters[1]
    let bySource = mixed.groups(of: mixedKeys, by: .source, profile: screenOnly)
    check(mixedKeys.count == 7 && bySource.map { $0.title } == ["Hex (sRGB)", "Display P3", "CMYK: Generic CMYK", "Lab"] && bySource.map { $0.keys.count } == [4, 1, 1, 1]
          && bySource[0].keys == Array(mixedKeys.prefix(4)) && bySource.flatMap { $0.keys }.sorted() == mixedKeys.sorted(),
          "grouped by how they were captured: hex, Display P3, each press, Lab, every colour once and in its own order")
    check(mixed.groups(of: mixedKeys, by: .none, profile: screenOnly).isEmpty && mixed.groups(of: [], by: .hue, profile: screenOnly).isEmpty,
          "grouping by nothing, or an empty page, gives no groups")
    let byHue = mixed.groups(of: Array(mixedKeys.prefix(4)), by: .hue, profile: screenOnly), byLight = mixed.groups(of: Array(mixedKeys.prefix(4)), by: .lightness, profile: screenOnly)
    check(byHue.map { $0.title } == ["Reds", "Blues", "Neutrals"] && byHue[2].keys == ["#808080", "#F2F2FF"] && byLight.map { $0.title } == ["Light", "Mid", "Dark"] && byLight[0].keys == ["#F2F2FF"] && byLight[2].keys == ["#0000FF"],
          "by hue in the order of the wheel with greys last; by lightness from light to dark")
    let byRange = mixed.groups(of: ["#808080", "#0000FF"], by: .range, profile: withPrint)
    check(byRange.map { $0.title } == ["In Range In Every Channel", "Out Of Range In At Least One Channel"] && byRange[1].keys == ["#0000FF"] && mixed.inRange("#0000FF", for: screenOnly),
          "by range: a blue no press can print is out of range for a print profile and in range for a screen one")
    mixed.setTags(ofColour: "#FF0000", ["brand"], at: t); mixed.setTags(ofColour: "#0000FF", ["accent", "zed"], at: t)
    check(mixed.groups(of: Array(mixedKeys.prefix(3)), by: .tag, profile: screenOnly).map { $0.title } == ["#accent", "#brand", "Untagged"], "by tag: each colour under its first tag, untagged last")
    check(mixed.shown(mixedKeys, filter: .beyondSRGB, profile: screenOnly) == [mixedKeys[4]] && mixed.shown(mixedKeys, filter: .withinSRGB, profile: screenOnly).count == 6
          && mixed.shown(mixedKeys, filter: .all, profile: screenOnly) == mixedKeys && mixed.shown(["#808080", "#0000FF"], filter: .outOfRange, profile: withPrint) == ["#0000FF"],
          "the filters: everything, what sRGB holds, what it cannot, and what the profile cannot")
    let ownAdds = PaletteSlot.page(mixedKeys, groups: bySource, offersNew: true), oneAdd = PaletteSlot.page(Array(mixedKeys.prefix(4)), groups: byHue, offersNew: true)
    check(bySource.map { $0.start?.kind } == [NewColourSheet.Kind.hex.rawValue, NewColourSheet.Kind.p3.rawValue, NewColourSheet.Kind.cmyk.rawValue, NewColourSheet.Kind.lab.rawValue]
          && bySource[2].start?.press == PressProfiles.generic && ownAdds.counts == [5, 2, 2, 2] && ownAdds.slots[4] == .add(bySource[0].start) && ownAdds.slots.last == .add(bySource[3].start),
          "grouped by how they were captured, every group ends with a blank swatch that starts a colour of its own kind, a build for its own press")
    check(oneAdd.counts == [1, 1, 3] && oneAdd.slots.filter { $0.key == nil } == [.add(nil)] && PaletteSlot.page(mixedKeys, groups: bySource, offersNew: false).slots.count == 7
          && PaletteSlot.page(["#FF0000"], groups: [], offersNew: true).slots == [.colour("#FF0000"), .add(nil)] && PaletteSlot.page([], groups: [], offersNew: true).counts.isEmpty,
          "any other grouping, or none, has one blank swatch at the end; a locked page has none")
    check(GroupHeaderView.text(bySource[0]) == "Hex (sRGB)  \u{00B7}  4", "a group's title carries its count")

    print("histograms")
    PrintCondition.current = PrintCondition.fallback
    let spread = Histogram.counts(of: ["#FF0000", "#FF8000", "#0000FF", "nonsense"], as: .rgb)
    check(spread.count == 3 && spread[0].count == 256 && spread[0][255] == 2 && spread[0][0] == 1 && spread[1][128] == 1 && spread[1][0] == 2 && spread[2][255] == 1 && spread.map { $0.reduce(0, +) } == [3, 3, 3],
          "a palette's histogram counts every colour once in each channel, at its value, and leaves out what is not a colour")
    let inkSpread = Histogram.counts(of: ["#FFFFFF"], as: .cmyk)
    check(HistogramType.rgb.values(of: "#A3E900") == [163, 233, 0] && HistogramType.cmyk.values(of: "#FFFFFF") == [0, 0, 0, 0] && inkSpread.count == 4 && inkSpread[0].count == 101 && inkSpread.allSatisfy { $0[0] == 1 }
          && HistogramType.rgb.values(of: vividKey) == [255, 0, 0] && HistogramType.cmyk.channels.count == HistogramType.cmyk.colours.count,
          "a swatch's own values are its sRGB bytes or its ink percentages for the press in force")

    check(HistogramType.rgb.warnings(for: [163, 233, 0]) == ["Blue In Black"] && HistogramType.rgb.warnings(for: [255, 128, 16]) == ["Red In White Out"] && HistogramType.rgb.warnings(for: [16, 128, 235]).isEmpty
          && HistogramType.cmyk.warnings(for: [2, 50, 96, 0]) == ["Cyan In White Out", "Yellow In Black"],
          "a channel outside the safe range is named with the zone it is in: black and white out for a screen, dot loss and fill-in for a press")

    check(HistogramType.offered.map { $0.title } == ["RGB", "HSL", "HSV", "CMYK", "P3", "Adobe", "BT.2020", "L*a*b*", "Y\u{2032}CbCr"] && Set(HistogramType.offered) == Set(HistogramType.allCases)
          && HistogramType.allCases.allSatisfy { $0.channels.count == $0.ranges.count && $0.channels.count == $0.colours.count && $0.values(of: "#4F8093")?.count == $0.channels.count },
          "every set of values a card shows has a histogram, in the order of the card's rows")
    let labSpread = Histogram.counts(of: ["#8E00E9"], as: .lab), hueSpread = Histogram.counts(of: ["#4F8093"], as: .hsl)
    check(HistogramType.hsl.values(of: "#4F8093") == [197, 30, 44] && HistogramType.hsv.values(of: "#4F8093") == [197, 46, 58] && HistogramType.lab.values(of: "#8E00E9") == [40, 73, -83]
          && hueSpread[0].count == 361 && hueSpread[0][197] == 1 && labSpread[1].count == 256 && labSpread[1][73 + 128] == 1 && labSpread[2][-83 + 128] == 1,
          "their values are the numbers on the card, counted on each channel's own scale; a* and b* run below nothing")
    check(HistogramType.lab.place(-128, in: 1) == 0 && HistogramType.lab.place(127, in: 2) == 1 && HistogramType.hsl.place(180, in: 0) == 0.5 && HistogramType.rgb.place(999, in: 0) == 1
          && HistogramType.hsl.safe == nil && HistogramType.lab.warnings(for: [0, -128, 127]).isEmpty && HistogramType.p3.warnings(for: [255, 128, 128]) == ["Red In White Out"],
          "each value is placed along its own scale; hue, saturation, lightness and Lab have no unsafe ends, the RGB spaces all do")

    print("analysis")
    let seenRed = ColourVision.protanopia.seen("#FF0000") ?? [], seenGrey = ColourVision.deuteranopia.seen("#808080") ?? []
    check(ColourVision.allCases.count == 5 && seenRed.count == 3 && seenRed[0] < 0.6 && abs(seenRed[0] - seenRed[1]) < 0.25
          && near(seenGrey[0], 128.0 / 255, 0.004) && near(seenGrey[1], 128.0 / 255, 0.004) && near(seenGrey[2], 128.0 / 255, 0.004)
          && ColourVision.allCases.allSatisfy { $0.seen("#FFFFFF")?.allSatisfy { near($0, 1, 0.002) } == true },
          "colour blind simulation: red loses its redness to someone with no red cones, and grey and white stay as they are for everyone")
    check(AnalysisKind.offered(for: 5).map { $0.title } == ["Colour Vision", "Contrast Grid", "Separation", "Gamut Map", "Print Reach", "Tone", "Hue Wheel", "Pairings", "On White, On Black", "Blend", "Bands"]
          && AnalysisKind.offered(for: 1).map { $0.title } == ["Colour Vision", "Gamut Map", "Print Reach", "Tone", "Hue Wheel", "On White, On Black"]
          && near(lightness(of: "#FFFFFF"), 100, 0.01) && near(lightness(of: "#000000"), 0, 0.01) && lightness(of: "#808080") > 50 && lightness(of: vividKey) > 40,
          "a palette has eleven panels, decisions first and looks last; one swatch has the six that mean something for one colour")
    let redGreen = separation("#D03020", "#5A8A20"), blackWhite = separation("#000000", "#FFFFFF"), same = separation("#4F8093", "#4F8093")
    check((redGreen?.seen ?? 0) > 30 && (redGreen?.worst ?? 99) < (redGreen?.seen ?? 0) / 2 && near(blackWhite?.seen ?? 0, 100, 0.5) && near(blackWhite?.worst ?? 0, 100, 0.5)
          && same?.seen == 0 && separation("nonsense", "#FFFFFF") == nil,
          "separation: a red and a green far apart to most eyes are much closer to a colour blind viewer; black and white are far apart for everyone")

    var pickLib = Library()
    let pickPalette = pickLib.createSwatch(named: "Picks", hexes: [], at: t)
    pickLib.activeSwatchID = pickPalette
    let pickedKey = pickLib.addPick(vivid, at: t)
    check(pickedKey.map { pickLib.hexes(inSwatch: pickPalette, by: .oldest) == [$0] } == true, "a wide pick goes into the active palette like any other")

    print("cinema, photo and video signal")
    let p3Red = RGBSpace.displayP3.master(of: [1, 0, 0])
    check(close(RGBSpace.p3D65.master(of: [1, 0, 0]), p3Red.x, p3Red.y, p3Red.z, 0.0005) && close(RGBSpace.dciP3.master(of: [1, 1, 1]), XYZ.d50.x, XYZ.d50.y, XYZ.d50.z, 0.001)
          && !close(RGBSpace.dciP3.master(of: [1, 0, 0]), p3Red.x, p3Red.y, p3Red.z, 0.002) && near(RGBSpace.p3D65.values(of: RGBSpace.displayP3.master(of: [0.5, 0.5, 0.5]))[0], pow(RGBSpace.displayP3.linear(0.5), 1 / 2.6), 0.0005),
          "P3-D65 has Display P3's primaries and white with a 2.6 gamma; DCI-P3 has the projector's own white, so its red is not the same red")
    let proRound = RGBSpace.prophoto.values(of: RGBSpace.prophoto.master(of: [0.2, 0.6, 0.9]))
    check(near(proRound[0], 0.2, 0.0005) && near(proRound[1], 0.6, 0.0005) && near(proRound[2], 0.9, 0.0005) && RGBSpace.rec2020.master(of: [0, 1, 0]).fits(.prophoto) && near(RGBSpace.prophoto.encoded(0.001), 0.016, 0.0001)
          && RGBSpace.prophoto.text([0.5, 0.25, 1]) == "0.5000, 0.2500, 1.0000" && RGBSpace.dciP3.text([1, 0.5, 0]) == "4095, 2048, 0  (12-bit)",
          "ProPhoto goes there and back, holds Rec. 2020's green, has its straight toe near black, and is never written in 8 bits; cinema values are 12-bit")
    check(RGBSpace.rec709.yCbCr([1, 1, 1], legal: true) == [940, 512, 512] && RGBSpace.rec709.yCbCr([0, 0, 0], legal: true) == [64, 512, 512] && RGBSpace.rec709.yCbCr([1, 0, 0], legal: true) == [250, 409, 960]
          && RGBSpace.rec709.yCbCr([0, 0, 1], legal: true)[1] == 960 && RGBSpace.rec709.yCbCr([1, 1, 1], legal: false) == [1023, 512, 512] && RGBSpace.rec2020.yCbCr([1, 0, 0], legal: true)[0] == 294,
          "the video signal: white is 940 with no colour, black 64, and pure red and blue reach 960 in their difference; Rec. 2020 weighs red more heavily")
    let videoRow = Rendering.of(steel, in: ProfileChannel(space: "rec709", legal: true)), cinemaRow = Rendering.of(steel, in: ProfileChannel(space: "dciP3"))
    check(videoRow.detail.hasPrefix("Y\u{2032}CbCr ") && videoRow.detail.hasSuffix("HD video, gamma 2.4") && cinemaRow.inRange && (cinemaRow.value ?? "").hasSuffix("(12-bit)") && near(cinemaRow.difference ?? 9, 0, 0.01)
          && Rendering.of(steel, in: ProfileChannel(space: "prophoto")).inRange && HistogramType.ycbcr.values(of: "#FFFFFF") == [940, 512, 512],
          "a video row carries its signal values; a colour is delivered to cinema and to ProPhoto without loss")
    let proTyped = NewColourSheet.read(.prophoto, ["128", "64.5", "255"], press: "")
    check(proTyped.colour?.source.space == "prophoto" && near(proTyped.colour?.source.values[1] ?? 0, 64.5 / 255, 0.00001) && NewColourSheet.Kind.offered.map { $0.title } == ["Display P3", "ProPhoto", "CMYK", "Lab", "Hex"]
          && proTyped.colour.map { ColourKeys.isKey(Library().addingColour($0)) } == true,
          "New Colour takes ProPhoto values, decimals kept, and the colour has a key of its own")

    print("colour profiles: palette, project, house")
    var studio = Library()
    studio.addPick("#4F8093", at: t)
    let client2 = studio.createProject(named: "Client", at: t)
    let webPalette = studio.createSwatch(named: "Web", hexes: ["#4F8093"], at: t), printPalette = studio.createSwatch(named: "Print", hexes: ["#4F8093"], at: t)
    let stockPalette = studio.createSwatch(named: "Stock", hexes: ["#4F8093"], at: t)
    studio.move(webPalette, to: client2, index: 0, at: t); studio.move(printPalette, to: client2, index: 1, at: t)
    let house = ColourProfiles.starters, screenProfile = house[0], printProfile = house[1], videoProfile = house[2]
    check(house.map { $0.name } == ["Screen And Web", "Print", "Video", "Rendering And Effects", "Every Channel", "Photography", "Cinema And VFX"] && printProfile.print?.press == PressProfiles.generic
          && house[4].channels.count == RGBSpace.allCases.count + 1 && Set(house.map { $0.id }).count == 7,
          "seven profiles to begin with, each with an id of its own; Print carries a press, Every Channel carries them all")
    check(studio.profile(forPalette: webPalette, house: house, houseDefault: nil).profile == screenProfile
          && studio.profile(forPalette: webPalette, house: house, houseDefault: videoProfile.id) == (videoProfile, .house),
          "with nothing chosen a palette uses the house default, or the first profile when there is none")
    studio.setProfile(printProfile, ofProject: client2, at: t.addingTimeInterval(1))
    check(studio.profile(forPalette: webPalette, house: house, houseDefault: videoProfile.id) == (printProfile, .project)
          && studio.profile(forPalette: stockPalette, house: house, houseDefault: videoProfile.id) == (videoProfile, .house) && studio.profileRecord(printProfile.id) == printProfile,
          "a project's profile is used by its palettes and not by a loose one, and the library keeps its own copy")
    studio.setProfile(screenProfile, ofPalette: webPalette, at: t.addingTimeInterval(2))
    check(studio.profile(forPalette: webPalette, house: house, houseDefault: nil) == (screenProfile, .palette)
          && studio.profile(forPalette: printPalette, house: house, houseDefault: nil) == (printProfile, .project),
          "a palette's own profile wins over its project's, so one project can hold a web palette and a print palette")
    check(studio.profile(forPalette: webPalette, house: [], houseDefault: nil).profile == screenProfile, "a library's own copy is enough: the profile is found with no house profiles at all")
    var otherStudio = studio
    otherStudio.setProfile(videoProfile, ofPalette: webPalette, at: t.addingTimeInterval(5))
    let agreed = mergeLibraries(local: studio, remote: otherStudio), agreedBack = mergeLibraries(local: otherStudio, remote: studio)
    check(agreed.swatch(webPalette)?.profile == videoProfile.id && agreedBack.swatch(webPalette)?.profile == videoProfile.id && agreed.project(client2)?.profile == printProfile.id
          && Set(agreed.colourProfiles.map { $0.id }) == Set([screenProfile.id, printProfile.id, videoProfile.id]),
          "the newer choice of profile wins a sync, and the merged library holds every profile either side used")
    studio.setProfile(nil, ofPalette: webPalette, at: t.addingTimeInterval(6))
    check(studio.profile(forPalette: webPalette, house: house, houseDefault: nil).origin == .project, "a palette can give up its own profile and go back to its project's")
    let studioStore = LibraryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("colorgain-studio-\(UUID().uuidString)"), legacyURL: nil, name: "Studio")
    try! studioStore.save(studio)
    check((try? studioStore.load())?.project(client2)?.profile == printProfile.id && (try? studioStore.load())?.colourProfiles.contains { $0.id == printProfile.id } == true,
          "the member's file carries the profile it works to, and the Library's Profiles pool carries the profile itself")
    try? FileManager.default.removeItem(at: studioStore.root)
    let saved2 = try! JSONEncoder.library.encode(studio)
    check((try? JSONDecoder.library.decode(Library.self, from: saved2)) == studio && !String(data: try! JSONEncoder.library.encode(Library()), encoding: .utf8)!.contains("colourProfiles"),
          "a library reads back with its profiles, and one with none says nothing about them")
    let copyOfWeb: UUID = { var l = otherStudio; return l.copyPalette(webPalette, to: nil, withNotes: false, at: t.addingTimeInterval(9)).flatMap { l.swatch($0)?.profile } ?? UUID() }()
    check(copyOfWeb == videoProfile.id, "a copy of a palette keeps the profile the original worked to")
    let profileFolder = FileManager.default.temporaryDirectory.appendingPathComponent("mmffdev-colour3-profiles-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: profileFolder) }
    var mine = house; mine[0].name = "Web Only"; mine[0].channels = [ProfileChannel(space: "srgb")]; mine[0].changedAt = t
    try? ColourProfiles.save(mine, to: profileFolder.appendingPathComponent("colour-profiles.json"))
    check(ColourProfiles.load(from: profileFolder.appendingPathComponent("colour-profiles.json")) == mine && ColourProfiles.load(from: profileFolder.appendingPathComponent("none.json")) == house,
          "the house's profiles read back as written, and a Mac with none saved starts with the five")

    print("a project takes a copy of a palette")
    var shop = Library()
    shop.addPick("#F55805", at: t); shop.addPick("#101010", at: t)
    let stock = shop.createSwatch(named: "Brand", hexes: ["#F55805", "#101010"], at: t)
    shop.setName("Brand Orange", of: "#F55805", in: stock, at: t)
    let alpha = shop.createProject(named: "Alpha", at: t), beta = shop.createProject(named: "Beta", at: t)
    let inAlpha = shop.copyPalette(stock, to: alpha, withNotes: true, at: t.addingTimeInterval(1))!
    check(shop.swatch(stock)?.projectID == nil && shop.swatch(inAlpha)?.projectID == alpha && shop.palettes(in: nil).map { $0.id } == [stock]
          && shop.palettes(in: alpha).map { $0.id } == [inAlpha],
          "taking a palette into a project leaves the original in the Palettes list and puts a copy in the project")
    check(shop.swatch(inAlpha)?.name == "Brand" && shop.swatch(inAlpha)?.entries.map { $0.hex } == ["#F55805", "#101010"]
          && shop.customName(of: "#F55805", in: inAlpha) == "Brand Orange" && shop.swatch(inAlpha)?.copiedFrom == stock,
          "the copy keeps the name, the colours in order and each colour's own name, and records where it came from")
    shop.setNote("The call to action.", of: "#F55805", in: inAlpha, at: t.addingTimeInterval(2))
    check(shop.hasNotes(inAlpha) && !shop.hasNotes(stock) && shop.note(of: "#F55805", in: stock) == nil,
          "notes written in the project stay off the original")
    let clean = shop.copyPalette(inAlpha, to: beta, withNotes: false, at: t.addingTimeInterval(3))!
    let noted2 = shop.copyPalette(inAlpha, to: beta, withNotes: true, at: t.addingTimeInterval(4))!
    check(!shop.hasNotes(clean) && shop.note(of: "#F55805", in: noted2) == "The call to action." && shop.note(of: "#F55805", in: inAlpha) == "The call to action.",
          "a copy to another project takes the notes only when asked, and the first project's notes are untouched")
    shop.setNote("Changed in Beta.", of: "#F55805", in: noted2, at: t.addingTimeInterval(5))
    shop.remove(["#101010"], fromSwatch: inAlpha, at: t.addingTimeInterval(5))
    check(shop.note(of: "#F55805", in: inAlpha) == "The call to action." && shop.swatch(stock)?.entries.count == 2 && shop.swatch(noted2)?.entries.count == 2,
          "the copies are separate from then on: a change in one reaches neither the original nor another copy")
    let back = shop.copyPalette(inAlpha, to: nil, withNotes: false, at: t.addingTimeInterval(6))!
    check(shop.swatch(back)?.projectID == nil && !shop.hasNotes(back) && shop.palettes(in: nil).count == 2, "a project's palette copied back to Palettes arrives without its notes")
    check(mergeLibraries(local: shop, remote: shop).swatch(inAlpha)?.copiedFrom == stock, "where a copy came from survives a sync")
    shop.setNote("Stock note.", of: "#F55805", in: stock, at: t.addingTimeInterval(6))
    let withStockNotes = shop.copyPalette(stock, to: beta, withNotes: true, at: t.addingTimeInterval(7))!
    let withoutStockNotes = shop.copyPalette(stock, to: beta, withNotes: false, at: t.addingTimeInterval(7))!
    check(shop.note(of: "#F55805", in: withStockNotes) == "Stock note." && !shop.hasNotes(withoutStockNotes) && shop.note(of: "#F55805", in: stock) == "Stock note.",
          "a loose palette has notes of its own, and a project's copy takes them or not as asked")
    var lab = Library()
    let delta = lab.createProject(named: "Delta", at: t)
    let kept = lab.createSwatch(named: "From The Lab", hexes: ["#112233", "#445566"], custom: true, at: t)
    let keptCopy = lab.copyPalette(kept, to: delta, withNotes: false, at: t)!
    check(lab.palettes(in: nil).map { $0.id } == [kept] && lab.palettes(in: delta).map { $0.id } == [keptCopy]
          && lab.swatch(keptCopy)?.name == "From The Lab" && lab.swatch(keptCopy)?.custom == true && lab.swatch(keptCopy)?.entries.count == 2,
          "colours saved to a project from a tool are kept in the Palettes collection and copied into the project")
    let pair = shop.createTypography(named: "Type", at: t)
    shop.setStyle(TypeStyle(id: UUID(), name: "Body", ink: "#101010", paper: "#FFFFFF", heading: "H", body: "B", headingFont: nil, bodyFont: nil), in: pair)
    let pairCopy = shop.copyPalette(pair, to: alpha, withNotes: false, at: t.addingTimeInterval(7))!
    check(shop.swatch(pairCopy)?.styles?.map { $0.name } == ["Body"] && shop.swatch(pairCopy)?.styles?.first?.id != shop.swatch(pair)?.styles?.first?.id,
          "a Typography palette is copied with its pairings, each a pairing of its own")

    var plain = Library()
    plain.addPick("#111111", at: t)
    plain.createSwatch(named: "P", hexes: ["#111111"], at: t)
    let saved = String(data: try! JSONEncoder.library.encode(plain), encoding: .utf8)!
    check(saved.components(separatedBy: "\"name\"").count == 2 && !saved.contains("nameChangedAt"),
          "a palette whose colours were never renamed saves as it always did")
}

// ---------- One order per place: each project, Favourites and the Palettes list ----------

func runOrderTests(check: (Bool, String) -> Void) {
    print("an order for each place")
    func at(_ n: Double) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + n) }
    var lib = Library()
    let a = lib.createSwatch(named: "A", hexes: ["#111111"], at: at(1))
    let b = lib.createSwatch(named: "B", hexes: ["#222222"], at: at(2))
    let c = lib.createSwatch(named: "C", hexes: ["#333333"], at: at(3))
    let project = lib.createProject(named: "Client", at: at(4))
    for id in [a, b, c] { lib.move(id, to: project, index: Int.max, at: at(5)); lib.setFavourite(id, true, at: at(6)) }
    func names(_ list: [Swatch]) -> String { list.map { $0.name }.joined() }
    check(names(lib.palettes(in: project)) == "ABC" && names(lib.orderedFavourites) == "ABC" && names(lib.listedPalettes) == "ABC",
          "before anything is arranged, Favourites and the Palettes list follow the project")

    lib.placeFavourites([c, a, b], at: at(10))
    lib.placeInList([b, c, a], at: at(11))
    check(names(lib.orderedFavourites) == "CAB" && names(lib.listedPalettes) == "BCA" && names(lib.palettes(in: project)) == "ABC",
          "Favourites and the Palettes list are each arranged without touching the project")
    lib.move(c, to: project, index: 0, at: at(12))
    check(names(lib.palettes(in: project)) == "CAB" && names(lib.orderedFavourites) == "CAB" && names(lib.listedPalettes) == "BCA",
          "reordering inside the project leaves Favourites and the Palettes list as they were")
    lib.move(a, to: project, index: 0, at: at(13))
    check(names(lib.palettes(in: project)) == "ACB" && names(lib.orderedFavourites) == "CAB", "and again: the project moves, Favourites does not")

    let d = lib.createSwatch(named: "D", hexes: ["#444444"], at: at(14))
    lib.setFavourite(d, true, at: at(15))
    check(names(lib.listedPalettes).hasPrefix("D") && names(lib.orderedFavourites).hasPrefix("D"),
          "a new palette goes to the top of a list that has been arranged")
    let saved = try? JSONDecoder().decode(Library.self, from: JSONEncoder().encode(lib))
    check(saved.map { names($0.orderedFavourites) } == names(lib.orderedFavourites) && saved.map { names($0.listedPalettes) } == names(lib.listedPalettes),
          "both orders survive being saved and read back")

    var other = lib
    other.placeFavourites([b, a, c, d], at: at(20))
    lib.placeInList([a, b, c, d], at: at(21))
    let merged = mergeLibraries(local: lib, remote: other)
    check(names(merged.orderedFavourites) == "BACD" && names(merged.listedPalettes) == "ABCD" && names(merged.palettes(in: project)) == "ACB",
          "a sync keeps the newer arrangement of each place separately")
}

// ---------- cLab: contrast ----------

func runContrastTests(check: (Bool, String) -> Void) {
    print("contrast tool")
    check(ContrastPair.text(4.4999) == "4.4 : 1" && ContrastPair.text(4.5) == "4.5 : 1" && ContrastPair.text(21) == "21.0 : 1",
          "a ratio is cut, not rounded, so a near miss never reads as a pass")
    check(ContrastUse.smallText.aa == 4.5 && ContrastUse.smallText.aaa == 7 && ContrastUse.largeText.aa == 3 && ContrastUse.largeText.aaa == 4.5
          && ContrastUse.graphics.aa == 3 && ContrastUse.graphics.aaa == nil, "the WCAG thresholds for text and graphics")
    check(nearestShade(of: "#767676", against: "#FFFFFF", reaching: 4.5) == "#767676", "a colour that already passes is left alone")
    for target in ContrastTarget.allCases {
        let fixed = nearestShade(of: "#8FB2FF", against: "#FFFFFF", reaching: target.rawValue)
        let hue = fixed.flatMap { ColourValues($0)?.oklch.h } ?? 0
        check(fixed.map { contrastRatio($0, "#FFFFFF") >= target.rawValue } == true && abs(hue - ColourValues("#8FB2FF")!.oklch.h) < 6,
              "a pale blue on white is fixed to \(ContrastPair.text(target.rawValue)) and stays blue: \(fixed ?? "none")")
    }
    let aa = nearestShade(of: "#8FB2FF", against: "#FFFFFF", reaching: 4.5)!, aaa = nearestShade(of: "#8FB2FF", against: "#FFFFFF", reaching: 7)!
    check(contrastRatio(aa, "#FFFFFF") < 4.7 && ColourValues(aaa)!.luminance < ColourValues(aa)!.luminance,
          "the fix goes only as far as it has to, and further for a stricter target")
    let onDark = nearestShade(of: "#444444", against: "#222222", reaching: 4.5)
    check(onDark.map { ColourValues($0)!.luminance > ColourValues("#444444")!.luminance && contrastRatio($0, "#222222") >= 4.5 } == true,
          "on a dark background the fix goes lighter: \(onDark ?? "none")")
    check(nearestShade(of: "#808080", against: "#777777", reaching: 7) == nil, "no shade reaches 7 : 1 against a mid grey, and the fix says so")
    func lc(_ text: String, _ bg: String) -> Double { apcaContrast(text: text, background: bg) }
    check(abs(lc("#000000", "#FFFFFF") - 106.04) < 0.01 && abs(lc("#FFFFFF", "#000000") + 107.88) < 0.01
          && abs(lc("#888888", "#FFFFFF") - 63.06) < 0.01 && abs(lc("#FFFFFF", "#888888") + 68.54) < 0.01,
          "APCA matches its published reference values: \(lc("#000000", "#FFFFFF")), \(lc("#FFFFFF", "#000000")), \(lc("#888888", "#FFFFFF")), \(lc("#FFFFFF", "#888888"))")
    check(lc("#777777", "#777777") == 0 && lc("#FFFFFF", "#FEFEFE") == 0, "no difference, or next to none, scores nothing")
    check(contrastRatio("#FFFFFF", "#E8590C") < 4.5 && abs(lc("#FFFFFF", "#E8590C")) >= 60 && contrastRatio("#000000", "#E8590C") > contrastRatio("#FFFFFF", "#E8590C"),
          "white on a strong orange: WCAG 2 fails it for body text and prefers black, APCA passes it as large text")
    check(APCAUse.best(for: -80) == .body && APCAUse.best(for: 62) == .large && APCAUse.best(for: 45) == .headline && APCAUse.best(for: 30) == nil
          && APCAUse.body.preferred == 90, "an Lc is graded by the most demanding use it is enough for, whichever way round the pair is")
    let lifted = nearestShade(of: "#8FB2FF") { abs(lc($0, "#FFFFFF")) >= 75 }
    check(lifted.map { abs(lc($0, "#FFFFFF")) >= 75 && abs(lc($0, "#FFFFFF")) < 78 } == true, "a fix can aim at an APCA score as well as a ratio: \(lifted ?? "none")")
    let strongest = strongestPair(in: ["#2456F5", "#F5BE24", "#0A216D", "#FFFFFF"])
    check(strongest == ContrastPair(ink: "#0A216D", paper: "#FFFFFF") && strongestPair(in: ["#FFFFFF"]) == nil,
          "the strongest pair in a palette is its two most different colours, the lighter as background")
}

func runTagScopeTests(check: (Bool, String) -> Void) {
    print("project tags stay in their project")
    let t = Date(timeIntervalSince1970: 1_800_000_000)
    var lib = Library()
    for hex in ["#111111", "#222222"] { lib.addPick(hex, at: t) }
    let project = lib.createProject(named: "Client A", at: t)
    let inside = lib.createSwatch(named: "Inside", hexes: ["#111111"], at: t)
    let outside = lib.createSwatch(named: "Outside", hexes: ["#222222"], at: t)
    lib.move(inside, to: project, index: 0, at: t)
    lib.setTag("Client", colour: nil, project: project, at: t)

    lib.setTags(ofPalette: inside, ["Client", "Web"], at: t.addingTimeInterval(1))
    lib.setTags(ofPalette: outside, ["Client", "Web"], at: t.addingTimeInterval(1))
    check(lib.swatch(inside)?.tagList == ["Client", "Web"] && lib.swatch(outside)?.tagList == ["Web"],
          "a palette outside the project cannot take the project's tag; a global tag goes anywhere")
    lib.setTags(ofColour: "#111111", ["Client"], at: t.addingTimeInterval(2))
    lib.setTags(ofColour: "#222222", ["Client", "Print"], at: t.addingTimeInterval(2))
    check(lib.colours.first { $0.hex == "#111111" }?.tags == ["Client"] && lib.colours.first { $0.hex == "#222222" }?.tags == ["Print"],
          "a swatch takes a project tag only if one of its palettes is in that project")
    check(lib.projects(holdingAll: ["#111111"]) == [project] && lib.projects(holdingAll: ["#111111", "#222222"]).isEmpty,
          "a selection is offered only the project tags that suit every swatch in it")
    lib.move(inside, to: nil, index: 0, at: t.addingTimeInterval(3))
    lib.setTags(ofPalette: inside, ["Client", "Web", "New"], at: t.addingTimeInterval(4))
    check(lib.swatch(inside)?.tagList == ["Client", "Web", "New"], "a tag already worn is not stripped when other tags are edited")
}

// ---------- Typography palettes ----------

func runTypographyTests(check: (Bool, String) -> Void) {
    print("typography palettes")
    func at(_ n: Double) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + n) }
    func style(_ ink: String, _ paper: String, name: String = "", font: String? = nil) -> TypeStyle {
        TypeStyle(id: UUID(), name: name, ink: ink, paper: paper, heading: "Hello", body: "Some words.", headingFont: font, bodyFont: nil)
    }
    var lib = Library()
    let picks = lib.createSwatch(named: "Brand", hexes: ["#112233"], at: at(1))
    let first = lib.createTypography(at: at(2)), second = lib.createTypography(at: at(3))
    check(lib.swatch(first)?.name == "Typography 1" && lib.swatch(second)?.name == "Typography 2" && lib.swatch(first)?.isTypography == true
          && lib.swatch(picks)?.isTypography == false, "Typography palettes are named Typography 1, 2, and are told apart from colour palettes")
    check(lib.activeSwatchID == picks, "a Typography palette never becomes the target for picks")

    let a = style("#ffffff", "#1B1B1F"), b = style("#2456F5", "#FFFFFF", font: "No Such Font")
    lib.setStyle(a, in: first, at: at(4))
    lib.setStyle(b, in: first, at: at(5))
    let kept = lib.swatch(first)?.styles ?? []
    check(kept.map { $0.name } == ["Typography Set 1", "Typography Set 2"], "pairings are named Typography Set 1, 2 as they are added")
    check(kept.first?.ink == "#FFFFFF" && lib.swatch(first)?.entries.map { $0.hex } == ["#FFFFFF", "#1B1B1F", "#2456F5"]
          && lib.colours.contains { $0.hex == "#2456F5" }, "a pairing\u{2019}s colours are tidied and join the palette and the library")
    check(kept[1].heading == "Hello" && kept[1].body == "Some words." && kept[1].headingFont == "No Such Font" && kept[1].fonts == ["No Such Font"],
          "a pairing keeps its words and the names of its fonts, installed or not")

    var renamed = kept[0]
    renamed.name = "  Dark Hero  "
    lib.setStyle(renamed, in: first, at: at(6))
    check(lib.swatch(first)?.styles?.map { $0.name } == ["Dark Hero", "Typography Set 2"], "a pairing is renamed in place, and keeps its position")
    lib.setStyle(style("#000000", "#FFFF00"), in: first, at: at(7))
    check(lib.swatch(first)?.styles?.last?.name == "Typography Set 3", "names carry on counting after a rename")
    lib.setStyle(style("#000000", "#FFFFFF"), in: picks, at: at(8))
    check(lib.swatch(picks)?.styles == nil, "a pairing cannot be put into a palette of colours")

    lib.replaceFont("No Such Font", with: "Helvetica", in: first, at: at(9))
    check(lib.swatch(first)?.styles?[1].headingFont == "Helvetica", "a missing font is replaced throughout the palette")
    lib.removeStyle(kept[0].id, from: first, at: at(10))
    check(lib.swatch(first)?.styles?.count == 2 && lib.swatch(first)?.styles?.contains { $0.id == kept[0].id } == false, "a pairing can be deleted")

    let project = lib.createProject(named: "Client", at: at(11))
    lib.move(first, to: project, index: 0, at: at(12))
    lib.setFavourite(first, true, at: at(13))
    check(lib.palettes(in: project).map { $0.id } == [first] && lib.orderedFavourites.map { $0.id } == [first] && lib.listedPalettes.contains { $0.id == first },
          "a Typography palette goes into projects, Favourites and the lists like any other")

    let saved = try? JSONDecoder().decode(Library.self, from: JSONEncoder().encode(lib))
    check(saved == lib, "Typography palettes survive being saved and read back")
    let old = try? JSONDecoder().decode(Swatch.self, from: Data("{\"id\":\"\(UUID().uuidString)\",\"name\":\"Old\",\"createdAt\":0,\"entries\":[]}".utf8))
    check(old != nil && old?.isTypography == false, "a palette saved before Typography existed still reads, as a palette of colours")

    let pack = lib.designPack(named: "Pack", palettes: [first], owner: "", licence: "", at: at(15)).palettes[0]
    check(pack.swatches.map { $0.file } == ["typography-1/swatches/01-typography-set-2-text-\(slug(colourName("#2456F5")))-2456f5.png",
                                            "typography-1/swatches/01-typography-set-2-bg-white-ffffff.png",
                                            "typography-1/swatches/02-typography-set-3-text-black-000000.png",
                                            "typography-1/swatches/02-typography-set-3-bg-yellow-ffff00.png"]
          && pack.swatches.map { $0.name }.prefix(2) == ["Typography Set 2 Text", "Typography Set 2 Background"],
          "a design pack names each file for its pairing and its part, so the two that belong together sit together: \(pack.swatches.map { $0.file })")

    var other = lib
    other.setStyle(style("#FF0000", "#FFFFFF", name: "From The Other Mac"), in: first, at: at(20))
    lib.renameSwatch(first, to: "Headlines", at: at(21))
    let merged = mergeLibraries(local: lib, remote: other)
    check(merged.swatch(first)?.name == "Headlines" && merged.swatch(first)?.styles?.last?.name == "From The Other Mac" && merged.swatch(first)?.styles?.count == 3,
          "a sync keeps the newer pairings and the newer name, each on its own")
}

func runImportTests(check: (Bool, String) -> Void) {
    print("importing palettes from files")
    // CSS the app wrote comes back as it went: one palette per comment group, each colour under its name.
    let brand = ExportPalette(name: "Brand", colours: [ExportColour(name: "Steel Blue", hex: "#4F8093"), ExportColour(name: "Ember", hex: "#B55226")])
    let night = ExportPalette(name: "Night", colours: [ExportColour(name: "Ink", hex: "#1B1B1B")])
    if let css = ExportFormat.css.data([brand, night]) {
        let back = PaletteImport.read(css, fallback: "tokens")
        check(back.map { $0.name } == ["Brand", "Night"], "CSS the app exported reads back as the same palettes")
        check(back.first?.colours == brand.colours, "each CSS variable gives back its colour and its name")
    } else { check(false, "the CSS export renders") }
    if let scss = ExportFormat.scss.data([brand]) {
        check(PaletteImport.read(scss, fallback: "x").first?.colours.map { $0.hex } == ["#4F8093", "#B55226"], "SCSS variables read back too")
    }
    let loose = PaletteImport.variables(in: ":root {\n  --accent: rgb(79, 128, 147);\n  --paper: #FFF;\n  --gap: 4px;\n  --color-ember: rgb(181 82 38 / 50%);\n}", fallback: "site")
    check(loose.count == 1 && loose[0].name == "site", "variables before any comment make one palette named for the file")
    check(loose.first?.colours.map { $0.hex } == ["#4F8093", "#FFFFFF", "#B55226"], "rgb(), #RGB and rgb with alpha read as colours; a length does not")
    check(loose.first?.colours.map { $0.name } == ["Accent", "Paper", "Ember"], "a variable's name is its words, with a color prefix dropped")
    check(PaletteImport.variableName("--swatch-steel-blue") == "Steel Blue" && PaletteImport.variableName("$primary_dark") == "Primary Dark",
          "swatch and $ markers go, and kebab or snake case becomes words")

    // Tokens: the 2025 object value, the older hex string, a description as the name, and a group as a palette.
    let tokens = """
    { "brand": { "steel": { "$type": "color", "$value": { "colorSpace": "srgb", "components": [0.3098, 0.502, 0.5765], "alpha": 1, "hex": "#4f8093" }, "$description": "Steel Blue" },
                 "ember": { "$type": "color", "$value": "#B55226" } },
      "spacing": { "gap": { "$type": "dimension", "$value": "4px" } } }
    """
    let read = PaletteImport.read(Data(tokens.utf8), fallback: "x")
    check(read.map { $0.name } == ["Brand"], "a tokens group with colours is a palette; one without is not")
    check(read.first?.colours == [ExportColour(name: "Ember", hex: "#B55226"), ExportColour(name: "Steel Blue", hex: "#4F8093")],
          "a token's description names it, else its key does; both value forms read")

    // A .colpal the app wrote reads back whole, with the names given in it.
    var lib = Library()
    let id = lib.createSwatch(named: "Brand", hexes: ["#4F8093", "#B55226"])
    lib.setName("Steel Blue", of: "#4F8093", in: id)
    if let data = try? ColourFiles.encoder().encode(CatalogueTree.paletteDocument(lib.swatch(id)!, in: lib, member: nil, file: "Brand")) {
        let own = PaletteImport.read(data, fallback: "x")
        check(own.first?.name == "Brand" && own.first?.colours.first?.name == "Steel Blue" && own.first?.colours.count == 2,
              "a .colpal reads back as its palette, with its names")
    } else { check(false, "the palette document writes") }

    // Merging: a new palette is made; the same again changes nothing; a name clash is numbered; a project keeps it.
    var merged = Library()
    let target = merged.createSwatch(named: "Picks", hexes: ["#000000"])
    let first = merged.merge([ImportedPalette(name: "Brand", colours: brand.colours)], into: nil)
    check(first == ImportOutcome(palettesMade: 1, added: 2, skipped: 0, renamed: 0), "an import into an empty place makes the palette and adds every colour")
    check(merged.activeSwatchID == target, "an import does not redirect picks")
    let again = merged.merge([ImportedPalette(name: "brand", colours: brand.colours)], into: nil)
    check(again == ImportOutcome(palettesMade: 0, added: 0, skipped: 2, renamed: 0), "the same file again, whatever its case, is skipped whole")
    let clash = merged.merge([ImportedPalette(name: "Brand", colours: [ExportColour(name: "Ember", hex: "#C06030")])], into: nil)
    let brandID = merged.palettes(in: nil).first { $0.name == "Brand" }!.id
    check(clash == ImportOutcome(palettesMade: 0, added: 1, skipped: 0, renamed: 1) && merged.name(of: "#C06030", in: brandID) == "Ember 2",
          "a different colour under a taken name comes in as the next number of that name")
    let project = merged.createProject(named: "Acme")
    let into = merged.merge([ImportedPalette(name: "Brand", colours: brand.colours)], into: project)
    check(into.palettesMade == 1 && merged.palettes(in: project).count == 1 && merged.palettes(in: nil).filter { $0.name == "Brand" }.count == 1,
          "an import into a member makes the palette there, not in the stock list of the same name")
}

// ---------- The setup: its steps, its draft and its proof strip ----------

func runSetupTests(check: (Bool, String) -> Void) {
    let steps = SetupAssistant.steps
    check(steps.first == "Welcome" && steps.last == "The Halo" && steps.firstIndex(of: "Ready") == steps.count - 2,
          "the setup opens on the welcome page, makes things at Ready and ends on the halo: \(steps)")
    check(SetupAssistant.reasons.count == steps.count && SetupAssistant.reasons.dropFirst().allSatisfy { !$0.isEmpty },
          "every step after the welcome has its reason for the welcome page's list")

    struct Sample: Codable, Equatable { var step: Int; var name: String; var folder: URL? }
    let suite = "mmffdev-colour3-selftest-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let draft = Sample(step: 3, name: "Studio", folder: URL(fileURLWithPath: "/Volumes/Client/Work"))
    SetupDraft.save(draft, key: "draft", in: defaults)
    check(SetupDraft.load(Sample.self, key: "draft", in: defaults) == draft, "a setup's draft survives being kept and read back, as across a relaunch")
    SetupDraft.clear(key: "draft", in: defaults)
    check(SetupDraft.load(Sample.self, key: "draft", in: defaults) == nil, "a draft is gone once the setup has made things")

    check(Design.steps.count == steps.count && Set(Design.steps.map { $0.name }).count == steps.count,
          "the design has one step colour per setup step, each with its own name")
    check(Design.steps.allSatisfy { contrastRatio($0.hex, "#161616") >= 3 },
          "every step colour carries an ink numeral at three to one or better, the bar for large text: \(Design.steps.map { String(format: "%.1f", contrastRatio($0.hex, "#161616")) })")
    check(Design.font(13, .thin).fontName == "HelveticaNeue-Thin" && Design.font(13, .light).fontName == "HelveticaNeue-Light",
          "Helvetica Neue's thin and light weights are on this Mac")
    check(HaloTrainer.lessons.map { $0.id } == ["turn", "deeper", "confirm"], "the halo trainer teaches its three moves in order; the dial opens itself")
    check(HaloTrainer.progress(["deeper"]) == (1, 3) && HaloTrainer.progress(["turn", "deeper", "confirm", "other"]) == (3, 3),
          "the trainer counts only its own lessons")
    let docs = URL(fileURLWithPath: "/Users/someone/Documents")
    check(DocumentsAccess.inside(docs.appendingPathComponent("Studio/Clients"), documents: docs) && DocumentsAccess.inside(docs, documents: docs)
          && !DocumentsAccess.inside(URL(fileURLWithPath: "/Users/someone/Documents Old/Studio"), documents: docs)
          && !DocumentsAccess.inside(URL(fileURLWithPath: "/Users/someone/Library/Application Support/MMFFDev Colour 3"), documents: docs),
          "a launch counts as needing Documents only for a folder inside it, not one that merely starts with its name")
    check(ThemedButton.readable(on: Brand.master) == .white && ThemedButton.readable(on: NSColor(srgbRed: 0.95, green: 0.66, blue: 0, alpha: 1)) == .black,
          "a lead button's text is white on Blue Ribbon and black on saffron")
}
