import AppKit

/// Compact native controls shared by the analysis dock and expanded workspace.
final class AnalysisMenu: NSPopUpButton {
    var changed: ((Int) -> Void)?
    init(_ label: String, _ titles: [String]) {
        super.init(frame: .zero, pullsDown: false)
        font = Design.Text.body.font(); addItems(withTitles: titles)
        target = self; action = #selector(picked); setAccessibilityLabel(label); toolTip = label
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped:Bool{true}
    override func draw(_ dirtyRect:NSRect){
        DropdownSkin.draw(in:bounds,hover:isHighlighted)
        Design.attributed(titleOfSelectedItem ?? title,.body,colour:isEnabled ? Design.ink:Design.quiet).draw(x:8,baseline:bounds.midY+4,width:max(0,bounds.width-44))
    }
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
    @objc private func picked() { needsDisplay=true;changed?(indexOfSelectedItem) }
    func options(_ titles: [String], selected: Int = 0) {
        removeAllItems(); addItems(withTitles: titles); selectItem(at: max(0, min(selected, titles.count - 1)));needsDisplay=true
    }
}

/// Guard-band findings use the plotted model, not the separate print ΔE verdict.
private final class HistogramFindingRow: NSButton {
    var name="", colour=NSColor.clear, messages:[String]=[]
    var opened=false
    var changed:(()->Void)?
    var rowHeight:CGFloat {28 + (opened ? CGFloat(messages.count)*24 : 0)}
    override var isFlipped:Bool{true}
    override init(frame:NSRect){super.init(frame:frame);target=self;action=#selector(toggle);isBordered=false}
    required init?(coder:NSCoder){fatalError()}
    @objc private func toggle(){guard !messages.isEmpty else{return};opened.toggle();changed?()}
    override func resetCursorRects(){if !messages.isEmpty{addCursorRect(bounds,cursor:.pointingHand)}}
    override func draw(_ dirtyRect:NSRect){
        if isHighlighted {Design.mist.setFill();bounds.fill()}
        colour.setFill();NSRect(x:0,y:6,width:16,height:16).fill()
        Design.rule.setStroke();NSBezierPath(rect:NSRect(x:0.5,y:6.5,width:15,height:15)).stroke()
        Design.attributed(name,.body).draw(x:24,baseline:20,width:max(0,bounds.width-130))
        if !messages.isEmpty {Design.attributed(opened ? "▾":"▸",.body).draw(x:bounds.width-94,baseline:20)}
        Design.attributed(messages.isEmpty ? "Pass":"Warning",.caption).draw(x:bounds.width-78,baseline:20,width:58)
        (messages.isEmpty ? ResultGlyph.pass:ResultGlyph.warning).draw(in:NSRect(x:bounds.width-16,y:6,width:16,height:16))
        if opened {for (i,message) in messages.enumerated(){Design.attributed(message,.caption,colour:Design.quiet).draw(x:24,baseline:44+CGFloat(i)*24,width:bounds.width-24)}}
    }
}

final class WorkspaceHistogramPane: NSView, WorkspaceScrollableContent {
    let plot = HistogramView()
    var spectrumWidth:CGFloat=260 {didSet{needsLayout=true}}
    private var spectrum:[NSColor]=[]
    private var spectrumRect=NSRect.zero
    let expandButton=WorkspaceExpandButton()
    var expanded=false {didSet{expandButton.isHidden=expanded;plot.fillsHeight=expanded;needsLayout=true}}
    var onConfiguration:(()->Void)?
    func copyConfiguration(from other:WorkspaceHistogramPane){model.selectItem(at:other.model.indexOfSelectedItem);rebuildChannels();channels.selectItem(at:other.channels.indexOfSelectedItem);refresh()}
    private let model = AnalysisMenu("Histogram Colour Model", HistogramType.offered.map(\.title))
    private let channels = AnalysisMenu("Histogram Channels", [])
    private let colours = AnalysisMenu("Inspect Colour", [])
    private var keys: [String] = []
    private var names:[String]=[]
    private var findingRows:[HistogramFindingRow]=[]
    private let warningsToggle=AnalysisButton(title:"Warnings",target:nil,action:nil)
    private var showsAllFindings=false
    private var findingHeight:CGFloat {28 + findingRows.reduce(0){$0 + $1.rowHeight}}
    @objc private func toggleWarnings(){showsAllFindings.toggle();refresh()}
    private func rebuildFindings(){
        let opened=Set(findingRows.filter(\.opened).map(\.name))
        findingRows.forEach{$0.removeFromSuperview()};findingRows=[]
        let channel=channels.indexOfSelectedItem > 1 ? channels.indexOfSelectedItem-2:nil
        let records=keys.enumerated().map { index,key -> (Int,[String]) in
            guard let values=type.values(of:key) else{return(index,["Colour Values Unavailable"])}
            return(index,Self.findings(type:type,values:values,channel:channel))
        }.sorted{ $0.1.isEmpty == $1.1.isEmpty ? $0.0 < $1.0 : !$0.1.isEmpty }
        for (index,messages) in records where showsAllFindings || !messages.isEmpty {
            let row=HistogramFindingRow(frame:.zero)
            row.name=names[index];row.colour=spectrum.indices.contains(index) ? spectrum[index]:Design.hex(keys[index]);row.messages=messages
            row.opened=opened.contains(row.name);row.setAccessibilityLabel(row.name+", "+(messages.isEmpty ? "Pass":messages.joined(separator:", ")))
            row.changed={ [weak self] in self?.refresh() };findingRows.append(row);addSubview(row)
        }
        warningsToggle.title=(showsAllFindings ? "▾  ":"▸  ")+"Warnings (\(records.filter{ !$0.1.isEmpty }.count))"
    }
    static func findings(type:HistogramType,values:[Int],channel:Int?=nil)->[String]{
        guard type == .rgb || type == .cmyk || type == .ycbcr else{return []}
        return values.enumerated().compactMap{index,value in
            guard type.channels.indices.contains(index),channel == nil || channel == index else{return nil}
            let range = type == .ycbcr ? (index == 0 ? 64...940:64...960):type.safe!
            if type == .cmyk && value == 0{return nil}
            guard !range.contains(value) else{return nil}
            return "\(type.channels[index]): \(value) · \(value < range.lowerBound ? "Below":"Above") \(range.lowerBound)–\(range.upperBound)"
        }
    }
    private var title = "Select A Palette"
    var onColour: ((String?) -> Void)?
    private var panelPlotHeight: CGFloat { plot.split ? plot.intrinsicContentSize.height : 112 }
    var panelContentPadding:CGFloat {12}
    var minimumContentHeight: CGFloat { expanded ? 420+findingHeight : panelPlotHeight+214+findingHeight }
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        [plot, model, channels, colours, expandButton,warningsToggle].forEach { addSubview($0) }
        model.changed = { [weak self] _ in self?.rebuildChannels(); self?.refresh(); self?.onConfiguration?() }
        channels.changed = { [weak self] _ in self?.refresh();self?.onConfiguration?() }
        colours.changed = { [weak self] i in
            guard let self else { return }; self.refresh(); self.onColour?(i > 0 ? self.keys[i-1] : nil)
        }
        warningsToggle.showsArrow=false;warningsToggle.target=self;warningsToggle.action=#selector(toggleWarnings)
        rebuildChannels()
    }
    required init?(coder: NSCoder) { fatalError() }
    private var type: HistogramType { HistogramType.offered[max(0, model.indexOfSelectedItem)] }
    static func retainedChannelSelection(_ selection:Int,channelCount:Int)->Int {
        guard selection >= 0 else{return 0}
        if selection < 2{return selection}
        return selection-2 < channelCount ? selection:1
    }
    private func rebuildChannels() {
        let retained=Self.retainedChannelSelection(channels.indexOfSelectedItem,channelCount:type.channels.count)
        channels.options(["Merged", "Per Channel"] + type.channels,selected:retained)
    }
    func update(_ palette: Swatch?, library: Library, selected: String?) {
        title = palette?.name ?? "Select A Palette"; keys = palette?.entries.map(\.hex) ?? []
        spectrum=keys.map{library.definition(of:$0)?.master.display ?? Design.hex($0)}
        names=keys.map{library.name(of:$0,in:palette?.id)}
        colours.options(["All Colours"] + keys.enumerated().map { "\($0.offset+1). \(library.name(of: $0.element, in: palette?.id))" }, selected: selected.flatMap { keys.firstIndex(of: $0) }.map { $0+1 } ?? 0)
        refresh()
    }
    private func refresh() {
        plot.type = type; plot.split = channels.indexOfSelectedItem == 1
        plot.selectedChannel = channels.indexOfSelectedItem > 1 ? channels.indexOfSelectedItem-2 : nil
        plot.counts = Histogram.counts(of: keys, as: type)
        plot.own = colours.indexOfSelectedItem > 0 ? type.values(of: keys[colours.indexOfSelectedItem-1]) : nil
        // RGB guard bands are advisory, never a gamut or ΔE diagnosis.
        plot.showsGuides = type == .rgb || type == .cmyk || (type == .ycbcr && (plot.split || plot.selectedChannel != nil))
        plot.guideRanges = type == .ycbcr ? [64...940,64...960,64...960] : nil
        rebuildFindings()
        needsLayout = true; needsDisplay = true
        var ancestor=superview
        while let view=ancestor {
            if let panel=view as? WorkspacePanel {panel.rail?.arrange();break}
            ancestor=view.superview
        }
    }
    override func layout() {
        super.layout(); let w = max(20,bounds.width-24)
        expandButton.frame=NSRect(x:bounds.width-92,y:2,width:80,height:26)
        let offset:CGFloat=expanded ? 0:32
        colours.frame = NSRect(x:12,y:32+offset,width:w,height:24)
        model.frame = NSRect(x:12,y:64+offset,width:w*0.40,height:24)
        channels.frame = NSRect(x:16+w*0.40,y:64+offset,width:w*0.60-4,height:24)
        plot.frame = NSRect(x:12,y:100+offset,width:w,height:expanded ? max(140,bounds.height-284-findingHeight) : panelPlotHeight)
        var fy=plot.frame.maxY+82
        warningsToggle.frame=NSRect(x:12,y:fy,width:w,height:28);fy += 28
        for row in findingRows{row.frame=NSRect(x:12,y:fy,width:w,height:row.rowHeight);fy += row.rowHeight}
        if expanded {
            let sw=min(spectrumWidth,max(40,plot.frame.width-24))
            spectrumRect=NSRect(x:plot.frame.midX-sw/2,y:bounds.height-76,width:sw,height:64)
        } else {
            spectrumRect=NSRect(x:12,y:36,width:w,height:20)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        Design.attributed(title,.bodyStrong).draw(x:12,baseline:21,width:bounds.width-110)
        PaletteSpectrum.draw(spectrum,in:spectrumRect)
        let y = plot.frame.maxY+22
        Design.attributed(type.scale,.caption,colour:Design.quiet).draw(x:12,baseline:y,width:bounds.width-24)
        let guide = type == .ycbcr ? "Legal Signal Bands · Not ΔE" : (type == .rgb || type == .cmyk ? "Advisory Guard Bands · Not ΔE" : "Full Channel Range")
        Design.attributed(guide,.caption,colour:Design.quiet).draw(x:12,baseline:y+24,width:bounds.width-24)
        Design.attributed("Bright: Selected · Dim: Palette",.caption,colour:Design.quiet).draw(x:12,baseline:y+48,width:bounds.width-24)
    }
}

final class WorkspaceBloomPane: NSView, WorkspaceScrollableContent {
    let chart = PrintBloomView(frame:.zero)
    let expandButton=WorkspaceExpandButton()
    var spectrumWidth:CGFloat=260 {didSet{needsLayout=true}}
    private var spectrum:[NSColor]=[]
    private var spectrumRect=NSRect.zero
    private let findings=PrintBloomFeedback()
    private let findingsScroll=FittedScrollView()
    var onConfiguration:(()->Void)?
    private let profiles = PrintProfileSelector(compact:true)
    private let press = AnalysisMenu("Printing Condition", [])
    private let intent = AnalysisMenu("Rendering Intent", RenderingIntent.allCases.map(\.name))
    private let tolerance = AnalysisMenu("ΔE2000 Tolerance", ["ΔE 1", "ΔE 1.5", "ΔE 2", "ΔE 3", "ΔE 5"])
    private let order = AnalysisMenu("Petal Order", PrintBloomView.Order.allCases.map(\.rawValue))
    private let black = AnalysisButton(title:"Black Point Compensation",target:nil,action:nil)
    private var settings = PrintProfileSettings()
    private var conditions: [String] = []
    private var title = "Select A Palette"
    private var summary = "Print Prediction · Select A Palette"
    var expanded = false { didSet {
        chart.expanded=expanded;chart.showsCaption = !expanded;expandButton.isHidden=expanded;findingsScroll.isHidden = !expanded
        [profiles,press,intent,tolerance,black].forEach{$0.isHidden=expanded};needsLayout=true
    } }
    var panelContentPadding:CGFloat {12}
    var minimumContentHeight: CGFloat {600}
    override var isFlipped: Bool { true }
    override init(frame:NSRect) {
        super.init(frame:frame); chart.compact=true;chart.showsExpandControl=false;black.setButtonType(.switch);black.showsCheck=true
        [chart,profiles,press,intent,tolerance,order,black,expandButton].forEach { addSubview($0) }
        findingsScroll.documentView=findings;findingsScroll.drawsBackground=false;findingsScroll.hasVerticalScroller=true;findingsScroll.autohidesScrollers=true;findingsScroll.isHidden=true;addSubview(findingsScroll)
        black.font=Design.Text.body.font(); black.target=self; black.action=#selector(saveBlack)
        press.changed = { [weak self] i in guard let self else{return}; self.settings.press=self.conditions[i];self.save() }
        intent.changed = { [weak self] i in self?.settings.intent=RenderingIntent.allCases[i];self?.save() }
        tolerance.changed = { [weak self] i in self?.settings.tolerance=[1,1.5,2,3,5][i];self?.save() }
        order.changed = { [weak self] i in self?.chart.order=PrintBloomView.Order.allCases[i]; AppPreferences.shared.set(PrintBloomView.Order.allCases[i].rawValue,forKey:"workspace.bloomOrder"); self?.onConfiguration?() }
    }
    required init?(coder:NSCoder){fatalError()}
    @objc private func saveBlack(){settings.blackPoint=black.state == .on;save()}
    private func save(){do{try SavedPrintProfiles.setCurrent(settings)}catch{NSApp.presentError(error)}}
    func update(_ palette:Swatch?,library:Library,selected:String?){
        title=palette?.name ?? "Select A Palette"
        spectrum=(palette?.entries ?? []).compactMap{library.definition(of:$0.hex)?.master.display}
        do { settings=try SavedPrintProfiles.load().current } catch { summary="Print Profiles Unavailable";chart.items=[];needsDisplay=true;return }
        conditions=PressProfiles.all.map(\.name);if !conditions.contains(settings.press){conditions.append(settings.press)}
        press.options(conditions,selected:conditions.firstIndex(of:settings.press) ?? 0)
        intent.selectItem(at:RenderingIntent.allCases.firstIndex(of:settings.intent) ?? 0)
        tolerance.selectItem(at:[1,1.5,2,3,5].firstIndex(of:settings.tolerance) ?? -1)
        if tolerance.indexOfSelectedItem < 0 { tolerance.title="ΔE \(settings.tolerance)" }
        black.state=settings.blackPoint ? .on:.off; black.isEnabled=settings.intent != .perceptual
        chart.order=PrintBloomView.Order(rawValue:AppPreferences.shared.string(forKey:"workspace.bloomOrder") ?? "") ?? .palette
        order.selectItem(at:PrintBloomView.Order.allCases.firstIndex(of:chart.order) ?? 0)
        chart.tolerance=settings.tolerance;chart.selected=selected
        var seen=Set<String>()
        chart.items=(palette?.entries ?? []).compactMap { entry in
            guard seen.insert(entry.hex).inserted, let definition=library.definition(of:entry.hex) else{return nil}
            let result=Rendering.of(definition,in:settings.channel)
            let build=PrintBuild.of(definition.master,press:settings.press,intent:settings.intent,blackPoint:settings.blackPoint)
            return PrintBloomView.Item(id:entry.hex,name:library.name(of:entry.hex,in:palette?.id),master:definition.master.display,printed:result.shown?.display,delta:result.difference,ink:build?.totalInk)
        }
        chart.selected = selected.flatMap { key in chart.items.contains{$0.id==key} ? key:nil } ?? chart.items.first?.id
        findings.update(item:chart.items.first{$0.id==chart.selected},tolerance:settings.tolerance,condition:settings.press)
        let valid=chart.items.compactMap(\.delta), passes=valid.filter{$0 <= settings.tolerance}.count
        summary=chart.items.isEmpty ? "Select A Palette To Predict Print" : "\(passes)/\(valid.count) Within ΔE \(settings.tolerance) · \(chart.items.count-valid.count) Unavailable"
        needsLayout=true;needsDisplay=true
    }
    override func layout(){
        super.layout();let w=max(20,bounds.width-24)
        expandButton.frame=NSRect(x:bounds.width-92,y:2,width:80,height:26)
        if expanded {
            let reportWidth=min(240,max(170,w*0.27))
            findingsScroll.frame=NSRect(x:12,y:44,width:reportWidth,height:max(0,bounds.height-164))
            findings.fit(width:findingsScroll.contentSize.width,minimumHeight:findingsScroll.contentSize.height)
            chart.frame=NSRect(x:reportWidth+28,y:68,width:max(80,bounds.width-reportWidth-40),height:max(280,bounds.height-164))
            let orderWidth=min(220,chart.frame.width)
            order.frame=NSRect(x:chart.frame.midX-orderWidth/2,y:36,width:orderWidth,height:24)
            let sw=min(spectrumWidth,max(40,chart.frame.width-24))
            spectrumRect=NSRect(x:chart.frame.midX-sw/2,y:bounds.height-76,width:sw,height:64)
        } else {
            spectrumRect=NSRect(x:12,y:36,width:w,height:20)
            order.frame=NSRect(x:12,y:64,width:w,height:24)
            chart.frame=NSRect(x:12,y:96,width:w,height:320)
            let y=chart.frame.maxY+28
            profiles.frame=NSRect(x:12,y:y,width:w,height:28)
            for (i,view) in [press,intent,tolerance,black].enumerated(){view.frame=NSRect(x:12,y:y+36+CGFloat(i)*32,width:w,height:24)}
        }
    }
    override func draw(_ dirtyRect:NSRect){
        Design.attributed(title,.bodyStrong).draw(x:12,baseline:21,width:bounds.width-(expanded ? 100:110))
        PaletteSpectrum.draw(spectrum,in:spectrumRect)
        if expanded {
            let item=chart.items.first{$0.id==chart.selected}, width=findingsScroll.contentSize.width
            Design.attributed(item?.name ?? "Select A Colour",.bodyStrong).draw(x:12,baseline:bounds.height-68,width:width)
            let detail=item?.delta.map{String(format:"ΔE00 %.2f · %@",$0,$0 <= chart.tolerance ? "Holds":"Outside")} ?? "Prediction Unavailable"
            Design.attributed(detail,.caption,colour:Design.quiet).draw(x:12,baseline:bounds.height-44,width:width)
            Design.attributed(summary,.caption,colour:Design.quiet).draw(x:12,baseline:bounds.height-16,width:width)
        } else {
            Design.attributed(summary,.caption,colour:Design.quiet).draw(x:12,baseline:chart.frame.maxY+18,width:bounds.width-24)
        }
    }
}

/// The list is the current filtered palette set; expansion never changes the user's grid mode.
final class WorkspaceExpandedPanel: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private var content:NSView?
    func present(_ view:NSView){content=view;detail.documentView=view;needsLayout=true}
    private let table=NSTableView(), list=FittedScrollView(), detail=FittedScrollView()
    private let close=WorkspaceExpandButton(closes:true)
    private var palettes:[Swatch]=[]
    private var updatingSelection=false
    var onPick:((UUID)->Void)?
    var onClose:(()->Void)?
    override var isFlipped:Bool{true}
    override init(frame:NSRect){
        super.init(frame:frame)
        let column=NSTableColumn(identifier:.init("palettes"));table.addTableColumn(column)
        table.headerView=nil;table.rowHeight=48;table.dataSource=self;table.delegate=self;table.style = .plain
        table.backgroundColor=Design.card
        list.documentView=table
        for scroll in [list,detail]{scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;addSubview(scroll)}
        close.run = { [weak self] in self?.onClose?() };addSubview(close)

    }
    required init?(coder:NSCoder){fatalError()}
    func update(_ palettes:[Swatch],selected:UUID?){updatingSelection=true;defer{updatingSelection=false};self.palettes=palettes;table.reloadData();if let index=palettes.firstIndex(where:{$0.id==selected}){table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)}else{table.deselectAll(nil)}}
    func tableViewSelectionDidChange(_ notification:Notification){if !updatingSelection {picked()}}
    @objc private func picked(){let i=table.selectedRow;guard palettes.indices.contains(i) else{return};onPick?(palettes[i].id)}
    @objc private func closed(){onClose?()}
    func numberOfRows(in tableView:NSTableView)->Int{palettes.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView?{
        AnalysisPaletteCell(palette:palettes[row])
    }
    func tableView(_ tableView:NSTableView,rowViewForRow row:Int)->NSTableRowView?{WorkspacePanelRow()}
    override func layout(){super.layout();let split=(bounds.width*0.20).rounded()
        close.frame=NSRect(x:bounds.width-96,y:2,width:80,height:26)
        list.frame=NSRect(x:0,y:0,width:split-1,height:bounds.height);table.tableColumns.first?.width=list.contentSize.width
        detail.frame=NSRect(x:split,y:0,width:bounds.width-split,height:bounds.height)
        content?.frame=NSRect(x:0,y:0,width:detail.contentSize.width,height:max((content as? WorkspaceScrollableContent)?.minimumContentHeight ?? 0,detail.contentSize.height))
    }
    override func draw(_ dirtyRect:NSRect){Design.card.setFill();bounds.fill();Design.rule.setFill();NSRect(x:(bounds.width*0.20).rounded()-1,y:0,width:1,height:bounds.height).fill()}
}

final class WorkspaceChannelControls:NSView,Overlay {
    private enum Toggle:Equatable {case paper,kOnly}
    private struct Choice {
        var profile:UUID?,channel:ProfileChannel?,group:String
        var link:URL?=nil,toggle:Toggle?=nil,enabled=true,relocateID:String?=nil,warning=false
    }
    private let button=DropdownButton()
    private var items:[String]=[],choices:[Choice?]=[]
    private var chosenIndex=0
    private var proofMenu:SwissDropdown.MenuPanel?
    private var preview:ProfileChannel?
    private var selectionTitle="Master Colours"
    private var library=Library(),palette:UUID?
    private var paper:Bool {AppPreferences.shared.bool(forKey:"workspace.targetPaperWhite")}
    private var kOnly:Bool {AppPreferences.shared.bool(forKey:"workspace.targetKOnly")}
    var onChange:(()->Void)?
    var onLocateICC:((String)->Void)?
    static let iccSection=UUID(uuidString:"F5A3B5A1-9764-4C37-9AD0-19AE7F958A21")!
    func useICC(_ profile:ICCProfileLibrary.Profile){
        AppPreferences.shared.set(Self.iccSection.uuidString,forKey:"workspace.channelProfile")
        AppPreferences.shared.set(profile.channel.space,forKey:"workspace.previewChannel")
        AppPreferences.shared.set(profile.key,forKey:"workspace.targetPress")
    }
    var selectedChannel:ProfileChannel? {preview}
    var overlayWindows:[NSWindow] {proofMenu.map{[$0]} ?? []}
    func dismissOverlay(){if let proofMenu{proofMenu.parent?.removeChildWindow(proofMenu);proofMenu.orderOut(nil)};proofMenu=nil;Overlays.closed(self)}
    override var isFlipped:Bool{true}
    override init(frame:NSRect){
        super.init(frame:frame);addSubview(button);button.title=selectionTitle;button.target=self;button.action=#selector(openMenu)
        button.setAccessibilityLabel("Colour Target");button.font=Design.Text.body.font()
    }
    required init?(coder:NSCoder){fatalError()}
    static func previewTitle(_ channel:ProfileChannel)->String {
        if let key=channel.press,key.hasPrefix(ICCProfileLibrary.prefix){return ICCProfileLibrary.shared.profile(for:key).map{$0.model+" · "+$0.name} ?? "Missing ICC Profile"}
        if let target=channel.target{return target.name+" · "+target.hint}
        if channel.isPrint{return (channel.space == ProfileChannel.printGrey ? "Grey · ":(channel.blackOnly == true ? "K-only · ":"CMYK · "))+(channel.press ?? PressProfiles.generic)}
        switch channel.rgb {
        case .displayP3?:return "Display P3 · Screen"
        case .p3D65?:return "P3-D65 · Cinema D65"
        case .dciP3?:return "DCI-P3 · Cinema White"
        default:return channel.name
        }
    }
    func configure(library:Library,palette:UUID?){
        self.library=library;self.palette=palette
        let profiles=ColourProfiles.load(),record=library.profile(forPalette:palette,house:profiles,houseDefault:ColourProfiles.houseDefault).profile
        let effective=record.changedAt == Date(timeIntervalSince1970:0) ? ColourProfiles.starters.first(where:{$0.id == record.id}) ?? record:record
        let savedPrint=try? SavedPrintProfiles.load().current.channel
        let installed=PressProfiles.all.filter{$0.name != PressProfiles.generic},greys=PressProfiles.greys
        items=["Master Colours"];choices=[Choice(profile:nil,channel:nil,group:"")]
        func heading(_ title:String){items += [SwissDropdown.MenuPanel.divider,SwissDropdown.MenuPanel.heading(title)];choices += [nil,nil]}
        func append(_ title:String,_ choice:Choice){items.append(title);choices.append(choice)}
        func condition(_ original:ProfileChannel)->ProfileChannel {
            var channel=original
            if channel.isPrint {
                channel.intent=paper ? .absolute:(savedPrint?.intent == .absolute ? .relative:savedPrint?.intent ?? .relative)
                channel.blackPoint=savedPrint?.blackPoint
                channel.blackOnly=channel.space == ProfileChannel.print && kOnly ? true:nil
            }
            return channel
        }
        func section(_ title:String,_ id:UUID?,_ channels:[ProfileChannel]){
            heading(title)
            for original in channels {
                let channel=condition(original)
                let available = !channel.isPrint || (channel.press != PressProfiles.generic && PressProfiles.installed.contains{$0.name == channel.press})
                if channel.isPrint,channel.press == PressProfiles.generic {
                    append("Generic CMYK · Unspecified, Not A Press",Choice(profile:id,channel:nil,group:title,enabled:false))
                } else {append(Self.previewTitle(channel)+(available ? "":" · Not Installed"),Choice(profile:id,channel:channel,group:title,enabled:available))}
            }
        }
        let iccGroups=ICCProfileLibrary.shared.grouped(ICCProfileLibrary.shared.profiles)
        if !iccGroups.missing.isEmpty {
            heading("Missing Profiles")
            for profile in iccGroups.missing {append(Self.previewTitle(profile.channel)+" · Locate…",Choice(profile:Self.iccSection,channel:condition(profile.channel),group:"Your ICC Profiles",relocateID:profile.id,warning:true))}
        }
        let paletteName=palette.flatMap{library.swatch($0)?.name} ?? "Current Selection"
        section("Palette: "+paletteName+" · "+effective.name,nil,effective.channels)
        let everyID=ColourProfiles.starters[4].id,printID=ColourProfiles.starters[1].id
        let ordered=profiles.filter{$0.id != everyID}+profiles.filter{$0.id == everyID}
        for profile in ordered {
            if profile.id == everyID {
                let linked=iccGroups.available
                if !linked.isEmpty {
                    heading("Your ICC Profiles")
                    for profile in linked.sorted(by:{$0.name.localizedStandardCompare($1.name) == .orderedAscending}) {
                        let available=ICCProfileLibrary.shared.space(for:profile.key) != nil
                        let channel=condition(profile.channel)
                        append(Self.previewTitle(channel)+(!profile.canTarget ? " · Inspect Only":(available ? "":" · Missing · Locate…")),Choice(profile:Self.iccSection,channel:channel,group:"Your ICC Profiles",enabled:profile.canTarget,relocateID:available ? nil:profile.id))
                    }
                }
            }
            var channels=profile.channels
            if profile.id == printID {channels=[]}
            if profile.id == everyID {channels=RGBSpace.allCases.map{ProfileChannel(space:$0.rawValue)}+ColourTargetSpace.allCases.map{ProfileChannel(space:$0.rawValue)}}
            if profile.id == printID || profile.id == everyID {
                channels.removeAll( where:{$0.isPrint})
                channels += installed.map{ProfileChannel(space:ProfileChannel.print,press:$0.name,intent:.relative)}
                channels += greys.map{ProfileChannel(space:ProfileChannel.printGrey,press:$0.name,intent:.relative)}
                if let missing=AppPreferences.shared.string(forKey:"workspace.targetPress"),missing != PressProfiles.generic,
                   !PressProfiles.installed.contains(where:{$0.name == missing}),AppPreferences.shared.string(forKey:"workspace.channelProfile") == profile.id.uuidString {
                    channels.append(ProfileChannel(space:AppPreferences.shared.string(forKey:"workspace.previewChannel") ?? ProfileChannel.print,press:missing))
                }
            }
            section(profile.name,profile.id,channels)
            if profile.id == printID {
                if greys.isEmpty{append("Grey Press ICC · None Installed",Choice(profile:profile.id,channel:nil,group:profile.name,enabled:false))}
                if channels.isEmpty{append("No Press ICC Profiles Installed",Choice(profile:profile.id,channel:nil,group:profile.name,enabled:false))}
                append("Simulate Paper White",Choice(profile:profile.id,channel:nil,group:profile.name,toggle:.paper,enabled:!channels.isEmpty))
                append("K-only · Use Selected CMYK Condition",Choice(profile:profile.id,channel:nil,group:profile.name,toggle:.kOnly,enabled:!installed.isEmpty))
                let missing=PrintTargetStandards.all.filter{!$0.installed(in:installed)}
                if !missing.isEmpty{heading("Not Installed · Get Profiles From Publisher")}
                for standard in missing {append(standard.name+" · "+standard.publisher+"…",Choice(profile:profile.id,channel:nil,group:profile.name,link:standard.url))}
            }
        }
        let savedProfile=AppPreferences.shared.string(forKey:"workspace.channelProfile").flatMap(UUID.init(uuidString:))
        let space=AppPreferences.shared.string(forKey:"workspace.previewChannel"),press=AppPreferences.shared.string(forKey:"workspace.targetPress")
        chosenIndex=space == nil ? 0:(choices.firstIndex{choice in
            guard let choice,let channel=choice.channel else{return false}
            return choice.profile == savedProfile && channel.space == space && (!(channel.isPrint || channel.space == ProfileChannel.iccRGB) || channel.press == press)
        } ?? 0)
        let selected=choices[chosenIndex];preview=selected?.channel
        selectionTitle=preview.map{(selected?.group ?? "")+" · "+Self.previewTitle($0)+(paper && $0.isPrint ? " · Paper White":"")} ?? "Master Colours"
        button.title=selectionTitle;button.toolTip="Colour Target · "+selectionTitle;needsDisplay=true
    }
    @objc private func openMenu(){
        guard let win=window else{return}
        if let proofMenu,proofMenu.isVisible{dismissOverlay();return}
        dismissOverlay();PressProfiles.refresh();configure(library:library,palette:palette)
        let snapshot=choices,width=max(400,bounds.width)
        let panel=SwissDropdown.MenuPanel(items:items,chosen:"",width:width,chosenIndex:chosenIndex){[weak self] index in
            guard let self,snapshot.indices.contains(index),let choice=snapshot[index] else{return}
            self.dismissOverlay()
            if let id=choice.relocateID {self.onLocateICC?(id);return}
            if let link=choice.link{NSWorkspace.shared.open(link);return}
            if let toggle=choice.toggle {
                let key=toggle == .paper ? "workspace.targetPaperWhite":"workspace.targetKOnly"
                AppPreferences.shared.set(!(toggle == .paper ? self.paper:self.kOnly),forKey:key)
            } else {
                AppPreferences.shared.set(choice.profile?.uuidString,forKey:"workspace.channelProfile")
                AppPreferences.shared.set(choice.channel?.space,forKey:"workspace.previewChannel")
                AppPreferences.shared.set(choice.channel?.press,forKey:"workspace.targetPress")
            }
            self.onChange?()
        }
        panel.configure(disabled:Set(choices.indices.filter{choices[$0]?.enabled != true}))
        panel.setWarnings(Set(choices.indices.filter{choices[$0]?.warning == true}))
        var checked:Set<Int>=[chosenIndex]
        for (index,choice) in choices.enumerated(){if choice?.toggle == .paper && paper || choice?.toggle == .kOnly && kOnly {checked.insert(index)}}
        panel.setCheckedIndexes(checked)
        let anchor=win.convertToScreen(convert(bounds,to:nil));panel.place(anchoredTo:NSRect(x:anchor.maxX-width,y:anchor.minY,width:width,height:anchor.height),within:win)
        win.addChildWindow(panel,ordered:.above);proofMenu=panel;Overlays.opened(self)
    }
    func reportUnavailable(_ count:Int){
        button.title=selectionTitle+(count > 0 ? " · Unavailable":"")
        button.toolTip="Colour Target · "+selectionTitle+(count > 0 ? " · Selected ICC unavailable; master display retained, target values unavailable":"")
    }
    override func layout(){
        super.layout();let left=Design.attributed("Colour Target",.bodyStrong).size().width+12
        button.frame=NSRect(x:left,y:(bounds.height-28)/2,width:max(0,bounds.width-left),height:28)
    }
    override func draw(_ dirtyRect:NSRect){
        let font=Design.Text.bodyStrong.font(),width=Design.attributed("Colour Target",.bodyStrong).size().width
        Design.attributed("Colour Target",.bodyStrong).draw(x:0,baseline:bounds.midY+(font.ascender+font.descender)/2,width:width)
    }
}

private final class AnalysisButton:NSButton {
    var showsCheck=false
    var showsArrow=true
    override var isFlipped:Bool{true}
    override func draw(_ dirtyRect:NSRect){
        let prefix=showsCheck ? (state == .on ? "☑  ":"☐  "):(showsArrow ? "↙  ":"")
        Design.attributed(prefix+title,.body,colour:isEnabled ? Design.ink:Design.quiet).draw(x:4,baseline:18,width:bounds.width-8)
    }
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
}

private final class AnalysisPaletteCell:NSView {
    let palette:Swatch
    init(palette:Swatch){self.palette=palette;super.init(frame:.zero);setAccessibilityElement(true);setAccessibilityLabel(palette.name+", "+String(palette.entries.count)+" Colours")}
    required init?(coder:NSCoder){fatalError()}
    override var isFlipped:Bool{true}
    override func draw(_ dirtyRect:NSRect){
        let sampleWidth:CGFloat=min(96,max(48,bounds.width*0.28)), textWidth=min(160,max(24,bounds.width-sampleWidth-20))
        Design.attributed(palette.name,.body).draw(x:8,baseline:18,width:textWidth)
        Design.attributed("\(palette.entries.count) Colours",.caption,colour:Design.quiet).draw(x:8,baseline:38,width:textWidth)
        let entries=Array(palette.entries.prefix(8)), width=sampleWidth/CGFloat(max(1,entries.count))
        for (i,entry) in entries.enumerated(){(ColourKeys.definition(of:entry.hex)?.master.display ?? Design.hex(entry.hex)).setFill();NSRect(x:16+textWidth+CGFloat(i)*width,y:10,width:width,height:28).fill()}
    }
}

/// One shared affordance for all docked/expanded panel content.
final class WorkspaceExpandButton:NSButton {
    var run:(()->Void)?
    private let closes:Bool
    init(closes:Bool=false){self.closes=closes;super.init(frame:.zero);isBordered=false;title=closes ? "Close":"Expand";setAccessibilityLabel(title);toolTip=closes ? "Close Expanded Panel · Esc":"Expand Panel";target=self;action=#selector(invoke)}
    required init?(coder:NSCoder){fatalError()}
    @objc private func invoke(){run?()}
    override var isFlipped:Bool{true}
    override func draw(_ dirtyRect:NSRect){Design.attributed((closes ? "×  ":"⤢  ")+title,.body,colour:isHighlighted ? Design.quiet:Design.ink).draw(x:4,baseline:19,width:bounds.width-8)}
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
}

/// Palette spectra use the same master colours and strip geometry in both analysis panes.
private enum PaletteSpectrum {
    static func draw(_ colours:[NSColor],in rect:NSRect){
        guard !colours.isEmpty else{return}
        let width=rect.width/CGFloat(colours.count)
        for (i,colour) in colours.enumerated(){colour.setFill();NSRect(x:rect.minX+CGFloat(i)*width,y:rect.minY,width:width,height:rect.height).fill()}
    }
}
