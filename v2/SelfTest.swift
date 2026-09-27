import Foundation

// Run with: MMFFDevColour2 --self-test
// Exercises the library logic against a throwaway folder. Never touches real data.

func runSelfTest() -> Never {
    var passed = 0, failed = 0
    func check(_ ok: Bool, _ what: String) {
        if ok { passed += 1; print("  ok    \(what)") }
        else { failed += 1; print("  FAIL  \(what)") }
    }

    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("mmffdev-colour2-selftest-\(UUID().uuidString)")
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
    check(lib.swatch(first)?.name == "Swatch 1", "first swatch is named \"Swatch 1\"")
    check(lib.activeSwatchID == first, "a new swatch becomes the pick target")
    lib = try! store.mutate { second = $0.createSwatch(at: t0.addingTimeInterval(1)) }
    check(lib.swatch(second)?.name == "Swatch 2", "second swatch is named \"Swatch 2\"")

    lib = try! store.mutate { $0.renameSwatch(first, to: "  Brand  ") }
    check(lib.swatch(first)?.name == "Brand", "rename trims and saves")
    lib = try! store.mutate { $0.renameSwatch(first, to: "   ") }
    check(lib.swatch(first)?.name == "Brand", "blank rename is rejected")
    check(lib.nextDefaultSwatchName() == "Swatch 3", "default names keep counting up after a rename")

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

    print("\n\(passed) passed, \(failed) failed")
    exit(failed == 0 ? 0 : 1)
}
