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
    check(out1.lastPathComponent == "MMFFDev Colour 3 Export" && out2.lastPathComponent == "MMFFDev Colour 3 Export 2",
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
          && fm.fileExists(atPath: mine.directory(for: "Studio").appendingPathComponent("Studio.colcatalogue").path),
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
    check(Permission.all.map { $0.title } == ["Adobe apps"], "the first-open setup lists each permission once")
    #else
    check(Permission.all.isEmpty, "the Store build has nothing for the user to allow up front")
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

    print("project files")
    var projLib = Library()
    let tp = Date(timeIntervalSince1970: 1_760_000_000)
    let client = projLib.createProject(named: "Client A", at: tp)
    let brandSwatch = projLib.createSwatch(at: tp.addingTimeInterval(0.123))
    projLib.renameSwatch(brandSwatch, to: "Brand")
    projLib.add(["#FF0000", "#0033FF"], toSwatch: brandSwatch, at: tp)
    projLib.move(brandSwatch, to: client, index: 0)
    let looseSwatch = projLib.createSwatch(at: tp.addingTimeInterval(1))
    projLib.add(["#00FF00"], toSwatch: looseSwatch, at: tp)
    let file = ProjectFile(project: projLib.project(client)!, in: projLib)
    check(file.palettes.map { $0.name } == ["Brand"] && file.colours.map { $0.hex }.sorted() == ["#0033FF", "#FF0000"],
          "a project file holds the project's palettes and the colours they use, and nothing from outside it")
    let fileData = try! file.data()
    let back = try! ProjectFile.read(fileData)
    check(back.palettes.map { $0.name } == ["Brand"] && back.project.name == "Client A" && (try? back.data()) == fileData,
          "a project reads back as written, to the millisecond")
    let projRoot = root.appendingPathComponent("projects")
    let libURL = projRoot.appendingPathComponent("Main/library.json")
    var written: [UUID: Data] = [:]
    let firstWrite = try! ProjectFiles.write(projLib, library: libURL, master: nil, written: &written)
    let again = try! ProjectFiles.write(projLib, library: libURL, master: nil, written: &written)
    let expected = projRoot.appendingPathComponent("Main/Projects/Client A/Space/Client A.colspace")
    check(firstWrite.files.map { $0.path } == [expected.path] && firstWrite.firstTime == [client] && again.files.isEmpty
          && (try? ProjectFiles.read(expected).data()) == fileData,
          "a project is a folder named for it, with its file in Config, under a Projects folder beside the library; written only when it changes")
    let brandFile = expected.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Palettes/Brand.colpalette")
    let brandDoc = try? ColourFiles.decoder().decode(PaletteDocument.self, from: Data(contentsOf: brandFile))
    let projectDoc = try? ColourFiles.decoder().decode(ProjectDocument.self, from: Data(contentsOf: expected))
    check(brandDoc?.palette.name == "Brand" && brandDoc?.project == client && brandDoc?.colours.count == 2 && brandDoc?.format == "colour-palette"
          && projectDoc?.palettes == [brandSwatch] && projectDoc?.format == "colour-space"
          && String(data: (try? Data(contentsOf: brandFile)) ?? Data(), encoding: .utf8)?.contains("\"name\" : \"Brand\"") == true,
          "each palette is a file of its own beside the project's, in plain text anyone can read, and the project lists its palettes in order")
    // Purposes: a file beside the palette for each one it serves, there exactly while it serves it.
    var purposeLib = projLib
    var purposeWritten: [UUID: Data] = [:]
    let purposeURL = projRoot.appendingPathComponent("Purposes/library.json")
    purposeLib.setPurpose(.print, on: true, ofPalette: brandSwatch, at: tp)
    purposeLib.setPurpose(.web, on: true, ofPalette: brandSwatch, at: tp)
    _ = try! ProjectFiles.write(purposeLib, library: purposeURL, master: nil, written: &purposeWritten)
    let purposeDir = projRoot.appendingPathComponent("Purposes/Projects/Client A/Channels"), purposePalettes = projRoot.appendingPathComponent("Purposes/Projects/Client A/Palettes")
    let printSide = purposeDir.appendingPathComponent("Brand.colprint"), webSide = purposeDir.appendingPathComponent("Brand.colweb")
    let printDoc = try? ColourFiles.decoder().decode(PurposeDocument.self, from: Data(contentsOf: printSide))
    let wholeBack = try? ProjectFiles.read(projRoot.appendingPathComponent("Purposes/Projects/Client A/Space/Client A.colspace"))
    check(fm.fileExists(atPath: webSide.path) && printDoc?.palette == brandSwatch && printDoc?.settings.purpose == .print && printDoc?.paletteName == "Brand"
          && purposeLib.swatch(brandSwatch)?.purposeList == [.web, .print] && wholeBack?.palettes.first?.purposeList == [.web, .print]
          && (try? wholeBack?.data()) == (try? ProjectFile(project: purposeLib.project(client)!, in: purposeLib).data()),
          "a palette serves a purpose exactly when that purpose's file sits beside it, and the project reads back with its purposes")
    purposeLib.setPurpose(.web, on: false, ofPalette: brandSwatch, at: tp.addingTimeInterval(5))
    _ = purposeLib.renameSwatch(brandSwatch, to: "Brand: 2026?")
    _ = try! ProjectFiles.write(purposeLib, library: purposeURL, master: nil, written: &purposeWritten)
    check(!fm.fileExists(atPath: webSide.path) && !fm.fileExists(atPath: printSide.path) && fm.fileExists(atPath: purposeDir.appendingPathComponent("Brand- 2026-.colprint").path)
          && fm.fileExists(atPath: purposePalettes.appendingPathComponent("Brand- 2026-.colpalette").path) && (try? fm.contentsOfDirectory(atPath: purposeDir.path))?.count == 1
          && (try? fm.contentsOfDirectory(atPath: purposePalettes.path))?.count == 1
          && purposeLib.swatch(brandSwatch)?.purposeList == [.print] && purposeLib.swatch(brandSwatch)?.purposes?.count == 2,
          "a purpose taken off loses its file but keeps its settings, and a renamed palette's files take the new name with nothing left behind")
    let joined = Library.merged(purposeLib.swatch(brandSwatch)?.purposes, [PurposeConfig(id: UUID(), purpose: .web, changedAt: tp.addingTimeInterval(9)), PurposeConfig(id: UUID(), purpose: .cine, changedAt: tp)])
    check(joined?.filter { $0.isLive }.map { $0.purpose } == [.web, .print, .cine] && Library.merged(nil, nil) == nil,
          "two Macs' purposes join, each purpose as it was last changed")
    check(Purpose.allCases.map { $0.fileExtension } == ["colweb", "colprint", "colphoto", "colvideo", "colcine", "col3d"] && Purpose.of(fileExtension: "COLPRINT") == .print,
          "each purpose has a file extension of its own that says what it is")
    if let one = SwatchDocument("#FF0000", in: brandSwatch, of: projLib), let oneData = try? one.data() {
        check((try? SwatchDocument.read(oneData)) == one && one.colour.hex == "#FF0000" && SwatchDocument.fileName("Fire / Red") == "Fire - Red.colswatch"
              && (try? SwatchDocument.read(fileData)) == nil, "one colour travels as a file of its own, and reads back as it was")
    } else { check(false, "a palette's colour can be made into a swatch file") }
    check(filesystemName("Red/Blue 50:50?") == "Red-Blue 50-50-" && filesystemName("aux") == "aux_" && filesystemName("COM1.old") == "COM1.old_"
          && filesystemName("Final. ") == "Final" && filesystemName("e\u{0301}") == "\u{00E9}" && filesystemName("...") == "Untitled",
          "a file name is safe on Windows and Linux as well as the Mac: no forbidden characters, no reserved names, no trailing dot")
    projLib.markProjectFile(client, known: true)
    check(ProjectFiles.lost(in: projLib, library: libURL, master: nil).isEmpty, "a project whose file is where it should be is not lost")
    try! fm.removeItem(at: expected.deletingLastPathComponent().deletingLastPathComponent())
    let lostNow = ProjectFiles.lost(in: projLib, library: libURL, master: nil)
    let afterLoss = try! ProjectFiles.write(projLib, library: libURL, master: nil, written: &written)
    check(lostNow[client] == .missing(expected: expected) && afterLoss.files.isEmpty && !fm.fileExists(atPath: expected.path),
          "a project file that has existed and is gone is reported, and never quietly written again")
    check(ProjectFiles.lost(in: projLib, library: projRoot.appendingPathComponent("Gone/library.json"), master: nil)[client]
          == .unavailable(folder: projRoot.appendingPathComponent("Gone/Projects")), "a Projects folder that is not there is reported as unavailable, not as a lost file")
    // Found again, as a file on its own: the folder structure is built round it.
    let loose = projRoot.appendingPathComponent("Found/Client A.config")
    try! fm.createDirectory(at: loose.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! fileData.write(to: loose)
    let adopted = try! ProjectFiles.adopt(loose, for: projLib.project(client)!)
    check(adopted.path == projRoot.appendingPathComponent("Found/Client A").path
          && fm.fileExists(atPath: adopted.appendingPathComponent("Space/Client A.colspace").path) && !fm.fileExists(atPath: loose.path)
          && (try? ProjectFiles.read(adopted.appendingPathComponent("Space/Client A.colspace")).data()) == fileData,
          "a found file on its own, even one an earlier version wrote in one piece, is given its folder structure beside it and still reads")
    check((try? ProjectFiles.adopt(adopted, for: projLib.project(client)!))?.path == adopted.path
          && (try? ProjectFiles.adopt(adopted.appendingPathComponent("Space"), for: projLib.project(client)!))?.path == adopted.path,
          "the project folder, or the folder in it that holds the file, is accepted as the file's home")
    var otherLib = Library()
    let otherProject = otherLib.createProject(named: "Other", at: tp)
    check((try? ProjectFiles.adopt(adopted, for: otherLib.project(otherProject)!)) == nil, "a file that belongs to a different project is refused")
    projLib.setProjectFolder(client, adopted.path)
    projLib.markProjectFile(client, known: true)
    check(ProjectFiles.lost(in: projLib, library: libURL, master: nil).isEmpty, "once found, the project is lost no more")
    // Renamed: the folder and file follow the new name on the next write.
    projLib.setProjectFolder(client, nil)
    projLib.markProjectFile(client, known: false)
    written[client] = nil
    _ = try! ProjectFiles.write(projLib, library: libURL, master: nil, written: &written)
    projLib.markProjectFile(client, known: true)
    _ = projLib.renameProject(client, to: "Client B")
    written[client] = nil
    let renamed = try! ProjectFiles.write(projLib, library: libURL, master: nil, written: &written)
    check(renamed.files.map { $0.path } == [projRoot.appendingPathComponent("Main/Projects/Client B/Space/Client B.colspace").path]
          && !fm.fileExists(atPath: projRoot.appendingPathComponent("Main/Projects/Client A").path),
          "a renamed project's folder and file take the new name")

    print("catalogue files")
    let catDir = root.appendingPathComponent("catalogue/Studio")
    let catStore = LibraryStore(directory: catDir, legacyURL: nil, name: "Studio")
    var catLib = Library()
    let tcat = Date(timeIntervalSince1970: 1_770_000_000)
    let jobA = catLib.createProject(named: "Job A", at: tcat), jobB = catLib.createProject(named: "Job B", at: tcat)
    let inA = catLib.createSwatch(at: tcat), inB = catLib.createSwatch(at: tcat.addingTimeInterval(1)), looseOne = catLib.createSwatch(at: tcat.addingTimeInterval(2))
    _ = catLib.renameSwatch(inA, to: "Autumn"); _ = catLib.renameSwatch(inB, to: "Winter"); _ = catLib.renameSwatch(looseOne, to: "Scratch")
    catLib.add(["#AA0000", "#00AA00"], toSwatch: inA, at: tcat)
    catLib.add(["#0000AA"], toSwatch: inB, at: tcat)
    catLib.add(["#111111"], toSwatch: looseOne, at: tcat)
    catLib.activeSwatchID = nil   // a pick into the library alone, into no palette
    catLib.addPick("#EEEEEE", at: tcat.addingTimeInterval(3))
    catLib.move(inA, to: jobA, index: 0, at: tcat)
    catLib.move(inB, to: jobB, index: 0, at: tcat)
    catLib.setTag("brand", colour: "#FF8800", project: nil, at: tcat)
    catLib.setTag("client", colour: nil, project: jobA, at: tcat)
    catLib.setTags(ofPalette: inA, ["brand", "client"], at: tcat)
    catLib.setPurpose(.print, on: true, ofPalette: inA, at: tcat)
    catLib.setPurpose(.web, on: true, ofPalette: inA, at: tcat)
    catLib.setPurpose(.web, on: false, ofPalette: inA, at: tcat.addingTimeInterval(1))
    catLib.setProfile(ColourProfiles.starters[1], ofPalette: inA, at: tcat)
    catLib.choosePurpose(.print, ofPalette: inA, at: tcat.addingTimeInterval(2))
    catLib.choosePurpose(.video, ofPalette: looseOne, at: tcat.addingTimeInterval(2))
    catLib.choosePurpose(.cine, ofPalette: inB, at: tcat.addingTimeInterval(2))
    catLib.choosePurpose(nil, ofPalette: inB, at: tcat.addingTimeInterval(3))
    catLib.deleteSwatch(catLib.createSwatch(at: tcat), at: tcat.addingTimeInterval(4))
    try! catStore.save(catLib)
    let catBack = try! catStore.load()
    check(catBack == catLib && catStore.unavailable.isEmpty, "a catalogue saved as an index and project files loads back exactly as it was")
    let indexText = String(data: (try? Data(contentsOf: catStore.url)) ?? Data(), encoding: .utf8) ?? ""
    let aConfig = catDir.appendingPathComponent("Projects/Job A")
    check(catStore.url.lastPathComponent == "Studio.colcatalogue" && indexText.contains("Job A") && !indexText.contains("Autumn")
          && fm.fileExists(atPath: aConfig.appendingPathComponent("Space/Job A.colspace").path) && fm.fileExists(atPath: aConfig.appendingPathComponent("Config/Job A.coldata").path)
          && fm.fileExists(atPath: aConfig.appendingPathComponent("Palettes/Autumn.colpalette").path) && fm.fileExists(atPath: aConfig.appendingPathComponent("Channels/Autumn.colprint").path)
          && !fm.fileExists(atPath: aConfig.appendingPathComponent("Channels/Autumn.colweb").path)
          && ProjectFiles.folders.allSatisfy { fm.fileExists(atPath: aConfig.appendingPathComponent($0).path) }
          && fm.fileExists(atPath: catDir.appendingPathComponent("Unfiled/Config/Unfiled.coldata").path) && fm.fileExists(atPath: catDir.appendingPathComponent("Unfiled/Palettes/Scratch.colpalette").path),
          "the catalogue's file is the index, named for the catalogue; each project holds its own palettes, and what belongs to no project is in Unfiled")
    let aProject = try? ColourFiles.decoder().decode(ProjectDocument.self, from: Data(contentsOf: aConfig.appendingPathComponent("Space/Job A.colspace")))
    let aPalette = try? ColourFiles.decoder().decode(PaletteDocument.self, from: Data(contentsOf: aConfig.appendingPathComponent("Palettes/Autumn.colpalette")))
    let looseFile = try? ColourFiles.decoder().decode(PaletteDocument.self, from: Data(contentsOf: catDir.appendingPathComponent("Unfiled/Palettes/Scratch.colpalette")))
    check(aProject?.turned == [TurnedPalette(palette: inA, purpose: .print, changedAt: tcat.addingTimeInterval(2))] && aPalette?.palette.purpose == nil
          && looseFile?.palette.purpose == .video && catBack.swatch(inA)?.purpose == .print && catBack.swatch(inB)?.purpose == nil
          && catBack.swatch(inB)?.purposeChangedAt == tcat.addingTimeInterval(3) && catBack.swatch(inB)?.purposeList == [.cine],
          "the purpose a palette is turned to is kept in its project's file; a palette in no project keeps its own; turning to none is remembered too")
    let unfiledData = try? ColourFiles.decoder().decode(DataDocument.self, from: Data(contentsOf: catDir.appendingPathComponent("Unfiled/Config/Unfiled.coldata")))
    let jobData = try? ColourFiles.decoder().decode(DataDocument.self, from: Data(contentsOf: aConfig.appendingPathComponent("Config/Job A.coldata")))
    check(unfiledData?.colours.map { $0.hex } == ["#EEEEEE"] && unfiledData?.tags.map { $0.name } == ["brand"] && unfiledData?.profiles.map { $0.id } == [ColourProfiles.starters[1].id]
          && jobData?.tags.map { $0.name }.sorted() == ["brand", "client"] && jobData?.project == jobA,
          "Unfiled is the home of global tags, the profiles and colours no palette uses; a project's data holds its own tags and carries the global ones it wears")
    // A project whose folder cannot be reached: listed, unavailable, never written over, and whole when it returns.
    let away = root.appendingPathComponent("catalogue/Job B away")
    try! fm.moveItem(at: catDir.appendingPathComponent("Projects/Job B"), to: away)
    let without = try! catStore.load()
    check(catStore.unavailable == [jobB] && without.projects.map { $0.name } == ["Job A", "Job B"] && without.swatch(inB) == nil && without.swatch(inA) != nil
          && ProjectFiles.lost(in: without, library: catStore.url, master: nil)[jobB] != nil,
          "a project whose files cannot be reached stays in the catalogue, marked unavailable, and is not taken to be deleted")
    try! catStore.mutate { $0.addPick("#ABCDEF", at: tcat.addingTimeInterval(9)) }
    check(!fm.fileExists(atPath: catDir.appendingPathComponent("Projects/Job B").path) && (try? catStore.load().projects.count) == 2,
          "saving while a project is unavailable leaves it listed and writes nothing in its place")
    try! fm.moveItem(at: away, to: catDir.appendingPathComponent("Projects/Job B"))
    let returned = try! catStore.load()
    check(catStore.unavailable.isEmpty && returned.swatch(inB)?.entries.map { $0.hex } == ["#0000AA"] && returned.colours.contains { $0.hex == "#ABCDEF" },
          "when its files come back the project is whole again, with what was done meanwhile kept")
    // Found again somewhere else: pointing the catalogue at the new place must read the project, never write over it.
    let movedTo = root.appendingPathComponent("catalogue/Moved/Job B")
    try! fm.createDirectory(at: movedTo.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! fm.moveItem(at: catDir.appendingPathComponent("Projects/Job B"), to: movedTo)
    try! catStore.mutate { $0.setProjectFolder(jobB, movedTo.path) }
    let refound = try! catStore.load()
    check(catStore.unavailable.isEmpty && refound.swatch(inB)?.entries.map { $0.hex } == ["#0000AA"] && refound.project(jobB)?.folder == movedTo.path
          && fm.fileExists(atPath: movedTo.appendingPathComponent("Palettes/Winter.colpalette").path),
          "a project found in another folder is read from there with everything in it, and nothing is written over it on the way")
    try! catStore.mutate { $0.setProjectFolder(jobB, nil) }
    try! fm.moveItem(at: movedTo, to: catDir.appendingPathComponent("Projects/Job B"))
    _ = try! catStore.load()
    // A palette moved from one project to another: in its new home, gone from its old one.
    try! catStore.mutate { $0.move(inA, to: jobB, index: 0, at: tcat.addingTimeInterval(20)) }
    check(!fm.fileExists(atPath: aConfig.appendingPathComponent("Palettes/Autumn.colpalette").path) && !fm.fileExists(atPath: aConfig.appendingPathComponent("Channels/Autumn.colprint").path)
          && fm.fileExists(atPath: catDir.appendingPathComponent("Projects/Job B/Channels/Autumn.colprint").path)
          && (try? catStore.load().swatch(inA)?.projectID) == jobB, "a palette moved to another project takes its files with it")
    // A catalogue an earlier version kept in one file.
    let oldDir = root.appendingPathComponent("catalogue/Earlier")
    try! fm.createDirectory(at: oldDir, withIntermediateDirectories: true)
    try! JSONEncoder.library.encode(catLib).write(to: oldDir.appendingPathComponent("library.json"))
    // One of its projects had been marked as written and its folder is not there: the one file is the only copy, so it is made again.
    var earlier = catLib
    earlier.markProjectFile(jobA, known: true)
    try! JSONEncoder.library.encode(earlier).write(to: oldDir.appendingPathComponent("library.json"))
    let oldStore = LibraryStore(directory: oldDir, legacyURL: nil)
    let converted = try! oldStore.load()
    check(oldStore.unavailable.isEmpty && (try? oldStore.load().swatch(inA)?.entries.count) == 2 && oldStore.unavailable.isEmpty
          && fm.fileExists(atPath: oldDir.appendingPathComponent("Projects/Job A/Palettes/Autumn.colpalette").path),
          "turning a one-file catalogue into project files writes every project, even one whose folder had gone, so nothing is left behind")
    check(converted.swatches.map { $0.name } == catLib.swatches.map { $0.name } && fm.fileExists(atPath: oldDir.appendingPathComponent("Earlier.colcatalogue").path)
          && !fm.fileExists(atPath: oldDir.appendingPathComponent("library.json").path)
          && ((try? fm.contentsOfDirectory(atPath: oldDir.appendingPathComponent("Backups").path)) ?? []).contains { $0.hasPrefix("library before catalogue files") }
          && (try? LibraryStore(directory: oldDir, legacyURL: nil).load().swatches.count) == catLib.swatches.count,
          "a catalogue an earlier version kept in one file is saved as catalogue files, and the one file is kept among the backups")

    // A project as an earlier version kept it, everything nested in Config: read where it is, and tidied when saved.
    let nestDir = root.appendingPathComponent("catalogue/Nested")
    let nestStore = LibraryStore(directory: nestDir, legacyURL: nil)
    try! nestStore.save(catLib)
    let nestA = nestDir.appendingPathComponent("Projects/Job A")
    try! fm.createDirectory(at: nestA.appendingPathComponent("Config/Palettes"), withIntermediateDirectories: true)
    try! fm.moveItem(at: nestA.appendingPathComponent("Space/Job A.colspace"), to: nestA.appendingPathComponent("Config/Job A.colproject"))
    try! fm.removeItem(at: nestA.appendingPathComponent("Space"))
    try! fm.moveItem(at: nestA.appendingPathComponent("Palettes/Autumn.colpalette"), to: nestA.appendingPathComponent("Config/Palettes/Autumn.colpalette"))
    try! fm.moveItem(at: nestA.appendingPathComponent("Channels/Autumn.colprint"), to: nestA.appendingPathComponent("Config/Palettes/Autumn.colprint"))
    let nestedBack = try! LibraryStore(directory: nestDir, legacyURL: nil).load()
    check(nestedBack == catLib, "a project an earlier version kept nested in its Config folder is still read whole")
    let nestAgain = LibraryStore(directory: nestDir, legacyURL: nil)
    try! nestAgain.mutate { $0.addPick("#123456", at: tcat.addingTimeInterval(30)) }
    check(fm.fileExists(atPath: nestA.appendingPathComponent("Space/Job A.colspace").path) && fm.fileExists(atPath: nestA.appendingPathComponent("Channels/Autumn.colprint").path)
          && !fm.fileExists(atPath: nestA.appendingPathComponent("Config/Job A.colproject").path) && !fm.fileExists(atPath: nestA.appendingPathComponent("Config/Palettes").path)
          && (try? nestAgain.load().swatch(inA)?.purposeList) == [.print],
          "and when it is next saved its files go into folders of their own, with nothing left nested")

    // A project as the version before this kept it: a Project folder holding a .colproject file. Read, and tidied when saved.
    let earlierDir = root.appendingPathComponent("catalogue/Earlier")
    try! LibraryStore(directory: earlierDir, legacyURL: nil).save(catLib)
    let earlierA = earlierDir.appendingPathComponent("Projects/Job A")
    try! fm.createDirectory(at: earlierA.appendingPathComponent("Project"), withIntermediateDirectories: true)
    try! fm.moveItem(at: earlierA.appendingPathComponent("Space/Job A.colspace"), to: earlierA.appendingPathComponent("Project/Job A.colproject"))
    try! fm.removeItem(at: earlierA.appendingPathComponent("Space"))
    check((try? LibraryStore(directory: earlierDir, legacyURL: nil).load()) == catLib, "a member kept as Project/Name.colproject by the version before is still read whole")
    try! LibraryStore(directory: earlierDir, legacyURL: nil).mutate { $0.addPick("#123457", at: tcat.addingTimeInterval(31)) }
    check(fm.fileExists(atPath: earlierA.appendingPathComponent("Space/Job A.colspace").path) && !fm.fileExists(atPath: earlierA.appendingPathComponent("Project").path),
          "and when it is next saved the file is Space/Name.colspace and the Project folder is gone")

    print("where catalogues and their members are kept")
    let homeDir = root.appendingPathComponent("home"), awayDir = root.appendingPathComponent("awayDir")
    let cats = Catalogues(root: homeDir, legacyURL: nil)
    let inside = try! cats.create("Inside")
    let outside = try! cats.create("Outside", under: awayDir)
    check(cats.directory(for: inside) == homeDir.appendingPathComponent("Catalogues/Inside") && cats.directory(for: outside) == awayDir.appendingPathComponent("Outside")
          && fm.fileExists(atPath: awayDir.appendingPathComponent("Outside/Outside.colcatalogue").path) && Set(cats.names()).isSuperset(of: ["Inside", "Outside"]),
          "a catalogue is made under Catalogues in the app's home, or under any folder the user chose, and both are listed")
    let adoptedName = try! Catalogues(root: root.appendingPathComponent("home2"), legacyURL: nil).adopt(awayDir.appendingPathComponent("Outside/Outside.colcatalogue"))
    check(adoptedName == "Outside" && Catalogues(root: root.appendingPathComponent("home2"), legacyURL: nil).directory(for: "Outside") == awayDir.appendingPathComponent("Outside"),
          "a .colcatalogue file chosen from anywhere is opened where it is, under its own name, with nothing copied")
    let renamedOut = try! cats.rename("Outside", to: "Outer")
    check(renamedOut == "Outer" && cats.directory(for: "Outer") == awayDir.appendingPathComponent("Outer") && fm.fileExists(atPath: awayDir.appendingPathComponent("Outer/Outer.colcatalogue").path),
          "a catalogue kept awayDir is renamed where it is, folder and file alike")
    let indexURL = awayDir.appendingPathComponent("Outer/Outer.colcatalogue")
    check(ProjectFiles.keep(awayDir.appendingPathComponent("Outer/Clients/Cookra"), beside: indexURL) == "Clients/Cookra"
          && ProjectFiles.keep(root.appendingPathComponent("drive/Cookra"), beside: indexURL) == root.appendingPathComponent("drive/Cookra").path
          && ProjectFiles.resolve("Clients/Cookra", beside: indexURL) == awayDir.appendingPathComponent("Outer/Clients/Cookra")
          && ProjectFiles.resolve(root.appendingPathComponent("drive/Cookra").path, beside: indexURL) == root.appendingPathComponent("drive/Cookra"),
          "a member's folder is kept relative to its catalogue when it is inside it, so it moves with the catalogue, and in full otherwise")
    try! Catalogues(root: homeDir, legacyURL: nil).store(for: "Inside").mutate { lib in
        let id = lib.createProject(named: "Cookra")
        lib.setProjectFolder(id, "Clients/Cookra")
    }
    check(fm.fileExists(atPath: homeDir.appendingPathComponent("Catalogues/Inside/Clients/Cookra/Space/Cookra.colspace").path)
          && (try? Catalogues(root: homeDir, legacyURL: nil).store(for: "Inside").load().projects.first?.name) == "Cookra",
          "a member whose folder is relative is written and read back inside its catalogue's folder")

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
    let lockedFile = ProjectFile(project: lockLib.project(lp)!, in: lockLib)
    check((try? ProjectFile.read(lockedFile.data()))?.project.isLocked == true, "the lock travels in the project file")

    print("history")
    var hist = StepHistory()
    var hLib = Library()
    let th = Date(timeIntervalSince1970: 1_760_000_000)
    hist.record("Opened", library: hLib, before: nil, limit: 0, at: th)
    let hp = hLib.createProject(named: "Client", at: th)
    hist.record("New Project", library: hLib, before: hist.steps.last!.library, limit: 0, at: th)
    let hs = hLib.createSwatch(at: th); hLib.add(["#FF0000"], toSwatch: hs, at: th); hLib.move(hs, to: hp, index: 0, at: th)
    hist.record("Add Colours", library: hLib, before: hist.steps.last!.library, limit: 0, at: th)
    let hs2 = hLib.createSwatch(at: th.addingTimeInterval(1)); hLib.add(["#00FF00"], toSwatch: hs2, at: th)
    hist.record("New Palette", library: hLib, before: hist.steps.last!.library, limit: 0, at: th)
    check(hist.steps.map { $0.title } == ["Opened", "New Project", "Add Colours", "New Palette"] && hist.current == 3,
          "every change is a step, newest last, and the library matches the last one")
    check(hist.steps.map { $0.project } == [nil, hp, hp, nil], "a step that touched one project is marked with it; a loose palette is not")
    check(hist.steps(in: hp).count == 2 && hist.steps(changing: hs).map { $0.title } == ["Add Colours"],
          "a project's steps and a palette's own changes can be picked out")
    let backTo = hist.go(to: 1)
    check(backTo?.swatches.isEmpty == true && hist.current == 1 && hist.steps.count == 4, "going back to a step gives that library and keeps the later steps")
    hist.record("Rename Project", library: hLib, before: backTo, limit: 0, at: th)
    check(hist.steps.map { $0.title } == ["Opened", "New Project", "Rename Project"] && hist.current == 2,
          "a new step taken from an earlier one cuts off the steps after it")
    hist.delete(at: 0)
    check(hist.steps.map { $0.title } == ["New Project", "Rename Project"] && hist.current == 1, "a step can be deleted and the current one follows")
    var hist3 = StepHistory()
    var cLib = Library()
    hist3.record("Opened", library: cLib, before: nil, limit: 0, at: th)
    let cs = cLib.createSwatch(at: th); cLib.add(["#FF2400", "#00FF00"], toSwatch: cs, at: th)
    hist3.record("Add Colours", library: cLib, before: hist3.steps.last!.library, limit: 0, at: th)
    cLib.remove(["#00FF00"], fromSwatch: cs, at: th)
    hist3.record("Remove Colours", library: cLib, before: hist3.steps.last!.library, limit: 0, at: th)
    check(hist3.change(at: 1) == StepChange(added: ["#FF2400", "#00FF00"], removed: []) && hist3.change(at: 2) == StepChange(added: [], removed: ["#00FF00"])
          && hist3.change(at: 0).isEmpty, "a step knows which colours it brought in or took out")
    check(stepSymbol(for: "Pick Colour") == "eyedropper" && stepSymbol(for: "Delete Palette") == "trash" && stepSymbol(for: "Rename Tag") == "pencil"
          && stepSymbol(for: "Sync") == "arrow.triangle.2.circlepath" && stepSymbol(for: "Something Else") == "circle", "each kind of step has a symbol")
    for i in 0..<5 { hist.record("Step \(i)", library: hLib, before: hLib, limit: 3, at: th) }
    check(hist.steps.count == 3 && hist.steps.last?.title == "Step 4" && hist.current == 2, "a limit keeps only the newest steps")
    let hRoot = root.appendingPathComponent("history/library.json")
    try! fm.createDirectory(at: hRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! HistoryStore.save(hist, beside: hRoot)
    check(HistoryStore.load(beside: hRoot) == hist && HistoryStore.url(beside: hRoot).lastPathComponent == "library.history.json",
          "history is kept in a sidecar file beside the library and reads back whole")
    check(HistoryStore.load(beside: root.appendingPathComponent("nowhere/library.json")).isEmpty, "no sidecar, no history")
    var hist2 = StepHistory()
    hist2.record("Opened", library: Library(), before: nil, limit: 0, at: th)
    hist2.record("New Project", library: hLib, before: Library(), limit: 0, at: th)
    let withSteps = ProjectFile(project: hLib.project(hp)!, in: hLib, history: hist2.steps(in: hp))
    check(withSteps.history.map { $0.title } == ["New Project"] && (try? ProjectFile.read(withSteps.data()))?.history == withSteps.history,
          "a project file lists the steps that touched the project, and reads them back")

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
          && real.previousURL != real.store(for: Catalogues.mainName).url,
          "the app looks for earlier libraries in the version 1 and version 2 folders, not its own")
    check(real.store(for: "Some other catalogue").previousURL == nil, "only Main is seeded from an earlier version")
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
    noted.setNote("  The call to action. Warm, never red. ", of: "#F55805", in: np, at: t.addingTimeInterval(1))
    steps.record("Describe Colour", library: noted, before: steps.steps.last!.library, limit: 0, at: t.addingTimeInterval(1))
    check(noted.note(of: "#F55805", in: np) == "The call to action. Warm, never red." && noted.note(of: "#F55805", in: nweb) == nil,
          "a colour described in one palette has no description in another")
    let notedFile = ProjectFile(project: noted.project(client)!, in: noted)
    check((try? ProjectFile.read(notedFile.data()))?.palettes.first?.entries.first?.note == "The call to action. Warm, never red.",
          "the description travels in the project file")
    var elsewhere = noted
    elsewhere.setNote("Buttons only.", of: "#F55805", in: np, at: t.addingTimeInterval(5))
    check(mergeLibraries(local: noted, remote: elsewhere).note(of: "#F55805", in: np) == "Buttons only."
          && mergeLibraries(local: elsewhere, remote: noted).note(of: "#F55805", in: np) == "Buttons only.", "the newer description wins a sync")
    noted.setName("Brand Orange", of: "#F55805", in: np, at: t.addingTimeInterval(6))
    steps.record("Rename Colour", library: noted, before: steps.steps.last!.library, limit: 0, at: t.addingTimeInterval(6))
    noted.setNote("", of: "#F55805", in: np, at: t.addingTimeInterval(10))
    steps.record("Describe Colour", library: noted, before: steps.steps.last!.library, limit: 0, at: t.addingTimeInterval(10))
    check(noted.note(of: "#F55805", in: np) == nil && mergeLibraries(local: noted, remote: elsewhere).note(of: "#F55805", in: np) == nil,
          "a blank description removes it, and a sync keeps it removed")
    noted.remove(["#F55805"], fromSwatch: np, at: t.addingTimeInterval(11))
    steps.record("Remove Colours", library: noted, before: steps.steps.last!.library, limit: 0, at: t.addingTimeInterval(11))
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
          && deltaE2000(someLab, someLab) == 0,
          "the colour difference matches the published CIEDE2000 figures, and a colour differs from itself by nothing")
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
    check(ColourDefinition.picked(NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1))?.source.space == RGBSpace.displayP3.rawValue
          && ColourDefinition.picked(NSColor(srgbRed: 79.0 / 255, green: 128.0 / 255, blue: 147.0 / 255, alpha: 1))?.sourceText == plainRGB.sourceText,
          "a pick from a wide screen is kept in Display P3 when sRGB cannot hold it, and as a plain hex when it can")
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
    let studioFile = ProjectFile(project: studio.project(client2)!, in: studio)
    check((try? ProjectFile.read(studioFile.data()))?.profiles?.map { $0.id } == [printProfile.id], "the project's file carries the profiles it works to")
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

    // A .colpalette the app wrote reads back whole, with the names given in it.
    var lib = Library()
    let id = lib.createSwatch(named: "Brand", hexes: ["#4F8093", "#B55226"])
    lib.setName("Steel Blue", of: "#4F8093", in: id)
    if let doc = try? ProjectFile.paletteDocuments([lib.swatch(id)!], colours: lib.colours, project: nil).first {
        let own = PaletteImport.read(doc.data, fallback: "x")
        check(own.first?.name == "Brand" && own.first?.colours.first?.name == "Steel Blue" && own.first?.colours.count == 2,
              "a .colpalette reads back as its palette, with its names")
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
