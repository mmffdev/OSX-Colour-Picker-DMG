import AppKit
import UniformTypeIdentifiers

final class ProofingPage: NSView, PageSection, NSTextFieldDelegate {
    var sectionAnchors: [(String,CGFloat)] {
        [("Set The Proof",baseline(2)+1),("Summary",baseline(Rows.summary)+1),("Charts",Rows.plots*u),
         ("Density",baseline(Rows.density)+1),("Inspect",baseline(Rows.inspector)+1),("Register",baseline(Rows.register)+1)]
    }
    var onResize: (() -> Void)?
    private let library: LibraryController
    private var session: ProofSession
    private var results: [ProofResult] = []
    private var busy = false, generation = 0
    private var selected = 0, pageNumber = 0
    private var filter = "All patches", sort = "Source order"
    private var message = ""
    private var menus: [SwissDropdown] = []
    private var hovered: Int?
    private var tracking: NSTrackingArea?
    private var menuSignature = ""
    private let settingsBody = ProofSettingsBody()
    lazy var settingsRail: ProofNavigationRail = {
        let rail = ProofNavigationRail(settings: settingsBody)
        rail.onSelect = { [weak self] in self?.selectPatch($0, reveal:false) }
        return rail
    }()
    private let simulation = ProofDensitySimulation()
    private var charts: [ProofChartView] = []
    private weak var chartDetail: ProofChartDetail?
    private weak var chartModal: SwissFocusModal?
    /// Baselines shared by drawing, controls and hit targets. Whole rows reserve action breathing room.
    private enum Rows {
        static let summary: CGFloat = 16, plots: CGFloat = 26, series: CGFloat = 40
        static let density: CGFloat = 52, densityPlot: CGFloat = 56, inspector: CGFloat = 70
        static let register: CGFloat = 82, results: CGFloat = 85, order: CGFloat = 88
        static let table: CGFloat = 92, pagination: CGFloat = table + 23, end: CGFloat = pagination + 5
    }
    private var railWidth: CGFloat { max(180, settingsBody.bounds.width - settingsBody.inset - settingsBody.insetRight) }
    private let tolerance = NSTextField(string: "2.0"), inkLimit = NSTextField(string: "300"), notes = NSTextField(string: "")
    private let importReference = SwissButton("Import Reference…", .secondary)
    private let importMeasured = SwissButton("Import Measurements…", .secondary)
    private let confirm = SwissButton("Confirm D50 / 2°", .secondary)
    private let save = SwissButton("Save Session…", .secondary), load = SwissButton("Open Session…", .secondary)
    private let monitorSetup = SwissButton("Monitor Setup…", .secondary)
    private let export = SwissButton("Export CSV…", .primary)
    private let pagination = ProofPaginationBar()
    private var hits: [(NSRect, Int)] = []
    private var patchButtons: [ProofPatchButton] = []
    private var registerScrollObserver: NSObjectProtocol?
    private var plotHits: [(NSPoint, Int)] = []
    private var colourHits: [(NSRect, LabD50)] = []
    private var pageLimit = 25, sortColumn = -1, sortAscending = true
    private var pageSize: Int { pageLimit == 0 ? max(1, visible.count) : pageLimit }
    private var paginationRow: CGFloat { Rows.table + CGFloat(min(pageSize, max(0, visible.count - pageNumber * pageSize))) + 1 }
    private let columns: [CGFloat] = [0,0.08,0.38,0.51,0.62,0.72,0.83]
    private let columnLabels = ["ID","Patch","ΔE","ΔL*","Δa*","Δb*","Status"]
    private var headerButtons: [ProofPatchButton] = []
    private let resetConfig = SwissButton("Reset Proof Settings", .secondary)
    private let saveConfig = SwissButton("Save Configuration…", .secondary)
    private let exportConfig = SwissButton("Export Configuration…", .secondary)
    private let loadConfig = SwissButton("Load Configuration…", .secondary)
    private var configurations: [ProofConfiguration] = []
    private var configButtons: [SwissButton] = []
    private var u: CGFloat { Design.App.unit }
    private func baseline(_ row: CGFloat) -> CGFloat { SettingsSheet.baseline(row) }
    private var cx: CGFloat {
        let columns = Design.App.pageColumns(width: bounds.width, in: window?.frame.width ?? Design.App.size.width)
        return columns.x[columns.split]
    }
    private var leftWidth: CGFloat { cx - Design.App.areaGutter }
    private var rightWidth: CGFloat { max(280, bounds.width - cx) }
    private static let builtins = ProofReferences.names
    private static func reference(_ name: String) -> ProofDataset? { try? ProofReferences.read(name) }
    init(library: LibraryController) {
        self.library = library
        let ref = Self.reference("FOGRA51") ?? ProofDataset(name: "No reference loaded", source: "Import a CGATS or CSV reference file", sha256: "", metadata: [:], patches: [])
        session = ProofSession(reference: ref, options: ProofOptions())
        super.init(frame: .zero)
        for (button, action) in [(importReference,#selector(referenceTapped)),(importMeasured,#selector(measuredTapped)),(confirm,#selector(confirmTapped)),(save,#selector(saveTapped)),(load,#selector(loadTapped)),(export,#selector(exportTapped)),(monitorSetup,#selector(monitorSetupTapped))] {
            button.target = self; button.action = action; addSubview(button)
        }
        addSubview(pagination)
        pagination.onPage = { [weak self] page in
            guard let self else { return }; self.pageNumber = page; self.hovered = nil
            self.reload(); self.revealRegisterRows()
        }
        pagination.onLimit = { [weak self] limit in
            guard let self else { return }; self.pageLimit = limit; self.pageNumber = 0; self.hovered = nil
            self.reload(); self.revealRegisterRows()
        }
        for (field, label) in [(tolerance,"Delta E tolerance"),(inkLimit,"Total ink review limit"),(notes,"Proof notes")] {
            field.font = Design.Text.body.font(); field.textColor = Design.ink
            field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
            field.delegate = self; field.setAccessibilityLabel(label); addSubview(field)
        }
        for _ in 0..<25 {
            let button=ProofPatchButton(); button.target=self;button.action=#selector(patchTapped(_:));addSubview(button);patchButtons.append(button)
        }
        for i in columnLabels.indices {
            let b = ProofPatchButton(); b.tag = i; b.target = self; b.action = #selector(sortTapped(_:))
            addSubview(b); headerButtons.append(b)
        }
        for (b,a) in [(resetConfig,#selector(resetConfigTapped)),(saveConfig,#selector(saveConfigTapped)),(exportConfig,#selector(exportConfigTapped)),(loadConfig,#selector(loadConfigTapped))] {
            b.target = self; b.action = a; settingsBody.addSubview(b)
        }
        refreshConfigurations()
        notes.placeholderAttributedString = Design.attributed("Job, substrate, instrument, measurement mode and operator", .body, colour: Design.quiet)
        settingsBody.onLayout = { [weak self] in self?.layoutRail() }
        for view in [importReference, importMeasured, confirm, tolerance, inkLimit] { settingsBody.addSubview(view) }
        for kind in ProofChartKind.allCases {
            let chart = ProofChartView(kind: kind, simulation: simulation)
            chart.onSelect = { [weak self] in self?.selectPatch($0, reveal: false) }
            chart.onExpand = { [weak self] in self?.expandChart(kind) }
            charts.append(chart); addSubview(chart)
        }
        confirm.toolTip = "Use only when you know the imported Lab data uses D50 and a 2° observer. Declared incompatible conditions cannot be overridden."
        setAccessibilityLabel("Proofing workspace")
        evaluate()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let registerScrollObserver { NotificationCenter.default.removeObserver(registerScrollObserver) } }
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let registerScrollObserver { NotificationCenter.default.removeObserver(registerScrollObserver) }
        registerScrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let clip = note.object as? NSClipView, clip === self.enclosingScrollView?.contentView else { return }
            self.layoutPatchButtons(); self.needsDisplay = true
        }
        enclosingScrollView?.contentView.postsBoundsChangedNotifications = true
    }
    override var isFlipped: Bool { true }
    func reload() { refreshConfigurations(); menuSignature = ""; needsLayout = true; needsDisplay = true; onResize?() }
    func height(forWidth width: CGFloat) -> CGFloat { baseline(paginationRow + 5) }
    private var visible: [Int] {
        var indices = results.indices.filter { i in
            filter == "All patches" || (filter == "Needs attention" ? results[i].status(session.options) != .withinTolerance : results[i].status(session.options) == .withinTolerance)
        }
        if sortColumn >= 0 { return ProofRegister.sorted(indices, results: results, options: session.options, column: sortColumn, ascending: sortAscending) }
        if sort == "Largest difference" { return ProofRegister.sorted(indices, results: results, options: session.options, column: 2, ascending: false) }
        return indices
    }
    private func rebuildMenus() {
        let names = library.library.listedPalettes.filter { !$0.isTypography }
        let signature = "\(rightWidth)|\(railWidth)|\(names.map { $0.id.uuidString + $0.name }.joined())|\(session.reference.name)|\(session.options.mode)|\(session.options.profile)|\(session.options.intent)|\(session.options.method)|\(session.options.recipe)|\(filter)|\(sort)"
        guard signature != menuSignature else { return }
        menuSignature = signature
        menus.forEach { $0.removeFromSuperview() }; menus = []
        func menu(_ label: String, value: String, options: [String], row: CGFloat, change: @escaping (String)->Void) {
            let inRail = row < Rows.results
            let view = SwissDropdown(label, value: value, options: options, allowsOwn: false, width: inRail ? railWidth : rightWidth)
            view.toolTip = label + ": " + value
            view.onChange = change; view.frame.origin = NSPoint(x: inRail ? settingsBody.inset : cx, y: baseline(row) - 11)
            let host: NSView = inRail ? settingsBody : self
            host.addSubview(view); menus.append(view)
        }
        let paletteOptions = names.enumerated().map { "Palette \($0.offset+1): \($0.element.name)" }
        menu("Reference", value: session.reference.name, options: Self.builtins.map { $0 + " · 72 patches" } + paletteOptions, row: 0) { [weak self] value in
            guard let self else { return }
            if let i = Self.builtins.firstIndex(where: { value.hasPrefix($0) }), let ref = Self.reference(Self.builtins[i]) { self.session.reference = ref }
            else if let i = paletteOptions.firstIndex(of: value) {
                let palette = names[i]
                let patches = palette.entries.enumerated().compactMap { (i,e) -> ProofPatch? in
                    guard let d = ColourKeys.definition(of: e.hex) ?? ColourDefinition.of(hex: e.hex) else { return nil }
                    let lab = d.master.lab
                    return ProofPatch(id: String(i+1), name: self.library.library.name(of: e.hex, in: palette.id), l: lab.l, a: lab.a, b: lab.b)
                }
                self.session.reference = ProofDataset(name: palette.name, source: "Library palette · \(palette.id)", sha256: "", metadata: ["ILLUMINATION_NAME":"D50","OBSERVER_ANGLE":"2"], patches: patches)
            }
            self.session.options.confirmD50 = false; self.selected = 0; self.pageNumber = 0; self.evaluate()
        }
        menu("Comparison", value: session.options.mode, options: ["Prediction","Measurement"], row: 3) { [weak self] in self?.session.options.mode = $0; self?.evaluate() }
        menu("Output profile", value: session.options.profile, options: PressProfiles.all.map(\.name), row: 6) { [weak self] in self?.session.embeddedProfile = nil; self?.session.options.profile = $0; self?.evaluate() }
        menu("Rendering intent · BPC off", value: RenderingIntent(rawValue: session.options.intent)?.name ?? "Absolute Colorimetric", options: (session.options.recipe ? [RenderingIntent.absolute, .relative] : RenderingIntent.allCases).map(\.name), row: 9) { [weak self] value in
            self?.session.options.intent = RenderingIntent.allCases.first { $0.name == value }!.rawValue; self?.evaluate()
        }
        menu("Prediction input", value: session.options.recipe ? "Keep CMYK recipe" : "Lab → CMYK", options: ["Lab → CMYK","Keep CMYK recipe"], row: 12) { [weak self] value in self?.session.options.recipe = value.hasPrefix("Keep"); if self?.session.options.recipe == true { self?.session.options.intent = RenderingIntent.absolute.rawValue }; self?.evaluate() }
        menu("Difference formula", value: DifferenceMethod(rawValue: session.options.method)?.label ?? "CIEDE2000", options: DifferenceMethod.allCases.map(\.label), row: 15) { [weak self] value in
            self?.session.options.method = DifferenceMethod.allCases.first { $0.label == value }!.rawValue; self?.evaluate()
        }
        menu("Results", value: filter, options: ["All patches","Needs attention","Within tolerance"], row: Rows.results) { [weak self] in self?.filter = $0; self?.pageNumber = 0; self?.reload() }
        menu("Order", value: sort, options: ["Source order","Largest difference"], row: Rows.order) { [weak self] in self?.sort = $0; self?.sortColumn = -1; self?.pageNumber = 0; self?.reload() }
    }
    private func button(_ b: SwissButton, x: CGFloat, row: CGFloat) {
        b.frame = NSRect(x:x,y:SettingsSheet.buttonTop(baseline:baseline(row)),width:b.intrinsicContentSize.width,height:SwissButton.height)
    }
    private func layoutRail() {
        rebuildMenus()
        for menu in menus {
            menu.layoutSubtreeIfNeeded()
            menu.frame.size = NSSize(width: menu.superview === settingsBody ? railWidth : rightWidth, height: menu.fittingSize.height)
        }
        let x = settingsBody.inset
        confirm.title = session.options.confirmD50 ? "D50 / 2° Confirmed" : "Confirm D50 / 2°"
        button(confirm,x:x,row:25)
        button(importReference,x:x,row:28); button(importMeasured,x:x,row:30)
        tolerance.frame = NSRect(x:x,y:baseline(19)-14,width:railWidth,height:22)
        inkLimit.frame = NSRect(x:x,y:baseline(22)-14,width:railWidth,height:22)
        for (b,row) in [(resetConfig,33),(saveConfig,36),(exportConfig,38),(loadConfig,40)] { button(b,x:x,row:CGFloat(row)) }
        for (i,b) in configButtons.enumerated() {
            b.frame = NSRect(x:x,y:SettingsSheet.buttonTop(baseline:baseline(45 + CGFloat(i)*2)),width:railWidth,height:SwissButton.height)
        }
        for action in [confirm,importReference,importMeasured,resetConfig,saveConfig,exportConfig,loadConfig] {
            action.frame.size.width = railWidth
        }
        settingsBody.needsDisplay = true
    }
    override func layout() {
        super.layout(); pageNumber = min(pageNumber, max(0, (visible.count-1)/pageSize)); layoutRail()
        button(load,x:cx,row:8); button(save,x:cx,row:10)
        button(monitorSetup,x:0,row:12)
        notes.frame = NSRect(x:cx,y:baseline(6)-14,width:rightWidth,height:22)
        button(export,x:0,row:89); export.isEnabled = !busy && !results.isEmpty
        pagination.frame = NSRect(x:0,y:paginationRow*u,width:bounds.width,height:2*u)
        pagination.update(total:visible.count,page:pageNumber,limit:pageLimit)
        for (i,b) in headerButtons.enumerated() {
            b.frame = NSRect(x:columns[i]*bounds.width,y:Rows.table*u,width:((i+1<columns.count ? columns[i+1] : 1)-columns[i])*bounds.width,height:u)
            b.setAccessibilityLabel("Sort by " + columnLabels[i] + (sortColumn == i ? (sortAscending ? ", ascending" : ", descending") : ""))
        }
        layoutPatchButtons()
        for (i,chart) in charts.enumerated() {
            let right = i % 2 == 1
            let row = i < 2 ? Rows.plots : i < 4 ? Rows.series : Rows.densityPlot
            chart.frame = NSRect(x:right ? cx : 0,y:row*u,width:right ? rightWidth : leftWidth,height:(i >= 2 && i < 4 ? 10 : 12)*u)
        }
        refreshCharts()
    }
    private func layoutPatchButtons() {
        let indices = Array(visible.dropFirst(pageNumber*pageSize).prefix(pageSize))
        let top = baseline(Rows.table)+11
        let viewport = enclosingScrollView?.documentVisibleRect ?? visibleRect
        let rows = Array(ProofRegister.viewportRows(count:indices.count,top:top,rowHeight:u,visible:viewport))
        while patchButtons.count < rows.count {
            let b = ProofPatchButton(); b.target=self; b.action=#selector(patchTapped(_:)); addSubview(b); patchButtons.append(b)
        }
        for (slot,button) in patchButtons.enumerated() {
            button.isHidden = slot >= rows.count
            guard slot < rows.count else { continue }
            let row = rows[slot], i = indices[row], r = results[i]
            button.tag = i
            button.frame = NSRect(x:0,y:top+CGFloat(row)*u,width:bounds.width,height:u)
            button.setAccessibilityLabel("Inspect \(r.reference.name), ID \(r.reference.id), Delta E \(number(r.difference)), \(r.status(session.options).rawValue)")
        }
    }
    private func refreshCharts() {
        for chart in charts { chart.results=results; chart.options=session.options; chart.selected=selected; chart.needsDisplay=true }
        chartDetail?.refresh(session: session, results: results, selected: selected)
    }
    @objc private func monitorSetupTapped() {
        let content = MonitorSetupView()
        let modal = SwissFocusModal(content:content,size:NSSize(width:1200,height:780))
        content.onClose = { [weak modal] in modal?.dismissOverlay() }
        modal.present(over:self)
    }
    private func expandChart(_ kind: ProofChartKind) {
        let detail = ProofChartDetail(kind:kind, simulation:simulation, session:session, results:results, selected:selected)
        let modal = SwissFocusModal(content:detail, size:NSSize(width:1200,height:780))
        detail.onClose = { [weak modal] in modal?.dismissOverlay() }
        detail.onSelect = { [weak self] in self?.selectPatch($0, reveal:false) }
        detail.onOptions = { [weak self] options in
            guard let self else { return }
            if options.profile != self.session.options.profile { self.session.embeddedProfile = nil }; self.session.options=options; self.tolerance.stringValue=String(options.tolerance); self.inkLimit.stringValue=String(options.inkLimit); self.evaluate()
        }
        detail.onSimulation = { [weak self] in self?.charts.last?.needsDisplay=true }
        chartDetail=detail; chartModal=modal; modal.present(over:self)
    }
    private func evaluate() {
        hovered = nil
        generation += 1; let token = generation
        session.notes = notes.stringValue
        var snapshot = session
        // Validate before slicing so duplicate IDs across different chunks cannot escape validation.
        if (try? snapshot.validate()) == nil {
            results = snapshot.reference.patches.map { ProofResult(reference: $0, issue: "Invalid proof data or settings") }
            busy = false; needsDisplay = true; needsLayout = true
            refreshCharts(); settingsRail.update(results: results, options: session.options, selected: selected); onResize?()
            return
        }
        // Register an embedded profile once per run, rather than rehashing its bytes every 64 patches.
        if let data = snapshot.embeddedProfile {
            snapshot.options.profile = PressProfiles.registerProofProfile(data)
            snapshot.embeddedProfile = nil
        }
        busy = true; results = []; menuSignature = ""; needsDisplay = true; needsLayout = true
        // Chunk on the main queue: the shared profile cache is also used by the other pages.
        var output: [ProofResult] = []
        func batch(_ offset: Int) {
            guard self.generation == token else { return }
            var part = snapshot
            part.reference.patches = Array(snapshot.reference.patches.dropFirst(offset).prefix(64))
            output += ProofEngine.evaluate(part)
            if offset + 64 < snapshot.reference.patches.count {
                DispatchQueue.main.async { batch(offset + 64) }
            } else {
                self.results = output; self.busy = false; self.selected = min(self.selected,max(0,output.count-1))
                self.needsDisplay = true; self.needsLayout = true; self.refreshCharts(); self.settingsRail.update(results:output,options:self.session.options,selected:self.selected); self.onResize?()
            }
        }
        DispatchQueue.main.async { batch(0) }
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let t = Double(tolerance.stringValue), t.isFinite, (0.01...100).contains(t), let ink = Double(inkLimit.stringValue), ink.isFinite, (1...400).contains(ink) else {
            message = "Tolerance must be 0.01–100; ink review limit 1–400%."
            tolerance.stringValue = String(session.options.tolerance); inkLimit.stringValue = String(session.options.inkLimit); needsDisplay = true; return
        }
        session.options.tolerance = t; session.options.inkLimit = ink; session.notes = notes.stringValue
        message = ""; evaluate()
    }
    @objc private func confirmTapped() { session.options.confirmD50.toggle(); evaluate() }
    @objc private func referenceTapped() { importFile(measurement:false) }
    @objc private func measuredTapped() { importFile(measurement:true) }
    private func importFile(measurement: Bool) {
        let panel = NSOpenPanel(); panel.title = measurement ? "Import Measured Lab Samples" : "Import Reference Patches"
        panel.message = "CGATS or CSV: SAMPLE_ID, LAB_L, LAB_A, LAB_B. Measurements match by exact patch ID."
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard size <= 12_000_000 else { throw ProofError.invalid("Maximum file size is 12 MB.") }
            let data = try Data(contentsOf:url), dataset = try ProofImport.read(data,name:url.lastPathComponent)
            if measurement { session.measurement = dataset; session.options.mode = "Measurement" }
            else { session.reference = dataset; selected = 0 }
            session.options.confirmD50 = false; pageNumber = 0; message = "Imported \(dataset.patches.count) patches."
            evaluate()
        } catch { message = error.localizedDescription; needsDisplay = true }
    }
    private func refreshConfigurations() {
        do { configurations = try ProofConfigurationStore.list(root: library.store.root) }
        catch { configurations = []; message = error.localizedDescription }
        configButtons.forEach { $0.removeFromSuperview() }; configButtons = []
        for (i,config) in configurations.enumerated() {
            let b = SwissButton(config.name, .secondary, target:self, action:#selector(configurationTapped(_:)))
            b.tag = i; b.toolTip = config.name + ".colcal · " + config.created.formatted()
            let menu = NSMenu()
            let remove = NSMenuItem(title:"Move Configuration To Trash…",action:#selector(removeConfiguration(_:)),keyEquivalent:"")
            remove.tag=i; remove.target=self; menu.addItem(remove); b.menu=menu
            settingsBody.addSubview(b); configButtons.append(b)
        }
        settingsBody.configurationCount = configurations.count; settingsRail.needsLayout = true
    }
    private func applyConfiguration(_ config: ProofConfiguration) {
        let v = config.densitySimulation ?? [1.61,1.67,1.30,88.89,2.5]
        simulation.current=v[0]; simulation.optimum=v[1]; simulation.minimum=v[2]; simulation.curvature=v[3]; simulation.tolerance=v[4]
        session = config.session; tolerance.stringValue = String(session.options.tolerance)
        inkLimit.stringValue = String(session.options.inkLimit); notes.stringValue = session.notes
        selected = 0; pageNumber = 0; message = "Loaded " + config.name; evaluate(); onResize?()
    }
    @objc private func removeConfiguration(_ sender: NSMenuItem) {
        guard configurations.indices.contains(sender.tag) else { return }
        let config = configurations[sender.tag], root = library.store.root
        let modal = SwissFocusModal(title:"Remove Configuration",message:"Move “" + config.name + "” to Trash? The currently loaded proof stays open.")
        modal.button("Move To Trash",primary:true) { [weak self,weak modal] in
            do {
                let dir=root.appendingPathComponent(ProofConfigurationStore.folder)
                for file in try FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil) where file.pathExtension == "colcal" {
                    guard let stored = try? ProofConfiguration.decode(Data(contentsOf:file)), stored.id == config.id else { continue }
                    try FileManager.default.trashItem(at:file,resultingItemURL:nil)
                }
                self?.refreshConfigurations(); self?.needsLayout=true; modal?.dismissOverlay()
            } catch { NSApp.presentError(error) }
        }
        modal.button("Cancel") { [weak modal] in modal?.dismissOverlay() }; modal.present(over:self)
    }
    @objc private func configurationTapped(_ sender: NSButton) {
        guard configurations.indices.contains(sender.tag) else { return }; applyConfiguration(configurations[sender.tag])
    }
    @objc private func resetConfigTapped() {
        let modal = SwissFocusModal(title:"Reset Proof Settings",message:"Restore the default FOGRA51 reference and proof settings, and clear imported measurements and notes. Saved configurations are retained.")
        modal.button("Reset",primary:true) { [weak self, weak modal] in
            guard let self, let reference = Self.reference("FOGRA51") else { return }
            self.applyConfiguration(ProofConfiguration(name:"Default proof settings",session:ProofSession(reference:reference,options:ProofOptions())))
            modal?.dismissOverlay()
        }
        modal.button("Cancel") { [weak modal] in modal?.dismissOverlay() }; modal.present(over:self)
    }
    private func captureConfiguration(name: String) throws -> ProofConfiguration {
        window?.makeFirstResponder(self); session.notes = notes.stringValue
        var copy = session
        if copy.embeddedProfile == nil {
            copy.embeddedProfile = PressProfiles.all.first { $0.name == copy.options.profile }.flatMap { FileManager.default.contents(atPath:$0.path) }
            if copy.options.mode == "Prediction", copy.embeddedProfile == nil { throw ProofError.invalid("The selected output profile could not be embedded. Choose an available CMYK profile before saving.") }
        }
        let config = ProofConfiguration(name:name.trimmingCharacters(in:.whitespacesAndNewlines),session:copy,densitySimulation:[simulation.current,simulation.optimum,simulation.minimum,simulation.curvature,simulation.tolerance])
        try config.validate(); return config
    }
    @objc private func saveConfigTapped() {
        let modal = SwissFocusModal(title:"Save Proof Configuration",message:"Keep this reference, measurements, settings and output profile with the active catalogue.")
        let field = modal.field("Configuration name",value:"")
        modal.button("Save",primary:true) { [weak self, weak modal] in
            guard let self else { return }
            do {
                let config = try self.captureConfiguration(name:field.stringValue)
                try ProofConfigurationStore.save(config,root:self.library.store.root)
                self.refreshConfigurations(); self.needsLayout=true; modal?.dismissOverlay()
            } catch { NSApp.presentError(error) }
        }
        modal.button("Cancel") { [weak modal] in modal?.dismissOverlay() }; modal.present(over:self)
    }
    @objc private func exportConfigTapped() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Proof Configuration.colcal"
        let folder = library.store.root.appendingPathComponent(ProofConfigurationStore.folder,isDirectory:true)
        do { try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true) }
        catch { NSApp.presentError(error); return }
        panel.directoryURL = folder
        panel.allowedContentTypes = [UTType(exportedAs:"com.mmffdev.colour.calibration",conformingTo:.json)]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let config = try captureConfiguration(name:url.deletingPathExtension().lastPathComponent)
            let data = try JSONEncoder().encode(config); _ = try ProofConfiguration.decode(data)
            try data.write(to:url,options:.atomic)
            if url.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL {
                try ProofConfigurationStore.save(config,root:library.store.root)
            }
            refreshConfigurations(); needsLayout=true
        } catch { NSApp.presentError(error) }
    }
    @objc private func loadConfigTapped() {
        let panel = NSOpenPanel(); panel.title="Load Proof Configuration"; panel.allowsMultipleSelection=false
        panel.allowedContentTypes = [UTType(exportedAs:"com.mmffdev.colour.calibration",conformingTo:.json)]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max) <= 40_000_000 else { throw ProofError.invalid("Configuration exceeds 40 MB.") }
            let config = try ProofConfiguration.decode(Data(contentsOf:url))
            try ProofConfigurationStore.save(config,root:library.store.root)
            refreshConfigurations(); applyConfiguration(config)
        } catch { NSApp.presentError(error) }
    }
    @objc private func saveTapped() {
        window?.makeFirstResponder(self); session.notes = notes.stringValue
        do { try session.validate(); try write(try JSONEncoder().encode(session), name:"Proof Session.colproof") }
        catch { message = error.localizedDescription; needsDisplay = true }
    }
    @objc private func loadTapped() {
        let panel = NSOpenPanel(); panel.title = "Open Proof Session"; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) <= 12_000_000 else { throw ProofError.invalid("Session exceeds 12 MB.") }
            let loaded = try JSONDecoder().decode(ProofSession.self,from:Data(contentsOf:url)); try loaded.validate()
            session = loaded; tolerance.stringValue = String(loaded.options.tolerance); inkLimit.stringValue = String(loaded.options.inkLimit); notes.stringValue = loaded.notes
            selected = 0; pageNumber = 0; message = "Session opened; results recalculated with installed profiles."; evaluate()
        } catch { message = error.localizedDescription; needsDisplay = true }
    }
    @objc private func exportTapped() {
        window?.makeFirstResponder(self); session.notes = notes.stringValue
        do { try write(Data(ProofEngine.csv(results,session:session).utf8),name:"Proof Report.csv") }
        catch { message = error.localizedDescription; needsDisplay = true }
    }
    private func write(_ data: Data, name: String) throws {
        let panel = NSSavePanel(); panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        try data.write(to:url,options:.atomic); message = "Saved \(url.lastPathComponent)"; needsDisplay = true
    }
    private func revealRegisterRows() {
        onResize?()
        DispatchQueue.main.async { [weak self] in
            guard let self, let scroll = self.enclosingScrollView else { return }
            scroll.superview?.layoutSubtreeIfNeeded()
            let y = min(self.RowsTableTop, max(0,self.bounds.height-scroll.contentView.bounds.height))
            scroll.contentView.scroll(to:NSPoint(x:0,y:y)); scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
    private var RowsTableTop: CGFloat { Rows.table*u }
    private func text(_ s: String, x: CGFloat, row: CGFloat, style: Design.Text = .body, width: CGFloat? = nil, colour: NSColor = Design.ink) {
        Design.attributed(s,style,colour:colour).draw(x:x,baseline:baseline(row),width:width ?? bounds.width-x)
    }
    private func number(_ n: Double?) -> String { n.map { String(format:"%.2f",$0) } ?? "—" }
    override func draw(_ dirtyRect: NSRect) {
        fill(bounds,Design.card); hits=[]; plotHits=[]; colourHits=[]
        SettingsSheet.title("Proofing.")
        SettingsSheet.introduction("Reference. Output. Evidence.","D50 / 2° · Predictions and measurements kept distinct",x:cx,width:bounds.width)
        SettingsSheet.section(1,"Set the proof",guide:baseline(2),contentX:cx,width:bounds.width)
        SettingsSheet.paragraph(session.reference.source,x:0,firstBaseline:baseline(7),width:leftWidth,height:2*u)
        SettingsSheet.paragraph(session.reference.conditions,x:0,firstBaseline:baseline(10),width:leftWidth,height:3*u,colour:Design.quiet)
        text("Job notes",x:cx,row:5,style:.caption); hairline(x:cx,y:baseline(6)+5,width:rightWidth,Design.rule)
        SettingsSheet.paragraph("Reference and comparison controls stay in Proof Settings. Sessions retain the source data, conditions and options.",x:cx,firstBaseline:baseline(12),width:rightWidth,height:2*u,colour:Design.quiet)
        text(message,x:0,row:14,style:.caption,colour:Design.quiet)
        SettingsSheet.section(2,"Proof summary",guide:baseline(Rows.summary),contentX:cx,width:bounds.width)
        let summary = ProofEngine.summary(results,options:session.options)
        text(busy ? "Calculating…" : session.options.mode + " · " + (summary.completePass ? "Within user tolerance" : "Review required"),x:cx,row:18,style:.heading)
        text("\(summary.passed) within · \(summary.evaluated) evaluated · \(summary.count) reference patches",x:cx,row:20)
        text("Mean  \(number(summary.mean))     P95  \(number(summary.p95))     Max  \(number(summary.maximum))",x:cx,row:22,style:.bodyStrong)
        let issue = ProofEngine.conditionsIssue(session) ?? (session.options.mode == "Measurement" ? "Measurements: \(session.measurement?.conditions ?? "None imported"). Missing mode or backing metadata remains unverified." : "\(session.options.profile) · \(session.options.intent) · BPC off")
        SettingsSheet.paragraph(issue,x:0,firstBaseline:baseline(20),width:leftWidth,height:4*u,colour:Design.quiet)
        if session.options.mode == "Measurement", let m = session.measurement {
            let refs = Set(session.reference.patches.map(\.id)); let extra = m.patches.filter { !refs.contains($0.id) }.count
            text("\(extra) unmatched measurement IDs · Missing patches never count as a pass",x:cx,row:24,style:.caption)
        } else { text("Screen swatches are previews. A profile prediction does not verify a printed sheet.",x:cx,row:24,style:.caption) }
        SettingsSheet.section(3,"Density simulation",guide:baseline(Rows.density),contentX:cx,width:bounds.width)
        SettingsSheet.paragraph("Simulated operating range",x:cx,firstBaseline:baseline(56),width:rightWidth,height:u)
        SettingsSheet.paragraph("Explore how density, the best achievable ΔE and curve shape affect the operating range. Expand the chart to edit the model and see the limits update.",x:cx,firstBaseline:baseline(58),width:rightWidth,height:4*u)
        SettingsSheet.paragraph("Illustrative quadratic model only. It is independent of the proof results and is not a press adjustment recommendation. Real optimisation requires a measured ink-density series.",x:cx,firstBaseline:baseline(63),width:rightWidth,height:4*u,colour:Design.quiet)
        SettingsSheet.section(4,"Inspect a patch",guide:baseline(Rows.inspector),contentX:cx,width:bounds.width)
        if results.indices.contains(selected) {
            let r = results[selected], a = r.reference.lab
            text(r.reference.name + " · ID " + r.reference.id,x:cx,row:72,style:.heading)
            let sw = (leftWidth-Design.App.gutter)/2, y = 75*u
            for (index,pair) in [("Reference",Optional(a)),(session.options.mode == "Measurement" ? "Measured" : "Predicted",r.sample)].enumerated() {
                let box = NSRect(x:CGFloat(index)*(sw+16),y:y,width:sw,height:2*u)
                fill(box,pair.1?.xyz.display ?? Design.mist); Design.ink.setStroke(); NSBezierPath(rect:box).stroke()
                if let lab = pair.1 { colourHits.append((box,lab)) }
                text(pair.0,x:box.minX,row:78,style:.caption,width:sw)
            }
            text("L* / a* / b* / C* / h°",x:cx,row:75,style:.caption)
            func values(_ l:LabD50) -> String { [l.l,l.a,l.b,hypot(l.a,l.b),(atan2(l.b,l.a)*180 / .pi + 360).truncatingRemainder(dividingBy:360)].map { number($0) }.joined(separator:" / ") }
            text(values(a),x:cx,row:76)
            text(r.sample.map(values) ?? "No comparable sample",x:cx,row:77)
            if let b = r.sample {
                let dl=b.l-a.l, da=b.a-a.a, db=b.b-a.b
                text("ΔL \(number(dl)) · Δa \(number(da)) · Δb \(number(db)) · ΔE \(number(r.difference))",x:cx,row:78,style:.bodyStrong)
                func direction(_ value:Double,_ positive:String,_ negative:String,_ same:String)->String { abs(value)<0.005 ? same : (value>0 ? positive : negative) }
                text([direction(dl,"Lighter","Darker","Same lightness"),direction(da,"Redder","Greener","Same a*"),direction(db,"Yellower","Bluer","Same b*")].joined(separator:" · "),x:cx,row:79,style:.caption)
            } else { text(r.issue ?? "Not evaluated",x:cx,row:79,style:.caption) }
        }
        SettingsSheet.section(5,"Patch register",guide:baseline(Rows.register),contentX:cx,width:bounds.width)
        text("Select a row or chart point to inspect a patch.",x:0,row:87,style:.caption,width:max(120,cx-32))
        let cols = columns
        for (i,label) in columnLabels.enumerated() {
            text(label + (sortColumn == i ? (sortAscending ? " ↑" : " ↓") : " ↕"),x:cols[i]*bounds.width+4,row:Rows.table,style:.caption,width:((i+1<cols.count ? cols[i+1] : 1)-cols[i])*bounds.width-8)
        }
        for (n,i) in visible.dropFirst(pageNumber*pageSize).prefix(pageSize).enumerated() {
            let r=results[i], a=r.reference.lab, y=baseline(Rows.table)+11+CGFloat(n)*u
            let rect=NSRect(x:0,y:y,width:bounds.width,height:u)
            guard rect.intersects(dirtyRect) else { continue }
            if i==selected { fill(rect,Design.mist); fill(NSRect(x:0,y:y,width:3,height:u),Design.houseYellow) }
            let vals=[r.reference.id,r.reference.name,number(r.difference),number(r.sample.map{$0.l-a.l}),number(r.sample.map{$0.a-a.a}),number(r.sample.map{$0.b-a.b}),r.difference == nil ? "Not evaluated" : (r.status(session.options) == .withinTolerance ? "Within" : "Review")]
            for j in cols.indices { Design.attributed(vals[j],.body).draw(x:cols[j]*bounds.width+4,baseline:y+Design.App.textBaseline,width:(j+1<cols.count ? cols[j+1]-cols[j] : 1-cols[j])*bounds.width-8) }
            hairline(x:0,y:rect.maxY-1,width:bounds.width,Design.rule); hits.append((rect,i))
        }
        SettingsSheet.paragraph("Fogra reference subsets are supplied unmodified with attribution; inclusion is not certification. Reports record source conditions and user tolerances. Density simulation is excluded from proof results.",x:0,firstBaseline:baseline(paginationRow+3),width:bounds.width,height:2*u,colour:Design.quiet)
    }
    private func selectPatch(_ index:Int, reveal:Bool) {
        guard results.indices.contains(index) else { return }
        selected=index; needsDisplay=true; refreshCharts(); settingsRail.select(index, reveal:true)
        if reveal { scrollToVisible(NSRect(x:0,y:baseline(Rows.inspector),width:bounds.width,height:10*u)) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking=NSTrackingArea(rect:.zero,options:[.mouseMoved,.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(tracking!)
    }
    override func mouseMoved(with event:NSEvent) {
        let p=convert(event.locationInWindow,from:nil)
        let row=hits.first{$0.0.contains(p)}?.1
        if row != hovered { hovered=row; needsDisplay=true }
        let actionable = row != nil || plotHits.contains{hypot($0.0.x-p.x,$0.0.y-p.y)<10}
        (actionable ? NSCursor.pointingHand : NSCursor.arrow).set()
    }
    override func mouseExited(with event:NSEvent) { hovered=nil; needsDisplay=true;NSCursor.arrow.set() }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    @objc private func sortTapped(_ sender: NSButton) {
        if sortColumn == sender.tag { sortAscending.toggle() } else { sortColumn = sender.tag; sortAscending = sender.tag < 2 || sender.tag == 6 }
        sort = columnLabels[sortColumn] + (sortAscending ? " · Ascending" : " · Descending")
        pageNumber = 0; hovered = nil; needsLayout = true; needsDisplay = true; onResize?()
    }
    @objc private func patchTapped(_ sender:NSButton) {selectPatch(sender.tag,reveal:true)}
    override func mouseDown(with event:NSEvent) {
        let p=convert(event.locationInWindow,from:nil)
        if let hit=hits.first(where:{$0.0.contains(p)}) {selectPatch(hit.1, reveal:true);return}
        if let hit=plotHits.min(by:{hypot($0.0.x-p.x,$0.0.y-p.y)<hypot($1.0.x-p.x,$1.0.y-p.y)}),hypot(hit.0.x-p.x,hit.0.y-p.y)<10 {selectPatch(hit.1, reveal:false);return}
        super.mouseDown(with:event)
    }
}

private final class ProofPatchButton:NSButton {
    private var hovered=false
    private var tracking:NSTrackingArea?
    override init(frame:NSRect) {super.init(frame:frame);title="";isBordered=false;setButtonType(.momentaryChange)}
    required init?(coder:NSCoder) {fatalError()}
    override func draw(_ dirtyRect:NSRect) {
        if let window, bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from:nil)), !isHidden {
            Design.quiet.withAlphaComponent(0.08).setFill();bounds.fill()
        }
        if window?.firstResponder === self {Design.ink.setStroke();NSBezierPath(rect:bounds.insetBy(dx:2,dy:2)).stroke()}
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas();if let tracking {removeTrackingArea(tracking)}
        tracking=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil);addTrackingArea(tracking!)
    }
    override func mouseEntered(with event:NSEvent) {hovered=true;needsDisplay=true;NSCursor.pointingHand.set()}
    override func mouseExited(with event:NSEvent) {hovered=false;needsDisplay=true;NSCursor.arrow.set()}
}

/// One table-width footer; pagination is applied only after the complete register is sorted.
private final class ProofPaginationBar: NSView, Overlay {
    override var isFlipped: Bool { true }
    var onPage: ((Int)->Void)?
    var onLimit: ((Int)->Void)?
    private var total = 0, page = 0, limit = 25
    private var controls: [ProofPageControl] = []
    private var pagePanel: SwissDropdown.MenuPanel?
    var overlayWindows: [NSWindow] { pagePanel.map { [$0] } ?? [] }
    func dismissOverlay() {
        if let pagePanel { pagePanel.parent?.removeChildWindow(pagePanel); pagePanel.orderOut(nil) }
        pagePanel = nil; Overlays.closed(self)
    }
    func update(total: Int, page: Int, limit: Int) {
        self.total = total; self.page = page; self.limit = limit
        controls.forEach { $0.removeFromSuperview() }; controls = []
        let count = limit == 0 ? 1 : max(1,(total + limit - 1)/limit)
        func control(_ title: String, _ label: String, _ tag: Int, enabled: Bool = true) {
            let b = ProofPageControl(); b.title = title; b.tag = tag; b.target = self
            b.action = #selector(tapped(_:)); b.isEnabled = enabled; b.selectedPage = tag == page && tag >= 0
            b.setAccessibilityLabel(label); b.toolTip = label; addSubview(b); controls.append(b)
        }
        control("Rows: \(limit == 0 ? "All" : String(limit)) ▾","Rows per page",-1)
        control("⇤","First page",0,enabled:page > 0)
        control("←","Previous page",max(0,page-1),enabled:page > 0)
        let shown = Set([0,count-1,page-1,page,page+1].filter { $0 >= 0 && $0 < count }).sorted()
        let pages = count <= 7 ? Array(0..<count) : shown
        var last = -1
        for p in pages {
            if last >= 0 && p-last > 1 { control("…","More pages",-2,enabled:false) }
            control(String(p+1),"Page \(p+1) of \(count)",p); last = p
        }
        control("→","Next page",min(count-1,page+1),enabled:page<count-1)
        control("⇥","Last page",count-1,enabled:page<count-1)
        // Selection belongs to numbered pages only, never navigation arrows.
        for b in controls where Int(b.title) == nil { b.selectedPage = false }
        needsLayout = true; needsDisplay = true
    }
    override func layout() {
        super.layout()
        controls.first?.frame = NSRect(x:180,y:12,width:104,height:32)
        let width: CGFloat = 32, gap: CGFloat = 4
        var x = bounds.width - CGFloat(max(0,controls.count-1))*(width+gap)+gap
        for b in controls.dropFirst() { b.frame = NSRect(x:x,y:12,width:width,height:32); x += width+gap }
    }
    override func draw(_ dirtyRect: NSRect) {
        fill(bounds,Design.card)
        fill(NSRect(x:0,y:0,width:bounds.width,height:1),Design.rule)
        fill(NSRect(x:0,y:bounds.height-1,width:bounds.width,height:1),Design.rule)
        let first = total == 0 ? 0 : (limit == 0 ? 1 : page*limit+1)
        let last = limit == 0 ? total : min(total,(page+1)*limit)
        Design.attributed("\(first)–\(last) of \(total) patches",.body,colour:Design.quiet).draw(x:4,baseline:33,width:172)
    }
    @objc private func tapped(_ sender: NSButton) {
        guard sender.tag == -1 else { onPage?(sender.tag); return }
        guard let window else { return }
        dismissOverlay()
        let values = ["All","10","25","50","100"]
        let panel = SwissDropdown.MenuPanel(items:values,chosen:limit == 0 ? "All" : String(limit),width:104) { [weak self] i in
            self?.dismissOverlay(); self?.onLimit?(Int(values[i]) ?? 0)
        }
        let rect = window.convertToScreen(convert(sender.frame,to:nil))
        panel.place(below:NSPoint(x:rect.minX,y:rect.minY-4))
        window.addChildWindow(panel,ordered:.above); pagePanel = panel; Overlays.opened(self)
    }
}
private final class ProofPageControl: NSButton {
    var selectedPage = false
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame:frame); isBordered = false; focusRingType = .none
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let hover = window.map { bounds.contains(convert($0.mouseLocationOutsideOfEventStream,from:nil)) } ?? false
        if selectedPage { fill(bounds,Design.ink) }
        else if isEnabled && hover { fill(bounds,Design.mist) }
        let text = Design.attributed(title,.body,colour:selectedPage ? Design.card : (isEnabled ? Design.ink : Design.soft))
        text.draw(x:(bounds.width-text.size().width)/2,baseline:21,width:bounds.width)
        if window?.firstResponder === self { Design.rule.setStroke(); NSBezierPath(rect:bounds.insetBy(dx:1,dy:1)).stroke() }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect:.zero,options:[.inVisibleRect,.mouseEnteredAndExited,.activeInActiveApp],owner:self))
    }
    override func mouseEntered(with event: NSEvent) { needsDisplay = true }
    override func mouseExited(with event: NSEvent) { needsDisplay = true }
    override func resetCursorRects() { if isEnabled { addCursorRect(bounds,cursor:.pointingHand) } }
}

final class ProofNavigationRail: StudioRail, NSTextFieldDelegate {
    var onSelect: ((Int)->Void)?
    private let patches = ProofRailPatches()
    private let patchesTab = SectionAnchorButton(), setupTab = SectionAnchorButton()
    private let search = NSTextField(string: "")
    private let back = ProofPageControl(), forward = ProofPageControl()
    private let status = SwissDropdown("Show",value:"All",options:["All","Within","Review","Missing"],allowsOwn:false,width:140)
    private var showingPatches = true
    private var results: [ProofResult] = [], options = ProofOptions(), selected = 0
    private var scope = "All"
    private var setupOffset: CGFloat = 0, patchOffset: CGFloat = 0
    init(settings: ProofSettingsBody) {
        super.init(body:settings); heading = "Proofing"; labels = ("",""); arrow = .none
        for (tab,title,tag) in [(patchesTab,"Patches",0),(setupTab,"Setup",1)] {
            tab.title = title; tab.tag = tag; tab.isBordered = false; tab.target = self; tab.action = #selector(tabTapped(_:)); addSubview(tab)
        }
        search.placeholderAttributedString = Design.attributed("Search patches…",.body,colour:Design.quiet)
        search.font = Design.Text.body.font(); search.textColor = Design.ink; search.isBordered = false; search.drawsBackground = false
        search.delegate = self; search.setAccessibilityLabel("Search proof patches"); addSubview(search)
        for (button,title,tag,label) in [(back,"←",-1,"Previous patch"),(forward,"→",1,"Next patch")] {
            button.title = title; button.tag = tag; button.target = self; button.action = #selector(step(_:)); button.setAccessibilityLabel(label); addSubview(button)
        }
        addSubview(status); status.onChange = { [weak self] value in self?.scope = value; self?.rebuild() }
        patches.onSelect = { [weak self] index in self?.onSelect?(index) }
        scroll.documentView = patches; updateTabs()
    }
    required init?(coder:NSCoder) { fatalError() }
    func update(results:[ProofResult],options:ProofOptions,selected:Int) {
        self.results = results; self.options = options; self.selected = selected; rebuild()
    }
    func select(_ index:Int,reveal:Bool) {
        selected = index
        if !patches.indices.contains(index) {
            scope = "All"; status.displayValue("All"); search.stringValue = ""; rebuild()
        }
        patches.selected = index; patches.needsDisplay = true; updateSteps()
        if reveal, showingPatches, let row = patches.indices.firstIndex(of:index) {
            layoutSubtreeIfNeeded()
            patches.scrollToVisible(NSRect(x:0,y:CGFloat(row)*56,width:patches.bounds.width,height:56))
        }
    }
    private func rebuild() {
        let query = search.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        patches.indices = results.indices.filter { i in
            let r = results[i], state = r.status(options)
            let match = query.isEmpty || r.reference.id.localizedCaseInsensitiveContains(query) || r.reference.name.localizedCaseInsensitiveContains(query)
            return match && (scope == "All" || (scope == "Within" && state == .withinTolerance) || (scope == "Missing" && r.sample == nil) || (scope == "Review" && state != .withinTolerance))
        }
        patches.results = results; patches.options = options; patches.selected = selected; patches.rebuildButtons()
        needsLayout = true; needsDisplay = true; updateSteps()
    }
    private func updateSteps() {
        let position = patches.indices.firstIndex(of:selected)
        back.isEnabled = position.map { $0 > 0 } ?? false
        forward.isEnabled = position.map { $0+1 < patches.indices.count } ?? !patches.indices.isEmpty
    }
    func controlTextDidChange(_ obj:Notification) { rebuild(); scroll.contentView.scroll(to:.zero) }
    @objc private func step(_ sender:NSButton) {
        let current = patches.indices.firstIndex(of:selected) ?? -1
        let next = current+sender.tag
        guard patches.indices.indices.contains(next) else { return }; onSelect?(patches.indices[next])
    }
    @objc private func tabTapped(_ sender:NSButton) {
        if showingPatches { patchOffset = scroll.contentView.bounds.minY } else { setupOffset = scroll.contentView.bounds.minY }
        showingPatches = sender.tag == 0; scroll.documentView = showingPatches ? patches : body
        updateTabs(); needsLayout = true; layoutSubtreeIfNeeded()
        scroll.contentView.scroll(to:NSPoint(x:0,y:showingPatches ? patchOffset : setupOffset)); scroll.reflectScrolledClipView(scroll.contentView)
    }
    private func updateTabs() {
        needsDisplay = true
        for (tab,active) in [(patchesTab,showingPatches),(setupTab,!showingPatches)] {
            tab.active = active; tab.attributedTitle = Design.attributed(tab.title,active ? .bodyStrong : .body,colour:active ? Design.ink : Design.quiet); tab.needsDisplay = true
        }
        for view in [search,status,back,forward] { view.isHidden = !showingPatches }
    }
    override func layout() {
        contentOffset = showingPatches ? 140 : 0
        super.layout()
        patchesTab.frame = NSRect(x:inset,y:AreaHeader.labelBaseline-17,width:84,height:28)
        setupTab.frame = NSRect(x:inset+84,y:AreaHeader.labelBaseline-17,width:72,height:28)
        let width = max(100,bounds.width-inset-insetRight)
        search.frame = NSRect(x:inset,y:AreaHeader.height,width:width,height:24)
        status.frame = NSRect(x:inset,y:AreaHeader.height+36,width:max(80,width-80),height:56)
        back.frame = NSRect(x:bounds.width-insetRight-72,y:AreaHeader.height+48,width:32,height:32)
        forward.frame = NSRect(x:bounds.width-insetRight-32,y:AreaHeader.height+48,width:32,height:32)
        if showingPatches {
            patches.inset = inset; patches.insetRight = max(0,insetRight-QuietScroller.lane)
            patches.frame = NSRect(x:0,y:0,width:scroll.contentSize.width,height:max(scroll.contentSize.height,patches.height))
            patches.needsLayout = true; patches.needsDisplay = true
        }
    }
    override func draw(_ dirtyRect:NSRect) {
        fill(bounds,Design.card)
        super.draw(dirtyRect)
        if showingPatches {
            let width = bounds.width-inset-insetRight
            hairline(x:inset,y:AreaHeader.height+27,width:width,Design.rule)
            Design.attributed("\(patches.indices.count) patches · Ref / Sample",.caption,colour:Design.quiet).draw(x:inset,baseline:AreaHeader.height+123,width:width)
        }
    }
}

private final class ProofRailPatches: StudioRail.RailBody {
    var results:[ProofResult] = [], indices:[Int] = [], options = ProofOptions(), selected = 0
    var onSelect:((Int)->Void)?
    private var buttons:[ProofPatchButton] = []
    private var scrollObserver: NSObjectProtocol?
    override var height:CGFloat { max(56,CGFloat(indices.count)*56) }
    deinit { if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) } }
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let clip = note.object as? NSClipView, clip === self.enclosingScrollView?.contentView else { return }
            self.rebuildButtons(); self.needsDisplay = true
        }
        enclosingScrollView?.contentView.postsBoundsChangedNotifications = true
    }
    func rebuildButtons() {
        // Reuse only the visible rows plus a small overscan, even for a 10,000-patch target.
        let visible = enclosingScrollView?.documentVisibleRect ?? bounds
        let rows = Array(ProofRegister.viewportRows(count:indices.count,top:0,rowHeight:56,visible:visible))
        while buttons.count < rows.count {
            let b = ProofPatchButton(); b.target = self; b.action = #selector(pick(_:)); addSubview(b); buttons.append(b)
        }
        for (slot,b) in buttons.enumerated() {
            b.isHidden = slot >= rows.count
            if slot < rows.count {
                let row = rows[slot]
                b.tag = indices[row]; let r = results[b.tag]
                b.frame = NSRect(x:inset,y:CGFloat(row)*56,width:max(0,bounds.width-inset-insetRight),height:56)
                b.setAccessibilityLabel("Select \(r.reference.name), ID \(r.reference.id), \(r.status(options).rawValue)")
                b.toolTip = "\(r.reference.name) · ID \(r.reference.id) · \(r.status(options).rawValue)"
            }
        }
    }
    override func layout() { super.layout(); rebuildButtons() }
    @objc private func pick(_ sender:NSButton) { onSelect?(sender.tag) }
    override func draw(_ dirtyRect:NSRect) {
        let width = bounds.width-inset-insetRight
        if indices.isEmpty { Design.attributed("No matching patches",.body,colour:Design.quiet).draw(x:inset,baseline:17,width:width); return }
        for row in indices.indices {
            let y = CGFloat(row)*56
            guard NSRect(x:0,y:y,width:bounds.width,height:56).intersects(dirtyRect) else { continue }
            let index = indices[row], r = results[index]
            if index == selected {
                fill(NSRect(x:inset,y:y,width:width,height:55),Design.mist)
                fill(NSRect(x:inset,y:y,width:3,height:55),Design.houseYellow)
            }
            Design.attributed(r.reference.name,.bodyStrong).draw(x:inset+8,baseline:y+17,width:max(0,width-78))
            let de = r.difference.map { String(format:"ΔE %.2f",$0) } ?? "ΔE —"
            let text = Design.attributed(de,.caption,colour:Design.quiet)
            text.draw(x:bounds.width-insetRight-text.size().width,baseline:y+17,width:74)
            for (i,lab) in [Optional(r.reference.lab),r.sample].enumerated() {
                let rect = NSRect(x:inset+8+CGFloat(i)*25,y:y+29,width:24,height:16)
                fill(rect,lab?.xyz.display ?? Design.mist); Design.rule.setStroke(); NSBezierPath(rect:rect).stroke()
            }
            let state = r.sample == nil ? "Missing" : r.status(options) == .withinTolerance ? "Within" : "Review"
            Design.attributed("\(r.reference.id) · \(state)",.caption,colour:Design.quiet).draw(x:inset+66,baseline:y+42,width:max(0,width-66))
            hairline(x:inset,y:y+55,width:width,Design.rule)
        }
    }
}
