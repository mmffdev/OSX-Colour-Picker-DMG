import AppKit

// ---------- Pick mode (hotkey-triggered) ----------

func runPickMode() -> Never {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)

    let sampler = NSColorSampler()
    let semaphore = DispatchSemaphore(value: 0)
    var picked: String?

    sampler.show { color in
        defer { semaphore.signal() }
        guard let color = color, let hex = hexOf(color) else { return }
        playShutter()
        copyToClipboard(hex)
        do {
            try LibraryStore.standard.mutate { $0.addPick(hex) }
        } catch {
            FileHandle.standardError.write("\(error.localizedDescription)\n".data(using: .utf8)!)
        }
        picked = hex
    }

    while semaphore.wait(timeout: .now()) == .timedOut {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    if let h = picked { print(h); exit(0) }
    exit(1)
}

// ---------- Library mode (window) ----------

final class AppDelegate: NSObject, NSApplicationDelegate {
    var wc: LibraryWindowController?
    var settings: SettingsWindowController?

    @objc func showSettings() {
        guard let wc = wc else { return }
        if settings == nil {
            let s = SettingsWindowController(library: wc)
            wc.onStateChanged = { [weak s] in s?.refresh() }
            settings = s
        }
        settings?.refresh()
        settings?.showWindow(nil)
        settings?.window?.makeKeyAndOrderFront(nil)
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)

        let wc = LibraryWindowController(store: .standard)
        self.wc = wc

        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(
            title: "About MMFFDev Colour 2",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""))
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: "Quit MMFFDev Colour 2",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"))
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "Pick a Colour", action: #selector(LibraryWindowController.pickFromWindow), keyEquivalent: "p"))
        fileMenu.addItem(NSMenuItem(title: "New Swatch", action: #selector(LibraryWindowController.newSwatch), keyEquivalent: "n"))
        let catalogueItem = NSMenuItem(title: "Catalogue", action: nil, keyEquivalent: "")
        catalogueItem.submenu = wc.catalogueMenu
        fileMenu.addItem(catalogueItem)
        fileMenu.addItem(NSMenuItem(title: "Sync Now", action: #selector(LibraryWindowController.syncNow), keyEquivalent: "S"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "Palette from Image\u{2026}", action: #selector(LibraryWindowController.paletteFromImage), keyEquivalent: "i"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "Export Library\u{2026}", action: #selector(LibraryWindowController.exportLibrary), keyEquivalent: "e"))
        fileMenu.addItem(NSMenuItem(title: "Import from MMFFDev Colour", action: #selector(LibraryWindowController.importFromV1), keyEquivalent: ""))
        fileMenu.items.forEach { if !$0.isSeparatorItem && $0.submenu == nil { $0.target = wc } }
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu

        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { wc.sync() } // on open: look for changes from the other Mac
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

// ---------- Entry point ----------

if CommandLine.arguments.contains("--self-test") {
    runSelfTest()
} else if CommandLine.arguments.contains("--pick") {
    runPickMode()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
