import AppKit
import QuartzCore
import UniformTypeIdentifiers
import ImageIO

// ---------- The Studio window: the app itself on Colorgain's own grid ----------
//
// Colorgain's main window as the design guide draws it (c_c_c_design_grid_app.md, c_c_design_elements.md):
// a 94 header, the library rail, the context rail, the page, the history rail and a 48 footer, on
// twelve columns inside 24 margins with 16 gutters. Everything is placed by frame from the grid and
// drawn in the ten text styles; no macOS control is on the window but the search field. It opens
// the window the app opens since 2026-10-08; the old window opens only with --classic. Begun 2026-10-07
// on Rick's free run: the library and palettes views only, their assets' layout and presentation.

final class StudioWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var onSessionInteraction:(()->Void)?
    /// A click anywhere that is not a field ends whatever field was being typed in, the search above all: otherwise the
    /// quick keys, 1 and 2, go on typing into it and the page is filtered by "22" while the picks land elsewhere.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, firstResponder is NSText, let content = contentView {
            let hit = content.hitTest(content.convert(event.locationInWindow, from: nil))
            var inField = false, v = hit
            while let view = v { if view is NSTextField || view is NSTextView { inField = true; break }; v = view.superview }
            if !inField { makeFirstResponder(content) }
        }
        super.sendEvent(event)
        switch event.type {
        case .leftMouseUp,.rightMouseUp,.keyUp,.scrollWheel,.magnify,.swipe:onSessionInteraction?()
        default:break
        }
    }
}

final class StudioWindowController: NSWindowController {
    static var shared: StudioWindowController?
    let frame: StudioFrame
    private var sessionTimer: Timer?
    private var sessionObservers: [NSObjectProtocol] = []

    private func startSessionMemory() {
        guard sessionObservers.isEmpty else{return}
        (window as? StudioWindow)?.onSessionInteraction={ [weak self] in self?.scheduleSessionSave() }
        for name in [NSWindow.didMoveNotification,NSWindow.didResizeNotification] {
            sessionObservers.append(NotificationCenter.default.addObserver(forName:name,object:window,queue:.main){[weak self] _ in self?.scheduleSessionSave()})
        }
        for name in [NSWindow.willCloseNotification,NSWindow.didResignKeyNotification] {
            sessionObservers.append(NotificationCenter.default.addObserver(forName:name,object:window,queue:.main){[weak self] _ in self?.sessionTimer?.invalidate();self?.sessionTimer=nil;self?.frame.saveWorkspaceSession(flush:true)})
        }
    }
    private func scheduleSessionSave() {
        sessionTimer?.invalidate()
        sessionTimer=Timer.scheduledTimer(withTimeInterval:1,repeats:false){[weak self] _ in self?.sessionTimer=nil;self?.frame.saveWorkspaceSession()}
    }
    deinit {sessionTimer?.invalidate();sessionObservers.forEach{NotificationCenter.default.removeObserver($0)}}

    init(library: LibraryController) {
        frame = StudioFrame(library: library)
        let w = StudioWindow(contentRect: NSRect(origin: .zero, size: Design.App.size),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.acceptsMouseMovedEvents = true
        w.title = Brand.edition
        w.titleVisibility = .visible
        w.titlebarAppearsTransparent = false
        w.isMovableByWindowBackground = false   // a press on the page is a press on the page, never a drag of the window
        w.collectionBehavior = [.fullScreenPrimary, .managed]   // a borderless window goes full screen only when told it may
        w.backgroundColor = Design.paper
        w.minSize = NSSize(width: 1200, height: 830)
        // A resize moves by whole units, so the rows always end on the beat above the footer.
        w.resizeIncrements = NSSize(width: 1, height: 1)
        w.contentView = frame
        w.center()
        if let screen = NSScreen.screens.min(by: { $0.frame.minX < $1.frame.minX }) { w.setFrame(screen.visibleFrame, display: false) }
        super.init(window: w)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc func editSelectedMetadata(){frame.editMetadata()}

    private static var gridKey: Any?

    static func closeWorkspace() {
        shared?.frame.saveWorkspaceSession(flush:true)
        shared?.sessionTimer?.invalidate()
        Overlays.closeAll()
        if let gridKey { NSEvent.removeMonitor(gridKey) }
        gridKey=nil;shared?.close();shared=nil
    }

    static func show(library: LibraryController, setupJourney: Bool = false) {
        let alreadyOpen=shared != nil
        let c = shared ?? StudioWindowController(library: library)
        shared = c
        // --palettes opens on the palettes view, --palette "<name>" on that palette, for looking at a screen straight away.
        let args = CommandLine.arguments
        let resumeRestart=alreadyOpen || (args.contains("--resume-workspace-session") && c.frame.restoreWorkspaceSession())
        let named = args.firstIndex(of: "--palette").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        let project = args.firstIndex(of: "--project").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        if resumeRestart { /* Explicit permission restart takes priority over old launch navigation flags. */ }
        else if let name = named, let s = library.library.swatches.first(where: { $0.name == name }) { c.frame.go(.palette(s.id)) }
        else if let name = project, let p = library.library.projects.first(where: { $0.name == name }) { c.frame.go(.project(p.id)) }
        else {
            let views: [(String, StudioFrame.Place)] = [("--settings", .settings), ("--schema", .schema), ("--shortcuts", .shortcuts), ("--halo", .halo), ("--tags", .tags), ("--lab", .lab), ("--contrast", .contrast), ("--prepress", .prepress(0)), ("--prepress-verify", .prepress(1)), ("--prepress-check", .prepress(2)), ("--prepress-print", .prepress(3)), ("--prepress-press", .prepress(4)), ("--projects", .projects), ("--palettes", .palettes), ("--share", .share), ("--appbridge", .appbridge), ("--appbridge-settings", .appbridgeSettings)]
            if let destination=views.first(where:{args.contains($0.0)})?.1 {c.frame.go(destination)}
            else if !c.frame.restoreWorkspaceSession() {c.frame.go(c.frame.restoredLibraryPlace())}
        }
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
        library.window = c.window   // errors and prompts come up on this window
        c.frame.enableSessionMemory();c.startSessionMemory()
        // The splash that sets up the work (TH-299): over the whole window when the catalogue has no structure yet, or when --splash asks; --no-splash keeps it away.
        // While the splash is being designed, the loop keeps the app in it: every launch opens on it, and Set starts it again instead of
        // building anything. --splash-loop for one run, or `defaults write ~/Library/Preferences/com.mmffdev.mmffdevcolour3 splashLoop -bool YES` until it is deleted
        // (by path: the Store edition's container answers to the bare domain once it has run).
        // The wizard has just completed on a first open; its completion must not skip the journey.
        if setupJourney || args.contains("--splash") || args.contains("--splash-loop") { c.frame.showSplash() }
        // --snap <file> writes the page that is showing, whole, as a PNG and quits: for measuring a screen below the fold without scrolling it.
        if let i = args.firstIndex(of: "--snap"), args.indices.contains(i + 1) {
            let to = URL(fileURLWithPath: args[i + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let png = c.frame.page.snapshot()?.representation(using: .png, properties: [:]) { try? png.write(to: to) }
                NSApp.terminate(nil)
            }
        }
        // The backslash key turns Master Inner on and off, whenever no words are being typed.
        if gridKey == nil {
            gridKey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak c, weak library] e in
                guard let c = c, e.window === c.window else { return e }
                if e.keyCode == 53, !Overlays.any, c.window?.attachedSheet == nil, c.frame.closeExpandedPanel() { return nil }
                if e.keyCode == 53, !Overlays.any, (c.window?.firstResponder as? ShortcutsSettings)?.isRecordingShortcut != true, c.frame.leaveSettings() { return nil }
                guard !(c.window?.firstResponder is NSText), !Overlays.any else { return e }
                if c.window?.firstResponder is ShortcutsSettings { return e }   // a key being recorded is not a key being used
                if e.keyCode == 48, e.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty, c.frame.splash == nil {
                    if !e.isARepeat {
                        c.frame.paletteWheel.present()
                    }
                    return nil
                }
                if e.charactersIgnoringModifiers?.lowercased() == "l", e.modifierFlags.intersection([.command,.control,.option,.shift]).isEmpty, c.window?.attachedSheet == nil, c.frame.splash == nil {
                    if !e.isARepeat { AppearancePresets.cycle() }; return nil
                }
                if e.characters == "\\" { c.frame.toggleGrid(); return nil }
                // The quick keys: single keys that work anywhere in the window.
                switch QuickKeys.command(for: e) {
                case "newPalette"?: library?.newPalette(); return nil
                case "pick"?: library?.togglePicking(); return nil
                case "sample"?: library?.sampleArea(); return nil
                case "outputProof"?: if !e.isARepeat { Prefs.deltaWarningsEnabled.toggle() }; return nil
                case "rail1"?: if !e.isARepeat { c.frame.toggleRail(1) }; return nil
                case "rail2"?: if !e.isARepeat { c.frame.toggleRail(2) }; return nil
                default: return e
                }
            }
        }
        // The controller's questions come up on the window's own panels, not the old window's.
        library.onPrompt = { [weak c] p in
            SwissConfirm.name(over: c?.window, title: p.title, note: p.message, placeholder: p.placeholder, confirm: p.confirm, check: p.check) { p.done($0) }
        }
        library.onAsk = { [weak c] title, message, choices in
            SwissConfirm.choose(over: c?.window, title: title, note: message, choices: choices.map { $0.title }) { i in if choices.indices.contains(i) { choices[i].run() } }
        }
        library.onOpenContrast = { [weak c] palette, style in
            c?.frame.go(.contrast)
            c?.frame.contrastPage.edit(style, in: palette)
        }
        library.onShow = { [weak c] s, _ in
            switch s {
            case .overview(let id): c?.frame.go(.project(id))
            case .palette(let id): c?.frame.go(.palette(id))
            default: break
            }
        }
        c.window?.makeFirstResponder(c.frame)   // not the search field: nothing blinks until it is wanted
    }
}

// MARK: - Drawing on the baseline

/// Text is placed by its baseline, never its box, so a row of different sizes sits level (the
/// guide's first law). All the window's views are flipped: y grows downwards, as the grid reads.
extension NSAttributedString {
    var baselineFont: NSFont { length > 0 ? attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? Design.Text.body.font() : Design.Text.body.font() }
    func draw(x: CGFloat, baseline: CGFloat) { if length > 0 { draw(at: NSPoint(x: x, y: baseline - baselineFont.ascender)) } }
    func draw(right: CGFloat, baseline: CGFloat) { draw(x: right - size().width, baseline: baseline) }
    /// Draws on one line, cut with an ellipsis where it would pass `width`.
    func draw(x: CGFloat, baseline: CGFloat, width: CGFloat) {
        if size().width <= width { draw(x: x, baseline: baseline); return }
        let m = NSMutableAttributedString(attributedString: self)
        while m.length > 1 && m.size().width > width { m.deleteCharacters(in: NSRange(location: m.length - 1, length: 1)); }
        m.deleteCharacters(in: NSRange(location: max(0, m.length - 1), length: min(1, m.length)))
        m.append(NSAttributedString(string: "\u{2026}", attributes: attributes(at: 0, effectiveRange: nil)))
        m.draw(x: x, baseline: baseline)
    }
}

func fill(_ r: NSRect, _ c: NSColor) { c.setFill(); r.fill() }
func hairline(x: CGFloat, y: CGFloat, width: CGFloat, _ c: NSColor = Design.rule) { fill(NSRect(x: x, y: y, width: width, height: 1), c) }

/// "Just now", "12 min", "3 hr", "Yesterday", then the day.
private func when(_ d: Date) -> String {
    let s = Date().timeIntervalSince(d)
    if s < 60 { return "Just now" }
    if s < 3600 { return "\(Int(s / 60)) min" }
    if s < 86400 { return "\(Int(s / 3600)) hr" }
    if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
    let f = DateFormatter(); f.dateFormat = "d MMM"
    return f.string(from: d)
}

/// Shared square register selection and colour strips.
private enum RailTile {
    static func spectrum(_ colours: [NSColor], in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        fill(rect, Design.mist)
        if !colours.isEmpty {
            let width = rect.width / CGFloat(colours.count)
            for (i, colour) in colours.enumerated() {
                fill(NSRect(x: rect.minX + CGFloat(i) * width, y: rect.minY, width: width + 0.5, height: rect.height), colour)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

// MARK: - The frame

final class StudioFrame: NSView {
    private static let imageCaptureDate:DateFormatter = {let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.dateFormat="yyyy:MM:dd HH:mm:ss";return f}()
    typealias A = Design.App
    let library: LibraryController

    /// What the page shows and the rails point at. The levels are the schema's: a collection, a folder
    /// in it where it groups its members, a member (the app's project), and the palettes inside.
    /// A group inside a member, by the member and the group: Palettes, Typography, Information, or any of the member's own.
    enum Place: Hashable, Codable { case catalogue, collection(UUID), folder(UUID, UUID), project(UUID), overview(UUID, UUID), group(UUID, UUID), palette(UUID), palettes, projects, imageIntake, designer, settings, schema, shortcuts, halo, sounds, general, colourManagement(Int), appleMenubar, sharingSettings, qrImport, help, librarySettings, tags, lab, prepress(Int), contrast, share, appbridge, appbridgeSettings }
    private(set) var place: Place = .catalogue
    private var linkedPalettes: WorkspaceLinkedPalettes { library.store.linkedPalettes }
    private var displayLibrary: Library { library.library }
    func isLinkedPalette(_ id: UUID) -> Bool { linkedPalettes.sources[id] != nil }
    func canEditLinkedPalette(_ id: UUID) -> Bool { linkedPalettes.canEdit(id) }
    func toggleLinkedPaletteEditing(_ id: UUID) {
        do {
            let unlock = !linkedPalettes.canEdit(id)
            if !unlock, library.library.activeSwatchID == id { library.setTarget(nil) }
            try linkedPalettes.setEditing(unlock, id: id)
            library.reload()
            pageLayout.needsLayout = true
        } catch { library.flash(error.localizedDescription) }
    }
    var showsLinkedPalette: Bool { if case .palette(let id) = place { return isLinkedPalette(id) }; return false }
    private func openLinkedPalette(_ record: UUID) {
        library.reload()
        go(.palette(record))
    }

    var activeAssetFrame: StudioFrame { embeddedPage ? self : pageLayout.active.controller ?? self }
    var selectedGridPalettes: [UUID] {
        let selected=page.grid.selectedItems
        guard !selected.isEmpty, selected.allSatisfy({$0.id.flatMap{library.library.swatch($0)} != nil}) else { return [] }
        return selected.compactMap(\.id)
    }
    var commandPalettes: [UUID] {
        if !page.grid.selectedItems.isEmpty { return selectedGridPalettes }
        if case .palette(let id)=place, library.library.swatch(id) != nil { return [id] }
        return []
    }
    var canEditCommandPalettes: Bool {
        !commandPalettes.isEmpty && commandPalettes.allSatisfy { !library.isLocked(palette:$0) && (!isLinkedPalette($0) || canEditLinkedPalette($0)) }
    }
    var selectedGridMembers:[UUID] {
        let selected=page.grid.selectedItems
        guard !selected.isEmpty,selected.allSatisfy({$0.id.flatMap{library.library.project($0)} != nil}) else{return []}
        return selected.compactMap(\.id)
    }
    var canDeleteGridSelection: Bool {
        let selected=page.grid.selectedItems
        if selected.isEmpty { return false }
        if !selectedGridPalettes.isEmpty { return canEditCommandPalettes }
        if !selectedGridMembers.isEmpty {return selectedGridMembers.allSatisfy{library.library.project($0)?.isLocked != true}}
        if selected.allSatisfy({$0.hex != nil}) {
            if case .palette(let id)=place { return !library.isLocked(palette:id) && (!isLinkedPalette(id) || canEditLinkedPalette(id)) }
            return place != .appbridge
        }
        return false
    }
    func deleteGridSelection() {
        guard canDeleteGridSelection else { return }
        if !selectedGridPalettes.isEmpty { library.delete(palettes:Set(selectedGridPalettes)); return }
        if !selectedGridMembers.isEmpty {
            let ids=selectedGridMembers
            let count=ids.reduce(0){$0+library.library.palettes(in:$1).count}
            SwissConfirm.ask(over:window,title:"Delete \(ids.count) Selected Members",note:"Their \(count) palettes move to My Library. The colours remain in this catalogue.",commit:"Delete") { [weak self] in
                guard let self else{return}
                self.library.apply("Delete Selected Members") { lib in
                    for id in ids {
                        if Prefs.libraryRemoveClaimed {lib.removeClaimedCopies(assignedTo:Set(lib.palettes(in:id).map(\.id)),catalogue:self.library.catalogue)}
                        lib.deleteProject(id)
                    }
                }
            }
            return
        }
        let hexes=page.grid.selectedItems.compactMap(\.hex)
        let title="Delete \(hexes.count) Selected Swatch"+(hexes.count == 1 ? "":"es")
        if case .palette(let id)=place {
            SwissConfirm.ask(over:window,title:title,note:"Remove these \(hexes.count) swatches from this palette. Their catalogue colours remain available.",commit:"Remove") { [weak self] in self?.library.remove(hexes,from:id) }
        } else {
            SwissConfirm.ask(over:window,title:title,note:"Delete these \(hexes.count) colours from the catalogue and every palette using them.",commit:"Delete") { [weak self] in self?.library.apply("Delete Selected Swatches") { $0.deleteColours(Set(hexes)) } }
        }
    }
    private var paletteSelection = PaletteSelection()
    private var selectionHalo: HaloMenu?
    private func selectPalette(_ id: UUID, order: [UUID], modifiers: NSEvent.ModifierFlags) {
        guard library.library.swatch(id) != nil else {
            if place == .appbridge { appbridge.selected = id; reload() }; return
        }
        paletteSelection.click(id, order: order, extend: modifiers.contains(.shift), toggle: modifiers.contains(.command))
        if modifiers.intersection([.shift, .command]).isEmpty {
            if place == .contrast, contrastPage.pick(.palette(id)) { reload(); return }
            go(.palette(id))
        } else { reload() }
    }
    private func batchActions() -> [HaloAction] {
        let ids = paletteSelection.ids, lib = library.library
        let palettes = lib.swatches.filter { ids.contains($0.id) }
        guard palettes.count > 1 else { return [] }
        let star = !palettes.allSatisfy { $0.favourite }
        let locked = ids.contains { library.isLocked(palette: $0) || (isLinkedPalette($0) && !canEditLinkedPalette($0)) }
        var actions = [
            HaloAction(id:"metadata",label:"Edit Metadata…",symbol:"info.circle",disabled:locked,onSelect:{ [weak self] in self?.editMetadata(for:ids.sorted{$0.uuidString<$1.uuidString}.first) }),
            HaloAction(id: "copy-colours", label: "Copy Colours", symbol: "doc.on.doc") { [weak self] in
                guard let self else { return }; self.library.copy(Array(Set(palettes.flatMap { $0.entries.map { $0.hex } })).sorted())
            },
            HaloAction(id: "favourites", label: star ? "Add To Favourites" : "Remove From Favourites", symbol: "star", disabled: locked) { [weak self] in
                self?.library.apply(star ? "Star Selected Palettes" : "Unstar Selected Palettes") { lib in for id in ids { lib.setFavourite(id, star) } }
            },
            HaloAction(id: "copy-project", label: "Copy To Project", symbol: "folder.badge.plus", children: { [weak self] in
                guard let self else { return [] }
                return self.library.library.orderedProjects.map { project in
                    HaloAction(id: project.id.uuidString, label: project.name, symbol: "folder", disabled: project.isLocked) { [weak self] in self?.library.copy(palettes: ids, to: project.id) }
                }
            }),
            addToCollectionAction(palettes.map{.palette($0.id,name:$0.name)}),
            HaloAction(id: "delete", label: "Delete Selected Palettes", symbol: "trash", disabled: locked,
                confirmation: ("Slide to delete", "Hold the arrow key")) { [weak self] in self?.library.delete(palettes: ids, confirmed: true) }
        ]
        actions[actions.count - 1].onMenuSelect = { [weak self] in self?.library.delete(palettes: ids) }
        return actions
    }
    private func openSelectionHalo(from view: NSView, rect: NSRect) {
        let actions = batchActions(); guard !actions.isEmpty else { return }
        let halo = selectionHalo ?? HaloMenu(label: "Selected Palettes", hint: "Actions for this selection", actions: [])
        selectionHalo = halo; halo.label = "\(paletteSelection.ids.count) Palettes Selected"; halo.actions = actions
        halo.open(centredOn: rect, in: view)
    }
    private(set) var chosenHex: String?

    let header = StudioHeader()
    let rail1 = LibraryRail()
    private let settingsCurtainClip = NSView()
    private let settingsCurtain = SettingsRailCurtain()
    private var settingsReturn: Place?
    private var lastSettingsPage: Place = .settings
    private var curtainProgress: CGFloat = 0

    let rail2 = PaletteTable()
    let paletteWheel = PaletteWheel(frame: .zero)
    let page = StudioPage()
    private let embeddedPage:Bool
    private var onPaneChange:(()->Void)?
    private var onOutsidePage:((Place)->Void)?
    private let pageLayout=LibraryPageLayout(frame:.zero)
    private var routingPrimary=false
    private var sessionCatalogue: URL?
    private var restoringSession=false
    private var lastLibrarySessionLayout: WorkspaceLayoutTemplate.State?
    private var lastSessionRecord:WorkspaceSession?

    func enableSessionMemory() {
        if sessionCatalogue != library.store.url {lastLibrarySessionLayout=nil;lastSessionRecord=nil}
        sessionCatalogue=library.store.url
    }
    func saveWorkspaceSession(flush:Bool=false) {
        guard !embeddedPage,!restoringSession,splash == nil,sessionCatalogue == library.store.url,window != nil else{return}
        if libraryLayoutAvailable {lastLibrarySessionLayout=captureWorkspaceLayout(forSession:true)}
        // The library tab tree stays intact while a settings or tools page is visible.
        var state=lastLibrarySessionLayout ?? captureWorkspaceLayout(forSession:true)!
        captureSessionRails(into:&state)
        state.settings=[:];state.printProfile=nil
        let record=WorkspaceSession(route:place,layout:state,page:captureLayoutPage(),settingsReturn:settingsReturn,
            lastSettings:lastSettingsPage,railScroll:sessionRails.map(\.sessionScroll),wideLibrary:wideLibraryRailVisible,
            wideAnalysis:wideAnalysisRailVisible,compactRail:compactRailSelection,targetPane:pageLayout.targetPaneID,
            focusedFolder:cataloguePane.sessionFocusedFolder,inspectedPalette:inspectedPalette,selectedPalettes:paletteSelection.ids)
        if record == lastSessionRecord {if flush{preferences.synchronize()};return}
        do {try record.write(for:library.store.url);lastSessionRecord=record;if flush{preferences.synchronize()}}
        catch {Diagnostics.log("workspace-session",error:error)}
    }
    private var sessionRails:[WorkspaceRail] {[leftPanelRail,rightPanelRail,intakeSourceRail,intakeTargetRail]}
    private func captureSessionRails(into state:inout WorkspaceLayoutTemplate.State) {
        state.panels=[]
        for (r,rail) in sessionRails.enumerated(){for (i,panel) in rail.panels.enumerated(){state.panels.append(.init(id:panel.panelID,rail:r,order:i,closed:panel.collapsed,height:Double(panel.preferredHeight)))}}
        state.rails=[Double(goal.rail1),Double(goal.rail2),Double(goal.history)]
        state.expanded=expanded;state.pageExpanded=page.expanded;state.window=window.map{.init($0.frame)}
    }
    @discardableResult func restoreWorkspaceSession()->Bool {
        guard !embeddedPage,let saved=WorkspaceSession.read(for:library.store.url) else{return false}
        enableSessionMemory()
        restoringSession=true;defer{restoringSession=false}
        do {
            routingPrimary=true;go(.catalogue);routingPrimary=false
            wideLibraryRailVisible=saved.wideLibrary;wideAnalysisRailVisible=saved.wideAnalysis;compactRailSelection=saved.compactRail
            // Session recovery must not roll back portable colour or appearance preferences.
            try restoreWorkspaceLayout(.init(name:"Last Session",state:saved.layout),scope:.app,session:true)
            lastLibrarySessionLayout=saved.layout
            let destination:Place
            switch saved.route {
            case .palette,.project,.overview,.group,.collection,.folder:destination=resolvedLayoutRoute(saved.route)
            default:destination=saved.route
            }
            if destination != place {routingPrimary=true;go(destination);routingPrimary=false}
            settingsReturn=saved.settingsReturn;lastSettingsPage=saved.lastSettings
            if !libraryLayoutAvailable {restoreLayoutPage(saved.page)}
            slideClock?.invalidate();slideClock=nil
            goal=(CGFloat(saved.layout.rails[0]),CGFloat(saved.layout.rails[1]),CGFloat(saved.layout.rails[2]));open=goal
            cataloguePane.sessionFocusedFolder=saved.focusedFolder
            paletteSelection.ids=saved.selectedPalettes.intersection(Set(library.library.swatches.map(\.id)))
            if let id=saved.inspectedPalette,library.library.swatch(id) != nil {
                inspectedPalette=id;inspectorPane.palette=library.library.swatch(id);page.grid.selectedPalette=id
            }
            pageLayout.restoreSessionTarget(saved.targetPane)
            needsLayout=true;layoutSubtreeIfNeeded()
            pageLayout.restoreSessionViews(saved.layout.tree,includePrimary:libraryLayoutAvailable){page.restoreLayoutView($0)}
            // Reapply the active tool's scroll after rail geometry has settled.
            if !libraryLayoutAvailable {page.restoreLayoutView(saved.page)}
            for (rail,y) in zip(sessionRails,saved.railScroll){rail.sessionScroll=y}
            return true
        } catch {routingPrimary=false;Diagnostics.log("workspace-session-restore",error:error);return false}
    }
    private var libraryLayoutAvailable:Bool {
        switch place {case .catalogue,.palettes,.palette,.collection,.folder,.project,.overview,.group:return true;default:return false}
    }
    let history = HistoryRail()
    let footer = StudioFooter()
    private let cataloguePane = WorkspaceCatalogues()
    func configureAssetImport(_ form: WorkspaceImportPane) {
        form.onSourceFilesChanged = { [weak self] files in
            guard let self else{return}
            self.importRenamePane.sampleFile=files.first ?? URL(fileURLWithPath:self.importKind == "ASE" ? "Palette.ase":"Palette.colpal")
        }
        form.onOpenPalette = { [weak self] id in self?.openLinkedPalette(id) }
        form.onFilesChanged = { [weak self] in
            guard let self else{return}
            self.appbridge.reloadImportedConnections()
            self.collectionsPane.refresh()
            if self.imageIntakeWorkspace{self.intakeSourcePane.refreshSelectedSource()}
        }
        form.onOpenASE = { [weak self] url in
            guard let self else { return }; self.appbridge.openImported(url); self.go(.appbridge)
        }
    }
    private lazy var importPane = WorkspaceImportPane(controller: library)
    private lazy var collectionsPane = WorkspaceCollectionsPane(controller:library)
    private lazy var collectionsPanel:WorkspacePanel = {
        let panel=WorkspacePanel(id:"asset-collections",title:"Collections",content:collectionsPane,resizable:false)
        panel.setHeaderAction(symbol:"plus",title:"New Collection"){[weak self] in self?.collectionsPane.createCollection()}
        return panel
    }()
    private lazy var importHandlingPane:WorkspaceImportHandlingPane = {
        let pane=WorkspaceImportHandlingPane(frame:.zero)
        pane.onChange={[weak self] value in self?.importPane.skipExisting=value}
        return pane
    }()
    private lazy var importRenamePane:WorkspaceImportRenamePane = {
        let pane=WorkspaceImportRenamePane(frame:.zero)
        pane.onChange={[weak self] options in self?.importPane.renaming=options}
        return pane
    }()
    private lazy var importCollectionPane:WorkspaceImportCollectionPane = {
        let pane=WorkspaceImportCollectionPane(controller:library)
        pane.onChange={[weak self] id in self?.importPane.collectionID=id}
        pane.onCreated={[weak self] in self?.collectionsPane.refresh()}
        return pane
    }()
    private lazy var importHandlingPanel=WorkspacePanel(id:"import-file-handling",title:"File Handling",content:importHandlingPane,resizable:false,draggable:false)
    private lazy var importRenamePanel=WorkspacePanel(id:"import-file-renaming",title:"File Renaming",content:importRenamePane,resizable:false,draggable:false)
    private lazy var importCollectionPanel:WorkspacePanel = {
        let panel=WorkspacePanel(id:"import-collection",title:"Add to Collection",content:importCollectionPane,resizable:false,draggable:false)
        panel.setHeaderAction(symbol:"plus",title:"New Collection"){[weak self] in self?.importCollectionPane.createCollection()}
        return panel
    }()
    private lazy var assetImportTargetPanel:WorkspacePanel = {
        importPane.typeInActionbar=true
        let panel=WorkspacePanel(id:"asset-import-target",title:"Destination",content:importPane,resizable:false,draggable:false)
        return panel
    }()
    private let iccProfilePane=ICCProfilePanel(frame:.zero)
    private let metadataPane=AssetMetadataPanel(frame:.zero)
    private var paletteFilter=PaletteAssetHandler.Filter(order:PaletteAssetHandler.Order(rawValue:AppPreferences.shared.string(forKey:"Workspace.Library.PaletteOrder") ?? "") ?? .newest)
    private let inspectorPane = WorkspaceInspector()
    private let histogramPane=WorkspaceHistogramPane(frame:.zero)
    private let bloomPane=WorkspaceBloomPane(frame:.zero)
    private let bloomWorkspace=WorkspaceExpandedPanel(frame:.zero)
    private let expandedBloom=WorkspaceBloomPane(frame:.zero)
    private let expandedHistogram=WorkspaceHistogramPane(frame:.zero)
    private enum ExpandedAnalysis {case bloom,histogram}
    private var expandedAnalysis:ExpandedAnalysis?
    private var analysisColour:String?
    private var analysisPalettes:[Swatch]=[]
    private struct AnalysisKey:Equatable {
        let revision:Int
        let palette:UUID?
        let colour:String?
        let channel:ProfileChannel?
        let print:ProfileChannel
        let expanded:ExpandedAnalysis?
    }
    private var lastAnalysisKey:AnalysisKey?
    private let filmstrip = WorkspaceFilmstrip()
    private let designerWorkspace=DesignerWorkspace(frame:.zero)
    private var onboardingRailPrepared=false
    private let leftPanelRail = WorkspaceRail(scrollbarOnLeft:true)
    private let rightPanelRail = WorkspaceRail(scrollbarOnLeft:false)
    /// Keyboard and footer buttons share rail state, including the narrow-window single-rail layout.
    func toggleRail(_ index:Int){
        if canvasWorkspace {
            guard !imageIntakeWorkspace,place != .designer else{return}
            if WorkspaceResponsiveGeometry.singleRail(bounds.width) {
                let selected=index == 1 ? 0:1
                compactRailSelection=compactRailSelection == selected ? 2:selected
            } else if index == 1 {wideLibraryRailVisible.toggle()}
            else {wideAnalysisRailVisible.toggle()}
            needsLayout=true
        } else {
            if index == 1 {goal.rail1=goal.rail1 < 1 ? 1:0}
            else {goal.rail2=goal.rail2 < 1 ? 1:0}
            slide()
        }
    }
    private var compactRailSelection = 0 // Library / Analysis / Neither.
    private var wideLibraryRailVisible = true
    private var wideAnalysisRailVisible = true
    private let railProfile=WorkspaceRail(scrollbarOnLeft:false)
    private let profileEditor=ProfileRailPane(frame:.zero)
    private let profileHeader=WorkspacePanelHeader(frame:.zero)
    private let profileHeaderContent=NSView(frame:.zero)
    private var profileOpen:CGFloat=0,profileGoal:CGFloat=0
    private let intakeSourceRail = WorkspaceRail(scrollbarOnLeft:true)
    private let intakeTargetRail = WorkspaceRail(scrollbarOnLeft:false)
    private let intakeSourcePane = WorkspaceImageIntakePane()
    private let intakeTargetPane = WorkspaceImageDestinationPane()
    private var imageImportTargetPanel:WorkspacePanel?
    private var importKind="Palettes"
    private var importsImages:Bool{importKind == "Photographs" || importKind == "Images"}
    private var intakeAssetFiles:[URL]=[]
    private var intakeAssetPreviews:[String:[NSColor]]=[:]
    private var intakeAssetColourCounts:[String:Int]=[:]
    private var intakeReturnPlace:Place = .catalogue
    private var intakeLinking=false
    private var intakeImages:[TileGrid.Item]=[]
    private var intakeSelectedPaths=Set<String>()
    private var intakeSelectAll=true
    private var intakeNewOnly=false
    private var intakeFullView=false
    private var intakeGridColumns=5
    private var intakeSort:WorkspaceImageSort = .off
    private var intakeFolder:URL?
    private var intakeImageLoading=false
    private var intakePreviewGeneration=0
    private var intakePreviewOrder:[String]=[]
    private var intakePreviews:[String:TileGrid.Item]=[:]
    private var intakePendingBatches=0
    private var intakeScanComplete=false
    private var photoFullView=false
    private var photoSort:WorkspaceImageSort = .off
    private let photoThumbnails:NSCache<NSString,NSImage>={let cache=NSCache<NSString,NSImage>();cache.countLimit=512;cache.totalCostLimit=128*1024*1024;return cache}()
    private var failedPhotoThumbnails:[String:Date]=[:]
    private var pendingPhotoThumbnails=Set<String>()
    private let photoPreviewQueue:OperationQueue={let queue=OperationQueue();queue.name="Colorgain.PhotoLibrary.Previews";queue.qualityOfService = .userInitiated;queue.maxConcurrentOperationCount=3;return queue}()
    private let intakePreviewQueue:OperationQueue = {let q=OperationQueue();q.name="Colorgain.ImageIntake.Previews";q.qualityOfService = .userInitiated;q.maxConcurrentOperationCount=4;return q}()
    private let workspaceDragShade=WorkspaceDragShade()
    private let viewportHeader = WorkspaceViewportBar(footer: false)
    private let viewportFooter = WorkspaceViewportBar(footer: true)
    private var inspectedPalette: UUID?
    private var workspaceFilter: String?
    private var canvasWorkspace: Bool {
        switch place { case .catalogue, .palettes, .palette, .collection, .folder, .project, .overview, .group, .imageIntake, .designer: return true; default: return false }
    }
    private var imageIntakeWorkspace:Bool {place == .imageIntake}
    private func canImportImagesFromCurrentPlace()->Bool {
        guard case .group(let projectID,let nodeID)=place,
              let node=SchemaTrial.rows(of:SchemaTrial.schema(for:projectID)).first(where:{$0.node.id==nodeID})?.node else{return false}
        return node.name.trimmingCharacters(in:.whitespacesAndNewlines).caseInsensitiveCompare("Photography") == .orderedSame
            || node.kind?.trimmingCharacters(in:.whitespacesAndNewlines).caseInsensitiveCompare("Photography") == .orderedSame
            || SchemaTrial.type(of:node).caseInsensitiveCompare("Images") == .orderedSame
    }
    private func photoRecords(project:UUID,bucket:UUID)->[(WorkspaceImportedAsset,URL)] {
        WorkspaceImport.records(store:library.store).filter{record,_ in
            record.member == project && record.bucket == bucket && (record.type == "Photographs" || record.type == "Images")
        }
    }
    private func photoThumbnail(for url:URL,modifiedAt:Date?)->NSImage? {
        let path=url.standardizedFileURL.path
        let key=path+"|"+String(modifiedAt?.timeIntervalSince1970 ?? 0)
        if let cached=photoThumbnails.object(forKey:key as NSString){return cached}
        if let failed=failedPhotoThumbnails[key],Date().timeIntervalSince(failed) < 10{return nil}
        guard pendingPhotoThumbnails.count < 128 else{return nil}
        guard pendingPhotoThumbnails.insert(key).inserted else{return nil}
        photoPreviewQueue.addOperation{[weak self] in
            let source=CGImageSourceCreateWithURL(url as CFURL,nil)
            let options:[CFString:Any]=[kCGImageSourceCreateThumbnailFromImageIfAbsent:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:520]
            let thumbnail=source.flatMap{CGImageSourceCreateThumbnailAtIndex($0,0,options as CFDictionary)}
            DispatchQueue.main.async{[weak self] in
                guard let self else{return}
                self.pendingPhotoThumbnails.remove(key)
                if let thumbnail{
                    let image=NSImage(cgImage:thumbnail,size:NSSize(width:CGFloat(thumbnail.width),height:CGFloat(thumbnail.height)))
                    self.photoThumbnails.setObject(image,forKey:key as NSString,cost:thumbnail.width*thumbnail.height*4)
                } else {
                    self.failedPhotoThumbnails[key]=Date()
                    if self.failedPhotoThumbnails.count > 512 {self.failedPhotoThumbnails=self.failedPhotoThumbnails.filter{Date().timeIntervalSince($0.value)<10}}
                }
                self.page.grid.imagePreviewReady(at:path)
                // A request may have been deferred while the decode queue was full.
                self.page.grid.setNeedsDisplay(self.page.grid.visibleRect)
            }
        }
        return nil
    }
    private func loadFullPhoto(){
        guard photoFullView,let path=page.grid.currentImagePath else{return}
        if page.grid.fullResolutionPath == path{return}
        page.grid.fullResolutionImage=nil;page.grid.fullResolutionPath=path
        photoPreviewQueue.addOperation{[weak self] in
            let image=NSImage(contentsOfFile:path)
            DispatchQueue.main.async{[weak self] in
                guard let self,self.photoFullView,self.page.grid.currentImagePath == path else{return}
                self.page.grid.fullResolutionImage=image
            }
        }
    }
    private func beginImageIntake(kind:String="Palettes"){
        importKind=(WorkspaceImport.types+["Photographs","Images"]).contains(kind) ? kind:"Palettes"
        intakeReturnPlace=place;intakeLinking=false
        intakeFullView=false;page.grid.across=intakeGridColumns
        intakePreviewGeneration+=1;intakePreviewQueue.cancelAllOperations()
        intakeImages=[];intakePreviewOrder=[];intakePreviews=[:];intakePendingBatches=0;intakeScanComplete=false
        intakeFolder=nil;intakeImageLoading=false
        intakeAssetFiles=[]
        intakeAssetPreviews=[:]
        intakeAssetColourCounts=[:]
        importPane.sourceFiles=[]
        importPane.requiresGridSelection=true
        intakeTargetPane.transfer = .copy
        let preferred:(UUID,UUID)? = {if case .group(let member,let bucket)=intakeReturnPlace{return (member,bucket)};return nil}()
        intakeTargetPane.configure(library:library.library,schema:library.store.schema,preselect:preferred,catalogueName:library.store.url.deletingPathExtension().lastPathComponent,assetKind:importKind)
        configureImportTarget()
        viewportHeader.setIntakeMode(true)
        go(.imageIntake)
        intakeSourcePane.assetKind=importKind
        intakeSourcePane.openAtImportLanding()
        intakeSourcePane.refreshSelectedSource()
    }
    func openImageImport(kind:String="Palettes"){beginImageIntake(kind:kind)}
    private func configureImportTarget(){
        guard let imageImportTargetPanel else{return}
        if importsImages {
            intakeTargetRail.remove(importHandlingPanel)
            intakeTargetRail.remove(importRenamePanel)
            intakeTargetRail.remove(importCollectionPanel)
            intakeTargetRail.remove(assetImportTargetPanel)
            importCollectionPane.refresh()
            if !intakeTargetRail.panels.contains(where:{$0 === importCollectionPanel}){intakeTargetRail.add(importCollectionPanel,at:0)}
            if !intakeTargetRail.panels.contains(where:{$0 === imageImportTargetPanel}){intakeTargetRail.add(imageImportTargetPanel)}
        } else {
            intakeTargetRail.remove(imageImportTargetPanel)
            importPane.selectType(importKind)
            importCollectionPane.refresh()
            if !intakeTargetRail.panels.contains(where:{$0 === importHandlingPanel}){intakeTargetRail.add(importHandlingPanel,at:0)}
            if !intakeTargetRail.panels.contains(where:{$0 === importRenamePanel}){intakeTargetRail.add(importRenamePanel,at:1)}
            if !intakeTargetRail.panels.contains(where:{$0 === importCollectionPanel}){intakeTargetRail.add(importCollectionPanel,at:2)}
            if !intakeTargetRail.panels.contains(where:{$0 === assetImportTargetPanel}){intakeTargetRail.add(assetImportTargetPanel)}
        }
        intakeTargetRail.needsLayout=true
    }
    private func changeImportKind(_ kind:String){
        guard kind != importKind else{return}
        importKind=kind;intakeLinking=false
        intakeAssetFiles=[]
        intakeAssetPreviews=[:]
        intakeAssetColourCounts=[:]
        intakeSelectedPaths=[];intakeSelectAll=true
        importPane.sourceFiles=[]
        intakeSourcePane.assetKind=kind
        intakeTargetPane.setContext(catalogue:library.store.url.deletingPathExtension().lastPathComponent,kind:kind)
        configureImportTarget();fillPage();needsLayout=true
    }
    private func cancelImageIntake(){
        let destination=intakeReturnPlace
        viewportHeader.setIntakeMode(false)
        go(destination)
    }
    private func setImageIntakeLinking(_ linking:Bool){
        intakeLinking=linking
        intakeTargetPane.transfer=linking ? .reference:.copy
        page.grid.note=linking ? "Selected images will stay at their source locations." : "Choose a source folder and select images to add."
        page.needsDisplay=true
        page.needsLayout=true
        fillPage()
    }
    private func showIntakeImages(folder:URL?,files:[URL],event:WorkspaceImageScanEvent){
        switch event {
        case .began:
            intakePreviewGeneration+=1;intakePreviewQueue.cancelAllOperations()
            intakeFolder=folder;intakeImages=[];intakePreviewOrder=[];intakePreviews=[:]
            intakeSelectedPaths=[]
            intakePendingBatches=0;intakeScanComplete=false;intakeImageLoading=true;fillPage()
        case .batch:
            guard !files.isEmpty else{return}
            let generation=intakePreviewGeneration
            intakePreviewOrder += files.map{$0.standardizedFileURL.path}
            intakePendingBatches+=1;intakeImageLoading=true
            intakePreviewQueue.addOperation{[weak self] in
                let decoded:[(URL,Date?,[String:String])]=files.compactMap{url in
                    guard let source=CGImageSourceCreateWithURL(url as CFURL,nil) else{return nil}
                    let props=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any]
                    let exif=props?[kCGImagePropertyExifDictionary] as? [CFString:Any]
                    let tiff=props?[kCGImagePropertyTIFFDictionary] as? [CFString:Any]
                    let dateString=(exif?[kCGImagePropertyExifDateTimeOriginal] as? String) ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String)
                    var metadata=Self.flattenMetadata(props ?? [:])
                    metadata.merge(Self.readImageSidecars(for:url),uniquingKeysWith:{_,sidecar in sidecar})
                    if let doi=metadata.first(where:{$0.key.localizedCaseInsensitiveContains("doi")})?.value {metadata["DOI"]=doi}
                    return (url,dateString.flatMap{Self.imageCaptureDate.date(from:$0)},metadata)
                }
                DispatchQueue.main.async{[weak self] in
                    guard let self,self.intakePreviewGeneration==generation else{return}
                    for (url,captureDate,metadata) in decoded{
                        let path=url.standardizedFileURL.path
                        let root=self.intakeFolder?.standardizedFileURL.path
                        let relative=root.map{path.hasPrefix($0.hasSuffix("/") ? $0 : $0+"/") ? String(path.dropFirst($0.count+1)) : url.lastPathComponent} ?? url.lastPathComponent
                        let parent=(relative as NSString).deletingLastPathComponent
                        let caption=parent == "." ? "" : parent
                        let dates=try? url.resourceValues(forKeys:[.creationDateKey,.contentModificationDateKey])
                        self.intakePreviews[path]=TileGrid.Item(title:url.lastPathComponent,caption:caption,colours:[],hex:nil,id:nil,imagePath:path,captureDate:captureDate,metadata:metadata,createdAt:dates?.creationDate,modifiedAt:dates?.contentModificationDate)
                        if self.intakeSelectAll { self.intakeSelectedPaths.insert(path) }
                    }
                    self.intakePendingBatches=max(0,self.intakePendingBatches-1)
                    self.scheduleIntakeRefresh()
                }
            }
        case .completed:
            intakeScanComplete=true;scheduleIntakeRefresh()
        }
    }

    private var intakeRefreshPending=false
    private func scheduleIntakeRefresh() {
        guard !intakeRefreshPending else{return}
        intakeRefreshPending=true
        DispatchQueue.main.asyncAfter(deadline:.now()+0.05){[weak self] in
            guard let self else{return}
            self.intakeRefreshPending=false
            self.refreshIntakeImages()
        }
    }

    private func refreshIntakeImages(){
        var images=intakePreviewOrder.compactMap{intakePreviews[$0]}
        // Until catalogue membership is persisted, every file discovered in this intake is new.
        switch intakeSort {
        case .captureTime: images.sort{($0.captureDate ?? .distantPast) > ($1.captureDate ?? .distantPast)}
        case .checkedState: images.sort{intakeSelectedPaths.contains($0.imagePath ?? "") && !intakeSelectedPaths.contains($1.imagePath ?? "")}
        case .fileName: images.sort{$0.title.localizedStandardCompare($1.title) == .orderedAscending}
        case .fileType: images.sort{URL(fileURLWithPath:$0.title).pathExtension.localizedCaseInsensitiveCompare(URL(fileURLWithPath:$1.title).pathExtension) == .orderedAscending}
        case .mediaType: images.sort{isRawImage($0.title) && !isRawImage($1.title)}
        case .off: break
        }
        intakeImages=images
        intakeImageLoading = !intakeScanComplete || intakePendingBatches > 0
        fillPage()
    }
    private func visibleImportFiles()->[URL] {
        let known=intakeNewOnly ? WorkspaceImport.seenSources(in:library.store.root):[]
        var files=intakeAssetFiles.filter{!known.contains($0.standardizedFileURL.path)}
        switch intakeSort {
        case .checkedState:
            files=files.enumerated().sorted{a,b in
                let selectedA=intakeSelectedPaths.contains(a.element.standardizedFileURL.path)
                let selectedB=intakeSelectedPaths.contains(b.element.standardizedFileURL.path)
                return selectedA == selectedB ? a.offset < b.offset:selectedA
            }.map(\.element)
        case .fileName:files.sort{$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending}
        case .fileType:files.sort{a,b in
            let order=a.pathExtension.localizedCaseInsensitiveCompare(b.pathExtension)
            return order == .orderedSame ? a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending:order == .orderedAscending
        }
        default:break
        }
        return files
    }
    /// Selection is independent of the preview dataset and its current order/scroll position.
    private func updateIntakeSelection(){
        page.grid.selectedImagePaths=intakeSelectedPaths
        if !importsImages {
            importPane.sourceFiles=visibleImportFiles().filter{intakeSelectedPaths.contains($0.standardizedFileURL.path)}
        }
        intakeTargetPane.selectedCount=intakeSelectedPaths.count
        for bar in [viewportHeader,viewportFooter] {
            bar.configureImageIntake(imageIntakeWorkspace,kind:importKind,linking:intakeLinking,selectAll:intakeSelectAll,newOnly:intakeNewOnly,fullView:intakeFullView,sort:intakeSort,imageCount:importsImages ? intakeImages.count:visibleImportFiles().count,selectedCount:intakeSelectedPaths.count,columns:intakeGridColumns)
        }
    }
    /// File-card previews are optional; selecting and importing can proceed while they load.
    private func previewIntakeAssets(_ files:[URL]){
        guard importKind == "Palettes",!files.isEmpty else{return}
        let generation=intakePreviewGeneration
        intakePreviewQueue.addOperation{[weak self] in
            let previews:[(String,[String],Int)]=files.compactMap{url in
                guard let size=(try? url.resourceValues(forKeys:[.fileSizeKey]))?.fileSize,size<=16*1024*1024,
                      let data=try? Data(contentsOf:url) else{return nil}
                let palette=PaletteImport.read(data,fallback:url.deletingPathExtension().lastPathComponent)
                let colours=palette.flatMap{$0.colours.map(\.hex)}
                return (url.standardizedFileURL.path,Array(colours.prefix(colours.count <= 10 ? 10:8)),colours.count)
            }
            DispatchQueue.main.async{[weak self] in
                guard let self,self.intakePreviewGeneration==generation,self.imageIntakeWorkspace else{return}
                for (path,hexes,count) in previews{self.intakeAssetPreviews[path]=hexes.map(Design.hex);self.intakeAssetColourCounts[path]=count}
                self.fillPage()
            }
        }
    }
    private func isRawImage(_ name:String)->Bool { UTType(filenameExtension:URL(fileURLWithPath:name).pathExtension)?.conforms(to:.rawImage) == true }
    private static func flattenMetadata(_ value:Any,prefix:String="")->[String:String]{
        var result:[String:String]=[:]
        if let dictionary=value as? [AnyHashable:Any]{
            for (key,value) in dictionary{let name=prefix.isEmpty ? String(describing:key):"\(prefix).\(key)";result.merge(flattenMetadata(value,prefix:name),uniquingKeysWith:{_,new in new})}
        }else if let array=value as? [Any]{for (i,value) in array.enumerated(){result.merge(flattenMetadata(value,prefix:"\(prefix)[\(i)]"),uniquingKeysWith:{_,new in new})}}
        else if let string=value as? String{result[prefix]=string}
        else if let number=value as? NSNumber{result[prefix]=number.stringValue}
        return result
    }
    private static func readImageSidecars(for image:URL)->[String:String]{
        var result:[String:String]=[:]
        let maximumSidecarBytes=2*1024*1024
        for ext in ["json","xml","xmp","csv","tsv"]{
            let url=image.deletingPathExtension().appendingPathExtension(ext)
            guard let size=try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize else{continue}
            guard size <= maximumSidecarBytes else{result["Sidecar.\(ext).Error"]="File exceeds 2 MB";continue}
            guard let data=try? Data(contentsOf:url) else{result["Sidecar.\(ext).Error"]="Could not read file";continue}
            switch ext{
            case "json":
                if let object=try? JSONSerialization.jsonObject(with:data){result.merge(flattenMetadata(object)){_,new in new}}
                else{result["Sidecar.json.Error"]="Invalid JSON"}
            case "csv","tsv":
                guard let text=String(data:data,encoding:.utf8) else{result["Sidecar.\(ext).Error"]="Invalid text encoding";continue}
                let rows=text.components(separatedBy:.newlines).filter{!$0.isEmpty}.map{$0.components(separatedBy:ext == "tsv" ? "\t":",")}
                guard rows.count>1 else{continue}
                for row in rows.dropFirst(){for column in 0..<min(rows[0].count,row.count){result["Sidecar.\(rows[0][column].trimmingCharacters(in:.whitespacesAndNewlines))"] = row[column].trimmingCharacters(in:.whitespacesAndNewlines)}}
            default:
                if let text=String(data:data,encoding:.utf8){result.merge(parseXMLMetadata(text)){_,new in new}}
            }
        }
        return result
    }
    private static func parseXMLMetadata(_ text:String)->[String:String]{
        guard let data=text.data(using:.utf8),let document=try? XMLDocument(data:data,options:[]) else{return [:]}
        var values:[String:String]=[:]
        for node in (try? document.rootElement()?.nodes(forXPath:".//*")) ?? []{
            guard let element=node as? XMLElement,let value=element.stringValue?.trimmingCharacters(in:.whitespacesAndNewlines),!value.isEmpty else{continue}
            values["Sidecar.\(element.name ?? "value")"]=value
        }
        return values
    }
    private var paletteGridReturn:(route:Place,view:WorkspaceLayoutTemplate.Page,selected:UUID,filter:PaletteAssetHandler.Filter)?
    @objc private func backToPaletteGrid(){
        guard let saved=paletteGridReturn else{return}
        inspectedPalette=saved.selected
        go(saved.route)
        restoreLayoutPage(saved.view)
        paletteFilter=saved.filter;fillPage();page.layoutSubtreeIfNeeded();page.restoreLayoutView(saved.view)
        page.grid.selectedPalette=saved.selected
    }
    private func inspectPalette(_ id: UUID) {
        if inspectedPalette != id { analysisColour=nil }
        inspectedPalette = id
        inspectorPane.palette = displayLibrary.swatch(id)
        page.grid.selectedPalette = id
        viewportHeader.channels.configure(library:displayLibrary,palette:id)
        if viewportHeader.channels.selectedChannel != nil { fillPage() } else { refreshAnalysis() }
        filmstrip.update(palettes(displayLibrary.swatches), selected: id, colours: shade)
    }
    /// Master Inner over everything: the columns and the beat, in the grid's orange, when it is on.
    let overlay = GridOverlay()
    /// The invisible strip across the top, around the window's three buttons: a press on it drags the window, and the pointer says so.
    let strip = TitleStrip()
    /// Contrast, drawn on the page's columns; kept here so the window can open it on a typography palette.
    let contrastPage: ContrastPage
    /// Export and Import as a wizard in the page (StudioShare.swift), begun from a palette's halo, a page's Export or the catalogue settings.
    let sharePage: SharePage
    /// PrePress: the four print workflows as routes, each a page of steps (PrePress.swift).
    private let printPaletteRail = LibraryRail()
    private var printWorkspace: Bool { place == .prepress(PrePressPage.Flow.print.rawValue) }
    let prePressPage: PrePressPage
    private var beforePrePressRail: CGFloat = 1
    private var beforeHelp: (rail1: CGFloat, rail2: CGFloat, history: CGFloat)?
    let appbridge = AppbridgeStore()
    /// How open each panel is, 0 to 1, and where each is going: the frame is laid out from these, and the clock slides them.
    private var open = (rail1: CGFloat(1), rail2: CGFloat(1), history: CGFloat(0))
    private var goal = (rail1: CGFloat(1), rail2: CGFloat(1), history: CGFloat(0))
    private var slideClock: Timer?
    private var lastSlide = Date()
    private var expanded = false
    private var beforeWheel: (rails: (rail1: CGFloat, rail2: CGFloat, history: CGFloat), expanded: Bool, pageExpanded: Bool)?

    @objc private func iccLibraryChanged(){fillPage()}

    init(library: LibraryController, embeddedPage:Bool=false) {
        self.embeddedPage=embeddedPage
        self.library = library
        contrastPage = ContrastPage(library: library)
        sharePage = SharePage(library: library)
        prePressPage = PrePressPage(library: library)
        super.init(frame: NSRect(origin: .zero, size: A.size))
        wantsLayer = true
        layer?.backgroundColor = Design.paper.cgColor
        for v in [rail1, rail2, page, history, printPaletteRail, footer, strip, header, paletteWheel, overlay] { addSubview(v) }
        for view in [leftPanelRail, rightPanelRail, railProfile, intakeSourceRail, intakeTargetRail, filmstrip, viewportHeader, viewportFooter] { addSubview(view) }
        let cataloguesPanel=WorkspacePanel(id: "catalogues", title: WorkspaceSidebarStructure.title, content: cataloguePane,resizable:false)
        cataloguePane.setCatalogueAction { [weak self] in self?.locateWorkspaceCatalogue() }
        leftPanelRail.add(cataloguesPanel)
        leftPanelRail.add(collectionsPanel)
        collectionsPane.onOpenAsset={[weak self] item in self?.openCollectedAsset(item)}
        collectionsPane.onFavourite = { [weak self] id in self?.library.toggleFavourite(id) }
        collectionsPane.onRename = { [weak self] id,name in self?.library.rename(id,to:name) }
        collectionsPane.onTarget = { [weak self] id in guard let self else{return};self.library.setTarget(self.library.library.activeSwatchID == id ? nil:id) }
        collectionsPane.onRating = { [weak self] id,rating in self?.library.apply("Rate Palette"){PaletteAssetHandler.setRating(rating,on:id,in:&$0)} }
        collectionsPane.onFlag = { [weak self] id,flag in self?.library.apply("Flag Palette"){PaletteAssetHandler.setFlag(flag,on:id,in:&$0)} }
        collectionsPane.onColourChanged = { [weak self] in
            guard let self else{return}
            self.cataloguePane.configureCollections(AssetCollections.list(in:self.library.store),linkedPaletteRecords:self.linkedPalettes.sources.mapValues{$0.record.id})
        }
        collectionsPane.onChanged = { [weak self] in
            guard let self else{return}
            self.cataloguePane.configureCollections(AssetCollections.list(in:self.library.store),linkedPaletteRecords:self.linkedPalettes.sources.mapValues{$0.record.id})
        }
        cataloguePane.onImportLibrary = { [weak self] in guard let self else{return};MyLibraryFile.chooseImport(library:self.library,over:self) }
        cataloguePane.onExportLibrary = { [weak self] in guard let self else{return};MyLibraryFile.chooseExport(over:self) }
        cataloguePane.onCreateClient = { [weak self] in guard let self else{return};CatalogueJourneyView.present(library:self.library,over:self,kind:"client") }
        cataloguePane.onCreateWork = { [weak self] client in guard let self else{return};CatalogueJourneyView.present(library:self.library,over:self,client:client,kind:"work") }
        cataloguePane.onAssetContext = { [weak self] id, view, point in self?.openContext(.palette(id), in: view, at: point) }
        cataloguePane.onOpenImportedAsset = { [weak self] id in self?.importPane.open(id: id) }
        configureAssetImport(importPane)
        cataloguePane.installICCProfiles(iccProfilePane)
        rightPanelRail.add(WorkspacePanel(id:"metadata",title:"Metadata",content:metadataPane,resizable:false))
        metadataPane.onEdit={ [weak self] id in self?.editMetadata(for:id) }
        metadataPane.onSettings={ (NSApp.delegate as? AppDelegate)?.showMetadataSettings() }
        iccProfilePane.onTarget = { [weak self] profile in
            if !ICCProfileLibrary.shared.profiles.contains(where:{$0.id == profile.id}) {ICCProfileLibrary.shared.add([profile])}
            self?.viewportHeader.channels.useICC(profile);self?.fillPage()
        }
        iccProfilePane.onCollectionActions={[weak self] profile in
            self?.addToCollectionAction(.init(kind:"ICC Profile",identity:profile.id,name:profile.name)) ?? HaloAction(id:"collections",label:"Add To Collection",symbol:"square.grid.2x2",disabled:true)
        }
        viewportHeader.channels.onLocateICC = { [weak self] id in self?.cataloguePane.revealICCProfiles();DispatchQueue.main.async { [weak self] in self?.iccProfilePane.locate(id) } }
        NotificationCenter.default.addObserver(self,selector:#selector(iccLibraryChanged),name:ICCProfileLibrary.changed,object:nil)
        let histogramPanel=WorkspacePanel(id:"histograms",title:"Histograms · Channel Levels",content:histogramPane,resizable:false)
        histogramPanel.setHeaderAction(symbol:"slider.horizontal.3",title:"Configure Viewing Proof"){[weak self] in self?.showProfileRail()};rightPanelRail.add(histogramPanel)
        let proofPanel=WorkspacePanel(id:"railProfile",title:"Viewing Proof Profiles",content:profileEditor,resizable:false,draggable:false)
        proofPanel.fillsRail=true;proofPanel.setHeaderAction(symbol:"xmark",title:"Close Viewing Proof Profiles"){[weak self] in self?.profileGoal=0;if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion{self?.profileOpen=0;self?.needsLayout=true}else{self?.slide()}};railProfile.add(proofPanel)
        NotificationCenter.default.addObserver(self,selector:#selector(openProfileRail(_:)),name:.openProfileRail,object:nil)
        let bloomPanel=WorkspacePanel(id:"bloom",title:"Delta Bloom · Output Difference",content:bloomPane,resizable:false)

        bloomPanel.setHeaderAction(symbol:"slider.horizontal.3",title:"Configure Viewing Proof"){[weak self] in self?.showProfileRail()};rightPanelRail.add(bloomPanel)
        let inspectorPanel=WorkspacePanel(id:"inspector",title:"Inspector",content:inspectorPane)
        inspectorPanel.collapsed=true;rightPanelRail.add(inspectorPanel)
        let sourcePanel=WorkspacePanel(id:"image-source",title:"Source",content:intakeSourcePane)
        sourcePanel.fillsRail=true;sourcePanel.pinsHeader=true
        sourcePanel.setHeaderAction(symbol:"plus",title:"Choose Folder…") { [weak self] in self?.intakeSourcePane.chooseFolder() }
        intakeSourceRail.add(sourcePanel)
        let destinationPanel=WorkspacePanel(id:"image-target",title:"Destination",content:intakeTargetPane)
        destinationPanel.fillsRail=true;destinationPanel.pinsHeader=true
        imageImportTargetPanel=destinationPanel
        intakeTargetRail.add(destinationPanel)
        intakeTargetPane.onAdd={ [weak self] destination,transfer in self?.importSelectedImages(to:destination,transfer:transfer) }
        intakeTargetPane.onTransfer={ [weak self] transfer in guard let self else{return};self.intakeLinking=transfer == .reference;self.fillPage() }
        intakeSourcePane.onImageFiles = { [weak self] folder, files, event in
            guard let self,self.imageIntakeWorkspace else{return}
            if self.importsImages {self.showIntakeImages(folder:folder,files:files,event:event)}
            else {
                switch event {
                case .began:
                    self.intakePreviewGeneration+=1;self.intakePreviewQueue.cancelAllOperations()
                    self.intakeFolder=folder;self.intakeAssetFiles=[];self.intakeAssetPreviews=[:];self.intakeAssetColourCounts=[:]
                    self.intakeSelectedPaths=[];self.intakeSelectAll=true
                case .batch:
                    self.intakeAssetFiles += files
                    if self.intakeSelectAll {
                        let seen=self.intakeNewOnly ? WorkspaceImport.seenSources(in:self.library.store.root):[]
                        self.intakeSelectedPaths.formUnion(files.map{$0.standardizedFileURL.path}.filter{!seen.contains($0)})
                    }
                    self.previewIntakeAssets(files)
                case .completed:break
                }
                self.updateIntakeSelection()
                self.fillPage()
            }
        }
        addSubview(designerWorkspace);designerWorkspace.isHidden=true
        addSubview(bloomWorkspace);bloomWorkspace.isHidden=true
        expandedBloom.expanded=true;expandedHistogram.expanded=true
        bloomPane.expandButton.run = { [weak self] in self?.expandAnalysis(.bloom) }
        histogramPane.expandButton.run = { [weak self] in self?.expandAnalysis(.histogram) }
        histogramPane.onConfiguration = { [weak self] in guard let self else{return}; self.expandedHistogram.copyConfiguration(from:self.histogramPane) }
        expandedHistogram.onConfiguration = { [weak self] in guard let self else{return};self.histogramPane.copyConfiguration(from:self.expandedHistogram) }
        expandedHistogram.onColour = { [weak self] key in self?.analysisColour=key;self?.refreshAnalysis() }
        bloomPane.onConfiguration = { [weak self] in self?.refreshAnalysis() }
        expandedBloom.onConfiguration = { [weak self] in self?.refreshAnalysis() }
        bloomWorkspace.onClose = { [weak self] in _ = self?.closeExpandedPanel() }
        bloomWorkspace.onPick = { [weak self] in self?.inspectPalette($0) }
        histogramPane.onColour = { [weak self] key in self?.analysisColour=key;self?.refreshAnalysis() }
        for chart in [bloomPane.chart,expandedBloom.chart] {chart.onSelect = { [weak self] key in self?.analysisColour=key;self?.refreshAnalysis() }}
        addSubview(profileHeader);profileHeader.addSubview(profileHeaderContent);profileHeaderContent.addSubview(viewportHeader.channels);viewportHeader.channels.headerMode=true
        if !embeddedPage {
            header.layoutControl.capture={ [weak self] in self?.captureWorkspaceLayout() }
            header.layoutControl.restore={ [weak self] record,scope in try self?.restoreWorkspaceLayout(record,scope:scope) }
        }
        viewportHeader.channels.onChange = { [weak self] in self?.page.grid.invalidatePrintPreviews();self?.fillPage();self?.pageLayout.refreshPages() }
        page.importPanel.onImport = { [weak self] in self?.beginImageIntake(kind:"Photographs") }
        viewportHeader.onImportLinking = { [weak self] linking in self?.setImageIntakeLinking(linking) }
        viewportHeader.onSelectAllImages = { [weak self] select in
            guard let self else{return};self.intakeSelectAll=select
            if select { self.intakeSelectedPaths.formUnion(self.importsImages ? self.intakePreviewOrder:self.visibleImportFiles().map{$0.standardizedFileURL.path}) } else { self.intakeSelectedPaths=[] }
            self.updateIntakeSelection()
        }
        viewportHeader.onImageFilter = { [weak self] newOnly in
            guard let self else{return};self.intakeNewOnly=newOnly
            if !self.importsImages {
                self.intakeSelectedPaths.formIntersection(Set(self.visibleImportFiles().map{$0.standardizedFileURL.path}))
                self.updateIntakeSelection();self.fillPage()
            } else {self.refreshIntakeImages()}
        }
        viewportHeader.onImageSort = { [weak self] sort in
            guard let self else{return};self.intakeSort=sort
            if self.importsImages{self.refreshIntakeImages()}else{self.fillPage()}
        }
        viewportHeader.onImageView = { [weak self] full in
            guard let self else{return};self.intakeFullView=full;self.page.grid.imageFullView=full
            if full {self.window?.makeFirstResponder(self.page.grid)}
            self.page.needsLayout=true
        }
        viewportHeader.onImportType = { [weak self] kind in self?.changeImportKind(kind) }
        viewportFooter.onImageView = { [weak self] full in
            guard let self else{return}
            if self.imageIntakeWorkspace {self.viewportHeader.onImageView?(full);return}
            guard self.canImportImagesFromCurrentPlace() else{return}
            self.photoFullView=full;self.page.grid.imageFullView=full
            self.viewportFooter.configureImageBrowser(active:true,fullView:full,index:self.page.grid.currentImageIndex+1,total:self.page.grid.items.count,sort:self.photoSort)
            if full{self.window?.makeFirstResponder(self.page.grid);self.loadFullPhoto()}
            self.page.needsLayout=true
        }
        viewportFooter.onImagePage = { [weak self] offset in self?.page.grid.changeImagePage(offset) }
        page.grid.onImagePageChanged = { [weak self] index,total in
            guard let self,self.canImportImagesFromCurrentPlace() else{return}
            self.viewportFooter.configureImageBrowser(active:true,fullView:self.photoFullView,index:index,total:total,sort:self.photoSort)
            self.loadFullPhoto()
        }
        viewportFooter.onImageSort = { [weak self] sort in
            guard let self else{return}
            if self.canImportImagesFromCurrentPlace(){self.photoSort=sort;self.fillPage()}
            else{self.viewportHeader.onImageSort?(sort)}
        }
        viewportHeader.onMetadataFilter = { [weak self] in self?.page.toggleMetadataFilter() }
        if CommandLine.arguments.contains("--ui-test-panels") {
            WorkspacePanelUITest.load(into:[leftPanelRail,rightPanelRail])
        }
        addSubview(workspaceDragShade);workspaceDragShade.isHidden=true
        for rail in [leftPanelRail,rightPanelRail] {
            rail.onDragging = { [weak self] dragging in self?.workspaceDragShade.isHidden = !dragging }
        }
        page.grid.onSelectionChanged = { [weak self] in
            guard let self else { return }
            self.viewportFooter.setSelectionCount(self.page.grid.selectedCount,total:self.page.grid.items.count)
        }
        page.grid.onSelectionEdited = { [weak self] in guard let self else{return};self.paletteSelection.ids=Set(self.selectedGridPalettes) }
        page.grid.onDeleteSelection = { [weak self] in self?.deleteGridSelection() }
        page.grid.onCopySelection = { [weak self] in
            guard let self else{return}
            let selected=self.page.grid.selectedItems
            let keys=selected.flatMap{ item -> [String] in
                if let hex=item.hex{return [hex]}
                return item.id.flatMap{self.library.library.swatch($0)}?.entries.map(\.hex) ?? []
            }
            if !keys.isEmpty {var seen=Set<String>();self.library.copy(keys.filter{seen.insert($0).inserted})}
        }
        page.workspaceToolbar = viewportFooter
        page.workspaceActionbar = viewportHeader
        viewportHeader.onAssetOrder = { [weak self] order in self?.page.assetOrder=order;self?.needsLayout=true }
        let setPaletteFilter:(PaletteAssetHandler.Filter)->Void={ [weak self] value in
            guard let self else{return};self.paletteFilter=value
            AppPreferences.shared.set(value.order.rawValue,forKey:"Workspace.Library.PaletteOrder")
            self.reload();self.needsLayout=true
        }
        cataloguePane.onPaletteFilter=setPaletteFilter
        page.paletteFilters.showsOrder=false
        page.paletteFilters.onChange=setPaletteFilter
        viewportFooter.onMode = { [weak self] list in self?.closeExpandedPanel(); self?.page.grid.listView = list; self?.page.needsLayout = true }
        viewportFooter.onLibraryRail = { [weak self] in self?.toggleRail(1) }
        viewportFooter.onAnalysisRail = { [weak self] in self?.toggleRail(2) }
        cataloguePane.onPick = { [weak self] in self?.go($0) }
        cataloguePane.onReorderAsset = { [weak self] action in
            guard let self else{return}
            switch action {
            case .library(let visible):
                let assets=GlobalAssets(home:Catalogues.standard.root)
                let original=assets.assetTypes
                let ordered=visible+original.filter{!visible.contains($0)}
                do {
                    try assets.setAssetTypes(ordered)
                    AppPreferences.shared.set(true,forKey:"Workspace.AssetTree.ManualOrder.Library")
                } catch {NSApp.presentError(error);return}
            case .catalogue(let project,let ids):
                let positions=Dictionary(uniqueKeysWithValues:ids.enumerated().map{($0.element,$0.offset)})
                func reordered(_ original:SchemaNode)->SchemaNode {
                    var node=original
                    if node.kind == "Simple Assets" {
                        node.children.sort{(positions[$0.id] ?? Int.max) < (positions[$1.id] ?? Int.max)}
                    } else {node.children=node.children.map(reordered)}
                    return node
                }
                var file=SchemaTrial.schema(for:self.library.store.root) ?? SchemaTrial.read(in:self.library.store.root)
                var stacks=file.stacks ?? [:]
                stacks[project.uuidString]=reordered(SchemaTrial.schema(for:project))
                file.stacks=stacks
                do {try self.library.store.save(self.library.library,schema:file)}
                catch {NSApp.presentError(error);return}
                AppPreferences.shared.set(true,forKey:"Workspace.AssetTree.ManualOrder."+project.uuidString)
            }
            self.library.reload();self.reload();self.needsLayout=true
        }
        cataloguePane.onFavourite = { [weak self] id in self?.library.toggleFavourite(id) }
        cataloguePane.onRename = { [weak self] id,name in self?.library.rename(id,to:name) }
        cataloguePane.onTarget = { [weak self] id in guard let self else{return};self.library.setTarget(self.library.library.activeSwatchID == id ? nil:id) }
        cataloguePane.onRating = { [weak self] id,rating in self?.library.apply("Rate Palette"){PaletteAssetHandler.setRating(rating,on:id,in:&$0)} }
        cataloguePane.onFlag = { [weak self] id,flag in self?.library.apply("Flag Palette"){PaletteAssetHandler.setFlag(flag,on:id,in:&$0)} }
        cataloguePane.onFilter = { [weak self] key in
            guard let self else { return }; self.workspaceFilter=key; self.place = .palettes; self.reload(); self.needsLayout=true
        }
        cataloguePane.onCatalogueAction = { [weak self] name,action in
            guard let self,let window=self.window else{return}
            CatalogueRowActions.perform(action,name:name,library:self.library,window:window) { [weak self] in self?.needsLayout=true;if let library=self?.library {NotificationCenter.default.post(name:.appStateDidChange,object:library)} }
        }
        cataloguePane.onCatalogue = { [weak self] name in self?.library.open(catalogue: name); self?.go(.catalogue) }
        filmstrip.onPick = { [weak self] id in self?.go(.palette(id)) }
        inspectorPane.onOpen = { [weak self] in guard let self, let id = self.inspectedPalette else { return }; self.go(.palette(id)) }
        inspectorPane.onTarget = { [weak self] in guard let self, let id = self.inspectedPalette else { return }; self.library.setTarget(id) }
        if !embeddedPage {
        var previousSurfaces = Design.surfaceColours
        NotificationCenter.default.addObserver(forName: .themeDidChange, object: nil, queue: .main) { _ in
            Design.refreshSurfaces(from: previousSurfaces)
            previousSurfaces = Design.surfaceColours
        }
        }
        settingsCurtainClip.wantsLayer = true
        settingsCurtainClip.layer?.masksToBounds = true
        settingsCurtainClip.isHidden = true
        addSubview(settingsCurtainClip, positioned: .above, relativeTo: rail1)
        settingsCurtainClip.addSubview(settingsCurtain)
        paletteWheel.onPresent = { [weak self] in
            guard let self else { return }
            self.beforeWheel = (self.goal, self.expanded, self.page.expanded)
            self.expanded = true; self.page.expanded = true
            self.goal = (0, 0, 0)
            self.slide()
        }
        paletteWheel.onDismiss = { [weak self] in
            guard let self, let previous = self.beforeWheel else { return }
            self.beforeWheel = nil
            self.goal = previous.rails
            self.expanded = previous.expanded; self.page.expanded = previous.pageExpanded
            self.slide()
        }
        header.onPaletteWheel = { [weak self] in self?.paletteWheel.present() }
        paletteWheel.backdropView = page
        paletteWheel.items = { [weak self] in
            guard let self else { return [] }
            return self.library.library.swatches.filter { !$0.isTypography }.map { palette in
                PaletteWheel.Item(id: palette.id, name: palette.name, colours: palette.entries.map { self.shade[$0.hex] ?? Design.hex($0.hex) }, details: palette.entries.map { PaletteWheel.ColourDetail(name: self.library.library.name(of: $0.hex, in: palette.id), hex: displayHex($0.hex)) })
            }
        }
        paletteWheel.currentID = { [weak self] in
            guard let self else { return nil }
            if let target = self.library.library.activeSwatchID,
               let palette = self.library.library.swatch(target), !palette.isTypography { return target }
            if case .palette(let id) = self.place { return id }
            return nil
        }
        paletteWheel.onOpen = { [weak self] id in
            guard let self, self.library.library.swatch(id) != nil else { return }
            self.go(.palette(id))
        }
        header.onTab = { [weak self] i in
            guard let self else{return}
            if i == 8 {self.go(.designer);return}
            if i == 7 {if !self.imageIntakeWorkspace {self.beginImageIntake()};return}
            self.go([Place.catalogue, .palettes, .lab, .prepress(0), .contrast, .projects, .appbridge][i])
        }
        header.onSettings = { [weak self] in
            guard self != nil else { return }
            (NSApp.delegate as? AppDelegate)?.showSettings()
        }
        page.add(StudioHelpPage(), as: .help)
        header.searchStorageKey = "Studio.Searches." + library.catalogue
        header.onSearch = { [weak self] _ in self?.scheduleSearchRefresh() }
        header.onSearchCommitted = { [weak self] in self?.fillHistory() }
        header.searchResults = { [weak self] query in
            guard let self else { return [] }
            let lib = self.library.library
            func matches(_ value: String) -> Bool { value.localizedCaseInsensitiveContains(query) }
            var results: [StudioHeader.SearchResult] = []
            for palette in lib.listedPalettes where matches(palette.name) {
                results.append(.init(title: palette.name, detail: "Palette", select: { [weak self] in self?.go(.palette(palette.id)) }))
            }
            for project in lib.orderedProjects where matches(project.name) {
                results.append(.init(title: project.name, detail: "Project", select: { [weak self] in self?.go(.project(project.id)) }))
            }
            for file in self.appbridge.files where matches(file.url.lastPathComponent) {
                results.append(.init(title: file.url.lastPathComponent, detail: "ASE File", select: { [weak self] in self?.appbridge.selected = file.id; self?.go(.appbridge) }))
            }
            for hex in lib.catalogueHexes(by: self.library.paletteSort) {
                let name = lib.name(of: hex, in: nil)
                guard matches(name) || matches(hex) else { continue }
                results.append(.init(title: name, detail: displayHex(hex), select: { [weak self] in
                    guard let self else { return }
                    self.go(.catalogue); self.choose(hex)
                    self.layoutSubtreeIfNeeded(); self.page.grid.reveal(hex)
                }))
                if results.count >= 100 { break }
            }
            return Array(results.prefix(100))
        }

        page.onAcross = { [weak self] n in
            guard let self else{return};self.page.grid.across=n
            if self.imageIntakeWorkspace && !self.intakeFullView {self.intakeGridColumns=n;self.page.grid.needsLayout=true}
        }
        page.grid.onImageSelectionChanged = { [weak self] paths in
            guard let self else { return }
            self.intakeSelectedPaths=paths
            let available=self.importsImages ? self.intakePreviewOrder:self.visibleImportFiles().map{$0.standardizedFileURL.path}
            self.intakeSelectAll = !available.isEmpty && available.allSatisfy(paths.contains)
            self.updateIntakeSelection()
        }
        page.grid.onImageSelectionToggle = { [weak self] path in
            guard let self else{return}
            if self.intakeSelectedPaths.contains(path){self.intakeSelectedPaths.remove(path)}else{self.intakeSelectedPaths.insert(path)}
            let available=self.importsImages ? self.intakePreviewOrder:self.visibleImportFiles().map{$0.standardizedFileURL.path}
            self.intakeSelectAll = !available.isEmpty && available.allSatisfy(self.intakeSelectedPaths.contains)
            self.updateIntakeSelection()
        }
        page.grid.onImageContextAction = { [weak self] path, action in
            guard let self else{return}
            switch action {
            case 0:
                self.intakeSelectedPaths.insert(path)
                self.intakeSelectAll = !self.intakePreviewOrder.isEmpty && self.intakePreviewOrder.allSatisfy(self.intakeSelectedPaths.contains)
                self.updateIntakeSelection()
            case 1:
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:path)])
            case 2:
                if self.imageIntakeWorkspace {self.intakeFullView=true}else{self.photoFullView=true}
                self.page.grid.showImageFull(path);self.page.needsLayout=true;self.fillPage()
                if !self.imageIntakeWorkspace {self.loadFullPhoto()}
            case 3:
                if self.imageIntakeWorkspace {self.intakeFullView=false}else{self.photoFullView=false}
                self.page.grid.imageFullView=false;self.fillPage()
            default:break
            }
        }
        page.grid.onImageContextActions = { [weak self] path in self?.imageContextActions(for: path) ?? [] }
        page.grid.onImageHalo = { [weak self] path, rect in self?.openImageHalo(for: path, rect: rect) }
        page.grid.onNotes = { [weak self] item in self?.openNotes(for: item) }
        page.grid.onTags = { [weak self] item in
            if let id=item.id {self?.tag(palette:id)}
            else if let hex=item.hex {self?.tag(swatches:[hex])}
        }
        rail1.onPaletteSelection = { [weak self] id, order, modifiers in self?.selectPalette(id, order: order, modifiers: modifiers) }
        rail2.onPaletteSelection = { [weak self] id, order, modifiers in self?.selectPalette(id, order: order, modifiers: modifiers) }
        rail1.onDeleteSelection = { [weak self] in guard let self else { return }; self.library.delete(palettes: self.paletteSelection.ids) }
        rail2.onDeleteSelection = rail1.onDeleteSelection
        rail1.onSelectionHalo = { [weak self] view, rect in self?.openSelectionHalo(from: view, rect: rect) }
        rail1.onPick = { [weak self] p in self?.go(p) }
        rail1.onArrow = { [weak self] in guard let self = self else { return }; self.goal.rail1 = self.goal.rail1 < 1 ? 1 : 0; self.slide() }
        rail2.arrow = .none
        history.arrow = .close
        history.onArrow = { [weak self] in self?.goal.history = 0; self?.slide() }
        header.onHistory = { [weak self] in guard let self = self else { return }; self.goal.history = self.goal.history < 1 ? 1 : 0; self.slide() }
        page.onArrow = { [weak self] in
            guard let self = self else { return }
            // The page takes the whole width: the history goes, rail2 goes, rail1 shuts; the arrow back gives the rails their width.
            self.expanded.toggle()
            self.page.expanded = self.expanded
            if self.expanded { self.goal = (0, 0, 0) } else { self.goal = (1, self.railTwo, self.goal.history) }
            self.slide()
        }
        // Dropping into the tree updates the library without navigating away from the source palette list.
        rail1.onDrop = { [weak self] palette, destination in
            guard let self = self else { return }
            // The Library policy determines source retention; the exact destination survives the drop.
            self.library.assignPalette(palette, to: destination.project, bucket: destination.bucket)
            self.reload()
        }
        cataloguePane.onDrop = { [weak self] palette,destination in
            guard let self else{return}
            self.library.assignPalette(palette,to:destination.project,bucket:destination.bucket,copyOnly:true)
            self.reload()
        }
        // A name typed over its words on either rail, written once the typing ends: a palette, a member, or a folder.
        let rename: (StudioFrame.Place, String) -> Void = { [weak self] p, name in
            guard let self = self else { return }
            switch p {
            case .palette(let id): self.library.rename(id, to: name)
            case .project(let id): self.library.apply("Rename Member") { $0.renameProject(id, to: name) }
            case .folder(let c, let f): SchemaTrial.changeCollection(c) { col in if let i = col.folders.firstIndex(where: { $0.id == f }) { col.folders[i].name = name } }
            default: break
            }
        }
        rail1.onRename = rename
        rail2.onDesignPalette = { [weak self] in self?.library.newPalette() }
        rail2.onRename = { [weak self] p, name in guard self?.place != .appbridge else { return }; rename(p, name) }
        rail1.onFavourite = { [weak self] id in self?.library.toggleFavourite(id) }
        rail1.onTarget = { [weak self] id in guard let self = self else { return }; self.library.setTarget(self.library.library.activeSwatchID == id ? nil : id) }
        rail1.onContext = { [weak self] place, view, point in self?.openContext(place, in: view, at: point) }
        rail2.onContext = { [weak self] place, view, point in self?.openContext(place, in: view, at: point) }
        page.grid.onContext = { [weak self] hex, point in guard let self else { return }; self.openSwatchContext(hex, in: self.page.grid, at: point) }
        page.grid.onAssetContext = { [weak self] id, point in guard let self else { return }; self.openContext(.palette(id), in: self.page.grid, at: point) }
        rail1.onGear = { [weak self] id, view, rect in self?.openHalo(for: id, from: view, rect: rect) }
        // A bucket opened or shut on either rail is remembered for this catalogue; rail2 is built from the state, so it is filled again.
        rail1.onShut = { [weak self] key, shut in guard let self = self else { return }; Prefs.setRailShut(key, shut, in: self.library.catalogue) }
        rail2.onShut = { [weak self] key, shut in guard let self = self else { return }; Prefs.setRailShut(key, shut, in: self.library.catalogue); self.fillContextRail() }
        // On the Contrast page a row chooses the palette the pair is picked from; everywhere else it opens the place.
        rail2.onPick = { [weak self] p in
            guard let self = self else { return }
            if self.place == .appbridge {
                if case .palette(let id) = p { self.page.cancelASEName(); self.appbridge.selected = id; self.reload(); return }
                if p == .appbridge { self.beginNewASE(); return }
            }
            if self.place == .contrast, self.contrastPage.pick(p) { return }
            self.go(p)
        }
        contrastPage.onPaletteChange = { [weak self] in if self?.place == .contrast { self?.fillContextRail() } }
        page.grid.onPick = { [weak self] hex in self?.choose(hex) }
        page.grid.onImagePreview={ [weak self] path,date in self?.photoThumbnail(for:URL(fileURLWithPath:path),modifiedAt:date) }
        page.grid.onPaletteRating={ [weak self] id,rating in self?.library.ratePalette(id,rating) }
        page.grid.onPaletteFlag={ [weak self] id,flag in self?.library.flagPalette(id,flag) }
        page.grid.onPaletteHalo = { [weak self] id,rect in guard let self else{return};if self.selectedGridPalettes.count > 1,self.selectedGridPalettes.contains(id) {self.paletteSelection.ids=Set(self.selectedGridPalettes);self.openSelectionHalo(from:self.page.grid,rect:rect)} else {self.openHalo(for:id,from:self.page.grid,rect:rect)} }
        page.onDeltaToggle = { [weak self] in Prefs.deltaWarningsEnabled.toggle();self?.page.applyDeltaState(Prefs.deltaWarningsEnabled) }
        NotificationCenter.default.addObserver(self,selector:#selector(printProfilesChanged),name:.printProfilesChanged,object:nil)
        if let settings=try? SavedPrintProfiles.load().current {PrintCondition.current=settings.channel;page.grid.deltaTolerance=settings.tolerance}
        page.grid.onSpectral = { [weak self] item in
            guard let self else { return [] }
            let palette:UUID? = item.id ?? { if case .palette(let id)=self.place {return id};return nil }()
            guard let palette else {return []}
            let keys=item.hex.map{[$0]} ?? self.displayLibrary.swatch(palette)?.entries.map(\.hex) ?? []
            return Array(keys.prefix(item.colours.count)).map { self.viewerSpectral($0,palette:palette)?.colour }
        }
        page.grid.onPreviewPaletteColour = { [weak self] id,index in self?.showPaletteViewer(id,colourIndex:index) }
        page.grid.onPreviewSwatch = { [weak self] in self?.showSwatchViewer($0) }
        page.grid.onCopy = { [weak self] text in self?.library.flash("Copied \(text)") }
        page.grid.onHalo = { [weak self] hex, rect in self?.openColourHalo(hex, rect: rect) }
        page.onPaletteDrop = { [weak self] id in
            guard let self,let palette=self.library.library.swatch(id),!palette.isTypography else{return false}
            switch self.place {
            case .project(let project):
                self.library.assignPalette(id,to:project,bucket:nil,copyOnly:true);return true
            case .group(let project,let bucket):
                guard SchemaTrial.rows(of:SchemaTrial.schema(for:project)).contains(where:{$0.node.id == bucket && SchemaTrial.role(of:$0.node) == .palettes}) else{return false}
                self.library.assignPalette(id,to:project,bucket:bucket,copyOnly:true);return true
            case .appbridge:
                return self.appbridge.append(ExportPalette(name:palette.name,colours:palette.entries.map{ExportColour(name:$0.name ?? $0.hex,hex:$0.hex)}))
            default:return false
            }
        }
        page.onFormat = { [weak self] in
            guard let self else{return}
            if self.canvasWorkspace {self.page.grid.needsDisplay=true}
            else{self.fillPage()}
        }
        header.onPick = { [weak self] in self?.library.togglePicking() }
        header.onSample = { [weak self] in self?.library.sampleArea() }
        page.grid.onSelectPalette = { [weak self] id in self?.inspectPalette(id) }
        page.paletteActions.back.target=self
        page.paletteActions.back.action=#selector(backToPaletteGrid)
        page.grid.onOpen = { [weak self] id in
            guard let self = self else { return }
            if self.displayLibrary.swatch(id) != nil {
                self.paletteGridReturn=(self.place,self.captureLayoutPage(),id,self.paletteFilter)
            }
            self.go(self.displayLibrary.project(id) != nil ? .project(id) : .palette(id))
        }
        page.settings.library = library
        page.settings.onChange = { [weak self] in self?.reload() }
        page.schema.library = library
        page.schema.onChange = { [weak self] in self?.reload() }
        // The New button makes a member where members are listed; on a member's Typography page, a typography palette, opened in Contrast for its first pairing.
        page.onNew = { [weak self] in self?.newFromPage() }
        page.add(ShortcutsSettings(), as: .shortcuts)
        page.add(SoundsSettings(), as: .sounds)
        page.add(HaloSettings(), as: .halo)
        let general = GeneralSettings()
        general.onWizard = { [weak self] in self?.showSplash() }
        general.onReset = { [weak self] in self?.reload() }
        page.add(general, as: .general)
        for index in 0..<3 {
            let colour = ColourManagementSettings(index: index)
            colour.onProfiles = { [weak self] in
                guard let self else { return }
                self.go(self.settingsReturn ?? .catalogue)
                self.layoutSubtreeIfNeeded()
                self.showProfileRail()
            }
            page.add(colour, as: .colourManagement(index))
        }
        page.onSettingsTab = { [weak self] destination in self?.go(destination) }
        page.add(AppleMenubarSettings(), as: .appleMenubar)
        page.add(SharingSettings(), as: .sharingSettings)
        let qrImport = QRImportPage()
        qrImport.onDocument = { [weak self] document in guard let self else { return }; QRSharing.review(document, library:self.library, over:self) }
        page.add(qrImport, as: .qrImport)
        page.add(LibrarySettings(), as: .librarySettings)
        // Tags: every tag with its colour, name, scope and what wears it, the one place for all of them (StudioTags.swift).
        page.add(TagsSettings(library: library), as: .tags)
        page.add(LabPage(library: library), as: .lab)
        printPaletteRail.arrow = .none
        printPaletteRail.heading = "Palettes"
        printPaletteRail.labels = ("Project & Palette", "Colours")
        printPaletteRail.onPaletteSelection = { [weak self] id, _, _ in
            guard let self else { return }
            self.prePressPage.selectPrintPalette(id)
            self.printPaletteRail.selectedPalettes = [id]
        }
        printPaletteRail.onShut = { [weak self] key, shut in
            guard let self else { return }
            Prefs.setRailShut(key, shut, in: self.library.catalogue); self.fillLibraryRail()
        }
        printPaletteRail.onFavourite = { [weak self] id in self?.library.toggleFavourite(id) }
        printPaletteRail.onGear = { [weak self] id, view, rect in self?.openHalo(for: id, from: view, rect: rect) }
        prePressPage.onPrintPaletteChange = { [weak self] id in self?.printPaletteRail.selectedPalettes = id.map { [$0] } ?? [] }
        prePressPage.onNavigate = { [weak self] n in self?.go(.prepress(n)) }
        page.add(prePressPage, as: .prepress)
        page.add(contrastPage, as: .contrast)
        page.add(sharePage, as: .share)
        let appbridgePage = AppbridgePage(store: appbridge)
        appbridgePage.onOpen = { [weak self] id in
            guard let self else { return }
            self.appbridge.selected = id; self.go(.appbridge)
        }
        appbridgePage.onCreate = { [weak self] in self?.beginNewASE() }
        page.add(appbridgePage, as: .appbridge)
        appbridge.onNotice = { [weak self] message in self?.library.flash(message) }
        appbridge.onChange = { [weak self] in guard let self else { return }; if self.place == .appbridge || self.place == .appbridgeSettings { self.reload() } }
        sharePage.onLeave = { [weak self] in guard let self else { return }; self.go(self.sharePage.didImportCatalogue ? .catalogue : self.shareReturn) }
        page.onExport = { [weak self] in
            guard let self else { return }
            if self.place == .appbridge { self.appbridge.exportCurrent() }
            else { self.exportFromPage() }
        }
        page.settings.onImport = { [weak self] in self?.startImport() }
        page.settings.onExport = { [weak self] in guard let self = self else { return }; self.startExport(.catalogue, subject: nil, name: self.library.catalogue) }
        page.schema.onSetUp = { [weak self] in self?.showSplash() }
        history.onScope = { [weak self] in self?.fillHistory() }
        history.onPick = { [weak self] hex in self?.choose(hex) }
        footer.onAct = { [weak self] i in self?.act(i) }
        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: .libraryDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: .schemaDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(historyChanged), name: .historyDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pickerStateChanged), name: .appStateDidChange, object: library)
        NotificationCenter.default.addObserver(self, selector: #selector(flashed(_:)), name: .statusMessage, object: nil)
        if !embeddedPage { library.onReveal = { [weak self] hex in
            guard let self else { return }
            if self.library.picking { self.chosenHex = hex; self.fillFooter(); self.pendingPickerRefresh = true }
            else { self.choose(hex) }
        } }
        if !embeddedPage {
            addSubview(pageLayout,positioned:.below,relativeTo:bloomWorkspace)
            pageLayout.canEditLinkedPalette={ [weak self] id in self?.canEditLinkedPalette(id) ?? false }
            pageLayout.toggleLinkedPaletteEditing={ [weak self] id in self?.toggleLinkedPaletteEditing(id) }
            pageLayout.isLinkedPalette={ [weak self] id in self?.isLinkedPalette(id) ?? false }
            pageLayout.currentPlace={ [weak self] in self?.place ?? .catalogue }
            pageLayout.capturePrimary={ [weak self] in self?.captureLayoutPage() ?? .init() }
            pageLayout.restorePrimary={ [weak self] in self?.restoreLayoutPage($0) }
            pageLayout.resolveRoute={ [weak self] in self?.resolvedLayoutRoute($0) ?? .catalogue }
            pageLayout.hidePageControls={ [weak self] in self?.onboardingActive == true }
            pageLayout.titleForPlace={ [weak self] place in self?.pageTitle(for:place) ?? "Library" }
            pageLayout.navigatePrimary={ [weak self] place in guard let self else{return};self.routingPrimary=true;self.go(place);self.routingPrimary=false }
            pageLayout.renamePrimary={ [weak self] name in self?.page.onRenamePalette?(name) }
            pageLayout.makePage={ [weak self] place in
                guard let self else{fatalError("Missing Library workspace")}
                let pane=StudioFrame(library:self.library,embeddedPage:true)
                pane.onPaneChange={ [weak self,weak pane] in guard let self,let pane else{return};self.pageLayout.refreshTabTitles();if self.pageLayout.active.controller === pane{self.followPane(pane)} }
                pane.onOutsidePage={ [weak self,weak pane] destination in
                    guard let self,let pane else{return}
                    if destination == .imageIntake {self.place=pane.place;self.beginImageIntake()}
                    else {self.go(destination)}
                }
                pane.go(place);return pane
            }
            pageLayout.onActivate={ [weak self] pane in guard let self else{return};self.followPane(pane ?? self) }
            pageLayout.primaryContent.arrange={ [weak self] in self?.arrangePageStack(in:self?.pageLayout.primaryContent.bounds ?? .zero) }
        }
    }
    @objc private func printProfilesChanged(){
        if let settings=try? SavedPrintProfiles.load().current {PrintCondition.current=settings.channel;page.grid.deltaTolerance=settings.tolerance}
        page.grid.invalidatePrintPreviews();page.refreshPrintProfiles();fillPage()
    }
    @objc private func flashed(_ n: Notification) { if let t = n.userInfo?["text"] as? String { footer.flash(t) } }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    private var pendingPickerRefresh = false
    private var pendingSearchRefresh:DispatchWorkItem?
    private func scheduleSearchRefresh() {
        pendingSearchRefresh?.cancel()
        let work=DispatchWorkItem{[weak self] in self?.fillPage(reuseGridIfSame:true)}
        pendingSearchRefresh=work
        DispatchQueue.main.asyncAfter(deadline:.now()+0.12,execute:work)
    }
    @objc private func libraryChanged(_ notice:Notification) {
        if library.picking { pendingPickerRefresh = true; return }
        if let scope=notice.userInfo?["scope"] as? String,scope == "review" || scope == "notes" {
            let snapshots=Dictionary(displayLibrary.swatches.map{($0.id,($0.name,$0.review ?? PaletteReview()))},uniquingKeysWith:{first,_ in first})
            page.grid.paletteReview={id in snapshots[id]}
            cataloguePane.refreshAssetPresentation(displayLibrary)
            page.grid.refreshReviewControls()
            if case .palette(let id)=place,let palette=displayLibrary.swatch(id) {
                page.paletteActions.review.configure(name:palette.name,review:palette.review)
            }
            if scope == "review" && (paletteFilter.rating != nil || paletteFilter.flag != nil || paletteFilter.order == .rating || paletteFilter.order == .flag) {fillPage()}
            return
        }
        reload()
    }
    @objc private func historyChanged() {
        if library.picking { pendingPickerRefresh = true; return }
        fillHistory()
    }
    @objc private func pickerStateChanged() {
        guard !library.picking, pendingPickerRefresh else { return }
        pendingPickerRefresh = false; reload()
        page.grid.chosenHex = chosenHex
    }

    @objc private func openProfileRail(_ notification:Notification){guard !embeddedPage,let source=notification.object as? NSView,source.window === window else{return};showProfileRail()}
    private func showProfileRail(){guard !embeddedPage else{return};viewportHeader.channels.showProfiles()}
    /// Slides every panel towards where it is going, a quarter of a second for the whole way, eased; stops when all have arrived.
    private func slide() {
        if embeddedPage {open=goal;needsLayout=true;return}
        header.historyOpen = goal.history > 0
        guard open != goal || profileOpen != profileGoal else { needsLayout = true; return }
        guard slideClock == nil else { return }
        page.layoutFrozen = true
        lastSlide = Date()
        slideClock = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            let now = Date(), step = CGFloat(now.timeIntervalSince(self.lastSlide) / 0.25)
            self.lastSlide = now
            func toward(_ v: CGFloat, _ g: CGFloat) -> CGFloat { v < g ? min(g, v + step) : max(g, v - step) }
            self.profileOpen=toward(self.profileOpen,self.profileGoal)
            self.open = (toward(self.open.rail1, self.goal.rail1), toward(self.open.rail2, self.goal.rail2), toward(self.open.history, self.goal.history))
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
            self.needsDisplay = true
            if self.open == self.goal && self.profileOpen == self.profileGoal {
                t.invalidate(); self.slideClock = nil
                let transition = CATransition(); transition.type = .fade; transition.duration = 0.12
                if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { self.page.layer?.add(transition, forKey: "RailContentReflow") }
                self.page.layoutFrozen = false; self.page.needsLayout = true
                self.page.layoutSubtreeIfNeeded()
            }
        }
        RunLoop.main.add(slideClock!, forMode: .common)
    }

    var onboardingActive:Bool {place == .catalogue && SchemaTrial.structure != nil && !page.onboardingDismissed && (library.library.projects.isEmpty || page.journey != nil)}
    private func pageTitle(for place:Place)->String {
        switch place {
        case .palette(let id):return displayLibrary.swatch(id)?.name ?? "Missing Palette"
        case .project(let id):return displayLibrary.project(id)?.name ?? "Missing Project"
        case .group(let project,let node),.overview(let project,let node):return SchemaTrial.rows(of:SchemaTrial.schema(for:project)).first(where:{$0.node.id == node})?.node.name ?? "Missing Section"
        case .collection(let id):return SchemaTrial.collections.first(where:{$0.id == id})?.name ?? "Collection"
        case .folder(let collection,let id):return SchemaTrial.collections.first(where:{$0.id == collection})?.folders.first(where:{$0.id == id})?.name ?? "Folder"
        case .palettes:return "Library Palettes"
        case .catalogue:return onboardingActive ? (SchemaTrial.personalMode ? "Personal":SchemaTrial.structure?.clientName ?? "Client")+" Onboarding":library.catalogue
        default:return "Library"
        }
    }
    private func arrangePageStack(in rect:NSRect){
        let width=rect.width,height=rect.height
        page.isHidden=false;viewportHeader.isHidden=onboardingActive;viewportFooter.isHidden=onboardingActive
        page.compactWorkspace=true;page.paneHeaderControls=true;page.inset=16;page.insetRight=16
        page.frame=NSRect(x:0,y:0,width:width,height:max(0,height-(onboardingActive ? 0:WorkspaceViewportBar.footerHeight)))
        viewportHeader.preferredHeight=page.actionbarHeight(for:width)
        viewportHeader.frame=NSRect(x:0,y:AreaHeader.rule,width:width,height:viewportHeader.preferredHeight)
        viewportFooter.frame=NSRect(x:0,y:max(0,height-WorkspaceViewportBar.footerHeight),width:width,height:WorkspaceViewportBar.footerHeight)
    }

    // Grid regions: three columns for the indexed library, two for the register, then the page.
    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        if embeddedPage {
            for view in [header,rail1,rail2,history,footer,strip,profileHeader,printPaletteRail,leftPanelRail,rightPanelRail,railProfile,intakeSourceRail,intakeTargetRail,filmstrip,designerWorkspace,bloomWorkspace,overlay,settingsCurtainClip] as [NSView] {view.isHidden=true}
            arrangePageStack(in:bounds);return
        }
        pageLayout.isHidden = !libraryLayoutAvailable
        page.paneHeaderControls=libraryLayoutAvailable
        if libraryLayoutAvailable {
            for view in [page,viewportHeader,viewportFooter] where view.superview !== pageLayout.primaryContent {pageLayout.primaryContent.addSubview(view)}
        } else {
            // Moving the shared viewport out of LibraryPageLayout must keep it below
            // the fixed header and rails. A plain addSubview puts it on top of them,
            // hiding From and the navigation when Import is opened from Library.
            for view in [page,viewportHeader,viewportFooter] where view.superview !== self {
                addSubview(view, positioned:.below, relativeTo:header)
            }
        }
        leftPanelRail.isHidden = !canvasWorkspace || imageIntakeWorkspace
        rightPanelRail.isHidden = !canvasWorkspace || imageIntakeWorkspace || place == .designer
        railProfile.isHidden=rightPanelRail.isHidden || profileOpen == 0
        designerWorkspace.isHidden = place != .designer
        page.isHidden = place == .designer
        intakeSourceRail.isHidden = !imageIntakeWorkspace
        intakeTargetRail.isHidden = !imageIntakeWorkspace
        filmstrip.isHidden = !canvasWorkspace || imageIntakeWorkspace || place == .designer
        viewportHeader.isHidden = !canvasWorkspace || place == .designer
        viewportFooter.isHidden = !canvasWorkspace || place == .designer
        bloomWorkspace.isHidden = !canvasWorkspace || expandedAnalysis == nil || place == .designer
        footer.isHidden = false
        profileHeader.isHidden = !canvasWorkspace || imageIntakeWorkspace || place == .designer
        if canvasWorkspace {
            let adaptive = !imageIntakeWorkspace && place != .designer
            let rails = WorkspaceResponsiveGeometry.rails(width:w, selection:compactRailSelection, library:wideLibraryRailVisible, analysis:wideAnalysisRailVisible)
            let left = adaptive ? rails.0:A.railWidth, right = adaptive ? rails.1:A.railWidth
            leftPanelRail.isHidden = leftPanelRail.isHidden || left == 0
            rightPanelRail.isHidden = rightPanelRail.isHidden || right == 0
            railProfile.isHidden = rightPanelRail.isHidden || profileOpen == 0
            viewportFooter.setRailControls(library:left > 0, analysis:right > 0, visible:adaptive)
            let proofWidth = right > 0 ? min(A.railWidth,max(0,w-left-right-280))*profileOpen:0
            let profileHeight:CGFloat=profileHeader.isHidden ? 0:viewportHeader.channels.headerHeight(forWidth:max(0,w-left-right-proofWidth-34))
            let intakeBarHeight:CGFloat=imageIntakeWorkspace ? page.actionbarHeight(for:max(0,w-left-right-proofWidth-2)):0
            let top = A.header + 1 + profileHeight + intakeBarHeight, bottom: CGFloat = A.footer + (imageIntakeWorkspace || place == .designer ? 0 : 120)
            let workspaceFooterY=h-bottom-WorkspaceViewportBar.footerHeight
            footer.frame=NSRect(x:0,y:h-A.footer,width:w,height:A.footer)
            footer.grid=(A.column(1,in:w),A.columnWidth(in:w),A.column(5,in:w))
            header.frame = NSRect(x: 0, y: 0, width: w, height: A.header)
            header.grid = (16, A.columnWidth(in: w)); header.railEdge = imageIntakeWorkspace ? A.railWidth:left
            let railTop=A.header+1
            profileHeader.frame=NSRect(x:left+1,y:railTop,width:w-left-right-proofWidth-2,height:profileHeight)
            profileHeaderContent.frame=NSRect(x:16,y:0,width:max(0,profileHeader.bounds.width-32),height:profileHeight)
            viewportHeader.channels.frame=profileHeaderContent.bounds
            leftPanelRail.frame = NSRect(x: 0, y: railTop, width: left, height: h-railTop-bottom)
            rightPanelRail.frame = NSRect(x: w-right, y: railTop, width: right, height: h-railTop-bottom)
            railProfile.frame=NSRect(x:w-right-proofWidth,y:railTop,width:proofWidth,height:h-railTop-bottom)
            intakeSourceRail.frame=leftPanelRail.frame
            intakeTargetRail.frame=rightPanelRail.frame
            designerWorkspace.frame=NSRect(x:left+1,y:top,width:w-left-1,height:h-top-bottom)
            page.frame = NSRect(x: left+1, y: top, width: w-left-right-proofWidth-2, height: max(0,workspaceFooterY-top))
            viewportHeader.usesHeaderSurface=imageIntakeWorkspace
            viewportHeader.preferredHeight=imageIntakeWorkspace ? intakeBarHeight:page.actionbarHeight(for:w-left-right-proofWidth-2)
            viewportHeader.frame=NSRect(x:left+1,y:imageIntakeWorkspace ? railTop:top+AreaHeader.rule,width:w-left-right-proofWidth-2,height:viewportHeader.preferredHeight)
            viewportFooter.frame=NSRect(x:left+1,y:workspaceFooterY,width:w-left-right-proofWidth-2,height:WorkspaceViewportBar.footerHeight)
            workspaceDragShade.frame=NSRect(x:left+1,y:top,width:w-left-right-proofWidth-2,height:h-top-bottom)
            bloomWorkspace.frame=NSRect(x:left+1,y:viewportHeader.frame.maxY,width:w-left-right-proofWidth-2,height:max(0,viewportFooter.frame.minY-viewportHeader.frame.maxY))
            expandedBloom.spectrumWidth=page.grid.paletteTileWidth;expandedHistogram.spectrumWidth=page.grid.paletteTileWidth
            if libraryLayoutAvailable {
                pageLayout.frame=NSRect(x:left+1,y:top,width:w-left-right-proofWidth-2,height:max(0,h-top-bottom))
                pageLayout.needsLayout=true;pageLayout.layoutSubtreeIfNeeded()
                arrangePageStack(in:pageLayout.primaryContent.bounds)
            }
            page.inset=16;page.insetRight=16
            page.compactWorkspace=true
            filmstrip.frame=NSRect(x:0,y:h-bottom,width:w,height:120)
            [rail1,rail2,history,printPaletteRail].forEach{$0.isHidden=true}
            settingsCurtainClip.isHidden=true
            strip.frame=NSRect(x:0,y:0,width:w,height:TitleStrip.height)
            paletteWheel.frame=bounds;paletteWheel.availableRect=page.convert(page.bounds,to:self);paletteWheel.anchor=NSPoint(x:left,y:page.convert(page.bounds,to:self).midY)
            if swatchViewer.superview != nil { layoutSwatchViewer() }
            overlay.frame=bounds;overlay.isHidden=true
            return
        }
        page.compactWorkspace=false
        header.frame = NSRect(x: 0, y: 0, width: w, height: A.header)
        footer.frame = NSRect(x: 0, y: h - A.footer, width: w, height: A.footer)
        let top = A.header + 1, bodyH = h - A.header - A.footer - 2
        func ease(_ v: CGFloat) -> CGFloat { v <= 0 ? 0 : v >= 1 ? 1 : 1 - pow(1 - v, 3) }
        // The same expanded dock widths serve legacy routes and the panel workspace.
        let r1Full=A.railWidth,r1Min=LibraryRail.collapsedWidth
        let r2Full=A.railWidth
        let hFull = A.size.width - A.column(11, in: A.size.width) + A.gutter / 2
        let r1W = (r1Min + (r1Full - r1Min) * (isSettings(place) || printWorkspace ? 0 : ease(open.rail1))).rounded(), r2W = (r2Full * ease(open.rail2)).rounded(), hW = (hFull * ease(open.history)).rounded()
        rail1.expandedWidth = r1Full; rail2.expandedWidth = r2Full
        printPaletteRail.expandedWidth = r1Full
        header.railEdge = r1Full
        rail1.frame = NSRect(x: 0, y: top, width: r1W, height: bodyH)
        settingsCurtainClip.frame = rail1.frame
        settingsCurtain.frame = NSRect(x: 0, y: -bodyH * (1 - curtainProgress), width: r1W, height: bodyH)
        rail1.isHidden = false
        rail1.collapsed = isSettings(place) || printWorkspace || (goal.rail1 == 0 && open.rail1 == 0)
        rail1.arrow = goal.rail1 < 1 ? .open : .close
        rail2.frame = NSRect(x: rail1.frame.maxX + 1, y: top, width: r2W, height: bodyH)
        rail2.isHidden = r2W < 2
        // The history slides in from the right edge, and off it completely, its width never changing.
        history.frame = NSRect(x: w - hW, y: top, width: hFull, height: bodyH)
        history.isHidden = hW < 1
        printPaletteRail.isHidden = !printWorkspace
        printPaletteRail.frame = NSRect(x: rail2.frame.maxX + 1, y: top, width: printWorkspace ? r1Full : 0, height: bodyH)
        printPaletteRail.inset = A.areaGutter / 2
        printPaletteRail.insetRight = A.margin
        let pageLeft = printWorkspace ? printPaletteRail.frame.maxX + 1 : rail2.frame.maxX + (r2W < 2 ? 0 : 1)
        page.frame = NSRect(x: pageLeft, y: top, width: w - hW - (history.isHidden ? 0 : 1) - pageLeft, height: bodyH)
        header.grid = (A.column(1, in: w), A.columnWidth(in: w))
        footer.grid = (A.column(1, in: w), A.columnWidth(in: w), A.column(5, in: w))
        // Every area's words sit exactly on its columns: the left edge on the first, the right edge at the end of the last; the page's edges
        // are half a gutter, which is a column's edge whichever columns it covers.
        func edges(_ v: NSView, _ from: Int, _ to: Int) -> (CGFloat, CGFloat) {
            (A.column(from, in: w) - v.frame.minX, v.frame.maxX - (A.column(to, in: w) + A.columnWidth(in: w)))
        }
        (rail1.inset, rail1.insetRight) = (A.column(1, in: w), A.areaGutter / 2)
        (rail2.inset, rail2.insetRight) = (A.areaGutter / 2 - 1, A.areaGutter / 2)
        (page.inset, page.insetRight) = (A.areaGutter / 2 - 1, open.history > 0 ? A.gutter / 2 - 1 : A.margin)
        overlay.page = NSRect(x: page.frame.minX + page.inset, y: 0, width: page.frame.width - page.inset - page.insetRight, height: 0)
        (history.inset, history.insetRight) = (A.gutter / 2, A.margin)
        strip.frame = NSRect(x: 0, y: 0, width: w, height: TitleStrip.height)
        if swatchViewer.superview != nil { layoutSwatchViewer() }
        paletteWheel.frame = bounds
        paletteWheel.availableRect = NSRect(x: 0, y: top + AreaHeader.rule + 1, width: w, height: max(0, bodyH - AreaHeader.rule - 1))
        paletteWheel.anchor = NSPoint(x: rail1.frame.maxX, y: paletteWheel.availableRect.midY)
        overlay.frame = bounds
        overlay.isHidden = !A.masterGrid
        overlay.needsDisplay = true
    }

    /// The backslash key: Master Inner on and off.
    func toggleGrid() { A.masterGrid.toggle(); overlay.isHidden = !A.masterGrid; overlay.needsDisplay = true; prePressPage.refreshGrid() }

    /// The splash over the whole window (TH-299): nothing of the app shows but the wordmark until it is done.
    private(set) var splash: StudioSplash?
    func showSplash() {
        guard splash == nil else { return }
        let s = StudioSplash(library: library)
        s.frame = bounds
        s.autoresizingMask = [.width, .height]
        s.onDone = { [weak self] in
            self?.splash?.removeFromSuperview()
            self?.splash = nil
            self?.overlay.splash = false
            self?.go(.catalogue)
        }
        addSubview(s)
        // The grid stays on top of it, for measuring, and draws the splash's own beat.
        addSubview(overlay)
        overlay.splash = true
        splash = s
        s.begin()
    }

    override func draw(_ dirtyRect: NSRect) {
        // Header and rail edges; StudioFooter owns its top border inside its own bounds.
        let w = bounds.width
        if canvasWorkspace {
            hairline(x:0,y:A.header,width:w)
            fill(NSRect(x:leftPanelRail.frame.maxX,y:A.header,width:1,height:leftPanelRail.frame.height),Design.rule)
            fill(NSRect(x:rightPanelRail.frame.minX-1,y:A.header,width:1,height:rightPanelRail.frame.height),Design.rule)
            return
        }
        hairline(x: 0, y: A.header, width: w)
        var lines = [rail1.frame.maxX]
        if !rail2.isHidden { lines.append(rail2.frame.maxX) }
        if !history.isHidden { lines.append(history.frame.minX - 1) }
        if printWorkspace { lines.append(printPaletteRail.frame.maxX) }
        for x in lines { fill(NSRect(x: x, y: A.header + 1, width: 1, height: rail1.frame.height), Design.rule) }
    }

    // MARK: What is shown

    private func isSettings(_ p: Place) -> Bool {
        switch p { case .settings, .schema, .shortcuts, .halo, .sounds, .general, .colourManagement, .appleMenubar, .sharingSettings, .librarySettings, .tags, .appbridgeSettings: return true; default: return false }
    }

    /// The Settings entry point resumes the last section; Catalogues remains an explicit rail destination.
    func openSettings() { go(lastSettingsPage) }

    private var resumePlaceKey: String { "Workspace.LibraryPlace.\(library.catalogue)" }

    /// Restores the last Library destination for this catalogue after the catalogue itself is opened.
    func restoredLibraryPlace() -> Place {
        guard let saved = AppPreferences.shared.string(forKey: resumePlaceKey) else { return .catalogue }
        let parts = saved.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let place: Place?
        switch parts.first {
        case "catalogue": place = .catalogue
        case "palettes": place = .palettes
        case "designer": place = .designer
        case "projects": place = .projects
        case "palette": place = parts.count == 2 ? UUID(uuidString: parts[1]).map(Place.palette) : nil
        case "project": place = parts.count == 2 ? UUID(uuidString: parts[1]).map(Place.project) : nil
        case "collection": place = parts.count == 2 ? UUID(uuidString: parts[1]).map(Place.collection) : nil
        case "folder": place = parts.count == 3 ? (UUID(uuidString: parts[1]).flatMap { c in UUID(uuidString: parts[2]).map { .folder(c, $0) } }) : nil
        case "overview", "group":
            place = parts.count == 3 ? (UUID(uuidString: parts[1]).flatMap { p in UUID(uuidString: parts[2]).map { parts[0] == "overview" ? .overview(p, $0) : .group(p, $0) } }) : nil
        default: place = nil
        }
        guard let place else { return .catalogue }
        switch place {
        case .palette(let id): return displayLibrary.swatch(id) == nil ? .catalogue : place
        case .project(let id), .overview(let id, _), .group(let id, _): return displayLibrary.project(id) == nil ? .catalogue : place
        case .collection(let id): return SchemaTrial.collections.contains { $0.id == id } ? place : .catalogue
        case .folder(let c, let f): return SchemaTrial.collections.first { $0.id == c }?.folders.contains { $0.id == f } == true ? place : .catalogue
        default: return place
        }
    }

    private func saveLibraryPlace(_ place: Place) {
        guard !embeddedPage else{return}
        let value: String?
        switch place {
        case .catalogue: value = "catalogue"
        case .palettes: value = "palettes"
        case .designer: value = "designer"
        case .projects: value = "projects"
        case .palette(let id): value = "palette:\(id.uuidString)"
        case .project(let id): value = "project:\(id.uuidString)"
        case .collection(let id): value = "collection:\(id.uuidString)"
        case .folder(let c, let f): value = "folder:\(c.uuidString):\(f.uuidString)"
        case .overview(let p, let n): value = "overview:\(p.uuidString):\(n.uuidString)"
        case .group(let p, let n): value = "group:\(p.uuidString):\(n.uuidString)"
        default: value = nil
        }
        if let value { AppPreferences.shared.set(value, forKey: resumePlaceKey) }
    }

    /// Escape returns to the page that was visible before entering any settings section.
    @discardableResult func leaveSettings() -> Bool {
        guard isSettings(place) else { return false }
        window?.makeFirstResponder(self)
        let destination = settingsReturn ?? .catalogue
        settingsReturn = nil
        go(destination)
        return true
    }

    private func moveSettingsCurtain(up: Bool) {
        curtainProgress = up ? 1 : 0
        settingsCurtainClip.isHidden = !up
        needsLayout = true
    }

    func go(_ requested: Place) {
        var p=requested
        let previousRoute=place
        if SchemaTrial.personalMode {switch p {case .collection,.folder:p = .catalogue;default:break}}
        if p == .schema {(NSApp.delegate as? AppDelegate)?.showCatalogueStructure();return}

        if !embeddedPage,!restoringSession,sessionCatalogue == library.store.url,libraryLayoutAvailable,p != place {lastLibrarySessionLayout=captureWorkspaceLayout(forSession:true)}
        if embeddedPage {
            switch p {case .catalogue,.palettes,.palette,.collection,.folder,.project,.overview,.group:break
            default:if let onOutsidePage{onOutsidePage(p);return}}
        }
        if !embeddedPage, libraryLayoutAvailable,!routingPrimary {
            switch p {case .catalogue,.palettes,.palette,.collection,.folder,.project,.overview,.group:
                if pageLayout.navigate(p){return}
            default:break}
        }
        if place == .imageIntake && p != .imageIntake { viewportHeader.setIntakeMode(false) }
        workspaceFilter=nil
        if place == .help, p != .help, let previous = beforeHelp {
            goal = previous; beforeHelp = nil
        }
        if case .palette(let id) = p, library.library.swatch(id) != nil {
            if !paletteSelection.ids.contains(id) { paletteSelection.ids = [id]; paletteSelection.anchor = id }
        } else { paletteSelection.ids = []; paletteSelection.anchor = nil }
        if p != place, case .palette = p { header.clearFilter() }
        page.cancelASEName()
        if isSettings(p) { lastSettingsPage = p }
        if isSettings(p) && !isSettings(place) {
            settingsReturn = place
            moveSettingsCurtain(up: true)
        } else if !isSettings(p) && isSettings(place) {
            settingsReturn = nil
            moveSettingsCurtain(up: false)
        }
        paletteWheel.dismiss()
        if p == .contrast && place != .contrast { contrastPage.arrive(fromLab: place == .lab) }
        // PrePress closes rail1: the page takes its columns, and rail2 holds the route or the settings.
        func narrows(_ p: Place) -> Bool { if case .prepress = p { return true }; return false }
        if narrows(p) && !narrows(place) {
            beforePrePressRail = goal.rail1
            goal.rail1 = 0
        } else if narrows(place) && !narrows(p) {
            goal.rail1 = beforePrePressRail
        }
        if p == .help {
            if place != .help { beforeHelp = goal }
            goal = (0, 0, 0)
        }
        place = p
        if !embeddedPage{pageLayout.updatePrimary(p)}
        saveLibraryPlace(p)
        slide()
        func libraryRoute(_ route:Place)->Bool {
            switch route {case .catalogue,.palettes,.palette,.collection,.folder,.project,.overview,.group:return true;default:return false}
        }
        reload(routeOnly:libraryRoute(previousRoute) && libraryRoute(p))
    }

    private func beginNewASE() {
        appbridge.selected = nil
        go(.appbridge)
        page.beginASEName { [weak self] name in
            guard let self else { return false }
            let picker = NSOpenPanel()
            picker.title = "Save New ASE File"
            picker.message = "Choose the folder for \(name).ase"
            picker.prompt = "Save"
            picker.canChooseFiles = false; picker.canChooseDirectories = true
            picker.canCreateDirectories = true; picker.allowsMultipleSelection = false
            picker.directoryURL = self.appbridge.creationDirectory
            guard picker.runModal() == .OK, let folder = picker.url else { return false }
            do {
                try FolderAccess.authorize(folder)
                let file = folder.appendingPathComponent(name + ".ase")
                try AdobeASE.empty.write(to: file, options: .withoutOverwriting)
                ASEIcon.apply(to: file)
                self.appbridge.add(file, folder: false)
                return true
            } catch {
                self.library.flash("Could not create ASE: " + error.localizedDescription)
                return false
            }
        }
    }

    /// The Lab has no rail2: its columns go to the page. Contrast keeps it, as the list of palettes to pick the pair from.
    private var railTwo: CGFloat { expanded || place == .lab || place == .catalogue || place == .qrImport || place == .help ? 0 : 1 }

    private func choose(_ hex: String) {
        chosenHex = hex
        page.grid.chosenHex = hex
        fillFooter()
    }

    /// Every colour as it is drawn, from its master, worked out once a reload.
    private var shade: [String: NSColor] = [:]
    func captureLayoutPage()->WorkspaceLayoutTemplate.Page {
        var state=page.captureLayoutView();state.rating=paletteFilter.rating;state.flag=paletteFilter.flag;state.order=paletteFilter.order.rawValue;state.filter=workspaceFilter;return state
    }
    func restoreLayoutPage(_ state:WorkspaceLayoutTemplate.Page){
        paletteFilter = .init(rating:state.rating,flag:state.flag,order:PaletteAssetHandler.Order(rawValue:state.order) ?? .newest);workspaceFilter=state.filter
        reload();page.restoreLayoutView(state)
    }
    private func resolvedLayoutRoute(_ route:Place)->Place {
        switch route {
        case .catalogue,.palettes:return route
        case .palette(let id):return displayLibrary.swatch(id) == nil ? .catalogue:route
        case .project(let id),.overview(let id,_),.group(let id,_):return displayLibrary.project(id) == nil ? .catalogue:route
        case .collection(let id):return SchemaTrial.collections.contains{$0.id == id} ? route:.catalogue
        case .folder(let c,let f):return SchemaTrial.collections.first{$0.id == c}?.folders.contains{$0.id == f} == true ? route:.catalogue
        default:return .catalogue
        }
    }
    private func captureWorkspaceLayout(forSession:Bool=false)->WorkspaceLayoutTemplate.State? {
        guard libraryLayoutAvailable || forSession else{return nil}
        var state=WorkspaceLayoutTemplate.State(tree:pageLayout.snapshot(),activePane:pageLayout.active.id)
        for (railIndex,rail) in [leftPanelRail,rightPanelRail,intakeSourceRail,intakeTargetRail].enumerated(){for (index,panel) in rail.panels.enumerated(){state.panels.append(.init(id:panel.panelID,rail:railIndex,order:index,closed:panel.collapsed,height:Double(panel.preferredHeight)))}}
        state.rails=[Double(goal.rail1),Double(goal.rail2),Double(goal.history)];state.expanded=expanded;state.pageExpanded=page.expanded;state.settings=forSession ? [:]:Layout_Handler.captureSettings();state.histogram=histogramPane.layoutSelection
        state.profileRailOpen=profileGoal > 0;state.window=window.map{.init($0.frame)};return state
    }
    private func restoreWorkspaceLayout(_ record:WorkspaceLayoutTemplate,scope:Layout_Handler.Scope,session:Bool=false)throws {
        try Layout_Handler.validate(record.state)
        guard record.state.version == 1 else{throw failure("This layout needs a newer version of Colorgain.")}
        guard libraryLayoutAvailable else{throw failure("Open Library Before Applying A Layout")}
        let state=record.state
        if scope == .app && !session {
            Layout_Handler.restoreSettings(state.settings)
            cataloguePane.restoreLayoutPreferences()
            NotificationCenter.default.post(name:.themeDidChange,object:nil)
        }
        if scope == .app {
            let rails=[leftPanelRail,rightPanelRail,intakeSourceRail,intakeTargetRail],panels=rails.flatMap(\.panels)
            for saved in state.panels.sorted(by:{$0.order < $1.order}) {
                guard rails.indices.contains(saved.rail),let panel=panels.first(where:{$0.panelID == saved.id}) else{continue}
                panel.collapsed=saved.closed;panel.preferredHeight=max(0,CGFloat(saved.height));rails[saved.rail].add(panel,at:saved.order)
            }
            histogramPane.layoutSelection=state.histogram;expandedHistogram.copyConfiguration(from:histogramPane)
            profileGoal=0;profileOpen=0
            expanded=state.expanded;page.expanded=state.pageExpanded
            if state.rails.count == 3 {slideClock?.invalidate();slideClock=nil;goal=(CGFloat(state.rails[0]),CGFloat(state.rails[1]),CGFloat(state.rails[2]));open=goal}
            if let rect=state.window?.rect,rect.width.isFinite,rect.height.isFinite,rect.minX.isFinite,rect.minY.isFinite,let window,let screen=NSScreen.screens.first(where:{$0.visibleFrame.intersects(rect)}) ?? window.screen {
                let visible=screen.visibleFrame,w=min(visible.width,max(window.minSize.width,rect.width)),h=min(visible.height,max(window.minSize.height,rect.height))
                window.setFrame(NSRect(x:max(visible.minX,min(rect.minX,visible.maxX-w)),y:max(visible.minY,min(rect.minY,visible.maxY-h)),width:w,height:h),display:true)
            }
        }
        needsLayout=true;layoutSubtreeIfNeeded()
        try pageLayout.restore(state.tree,activePane:state.activePane,pageOnly:scope == .catalogue)
        needsLayout=true;layoutSubtreeIfNeeded();followPane(pageLayout.active.controller ?? self)
        if session,SchemaTrial.structure != nil,library.library.projects.isEmpty {
            for panel in leftPanelRail.panels {panel.collapsed=panel.panelID != "catalogues"}
            cataloguePane.beginOnboarding()
        }
    }
    /// A route change reuses the library tree and colour table; model changes rebuild them.
    func reload(routeOnly:Bool=false) {
        if !routeOnly{page.grid.invalidatePrintPreviews()}
        if !embeddedPage{header.layoutControl.catalogueURL=library.store.url}
        if !embeddedPage {appbridge.bind(to: library.store.root)}
        // A restored Import tab can arrive without beginImageIntake(). Rebuild its
        // destination rail from the active catalogue on every full workspace reload.
        if imageIntakeWorkspace {
            intakeTargetPane.configure(library:library.library,schema:library.store.schema,catalogueName:library.store.url.deletingPathExtension().lastPathComponent,assetKind:importKind)
            configureImportTarget()
            viewportHeader.setIntakeMode(true,linking:intakeLinking)
            // Restored Import tabs bypass beginImageIntake; keep the source scanner's
            // file filter in sync with the type shown by the action bar.
            intakeSourcePane.assetKind=importKind
            if intakeFolder == nil {intakeSourcePane.refreshSelectedSource()}
        }
        let lib = displayLibrary
        if SchemaTrial.structure != nil,lib.projects.isEmpty {
            if !onboardingRailPrepared, !embeddedPage {
                for panel in leftPanelRail.panels {panel.collapsed=panel.panelID != "catalogues"}
                cataloguePane.beginOnboarding();onboardingRailPrepared=true
            }
        }
        if !routeOnly{shade = lib.displayTable()}
        if SchemaTrial.personalMode {switch place {case .collection,.folder:place = .catalogue;default:break}}
        // A place that is gone goes back to the catalogue.
        switch place {
        case .palette(let id) where lib.swatch(id) == nil: place = .catalogue
        case .project(let id) where lib.project(id) == nil: place = .catalogue
        case .overview(let id, _) where lib.project(id) == nil: place = .catalogue
        case .group(let id, _) where lib.project(id) == nil: place = .catalogue
        case .collection(let id) where !SchemaTrial.collections.contains(where: { $0.id == id }): place = .catalogue
        case .folder(let c, let f) where !(SchemaTrial.collections.first { $0.id == c }?.folders.contains { $0.id == f } ?? false): place = .catalogue
        default: break
        }
        if goal.rail2 != railTwo {
            goal.rail2 = railTwo
            // Before the window is on screen the rail is simply shut; after, it slides.
            if window?.isVisible == true { slide() } else { open.rail2 = railTwo; needsLayout = true }
        }
        paletteSelection.ids.formIntersection(Set(library.library.swatches.map { $0.id }))
        rail1.selectedPalettes = paletteSelection.ids
        rail2.selectedPalettes = paletteSelection.ids
        rail1.selectionHeight = paletteSelection.ids.contains { library.library.swatch($0)?.claim != nil } ? Design.App.unit * 2 : Design.App.unit
        if routeOnly {
            let selection:Place
            if case .overview(let id,_)=place{selection = .project(id)}else{selection=place}
            cataloguePane.selectRoute(selection,key:workspaceFilter)
        } else {
            fillLibraryRail()
            if !leftPanelRail.isHidden {collectionsPane.refreshIfCatalogueChanged()}
        }
        fillContextRail()
        fillPage()
        if slideClock != nil {
            page.layoutFrozen = false; page.needsLayout = true; page.layoutSubtreeIfNeeded(); page.layoutFrozen = true
        }
        fillHistory()
        fillFooter()
        header.live = { switch place { case .catalogue, .palette: return 0; case .imageIntake: return 7; case .designer: return 8; case .help, .settings, .schema, .shortcuts, .halo, .sounds, .general, .colourManagement, .appleMenubar, .sharingSettings, .librarySettings, .tags, .share, .appbridgeSettings: return nil; case .group, .overview: return 0; case .lab: return 2; case .prepress: return 3; case .contrast: return 4; case .projects: return 5; case .appbridge: return 6; case .qrImport: return 7; default: return 1 } }()
    }

    private func palettes(_ list: [Swatch]) -> [Swatch] { list.filter { !$0.isTypography } }

    // MARK: Sharing

    /// The wizard on a level of the catalogue: the whole catalogue from its settings, a collection or member from its page, a palette from its halo.
    private var shareReturn: Place = .catalogue
    func startExport(_ level: ShareLevel, subject: UUID?, name: String) {
        shareReturn = place
        sharePage.beginExport(level: level, subject: subject, name: name)
        go(.share)
    }
    func startImport(url: URL? = nil) {
        shareReturn = place
        sharePage.beginImport(url: url)
        go(.share)
    }
    private func exportFromPage() {
        switch place {
        case .project(let id), .overview(let id, _): startExport(.workGroup, subject: id, name: library.library.project(id)?.name ?? "Member")
        case .folder(let cid, let fid):
            let name = SchemaTrial.collections.first { $0.id == cid }?.folders.first { $0.id == fid }?.name ?? "Group"
            startExport(.workGroup, subject: fid, name: name)
        case .collection(let id): startExport(.collection, subject: id, name: SchemaTrial.collections.first { $0.id == id }?.name ?? "Collection")
        default: startExport(.catalogue, subject: nil, name: library.catalogue)
        }
    }

    // MARK: The palette's halo

    private func viewerSpectral(_ key:String,palette:UUID)->SpectralEngine.Prediction? {
        guard let catalogue=CatalogueTree.catalogue(in:library.store.root)?.id,
              let definition=displayLibrary.definition(of:key) else{return nil}
        return SpectralStore.shared.prediction(catalogue:catalogue,palette:palette,colour:key,definition:definition,light:PaletteViewing.illuminant)
    }
    private func viewerProof(_ key:String)->NSColor?{
        guard let channel=viewportHeader.channels.selectedChannel,
              let definition=displayLibrary.definition(of:key) ?? ColourKeys.definition(of:key) ?? ColourDefinition.of(hex:key) else{return nil}
        let rendering=Rendering.of(definition,in:channel)
        guard let difference=rendering.difference,difference.isFinite else{return nil}
        return rendering.shown?.display
    }
    private let swatchViewer = PaletteWheel()
    private func layoutSwatchViewer() {
        page.layoutSubtreeIfNeeded()
        swatchViewer.frame = bounds
        // Page may be nested inside a split-pane container; never treat its frame as root coordinates.
        swatchViewer.availableRect = page.convert(page.previewViewport, to: swatchViewer).intersection(swatchViewer.bounds)
        swatchViewer.controlsRect = viewportHeader.convert(viewportHeader.bounds,to:swatchViewer)
    }
    private func showSwatchViewer(_ hex: String) {
        let list = page.grid.items.filter { $0.hex != nil }
        guard !list.isEmpty else { return }
        let palette: Swatch? = { if case .palette(let id) = place { return displayLibrary.swatch(id) }; return nil }()
        let item = PaletteWheel.Item(id: palette?.id ?? UUID(), name: palette?.name ?? "All Colours",
            colours: list.map { item in item.sourceCMYK == nil ? (displayLibrary.definition(of:item.hex!) ?? ColourKeys.definition(of:item.hex!) ?? ColourDefinition.of(hex:item.hex!))?.master.display ?? item.colours.first ?? Design.hex(item.hex!) : item.colours.first ?? Design.hex(item.hex!) },
            details: list.map { .init(name: $0.title.components(separatedBy: " / ").first ?? $0.title, hex: $0.hex!) })
        let unprofiled=Set(list.filter{$0.sourceCMYK != nil}.compactMap(\.hex))
        swatchViewer.onProof={ [weak self] key in unprofiled.contains(key) ? nil:self?.viewerProof(key) }
        swatchViewer.onSpectral={ [weak self] key in palette.flatMap{self?.viewerSpectral(key,palette:$0.id)?.colour} }
        swatchViewer.backdropView = self
        addSubview(swatchViewer, positioned: .above, relativeTo: nil)
        layoutSwatchViewer()
        swatchViewer.onDismiss = { [weak self] in self?.swatchViewer.removeFromSuperview() }
        swatchViewer.presentSwatch(item, hex: hex)
    }
    private func shareQR(hex:String? = nil,palette:UUID? = nil) {
        let lib=displayLibrary
        if hex != nil,place == .appbridge,page.grid.items.first(where:{$0.hex==hex})?.sourceCMYK != nil { library.flash("This ASE swatch has no embedded ICC profile. Import it with a defined print condition before sharing its master colour.");return }
        let origin:UUID? = { if let palette{return palette};if case .palette(let id)=place{return id};return nil }()
        let name=palette.flatMap { lib.swatch($0)?.name } ?? hex.map { lib.name(of:$0,in:origin) } ?? "Colour"
        let keys=hex.map { [$0] } ?? palette.flatMap { lib.swatch($0)?.entries.map { $0.hex } } ?? []
        let entries=keys.compactMap { key -> ColourQR.Entry? in
            guard let d=ColourKeys.definition(of:key) ?? ColourDefinition.of(hex:key) else { return nil }
            return .init(name:lib.name(of:key,in:origin),source:d.source,master:d.master,kind:d.kind)
        }
        guard entries.count==keys.count,!entries.isEmpty else { library.flash("There are no complete colour records to share.");return }
        QRSharing.show(.init(type:palette == nil ? "swatch" : "palette",name:name,colours:entries),over:self)
    }
    private func showPaletteViewer(_ id:UUID,colourIndex:Int? = nil) {
        guard let palette=displayLibrary.swatch(id),!palette.entries.isEmpty else { return }
        let item=PaletteWheel.Item(id:id,name:palette.name,colours:palette.entries.map{shade[$0.hex] ?? Design.hex($0.hex)},details:palette.entries.map{.init(name:displayLibrary.name(of:$0.hex,in:id),hex:$0.hex)})
        swatchViewer.onProof={ [weak self] in self?.viewerProof($0) }
        swatchViewer.onSpectral={ [weak self] in self?.viewerSpectral($0,palette:id)?.colour }
        swatchViewer.backdropView=self;addSubview(swatchViewer,positioned:.above,relativeTo:nil)
        layoutSwatchViewer()
        swatchViewer.onDismiss={ [weak self] in self?.swatchViewer.removeFromSuperview() }
        if let colourIndex,palette.entries.indices.contains(colourIndex) {swatchViewer.presentSwatch(item,hex:palette.entries[colourIndex].hex)} else {swatchViewer.presentPalette(item)}
    }
    private let contextMenu = SwissContextMenu()
    private func addToCollectionAction(_ item:AssetCollectionItem)->HaloAction {addToCollectionAction([item])}
    private func addToCollectionAction(_ items:[AssetCollectionItem])->HaloAction {
        HaloAction(id:"collections",label:"Add To Collection",symbol:"square.grid.2x2",children:{[weak self] in
            guard let self else{return []}
            let collections=AssetCollections.list(in:self.library.store)
            let existing=collections.map { collection in
                let held=Set(collection.items.map(\.key)),included=items.allSatisfy{held.contains($0.key)}
                return HaloAction(id:collection.id.uuidString,label:collection.name,symbol:"folder",checked:included,onSelect:{[weak self] in
                    guard let self else{return}
                    do {
                        if included {try AssetCollections.remove(items,from:collection.id,in:self.library.store)}
                        else {try AssetCollections.add(items,to:collection.id,in:self.library.store)}
                        self.collectionsPane.refresh()
                        self.library.flash(included ? "Removed from \(collection.name).":"Added to \(collection.name).")
                    } catch {self.library.flash(error.localizedDescription)}
                })
            }
            let create=HaloAction(id:"new",label:"New Collection…",symbol:"plus",onSelect:{[weak self] in
                guard let self else{return}
                self.collectionsPane.createCollection { [weak self] id in
                    guard let self else{return}
                    do {try AssetCollections.add(items,to:id,in:self.library.store);self.collectionsPane.refresh();self.library.flash("Added to Collection.")}
                    catch {self.library.flash(error.localizedDescription)}
                }
            })
            return existing + [create]
        })
    }
    private func openCollectedAsset(_ item:AssetCollectionItem){
        if item.kind == "Palette",let id=UUID(uuidString:item.identity),library.library.swatch(id) != nil {go(.palette(id));return}
        if item.kind == "Colour" {go(.catalogue);showSwatchViewer(item.identity);return}
        if item.kind == "ICC Profile" {showProfileRail();iccProfilePane.locate(item.identity);return}
        if item.kind == "ASE",let id=UUID(uuidString:item.identity),appbridge.files.contains(where:{$0.id == id}){appbridge.selected=id;go(.appbridge);return}
        if let id=UUID(uuidString:item.identity),WorkspaceImport.records(store:library.store).contains(where:{$0.0.id == id}) {importPane.open(id:id);return}
        if FileManager.default.fileExists(atPath:item.identity){NSWorkspace.shared.open(URL(fileURLWithPath:item.identity));return}
        library.flash("This asset is no longer available. Remove its Collection entry or locate the original.")
    }
    private func openContext(_ place: Place, in view: NSView, at point: NSPoint) {
        if view === page.grid {paletteSelection.ids=Set(selectedGridPalettes)}
        let actions: [HaloAction]
        switch place {
        case .palette(let id):
            if library.library.swatch(id) != nil {
                if paletteSelection.ids.contains(id), paletteSelection.ids.count > 1 { actions = batchActions() }
                else { paletteSelection.ids = [id]; paletteSelection.anchor = id; reload(); actions = paletteContextActions(for: id) }
            }
            else if let file = appbridge.files.first(where: { $0.id == id }) {
                actions = [
                    HaloAction(id: "open", label: "Open", symbol: "arrow.up.right", onSelect: { [weak self] in self?.appbridge.selected = id; self?.go(.appbridge) }),
                    HaloAction(id: "duplicate", label: "Duplicate", symbol: "doc.on.doc", disabled: file.problem != nil) { [weak self] in self?.appbridge.duplicate(file) },
                    HaloAction(id: "locate", label: "Locate File…", symbol: "folder") { [weak self] in self?.appbridge.locate(file) { self?.reload() } },
                    addToCollectionAction(.init(kind:"ASE",identity:file.id.uuidString,name:file.url.lastPathComponent)),
                    HaloAction(id: "detach", label: "Detach", symbol: "minus.circle") { [weak self] in self?.appbridge.detach(file) },
                    HaloAction(id: "delete", label: "Move File To Trash…", symbol: "trash") { [weak self] in self?.appbridge.confirmDelete(file, over: view) }
                ]
            } else if let record=WorkspaceImport.records(store:library.store).first(where:{$0.0.id == id})?.0 {
                actions=[
                    HaloAction(id:"open",label:"Open",symbol:"arrow.up.right",onSelect:{[weak self] in self?.importPane.open(id:id)}),
                    addToCollectionAction(.imported(record))
                ]
            } else { return }
        case .project(let id), .overview(let id, _), .group(let id, _):
            actions = [
                HaloAction(id: "open", label: "Open", symbol: "arrow.up.right") { [weak self] in self?.go(place) },
                HaloAction(id: "rename", label: "Rename Project…", symbol: "pencil") { [weak self] in self?.library.renameProject(id) },
                HaloAction(id: "export", label: "Export Project…", symbol: "square.and.arrow.up") { [weak self] in self?.startExport(.workGroup, subject: id, name: self?.library.library.project(id)?.name ?? "Project") },
                HaloAction(id: "delete", label: "Delete Project…", symbol: "trash") { [weak self] in self?.library.delete(project: id) }
            ]
        default: return
        }
        contextMenu.open(actions, at: point, in: view)
    }
    func editMetadata(for id:UUID? = nil) {
        let target=id ?? { if case .palette(let id)=place{return id};return nil }()
        guard let target,let palette=library.library.swatch(target),let root=window?.contentView else{return}
        let targets=paletteSelection.ids.contains(target) && paletteSelection.ids.count>1 ? Array(paletteSelection.ids):[target]
        AssetMetadataEditor.present(palette,selectedCount:targets.count,over:root){ [weak self] metadata,included in
            guard let self else{return}
            self.library.apply("Edit Asset Metadata") { lib in
                for id in targets {
                    guard let index=lib.swatches.firstIndex(where:{$0.id==id}) else{continue}
                    var value=lib.swatches[index].metadata ?? AssetMetadata()
                    AssetMetadataSchema.apply(metadata,to:&value,including:included)
                    value.tidy();lib.swatches[index].metadata=value.isEmpty ? nil:value
                    if included.contains(10){lib.setTags(ofPalette:id,metadata.keywords ?? [])}
                }
            }
            self.metadataPane.palette=self.library.library.swatch(target)
        }
    }
    func editMetadata(forColour hex:String) {
        guard let colour=library.library.colours.first(where:{$0.hex==hex}),let root=window?.contentView else{return}
        let sample=Swatch(id:UUID(),name:colourName(hex),createdAt:Date(),entries:[SwatchEntry(hex:hex,addedAt:Date())],metadata:colour.metadata)
        AssetMetadataEditor.present(sample,over:root){ [weak self] metadata,included in
            guard let self else{return}
            self.library.apply("Edit Colour Metadata") { lib in if let i=lib.colours.firstIndex(where:{$0.hex==hex}){var value=lib.colours[i].metadata ?? AssetMetadata();AssetMetadataSchema.apply(metadata,to:&value,including:included);value.tidy();lib.colours[i].metadata=value.isEmpty ? nil:value} }
        }
    }
    private func openSwatchContext(_ hex: String, in view: NSView, at point: NSPoint) {
        if let actions=selectedSwatchActions(hex) {contextMenu.open(actions,at:point,in:view);return}
        let palette: UUID? = { if case .palette(let id) = place { return id }; return nil }()
        var actions = place == .appbridge ? StudioPage.models.map { format in
            HaloAction(id: format.rawValue, label: "Copy " + format.label, symbol: "doc.on.doc", onSelect: { [weak self] in
                let source = self?.page.grid.items.first { $0.hex == hex }?.sourceCMYK
                ColourCopies.copy(hex, text: format == .cmyk ? (source ?? format.text(hex)) : format.text(hex, lowercase: Prefs.lowercaseHex), sourceCMYK: source)
            })
        } : SwatchMenu.ring(for: hex, in: palette, library: library, editTags: { [weak self] in self?.tag(swatches: $0) })
        actions.append(HaloAction(id:"qr",label:"Share Swatch QR",symbol:"qrcode",onSelect:{ [weak self] in self?.shareQR(hex:hex) }))
        actions.append(HaloAction(id:"notes",label:"Add Notes…",symbol:"note.text",onSelect:{ [weak self] in self?.openNotes(for: self?.page.grid.items.first(where:{$0.hex == hex})) }))
        actions.append(addToCollectionAction(.colour(hex,name:library.library.name(of:hex,in:nil))))
        actions.append(HaloAction(id:"metadata",label:"Edit Metadata…",symbol:"info.circle",onSelect:{ [weak self] in self?.editMetadata(forColour:hex) }))
        contextMenu.open(actions, at: point, in: view)
    }

    private var halo: HaloMenu?

    private func paletteFileLocation(_ id: UUID) -> (file: URL?, root: URL?) {
        if let source = linkedPalettes.sources[id] {
            let root = source.index.deletingLastPathComponent()
            return (try? source.record.url(in: root), source.record.external ? nil : root)
        }
        let roots = [library.store.root, library.store.assetsHome].compactMap { $0 }
        let file = roots.compactMap { CatalogueTree.file(ofPalette: id, in: $0) }.first
        return (file, roots.first { root in file.flatMap { AssetFileActions.relativePath(of: $0, under: root) } != nil })
    }

    /// One action tree drives the palette's context menu and halo.
    private func paletteActions(for id: UUID) -> [HaloAction] {
        let lib = library.library
        guard let s = lib.swatch(id) else { return [] }
        let library = self.library
        let location = paletteFileLocation(id)
        let feedback: (String) -> Void = { [weak self] in self?.library.flash($0) }
        func group(_ id: String, _ label: String, _ symbol: String, _ inner: @escaping () -> [HaloAction]) -> HaloAction { HaloAction(id: id, label: label, symbol: symbol, children: inner) }
        var actions: [HaloAction] = [
            HaloAction(id:"view",label:"View",symbol:"eye",onSelect:{ [weak self] in self?.showPaletteViewer(id) }),
            HaloAction(id:"swatches",label:"Open Swatches",symbol:"square.grid.2x2",onSelect:{ [weak self] in self?.go(.palette(id)) }),
            HaloAction(id:"print-preview",label:"Output Proof",symbol:"exclamationmark.triangle",description:"Toggle output proof comparisons across palettes and swatches",onSelect:{ [weak self] in self?.page.grid.togglePrintPreview(palette:id) }),
            HaloAction(id: "rename", label: "Rename", symbol: "pencil", edit: (s.name, "Palette name", "Return keeps it", { library.rename(id, to: $0) })),
            HaloAction(id: "fav", label: s.favourite ? "Remove From Favourites" : "Add To Favourites", symbol: "star", checked: s.favourite) { library.toggleFavourite(id) },
            HaloAction(id: "target", label: lib.activeSwatchID == id ? "Stop Sending Picks Here" : "Send Picks Here", symbol: "scope", checked: lib.activeSwatchID == id) { library.setTarget(lib.activeSwatchID == id ? nil : id) },
            HaloAction(id: "tags", label: "Tags\u{2026}", symbol: "tag", onSelect: { [weak self] in self?.tag(palette: id) }),
            HaloAction(id: "notes", label: "Add Notes…", symbol: "note.text", onSelect: { [weak self] in self?.openNotes(for: self?.page.grid.items.first(where:{$0.id == id}) ?? TileGrid.Item(title:s.name,caption:"",colours:s.entries.compactMap{lib.definition(of:$0.hex)?.master.display},hex:nil,id:id)) }),
            HaloAction(id: "metadata", label: "Edit Metadata\u{2026}", symbol: "info.circle", onSelect: { [weak self] in self?.editMetadata(for:id) }),
            HaloAction(id: "duplicate", label: "Duplicate", symbol: "plus.square.on.square") { library.duplicate(id) },
            group("copy-to", "Copy To Member", "folder.badge.plus") {
                var inner: [HaloAction] = lib.orderedProjects.filter { $0.id != s.projectID }.map { p in HaloAction(id: p.id.uuidString, label: p.name, symbol: "folder") { library.move(palette: id, to: p.id, index: Int.max) } }
                if s.projectID != nil { inner.append(HaloAction(id: "loose", label: "Palettes, Outside Any Member", symbol: "tray") { library.move(palette: id, to: nil, index: Int.max) }) }
                inner.append(HaloAction(id: "new", label: "New Member\u{2026}", symbol: "plus") { library.startProject(moving: id) })
                return inner
            },
            addToCollectionAction(linkedPalettes.sources[id].map{.imported($0.record)} ?? .palette(id,name:s.name)),
            HaloAction(id: "reveal", label: "Reveal in Finder", symbol: "folder", disabled: location.file == nil) {
                AssetFileActions.reveal(location.file, feedback: feedback)
            },
            group("copy-path", "Copy Path", "doc.on.doc") {
                AssetFileActions.pathActions(file: location.file, root: location.root, feedback: feedback)
            },
            group("share", "Share", "square.and.arrow.up") { [weak self] in
                AssetFileActions.sharingActions(file: location.file, title: s.name, feedback: feedback) + [
                    HaloAction(id: "qr", label: "Share Palette QR", symbol: "qrcode", onSelect: { [weak self] in self?.shareQR(palette: id) })
                ]
            },
            HaloAction(id: "copy-all", label: "Copy All", symbol: "doc.on.doc") { library.copy(lib.hexes(inSwatch: id, by: .oldest), from: s.name) },
            HaloAction(id: "export", label: "Export Palette\u{2026}", symbol: "square.and.arrow.up", onSelect: { [weak self] in self?.startExport(.palette, subject: id, name: s.name) }),
            HaloAction(id: "delete", label: "Delete Palette", symbol: "trash", confirmation: ("Slide to delete", "Hold the arrow key")) { library.delete(palette: id, confirmed: true) },
        ]
        if s.projectID != nil { actions.insert(HaloAction(id: "open", label: "Open Member", symbol: "arrow.up.right", onSelect: { [weak self] in if let p = s.projectID { self?.go(.project(p)) } }), at: 0) }
        for id in ["copy-to"] {
            if let i=actions.firstIndex(where:{$0.id==id}),let children=actions[i].children {
                let title=actions[i].label
                actions[i].destinationGallery={HaloGalleryRequest.destinations(children(),title:title,source:s.name+" · \(s.entries.count) Colours",commit:"Copy Here",library:library,sourceColours:s.entries.map{lib.definition(of:$0.hex)?.master.display ?? Design.hex($0.hex)})}
            }
        }
        if let i = actions.firstIndex(where: { $0.id == "delete" }) { actions[i].onMenuSelect = { library.delete(palette: id) } }
        if let source = linkedPalettes.sources[id] {
            actions.insert(HaloAction(id: "reference", label: "Manage Reference…", symbol: "link", onSelect: { [weak self] in self?.importPane.manage(id: source.record.id) }), at: 0)
            if !linkedPalettes.canEdit(id) {
                let allowed:Set<String> = ["view", "swatches", "print-preview", "reference", "reveal", "copy-path", "share", "copy-all", "export", "notes", "collections"]
                actions = actions.filter { allowed.contains($0.id) }
            }
        }
        return actions
    }
    private func paletteContextActions(for id: UUID) -> [HaloAction] {
        let sections: [String: Int] = [
            "reference": 0, "open": 0, "view": 0, "swatches": 0, "print-preview": 0,
            "rename": 1, "fav": 1, "target": 1, "tags": 1, "notes": 1, "duplicate": 1, "copy-to": 1, "collections": 1,
            "reveal": 2, "copy-path": 2, "share": 3, "copy-all": 4, "export": 4, "delete": 5
        ]
        return sectionedActions(paletteActions(for: id), sections: sections)
    }
    private func sectionedActions(_ actions: [HaloAction], sections: [String: Int]) -> [HaloAction] {
        var result: [HaloAction] = [], previous: Int?
        for action in actions {
            let section = sections[action.id] ?? 0
            if let previous, previous != section {
                result.append(HaloAction(id: "divider-\(result.count)", label: SwissDropdown.MenuPanel.divider, symbol: "minus", disabled: true))
            }
            result.append(action); previous = section
        }
        return result
    }
    private func imageActions(for path: String) -> [HaloAction] {
        let file = URL(fileURLWithPath: path)
        let roots = [library.store.root, library.store.assetsHome].compactMap { $0 }
        let root = roots.first { AssetFileActions.relativePath(of: file, under: $0) != nil }
        let feedback: (String) -> Void = { [weak self] in self?.library.flash($0) }
        var actions: [HaloAction] = []
        if imageIntakeWorkspace {
            actions.append(HaloAction(id: "import-file", label: "Import File", symbol: "square.and.arrow.down") { [weak self] in self?.page.grid.onImageContextAction?(path, 0) })
        }
        if !page.grid.imageFullView {
            actions.append(HaloAction(id: "full-view", label: "Show in Full", symbol: "arrow.up.left.and.arrow.down.right") { [weak self] in self?.page.grid.onImageContextAction?(path, 2) })
        }
        actions.append(HaloAction(id: "notes", label: "Add Notes…", symbol: "note.text") { [weak self] in self?.openNotes(for: self?.page.grid.items.first(where:{$0.imagePath == path})) })
        let imported=WorkspaceImport.records(store:library.store).first{
            (try? $0.0.url(in:$0.1.deletingLastPathComponent()).standardizedFileURL.path) == file.standardizedFileURL.path
        }?.0
        actions.append(addToCollectionAction(imported.map(AssetCollectionItem.imported) ?? .file(path,kind:"Image",name:file.lastPathComponent)))
        actions.append(HaloAction(id: "reveal", label: "Reveal in Finder", symbol: "folder") {
            AssetFileActions.reveal(file, feedback: feedback)
        })
        actions.append(HaloAction(id: "copy-path", label: "Copy Path", symbol: "doc.on.doc", children: {
            AssetFileActions.pathActions(file: file, root: root, feedback: feedback)
        }))
        actions.append(HaloAction(id: "share", label: "Share", symbol: "square.and.arrow.up", children: {
            AssetFileActions.sharingActions(file: file, title: file.lastPathComponent, feedback: feedback)
        }))
        return actions
    }
    private func imageContextActions(for path: String) -> [HaloAction] {
        sectionedActions(imageActions(for: path), sections: ["import-file": 0, "full-view": 0, "notes": 0, "collections": 0, "reveal": 1, "copy-path": 1, "share": 2])
    }
    private var imageHalo: HaloMenu?
    private func openNotes(for item: TileGrid.Item?) {
        guard let item else { return }
        AssetNotes.configureLooseStore(beside:library.store.url)
        if let id=item.id, library.isLocked(palette:id) || (linkedPalettes.sources[id] != nil && !linkedPalettes.canEdit(id)) {
            library.flash("Unlock this palette before editing its notes."); return
        }
        let palette: UUID? = { if case .palette(let id) = place { return id }; return nil }()
        guard let key = AssetNotes.key(for: item, palette: palette, scope: library.store.url.path) else { return }
        if let id=item.id { AssetNotes.cache(library.library.swatch(id)?.assetNotes,for:key) }
        if let hex=item.hex,let palette {
            let record=library.library.note(of:hex,in:palette).map{AssetNotes.Record(name:library.library.name(of:hex,in:palette),description:$0)}
            AssetNotes.cache(record,for:key)
        }
        let displayName=item.hex.map{library.library.name(of:$0,in:palette)} ?? item.title
        let editor = AssetNotesEditor(item: item, key: key, name: displayName) { [weak self] message in self?.library.flash(message) }
        let modal = SwissFocusModal(content: editor, size: NSSize(width: 748, height: 520))
        editor.modal = modal
        if let id=item.id { editor.onSave={ [weak self] record in self?.library.setPaletteNotes(id,record) } }
        else if let hex=item.hex,let palette { editor.onSave={ [weak self] record in self?.library.setColourNotes(hex,in:palette,record) } }
        editor.onChange = { [weak self] in self?.page.grid.needsDisplay = true }
        modal.present(over: self)
    }
    private func openImageHalo(for path: String, rect: NSRect) {
        let h = imageHalo ?? HaloMenu(label: "Image", hint: "Scroll to turn, click to choose", actions: [])
        imageHalo = h
        h.label = URL(fileURLWithPath: path).lastPathComponent
        h.actions = imageActions(for: path)
        h.open(centredOn: rect, in: page.grid)
    }
    private func openHalo(for id: UUID, from view: NSView, rect: NSRect) {
        guard let s = displayLibrary.swatch(id) else { return }
        let actions = paletteActions(for: id)
        let h = halo ?? HaloMenu(label: "Palette", hint: "Scroll to turn, click to choose", actions: [])
        halo = h
        h.label = s.name
        h.actions = actions
        h.open(centredOn: rect, in: view)
    }

    /// The halo on a colour: the old swatch ring, over the tile that was clicked.
    private func selectedSwatchActions(_ hex:String)->[HaloAction]? {
        let selected=page.grid.selectedItems
        guard selected.count > 1,selected.allSatisfy({$0.hex != nil}),selected.contains(where:{$0.hex == hex}) else{return nil}
        let keys=selected.compactMap(\.hex)
        return [
            HaloAction(id:"copy-selected",label:"Copy \(keys.count) Swatches",symbol:"doc.on.doc") { [weak self] in self?.library.copy(keys) },
            HaloAction(id:"tag-selected",label:"Tag \(keys.count) Swatches…",symbol:"tag",disabled:!canDeleteGridSelection) { [weak self] in guard let self else{return};TagPanel.colours(keys,library:self.library,over:self.window) },
            addToCollectionAction(keys.map{.colour($0,name:colourName($0))}),
            HaloAction(id:"delete-selected",label:"Delete \(keys.count) Swatches…",symbol:"trash",disabled:!canDeleteGridSelection) { [weak self] in self?.deleteGridSelection() }
        ]
    }
    private var colourHalo: HaloMenu?
    private func openColourHalo(_ hex: String, rect: NSRect) {
        if let actions=selectedSwatchActions(hex) {
            let h=colourHalo ?? HaloMenu(label:"Selected Swatches",hint:"Actions for this selection",actions:[])
            colourHalo=h;h.label="\(page.grid.selectedCount) Swatches Selected";h.actions=actions;h.open(centredOn:rect,in:page.grid);return
        }
        let inPalette: UUID? = { if case .palette(let id) = place { return id }; return nil }()
        let h = colourHalo ?? HaloMenu(label: "Colour", hint: "Scroll to turn, click to choose", actions: [])
        colourHalo = h
        h.label = colourName(hex)
        h.caption = page.format.text(hex, lowercase: Prefs.lowercaseHex)
        if place == .appbridge {
            h.actions = StudioPage.models.map { format in
                HaloAction(id: format.rawValue, label: "Copy " + format.label, symbol: "doc.on.doc", onSelect: { [weak self] in
                    let source = self?.page.grid.items.first { $0.hex == hex }?.sourceCMYK
                    ColourCopies.copy(hex, text: format == .cmyk ? (source ?? format.text(hex)) : format.text(hex, lowercase: Prefs.lowercaseHex), sourceCMYK: source)
                })
            }
        } else {
            h.actions = SwatchMenu.ring(for: hex, in: inPalette, library: library, editTags: { [weak self] hexes in self?.tag(swatches: hexes) })
        }
        h.actions.insert(contentsOf:[
            HaloAction(id:"view",label:"View",symbol:"eye",onSelect:{ [weak self] in self?.showSwatchViewer(hex) }),
            HaloAction(id:"print-preview",label:"Output Proof",symbol:"exclamationmark.triangle",description:"Toggle output proof comparisons across palettes and swatches",onSelect:{ [weak self] in self?.page.grid.togglePrintPreview(hex:hex) })
        ],at:0)
        h.actions.append(HaloAction(id:"qr",label:"Share Swatch QR",symbol:"qrcode",onSelect:{ [weak self] in self?.shareQR(hex:hex) }))
        h.actions.append(HaloAction(id:"notes",label:"Add Notes…",symbol:"note.text",onSelect:{ [weak self] in self?.openNotes(for: self?.page.grid.items.first(where:{$0.hex == hex})) }))
        h.actions.append(addToCollectionAction(.colour(hex,name:colourName(hex))))
        h.actions.append(HaloAction(id:"metadata",label:"Edit Metadata…",symbol:"info.circle",onSelect:{ [weak self] in self?.editMetadata(forColour:hex) }))
        h.open(centredOn: rect, in: page.grid)
    }
    /// Tags typed on the window's own panel, separated by commas, with the scope a new one takes (StudioTags.swift).
    private func tag(swatches hexes: [String]) { TagPanel.colours(hexes, library: library, over: window) }
    private func tag(palette id: UUID) { TagPanel.palette(id, library: library, over: window) }

    /// New on the page: on a member's Typography group, a typography palette in that member, opened in Contrast for its first pairing; anywhere else, a member.
    private func newFromPage() {
        if canImportImagesFromCurrentPlace(),case .group(let member,let bucket)=place {
            let node=SchemaTrial.rows(of:SchemaTrial.schema(for:member)).first{$0.node.id == bucket}?.node
            beginImageIntake(kind:node.map{SchemaTrial.type(of:$0).caseInsensitiveCompare("Images") == .orderedSame} == true ? "Images":"Photographs")
            return
        }
        if case .group(let pid, let nid) = place, let node = SchemaTrial.rows(of: SchemaTrial.schema(for: pid)).first(where: { $0.node.id == nid })?.node,
           SchemaTrial.role(of: node) == .typography {
            var made: UUID?
            library.apply("New Typography Palette") { made = $0.createTypography(in: pid) }
            guard let id = made, library.library.swatch(id) != nil else { return }
            go(.contrast)
            contrastPage.edit(nil, in: id)
            return
        }
        newMember()
    }
    private func importSelectedImages(to destination:WorkspaceImport.ImageDestination,transfer:WorkspaceImport.ImageTransfer){
        let selected=intakeImages.compactMap{item -> URL? in
            guard let path=item.imagePath,intakeSelectedPaths.contains(path) else{return nil}
            return URL(fileURLWithPath:path)
        }
        guard !selected.isEmpty else{library.flash("Select images in the viewport first.");return}
        let kind:String
        switch destination {
        case .catalogue(let member,let bucket):
            guard let node=SchemaTrial.rows(of:SchemaTrial.schema(for:member)).first(where:{$0.node.id == bucket})?.node else{library.flash("The image destination changed. Select it again.");return}
            kind=SchemaTrial.type(of:node).caseInsensitiveCompare("Images") == .orderedSame ? "Images":"Photographs"
        case .library,.custom:kind="Photographs"
        }
        commitImages(selected,to:destination,kind:kind,transfer:transfer)
    }
    private func commitImages(_ selected:[URL],to destination:WorkspaceImport.ImageDestination,kind:String,transfer:WorkspaceImport.ImageTransfer){
        let store=library.store
        let collectionID=importCollectionPane.selectedID
        do{
            if transfer == .reference{for source in selected{try FolderAccess.authorize(source)}}
            if case .custom(let folder)=destination{try FolderAccess.authorize(folder)}
        }catch{library.flash(error.localizedDescription);return}
        let progress=SwissFocusModal(title:"Importing \(kind)",message:"Processing \(plural(selected.count,"image"))…")
        let bar=NSProgressIndicator(frame:.zero);bar.style = .bar;bar.isIndeterminate=true
        progress.content(bar,height:20);progress.present(over:self);bar.startAnimation(nil)
        DispatchQueue.global(qos:.userInitiated).async{[weak self] in
            let result=Result{try WorkspaceImport.addImages(selected,destination:destination,kind:kind,transfer:transfer,store:store,collectionID:collectionID)}
            DispatchQueue.main.async{[weak self] in
                bar.stopAnimation(nil);progress.dismissOverlay()
                guard let self else{return}
                guard self.library.store === store else{self.library.flash("The catalogue changed while images were being added. Reopen it to review the result.");return}
                switch result {
                case .success(let count):
                    self.library.reload();self.collectionsPane.refresh();self.reload()
                    if self.imageIntakeWorkspace {
                        switch destination {
                        case .catalogue(let member,let bucket):self.go(.group(member,bucket))
                        case .library,.custom:self.go(.catalogue)
                        }
                    }
                    self.library.flash("Added \(count) \(count == 1 ? "image":"images")")
                case .failure(let error):self.library.flash(error.localizedDescription)
                }
            }
        }
    }

    /// A member made where the page stands: in the collection or folder in view, else the first collection, made now if there is none; named on the window's own panel.
    private func newMember() {
        if SchemaTrial.structure != nil {CatalogueJourneyView.present(library:library,over:self,client:SchemaTrial.personalMode ? SchemaTrial.structure?.personalCollectionID:nil,kind:SchemaTrial.collections.isEmpty ? "client":"work");return}
        let all = SchemaTrial.collections
        var c = all.first ?? SchemaTrial.SchemaFile.fresh.collections[0], folder: UUID? = nil
        switch place {
        case .collection(let id): c = all.first { $0.id == id } ?? c
        case .folder(let id, let f): c = all.first { $0.id == id } ?? c; folder = f
        default: break
        }
        library.startProject(moving: nil, called: SchemaTrial.memberName(of: c), in: c) { [weak self] id in
            if !SchemaTrial.collections.contains(where: { $0.id == c.id }) { c = SchemaTrial.homeForNewMember() }
            SchemaTrial.place(id, in: c.id, folder: folder)
            self?.go(.project(id))
        }
    }

    /// The members of a collection, in rail1's order; with `folder`, those in that folder, or those in none when nil.
    private func members(of c: SchemaCollection, folder: UUID?? = .none) -> [Project] {
        let all = SchemaTrial.collections, places = SchemaTrial.places
        return library.library.orderedProjects.filter { p in
            guard SchemaTrial.collection(of: p.id, among: all, places: places).id == c.id else { return false }
            if case .some(let f) = folder { return SchemaTrial.folder(of: p.id, among: all, places: places) == f }
            return true
        }
    }

    private func locateWorkspaceCatalogue() {
        guard let window else{return}
        SimpleCatalogueImport.choose(over:window,library:library)
    }

    private func fillLibraryRail() {
        let lib = library.library
        var rows: [LibraryRail.Row] = [.group("Library", key: "catalogue"), .row("All Palettes", palettes(lib.swatches).count, .catalogue, 0)]
        func two(_ s: Swatch, in project: UUID? = nil, indent: Int = 0) -> LibraryRail.Row {
            .palette(LibraryRail.PaletteRow(id: s.id, name: s.claim.map { $0.prefix + " · " + s.name } ?? s.name, count: s.entries.count, colours: s.entries.map { shade[$0.hex] ?? Design.hex($0.hex) },
                                            favourite: s.favourite, target: lib.activeSwatchID == s.id, project: project, indent: indent, bucket: s.bucketID))
        }
        /// A member, then its stack as the schema lays it out, each group one step in with what it holds: the palettes
        /// under the Palettes group and the typography palettes under Typography, each with its icons, so picks can be
        /// sent to any of them from here; a member whose stack has no groups lists its palettes straight beneath it.
        func memberRows(_ p: Project, indent: Int) -> [LibraryRail.Row] {
            let held = lib.palettes(in: p.id), colours = palettes(held), type = held.filter { $0.isTypography }
            var out: [LibraryRail.Row] = [.row(p.name, colours.count, .project(p.id), indent)]
            let stack = SchemaTrial.rows(of: SchemaTrial.schema(for: p.id)).filter { $0.level >= 2 }
            if stack.isEmpty { return out + colours.map { two($0, in: p.id, indent: indent + 1) } }
            for (node, level) in stack {
                let at = indent + level - 1
                switch SchemaTrial.role(of: node) {
                case .palettes?:
                    let scoped = palettes(lib.palettes(in: p.id, bucket: node.id, buckets: stack.filter { SchemaTrial.role(of: $0.node) == .palettes }.map { $0.node.id }))
                    out.append(.node(node.name, scoped.count, p.id, at, true, node.id))
                    out += scoped.map { two($0, in: p.id, indent: at + 1) }
                case .typography?:
                    out.append(.node(node.name, type.count, p.id, at, false, node.id))
                    out += type.map { two($0, in: p.id, indent: at + 1) }
                case .tags?:
                    // The member's own tags beneath the group, each with the colours wearing it, then the way to the editor.
                    let own = lib.allTags.filter { lib.project(ofTag: $0) == p.id }
                    out.append(.node(node.name, own.count, p.id, at, false, node.id))
                    out += own.map { t in .tag(t, lib.colours.filter { $0.tags?.contains(t) == true }.count, p.id, at + 1) }
                    out.append(.tag("Edit Tags", -1, p.id, at + 1))
                case nil:
                    let canDrop = SchemaTrial.rows(of: node).contains { SchemaTrial.role(of: $0.node) == .palettes }
                    out.append(.node(node.name, 0, p.id, at, canDrop, node.id))
                case .information?:
                    out.append(.node(node.name, 0, p.id, at, false, node.id))
                }
            }
            return out
        }
        let favourites = palettes(lib.orderedFavourites)
        if !favourites.isEmpty {
            rows.append(.group("Favourites", key: "favourites"))
            rows += favourites.map { two($0) }
        }
        // Level 0: each collection is a heading. Level 1: its folders, where it has them, each holding its
        // members. Then the member itself, the app's project, with its palettes counted.
        for c in SchemaTrial.collections {
            rows.append(.group(c.name, key: "collection:\(c.id.uuidString)"))
            // Level 1 and below: the folders nest, each one step further in, its members under it before the folders inside it.
            func folderRows(_ f: SchemaFolder, indent: Int) -> [LibraryRail.Row] {
                let inside = members(of: c, folder: .some(f.id))
                let beneath = inside.count + c.descendants(of: f.id).reduce(0) { $0 + members(of: c, folder: .some($1.id)).count }
                var out: [LibraryRail.Row] = [.row(f.name, beneath, .folder(c.id, f.id), indent)]
                out += inside.flatMap { memberRows($0, indent: indent + 1) }
                for child in c.children(of: f.id) { out += folderRows(child, indent: indent + 1) }
                return out
            }
            if c.folderName != nil { for f in c.children(of: nil) { rows += folderRows(f, indent: 0) } }
            // A member in no folder sits beside the folders, straight in its collection, so the tree's lines tie it to the
            // collection and not to the last folder above it, and shutting that folder leaves it showing.
            rows += members(of: c, folder: .some(nil)).flatMap { memberRows($0, indent: 0) }
            if members(of: c).isEmpty {
                // The Master Template is a recipe for members, so it has no live Library groups until the first member exists.
                // Keep an explicit doorway here instead of leaving a new collection looking like a lone, broken heading.
                rows.append(.row("Add First \(SchemaTrial.memberName(of: c))", 0, .collection(c.id), 0))
            }
        }
        let loose = palettes(lib.palettes(in: nil)).filter { $0.claim == nil }
        let claimed = palettes(lib.palettes(in: nil)).filter { $0.claim != nil }
        if !claimed.isEmpty {
            rows.append(.group("Claimed Palettes", key: "claimed"))
            rows += claimed.map { two($0, in: nil, indent: 0) }
        }
        rows.append(.group("Palettes", key: "palettes"))
        rows += loose.map { two($0) }
        rows.append(.row("All Palettes", palettes(lib.swatches).count, .palettes, 0))
        rail1.shut = Prefs.railShut(in: library.catalogue)
        let treeSelection: Place
        if case .overview(let id, _) = place { treeSelection = .project(id) } else { treeSelection = place }
        rail1.set(rows: rows, chosen: treeSelection)
        leftPanelRail.arrange(); rightPanelRail.arrange()
        importPane.refresh()
        cataloguePane.importedAssets = WorkspaceImport.records(store: library.store).map { $0.0 }
        cataloguePane.filter=paletteFilter
        cataloguePane.configureAssets(lib)
        cataloguePane.configureCollections(AssetCollections.list(in:library.store),linkedPaletteRecords:linkedPalettes.sources.mapValues{$0.record.id})
        cataloguePane.update(names: library.availableCatalogues(), active: library.catalogue, rows: rows, selected: treeSelection, selectedKey: workspaceFilter,allFavourites:lib.orderedFavourites)
        if printWorkspace {
            var allowedGroup = false
            let printRows = rows.filter { row in
                switch row {
                case .group(let name, let key):
                    allowedGroup = key != "catalogue" && key != "favourites" && key != "claimed"
                    return allowedGroup && name != "Claimed Palettes"
                case .palette(let p): return allowedGroup && lib.swatch(p.id)?.isTypography == false && lib.swatch(p.id)?.claim == nil
                case .node(_, _, let project, _, _, let node):
                    guard allowedGroup, let n = SchemaTrial.rows(of: SchemaTrial.schema(for: project)).first(where: { $0.node.id == node })?.node else { return false }
                    return SchemaTrial.role(of: n) == .palettes || (SchemaTrial.role(of: n) == nil && SchemaTrial.rows(of: n).contains { SchemaTrial.role(of: $0.node) == .palettes })
                case .tag: return false
                case .row(_, _, let destination, _): return allowedGroup && destination != .palettes
                }
            }
            printPaletteRail.shut = Prefs.railShut(in: library.catalogue)
            printPaletteRail.selectedPalettes = prePressPage.selectedPrintPaletteID.map { [$0] } ?? []
            printPaletteRail.set(rows: printRows, chosen: prePressPage.selectedPrintPaletteID.map { .palette($0) } ?? .prepress(3))
        }
    }

    /// rail2 follows the place: the palettes of the catalogue or a project's level, or, for a member, its
    /// whole stack as the schema lays it out: Information, Palettes, Typography, Tags and any group of its own.
    private func fillContextRail() {
        let lib = library.library
        rail2.warningIDs = place == .appbridge ? Set(appbridge.missing.map { $0.id }) : []
        rail2.onWarning = { [weak self] in guard let self else { return }; self.appbridge.showMissing(over: self) }
        rail2.readOnlyRows = place == .appbridge
        func paletteRow(_ s: Swatch, indent: Int = 0) -> PaletteTable.Row {
            .palette(s.id, s.name, s.entries.count, s.entries.map { shade[$0.hex] ?? Design.hex($0.hex) }, place == .palette(s.id), indent)
        }
        func memberRows(_ list: [Project]) -> [PaletteTable.Row] {
            list.map { .item($0.name, "\(palettes(lib.palettes(in: $0.id)).count)", 0, .project($0.id), place == .project($0.id)) }
        }
        // A group that holds rows carries its caret and is open unless shut for this catalogue; a shut one's rows are left out.
        let shut = Prefs.railShut(in: library.catalogue)
        func fold(_ key: String, holds: Bool) -> (key: String, open: Bool)? { holds ? (key, !shut.contains(key)) : nil }
        /// A folder of a collection as a group with its members under it; the members in no folder come first, straight under the
        /// collection, so none sits under the last folder's heading looking like one of its own.
        func folderRows(_ c: SchemaCollection, indent: Int) -> [PaletteTable.Row] {
            var out = memberRows(members(of: c, folder: .some(nil)))
            guard c.folderName != nil else { return out }
            for f in c.folders {
                let inside = memberRows(members(of: c, folder: .some(f.id))), key = "r2.folder:\(f.id.uuidString)"
                let state = fold(key, holds: !inside.isEmpty)
                out.append(.group(f.name, indent, fold: state))
                if state?.open ?? false { out += inside }
            }
            return out
        }
        var heading = "Palettes", labels = ("Palette", "Count"), rows: [PaletteTable.Row] = []
        switch place {
        case .qrImport, .help, .imageIntake, .designer: break
        case .catalogue:
            break // No context until a Library item is selected.
        case .palettes:
            heading = "Unclaimed Palettes"
            rows = palettes(lib.libraryPalettes).filter { $0.claim == nil }.map { paletteRow($0) }
        case .palette(let id):
            if let palette = lib.swatch(id), let p = palette.projectID, let project = lib.project(p) {
                return fillStack(of: project, in: lib, node: palette.bucketID)
            }
            heading = "Unclaimed Palettes"
            rows = palettes(lib.libraryPalettes).filter { $0.claim == nil }.map { paletteRow($0) }
        case .collection(let id):
            guard let c = SchemaTrial.collections.first(where: { $0.id == id }) else { return }
            heading = c.name; labels = (SchemaTrial.memberName(of: c), "Palettes")
            rows = folderRows(c, indent: 0)
        case .folder(let cid, let fid):
            guard let c = SchemaTrial.collections.first(where: { $0.id == cid }), let f = c.folders.first(where: { $0.id == fid }) else { return }
            heading = f.name; labels = (SchemaTrial.memberName(of: c), "Palettes")
            rows = memberRows(members(of: c, folder: .some(fid)))
        case .project(let id):
            guard let project = lib.project(id) else { return }
            return fillStack(of: project, in: lib)
        case .overview(let id, let node), .group(let id, let node):
            guard let project = lib.project(id) else { return }
            return fillStack(of: project, in: lib, node: node)
        case .appbridge:
            heading = "Appbridge"; labels = ("ASE File", "Swatches")
            rows.append(.item("Create New ASE", nil, 0, .appbridge, false))
            let folders = Dictionary(grouping: appbridge.files) { $0.url.deletingLastPathComponent().path }
            for path in folders.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
                rows.append(.divider(URL(fileURLWithPath: path).lastPathComponent))
                for file in folders[path, default: []].sorted(by: { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }) {
                    rows.append(.palette(file.id, file.url.lastPathComponent, file.swatches.count,
                                         file.swatches.map { $0.preview }, appbridge.selected == file.id, 0))
                }
            }
            rows.append(.item("Appbridge Settings", nil, 0, .appbridgeSettings, false))
        case .settings, .schema, .shortcuts, .halo, .sounds, .general, .colourManagement, .appleMenubar, .sharingSettings, .librarySettings, .tags, .share, .appbridgeSettings:
            heading = "Settings"; labels = ("Section", "")
            rows = SettingsNavigation.groups.map { group in
                .item(group.title, nil, 0, group.tabs[0].1, group.tabs.contains { $0.1 == place })
            }
        case .prepress(let n):
            heading = "PrePress"; labels = ("Workflow", "Steps")
            rows.append(.item("Which job is it?", nil, 0, .prepress(0), n == 0))
            rows.append(.divider("Workflows"))
            for route in PrePressPage.routes {
                rows.append(.item(route.title, route.later ? "Later" : "\(route.steps.count)", 0, .prepress(route.flow.rawValue), n == route.flow.rawValue))
            }
        case .lab:
            return   // no rail2: the page has its columns
        case .contrast:
            // The palettes the pair is picked from: the Lab's wheel when it is on offer, Favourites, each member's, then every palette; colours only.
            let chosen = contrastPage.state.palette
            if contrastPage.wheelOffered, let wheel = library.labPalette {
                rows.append(.item("Colour Lab Wheel", "\(wheel.colours.count)", 0, .lab, chosen == nil))
            }
            func group(_ title: String, key: String, _ list: [Swatch]) {
                let colours = palettes(list)
                guard !colours.isEmpty else { return }
                let state = fold("r2.contrast:\(key)", holds: true)
                rows.append(.group(title, 0, fold: state))
                guard state?.open ?? false else { return }
                rows += colours.map { s in .palette(s.id, s.name, s.entries.count, s.entries.map { shade[$0.hex] ?? Design.hex($0.hex) }, chosen == s.id, 1) }
            }
            group("Favourites", key: "favourites", library.favourites)
            for p in lib.orderedProjects { group(p.name, key: "project.\(p.id.uuidString)", lib.palettes(in: p.id)) }
            group("Palettes", key: "palettes", lib.libraryPalettes.filter { $0.claim == nil })
            group("Claimed Palettes", key: "claimed", lib.libraryPalettes.filter { $0.claim != nil })
        case .projects:
            heading = "Members"; labels = ("Collection", "Palettes")
            for c in SchemaTrial.collections {
                let inside = folderRows(c, indent: 1), state = fold("r2.collection:\(c.id.uuidString)", holds: !inside.isEmpty)
                rows.append(.group(c.name, 0, fold: state))
                if state?.open ?? false { rows += inside }
            }
        }
        rail2.set(heading: heading, labels: labels, rows: rows)
    }

    /// A member's stack in rail2: each group of the schema in its order, the app's own four holding
    /// what they always have, any other a label with its own groups inside it.
    private func fillStack(of project: Project, in lib: Library, node: UUID? = nil) {
        let schema = SchemaTrial.schema(for: project.id)
        let firstOverview = SchemaTrial.rows(of: schema).first { SchemaTrial.role(of: $0.node) == .information }?.node.id
        let held = lib.palettes(in: project.id)
        let own = lib.allTags.filter { lib.project(ofTag: $0) == project.id }
        var rows: [PaletteTable.Row] = []
        let shut = Prefs.railShut(in: library.catalogue)
        // A group with a role holds what it always has, wherever the pattern puts it; any other group is a label with its own beneath.
        // A group that holds rows carries its caret; shut, its rows and the groups inside it are left out.
        func walk(_ group: SchemaNode, _ indent: Int) {
            let here = StudioFrame.Place.group(project.id, group.id)
            var name = group.name, inner: [PaletteTable.Row] = []
            switch SchemaTrial.role(of: group) {
            case .information?:
                if name.isEmpty { name = "Information" }
                let overview = Place.overview(project.id, group.id)
                inner.append(.item("Overview", nil, indent, overview, place == overview || (place == .project(project.id) && group.id == firstOverview)))
            case .palettes?:
                if name.isEmpty { name = "Palettes" }
                let colours = lib.palettes(in: project.id, bucket: group.id, buckets: SchemaTrial.rows(of: schema).filter { SchemaTrial.role(of: $0.node) == .palettes }.map { $0.node.id }).filter { !$0.isTypography }
                func row(_ s: Swatch) -> PaletteTable.Row { .palette(s.id, s.name, s.entries.count, s.entries.map { shade[$0.hex] ?? Design.hex($0.hex) }, place == .palette(s.id), indent) }
                // This week's arrivals first, parted from the rest by a word on a hairline, when there are both.
                let week = Date().addingTimeInterval(-7 * 24 * 3600)
                let fresh = colours.filter { ($0.placedAt ?? $0.createdAt) >= week }, older = colours.filter { ($0.placedAt ?? $0.createdAt) < week }
                if !fresh.isEmpty && !older.isEmpty {
                    inner.append(.divider("Just Added")); inner += fresh.map(row)
                    inner.append(.divider("Earlier")); inner += older.map(row)
                } else { inner += colours.map(row) }
                if colours.isEmpty { inner.append(.item("None found", nil, indent, nil, false)) }
            case .typography?:
                if name.isEmpty { name = "Typography" }
                let type = held.filter { $0.isTypography }
                inner += type.map { .item($0.name, "\($0.styles?.count ?? 0)", indent, nil, false) }
                if type.isEmpty { inner.append(.item("None found", nil, indent, nil, false)) }
            case .tags?:
                if name.isEmpty { name = "Tags" }
                inner += own.map { .item($0, nil, indent, nil, false) }
                if own.isEmpty { inner.append(.item("None found", nil, indent, nil, false)) }
            case nil:
                break
            }
            let key = "r2.node:\(project.id.uuidString):\(group.id.uuidString)", open = !shut.contains(key)
            let holds = !inner.isEmpty || !group.children.isEmpty
            rows.append(.group(name, indent, here, place == here, fold: holds ? (key, open) : nil))
            guard open else { return }
            rows += inner
            for child in group.children { walk(child, indent + 1) }
        }
        let focused = node.flatMap { id in SchemaTrial.rows(of: schema).first { $0.node.id == id }?.node }
        for group in focused.map({ [$0] }) ?? schema.children { walk(group, 0) }
        let c = SchemaTrial.collection(of: project.id)
        rail2.set(heading: focused.map { project.name + " / " + $0.name } ?? project.name, labels: (SchemaTrial.memberName(of: c), "Items"), rows: rows)
    }

    private func fillPage(reuseGridIfSame:Bool=false) {
        if place == .designer {return}
        page.importImageControls=importsImages
        page.onRenamePalette=nil
        page.paletteSwatchCount=nil
        page.showsPaletteFilters=false
        page.paletteFilters.value=paletteFilter
        switch place {
        case .catalogue,.palettes,.project,.overview,.collection,.folder:page.showsPaletteFilters=true
        case .group(let project,let node):
            page.showsPaletteFilters=SchemaTrial.rows(of:SchemaTrial.schema(for:project)).first(where:{$0.node.id == node}).map{(SchemaTrial.role(of:$0.node) == .palettes || SchemaTrial.role(of:$0.node) == nil)} ?? false
        default:break
        }
        viewportHeader.preferredHeight=page.actionbarHeight(for:viewportHeader.bounds.width)
        page.paletteFilters.isHidden = !page.showsPaletteFilters
        page.paletteActions.isHidden=true
        page.paletteActions.back.isHidden=paletteGridReturn == nil
        if case .palette(let id)=place,let palette=displayLibrary.swatch(id) {
            page.onRenamePalette=linkedPalettes.canEdit(id) ? { [weak self] name in self?.library.rename(id,to:name) } : nil
            page.paletteSwatchCount=palette.entries.count
            page.paletteActions.isHidden=false
            page.paletteActions.configure(PaletteAssetHandler.presentation(palette,in:displayLibrary))
            page.paletteActions.target.isEnabled=linkedPalettes.canEdit(id)
            page.paletteActions.favourite.isEnabled=linkedPalettes.canEdit(id)
            page.paletteActions.review.isReadOnly = !linkedPalettes.canEdit(id)
            page.paletteActions.favourite.run={ [weak self] in self?.library.toggleFavourite(id) }
            page.paletteActions.target.run={ [weak self] in guard let self else{return};self.library.setTarget(self.displayLibrary.activeSwatchID == id ? nil:id) }
            page.paletteActions.review.onRating={ [weak self] rating in self?.library.apply("Rate Palette"){PaletteAssetHandler.setRating(rating,on:id,in:&$0)} }
            page.paletteActions.review.onFlag={ [weak self] flag in self?.library.apply("Flag Palette"){PaletteAssetHandler.setFlag(flag,on:id,in:&$0)} }
        }
        if !embeddedPage { pageLayout.renamePrimary = page.onRenamePalette }
        page.paletteCount = nil
        let lib = displayLibrary
        let palettesByID=Dictionary(lib.swatches.map{($0.id,$0)},uniquingKeysWith:{first,_ in first})
        page.grid.paletteReview={id in palettesByID[id].map{($0.name,$0.review ?? PaletteReview())}}
        let proofChannel=viewportHeader.channels.selectedChannel
        let proofDefinitions=Dictionary(lib.colours.compactMap{colour -> (String,ColourDefinition)? in
            colour.definition.map{(colour.hex,$0)}
        },uniquingKeysWith:{first,_ in first})
        let proofPalettes=palettesByID.mapValues{$0.entries.map(\.hex)}
        page.grid.canHover={item in item.hex != nil || item.id.map{proofPalettes[$0] != nil} == true}
        page.grid.onOriginal={item in
            guard let keys=item.hex.map({[$0]}) ?? item.id.flatMap({proofPalettes[$0]}) else{return nil}
            if item.sourceCMYK != nil{return item.colours}
            return Array(keys.prefix(item.colours.count)).enumerated().map{index,key in
                (proofDefinitions[key] ?? ColourKeys.definition(of:key) ?? ColourDefinition.of(hex:key))?.master.display ?? item.colours[index]
            }
        }
        if let proofChannel {page.grid.onPrint={item in
            guard item.sourceCMYK == nil else{return []}
            let keys=item.hex.map{[$0]} ?? item.id.flatMap{proofPalettes[$0]} ?? []
            let previews=keys.map{key -> TileGrid.PrintPreview? in
                guard let definition=proofDefinitions[key] ?? ColourKeys.definition(of:key) ?? ColourDefinition.of(hex:key) else{return nil}
                let rendering=Rendering.of(definition,in:proofChannel)
                guard let shown=rendering.shown,let difference=rendering.difference,difference.isFinite else{return nil}
                return .init(colour:shown.display,delta:difference)
            }
            return previews.allSatisfy{$0 != nil} ? previews.compactMap{$0}:[]
        }} else {page.grid.onPrint=nil}
        if case .palette(let id)=place{inspectedPalette=id}
        viewportHeader.channels.configure(library:lib,palette:inspectedPalette)
        var shade=self.shade
        var unavailable=0
        if canvasWorkspace, let channel=viewportHeader.channels.selectedChannel {
            for key in Array(shade.keys) {
                if let definition=lib.definition(of:key),let shown=Rendering.of(definition,in:channel).shown {shade[key]=shown.display}
                else {unavailable += 1}
            }
        }
        viewportHeader.channels.reportUnavailable(unavailable)
        page.configureImportPanel(nil)
        if imageIntakeWorkspace { viewportHeader.setIntakeMode(true,linking:intakeLinking) }
        let search = header.search.lowercased()
        AssetNotes.configureLooseStore(beside:library.store.url)
        func keep(_ name: String, _ hex: String?) -> Bool { search.isEmpty || name.lowercased().contains(search) || (hex?.lowercased().contains(search) ?? false) }
        // A colour's words: its name, and its value in the model the page's header has chosen.
        var paletteBars:[String:[NSColor]]=[:]
        if Prefs.showPaletteBars {
            for palette in lib.swatches {for key in Set(palette.entries.map(\.hex)){paletteBars[key,default:[]].append(identityColour(palette.id))}}
        }
        let coloursByHex=Dictionary(lib.colours.map{($0.hex,$0)},uniquingKeysWith:{first,_ in first})
        func tiles(_ hexes: [String], in palette: UUID?) -> [TileGrid.Item] {
            hexes.compactMap { hex in
                let name = lib.name(of: hex, in: palette)
                guard keep(name,hex) else{return nil}
                let caption:String
                if canvasWorkspace,let definition=lib.definition(of:hex) ?? ColourDefinition.of(hex:hex) {
                    if let channel=viewportHeader.channels.selectedChannel {
                        let rendering=Rendering.of(definition,in:channel)
                        let written=channel.rgb == .srgb ? rendering.value?.components(separatedBy:"   ").last:rendering.value
                        caption=(channel.isPrint ? (channel.space == ProfileChannel.printGrey ? "Grey":"CMYK"):channel.name)+"  "+(written ?? "Unavailable")
                    } else {caption=definition.sourceText}
                } else {caption=page.format.caption(hex)}
                if let palette {
                    let record=lib.note(of:hex,in:palette).map{AssetNotes.Record(name:name,description:$0)}
                    AssetNotes.cache(record,for:"colour:"+palette.uuidString+":"+hex.uppercased())
                }
                return TileGrid.Item(title:name+" / "+ColourFormat.hex.text(hex),caption:caption,colours:[shade[hex] ?? Design.hex(hex)],hex:hex,id:nil,paletteBars:paletteBars[hex] ?? [],createdAt:coloursByHex[hex]?.pickedAt,modifiedAt:coloursByHex[hex]?.tagsChangedAt)
            }
        }
        func cards(_ list: [Swatch]) -> [TileGrid.Item] {
            PaletteAssetHandler.filtered(list,by:paletteFilter,in:lib).compactMap { s in
                AssetNotes.cache(s.assetNotes,for:"asset:"+s.id.uuidString)
                let m=s.metadata
                var metadata:[String:String]=[:]
                func put(_ key:String,_ value:String?){if let value,!value.isEmpty{metadata[key]=value}}
                put("XMP.Title",m?.title ?? s.name);put("XMP.Description",m?.description);put("XMP.Creator",m?.creator);put("IPTC.CopyrightNotice",m?.rights);put("XMP.Rights",m?.rights);put("IPTC.Source",m?.source);put("XMP.Identifier",m?.identifier);put("IPTC.SubjectCode",m?.subjectCode);put("Colorgain.PrintProcess",m?.printProcess);put("Colorgain.ColourStandard",m?.colourStandard)
                if let tags=s.tagList.isEmpty ? m?.keywords:s.tagList,!tags.isEmpty{metadata["IPTC.Keywords"]=tags.joined(separator:", ");metadata["XMP.Subject"]=tags.joined(separator:", ")}
                return keep(s.name, nil) ? TileGrid.Item(title: s.name, caption: "\(s.entries.count) " + (s.entries.count == 1 ? "colour" : "colours"), colours: s.entries.prefix(s.entries.count <= 10 ? 10:8).map { shade[$0.hex] ?? Design.hex($0.hex) }, hex: nil, id: s.id,metadata:metadata,paletteColourCount:s.entries.count,linkedReference:isLinkedPalette(s.id),editingLocked:!linkedPalettes.canEdit(s.id),createdAt:s.createdAt,modifiedAt:[s.createdAt,s.nameChangedAt,s.tagsChangedAt,s.stylesChangedAt,s.review?.ratingChangedAt,s.review?.flagChangedAt,m?.changedAt].compactMap{$0}.max()) : nil
            }
        }
        func cardsOf(_ projects: [Project]) -> ([TileGrid.Item], Int) {
            let list = projects.flatMap { palettes(lib.palettes(in: $0.id)) }
            return (cards(list), list.reduce(0) { $0 + $1.entries.count })
        }
        var items: [TileGrid.Item] = [], title = "", meta = ("", "")
        page.show(.tiles)
        page.grid.note = nil
        switch place {
        case .project(let project):page.acceptsPaletteDrop = displayLibrary.project(project)?.isLocked == false
        case .group(let project,let bucket):page.acceptsPaletteDrop = displayLibrary.project(project)?.isLocked == false && SchemaTrial.rows(of:SchemaTrial.schema(for:project)).contains(where:{$0.node.id == bucket && SchemaTrial.role(of:$0.node) == .palettes})
        default:page.acceptsPaletteDrop = place == .appbridge && appbridge.current?.problem == nil && appbridge.current != nil && !appbridge.writing
        }
        let photographPage=canImportImagesFromCurrentPlace()
        page.assetProps=photographPage ? .photographs:AssetPageProps()
        page.showsPaletteFilters=page.showsPaletteFilters && page.assetProps.filters.contains(.paletteReview)
        page.paletteFilters.isHidden = !page.showsPaletteFilters
        page.showsFormat=page.assetProps.menus.contains(.colourFormat) && place != .appbridge && !imageIntakeWorkspace
        page.grid.showsHalo = true
        // A new member can be made wherever members are listed: the Members view, a collection, a folder.
        func newWord(_ c: SchemaCollection) -> String { "New " + SchemaTrial.memberName(of: c) }
        func memberCards(_ list: [Project]) -> [TileGrid.Item] {
            list.compactMap { p in
                let own = palettes(lib.palettes(in: p.id))
                var seen = Set<String>(), hexes: [String] = []
                for h in own.flatMap({ $0.entries.map { $0.hex } }) where !seen.contains(h) { seen.insert(h); hexes.append(h) }
                return keep(p.name, nil) ? TileGrid.Item(title: p.name, caption: plural(own.count, "palette"), colours: hexes.prefix(8).map { shade[$0] ?? Design.hex($0) }, hex: nil, id: p.id,createdAt:p.createdAt,modifiedAt:[p.createdAt,p.nameChangedAt,p.detailsChangedAt].compactMap{$0}.max()) : nil
            }
        }
        switch place {
        case .designer: break
        case .imageIntake:
            title = importsImages ? (intakeLinking ? "Link \(importKind)" : "Import \(importKind)"):"Import \(importKind)"
            meta = (intakeFolder?.lastPathComponent ?? "Choose a destination", library.catalogue)
            items = importsImages ? intakeImages:visibleImportFiles().map { url in
                let root=intakeFolder?.standardizedFileURL.path ?? ""
                let path=url.standardizedFileURL.path
                let relative=path.hasPrefix(root+"/") ? String(path.dropFirst(root.count+1)):url.lastPathComponent
                let parent=(relative as NSString).deletingLastPathComponent
                let count=intakeAssetColourCounts[path]
                return TileGrid.Item(title:importKind == "Palettes" ? url.deletingPathExtension().lastPathComponent:url.lastPathComponent,
                    caption:importKind == "Palettes" ? count.map{plural($0,"colour")} ?? "Reading…" : (parent == "." ? url.pathExtension.uppercased():parent),
                    colours:intakeAssetPreviews[path] ?? [],hex:nil,id:nil,imagePath:path,paletteColourCount:count ?? 0,selectionID:"import:"+path)
            }
            page.grid.note = !importsImages ? (items.isEmpty ? (intakeFolder == nil ? "Choose a source folder in Source to show its \(importKind) files here." : intakeNewOnly && !intakeAssetFiles.isEmpty ? "All compatible files in this folder have already been imported." : "No compatible \(importKind) files found in this folder.") : nil)
                : intakeImageLoading ? "Reading image files and preparing previews…"
                : intakeLinking ? "Select a source folder to review linked images here."
                : intakeFolder == nil ? "Choose a source folder in Source to show its images here."
                : items.isEmpty ? "No readable images found in this folder."
                : nil
        case .appbridge:
            title = "Appbridge"; meta = ("Directory: Choose on save", "Connected folders")
            if let file = appbridge.current {
                title = file.url.deletingPathExtension().lastPathComponent
                if file.problem == nil { page.showExport("Export A Copy…") }
                meta = ("Directory: " + AppbridgePath.display(file.url.deletingLastPathComponent().path), plural(file.swatches.count, "swatch"))
                if let problem = file.problem { page.grid.note = problem }
                else if file.swatches.isEmpty { page.grid.note = "Drop a palette from Rail 1 here to add its swatches." }
                items = file.swatches.enumerated().map { index, swatch in
                    TileGrid.Item(title: (swatch.group.isEmpty ? swatch.name : swatch.group) + " / " + (hexOf(swatch.preview) ?? "—"),
                        caption: page.format.caption(hexOf(swatch.preview) ?? "#000000", sourceCMYK: swatch.model == "CMYK" ? swatch.cmykText : nil), colours: [swatch.preview], hex: hexOf(swatch.preview), id: nil, sourceCMYK: swatch.model == "CMYK" ? swatch.cmykText : nil,selectionID:"ase:\(file.id):\(index)")
                }
            } else { page.grid.note = appbridge.files.isEmpty ? "Import an ASE file in Appbridge Settings to begin." : "Select an ASE file from Rail 2 to open its swatches." }
        case .projects:
            let all = SchemaTrial.collections
            items = memberCards(lib.orderedProjects)
            title = "Members"; meta = (plural(items.count, "member"), plural(all.count, "collection"))
            page.showNew(newWord(all.first ?? SchemaTrial.SchemaFile.fresh.collections[0]))
        case .schema:
            let all = SchemaTrial.collections
            title = "Schema"; meta = (plural(all.count, "collection"), plural(lib.projects.count, "member"))
            page.show(.schema)
        case .appbridgeSettings:
            title = "Appbridge"; meta = ("Adobe ASE", "Folders & Notifications")
            page.show(.appbridge)
        case .shortcuts:
            title = "Shortcuts"; meta = ("\(QuickKeys.commands.count) quick keys", plural(Shortcuts.commands.count, "command"))
            page.show(.shortcuts)
        case .appleMenubar:
            title = "Apple Menubar"; meta = ("Colour Tools", "App Store")
            page.show(.appleMenubar)
        case .sharingSettings:
            title = "Sharing"; meta = ("QR Generation Settings", "Offline Colour Exchange")
            page.show(.sharingSettings)
        case .help:
            title = "Help"; meta = ("Colorgain", "Getting Started")
            page.showsFormat = false
            page.show(.help)
        case .qrImport:
            title = "Import"; meta = ("QR Colour Exchange", "Camera · Image · Clipboard")
            page.show(.qrImport)
        case .colourManagement(let index):
            title = "Colour Management"; meta = ("", "")
            page.show(.colourManagement(max(0, min(2, index))))
        case .general:
            title = "General"; meta = ("Setup & Preferences", "")
            page.show(.general)
        case .librarySettings:
            title = "Library"; meta = ("Palette Settings", "")
            page.show(.librarySettings)
        case .sounds:
            title = "Sounds"; meta = ("Audio feedback", "Copy and pick")
            page.show(.sounds)
        case .halo:
            title = "Halo"; meta = ("Scrolling", "Colours")
            page.show(.halo)
        case .tags:
            title = "Tags"; meta = (plural(lib.allTags.count, "tag"), "Global and scoped")
            page.show(.tags)
        case .share:
            title = sharePage.pageTitle; meta = (sharePage.pageTitle, "One catalogue file")
            page.show(.share)
        case .prepress(let n):
            let flow = PrePressPage.Flow(rawValue: n) ?? .menu
            prePressPage.flow = flow
            if let route = PrePressPage.route(flow) { title = route.title; meta = (route.who, route.steps.joined(separator: " · ")) }
            else { title = "PrePress"; meta = ("Four workflows", "One artefact each") }
            page.show(.prepress)
        case .lab:
            title = "Colour Lab"; meta = ("The wheel", "Build on a colour")
            page.show(.lab)
        case .contrast:
            title = "Contrast"; meta = ("Check a pair", "WCAG 2 \u{00B7} APCA")
            page.show(.contrast)
        case .catalogue:
            if SchemaTrial.structure != nil, !page.onboardingDismissed, (lib.projects.isEmpty || page.journey != nil) {
                if page.journey == nil {
                    let journey=CatalogueJourneyView(library:library)
                    journey.onBrowse={ [weak self] in self?.page.onboardingDismissed=true;self?.reload() }
                    page.journey=journey;page.addSubview(journey)
                }
                page.journey?.refresh();page.show(.welcome);page.showsPaletteFilters=false;page.paletteFilters.isHidden=true
                title="Welcome to Colorgain";meta=("",library.catalogue)
            } else {
            items = cards(palettes(lib.swatches))
            title = "All Palettes"; meta = ("\(items.count) palettes", library.catalogue)
            }
        case .palette(let id):
            let s = lib.swatch(id)
            items = tiles(lib.hexes(inSwatch: id, by: library.paletteSort), in: id)
            title = s?.name ?? "Palette"
            if let source = linkedPalettes.sources[id] {
                page.paletteSwatchCount = s?.entries.count
                page.grid.note = source.problem
            }
            page.paletteCount = "\(items.count) Colours"
            meta = (linkedPalettes.sources[id].map { $0.problem == nil ? "Linked Reference" : "Linked Reference · Unavailable" } ?? s?.projectID.flatMap { lib.project($0)?.name } ?? "No Project", "")
        case .project(let id), .overview(let id, _):
            let list = palettes(lib.palettes(in: id))
            items = cards(list)
            title = lib.project(id)?.name ?? "Project"
            meta = ("\(items.count) palettes", "\(list.reduce(0) { $0 + $1.entries.count }) colours")
        case .group(let id, let nid):
            // A group's page: what it holds in the member. Palettes and Typography as cards; Information and Tags their words; a group of the member's own, the palettes beneath it.
            let tree = SchemaTrial.schema(for: id)
            let node = SchemaTrial.rows(of: tree).first { $0.node.id == nid }?.node
            let held = lib.palettes(in: id), member = lib.project(id)?.name ?? "Member"
            title = node?.name ?? "Group"
            if photographPage {
                let records=photoRecords(project:id,bucket:nid)
                items=records.compactMap{record,index in
                    guard let url=try? record.url(in:index.deletingLastPathComponent()),keep(record.name,nil) else{return nil}
                    let dates=try? url.resourceValues(forKeys:[.creationDateKey,.contentModificationDateKey])
                    return TileGrid.Item(title:record.name,caption:record.external ? "Linked Original":"Image",colours:[],hex:nil,id:nil,imagePath:url.path,linkedReference:record.external,createdAt:dates?.creationDate,modifiedAt:dates?.contentModificationDate)
                }
                switch photoSort {
                case .fileName:items.sort{$0.title.localizedStandardCompare($1.title) == .orderedAscending}
                case .fileType:items.sort{URL(fileURLWithPath:$0.title).pathExtension.localizedCaseInsensitiveCompare(URL(fileURLWithPath:$1.title).pathExtension) == .orderedAscending}
                default:break
                }
                meta=(plural(items.count,"image"),member)
                page.grid.note=records.isEmpty ? "No images yet. Add photographs or images to this folder." : nil
                page.showNew("Add Images…")
                break
            }
            switch node.flatMap({ SchemaTrial.role(of: $0) }) {
            case .palettes?:
                let list = palettes(lib.palettes(in: id, bucket: nid, buckets: SchemaTrial.rows(of: tree).filter { SchemaTrial.role(of: $0.node) == .palettes }.map { $0.node.id })); items = cards(list)
                meta = (plural(list.count, "palette"), member)
            case .typography?:
                // A typography palette holds styles, not colours: its card says how many, and the button makes another in this member.
                let list = held.filter { $0.isTypography }
                items = list.compactMap { s in keep(s.name, nil) ? TileGrid.Item(title: s.name, caption: plural(s.styles?.count ?? 0, "style"), colours: [], hex: nil, id: s.id,createdAt:s.createdAt,modifiedAt:[s.createdAt,s.nameChangedAt,s.stylesChangedAt,s.tagsChangedAt].compactMap{$0}.max()) : nil }
                meta = (plural(list.count, "typography palette"), member)
                page.showNew("New Typography Palette")
            case .tags?:
                let own = lib.allTags.filter { lib.project(ofTag: $0) == id }
                items = own.map { t in TileGrid.Item(title: t, caption: plural(lib.hexes(tagged: t).count, "colour"), colours: lib.hexes(tagged: t).prefix(8).map { shade[$0] ?? Design.hex($0) }, hex: nil, id: nil) }
                meta = (plural(own.count, "tag"), member)
            case .information?:
                // The member's notes as the page's words, under the rule; the Labels say only whether there are any.
                let notes = (lib.project(id)?.details?[ProjectField.notes.rawValue] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                items = []
                meta = (notes.isEmpty ? "No notes yet" : "Notes", member)
                page.grid.note = notes.isEmpty ? "No notes yet. Describe this member under Settings, Schema." : notes
            case nil:
                // A heading such as Web aggregates its own descendant buckets only.
                let allBuckets = SchemaTrial.rows(of: tree).filter { SchemaTrial.role(of: $0.node) == .palettes }.map { $0.node.id }
                let inside = node.map { SchemaTrial.rows(of: $0).filter { SchemaTrial.role(of: $0.node) == .palettes }.map { $0.node.id } } ?? []
                let list = palettes(inside.flatMap { lib.palettes(in: id, bucket: $0, buckets: allBuckets) }); items = cards(list)
                meta = (plural(list.count, "palette"), member)
            }
        case .collection(let id):
            guard let c = SchemaTrial.collections.first(where: { $0.id == id }) else { return }
            let m = members(of: c)
            let (made, colours) = cardsOf(m)
            items = made; title = c.name
            meta = ("\(m.count) " + SchemaTrial.plural(SchemaTrial.memberName(of: c)).lowercased(), "\(colours) colours")
        case .folder(let cid, let fid):
            guard let c = SchemaTrial.collections.first(where: { $0.id == cid }), let f = c.folders.first(where: { $0.id == fid }) else { return }
            let m = members(of: c, folder: .some(fid))
            let (made, colours) = cardsOf(m)
            items = made; title = f.name
            meta = ("\(m.count) " + SchemaTrial.plural(SchemaTrial.memberName(of: c)).lowercased(), "\(colours) colours")
        case .palettes:
            let list: [Swatch]
            switch workspaceFilter {
            case "favourites": list=palettes(lib.orderedFavourites); title="Favourites"
            case "claimed": list=palettes(lib.swatches.filter{$0.claim != nil}); title="Claimed Palettes"
            case "palettes": list=palettes(lib.libraryPalettes); title="Unassigned Palettes"
            case "typography": list=lib.libraryPalettes.filter(\.isTypography); title="Typography"
            default: list=palettes(lib.swatches); title="All Palettes"
            }
            items = cards(list)
            meta = ("\(items.count) palettes", "\(lib.orderedProjects.count) projects")
        case .settings:
            let n = library.availableCatalogues().count
            title = "Catalogues"; meta = (library.catalogue, "\(n) " + (n == 1 ? "catalogue" : "catalogues"))
            page.show(.catalogues)
        }
        switch place {
        case .collection(let id): if let c = SchemaTrial.collections.first(where: { $0.id == id }) { page.showNew(newWord(c)); page.showExport("Export Collection\u{2026}") }
        case .folder(let cid, _): if let c = SchemaTrial.collections.first(where: { $0.id == cid }) { page.showNew(newWord(c)); page.showExport("Export \(c.folderName ?? "Group")\u{2026}") }
        case .project(let id), .overview(let id, _): page.showExport("Export \(SchemaTrial.memberName(of: SchemaTrial.collection(of: id)))\u{2026}")
        default: break
        }
        page.settingsDestination = isSettings(place) ? place : nil
        if let group = SettingsNavigation.group(for: place) { title = group.title }
        page.toolTip = place == .appbridge ? appbridge.current?.url.deletingLastPathComponent().path : nil
        analysisPalettes=items.compactMap{item in item.id.flatMap{palettesByID[$0]}}
        if case .palette(let selected)=place { metadataPane.palette=lib.swatch(selected) }
        else { metadataPane.palette=paletteSelection.ids.count == 1 ? paletteSelection.ids.first.flatMap{lib.swatch($0)} : nil }
        if page.showsPaletteFilters {meta.0=plural(items.count,"palette")}
        page.grid.selectionScope=String(describing:place)
        page.grid.notePaletteID = { if case .palette(let id) = place { return id }; return nil }()
        page.grid.noteScope = library.store.url.path
        page.set(title: title, meta: meta, items: items,reuseGridIfSame:reuseGridIfSame)
        page.grid.showsHalo = true
        let catalogueID=CatalogueTree.catalogue(in:library.store.root)?.id ?? UUID()
        page.configureMetadataFilters(store:MetadataFilterStore(catalogueURL:library.store.url),catalogueID:catalogueID)
        page.configureImageIntake(imageIntakeWorkspace,kind:importKind,linking:intakeLinking,gridColumns:intakeGridColumns,fullView:intakeFullView)
        page.grid.imageFullView=photographPage ? photoFullView:(imageIntakeWorkspace && intakeFullView)
        let metadataFilterAvailable:Bool
        switch place {
        case .catalogue,.palette,.project,.overview,.group,.collection,.folder,.palettes,.projects,.appbridge: metadataFilterAvailable=true
        default: metadataFilterAvailable=imageIntakeWorkspace
        }
        viewportHeader.configureMetadataFilter(visible:metadataFilterAvailable && page.assetProps.filters.contains(.metadata),active:page.metadataFilterIsExpanded)
        page.grid.selectedImagePaths=intakeSelectedPaths
        intakeTargetPane.selectedCount=intakeSelectedPaths.count
        intakeTargetPane.setContext(catalogue:library.store.url.deletingPathExtension().lastPathComponent,kind:importKind)
        viewportHeader.configureImageIntake(imageIntakeWorkspace,kind:importKind,linking:intakeLinking,selectAll:intakeSelectAll,newOnly:intakeNewOnly,fullView:intakeFullView,sort:intakeSort,imageCount:importsImages ? intakeImages.count:visibleImportFiles().count,selectedCount:intakeSelectedPaths.count,columns:intakeGridColumns)
        viewportFooter.configureImageIntake(imageIntakeWorkspace,kind:importKind,linking:intakeLinking,selectAll:intakeSelectAll,newOnly:intakeNewOnly,fullView:intakeFullView,sort:intakeSort,imageCount:importsImages ? intakeImages.count:visibleImportFiles().count,selectedCount:intakeSelectedPaths.count,columns:intakeGridColumns)
        viewportFooter.configureImageBrowser(active:photographPage,fullView:photoFullView,index:page.grid.currentImageIndex+1,total:items.count,
            sort:page.assetProps.menus.contains(.sort) && photographPage ? photoSort:nil,
            view:page.assetProps.menus.contains(.imageView),paginated:page.assetProps.pagination == .imageByImage)
        if imageIntakeWorkspace && !importsImages {
            viewportFooter.setSelectionCount(intakeSelectedPaths.count,total:visibleImportFiles().count)
        }
        page.grid.chosenHex = chosenHex
        inspectorPane.catalogue=library.catalogue;inspectorPane.total=palettes(lib.swatches).count
        inspectorPane.displayColours=shade
        if case .palette(let id)=place{inspectedPalette=id}
        inspectorPane.palette=inspectedPalette.flatMap{lib.swatch($0)}
        page.grid.selectedPalette=inspectedPalette
        filmstrip.update(palettes(lib.swatches),selected:inspectedPalette,colours:shade)
        refreshAnalysis()
        if !embeddedPage,let active=pageLayout.active.controller{followPane(active)}
    }

    private func expandAnalysis(_ kind:ExpandedAnalysis) {
        expandedAnalysis=kind
        if kind == .histogram {expandedHistogram.copyConfiguration(from:histogramPane)}
        bloomWorkspace.present(kind == .bloom ? expandedBloom:expandedHistogram)
        refreshAnalysis();needsLayout=true
    }
    @discardableResult func closeExpandedPanel()->Bool {
        guard expandedAnalysis != nil else{return false}
        expandedAnalysis=nil;page.expandedPanelTitle=nil;window?.makeFirstResponder(page.grid);needsLayout=true;return true
    }
    private func followPane(_ pane:StudioFrame){
        if pane === self {refreshAnalysis();inspectorPane.palette=inspectedPalette.flatMap{pane.displayLibrary.swatch($0)};return}
        lastAnalysisKey=nil
        let previous=place;place=pane.place;fillLibraryRail();fillContextRail();place=previous
        let palette=pane.inspectedPalette.flatMap{pane.displayLibrary.swatch($0)}
        inspectedPalette=pane.inspectedPalette
        inspectorPane.palette=palette
        histogramPane.update(palette,library:pane.displayLibrary,selected:pane.analysisColour)
        bloomPane.update(palette,library:pane.displayLibrary,selected:pane.analysisColour)
    }
    private func refreshAnalysis() {
        let lib=displayLibrary
        let visible=analysisPalettes
        if case .palette(let id)=place { inspectedPalette=id }
        else if !visible.contains(where:{$0.id==inspectedPalette}) {inspectedPalette=visible.first?.id;analysisColour=nil}
        let palette=inspectedPalette.flatMap{lib.swatch($0)}
        page.expandedPanelTitle=canvasWorkspace ? expandedAnalysis.map{($0 == .bloom ? "Delta Bloom":"Histograms")+" > "+(palette?.name ?? "Select A Palette")} : nil
        expandedBloom.spectrumWidth=page.grid.paletteTileWidth;expandedHistogram.spectrumWidth=page.grid.paletteTileWidth
        let key=AnalysisKey(revision:library.revision,palette:palette?.id,colour:analysisColour,channel:viewportHeader.channels.selectedChannel,print:PrintCondition.current,expanded:expandedAnalysis)
        if key != lastAnalysisKey {
            lastAnalysisKey=key
            histogramPane.update(palette,library:lib,selected:analysisColour)
            bloomPane.update(palette,library:lib,selected:analysisColour)
            if expandedAnalysis == .bloom {expandedBloom.update(palette,library:lib,selected:analysisColour)}
            if expandedAnalysis == .histogram {expandedHistogram.update(palette,library:lib,selected:analysisColour)}
        }
        bloomWorkspace.update(visible.isEmpty ? palette.map{[$0]} ?? []:visible,selected:inspectedPalette)
        onPaneChange?()
    }

    /// Every step the catalogue took, newest first, each with what it did: the colours that came or went, by name, and the
    /// member it touched. On a member, or one of its palettes or groups, only that member's own steps: each has a history of its own.
    private func fillHistory() {
        let lib = library.library, log = history.global ? library.globalHistory : library.history
        let steps = log.steps
        var member: UUID?
        switch place {
        case .project(let id), .overview(let id, _), .group(let id, _): member = id
        case .palette(let id): member = lib.swatch(id)?.projectID
        default: break
        }
        var rows: [HistoryRail.Row] = []
        for i in steps.indices.reversed() {
            let step = steps[i]
            if !history.global, let m = member, step.project != m { continue }
            let change = log.change(at: i)
            var parts: [String] = []
            if !change.added.isEmpty { parts.append(change.added.prefix(2).map { lib.name(of: $0, in: nil) }.joined(separator: ", ") + (change.added.count > 2 ? " +\(change.added.count - 2)" : "") + " added") }
            if !change.removed.isEmpty { parts.append(change.removed.prefix(2).map { lib.name(of: $0, in: nil) }.joined(separator: ", ") + (change.removed.count > 2 ? " +\(change.removed.count - 2)" : "") + " removed") }
            if let p = step.project.flatMap({ lib.project($0)?.name }) { parts.append(p) }
            let chips = Array((change.added + change.removed).prefix(4))
            rows.append(HistoryRail.Row(symbol: stepSymbol(for: step.title), title: step.title, detail: parts.joined(separator: "  \u{00B7}  "), time: when(step.date),
                                        chips: chips.map { shade[$0] ?? Design.hex($0) }, hex: chips.first))
            if rows.count >= 120 { break }
        }
        var dated = Array(zip(steps.indices.reversed().filter { history.global || member == nil || steps[$0].project == member }.prefix(rows.count).map { steps[$0].date }, rows))
        if history.global { dated += header.savedSearches.map { ( $0.date, HistoryRail.Row(symbol: "magnifyingglass", title: "Search: " + $0.query, detail: "Search journey", time: when($0.date), chips: [], hex: nil)) } }
        history.set(rows: dated.sorted { $0.0 > $1.0 }.prefix(120).map { $0.1 })
    }

    private func fillFooter() {
        let lib = library.library
        let hex = chosenHex ?? lib.colours.max { $0.pickedAt < $1.pickedAt }?.hex ?? Brand.masterHex
        let name = hex == Brand.masterHex && chosenHex == nil && lib.colours.isEmpty ? Brand.masterName : lib.name(of: hex, in: nil)
        footer.set(hex: hex, name: name)
    }

    private func act(_ i: Int) {
        let hex = footer.hex
        switch i {
        case 0: copyToClipboard(hex)
        case 1: copyToClipboard(footer.name)
        default: copyToClipboard(ColourFormat.cssRGB.text(hex))
        }
    }
}

// MARK: - The header, 94 high

/// The wordmark, the tabs, Search, the tile-size slider and the avatar, all on one baseline.
final class MiniSlider: ClickCursorView {
    override var handCursorRects:[NSRect]{[bounds]}

    var value: CGFloat = 0.5 { didSet { needsDisplay = true } }
    var onChange: ((CGFloat) -> Void)?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let y = bounds.midY
        hairline(x: 0, y: y, width: bounds.width, Design.rule)
        fill(NSRect(x: 0, y: y, width: bounds.width * value, height: 1), Design.ink)
        fill(NSRect(x: (bounds.width - 8) * value, y: y - 4, width: 8, height: 8), Design.ink)
    }
    override func mouseDown(with event: NSEvent) { track(event) }
    override func mouseDragged(with event: NSEvent) { track(event) }
    private func track(_ e: NSEvent) {
        let x = convert(e.locationInWindow, from: nil).x
        value = max(0, min(1, (x - 4) / (bounds.width - 8)))
        onChange?(value)
    }
}

// MARK: - A rail

/// A Card with 22 top padding and a heading row with the arrow; rows below are drawn by the subclass.
/// The rail scrolls when its rows pass its height, the scroller hidden until the wheel moves.
/// The library rail: groups of rows, the name left and a tabular count right; a row one step in sits
/// inside the row above it, as a member sits in its folder.
private final class RailSelectionBar: NSView {
    var count = 0 { didSet { needsDisplay = true } }
    var haloRight: CGFloat = 0 { didSet { needsDisplay = true } }
    var onHalo: ((NSView, NSRect) -> Void)?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        fill(bounds, Design.card); hairline(x: 0, y: 0, width: bounds.width)
        Design.attributed("\(count) Palettes Selected", .bodyStrong).draw(x: Design.App.margin, baseline: bounds.midY + 5, width: max(0, haloRight - Design.App.margin - 28))
        Design.haloMark(in: NSRect(x: haloRight - 8, y: bounds.midY - 8, width: 16, height: 16), colour: Design.ink)
    }
    override func resetCursorRects() { addCursorRect(NSRect(x: haloRight - 14, y: 0, width: 28, height: bounds.height), cursor: .pointingHand) }
    override func mouseDown(with event: NSEvent) { let p = convert(event.locationInWindow, from: nil); if abs(p.x - haloRight) < 18 { onHalo?(self, NSRect(x: haloRight - 8, y: bounds.midY - 8, width: 16, height: 16)) } }
}

final class LibraryRail: StudioRail {
    override var handCursorRects:[NSRect]{super.handCursorRects+(collapsed ? [NSRect(x:0,y:0,width:bounds.width,height:AreaHeader.height)]+markHits.map{$0.0}:[])}

    /// A group label; a row with its count; a palette on two lines, its name over its colours with the count on the second line.
    /// A palette row: its name, count, colours, whether it is a favourite and the picks' target, and the member it sits in, at an indent.
    struct DropDestination: Equatable { let project: UUID; let bucket: UUID? }
    struct PaletteRow { let id: UUID; let name: String; let count: Int; let colours: [NSColor]; let favourite: Bool; let target: Bool; let project: UUID?; let indent: Int; var bucket: UUID? = nil }
    /// A group of a member's stack: its name, what it holds, the member, its indent, and whether a palette can be dropped on it.
    /// A tag of a member, under its Tags group: the tag, how many colours wear it, the member, the indent; or the link to edit them.
    /// A group's key is what its open or shut state is kept under; nil keys it by its title.
    enum Row { case group(String, key: String? = nil), row(String, Int, StudioFrame.Place, Int), palette(PaletteRow), node(String, Int, UUID, Int, Bool, UUID), tag(String, Int, UUID, Int) }
    var onPaletteSelection: ((UUID, [UUID], NSEvent.ModifierFlags) -> Void)?
    var onDeleteSelection: (() -> Void)?
    var onContext: ((StudioFrame.Place, NSView, NSPoint) -> Void)?
    var onPick: ((StudioFrame.Place) -> Void)?
    /// The buckets shut, by key, and a bucket opened or shut by its caret: its key, and whether it is now shut.
    var shut: Set<String> { get { list.shut } set { list.shut = newValue; needsLayout = true } }
    var onShut: ((String, Bool) -> Void)?
    /// A name typed over where it is drawn: the place renamed, and the new name.
    var onRename: ((StudioFrame.Place, String) -> Void)?
    /// A palette dropped on a member: the palette, then the member it lands in.
    var onDrop: ((UUID, DropDestination) -> Void)?
    /// The three icons on a palette row: the star, the picks' target, and the gear, which opens the halo over the icon's rect in the body's coordinates.
    var onFavourite: ((UUID) -> Void)?
    var onTarget: ((UUID) -> Void)?
    var onGear: ((UUID, NSView, NSRect) -> Void)?
    var selectedPalettes: Set<UUID> { get { list.selectedPalettes } set { list.selectedPalettes = newValue; selectionBar.count = newValue.count; needsLayout = true } }
    var selectionHeight = Design.App.unit { didSet { needsLayout = true } }
    var onSelectionHalo: ((NSView, NSRect) -> Void)?
    private let selectionBar = RailSelectionBar()
    private var list: Body { body as! Body }
    override func layout() {
        super.layout()
        let show = !collapsed && selectedPalettes.count > 1
        selectionBar.isHidden = !show
        if show { scroll.frame.size.height = max(0, scroll.frame.height - selectionHeight) }
        selectionBar.frame = NSRect(x: 0, y: bounds.height - selectionHeight, width: bounds.width, height: selectionHeight)
        selectionBar.haloRight = bounds.width - insetRight - 12
    }
    /// Shut to a narrow strip: the arrow to open it, then a mark for each of its groups, the chosen one's filled.
    var collapsed = false { didSet { if collapsed != oldValue { scroll.isHidden = collapsed; needsDisplay = true } } }
    static let collapsedWidth: CGFloat = 48
    private var markHits: [(NSRect, StudioFrame.Place)] = []
    init() {
        super.init(body: Body()); addSubview(selectionBar)
        selectionBar.onHalo = { [weak self] view, rect in self?.onSelectionHalo?(view, rect) }
        list.onPaletteSelection = { [weak self] id, order, modifiers in self?.onPaletteSelection?(id, order, modifiers) }
        list.onDeleteSelection = { [weak self] in self?.onDeleteSelection?() }
        heading = "Library"; labels = ("Name", "Count")
        list.onContext = { [weak self] place, view, point in self?.onContext?(place, view, point) }
        list.onPick = { [weak self] p in self?.onPick?(p) }
        list.onRename = { [weak self] p, n in self?.onRename?(p, n) }
        list.onDrop = { [weak self] s, m in self?.onDrop?(s, m) }
        list.onFavourite = { [weak self] id in self?.onFavourite?(id) }
        list.onTarget = { [weak self] id in self?.onTarget?(id) }
        list.onGear = { [weak self] id, v, r in self?.onGear?(id, v, r) }
        list.onShut = { [weak self] key, shut in self?.needsLayout = true; self?.onShut?(key, shut) }
    }
    required init?(coder: NSCoder) { fatalError() }
    func set(rows: [Row], chosen: StudioFrame.Place) { list.rows = rows; list.chosen = chosen; needsLayout = true; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        guard collapsed else { super.draw(dirtyRect); return }
        let x = (Self.collapsedWidth - 16) / 2
        Design.arrow(16).draw(in: NSRect(x: x, y: AreaHeader.headingBaseline - 13, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        hairline(x: x, y: AreaHeader.rule, width: 16, Design.rule)
        // One icon per group on the unit's line, in the house stroke: the catalogue a grid of four, favourites a star, a collection a
        // folder, palettes three bands. Ink for the group holding the chosen place, quiet for the rest.
        markHits = []
        var y = AreaHeader.height, groupPlace: StudioFrame.Place? = nil, groupHas = false, groupName = ""
        var marks: [(StudioFrame.Place, Bool, String)] = []
        for r in list.rows {
            switch r {
            case .group(let title, _):
                if let p = groupPlace { marks.append((p, groupHas, groupName)) }
                groupPlace = nil; groupHas = false; groupName = title
            case .row(_, _, let p, _):
                if groupPlace == nil { groupPlace = p }
                if p == list.chosen { groupHas = true }
            case .palette(let pr):
                if groupPlace == nil { groupPlace = .palette(pr.id) }
                if .palette(pr.id) == list.chosen { groupHas = true }
            case .node(_, _, let pid, _, _, _), .tag(_, _, let pid, _):
                if groupPlace == nil { groupPlace = .project(pid) }
            }
        }
        if let p = groupPlace { marks.append((p, groupHas, groupName)) }
        for (p, on, name) in marks {
            let g = NSRect(x: (Self.collapsedWidth - 16) / 2, y: y + Design.App.textBaseline - 13, width: 16, height: 16)
            (on ? Design.ink : Design.quiet).setStroke()
            let path = NSBezierPath(); path.lineWidth = 1.2; path.lineJoinStyle = .miter
            switch name {
            case "Catalogue":
                for (dx, dy) in [(0, 0), (9, 0), (0, 9), (9, 9)] as [(CGFloat, CGFloat)] { path.appendRect(NSRect(x: g.minX + dx + 0.5, y: g.minY + dy + 0.5, width: 6, height: 6)) }
            case "Favourites":
                let c = NSPoint(x: g.midX, y: g.midY + 0.5), r1: CGFloat = 7.5, r2: CGFloat = 3
                for k in 0..<10 {
                    let a = -CGFloat.pi / 2 + CGFloat(k) * CGFloat.pi / 5, r = k % 2 == 0 ? r1 : r2
                    let pt = NSPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                    if k == 0 { path.move(to: pt) } else { path.line(to: pt) }
                }
                path.close()
            case "Palettes":
                for dx in [0, 5.5, 11] as [CGFloat] { path.appendRect(NSRect(x: g.minX + dx + 0.5, y: g.minY + 0.5, width: 4, height: 15)) }
            default:
                // A folder: the tab, then the body.
                path.move(to: NSPoint(x: g.minX + 0.5, y: g.maxY - 0.5)); path.line(to: NSPoint(x: g.minX + 0.5, y: g.minY + 2.5)); path.line(to: NSPoint(x: g.minX + 6, y: g.minY + 2.5))
                path.line(to: NSPoint(x: g.minX + 8, y: g.minY + 5)); path.line(to: NSPoint(x: g.maxX - 0.5, y: g.minY + 5)); path.line(to: NSPoint(x: g.maxX - 0.5, y: g.maxY - 0.5)); path.close()
            }
            path.stroke()
            markHits.append((NSRect(x: 0, y: y, width: Self.collapsedWidth, height: Design.App.unit), p))
            y += Design.App.unit
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard collapsed else { super.mouseDown(with: event); return }
        let p = convert(event.locationInWindow, from: nil)
        if p.y < AreaHeader.height { onArrow?(); return }
        if let m = markHits.first(where: { $0.0.contains(p) }) { onArrow?(); onPick?(m.1) }
    }

    final class Body: RailBody, NSDraggingSource {
    override var handCursorRects:[NSRect]{hits.map{$0.0}+iconHits.map{$0.0}+caretHits.map{$0.0}+nameHits.map{$0.0}+tagLinks.map{$0.0}}

        /// Every row the rail has, open or shut; `shown` is what is drawn.
        var rows: [Row] = [] { didSet { rebuild() } }
        /// The buckets shut, by key: what is inside them is not shown.
        var shut: Set<String> = [] { didSet { rebuild() } }
        var selectedPalettes: Set<UUID> = [] { didSet { rollover.settle(); needsDisplay = true } }
        var chosen: StudioFrame.Place = .catalogue { didSet { rollover.settle(); needsDisplay = true } }
        var onPaletteSelection: ((UUID, [UUID], NSEvent.ModifierFlags) -> Void)?
    var onDeleteSelection: (() -> Void)?
    var onContext: ((StudioFrame.Place, NSView, NSPoint) -> Void)?
    var onPick: ((StudioFrame.Place) -> Void)?
        var onRename: ((StudioFrame.Place, String) -> Void)?
        var onDrop: ((UUID, DropDestination) -> Void)?
        var onFavourite: ((UUID) -> Void)?
        var onTarget: ((UUID) -> Void)?
        var onGear: ((UUID, NSView, NSRect) -> Void)?
        var onShut: ((String, Bool) -> Void)?
        /// The icons on palette rows, with what a press on each does.
        private var iconHits: [(NSRect, Int, UUID)] = []
        /// The carets, each with the key of the bucket it opens and shuts.
        private var caretHits: [(NSRect, String)] = []
        /// The Edit Tags rows, each with the member it is under.
        private var tagLinks: [(NSRect, UUID)] = []
        static var row: CGFloat { unit }
        static var two: CGFloat { unit * 2 }
        /// Retained for a future tree presentation; keep the current rail free of elbow connectors.
        static let showsTreeConnectors = false
        static var groupAbove: CGFloat { unit }
        static let step: CGFloat = 16
        /// After a row's 14 mark, the caret's slot, then the words: mark, caret, words, on every row so the words of a level align
        /// whether or not the row holds anything. A group heading has no mark: its caret stands on the column, its words where its rows' marks are.
        static let caretSlot: CGFloat = 14
        static var words: CGFloat { 14 + caretSlot }
        static let headingWords: CGFloat = 12
        private var hits: [(NSRect, StudioFrame.Place)] = []
        /// Every name that can be renamed where it is: its rect, with the line at `line` into it, its place, its words and its style.
        private var nameHits: [(NSRect, StudioFrame.Place, String, Design.Text)] = []
        /// The place whose name is being typed over, so the drawn name stays out of the field's way.
        private var renaming: StudioFrame.Place?
        /// The palette under the mouse at mouseDown, so a drag can take it; the member a drag is over.
        private var pressed: (UUID, String, [NSColor])?
        private var pendingPaletteClick: (NSRect, StudioFrame.Place)?
        /// Where and when the mouse went down, so a drag starts only once the pointer has clearly left the press.
        private var pressedAt: (NSPoint, TimeInterval) = (.zero, 0)
        private var target: DropDestination?

        private let rollover = Rollover<String>()
        private var rowHits: [(NSRect, String)] = []
        override init(frame: NSRect) {
            super.init(frame: frame); registerForDraggedTypes([PaletteDrag.type])
            rollover.barberPole = true
            rollover.keys = { [weak self] in self?.shown.map { Self.key(of: $0.row) } ?? [] }
            rollover.locked = { [weak self] key in
                guard let self else { return false }
                return self.shown.contains { Self.key(of: $0.row) == key && self.selected($0.row) }
            }
            rollover.redraw = { [weak self] in self?.needsDisplay = true }
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .activeInActiveApp], owner: self))
        }
        private func selected(_ row: Row) -> Bool {
            switch row {
            case .row(_, _, let place, _): return place == chosen
            case .node(_, _, let project, _, _, let node): return chosen == .group(project, node)
            case .palette(let palette): return selectedPalettes.contains(palette.id)
            default: return false
            }
        }
        override func mouseMoved(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            rollover.moved(rowHits.first { $0.0.contains(point) }?.1)
        }
        override func mouseExited(with event: NSEvent) { rollover.moved(nil) }
        required init?(coder: NSCoder) { fatalError() }

        // MARK: Open and shut

        /// A row as drawn: its level in the tree (a group 0, a row one more than its indent), the key its state is kept
        /// under, and whether it holds rows, which is what earns it a caret.
        struct Shown { let row: Row; let level: Int; let key: String; let holds: Bool }
        private(set) var shown: [Shown] = []
        static func level(of r: Row) -> Int {
            switch r {
            case .group: return 0
            case .row(_, _, _, let i), .node(_, _, _, let i, _, _), .tag(_, _, _, let i): return i + 1
            case .palette(let pr): return pr.indent + 1
            }
        }
        /// A stable key for a bucket: a collection, folder, member or group by its id; the catalogue's own headings by name.
        static func key(of r: Row) -> String {
            switch r {
            case .group(let title, let key): return key ?? "group:" + title
            case .row(let name, _, let place, _):
                switch place {
                case .folder(_, let f): return "folder:\(f.uuidString)"
                case .project(let id): return "member:\(id.uuidString)"
                default: return "row:" + name
                }
            case .node(_, _, let pid, _, _, let nid): return "node:\(pid.uuidString):\(nid.uuidString)"
            case .tag(let name, _, let pid, _): return "tag:\(pid.uuidString):" + name
            case .palette(let pr): return "palette:\(pr.id.uuidString)"
            }
        }
        /// What is shown: every row, less those inside a shut bucket. A row holds the rows after it that are deeper than it.
        private func rebuild() {
            var out: [Shown] = [], hideBelow: Int? = nil
            for (i, r) in rows.enumerated() {
                let level = Self.level(of: r)
                if let h = hideBelow, level > h { continue }
                hideBelow = nil
                let key = Self.key(of: r), holds = i + 1 < rows.count && Self.level(of: rows[i + 1]) > level
                out.append(Shown(row: r, level: level, key: key, holds: holds))
                if holds && shut.contains(key) { hideBelow = level }
            }
            shown = out
            rollover.settle(); needsDisplay = true
        }
        private func toggle(_ key: String) {
            let shutNow = !shut.contains(key)
            if shutNow { shut.insert(key) } else { shut.remove(key) }
            onShut?(key, shutNow)
        }

        /// The first group's header sits on the first-order line, the first row under the rule; every later group has a unit of air above it.
        override var height: CGFloat {
            var h: CGFloat = 0
            for (i, s) in shown.enumerated() {
                switch s.row {
                case .group: h += (i == 0 ? 0 : Self.groupAbove) + Self.row
                case .row, .node, .tag: h += Self.row
                case .palette: h += Self.two
                }
            }
            return h + Self.unit
        }

        /// A 16 icon in the house stroke: the star, the picks' target, the gear. `on` fills the star or the target's centre.
        private func icon(_ which: Int, in g: NSRect, on: Bool, colour: NSColor) {
            colour.setStroke(); colour.setFill()
            let path = NSBezierPath(); path.lineWidth = 1.1; path.lineJoinStyle = .miter
            switch which {
            case 0:
                let c = NSPoint(x: g.midX, y: g.midY + 0.5), r1: CGFloat = 7, r2: CGFloat = 2.8
                for k in 0..<10 {
                    let a = -CGFloat.pi / 2 + CGFloat(k) * CGFloat.pi / 5, r = k % 2 == 0 ? r1 : r2
                    let pt = NSPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                    if k == 0 { path.move(to: pt) } else { path.line(to: pt) }
                }
                path.close()
                if on { path.fill() } else { path.stroke() }
            case 1:
                path.appendOval(in: g.insetBy(dx: 1.5, dy: 1.5))
                path.stroke()
                if on { NSBezierPath(ovalIn: g.insetBy(dx: 5.5, dy: 5.5)).fill() }
                else { let dot = NSBezierPath(ovalIn: g.insetBy(dx: 6.5, dy: 6.5)); dot.lineWidth = 1; dot.stroke() }
            default:
                // The halo: its own mark, a ring with a ring inside.
                Design.haloMark(in: g, colour: colour)
            }
        }

        /// A row's caret, in the slot after its mark, when the row holds others; the slot is kept empty otherwise.
        private func caret(_ s: Shown, mark mx: CGFloat, top y: CGFloat, colour: NSColor) {
            guard s.holds else { return }
            Caret.draw(open: !shut.contains(s.key), centre: NSPoint(x: mx + 14 + Self.caretSlot / 2, y: y + Self.line - 5), colour: colour)
            caretHits.append((NSRect(x: mx + 14, y: y, width: Self.caretSlot, height: Self.row), s.key))
        }

        override func draw(_ dirtyRect: NSRect) {
            var y: CGFloat = 0
            hits = []; iconHits = []; nameHits = []; caretHits = []; tagLinks = []
            let right = bounds.width - insetRight
            /// A member lit while a palette is dragged over it, or a group of its stack that takes the drop: a one-point ink edge.
            func edge(_ box: NSRect) {
                Design.ink.setStroke()
                let e = NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5)); e.lineWidth = 1; e.stroke()
            }
            // The grounds first, then the tree's lines over them, then every row's mark and words.
            var tree: [TreeLines.Row] = []
            rowHits = []
            var yy: CGFloat = 0
            for (i, s) in shown.enumerated() {
                switch s.row {
                case .group:
                    if i > 0 { yy += Self.groupAbove }
                    let box = NSRect(x: 0, y: yy, width: bounds.width, height: Self.row)
                    rowHits.append((box, Self.key(of: s.row)))
                    rollover.pane(Self.key(of: s.row), box: box, reach: bounds.width, stripWidth: min(24, inset))
                    tree.append(TreeLines.Row(top: yy, height: Self.row, level: 0, anchor: inset + 5, markLeft: inset, baseline: Self.line))
                    yy += Self.row
                case .row(_, _, let place, let indent):
                    let mx = inset + 12 + CGFloat(indent) * Self.step
                    let box = NSRect(x: 0, y: yy, width: bounds.width, height: Self.row)
                    rowHits.append((box, Self.key(of: s.row)))
                    rollover.pane(Self.key(of: s.row), box: box, reach: bounds.width, stripWidth: min(24, inset))
                    tree.append(TreeLines.Row(top: yy, height: Self.row, level: s.level, anchor: mx + 7, markLeft: mx, baseline: Self.line))
                    yy += Self.row
                case .node(_, _, _, let indent, _, _), .tag(_, _, _, let indent):
                    let mx = inset + 12 + CGFloat(indent) * Self.step
                    let box = NSRect(x: 0, y: yy, width: bounds.width, height: Self.row)
                    rowHits.append((box, Self.key(of: s.row)))
                    rollover.pane(Self.key(of: s.row), box: box, reach: bounds.width, stripWidth: min(24, inset))
                    tree.append(TreeLines.Row(top: yy, height: Self.row, level: s.level, anchor: mx + 7, markLeft: mx, baseline: Self.line))
                    yy += Self.row
                case .palette(let pr):
                    let mx = inset + 12 + CGFloat(pr.indent) * Self.step
                    let box = NSRect(x: 0, y: yy, width: bounds.width, height: Self.two)
                    rowHits.append((box, Self.key(of: s.row)))
                    rollover.pane(Self.key(of: s.row), box: box, reach: bounds.width, stripWidth: min(24, inset))
                    tree.append(TreeLines.Row(top: yy, height: Self.two, level: s.level, anchor: mx + 7, markLeft: mx, baseline: Self.line))
                    yy += Self.two
                }
            }

            if Self.showsTreeConnectors { TreeLines.draw(tree, colour: Design.rule) }
            for (i, s) in shown.enumerated() {
                switch s.row {
                case .group(let title, _):
                    if i > 0 { y += Self.groupAbove }
                    // A first-order header: Title Case, the body weight, on the line every area shares. Its caret stands on the
                    // column where the tree's stem hangs from, its words over its rows' marks; the whole heading opens and shuts it.
                    if s.holds {
                        Caret.draw(open: !shut.contains(s.key), centre: NSPoint(x: inset + 4.5, y: y + Self.line - 5), colour: Design.quiet)
                        caretHits.append((NSRect(x: 0, y: y, width: bounds.width, height: Self.row), s.key))
                    }
                    Design.attributed(title, .body).draw(x: inset + Self.headingWords, baseline: y + Self.line, width: right - inset - Self.headingWords)
                    y += Self.row
                case .row(let name, let count, let place, let indent):
                    let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
                    let on = place == chosen
                    // Rows sit one small step in from their group's header, so the groups read as groups; the mark, the caret, then the words.
                    let b = y + Self.line, mx = inset + 12 + CGFloat(indent) * Self.step, x = mx + Self.words
                    let mark: String
                    switch place {
                    case .folder: mark = "building.2"
                    case .project: mark = "folder"
                    case .catalogue: mark = "square.grid.2x2"
                    case .palettes: mark = "swatchpalette"
                    default: mark = "folder"
                    }
                    RowMark.draw(mark, x: mx, baseline: b, colour: on ? Design.ink : Design.quiet)
                    caret(s, mark: mx, top: y, colour: on ? Design.ink : Design.quiet)
                    let countText = Design.attributed(String(count), .caption, colour: Design.quiet)
                    let countW = countText.size().width
                    let nameText = Design.attributed(name, on ? .bodyStrong : .body), nameW = right - x - countW - 12
                    if renaming != place {
                        nameText.draw(x: x, baseline: b, width: nameW - (on ? 10 : 0))
                        if on { fill(NSRect(x: x + min(nameText.size().width, right - x - countW - 22) + 6, y: b - 6, width: 4, height: 4), Design.ink) }
                    }
                    switch place {
                    case .project, .folder: nameHits.append((NSRect(x: x, y: y, width: nameW, height: Self.row), place, name, on ? .bodyStrong : .body))
                    default: break
                    }
                    countText.draw(right: right, baseline: b)
                    if case .project(let id) = place, target == DropDestination(project: id, bucket: nil) { edge(box) }
                    hits.append((box, place))
                    y += Self.row
                case .node(let name, let count, let pid, let indent, let drop, let nid):
                    let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
                    let b = y + Self.line, mx = inset + 12 + CGFloat(indent) * Self.step, x = mx + Self.words
                    let on = chosen == .group(pid, nid)
                    // The old sidebar's marks for a member's groups: palettes, information, typography, tags, and a dashed square for one of your own.
                    let role = SchemaTrial.role(of: SchemaNode(name: name))
                    let mark = role == .palettes ? "swatchpalette" : role == .information ? "info.circle" : role == .typography ? "textformat" : role == .tags ? "tag" : "square.dashed"
                    RowMark.draw(mark, x: mx, baseline: b, colour: Design.quiet)
                    caret(s, mark: mx, top: y, colour: Design.quiet)
                    let countText = Design.attributed(count > 0 ? String(count) : "", .caption, colour: Design.quiet)
                    Design.attributed(name, on ? .bodyStrong : .body).draw(x: x, baseline: b, width: right - x - countText.size().width - 12)
                    countText.draw(right: right, baseline: b)
                    if drop, target == DropDestination(project: pid, bucket: nid) { edge(box) }
                    hits.append((box, .group(pid, nid)))
                    y += Self.row
                case .tag(let name, let count, let pid, let indent):
                    // A tag with its mark and how many colours wear it; the last row the way to the editor, a quiet word.
                    let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
                    let b = y + Self.line, mx = inset + 12 + CGFloat(indent) * Self.step, x = mx + Self.words
                    let link = count < 0
                    RowMark.draw(link ? "slider.horizontal.3" : "tag", x: mx, baseline: b, colour: Design.quiet)
                    let countText = Design.attributed(count > 0 ? String(count) : "", .caption, colour: Design.quiet)
                    Design.attributed(name, .body, colour: link ? Design.quiet : Design.ink).draw(x: x, baseline: b, width: right - x - countText.size().width - 12)
                    countText.draw(right: right, baseline: b)
                    hits.append((box, link ? .tags : .project(pid)))
                    if link { tagLinks.append((box, pid)) }
                    y += Self.row
                case .palette(let pr):
                    let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.two)
                    let place = StudioFrame.Place.palette(pr.id), on = selectedPalettes.contains(pr.id)
                    let mx = inset + 12 + CGFloat(pr.indent) * Self.step
                    let x = mx + 28, tileRight = right - 4
                    let nameW = max(1, tileRight - x)
                    if renaming != place { Design.attributed(pr.name, on ? .bodyStrong : .body, colour: Design.ink).draw(x: x, baseline: y + Self.line, width: nameW) }
                    nameHits.append((NSRect(x: x, y: y, width: nameW, height: Self.row), place, pr.name, .body))
                    RailTile.spectrum(pr.colours, in: NSRect(x: x, y: y + Self.unit + 7, width: max(1, tileRight - x - 28), height: 10))
                    for which in [0, 1, 2] {
                        let rect = NSRect(x: which == 2 ? tileRight - 16 : mx + 3, y: y + (which == 0 ? 0 : Self.unit) + 4, width: 16, height: 16)
                        let lit = which == 0 ? pr.favourite : which == 1 && pr.target
                        icon(which, in: rect, on: lit, colour: lit ? Design.ink : Design.quiet)
                        iconHits.append((rect.insetBy(dx: -4, dy: -4), which, pr.id))
                    }
                    hits.append((box, place))
                    y += Self.two
                }
            }
        }

        private func palette(at p: NSPoint) -> (UUID, String, [NSColor])? {
            var y: CGFloat = 0
            for (i, s) in shown.enumerated() {
                switch s.row {
                case .group: y += (i == 0 ? 0 : Self.groupAbove) + Self.row
                case .row, .node, .tag: y += Self.row
                case .palette(let pr):
                    if NSRect(x: 0, y: y, width: bounds.width, height: Self.two).contains(p) { return (pr.id, pr.name, pr.colours) }
                    y += Self.two
                }
            }
            return nil
        }

        private var focusedPalette: UUID?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 125 || event.keyCode == 126 {
                let order: [UUID] = shown.compactMap { if case .palette(let p) = $0.row { return p.id }; return nil }
                if let focus = focusedPalette ?? order.first(where: { selectedPalettes.contains($0) }), let i = order.firstIndex(of: focus), !order.isEmpty {
                    let next = order[min(order.count - 1, max(0, i + (event.keyCode == 125 ? 1 : -1)))]
                    focusedPalette = next; onPaletteSelection?(next, order, event.modifierFlags); return
                }
            }
            if event.keyCode == 51 || event.keyCode == 117 { onDeleteSelection?(); return }
            super.keyDown(with: event)
        }
        override func rightMouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            guard let hit = hits.first(where: { $0.0.contains(point) }) else { return }
            onContext?(hit.1, self, point)
        }
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            let p = convert(event.locationInWindow, from: nil)
            pressed = nil; pendingPaletteClick = nil; pressedIcon = nil
            // An icon acts on the release, not the press: the halo opens under the pointer, and a press that opened it must not be the click that chooses on it.
            if let h = iconHits.first(where: { $0.0.contains(p) }) { pressedIcon = h; return }
            // A caret opens or shuts its bucket and goes nowhere; the words beside it still go where they always have.
            if let c = caretHits.first(where: { $0.0.contains(p) }) { toggle(c.1); return }
            if event.clickCount == 2, let h = nameHits.first(where: { $0.0.contains(p) }) { rename(h, at: p); return }
            pressed = palette(at: p); pressedAt = (event.locationInWindow, event.timestamp)
            // Edit Tags under a member opens Settings, Tags filtered to that member.
            if let l = tagLinks.first(where: { $0.0.contains(p) }) { TagsSettings.pendingScope = .member(l.1) }
            if let h = hits.first(where: { $0.0.contains(p) }) {
                if pressed != nil { pendingPaletteClick = h }
                else {
                if case .palette(let id) = h.1 {
                    focusedPalette = id
                    onPaletteSelection?(id, shown.compactMap { if case .palette(let p) = $0.row { return p.id }; return nil }, event.modifierFlags)
                } else { onPick?(h.1) }
            }
            }
        }
        /// A double-click on a name: the cursor goes into the words where they are, and the name is written when the typing ends.
        private func rename(_ h: (NSRect, StudioFrame.Place, String, Design.Text), at p: NSPoint) {
            renaming = h.1; needsDisplay = true
            InlineName.edit(h.2, style: h.3, in: self, x: h.0.minX, baseline: h.0.minY + Self.line, width: h.0.width, at: p) { [weak self] name in
                self?.renaming = nil; self?.needsDisplay = true
                if let n = name, n != h.2 { self?.onRename?(h.1, n) }
            }
        }
        override func mouseDragged(with event: NSEvent) {
            guard let (id, name, colours) = pressed, PaletteDrag.counts(event, from: pressedAt) else { return }
            pressed = nil; pendingPaletteClick = nil
            PaletteDrag.begin(id, name: name, colours: colours, event: event, in: self)
        }
        private var pressedIcon: (NSRect, Int, UUID)?
        private func finishPaletteClick(_ event: NSEvent) {
            let pending = pendingPaletteClick
            pendingPaletteClick = nil; pressed = nil
            if let pending, pending.0.contains(convert(event.locationInWindow, from: nil)),
               hypot(event.locationInWindow.x - pressedAt.0.x, event.locationInWindow.y - pressedAt.0.y) < PaletteDrag.threshold {
                if case .palette(let id) = pending.1 {
                    focusedPalette = id
                    onPaletteSelection?(id, shown.compactMap { if case .palette(let p) = $0.row { return p.id }; return nil }, event.modifierFlags)
                } else { onPick?(pending.1) }
            }
        }
        override func mouseUp(with event: NSEvent) {
            finishPaletteClick(event)
            if let h = pressedIcon {
                pressedIcon = nil
                if h.0.contains(convert(event.locationInWindow, from: nil)) {
                    switch h.1 {
                    case 0: onFavourite?(h.2)
                    case 1: onTarget?(h.2)
                    default: onGear?(h.2, self, h.0)
                    }
                }
            }
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { [.copy, .move] }

        // MARK: A palette dropped on a member, or on one of the member's own palettes

        private func member(at p: NSPoint) -> DropDestination? {
            var y: CGFloat = 0
            for (i, s) in shown.enumerated() {
                switch s.row {
                case .group: y += (i == 0 ? 0 : Self.groupAbove) + Self.row
                case .row(_, _, let place, _):
                    if case .project(let id) = place, NSRect(x: 0, y: y, width: bounds.width, height: Self.row).contains(p) { return DropDestination(project: id, bucket: nil) }
                    y += Self.row
                case .node(_, _, let pid, _, let drop, let nid):
                    if drop, NSRect(x: 0, y: y, width: bounds.width, height: Self.row).contains(p) { return DropDestination(project: pid, bucket: nid) }
                    y += Self.row
                case .tag: y += Self.row
                case .palette(let pr):
                    if let m = pr.project, NSRect(x: 0, y: y, width: bounds.width, height: Self.two).contains(p) { return DropDestination(project: m, bucket: pr.bucket) }
                    y += Self.two
                }
            }
            return nil
        }
        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            let over = member(at: convert(sender.draggingLocation, from: nil))
            if over != target { target = over; needsDisplay = true }
            return over == nil ? [] : .copy
        }
        override func draggingExited(_ sender: NSDraggingInfo?) { target = nil; needsDisplay = true }
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            defer { target = nil; needsDisplay = true }
            guard let m = member(at: convert(sender.draggingLocation, from: nil)), let s = PaletteDrag.palette(on: sender.draggingPasteboard) else { return false }
            onDrop?(s, m)
            return true
        }
    }
}

/// A palette on the pasteboard while it is dragged between the rails: its id under a type of the app's own.
enum PaletteDrag {
    static let type = NSPasteboard.PasteboardType("com.mmffdev.colorgain.palette")

    /// Use the normal distance threshold: quick drags must work without a hold delay.
    /// A click or a small pointer wobble still cannot lift a palette.
    static let threshold: CGFloat = 8
    static func counts(_ event: NSEvent, from press: (NSPoint, TimeInterval)) -> Bool {
        hypot(event.locationInWindow.x - press.0.x, event.locationInWindow.y - press.0.y) >= threshold
    }

    static func palette(on board: NSPasteboard) -> UUID? {
        board.pasteboardItems?.first?.string(forType: type).flatMap { UUID(uuidString: $0) }
    }

    /// Starts the drag from a rail: the drag image is the palette's strip with its name, as the rails draw it.
    static func begin(_ id: UUID, name: String, colours: [NSColor], event: NSEvent, in view: NSView & NSDraggingSource) {
        let item = NSPasteboardItem()
        item.setString(id.uuidString, forType: type)
        let size = NSSize(width: 180, height: 24)
        let image = NSImage(size: size, flipped: true) { r in
            Design.card.setFill(); r.fill()
            let strip = NSRect(x: 4, y: 7, width: 44, height: 10)
            if colours.isEmpty { Design.mist.setFill(); strip.fill() }
            else {
                let bw = strip.width / CGFloat(colours.count)
                for (k, c) in colours.enumerated() { c.setFill(); NSRect(x: strip.minX + CGFloat(k) * bw, y: strip.minY, width: bw + 0.5, height: strip.height).fill() }
            }
            Design.attributed(name, .body).draw(at: NSPoint(x: 56, y: 4))
            Design.rule.setStroke()
            let e = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)); e.lineWidth = 1; e.stroke()
            return true
        }
        let drag = NSDraggingItem(pasteboardWriter: item)
        let p = view.convert(event.locationInWindow, from: nil)
        drag.setDraggingFrame(NSRect(x: p.x - 20, y: p.y - 12, width: size.width, height: size.height), contents: image)
        view.beginDraggingSession(with: [drag], event: event, source: view)
    }
}

/// The context rail: a table. A palette row carries a strip of every colour in it before its name and
/// its count at the right; a group row is a Label, one step in for each level down; an item row is a
/// name with a detail at the right, going somewhere when it has a place.
final class PaletteTable: StudioRail {
    var onDesignPalette: (() -> Void)?
    private let designPalette = ActionButton(title: "Design Palette", target: nil, action: nil)
    @objc private func createPalette() { onDesignPalette?() }

    var warningIDs = Set<UUID>()
    var onWarning: (() -> Void)?
    private var warnings: [NSButton] = []
    override func layout() {
        super.layout()
        designPalette.frame = NSRect(x: inset, y: AreaHeader.height, width: bounds.width - inset - insetRight, height: Design.App.unit)
        warnings.forEach { $0.removeFromSuperview() }; warnings = []
        var y: CGFloat = 0
        for row in table.rows {
            if case .palette(let id, _, _, _, _, _, _) = row, warningIDs.contains(id) {
                let button = AppbridgeListButton("Missing ASE files — Locate or Remove", symbol: "exclamationmark.triangle") { [weak self] in self?.onWarning?() }
                button.frame = NSRect(x: table.bounds.width - table.insetRight - 24, y: y, width: 24, height: Body.row)
                table.addSubview(button); warnings.append(button)
            }
            y += Body.height(of: row)
        }
    }

    enum Row {
        /// A group's heading, with the place its page is and whether that page is showing; `fold`, when it holds rows, the key
        /// its open or shut state is kept under and whether it is open. A shut group's rows are left out by whoever fills the rail.
        case group(String, Int, StudioFrame.Place? = nil, Bool = false, fold: (key: String, open: Bool)? = nil)
        case palette(UUID, String, Int, [NSColor], Bool, Int, prefix: String? = nil)
        case item(String, String?, Int, StudioFrame.Place?, Bool)
        /// A word on a hairline between runs of rows, as "Just Added" parts this week's palettes from the rest.
        case divider(String)
    }
    var readOnlyRows = false { didSet { table.readOnlyRows = readOnlyRows } }
    var onPaletteSelection: ((UUID, [UUID], NSEvent.ModifierFlags) -> Void)?
    var onDeleteSelection: (() -> Void)?
    var onContext: ((StudioFrame.Place, NSView, NSPoint) -> Void)?
    var onPick: ((StudioFrame.Place) -> Void)?
    var onRename: ((StudioFrame.Place, String) -> Void)?
    /// A group's caret pressed: its key, and whether it is now shut.
    var onShut: ((String, Bool) -> Void)?
    var selectedPalettes: Set<UUID> { get { table.selectedPalettes } set { table.selectedPalettes = newValue } }
    private var table: Body { body as! Body }
    init() {
        super.init(body: Body()); labels = ("Palette", "Count")
        designPalette.isBordered = false
        designPalette.alignment = .left
        designPalette.title = "Design Palette"
        designPalette.target = self; designPalette.action = #selector(createPalette)
        designPalette.setAccessibilityLabel("Design Palette")
        designPalette.toolTip = "Create a new palette"
        designPalette.isHidden = true
        addSubview(designPalette)
        table.onPaletteSelection = { [weak self] id, order, modifiers in self?.onPaletteSelection?(id, order, modifiers) }
        table.onDeleteSelection = { [weak self] in self?.onDeleteSelection?() }
        table.onContext = { [weak self] place, view, point in self?.onContext?(place, view, point) }
        table.onPick = { [weak self] p in self?.onPick?(p) }
        table.onRename = { [weak self] p, n in self?.onRename?(p, n) }
        table.onShut = { [weak self] k, s in self?.onShut?(k, s) }
    }
    required init?(coder: NSCoder) { fatalError() }
    func set(heading: String, labels: (String, String), rows: [Row]) {
        let offersDesign = labels.0 == "Palette" && labels.1 == "Count"
        designPalette.isHidden = !offersDesign
        contentOffset = offersDesign ? 2 * Design.App.unit : 0
        self.heading = heading; self.labels = labels; table.rows = rows; needsLayout = true
        // The chosen row is brought into view when it is out of it, which the eye expects when it was chosen elsewhere;
        // a row already in view, clicked here, leaves the list exactly where it is.
        if selectedPalettes.count > 1 { return }
        var y: CGFloat = 0
        for r in rows {
            let h = Body.height(of: r)
            switch r {
            case .palette(_, _, _, _, true, _, _), .item(_, _, _, _, true):
                layoutSubtreeIfNeeded()
                let row = NSRect(x: 0, y: y, width: 1, height: h)
                if !body.visibleRect.contains(row) { body.scrollToVisible(NSRect(x: 0, y: max(0, y - h), width: 1, height: h * 3)) }
                return
            default: y += h
            }
        }
    }

    final class Body: RailBody, NSDraggingSource {
    override var handCursorRects:[NSRect]{hits.map{$0.0}+caretHits.map{$0.0}+nameHits.map{$0.0}}

        var selectedPalettes: Set<UUID> = [] { didSet { rollover.settle(); needsDisplay = true } }
        var readOnlyRows = false
        var rows: [Row] = [] { didSet { rollover.settle() } }
        var onPaletteSelection: ((UUID, [UUID], NSEvent.ModifierFlags) -> Void)?
    var onDeleteSelection: (() -> Void)?
    var onContext: ((StudioFrame.Place, NSView, NSPoint) -> Void)?
    var onPick: ((StudioFrame.Place) -> Void)?
        var onRename: ((StudioFrame.Place, String) -> Void)?
        var onShut: ((String, Bool) -> Void)?
        static var row: CGFloat { unit }
        static var group: CGFloat { unit }
        static var divider: CGFloat { unit }
        static let step: CGFloat = 16, strip: CGFloat = 44
        /// A group's caret stands where its words would, on the column; the words follow it.
        static let caretSlot: CGFloat = 12
        private var hits: [(NSRect, StudioFrame.Place)] = []
        private var caretHits: [(NSRect, String, Bool)] = []
        private var nameHits: [(NSRect, StudioFrame.Place, String, Design.Text)] = []
        private var renaming: StudioFrame.Place?
        private var pressed: (UUID, String, [NSColor])?
        private var pendingPaletteClick: (NSRect, StudioFrame.Place)?
        /// Where and when the mouse went down, so a drag starts only once the pointer has clearly left the press.
        private var pressedAt: (NSPoint, TimeInterval) = (.zero, 0)
        /// The schema page's rollover: the pane flies out under the pointer and stays out on the chosen row, over its Mist ground.
        private let rollover = Rollover<StudioFrame.Place>()
        static func height(of r: Row) -> CGFloat {
            switch r { case .group: return group; case .divider: return divider; case .palette(_, _, _, _, _, _, let prefix): return prefix == nil ? row : row * 2; default: return row }
        }
        override var height: CGFloat { rows.reduce(0) { $0 + Self.height(of: $1) } + Self.unit }

        override init(frame: NSRect) {
            super.init(frame: frame)
            rollover.barberPole = true
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self))
            rollover.keys = { [weak self] in self?.rows.compactMap { Self.place(of: $0).map { $0.0 } } ?? [] }
            rollover.locked = { [weak self] key in
                guard let self else { return false }
                return self.rows.contains { row in
                    guard let (place, chosen) = Self.place(of: row), place == key else { return false }
                    if case .palette(let id) = place, !self.readOnlyRows { return self.selectedPalettes.contains(id) }
                    return chosen
                }
            }
            rollover.redraw = { [weak self] in self?.needsDisplay = true }
        }
        required init?(coder: NSCoder) { fatalError() }

        /// Where a row goes, and whether that is the place showing; nil for a row that goes nowhere.
        static func place(of r: Row) -> (StudioFrame.Place, Bool)? {
            switch r {
            case .group(_, _, let p?, let chosen, _): return (p, chosen)
            case .palette(let id, _, _, _, let chosen, _, _): return (.palette(id), chosen)
            case .item(_, _, _, let p?, let chosen): return (p, chosen)
            default: return nil
            }
        }

        override func draw(_ dirtyRect: NSRect) {
            let right = bounds.width - insetRight
            hits = []; nameHits = []; caretHits = []
            // Where each row's words begin and how far they run, so the rollover's pane can reach a step past them.
            func lead(_ r: Row) -> (x: CGFloat, words: NSAttributedString, room: CGFloat)? {
                switch r {
                case .group(let name, let indent, _, let chosen, _):
                    let x = inset + CGFloat(indent) * Self.step + Self.caretSlot
                    return (x, Design.attributed(name, chosen ? .bodyStrong : .body), right - x)
                case .palette(_, let name, _, _, let chosen, let indent, let prefix):
                    let x = inset + CGFloat(indent) * Self.step + 4
                    return (x, Design.attributed(prefix.map { $0 + " · " + name } ?? name, chosen ? .bodyStrong : .body), prefix == nil ? max(1, right - 4 - x - 28) * 0.52 : right - x)
                case .item(let name, let detail, let indent, _, let chosen):
                    let x = inset + CGFloat(indent) * Self.step
                    return (x, Design.attributed(name, chosen ? .bodyStrong : .body), right - x - Design.attributed(detail ?? "", .caption).size().width - 12)
                case .divider: return nil
                }
            }
            // The grounds and the panes first, as the schema page lays them: the chosen row's Mist from a point over the rule
            // above it, then each pane as far out as it has flown, to a step past the words; the rows' words and rules go over them.
            var y: CGFloat = 0
            for r in rows {
                let h = Self.height(of: r), box = NSRect(x: 0, y: y, width: bounds.width, height: h)
                if let (p, chosen) = Self.place(of: r) {
                    if let l = lead(r) { rollover.pane(p, box: box, reach: l.x + min(l.words.size().width, l.room) + Self.step, stripWidth: min(24, inset)) }
                }
                y += h
            }
            y = 0
            for r in rows {
                switch r {
                case .group(let name, let indent, let place, let chosen, let fold):
                    // A first-order header: Title Case, the body weight, on the shared line; the one whose page is showing on the ground.
                    // When it holds rows its caret leads it, on the column; a heading that goes nowhere opens and shuts on a click anywhere.
                    let x = inset + CGFloat(indent) * Self.step, b = y + Self.line
                    if let f = fold {
                        Caret.draw(open: f.open, centre: NSPoint(x: x + 4.5, y: b - 5), colour: chosen ? Design.ink : Design.quiet)
                        let hit = place == nil ? NSRect(x: 0, y: y, width: bounds.width, height: Self.group) : NSRect(x: x - 6, y: y, width: Self.caretSlot + 6, height: Self.group)
                        caretHits.append((hit, f.key, f.open))
                    }
                    Design.attributed(name, chosen ? .bodyStrong : .body).draw(x: x + Self.caretSlot, baseline: b, width: right - x - Self.caretSlot)
                    if let p = place { hits.append((NSRect(x: 0, y: y, width: bounds.width, height: Self.group), p)) }
                    y += Self.group
                case .palette(let id, let name, let count, let colours, let rowChosen, let indent, let prefix):
                    let chosen = readOnlyRows ? rowChosen : selectedPalettes.contains(id)
                    let h = Self.height(of: r)
                    let box = NSRect(x: 0, y: y, width: bounds.width, height: h)
                    let x = inset + CGFloat(indent) * Self.step, nameX = x + 4, tileRight = right - 4
                    let b = y + Self.line, countText = Design.attributed(String(count), .caption, colour: Design.quiet)
                    if let prefix {
                        Design.attributed(prefix + " · " + name, chosen ? .bodyStrong : .body).draw(x: nameX, baseline: b, width: tileRight - nameX)
                        RailTile.spectrum(colours, in: NSRect(x: nameX, y: y + Self.row + 5, width: max(1, tileRight - nameX - countText.size().width - 16), height: 16))
                        countText.draw(right: tileRight, baseline: b + Self.row)
                        hairline(x: 0, y: y + h - 1, width: bounds.width, Design.rule)
                        hits.append((box, .palette(id)))
                        y += h
                        continue
                    }
                    let available = max(1, tileRight - nameX - 28)
                    let nameW = available * 0.52, stripX = nameX + nameW + 8
                    if renaming != .palette(id) { Design.attributed(name, chosen ? .bodyStrong : .body, colour: Design.ink).draw(x: nameX, baseline: b, width: nameW) }
                    nameHits.append((NSRect(x: nameX, y: y, width: nameW, height: Self.row), .palette(id), name, .body))
                    if !readOnlyRows || count > 0 { countText.draw(right: tileRight, baseline: b) }
                    RailTile.spectrum(colours, in: NSRect(x: stripX, y: y + (h - 16) / 2, width: max(1, available - nameW - 8), height: 16))
                    hairline(x: 0, y: y + h - 1, width: bounds.width, Design.rule)
                    hits.append((box, .palette(id)))
                    y += h
                case .item(let name, let detail, let indent, let place, let chosen):
                    let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
                    let b = y + Self.line, x = inset + CGFloat(indent) * Self.step
                    let detailText = Design.attributed(detail ?? "", .caption, colour: Design.quiet)
                    let dim = place == nil && detail == nil && name == "None found"
                    let nameW = right - x - detailText.size().width - 12
                    if renaming == nil || renaming != place { Design.attributed(name, chosen ? .bodyStrong : .body, colour: dim ? Design.soft : Design.ink).draw(x: x, baseline: b, width: nameW) }
                    if case .project? = place { nameHits.append((NSRect(x: x, y: y, width: nameW, height: Self.row), place!, name, chosen ? .bodyStrong : .body)) }
                    if detail != nil { detailText.draw(right: right, baseline: b) }
                    hairline(x: 0, y: y + Self.row - 1, width: bounds.width, Design.mist)
                    if let p = place { hits.append((box, p)) }
                    y += Self.row
                case .divider(let word):
                    Design.attributed(word, .label, colour: Design.quiet).draw(x: inset, baseline: y + Self.line)
                    hairline(x: 0, y: y + Self.divider - 1, width: bounds.width, Design.rule)
                    y += Self.divider
                }
            }
            if rows.isEmpty { Design.attributed("Nothing found", .caption, colour: Design.soft).draw(x: inset, baseline: y + Self.line) }
        }

        // MARK: The pointer

        override func mouseMoved(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            rollover.moved(hits.first { $0.0.contains(p) }?.1)
        }
        override func mouseExited(with event: NSEvent) { rollover.moved(nil) }

        private func palette(at p: NSPoint) -> (UUID, String, [NSColor])? {
            var y: CGFloat = 0
            for r in rows {
                if case .palette(let id, let name, _, let colours, _, _, _) = r, NSRect(x: 0, y: y, width: bounds.width, height: Self.height(of: r)).contains(p) { return (id, name, colours) }
                y += Self.height(of: r)
            }
            return nil
        }
        private var focusedPalette: UUID?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 125 || event.keyCode == 126 {
                let order: [UUID] = rows.compactMap { if case .palette(let id, _, _, _, _, _, _) = $0 { return id }; return nil }
                if let focus = focusedPalette ?? order.first(where: { selectedPalettes.contains($0) }), let i = order.firstIndex(of: focus), !order.isEmpty {
                    let next = order[min(order.count - 1, max(0, i + (event.keyCode == 125 ? 1 : -1)))]
                    focusedPalette = next; onPaletteSelection?(next, order, event.modifierFlags); return
                }
            }
            if !readOnlyRows && (event.keyCode == 51 || event.keyCode == 117) { onDeleteSelection?(); return }
            super.keyDown(with: event)
        }
        override func rightMouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            guard let hit = hits.first(where: { $0.0.contains(point) }) else { return }
            onContext?(hit.1, self, point)
        }
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            let p = convert(event.locationInWindow, from: nil)
            pressed = nil; pendingPaletteClick = nil
            // A caret opens or shuts its group and goes nowhere; the group's words still open its page.
            if let c = caretHits.first(where: { $0.0.contains(p) }) { onShut?(c.1, c.2); return }
            if !readOnlyRows, event.clickCount == 2, let h = nameHits.first(where: { $0.0.contains(p) }) {
                renaming = h.1; needsDisplay = true
                InlineName.edit(h.2, style: h.3, in: self, x: h.0.minX, baseline: h.0.minY + Self.line, width: h.0.width, at: p) { [weak self] name in
                    self?.renaming = nil; self?.needsDisplay = true
                    if let n = name, n != h.2 { self?.onRename?(h.1, n) }
                }
                return
            }
            pressed = palette(at: p); pressedAt = (event.locationInWindow, event.timestamp)
            if let h = hits.first(where: { $0.0.contains(p) }) {
                if pressed != nil { pendingPaletteClick = h }
                else { onPick?(h.1) }
            }
        }
        override func mouseDragged(with event: NSEvent) {
            guard !readOnlyRows, let (id, name, colours) = pressed, PaletteDrag.counts(event, from: pressedAt) else { return }
            pressed = nil; pendingPaletteClick = nil
            PaletteDrag.begin(id, name: name, colours: colours, event: event, in: self)
        }
        override func mouseUp(with event: NSEvent) {
            let pending = pendingPaletteClick
            pendingPaletteClick = nil; pressed = nil
            if let pending, pending.0.contains(convert(event.locationInWindow, from: nil)),
               hypot(event.locationInWindow.x - pressedAt.0.x, event.locationInWindow.y - pressedAt.0.y) < PaletteDrag.threshold {
                if case .palette(let id) = pending.1 {
                    focusedPalette = id
                    onPaletteSelection?(id, rows.compactMap { if case .palette(let id, _, _, _, _, _, _) = $0 { return id }; return nil }, event.modifierFlags)
                } else { onPick?(pending.1) }
            }
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { [.copy, .move] }
    }
}

/// The history rail: a step on two units. The first line, the step's mark where a row's mark stands, its title, and when at
/// the right; the second, the colours it touched as small squares standing on the line, then what it did to whom.
final class HistoryRail: StudioRail {
    var global = false
    var onScope: (() -> Void)?
    private lazy var scope = SwissDropdown("History Scope", value: "Catalogue", options: ["Catalogue", "Global"], allowsOwn: false, width: 160)
    override func layout() {
        super.layout()
        let width = max(80, bounds.width - inset - insetRight)
        scope.constraints.first(where: { $0.firstAttribute == .width })?.constant = width
        scope.frame = NSRect(x: inset, y: AreaHeader.height, width: width, height: Design.App.unit * 2)
        scroll.frame.origin.y += Design.App.unit * 2
        scroll.frame.size.height = max(0, scroll.frame.height - Design.App.unit * 2)
    }
    /// A step: its mark and title on the first line with when it was, the colours it touched and what it did on the second.
    struct Row { let symbol: String; let title: String; let detail: String; let time: String; let chips: [NSColor]; let hex: String? }
    var onPick: ((String) -> Void)?
    private var list: Body { body as! Body }
    init() { super.init(body: Body()); addSubview(scope); scope.onChange = { [weak self] value in self?.global = value == "Global"; self?.onScope?() }; heading = "History"; labels = ("Step", "When"); list.onPick = { [weak self] h in self?.onPick?(h) } }
    required init?(coder: NSCoder) { fatalError() }
    func set(rows: [Row]) { list.rows = rows; needsLayout = true }

    final class Body: RailBody {
    override var handCursorRects:[NSRect]{hits.map{$0.0}}

        var rows: [Row] = [] { didSet { needsDisplay = true } }
        var onPick: ((String) -> Void)?
        static var row: CGFloat { unit * 2 }
        /// The mark's 14 and the gap to the words, as rail1's rows have it; a chip is 10 square, 4 apart, 8 clear of the words.
        static let words: CGFloat = 20, chip: CGFloat = 10, chipGap: CGFloat = 4
        private var hits: [(NSRect, String)] = []
        override var height: CGFloat { CGFloat(rows.count) * Self.row + Self.unit }

        override func draw(_ dirtyRect: NSRect) {
            var y: CGFloat = 0
            let right = bounds.width - insetRight
            hits = []
            for r in rows {
                let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
                let b1 = y + Self.line, b2 = y + Self.unit + Self.line, x0 = inset + Self.words
                // The step's mark where a row's mark stands, the title after it, the time at the right.
                RowMark.draw(r.symbol, x: inset, baseline: b1, colour: Design.quiet)
                let time = Design.attributed(r.time, .caption, colour: Design.quiet)
                Design.attributed(r.title, .body).draw(x: x0, baseline: b1, width: right - x0 - time.size().width - 12)
                time.draw(right: right, baseline: b1)
                // The second line, under the title: the chips, their feet on the caption's line, then what it did to whom.
                var x = x0
                for c in r.chips { fill(NSRect(x: x, y: b2 - Self.chip, width: Self.chip, height: Self.chip), c); x += Self.chip + Self.chipGap }
                if !r.chips.isEmpty { x += 8 - Self.chipGap }
                Design.attributed(r.detail, .caption, colour: Design.quiet).draw(x: x, baseline: b2, width: right - x)
                hairline(x: 0, y: box.maxY - 1, width: bounds.width, Design.mist)
                if let h = r.hex { hits.append((box, h)) }
                y += Self.row
            }
            if rows.isEmpty { Design.attributed("Nothing found", .caption, colour: Design.soft).draw(x: inset, baseline: y + Self.line) }
        }
        override func mouseDown(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            if let h = hits.first(where: { $0.0.contains(p) }) { onPick?(h.1) }
        }
    }
}

// MARK: - The page

/// Asset handlers opt into page capabilities while retaining one viewport layout.
// MARK: - Settings: Catalogues

/// The Catalogues settings on the page. The actions along the top, then one row per catalogue: Set
/// Active before a small static square, the catalogue's colour once it has one, then its name; a click
/// on Set Active swaps the open catalogue without opening the row, a click on the row opens it like an
/// accordion, everything in it on the row's own left edge. About, with the notes kept in the catalogue's
/// file on a hairline; All Colours, the count; Directory, its folder; Contents, the catalogue as rail1
/// lists it, every member and palette with a square to tick, its colours as a strip, and Duplicate,
/// Relocate and Remove on its right; once something is ticked, a bar with Relocate and Remove for all
/// of it. Relocate drops the list of other catalogues. Then the hue strip while a colour is being
/// chosen, and Assign Colour, Duplicate and Remove for the catalogue itself at the right, Main like any
/// other while another catalogue is on the list. Remove asks
/// on the window's own confirm panel, with what the catalogue holds and the choice of moving all of it
/// to another catalogue first. The page scrolls as one piece.
final class CatalogueSettings: ClickCursorView, NSTextViewDelegate, Overlay {
    override var handCursorRects:[NSRect]{rowHits.map{$0.0}+activeHits.map{$0.0}+actionHits.map{$0.0}+lineHits.map{$0.0}+lineActionHits.map{$0.0}+barHits.map{$0.0}+addHits.map{$0.0}+(expanded == nil ? []:[spectrum])}

    var overlayWindows: [NSWindow] { dropped.map { [$0] } ?? [] }
    func dismissOverlay() { closeMenu() }
    weak var library: LibraryController?
    var onChange: (() -> Void)?
    var onResize: (() -> Void)?
    private var names: [String] = []
    private var expanded: String?
    /// How far open each row's panel is, 0 to 1; a row not here is shut. Driven towards its target by the clock.
    private var openness: [String: CGFloat] = [:]
    private var clock: Timer?
    private var hover: String?
    private var lineHover: Item?
    private var picking = false
    /// What the open catalogue holds, listed as rail1 lists it, and what is ticked.
    private var contents: Library?
    private var lines: [Line] = []
    private var ticked = Set<Item>()
    private var rowHits: [(NSRect, String)] = [], activeHits: [(NSRect, String)] = [], actionHits: [(NSRect, Int)] = []
    private var lineHits: [(NSRect, Item)] = [], lineActionHits: [(NSRect, Item, Int)] = [], barHits: [(NSRect, Int)] = [], addHits: [(NSRect, UUID, String)] = []
    private var spectrum = NSRect.zero
    private var dropped: SwissDropdown.MenuPanel?
    private var removeButtons: [String: SwissButton] = [:]
    private let openButton = SwissButton("Open Catalogue\u{2026}", .primary)
    private let newButton = SwissButton("New Catalogue", .secondary)
    private let finderButton = SwissButton("Show In Finder", .secondary)
    private let importButton = SwissButton("Import\u{2026}", .secondary)
    private let exportButton = SwissButton("Export Catalogue\u{2026}", .secondary)
    var onImport: (() -> Void)?
    var onExport: (() -> Void)?
    private let aboutScroll = FittedScrollView()
    private let about = NSTextView()
    /// On the beat: every row a unit, the notes three, the hue strip two; text on the unit's line.
    static var u: CGFloat { Design.App.unit }
    static var lineY: CGFloat { Design.App.textBaseline }
    static var row: CGFloat { u }
    static var strip: CGFloat { u * 2 }
    static var notes: CGFloat { u * 3 }
    static var line: CGFloat { u }
    static var bar: CGFloat { u }
    static let square: CGFloat = 12, step: CGFloat = 24
    /// The catalogue row: Set Active and its circle take the first 92 points, then the square, then the name.
    private static let activeWidth: CGFloat = 92
    /// Inside the open row, top down: About and its notes on a hairline; All Colours; Directory; Contents and its rule; the lines.
    private static var aboutLabel: CGFloat { lineY }
    private static var aboutBox: CGFloat { u }
    private static var coloursLabel: CGFloat { 4 * u + lineY }
    private static var coloursValue: CGFloat { 5 * u + lineY }
    private static var directoryLabel: CGFloat { 6 * u + lineY }
    private static var directory: CGFloat { 7 * u + lineY }
    private static var contentsLabel: CGFloat { 8 * u + lineY }
    private static var contentsRule: CGFloat { 9 * u - 1 }
    private static var linesTop: CGFloat { 9 * u }
    private static var actions: CGFloat { u }
    /// A line's parts: the square, then its colours as a strip, then the name.
    private static let inset: CGFloat = 16, stripWidth: CGFloat = 72, stripHeight: CGFloat = 12
    private static let coloursKey = "catalogue.colours"

    private enum Item: Hashable { case project(UUID), palette(UUID) }
    /// One line of the contents: a heading; a thing with its colours and a count, tickable when it is a member or a palette; or a warning that a collection is empty.
    private struct Line { var text: String; var count: String; var item: Item?; var indent: Int; var heading: Bool; var warning = false; var hexes: [String] = []; var collection: UUID? = nil; var member = "" }

    init() {
        super.init(frame: .zero)
        openButton.target = self; openButton.action = #selector(openCatalogue)
        newButton.target = self; newButton.action = #selector(newCatalogue)
        finderButton.target = self; finderButton.action = #selector(showInFinder)
        importButton.target = self; importButton.action = #selector(importPressed)
        exportButton.target = self; exportButton.action = #selector(exportPressed)
        aboutScroll.documentView = about
        aboutScroll.hasVerticalScroller = true
        aboutScroll.autohidesScrollers = true
        aboutScroll.drawsBackground = false
        aboutScroll.borderType = .noBorder
        aboutScroll.isHidden = true
        about.font = Design.Text.body.font()
        about.textColor = Design.ink
        about.drawsBackground = false
        about.insertionPointColor = Design.ink
        // No inset: the words start on the row's own left edge, under the heading.
        about.textContainerInset = .zero
        about.textContainer?.lineFragmentPadding = 0
        about.isRichText = false
        about.delegate = self
        about.autoresizingMask = [.width]
        about.isVerticallyResizable = true
        about.textContainer?.widthTracksTextView = true
        for v in [openButton, newButton, finderButton, importButton, exportButton, aboutScroll] { addSubview(v) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    func reload() {
        names = library?.availableCatalogues() ?? []
        for name in Array(removeButtons.keys) where !names.contains(name) {
            removeButtons.removeValue(forKey: name)?.removeFromSuperview()
        }
        for name in names where removeButtons[name] == nil {
            let button = SwissButton("Remove…", .secondary)
            button.identifier = NSUserInterfaceItemIdentifier(name)
            button.target = self; button.action = #selector(removeCataloguePressed(_:))
            button.setAccessibilityLabel("Remove Catalogue \(name)")
            button.toolTip = "Review removal of \(name)"
            removeButtons[name] = button
            addSubview(button)
        }
        if let e = expanded, !names.contains(e) { expanded = nil; picking = false; openness = [:] }
        loadContents()
        refresh()
    }

    private func refresh() { needsLayout = true; needsDisplay = true; onResize?() }

    // MARK: A catalogue's own colour, kept with the settings by its name; its notes, kept in its file.

    private static var colours: [String: String] {
        get { AppPreferences.shared.dictionary(forKey: coloursKey) as? [String: String] ?? [:] }
        set { AppPreferences.shared.set(newValue, forKey: coloursKey) }
    }
    private func colour(of name: String) -> NSColor? { Self.colours[name].map { Design.hex($0) } }
    private func index(of name: String) -> URL { Catalogues.standard.store(for: name).url }

    private func loadAbout() {
        guard let e = expanded else { return }
        about.string = CatalogueFiles.about(index: index(of: e))
    }
    private func saveAbout() {
        guard let e = expanded, FileManager.default.fileExists(atPath: index(of: e).path) else { return }
        try? CatalogueFiles.setAbout(about.string, index: index(of: e))
    }
    func textDidEndEditing(_ notification: Notification) { saveAbout() }
    func textDidChange(_ notification: Notification) { needsDisplay = true }

    // MARK: What a catalogue holds

    /// The library of a catalogue: the open one's as it stands, any other's read from its file.
    private func libraryFor(_ name: String) -> Library? {
        if let lib = library, lib.catalogue == name { return lib.library }
        return try? Catalogues.standard.store(for: name).load()
    }

    /// A change to a catalogue: through the controller for the open one, so it is a step in the history; on the file for any other.
    private func edit(_ name: String, _ title: String, _ body: (inout Library) -> Void) throws {
        if let lib = library, lib.catalogue == name { lib.apply(title, body); return }
        let store = Catalogues.standard.store(for: name)
        var l = try store.load()
        body(&l)
        try store.save(l)
    }

    private func loadContents() {
        ticked = []
        guard let e = expanded, let lib = libraryFor(e) else { contents = nil; lines = []; return }
        contents = lib
        lines = Self.lines(of: lib, schema: SchemaTrial.read(in: Catalogues.standard.directory(for: e)))
    }

    /// The catalogue as rail1 lists it: Favourites; each collection with its folders and members, or a word that it is empty; the loose palettes.
    private static func lines(of lib: Library, schema: SchemaTrial.SchemaFile) -> [Line] {
        var out: [Line] = []
        func palette(_ s: Swatch, _ indent: Int) -> Line {
            Line(text: s.name, count: "\(s.entries.count)", item: .palette(s.id), indent: indent, heading: false, hexes: s.entries.map { $0.hex })
        }
        let favourites = lib.orderedFavourites
        if !favourites.isEmpty {
            out.append(Line(text: "Favourites", count: "", item: nil, indent: 0, heading: true))
            out += favourites.map { palette($0, 0) }
        }
        let all = schema.collections, places = schema.places
        func members(of c: SchemaCollection, folder: UUID?) -> [Project] {
            lib.orderedProjects.filter { p in
                SchemaTrial.collection(of: p.id, among: all, places: places).id == c.id && SchemaTrial.folder(of: p.id, among: all, places: places) == folder
            }
        }
        func member(_ p: Project, _ indent: Int) -> Line {
            let own = lib.palettes(in: p.id)
            var seen = Set<String>(), hexes: [String] = []
            for h in own.flatMap({ $0.entries.map { $0.hex } }) where !seen.contains(h) { seen.insert(h); hexes.append(h) }
            return Line(text: p.name, count: "\(own.count)", item: .project(p.id), indent: indent, heading: false, hexes: hexes)
        }
        for c in all {
            out.append(Line(text: c.name, count: "", item: nil, indent: 0, heading: true))
            var any = false
            if c.folderName != nil {
                for f in c.folders {
                    let inside = members(of: c, folder: f.id)
                    out.append(Line(text: f.name, count: "\(inside.count)", item: nil, indent: 0, heading: false))
                    out += inside.map { member($0, 1) }
                    any = true
                }
            }
            let loose = members(of: c, folder: nil)
            out += loose.map { member($0, 0) }
            if !any && loose.isEmpty {
                // The member's own word from the schema, "Project" or "Client": "No clients", and Add First Client at the right.
                let what = c.stack.name.isEmpty ? "Member" : c.stack.name
                out.append(Line(text: "No \(SchemaTrial.plural(what).lowercased())", count: "", item: nil, indent: 0, heading: false, warning: true, collection: c.id, member: what))
            }
        }
        out.append(Line(text: "Palettes", count: "", item: nil, indent: 0, heading: true))
        out += lib.palettes(in: nil).map { palette($0, 0) }
        return out
    }

    // MARK: Where things are

    /// The three buttons sit in the first two units, their words on the second line; the rule closes the third.
    var sectionAnchors: [(String,CGFloat)] { [("Actions",SettingsSheet.headerGuide+1),("Catalogues",rowsTop+1)] }
    private var rowsTop: CGFloat { SettingsSheet.contentStart + 3 * Self.u - 1 }
    private var others: [String] { names.filter { $0 != expanded } }
    /// The panel's full height, and its height now, part way through opening or closing.
    private func fullPanelHeight(for name: String) -> CGFloat {
        var h = Self.linesTop + CGFloat(lines.count) * Self.line
        if !ticked.isEmpty { h += Self.bar }
        h += Self.u
        if name == expanded && picking { h += Self.strip + Self.u }
        return h + Self.actions + Self.u
    }
    private func panelHeight(for name: String) -> CGFloat { (fullPanelHeight(for: name) * (openness[name] ?? 0)).rounded() }

    /// The whole view's height at a width: the actions, the rows with their panels, the caption.
    func height(forWidth width: CGFloat) -> CGFloat {
        var y = rowsTop + 1
        for n in names { y += Self.row + panelHeight(for: n) }
        return y + Self.u + 3 * Self.u + Self.u
    }

    /// Opens or shuts rows over a quarter of a second, eased, the way a drawer moves.
    private func animate() {
        guard clock == nil else { return }
        let started = Date()
        let from = openness
        clock = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            let f = min(1, Date().timeIntervalSince(started) / 0.25)
            let eased = CGFloat(1 - pow(1 - f, 3))
            var done = true
            for n in Set(from.keys).union(self.expanded.map { [$0] } ?? []) {
                let target: CGFloat = n == self.expanded ? 1 : 0
                let start = from[n] ?? 0
                // Snap to the target on the last tick: the easing's arithmetic lands a hair short of 1 otherwise.
                let now = f >= 1 ? target : start + (target - start) * eased
                self.openness[n] = now
                if now != target { done = false }
            }
            if done {
                t.invalidate(); self.clock = nil
                self.openness = self.openness.filter { $0.value > 0 }
            }
            self.refresh()
        }
        RunLoop.main.add(clock!, forMode: .common)
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 0
        for b in [openButton, newButton, finderButton, importButton, exportButton] {
            let w = b.intrinsicContentSize.width
            b.frame = NSRect(x: x, y: SettingsSheet.contentStart + Self.u + Self.lineY - 22, width: w, height: 32)
            x += w + 12
        }
        var rowY = rowsTop + 1
        for name in names {
            if let button = removeButtons[name] {
                let width = button.intrinsicContentSize.width
                button.frame = NSRect(x: bounds.width - width, y: rowY, width: width, height: Self.row)
            }
            rowY += Self.row + panelHeight(for: name)
        }
        let open = expanded.map { openness[$0] ?? 0 } ?? 0
        aboutScroll.isHidden = open < 1
        if let e = expanded {
            var y = rowsTop + 1
            for n in names { if n == e { break }; y += Self.row + panelHeight(for: n) }
            aboutScroll.frame = NSRect(x: 0, y: y + Self.row + Self.aboutBox, width: bounds.width, height: Self.notes)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        SettingsSheet.title("Catalogues.")
        SettingsSheet.divider(above: SettingsSheet.headerGuide, width: bounds.width)
        var y = rowsTop
        hairline(x: 0, y: y, width: bounds.width, Design.rule)
        y += 1
        rowHits = []; activeHits = []; actionHits = []; lineHits = []; lineActionHits = []; barHits = []; addHits = []
        spectrum = .zero
        let current = library?.catalogue
        for n in names {
            let row = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
            let b = y + Self.lineY
            let active = n == current
            // Set Active: a circle, filled for the open catalogue, and the word; a click here swaps without opening the row.
            let c = NSRect(x: 1, y: b - 9, width: 10, height: 10)
            let circle = NSBezierPath(ovalIn: c.insetBy(dx: 0.5, dy: 0.5)); circle.lineWidth = 1
            if active { Design.ink.setFill(); circle.fill() } else { (hover == n ? Design.ink : Design.quiet).setStroke(); circle.stroke() }
            Design.attributed(active ? "Active" : "Set Active", .caption, colour: active ? Design.ink : Design.quiet).draw(x: 18, baseline: b)
            if !active { activeHits.append((NSRect(x: -6, y: y, width: Self.activeWidth, height: Self.row), n)) }
            // The square: the catalogue's colour, or Card; a static mark now.
            let sq = NSRect(x: Self.activeWidth, y: b - 10, width: Self.square, height: Self.square)
            let own = colour(of: n)
            fill(sq, own ?? Design.card)
            Design.ink.setStroke()
            let edge = NSBezierPath(rect: sq.insetBy(dx: 0.5, dy: 0.5)); edge.lineWidth = 1; edge.stroke()
            let nx = Self.activeWidth + Self.step
            Design.attributed(n, active ? .bodyStrong : .body).draw(x: nx, baseline: b, width: max(0, bounds.width - nx - (removeButtons[n]?.intrinsicContentSize.width ?? 90) - 16))
            let open = openness[n] ?? 0
            // A shut row ends on its divider; an open one is a container, and the divider moves down to close it.
            if open == 0 { hairline(x: 0, y: y + Self.row - 1, width: bounds.width, Design.mist) }
            rowHits.append((row, n))
            y += Self.row
            if open > 0 {
                let shown = panelHeight(for: n)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: NSRect(x: 0, y: y, width: bounds.width, height: shown)).addClip()
                drawPanel(n, at: y, live: n == expanded && open == 1, own: own)
                NSGraphicsContext.restoreGraphicsState()
                y += shown
                hairline(x: 0, y: y - 1, width: bounds.width, Design.mist)
            }
        }
        y += Self.u
        Design.attributed("A catalogue is a separate library with its own colours, palettes and projects. Open Catalogue puts one on the list where it is, from its .colcatalogue file, or makes one from a library.json; nothing is copied or changed. Tick what a catalogue holds to relocate it to another catalogue or remove it; Remove opens a guided choice to detach, archive, transfer or bin owned files.", .caption, colour: Design.quiet, lineHeight: true)
            .draw(in: NSRect(x: 0, y: y, width: min(bounds.width, 560), height: 3 * Self.u))
    }

    /// A palette's colours as a strip, every colour an equal band, the way rail2 draws one.
    private func strip(_ hexes: [String], in r: NSRect) {
        guard !hexes.isEmpty else {
            Design.rule.setStroke()
            let e = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)); e.lineWidth = 1; e.stroke()
            return
        }
        let band = r.width / CGFloat(hexes.count)
        for (i, h) in hexes.enumerated() { fill(NSRect(x: r.minX + CGFloat(i) * band, y: r.minY, width: band + 0.5, height: r.height), Design.hex(h)) }
    }

    /// The open row's panel, on the row's own left edge. `live` is a fully open panel, the one that takes clicks.
    private func drawPanel(_ n: String, at y: CGFloat, live: Bool, own: NSColor?) {
        let w = bounds.width
        Design.attributed("About", .header).draw(x: 0, baseline: y + Self.aboutLabel)
        if about.string.isEmpty {
            Design.attributed("Add catalogue notes\u{2026}", .body, colour: Design.soft).draw(at: NSPoint(x: 0, y: y + Self.aboutBox))
        }
        hairline(x: 0, y: y + Self.aboutBox + Self.notes, width: w, Design.rule)
        Design.attributed("All Colours", .header).draw(x: 0, baseline: y + Self.coloursLabel)
        Design.attributed(contents.map { plural($0.colours.count, "colour") } ?? "", .body, colour: Design.quiet).draw(x: 0, baseline: y + Self.coloursValue)
        Design.attributed("Directory", .header).draw(x: 0, baseline: y + Self.directoryLabel)
        let dir = Catalogues.standard.directory(for: n)
        Design.attributed((dir.path as NSString).abbreviatingWithTildeInPath, .body, colour: Design.quiet).draw(x: 0, baseline: y + Self.directory, width: w)
        // Contents: the catalogue as rail1 lists it, a square before each thing that can be ticked, its colours, its name.
        Design.attributed("Contents", .header).draw(x: 0, baseline: y + Self.contentsLabel)
        hairline(x: 0, y: y + Self.contentsRule, width: w, Design.rule)
        var ly = y + Self.linesTop
        for l in lines {
            let lb = ly + Self.lineY
            if l.heading {
                Design.attributed(l.text, .body).draw(x: 0, baseline: lb)
            } else if l.warning {
                // An empty collection: a small orange triangle and the word.
                let t = NSBezierPath()
                t.move(to: NSPoint(x: Self.inset + 6, y: lb - 10)); t.line(to: NSPoint(x: Self.inset + 12, y: lb)); t.line(to: NSPoint(x: Self.inset, y: lb)); t.close()
                Design.orange.setFill(); t.fill()
                Design.attributed(l.text, .body, colour: Design.quiet).draw(x: Self.inset + Self.step, baseline: lb)
                // The way on, at the right: a plus and "Add First Client".
                let add = Design.attributed("Add First \(l.member)", .caption, colour: Design.quiet)
                let ax = w - add.size().width
                add.draw(x: ax, baseline: lb)
                icon(4, at: NSPoint(x: ax - 14, y: lb - 9), colour: Design.quiet, own: nil, small: true)
                if live, let c = l.collection { addHits.append((NSRect(x: ax - 20, y: ly, width: add.size().width + 24, height: Self.line), c, l.member)) }
            } else {
                let x = Self.inset + CGFloat(l.indent) * Self.step
                if let item = l.item {
                    let on = ticked.contains(item)
                    let sq = NSRect(x: x, y: lb - 10, width: Self.square, height: Self.square)
                    fill(sq, on ? Design.ink : lineHover == item ? Design.mist : Design.card)
                    Design.ink.setStroke()
                    let edge = NSBezierPath(rect: sq.insetBy(dx: 0.5, dy: 0.5)); edge.lineWidth = 1; edge.stroke()
                    strip(l.hexes, in: NSRect(x: x + 20, y: lb - 10, width: Self.stripWidth, height: Self.stripHeight))
                    // The line's own triggers at the right, from the edge leftwards, then its count.
                    var ax = w
                    for (title, glyph) in [("Remove", 2), ("Relocate", 3), ("Duplicate", 1)] {
                        let t = Design.attributed(title, .caption, colour: Design.quiet)
                        ax -= t.size().width
                        t.draw(x: ax, baseline: lb)
                        ax -= 14
                        icon(glyph, at: NSPoint(x: ax, y: lb - 9), colour: Design.quiet, own: nil, small: true)
                        if live { lineActionHits.append((NSRect(x: ax - 4, y: ly, width: t.size().width + 24, height: Self.line), item, glyph)) }
                        ax -= 20
                    }
                    let count = Design.attributed(l.count, .caption, colour: Design.quiet)
                    count.draw(right: ax - 8, baseline: lb)
                    let nameX = x + 20 + Self.stripWidth + 12
                    Design.attributed(l.text, .body, colour: on ? Design.ink : Design.quiet).draw(x: nameX, baseline: lb, width: ax - 8 - count.size().width - 12 - nameX)
                    if live { lineHits.append((NSRect(x: 0, y: ly, width: ax - 8, height: Self.line), item)) }
                } else {
                    Design.attributed(l.text, .body, colour: Design.quiet).draw(x: x, baseline: lb, width: w - x - 48)
                    Design.attributed(l.count, .caption, colour: Design.quiet).draw(right: w, baseline: lb)
                }
            }
            ly += Self.line
        }
        if !ticked.isEmpty {
            // The bar for what is ticked: the count at the left, Relocate and Remove at the right.
            hairline(x: 0, y: ly, width: w, Design.mist)
            let bb = ly + Self.lineY
            Design.attributed("\(ticked.count) Selected", .body, colour: Design.quiet).draw(x: Self.inset, baseline: bb)
            var ax = w
            for (title, glyph) in [("Remove", 2), ("Relocate", 3)] {
                let t = Design.attributed(title, .body, colour: Design.quiet)
                ax -= t.size().width
                t.draw(x: ax, baseline: bb)
                ax -= 16
                icon(glyph, at: NSPoint(x: ax, y: bb - 10), colour: Design.quiet, own: nil)
                if live { barHits.append((NSRect(x: ax - 4, y: ly, width: t.size().width + 28, height: Self.bar), glyph)) }
                ax -= 24
            }
            ly += Self.bar
        }
        var ay = ly + Self.u
        if n == expanded && picking {
            // The hue strip, the whole way across and above the actions: each click gives the catalogue that colour.
            if live { spectrum = NSRect(x: 0, y: ay, width: w, height: Self.strip) }
            for px in stride(from: 0, to: w, by: 1) {
                NSColor(hue: px / w, saturation: 0.85, brightness: 0.95, alpha: 1).setFill()
                NSRect(x: px, y: ay, width: 1.5, height: Self.strip).fill()
            }
            ay += Self.strip + Self.u
        }
        // The actions from the right edge leftwards; the live one underlined, never bold, so nothing moves.
        let ab = ay + Self.lineY
        var ax = w
        for (title, glyph) in [("Remove", 2), ("Duplicate", 1), ("Assign Colour", 0)] {
            let on = glyph == 0 && picking
            let t = Design.attributed(title, .body, colour: on ? Design.ink : Design.quiet)
            ax -= t.size().width
            t.draw(x: ax, baseline: ab)
            if on { hairline(x: ax, y: ab + 4, width: t.size().width, Design.ink) }
            ax -= 16
            icon(glyph, at: NSPoint(x: ax, y: ab - 10), colour: on ? Design.ink : Design.quiet, own: own)
            if live { actionHits.append((NSRect(x: ax - 4, y: ay, width: t.size().width + 28, height: Self.actions), glyph)) }
            ax -= 24
        }
    }

    /// The small marks: a square for a colour, two squares for a copy, a cross for the end, an arrow for a move. `small` is the 10-point size beside a caption.
    private func icon(_ which: Int, at p: NSPoint, colour: NSColor, own: NSColor?, small: Bool = false) {
        colour.setStroke()
        let s: CGFloat = small ? 9 : 11
        switch which {
        case 0:
            let r = NSRect(x: p.x + 0.5, y: p.y + 0.5, width: s, height: s)
            if let own = own { own.setFill(); r.fill() }
            let path = NSBezierPath(rect: r); path.lineWidth = 1; path.stroke()
        case 1:
            for (dx, dy) in [(3, 0), (0, 3)] {
                let r = NSRect(x: p.x + CGFloat(dx) + 0.5, y: p.y + CGFloat(dy) + 0.5, width: s - 3, height: s - 3)
                Design.card.setFill(); r.fill()
                let path = NSBezierPath(rect: r); path.lineWidth = 1; path.stroke()
            }
        case 4:
            let m = (s + 1) / 2
            let path = NSBezierPath()
            path.move(to: NSPoint(x: p.x, y: p.y + m)); path.line(to: NSPoint(x: p.x + s, y: p.y + m))
            path.move(to: NSPoint(x: p.x + m, y: p.y)); path.line(to: NSPoint(x: p.x + m, y: p.y + s))
            path.lineWidth = 1.2; path.stroke()
        case 3:
            let m = (s + 1) / 2
            let path = NSBezierPath()
            path.move(to: NSPoint(x: p.x, y: p.y + m)); path.line(to: NSPoint(x: p.x + s, y: p.y + m))
            path.move(to: NSPoint(x: p.x + s - 4, y: p.y + m - 4)); path.line(to: NSPoint(x: p.x + s, y: p.y + m)); path.line(to: NSPoint(x: p.x + s - 4, y: p.y + m + 4))
            path.lineWidth = 1.2; path.stroke()
        default:
            let path = NSBezierPath()
            path.move(to: NSPoint(x: p.x + 1, y: p.y + 1)); path.line(to: NSPoint(x: p.x + s, y: p.y + s))
            path.move(to: NSPoint(x: p.x + s, y: p.y + 1)); path.line(to: NSPoint(x: p.x + 1, y: p.y + s))
            path.lineWidth = 1.2; path.stroke()
        }
    }

    // MARK: The pointer

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let over = rowHits.first { $0.0.contains(p) }?.1
        let overLine = lineHits.first { $0.0.contains(p) }?.1
        if over != hover || overLine != lineHover { hover = over; lineHover = overLine; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { hover = nil; lineHover = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if spectrum.contains(p), let e = expanded {
            // The strip stays open: each click is the catalogue's colour until the strip is put away.
            let c = NSColor(hue: max(0, min(1, p.x / spectrum.width)), saturation: 0.85, brightness: 0.95, alpha: 1)
            var all = Self.colours
            all[e] = hexOf(c) ?? "#000000"
            Self.colours = all
            needsDisplay = true
            return
        }
        if let a = actionHits.first(where: { $0.0.contains(p) }) {
            switch a.1 {
            case 0: picking.toggle()
            case 1: duplicateExpanded()
            default: askToRemove()
            }
            refresh()
            return
        }
        if let b = barHits.first(where: { $0.0.contains(p) }) {
            if b.1 == 3 { relocateMenu(for: ticked, below: b.0) } else { askToRemove(ticked) }
            return
        }
        if let a = addHits.first(where: { $0.0.contains(p) }) { addFirst(in: a.1, called: a.2); return }
        if let la = lineActionHits.first(where: { $0.0.contains(p) }) {
            switch la.2 {
            case 1: duplicate(la.1)
            case 3: relocateMenu(for: [la.1], below: la.0)
            default: askToRemove([la.1])
            }
            return
        }
        if let l = lineHits.first(where: { $0.0.contains(p) }) {
            if ticked.contains(l.1) { ticked.remove(l.1) } else { ticked.insert(l.1) }
            refresh()
            return
        }
        if let s = activeHits.first(where: { $0.0.contains(p) }), let lib = library {
            if s.1 != lib.catalogue { lib.open(catalogue: s.1); onChange?() }
            return
        }
        if let r = rowHits.first(where: { $0.0.contains(p) }) {
            saveAbout()
            expanded = expanded == r.1 ? nil : r.1
            picking = false
            loadAbout()
            loadContents()
            animate()
            refresh()
        }
    }

    // MARK: The list of other catalogues, dropped under Relocate

    private func relocateMenu(for items: Set<Item>, below r: NSRect) {
        guard let win = window, !items.isEmpty else { return }
        let places = others + ["New Catalogue\u{2026}"]
        let panel = SwissDropdown.MenuPanel(items: places, chosen: "", width: 240) { [weak self] i in
            guard let self = self else { return }
            self.closeMenu()
            if i == places.count - 1 {
                do { self.relocate(items, to: try Catalogues.standard.create(Self.freshName())) } catch { self.library?.show(error) }
            } else { self.relocate(items, to: places[i]) }
        }
        let origin = win.convertToScreen(convert(NSRect(x: r.maxX - 240, y: r.maxY, width: 1, height: 1), to: nil)).origin
        panel.place(below: NSPoint(x: origin.x, y: origin.y - 2))
        win.addChildWindow(panel, ordered: .above)
        dropped = panel
        Overlays.opened(self)
    }

    private func closeMenu() {
        if let m = dropped { m.parent?.removeChildWindow(m); m.orderOut(nil) }
        dropped = nil
        Overlays.closed(self)
    }

    // MARK: Moving, copying and removing what is ticked

    private static func freshName() -> String {
        let taken = Catalogues.standard.names()
        var n = 1
        while taken.contains("Catalogue \(n)") { n += 1 }
        return "Catalogue \(n)"
    }

    /// What the items come to: the members, with every palette of theirs, and the palettes ticked on their own.
    private func gather(_ items: Set<Item>, in lib: Library) -> (projects: [Project], palettes: [Swatch]) {
        var projects: [Project] = [], palettes: [Swatch] = []
        for case .project(let id) in items {
            if let p = lib.project(id) { projects.append(p); palettes += lib.palettes(in: id) }
        }
        for case .palette(let id) in items where !palettes.contains(where: { $0.id == id }) {
            if let s = lib.swatch(id) { palettes.append(s) }
        }
        return (projects, palettes)
    }

    /// The same thing under a new id and name: through its file form, so every field travels.
    private func copy<T: Codable>(_ v: T, named name: String) -> (T, UUID)? {
        guard let data = try? ColourFiles.encoder().encode(v), var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let id = UUID()
        obj["id"] = id.uuidString
        obj["name"] = name
        guard let out = try? JSONSerialization.data(withJSONObject: obj), let made = try? ColourFiles.decoder().decode(T.self, from: out) else { return nil }
        return (made, id)
    }

    /// Puts members and palettes into a library. One already there, by id or by name, goes in as a copy, suffixed (Copy).
    private func put(projects: [Project], palettes: [Swatch], into dst: inout Library) {
        var remap: [UUID: UUID] = [:]
        for p in projects {
            if dst.project(p.id) == nil && !dst.projects.contains(where: { $0.name == p.name }) { dst.projects.append(p); continue }
            if let (c, id) = copy(p, named: p.name + " (Copy)") { dst.projects.append(c); remap[p.id] = id }
        }
        for s in palettes {
            var s = s
            if let pid = s.projectID {
                if let new = remap[pid] { s.projectID = new } else if dst.project(pid) == nil { s.projectID = nil }
            }
            let taken = dst.swatch(s.id) != nil || dst.swatches.contains { $0.name == s.name && $0.projectID == s.projectID }
            if !taken { dst.swatches.append(s); continue }
            if let (c, _) = copy(s, named: s.name + " (Copy)") { dst.swatches.append(c) }
        }
    }

    /// Copies the members and palettes into the target with the colours, profiles and tags they use, then takes them out of the source.
    private func move(projects: [Project], palettes: [Swatch], from source: String, to target: String, in lib: Library) throws {
        let hexes = Set(palettes.flatMap { $0.entries.map { $0.hex } })
        let colours = lib.colours.filter { hexes.contains($0.hex) }
        let profiles = lib.colourProfiles.filter { pr in projects.contains { $0.profile == pr.id } }
        let ids = Set(projects.map { $0.id })
        let tags = lib.tagInfo.filter { $0.projectID.map { ids.contains($0) } ?? false }
        try edit(target, "Relocate In") { dst in
            self.put(projects: projects, palettes: palettes, into: &dst)
            for c in colours where !dst.colours.contains(where: { $0.hex == c.hex }) { dst.colours.append(c) }
            for pr in profiles where !dst.colourProfiles.contains(where: { $0.id == pr.id }) { dst.colourProfiles.append(pr) }
            for t in tags where !dst.tagInfo.contains(where: { $0.name == t.name && $0.projectID == t.projectID }) { dst.tagInfo.append(t) }
        }
        try edit(source, "Relocate Out") { src in
            for s in palettes { src.deleteSwatch(s.id) }
            for p in projects { src.deleteProject(p.id) }
        }
    }

    private func relocate(_ items: Set<Item>, to target: String) {
        guard let e = expanded, let lib = contents, !items.isEmpty, target != e else { return }
        let picked = gather(items, in: lib)
        do { try move(projects: picked.projects, palettes: picked.palettes, from: e, to: target, in: lib) } catch { library?.show(error) }
        names = library?.availableCatalogues() ?? names
        loadContents(); refresh(); onChange?()
    }

    /// The collection's first member, named for what the schema calls one, placed in the collection; it is renamed on its Overview.
    private func addFirst(in collection: UUID, called kind: String) {
        guard let e = expanded else { return }
        var made: UUID?
        do { try edit(e, "New \(kind)") { lib in made = lib.createProject(named: "\(kind) 1") } } catch { library?.show(error) }
        if let id = made { SchemaTrial.place(id, in: collection, folder: nil, catalogue: Catalogues.standard.directory(for: e)) }
        loadContents(); refresh(); onChange?()
    }

    /// A copy beside the original, suffixed (Copy); a member's palettes come with it.
    private func duplicate(_ item: Item) {
        guard let e = expanded, let lib = contents else { return }
        let picked = gather([item], in: lib)
        do {
            try edit(e, "Duplicate") { src in
                var remap: [UUID: UUID] = [:]
                for p in picked.projects { if let (c, id) = self.copy(p, named: p.name + " (Copy)") { src.projects.append(c); remap[p.id] = id } }
                for s in picked.palettes {
                    guard let (c, _) = self.copy(s, named: s.name + " (Copy)") else { continue }
                    var made = c
                    if let pid = s.projectID, let new = remap[pid] { made.projectID = new }
                    src.swatches.append(made)
                }
            }
        } catch { library?.show(error) }
        loadContents(); refresh(); onChange?()
    }

    private func askToRemove(_ items: Set<Item>) {
        guard let e = expanded, let lib = contents, !items.isEmpty else { return }
        let picked = gather(items, in: lib)
        // The title is the act and its object; the note names what, then what it means.
        let title = picked.projects.isEmpty ? (picked.palettes.count == 1 ? "Remove Palette" : "Remove Palettes")
            : items.count == picked.projects.count ? (picked.projects.count == 1 ? "Remove Member" : "Remove Members") : "Remove Items"
        let names = (picked.projects.map { $0.name } + picked.palettes.filter { s in !picked.projects.contains { $0.id == s.projectID } }.map { $0.name })
        let listed = names.count <= 3 ? names.joined(separator: ", ") : "\(names.prefix(2).joined(separator: ", ")) and \(names.count - 2) more"
        SwissConfirm.ask(over: window, title: title,
                         note: "You are about to remove \(listed) from \(e). It goes for good, a member's palettes with it; the colours stay in the catalogue. Slide across to go on.",
                         commit: "Remove") { [weak self] in
            guard let self = self else { return }
            do {
                try self.edit(e, "Remove") { src in
                    for s in picked.palettes { src.deleteSwatch(s.id) }
                    for p in picked.projects { src.deleteProject(p.id) }
                }
            } catch { self.library?.show(error) }
            self.loadContents(); self.refresh(); self.onChange?()
        }
    }

    // MARK: The catalogue's own actions

    private func duplicateExpanded() {
        guard let e = expanded, let lib = library else { return }
        saveAbout()
        do {
            let copy = try Catalogues.standard.store(for: e).load()
            let name = try Catalogues.standard.create(e + " (Copy)", holding: copy)
            try? CatalogueFiles.setAbout(about.string, index: index(of: name))
            if let c = Self.colours[e] { var all = Self.colours; all[name] = c; Self.colours = all }
        } catch { lib.show(error) }
        reload(); onChange?()
    }

    @objc private func removeCataloguePressed(_ sender: SwissButton) {
        guard let name = sender.identifier?.rawValue else { return }
        saveAbout()
        askToRemove(name)
    }

    private func askToRemove() {
        guard let name = expanded else { return }
        askToRemove(name)
    }

    private func askToRemove(_ name: String) {
        guard let window else { return }
        FileCatalogueRemovalWizard(name: name, window: window) { [weak self] success in
            guard let self, success else { return }
            let available = Catalogues.standard.names()
            if let library = self.library, library.catalogue == name {
                if let next = available.first { library.open(catalogue: next) }
                else { (NSApp.delegate as? AppDelegate)?.runSetupAssistant() }
            }
            self.expanded = nil; self.reload(); self.onChange?()
        }.start()
    }

    @objc private func openCatalogue() {
        guard let lib = library, let w = window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: ColourFiles.catalogue), UTType(filenameExtension: ColourFiles.legacyCatalogue), .json].compactMap { $0 }
        panel.prompt = "Open"
        panel.message = "Choose a catalogue's .colcatalogue file to open it where it is, or a library.json to make a catalogue from it."
        panel.beginSheetModal(for: w) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            CatalogueOpen.selected(url, over: w) { [weak self] result in
                switch result {
                case .success(let name): if let name { lib.open(catalogue: name); self?.onChange?() }
                case .failure(let error): lib.show(error)
                }
            }
        }
    }

    @objc private func importPressed() { onImport?() }
    @objc private func exportPressed() { onExport?() }
    @objc private func newCatalogue() {
        guard let lib = library else { return }
        do { lib.open(catalogue: try Catalogues.standard.create(Self.freshName())) } catch { lib.show(error) }
        onChange?()
    }

    @objc private func showInFinder() {
        guard let lib = library else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lib.store.url])
    }
}

/// The Settings curtain occupies Rail 1 alone, clipped at the footer's upper edge.
private final class SettingsRailCurtain: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Design.card.setFill(); bounds.fill()
        NSBezierPath(rect: bounds).addClip()
        NSColor(calibratedWhite: 0.82, alpha: 1).setFill()
        let stripe: CGFloat = 48
        var y = -bounds.width - stripe * 2
        while y < bounds.height + stripe * 2 {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 0, y: y))
            p.line(to: NSPoint(x: bounds.width, y: y + bounds.width))
            p.line(to: NSPoint(x: bounds.width, y: y + bounds.width + stripe))
            p.line(to: NSPoint(x: 0, y: y + stripe))
            p.close(); p.fill()
            y += stripe * 2
        }
    }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override var acceptsFirstResponder: Bool { true }
    override func scrollWheel(with event: NSEvent) { }
}
