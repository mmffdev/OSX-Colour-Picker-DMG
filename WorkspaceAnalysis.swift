import AppKit

/// Compact native controls shared by the analysis dock and expanded workspace.
final class AnalysisMenu: ClickCursorPopupButton, Overlay {
    var borderless=false {didSet{needsDisplay=true}}
    var dismissOnOutsideClick:Bool{true}
    private var houseMenu:SwissDropdown.MenuPanel?
    var menuHeadings = false
    var overlayWindows:[NSWindow]{houseMenu.map{[$0]} ?? []}
    func dismissOverlay(){if let houseMenu{houseMenu.parent?.removeChildWindow(houseMenu);houseMenu.orderOut(nil)};houseMenu=nil;Overlays.closed(self)}
    func handleOverlayEscape()->Bool{dismissOverlay();return true}
    override func mouseDown(with event:NSEvent){openHouseMenu()}
    override func accessibilityPerformPress()->Bool{guard isEnabled else{return false};openHouseMenu();return true}
    override func keyDown(with event:NSEvent){if [36,49,125].contains(event.keyCode){openHouseMenu()}else{super.keyDown(with:event)}}
    private func openHouseMenu(){
        guard isEnabled,let owner=window else{return}
        if houseMenu?.isVisible == true{dismissOverlay();return};dismissOverlay()
        let titles=itemTitles
        let width=min(440,max(bounds.width,min(440,(titles.map{Design.attributed($0,.body).size().width}.max() ?? 0)+52)))
        let panel=SwissDropdown.MenuPanel(items:titles,chosen:"",width:width,literalItems:!menuHeadings,chosenIndex:indexOfSelectedItem){[weak self] index in
            guard let self else{return};self.dismissOverlay();self.selectItem(at:index);self.picked()
        }
        let anchor=owner.convertToScreen(convert(bounds,to:nil));panel.place(anchoredTo:anchor,within:owner)
        owner.addChildWindow(panel,ordered:.above);houseMenu=panel;panel.makeKeyAndOrderFront(nil);Overlays.opened(self)
    }
    var fittedWidth: CGFloat { ceil(Design.attributed(titleOfSelectedItem ?? title, .body).size().width) + (borderless ? 20:48) }
    var changed: ((Int) -> Void)?
    init(_ label: String, _ titles: [String]) {
        super.init(frame: .zero, pullsDown: false)
        font = Design.Text.body.font(); addItems(withTitles: titles)
        target = self; action = #selector(picked); setAccessibilityLabel(label); toolTip = label
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped:Bool{true}
    override func draw(_ dirtyRect:NSRect){
        // Own the same surface as the house menu, including inside native dark Settings.
        if borderless{InlineDropdownSkin.draw(in:bounds)}else{Design.card.setFill();NSBezierPath(roundedRect:bounds,xRadius:4,yRadius:4).fill();DropdownSkin.draw(in:bounds,hover:isHighlighted)}
        Design.attributed(titleOfSelectedItem ?? title,.body,colour:isEnabled ? Design.ink:Design.quiet).draw(x:borderless ? 0:8,baseline:bounds.midY+(borderless ? 5:4),width:max(0,bounds.width-(borderless ? 20:44)))
    }
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
    @objc private func picked() { needsDisplay=true;changed?(indexOfSelectedItem) }
    func options(_ titles: [String], selected: Int = 0) {
        removeAllItems(); addItems(withTitles: titles); selectItem(at: max(0, min(selected, titles.count - 1)));needsDisplay=true
    }
}

/// One target contract and adaptive control stack shared by both analysis panels.
enum AnalysisTarget {
    static let changed=Notification.Name("Colorgain.AnalysisTargetChanged")
    static let categories=["Design And Photography","Print","Video And Cinema","3D And VFX"]
    static var category:Int {max(0,min(3,(try? SavedPrintProfiles.load().current.viewingCategory) ?? (AppPreferences.shared.object(forKey:"workspace.analysisCategory") as? Int) ?? 1))}
    private static func candidates(for category:Int)->[ProfileChannel]{
        switch category{
        case 0:return [RGBSpace.srgb,.displayP3,.adobeRGB,.prophoto].map{ProfileChannel(space:$0.rawValue)}+[ColourTargetSpace.eciRGB,.grey22].map{ProfileChannel(space:$0.rawValue)}+(ICCProfileLibrary.shared.profiles+ICCProfileLibrary.shared.system).filter{$0.model == "RGB"}.map(\.channel)
        case 1:return [PrintCondition.current]
        case 2:return [RGBSpace.rec709,.rec2020,.p3D65,.dciP3].map{ProfileChannel(space:$0.rawValue)}+[ColourTargetSpace.pq,.hlg,.dciXYZ].map{ProfileChannel(space:$0.rawValue)}
        default:return [RGBSpace.acescg,.linearSRGB].map{ProfileChannel(space:$0.rawValue)}+[ColourTargetSpace.aces2065,.acescct,.linear2020,.linearP3].map{ProfileChannel(space:$0.rawValue)}
        }
    }
    static func choices(for category:Int)->[ProfileChannel]{var seen=Set<String>();return candidates(for:category).filter{seen.insert($0.space+"|"+($0.press ?? "")).inserted}}
    static var choices:[ProfileChannel]{choices(for:category)}
    static var labels:[String]{choices.map{$0.space == ProfileChannel.iccRGB ? $0.name+" · ICC":$0.name}}
    static var channel:ProfileChannel{
        let settings=(try? SavedPrintProfiles.load().current) ?? PrintProfileSettings()
        if category == 1{return settings.channel}
        if var stored=settings.viewingChannel{stored.intent=settings.intent;stored.blackPoint=settings.blackPoint;return stored}
        let id=AppPreferences.shared.string(forKey:"workspace.analysisSpace.\(category)")
        var result=choices.first{$0.space+"|"+($0.press ?? "") == id} ?? choices[0]
        result.legal=AppPreferences.shared.bool(forKey:"workspace.analysisLegal")
        result.intent=settings.intent;result.blackPoint=settings.blackPoint
        return result
    }
    static func category(for channel:ProfileChannel)->Int{
        if channel.isPrint{return 1}
        if let rgb=channel.rgb{switch rgb{case .rec709,.rec2020,.p3D65,.dciP3:return 2;case .acescg,.linearSRGB:return 3;default:return 0}}
        if let target=channel.target{switch target{case .pq,.hlg,.dciXYZ:return 2;case .aces2065,.acescct,.linear2020,.linearP3:return 3;default:return 0}}
        return 0
    }
    static var hasSignalRange:Bool{channel.rgb?.isVideo == true || channel.target?.isHDR == true}
    static var metric:String{channel.target?.isHDR == true ? "ΔE ITP":"ΔE00"}
    static func notify(){NotificationCenter.default.post(name:changed,object:nil)}
}
private final class AnalysisTargetFilter:NSView {
    private let workflow=AnalysisMenu("Analysis Workflow",AnalysisTarget.categories)
    private let target=AnalysisMenu("Output Profile",[])
    private let intent=AnalysisMenu("Rendering Intent",RenderingIntent.allCases.map(\.name))
    private let blackMenu=AnalysisMenu("Black Point Compensation",["Off","On"])
    private let range=AnalysisMenu("Signal Range",["Full Range · 10-Bit","Legal Range · 10-Bit"])
    private let tolerance=AnalysisMenu("Colour Difference Tolerance",["ΔE 1","ΔE 1.5","ΔE 2","ΔE 3","ΔE 5"])
    private let preset=PrintProfileSelector(compact:true)
    private let black=AnalysisButton(title:"Black Point Compensation",target:nil,action:nil)
    private let heading=Design.text("",.caption,colour:Design.quiet)
    private var printNames:[String]=[]
    var draft:PrintProfileSettings? {didSet{sync()}}
    private var category:Int {draft?.viewingCategory ?? AnalysisTarget.category}
    private var channel:ProfileChannel {
        guard let draft else{return AnalysisTarget.channel}
        if category == 1{return draft.channel}
        var c=draft.viewingChannel ?? AnalysisTarget.choices(for:category)[0]
        c.intent=draft.intent;c.blackPoint=draft.blackPoint;return c
    }
    private var choices:[ProfileChannel]{AnalysisTarget.choices(for:category)}
    private var hasSignalRange:Bool{channel.rgb?.isVideo == true || channel.target?.isHDR == true}
    private var metric:String{channel.target?.isHDR == true ? "ΔE ITP":"ΔE00"}
    private var inlineFields: [(String, AnalysisMenu)] {
        var fields = [("Workflow", workflow), ("Target", target), ("Tolerance", tolerance)]
        if category == 1 || channel.space == ProfileChannel.iccRGB { fields.append(("Rendering Intent", intent));fields.append(("Black Point Compensation",blackMenu)) }
        return fields
    }
    var inlineLeadingWidth: CGFloat = 0
    private func inlinePositions(width: CGFloat, leading: CGFloat) -> [(AnalysisMenu, NSRect)] {
        var x = leading, y: CGFloat = 3
        return inlineFields.map { label, menu in
            let labelWidth = Design.attributed(label, .controlLabel).size().width + 12
            let fieldWidth = labelWidth + menu.fittedWidth
            if x > 0 && x + fieldWidth > width { x = 0; y += 34 }
            let frame = NSRect(x:x + labelWidth,y:y,width:menu.fittedWidth,height:28)
            x += fieldWidth + 24
            return (menu, frame)
        }
    }
    func inlineHeight(forWidth width: CGFloat, leading: CGFloat) -> CGFloat {
        (inlinePositions(width: width, leading: leading).last?.1.maxY ?? 31) + 3
    }
    var inline=false {didSet{[workflow,target,tolerance,intent,blackMenu].forEach{$0.borderless=inline}}}
    var changed:(()->Void)?
    var height:CGFloat{self.category == 1 ? 168:108+(self.hasSignalRange || self.channel.space == ProfileChannel.iccRGB ? 32:0)}
    override var isFlipped:Bool{true}
    override init(frame:NSRect){super.init(frame:frame)
        [workflow,target,intent,range,tolerance,black,blackMenu,heading].forEach{addSubview($0)}
        blackMenu.isHidden=true
        blackMenu.changed={ [weak self] index in self?.save{$0.blackPoint=index == 1} }
        workflow.changed={ [weak self] index in guard let self else{return};if self.draft == nil{AppPreferences.shared.set(index,forKey:"workspace.analysisCategory")};self.save{$0.viewingCategory=index;$0.viewingChannel=nil} }
        target.changed={ [weak self] index in guard let self else{return}
            if self.category == 1{self.save{ $0.press=self.printNames[index] }}else{let c=self.choices[index];self.save{$0.viewingCategory=self.category;$0.viewingChannel=c}}
        }
        intent.changed={ [weak self] index in self?.save{$0.intent=RenderingIntent.allCases[index]} }
        tolerance.changed={ [weak self] index in self?.save{$0.tolerance=[1,1.5,2,3,5][index]} }
        range.changed={ [weak self] index in guard let self else{return};var c=self.channel;c.legal=index == 1;self.save{$0.viewingCategory=self.category;$0.viewingChannel=c} }
        black.setButtonType(.switch);black.showsCheck=true;black.target=self;black.action=#selector(toggleBlack)
        NotificationCenter.default.addObserver(self,selector:#selector(reload),name:ICCProfileLibrary.changed,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(reload),name:AnalysisTarget.changed,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(reload),name:.printProfilesChanged,object:nil)
        sync()
    }
    required init?(coder:NSCoder){fatalError()}
    deinit{NotificationCenter.default.removeObserver(self)}
    private func save(_ change:(inout PrintProfileSettings)->Void){
        if var settings=draft{change(&settings);draft=settings;changed?();return}
        do{var settings=try SavedPrintProfiles.load().current;change(&settings);if settings.viewingCategory == nil{settings.viewingCategory=self.category};try SavedPrintProfiles.setCurrent(settings)}catch{NSApp.presentError(error)}
    }
    @objc private func toggleBlack(){save{$0.blackPoint=black.state == .on}}
    @objc private func reload(){sync();changed?()}
    func sync(){
        let printMode=self.category == 1,settings=draft ?? (try? SavedPrintProfiles.load().current) ?? PrintProfileSettings()
        workflow.selectItem(at:self.category)
        if printMode{printNames=PressProfiles.all.map(\.name);if !printNames.contains(settings.press){printNames.append(settings.press)};target.options(printNames,selected:printNames.firstIndex(of:settings.press) ?? 0)}else{let options=self.choices;target.options(options.map{$0.space == ProfileChannel.iccRGB ? $0.name+" · ICC":$0.name},selected:options.firstIndex{$0.space == self.channel.space && $0.press == self.channel.press} ?? 0)}
        heading.stringValue=printMode ? "Printing Condition":(self.category == 2 ? "Video / Cinema Output":"Output Colour Space")
        intent.selectItem(at:RenderingIntent.allCases.firstIndex(of:settings.intent) ?? 0);black.state=settings.blackPoint ? .on:.off;black.isEnabled=settings.intent == .relative
        blackMenu.selectItem(at:settings.blackPoint ? 1:0);blackMenu.isEnabled=settings.intent == .relative
        blackMenu.toolTip=settings.intent == .relative ? "Map source black to output black while retaining shadow detail":"Black Point Compensation Applies To Relative Colorimetric"
        blackMenu.isHidden = !inline || !(printMode || channel.space == ProfileChannel.iccRGB)
        tolerance.options([1.0,1.5,2,3,5].map{self.metric+" \($0)"},selected:[1.0,1.5,2,3,5].firstIndex(of:settings.tolerance) ?? 2)
        range.selectItem(at:self.channel.legal == true ? 1:0)
        [preset,black].forEach{$0.isHidden = !printMode};intent.isHidden = !(printMode || self.channel.space == ProfileChannel.iccRGB);range.isHidden = !self.hasSignalRange
        needsLayout=true
    }
    override func draw(_ dirtyRect:NSRect){if inline{
        // Labels and triggers share the same current geometry, including after a target change.
        let positions=inlinePositions(width:bounds.width,leading:inlineLeadingWidth)
        for ((label, _), (_, frame)) in zip(inlineFields,positions) {
            let width = Design.attributed(label, .controlLabel).size().width
            Design.attributed(label, .controlLabel).draw(x:frame.minX-width-12,baseline:frame.minY+18,width:width)
        }
    }}
    override func layout(){super.layout();let w=bounds.width,printMode=self.category == 1
        if inline{
            heading.isHidden=true;intent.isHidden = !(printMode || channel.space == ProfileChannel.iccRGB);black.isHidden=true;blackMenu.isHidden=intent.isHidden;range.isHidden=true
            for (menu, frame) in inlinePositions(width: w, leading: inlineLeadingWidth) { menu.frame = frame }
            // AppKit moves child controls without necessarily invalidating their parent's labels.
            needsDisplay=true
            return
        }
        blackMenu.isHidden=true
        workflow.frame=NSRect(x:0,y:0,width:w,height:24);heading.frame=NSRect(x:0,y:30,width:w,height:18);target.frame=NSRect(x:0,y:48,width:w,height:24)
        if printMode{intent.frame=NSRect(x:0,y:80,width:w,height:24);black.frame=NSRect(x:0,y:112,width:w,height:24);tolerance.frame=NSRect(x:0,y:144,width:w,height:24)}
        else{if self.hasSignalRange{range.frame=NSRect(x:0,y:80,width:w,height:24)};if !intent.isHidden{intent.frame=NSRect(x:0,y:80,width:w,height:24)};tolerance.frame=NSRect(x:0,y:self.hasSignalRange || !intent.isHidden ? 116:80,width:w,height:24)}
    }
}

/// Guard-band findings use the plotted model, not the separate print ΔE verdict.
private final class HistogramFindingRow: NSView {
    var name="", colour=NSColor.clear, valueText="", advisory=false
    var rowHeight:CGFloat {28}
    override var isFlipped:Bool{true}
    override func draw(_ dirtyRect:NSRect){
        colour.setFill();NSRect(x:0,y:6,width:16,height:16).fill()
        Design.rule.setStroke();NSBezierPath(rect:NSRect(x:0.5,y:6.5,width:15,height:15)).stroke()
        Design.attributed(name,.body).draw(x:24,baseline:20,width:max(0,bounds.width-196))
        Design.attributed(valueText,.caption).draw(x:bounds.width-168,baseline:20,width:146)
        (advisory ? ResultGlyph.warning:ResultGlyph.pass).draw(in:NSRect(x:bounds.width-16,y:6,width:16,height:16))
    }
}

final class WorkspaceHistogramPane: NSView, WorkspaceScrollableContent {
    var layoutSelection:[Int]{get{[model.indexOfSelectedItem,channels.indexOfSelectedItem,showsAllFindings ? 1:0]}set{
        guard newValue.count == 3,HistogramType.offered.indices.contains(newValue[0]) else{return}
        model.selectItem(at:newValue[0]);rebuildChannels();channels.selectItem(at:Self.retainedChannelSelection(newValue[1],channelCount:type.channels.count));showsAllFindings=newValue[2] != 0;refresh()
    }}
    let plot = HistogramView()
    private let targetFilter=AnalysisTargetFilter(frame:.zero)
    private var targetValues:[String:[Double]]=[:]
    private var componentNames:[String]=[]
    private var componentDomain:ClosedRange<Double> = 0...1
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
    private let printingCondition=AnalysisMenu("Histogram Printing Condition",[])
    private var printConditions:[String]=[]
    private var keys: [String] = []
    private var names:[String]=[]
    private var findingRows:[HistogramFindingRow]=[]
    private let failsHeading=Design.text("Fails (0)",.bodyStrong)
    private let warningsToggle=AnalysisButton(title:"Full Colour List",target:nil,action:nil)
    private var showsAllFindings=false
    private var findingHeight:CGFloat {56 + findingRows.reduce(0){$0 + $1.rowHeight}}
    @objc private func toggleWarnings(){showsAllFindings.toggle();refresh()}
    private func rebuildFindings(){
        findingRows.forEach{$0.removeFromSuperview()};findingRows=[]
        let output=AnalysisTarget.channel
        let channel=channels.indexOfSelectedItem > 1 ? channels.indexOfSelectedItem-2:nil
        let records=keys.enumerated().map { index,key -> (Int,[String]) in
            if !output.isPrint,targetValues[key] == nil{return(index,["Output Transform Unavailable"])}
            guard let values=type.values(of:key) else{return(index,["Colour Values Unavailable"])}
            return(index,Self.findings(type:type,values:values,channel:channel))
        }.sorted{ $0.1.isEmpty == $1.1.isEmpty ? $0.0 < $1.0 : !$0.1.isEmpty }
        for (index,messages) in records where showsAllFindings || !messages.isEmpty {
            let row=HistogramFindingRow(frame:.zero)
            row.name=names[index];row.colour=spectrum.indices.contains(index) ? spectrum[index]:Design.hex(keys[index]);row.advisory = !messages.isEmpty
            if let values=targetValues[keys[index]]{
                row.valueText=values.enumerated().filter{channel == nil || channel == $0.offset}.map{componentNames[$0.offset]+" "+componentText($0.element)}.joined(separator:"  ")
                row.toolTip=output.name+" · "+row.valueText
            }else if !output.isPrint{row.valueText="Unavailable";row.toolTip="Output Transform Unavailable";row.advisory=true
            }else if let values=type.values(of:keys[index]){
                let indices=values.indices.filter{type.channels.indices.contains($0) && (channel == nil || channel == $0)}
                row.valueText=indices.map{"\(type == .cmyk && $0 == 3 ? "K":String(type.channels[$0].prefix(1))) \(values[$0])"}.joined(separator:"  ")
                row.toolTip=(indices.map{"\(type.channels[$0]): \(values[$0])"}+messages).joined(separator:" · ")
            }else{row.valueText="Unavailable";row.toolTip="Colour Values Unavailable"}
            row.setAccessibilityElement(true);row.setAccessibilityRole(.staticText);row.setAccessibilityLabel(row.name+", "+(row.toolTip ?? row.valueText));findingRows.append(row);addSubview(row)
        }
        failsHeading.stringValue="Fails (\(records.filter{ !$0.1.isEmpty }.count))"
        failsHeading.toolTip="Channel advisory failures; separate from the output colour-difference verdict"
        warningsToggle.title=(showsAllFindings ? "▾  ":"▸  ")+"Full Colour List (\(records.count))"
        warningsToggle.setAccessibilityLabel(showsAllFindings ? "Collapse Full Colour List":"Show Full Colour List")
        warningsToggle.isEnabled = !records.isEmpty
    }
    static func findings(type:HistogramType,values:[Int],channel:Int?=nil)->[String]{
        guard type == .cmyk || type == .ycbcr else{return []}
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
    var minimumContentHeight: CGFloat { (expanded ? 420+findingHeight : panelPlotHeight+222+findingHeight) }
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        [plot, channels, colours, expandButton,failsHeading,warningsToggle].forEach { addSubview($0) }
        targetFilter.changed={ [weak self] in self?.rebuildChannels();self?.refresh();self?.onConfiguration?() }
        printingCondition.changed={ [weak self] index in
            guard let self,self.printConditions.indices.contains(index) else{return}
            do{var settings=try SavedPrintProfiles.load().current;settings.press=self.printConditions[index];try SavedPrintProfiles.setCurrent(settings);self.refresh()}catch{NSApp.presentError(error)}
        }
        model.changed = { [weak self] _ in self?.rebuildChannels(); self?.refresh(); self?.onConfiguration?() }
        channels.changed = { [weak self] _ in self?.refresh();self?.onConfiguration?() }
        colours.changed = { [weak self] i in
            guard let self else { return }; self.refresh(); self.onColour?(i > 0 ? self.keys[i-1] : nil)
        }
        warningsToggle.showsArrow=false;warningsToggle.target=self;warningsToggle.action=#selector(toggleWarnings)
        rebuildChannels()
    }
    required init?(coder: NSCoder) { fatalError() }
    private var type: HistogramType { AnalysisTarget.channel.isPrint ? .cmyk:.rgb }
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
    private func componentText(_ value:Double)->String{componentDomain.upperBound >= 255 ? String(format:"%.0f",value):String(format:"%.3f",value)}
    private func bin(_ value:Double)->Int{Int((min(1,max(0,(value-componentDomain.lowerBound)/(componentDomain.upperBound-componentDomain.lowerBound)))*1023).rounded())}
    private func refresh() {
        plot.type=type;plot.split=channels.indexOfSelectedItem == 1
        plot.selectedChannel=channels.indexOfSelectedItem > 1 ? channels.indexOfSelectedItem-2:nil
        let output=AnalysisTarget.channel
        targetValues=[:]
        if !output.isPrint{
            for key in keys{
                guard let definition=ColourKeys.definition(of:key) ?? ColourDefinition.of(hex:key) else{continue}
                let values=output.rgb?.values(of:definition.master) ?? output.target?.values(of:definition.master) ?? ICCRGBRendering.components(definition,in:output)
                if var values,values.allSatisfy(\.isFinite){
                    if AnalysisTarget.hasSignalRange{values=values.map{Double(RGBSpace.videoCode($0,legal:output.legal ?? false))}}
                    else if let rgb=output.rgb,rgb != .acescg && rgb != .linearSRGB{values=values.map{$0*255}}
                    targetValues[key]=values
                }
            }
            componentNames=output.target == .grey22 ? ["Grey"]:(output.target == .dciXYZ ? ["X","Y","Z"]:["R","G","B"])
            let all=targetValues.values.flatMap{$0}
            let nominal:Double=AnalysisTarget.hasSignalRange ? 1023:((output.rgb != nil && output.rgb != .acescg && output.rgb != .linearSRGB) ? 255:1)
            componentDomain=min(0,floor(all.min() ?? 0))...max(nominal,ceil(all.max() ?? nominal))
            plot.componentNames=componentNames;plot.componentRanges=componentNames.map{_ in 0...1023}
            let domain=componentDomain
            plot.componentValue={value in let actual=domain.lowerBound+Double(value)/1023*(domain.upperBound-domain.lowerBound);return String(format:domain.upperBound >= 255 ? "%.0f":"%.3f",actual)}
            var counts=componentNames.map{_ in Array(repeating:0,count:1024)}
            for values in targetValues.values{for (index,value) in values.enumerated() where counts.indices.contains(index){counts[index][bin(value)] += 1}}
            plot.counts=counts
            plot.own=colours.indexOfSelectedItem > 0 ? targetValues[keys[colours.indexOfSelectedItem-1]]?.map{bin($0)}:nil
        }else{plot.componentNames=nil;plot.componentRanges=nil;plot.componentValue=nil;plot.counts=Histogram.counts(of:keys,as:type);plot.own=colours.indexOfSelectedItem > 0 ? type.values(of:keys[colours.indexOfSelectedItem-1]):nil}
        let labels=output.isPrint ? type.channels:componentNames
        let selection=Self.retainedChannelSelection(channels.indexOfSelectedItem,channelCount:labels.count)
        channels.options(["Merged","Per Channel"]+labels,selected:selection)
        plot.split=selection == 1;plot.selectedChannel=selection > 1 ? selection-2:nil
        plot.showsGuides=output.isPrint || (AnalysisTarget.hasSignalRange && output.legal == true)
        plot.guideRanges=output.isPrint ? nil:(AnalysisTarget.hasSignalRange && output.legal == true ? componentNames.map{_ in 64...940}:nil)
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
        let offset:CGFloat=(expanded ? 0:32)+0+8
        targetFilter.frame=NSRect(x:12,y:expanded ? 32:64,width:w,height:0)
        colours.frame = NSRect(x:12,y:32+offset,width:w,height:24)
        model.frame = .zero
        channels.frame = NSRect(x:12,y:64+offset,width:w,height:24)
        printingCondition.frame = .zero
        plot.frame = NSRect(x:12,y:100+offset,width:w,height:expanded ? max(140,bounds.height-284-findingHeight-0) : panelPlotHeight)
        var fy=plot.frame.maxY+82
        failsHeading.frame=NSRect(x:12,y:fy+4,width:w,height:20);fy += 28
        for row in findingRows where row.advisory{row.frame=NSRect(x:12,y:fy,width:w,height:row.rowHeight);fy += row.rowHeight}
        warningsToggle.isHidden=false
        warningsToggle.frame=NSRect(x:12,y:fy,width:w,height:28);fy += 28
        for row in findingRows where !row.advisory{row.frame=NSRect(x:12,y:fy,width:w,height:row.rowHeight);fy += row.rowHeight}
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
        Design.attributed(AnalysisTarget.channel.isPrint ? type.scale:String(format:"Target Components %.3f To %.3f",componentDomain.lowerBound,componentDomain.upperBound),.caption,colour:Design.quiet).draw(x:12,baseline:y,width:bounds.width-24)
        let guide = AnalysisTarget.hasSignalRange && AnalysisTarget.channel.legal == true ? "10-Bit Legal RGB · 64 To 940" : type == .ycbcr ? "Signal Levels · Legal Bands" : (type == .cmyk ? "Channel Levels · Advisory Bands" : "Full Channel Range")
        Design.attributed(guide,.caption,colour:Design.quiet).draw(x:12,baseline:y+24,width:bounds.width-24)
        Design.attributed("Bright: Selected · Dim: Palette",.caption,colour:Design.quiet).draw(x:12,baseline:y+48,width:bounds.width-24)
    }
}

final class WorkspaceBloomPane: NSView, WorkspaceScrollableContent {
    let chart = PrintBloomView(frame:.zero)
    private let targetFilter=AnalysisTargetFilter(frame:.zero)
    private var reloadTarget:(()->Void)?
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
    var minimumContentHeight: CGFloat {expanded ? 500:104+320+18-Design.Text.caption.font().descender}
    override var isFlipped: Bool { true }
    override init(frame:NSRect) {
        super.init(frame:frame); chart.compact=true;chart.showsExpandControl=false;black.setButtonType(.switch);black.showsCheck=true
        [chart,order,expandButton].forEach { addSubview($0) }
        findingsScroll.documentView=findings;findingsScroll.drawsBackground=false;findingsScroll.hasVerticalScroller=true;findingsScroll.autohidesScrollers=true;findingsScroll.isHidden=true;addSubview(findingsScroll)
        targetFilter.changed={ [weak self] in self?.reloadTarget?() }
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
        reloadTarget={ [weak self] in self?.update(palette,library:library,selected:selected) }
        title=palette?.name ?? "Select A Palette"
        spectrum=(palette?.entries ?? []).compactMap{library.definition(of:$0.hex)?.master.display}
        do { settings=try SavedPrintProfiles.load().current } catch { summary="Print Profiles Unavailable";chart.items=[];needsDisplay=true;return }
        conditions=PressProfiles.all.map(\.name);if !conditions.contains(settings.press){conditions.append(settings.press)}
        press.options(conditions,selected:conditions.firstIndex(of:settings.press) ?? 0)
        intent.selectItem(at:RenderingIntent.allCases.firstIndex(of:settings.intent) ?? 0)
        tolerance.selectItem(at:[1,1.5,2,3,5].firstIndex(of:settings.tolerance) ?? -1)
        if tolerance.indexOfSelectedItem < 0 { tolerance.title="ΔE \(settings.tolerance)" }
        black.state=settings.blackPoint ? .on:.off; black.isEnabled=settings.intent == .relative
        chart.order=PrintBloomView.Order(rawValue:AppPreferences.shared.string(forKey:"workspace.bloomOrder") ?? "") ?? .palette
        order.selectItem(at:PrintBloomView.Order.allCases.firstIndex(of:chart.order) ?? 0)
        chart.tolerance=settings.tolerance;chart.selected=selected;chart.differenceMetric=AnalysisTarget.metric;chart.outputName=AnalysisTarget.channel.name
        var seen=Set<String>()
        chart.items=(palette?.entries ?? []).compactMap { entry in
            guard seen.insert(entry.hex).inserted, let definition=library.definition(of:entry.hex) else{return nil}
            let result=Rendering.of(definition,in:AnalysisTarget.channel)
            let build=AnalysisTarget.channel.isPrint ? PrintBuild.of(definition.master,press:settings.press,intent:settings.intent,blackPoint:settings.blackPoint):nil
            return PrintBloomView.Item(id:entry.hex,name:library.name(of:entry.hex,in:palette?.id),master:definition.master.display,printed:result.shown?.display,delta:result.difference,ink:build?.totalInk)
        }
        chart.selected = selected.flatMap { key in chart.items.contains{$0.id==key} ? key:nil } ?? chart.items.first?.id
        findings.update(item:chart.items.first{$0.id==chart.selected},tolerance:settings.tolerance,condition:AnalysisTarget.channel.name,isPrint:AnalysisTarget.channel.isPrint,metric:AnalysisTarget.metric)
        let valid=chart.items.compactMap(\.delta), passes=valid.filter{$0 <= settings.tolerance}.count
        summary=chart.items.isEmpty ? "Select A Palette To Predict Output" : "\(passes)/\(valid.count) Within \(AnalysisTarget.metric) \(settings.tolerance) · \(chart.items.count-valid.count) Unavailable"
        needsLayout=true;needsDisplay=true
    }
    override func layout(){
        super.layout();let w=max(20,bounds.width-24)
        expandButton.frame=NSRect(x:bounds.width-92,y:2,width:80,height:26)
        targetFilter.frame=NSRect(x:12,y:64,width:w,height:0)
        if expanded {
            let reportWidth=min(240,max(170,w*0.27))
            findingsScroll.frame=NSRect(x:12,y:80+0,width:reportWidth,height:max(0,bounds.height-200-0))
            findings.fit(width:findingsScroll.contentSize.width,minimumHeight:findingsScroll.contentSize.height)
            chart.frame=NSRect(x:reportWidth+28,y:108+0,width:max(80,bounds.width-reportWidth-40),height:max(280,bounds.height-240-0))
            let orderWidth=min(220,chart.frame.width)
            order.frame=NSRect(x:chart.frame.midX-orderWidth/2,y:76+0,width:orderWidth,height:24)
            let sw=min(spectrumWidth,max(40,chart.frame.width-24))
            spectrumRect=NSRect(x:chart.frame.midX-sw/2,y:bounds.height-76,width:sw,height:64)
        } else {
            spectrumRect=NSRect(x:12,y:36,width:w,height:20)
            order.frame=NSRect(x:12,y:72+0,width:w,height:24)
            chart.frame=NSRect(x:12,y:104+0,width:w,height:320)
        }
    }
    override func draw(_ dirtyRect:NSRect){
        Design.attributed(title,.bodyStrong).draw(x:12,baseline:21,width:bounds.width-(expanded ? 100:110))
        PaletteSpectrum.draw(spectrum,in:spectrumRect)
        if expanded {
            let item=chart.items.first{$0.id==chart.selected}, width=findingsScroll.contentSize.width
            Design.attributed(item?.name ?? "Select A Colour",.bodyStrong).draw(x:12,baseline:bounds.height-68,width:width)
            let detail=item?.delta.map{String(format:"%@ %.2f",AnalysisTarget.metric,$0)} ?? "Prediction Unavailable"
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
    private let table=ClickCursorTableView(), list=FittedScrollView(), detail=FittedScrollView()
    private let close=WorkspaceExpandButton(closes:true)
    private var palettes:[Swatch]=[]
    private var selectedPalette:UUID?
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
    func update(_ palettes:[Swatch],selected:UUID?){
        guard palettes != self.palettes || selected != selectedPalette else{return}
        updatingSelection=true;defer{updatingSelection=false}
        let contentsChanged=palettes != self.palettes
        self.palettes=palettes;selectedPalette=selected
        if contentsChanged{table.reloadData()}
        if let index=palettes.firstIndex(where:{$0.id==selected}){table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)}else{table.deselectAll(nil)}
    }
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
        var link:URL?=nil,toggle:Toggle?=nil,enabled=true,relocateID:String?=nil,warning=false,savedID:UUID?=nil,saveNew=false
    }
    private let button=DropdownButton()
    private let inlineForm=AnalysisTargetFilter(frame:.zero)
    var headerMode=false {didSet{inlineForm.isHidden = !headerMode;needsLayout=true}}
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
    private var presetWidth: CGFloat { ceil(Design.attributed(button.title, .body).size().width) + 20 }
    private var presetFieldWidth: CGFloat { Design.attributed("Preset", .controlLabel).size().width + 12 + presetWidth }
    func headerHeight(forWidth width: CGFloat) -> CGFloat { inlineForm.inlineHeight(forWidth: width, leading: presetFieldWidth + 24) }
    var selectedChannel:ProfileChannel? {preview}
    private var editingProfile=false
    var overlayWindows:[NSWindow] {proofMenu.map{[$0]} ?? []}
    func handleOverlayEscape()->Bool{let editing=editingProfile;dismissOverlay();if editing{openMenu()};return true}
    func dismissOverlay(){if let proofMenu{proofMenu.parent?.removeChildWindow(proofMenu);proofMenu.orderOut(nil)};proofMenu=nil;editingProfile=false;Overlays.closed(self)}
    override var isFlipped:Bool{true}
    override init(frame:NSRect){
        super.init(frame:frame);addSubview(button);button.borderless=true;button.title=selectionTitle;button.target=self;button.action=#selector(openMenu)
        button.setAccessibilityLabel("Preset");button.font=Design.Text.body.font()
        addSubview(inlineForm, positioned:.below, relativeTo:button);inlineForm.inline=true;inlineForm.isHidden=true;inlineForm.changed={ [weak self] in self?.configure(library:self?.library ?? Library(),palette:self?.palette);self?.onChange?() }

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
        defer { needsLayout = true; window?.contentView?.needsLayout = true }
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
                heading("Proof Options")
                append("Simulate Paper White",Choice(profile:profile.id,channel:nil,group:profile.name,toggle:.paper,enabled:!channels.isEmpty))
                append("K-only · Use Selected CMYK Condition",Choice(profile:profile.id,channel:nil,group:profile.name,toggle:.kOnly,enabled:!installed.isEmpty))
                let missing=PrintTargetStandards.all.filter{!$0.installed(in:installed)}
                if !missing.isEmpty{heading("Not Installed · Get Profiles From Publisher")}
                for standard in missing {append(standard.name+" · "+standard.publisher+"…",Choice(profile:profile.id,channel:nil,group:profile.name,link:standard.url))}
            }
        }
        if let saved=try? SavedPrintProfiles.load(){
            let prefix=[SwissDropdown.MenuPanel.heading("My Profiles")]+saved.profiles.map(\.name)+["Save Profile…",SwissDropdown.MenuPanel.divider]
            let savedChoices:[Choice?]=[nil]+saved.profiles.map{Choice(profile:nil,channel:$0.settings.viewingChannel ?? $0.settings.channel,group:"My Profiles",savedID:$0.id)}+[Choice(profile:nil,channel:nil,group:"My Profiles",saveNew:true),nil]
            items=prefix+items;choices=savedChoices+choices
        }
        let savedProfile=AppPreferences.shared.string(forKey:"workspace.channelProfile").flatMap(UUID.init(uuidString:))
        let space=AppPreferences.shared.string(forKey:"workspace.previewChannel"),press=AppPreferences.shared.string(forKey:"workspace.targetPress")
        let masterIndex=choices.firstIndex{ $0?.group == "" } ?? 0
        chosenIndex=space == nil ? masterIndex:(choices.firstIndex{choice in
            guard let choice,let channel=choice.channel else{return false}
            return choice.profile == savedProfile && channel.space == space && (!(channel.isPrint || channel.space == ProfileChannel.iccRGB) || channel.press == press)
        } ?? masterIndex)
        let selected=choices[chosenIndex];preview=selected?.channel
        if let document=try? SavedPrintProfiles.load(),document.current.viewingCategory != nil{
            preview=AnalysisTarget.channel
            if let index=choices.firstIndex(where:{$0?.channel?.space == preview?.space && $0?.channel?.press == preview?.press}){chosenIndex=index;proofMenu?.setCheckedIndexes([index])}
            selectionTitle=document.profiles.first(where:{$0.id == document.selected})?.name ?? AnalysisTarget.channel.name;button.title=selectionTitle;button.toolTip="Viewing Proof · "+selectionTitle;needsDisplay=true;return
        }
        selectionTitle=preview.map{(selected?.group ?? "")+" · "+Self.previewTitle($0)+(paper && $0.isPrint ? " · Paper White":"")} ?? "Master Colours"
        button.title=selectionTitle;button.toolTip="Colour Target · "+selectionTitle;needsDisplay=true
    }
    func showProfiles(){dismissOverlay();openMenu()}
    @objc private func openMenu(){
        guard let win=window else{return}
        if let proofMenu,proofMenu.isVisible{dismissOverlay();return}
        dismissOverlay();PressProfiles.refresh();configure(library:library,palette:palette)
        let snapshot=choices,width:CGFloat=440
        let panel=SwissDropdown.MenuPanel(items:items,chosen:"",width:width,chosenIndex:chosenIndex){[weak self] index in
            guard let self,snapshot.indices.contains(index),let choice=snapshot[index] else{return}
            if choice.saveNew { self.saveProfile(); return }
            if let id=choice.savedID{do{try SavedPrintProfiles.select(id);self.onChange?()}catch{NSApp.presentError(error)};return}
            if let id=choice.relocateID {self.dismissOverlay();self.onLocateICC?(id);return}
            if let link=choice.link{self.dismissOverlay();NSWorkspace.shared.open(link);return}
            if let toggle=choice.toggle {
                let key=toggle == .paper ? "workspace.targetPaperWhite":"workspace.targetKOnly"
                AppPreferences.shared.set(!(toggle == .paper ? self.paper:self.kOnly),forKey:key)
            } else {
                AppPreferences.shared.set(choice.profile?.uuidString,forKey:"workspace.channelProfile")
                AppPreferences.shared.set(choice.channel?.space,forKey:"workspace.previewChannel")
                AppPreferences.shared.set(choice.channel?.press,forKey:"workspace.targetPress")
                if let channel=choice.channel{do{var settings=try SavedPrintProfiles.load().current;settings.viewingCategory=AnalysisTarget.category(for:channel);settings.viewingChannel=channel.isPrint ? nil:channel;if channel.isPrint{settings.press=channel.press ?? PressProfiles.generic};try SavedPrintProfiles.setCurrent(settings)}catch{NSApp.presentError(error)}}
            }
            self.onChange?()
        }
        panel.configure(disabled:Set(choices.indices.filter{choices[$0]?.enabled != true}))
        panel.setWarnings(Set(choices.indices.filter{choices[$0]?.warning == true}))
        var checked:Set<Int>=[chosenIndex]
        for (index,choice) in choices.enumerated(){if choice?.toggle == .paper && paper || choice?.toggle == .kOnly && kOnly {checked.insert(index)}}
        panel.setCheckedIndexes(checked)
        let anchor=win.convertToScreen(button.convert(button.bounds,to:nil));panel.place(anchoredTo:anchor,within:win)
        for (index,choice) in snapshot.enumerated(){if let id=choice?.savedID{
            panel.setActions(for:index,symbols:[("pencil","Edit Profile"),("square.and.arrow.up","Export Profile"),("trash","Remove Profile")]){[weak self] action in
                do{guard let profile=try SavedPrintProfiles.load().profiles.first(where:{$0.id == id}) else{return}
                    if action == 0{self?.editProfile(profile)}else{try SavedPrintProfiles.select(id)}
                    if action != 0{let exchange=PrintProfileSelector(compact:true);if action == 1{exchange.exportFile()}else{exchange.confirmRemoval(profile)}}
                }catch{NSApp.presentError(error)}
            }
        }}
        win.addChildWindow(panel,ordered:.above);proofMenu=panel;panel.makeKeyAndOrderFront(nil);Overlays.opened(self)
    }
    func reportUnavailable(_ count:Int){
        button.title=selectionTitle+(count > 0 ? " · Unavailable":"")
        button.toolTip="Colour Target · "+selectionTitle+(count > 0 ? " · Selected ICC unavailable; master display retained, target values unavailable":"")
    }
    private func saveProfile() { editProfile(nil) }
    private func editProfile(_ original:SavedPrintProfile?) {
        guard let owner=window else{return}
        do {
            var settings=try original?.settings ?? SavedPrintProfiles.load().current
            if settings.viewingCategory == nil{settings.viewingCategory=AnalysisTarget.category;settings.viewingChannel=AnalysisTarget.channel.isPrint ? nil:AnalysisTarget.channel}
            dismissOverlay()
            let form=ViewingProfileDropdownForm(original:original,settings:settings)
            let panel=SwissDropdown.MenuPanel(items:[],chosen:"",width:440){_ in}
            let arrange:()->Void = { [weak form,weak panel,weak self,weak owner] in
                guard let form,let panel,let self,let owner else{return}
                let height=form.contentHeight
                let scroll=FittedScrollView(frame:NSRect(x:0,y:0,width:440,height:height));scroll.drawsBackground=true;scroll.backgroundColor=Design.card;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
                scroll.wantsLayer=true;scroll.layer?.borderColor=Design.rule.cgColor;scroll.layer?.borderWidth=1
                form.frame=NSRect(x:0,y:0,width:440-QuietScroller.lane,height:height);scroll.documentView=form
                panel.contentView=scroll;panel.setContentSize(NSSize(width:440,height:height))
                let anchor=owner.convertToScreen(self.button.convert(self.button.bounds,to:nil));panel.place(anchoredTo:anchor,within:owner)
            }
            form.onResize={arrange()}
            form.onCancel={ [weak self] in self?.dismissOverlay();self?.openMenu() }
            form.onSave={ [weak self,weak form] name,draft in
                do {
                    var profile=original ?? SavedPrintProfile(name:name,description:"",settings:draft)
                    profile.name=name;profile.settings=draft
                    let saved=try SavedPrintProfiles.save(profile);try SavedPrintProfiles.select(saved.id)
                    self?.onChange?();self?.dismissOverlay()
                    // Reopen after the Save click and proof-change notifications finish routing.
                    DispatchQueue.main.async { [weak self] in self?.showProfiles() }
                }catch{form?.showError(error.localizedDescription)}
            }
            arrange();owner.addChildWindow(panel,ordered:.above);proofMenu=panel;editingProfile=true;panel.makeKeyAndOrderFront(nil);Overlays.opened(self);form.focusName()
        }catch{NSApp.presentError(error)}
    }
    override func layout(){
        super.layout();let left=Design.attributed("Preset",.controlLabel).size().width+12
        button.frame=NSRect(x:left,y:headerMode ? 3:(bounds.height-28)/2,width:headerMode ? presetWidth:max(0,bounds.width-left),height:28)
        inlineForm.inlineLeadingWidth = presetFieldWidth + 24
        inlineForm.frame = bounds
        inlineForm.needsLayout = true
        inlineForm.needsDisplay = true
        needsDisplay = true
    }
    override func draw(_ dirtyRect:NSRect){
        let width=Design.attributed("Preset",.controlLabel).size().width
        Design.attributed("Preset",.controlLabel).draw(x:0,baseline:headerMode ? 21:bounds.midY+4,width:width)
    }
}

private final class AnalysisButton:ClickCursorButton {
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
final class WorkspaceExpandButton:ClickCursorButton {
    var run:(()->Void)?
    private let closes:Bool
    init(closes:Bool=false){self.closes=closes;super.init(frame:.zero);isBordered=false;title=closes ? "Close":"Expand";setAccessibilityLabel(title);toolTip=closes ? "Close Expanded Panel · Esc":"Expand Panel";target=self;action=#selector(invoke)}
    required init?(coder:NSCoder){fatalError()}
    @objc private func invoke(){run?()}
    override var isFlipped:Bool{true}
    override func draw(_ dirtyRect:NSRect){Design.attributed((closes ? "×  ":"⤢  ")+title,.body,colour:isHighlighted ? Design.quiet:Design.ink).draw(x:4,baseline:19,width:bounds.width-8)}
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
}

/// Palette spectra use the same master colours and strip geometry in both analysis panes and in railInfo.
enum PaletteSpectrum {
    static func draw(_ colours:[NSColor],in rect:NSRect){
        guard !colours.isEmpty else{return}
        let width=rect.width/CGFloat(colours.count)
        for (i,colour) in colours.enumerated(){colour.setFill();NSRect(x:rect.minX+CGFloat(i)*width,y:rect.minY,width:width,height:rect.height).fill()}
    }
}

/// Dedicated global viewing-proof editor. Asset data stays in its existing catalogue files.
final class ProfileRailPane:NSView,WorkspaceScrollableContent,NSTableViewDataSource,NSTableViewDelegate {
    private let title=Design.text("Saved Viewing Profiles",.bodyStrong)
    private let list=FittedScrollView(),table=ClickCursorTableView()
    private let name=NSTextField(string:"")
    private let form=AnalysisTargetFilter(frame:.zero)
    private let status=Design.text("",.caption,colour:Design.quiet,wraps:true)
    private let actions=["Save New","Update","Rename","Duplicate","Remove","Import…","Export…"].map{SwissButton($0,.secondary)}
    private let exchange=PrintProfileSelector(compact:true)
    private var profiles:[SavedPrintProfile]=[],editingID:UUID?,refreshing=false
    var isPopupDesigner=false {didSet{needsLayout=true}}
    var minimumContentHeight:CGFloat{320+form.height+144}
    override var isFlipped:Bool{true}
    override init(frame:NSRect){super.init(frame:frame)
        [title,list,name,form,status].forEach{addSubview($0)};actions.forEach{addSubview($0)}
        let column=NSTableColumn(identifier:.init("profile"));table.addTableColumn(column);table.headerView=nil;table.rowHeight=28;table.intercellSpacing = .zero;table.backgroundColor=Design.card;table.dataSource=self;table.delegate=self;table.setAccessibilityLabel("Saved Viewing Profiles")
        list.documentView=table;list.drawsBackground=false;list.hasVerticalScroller=true;list.autohidesScrollers=true
        name.font=Design.Text.bodyStrong.font();name.textColor=Design.ink;name.drawsBackground=false;name.isBordered=false;name.focusRingType = .none;name.placeholderAttributedString=Design.attributed("Profile Name",.bodyStrong,colour:Design.quiet);name.setAccessibilityLabel("Viewing Profile Name");name.target=self;name.action=#selector(renameFromField)
        for (index,button) in actions.enumerated(){button.target=self;button.action=#selector(act(_:));button.tag=index}
        form.changed={ [weak self] in self?.reload() }
        NotificationCenter.default.addObserver(self,selector:#selector(reload),name:.printProfilesChanged,object:nil)
        reload()
    }
    required init?(coder:NSCoder){fatalError()}
    deinit{NotificationCenter.default.removeObserver(self)}
    @objc private func reload(){
        guard !refreshing else{return};refreshing=true;defer{refreshing=false}
        do{let document=try SavedPrintProfiles.load();profiles=document.profiles
            if let id=document.selected,let selected=profiles.first(where:{$0.id == id}){editingID=id;name.stringValue=selected.name}
            if let id=editingID,!profiles.contains(where:{$0.id == id}){editingID=nil;name.stringValue=""}
            table.reloadData();if let index=profiles.firstIndex(where:{$0.id == editingID}){table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)}
            status.stringValue=document.selected == nil ? "Current Settings · Save New Or Update":"Selected Viewing Proof"
        }catch{status.stringValue=error.localizedDescription}
        for index in [1,2,3,4]{actions[index].isEnabled=editingID != nil};needsLayout=true
        if let scroll=enclosingScrollView{setFrameSize(NSSize(width:frame.width,height:max(scroll.contentSize.height,minimumContentHeight)))}
        var parent=superview;while let view=parent{if let rail=view as? WorkspaceRail{rail.arrange();break};parent=view.superview}
    }
    func numberOfRows(in tableView:NSTableView)->Int{profiles.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView?{
        let profile=profiles[row],entry=ProfileEntry(frame:.zero);entry.label.stringValue=profile.name
        entry.onAction={ [weak self] action in
            guard let self else{return}
            do{
                // Update captures the draft before selecting the row replaces it.
                let draft=try SavedPrintProfiles.load().current
                if action == 0{var updated=profile;updated.settings=draft;let saved=try SavedPrintProfiles.save(updated);try SavedPrintProfiles.select(saved.id)}
                else{try SavedPrintProfiles.select(profile.id);self.editingID=profile.id;self.name.stringValue=profile.name
                    switch action{
                    case 1:self.window?.makeFirstResponder(self.name);self.name.selectText(nil);self.status.stringValue="Edit The Name, Then Choose Rename"
                    case 2:self.exchange.reload();self.exchange.exportFile()
                    default:self.exchange.confirmRemoval(profile)
                    }
                }
            }catch{self.status.stringValue=error.localizedDescription}
        };return entry
    }
    private final class ProfileEntry:NSView{
        let label=Design.text("",.body)
        var onAction:((Int)->Void)?
        private var buttons:[NSButton]=[]
        override init(frame:NSRect){super.init(frame:frame);addSubview(label);label.lineBreakMode = .byTruncatingTail
            for (index,item) in [("arrow.clockwise","Update Profile"),("pencil","Rename Profile"),("square.and.arrow.up","Export Profile"),("trash","Remove Profile")].enumerated(){let button=ClickCursorButton(frame:.zero);button.isBordered=false;button.title="";button.image=NSImage(systemSymbolName:item.0,accessibilityDescription:item.1);button.imagePosition = .imageOnly;button.contentTintColor=Design.ink;button.toolTip=item.1;button.setAccessibilityLabel(item.1);button.tag=index;button.target=self;button.action=#selector(performAction(_:));addSubview(button);buttons.append(button)}
        }
        required init?(coder:NSCoder){fatalError()}
        @objc private func performAction(_ sender:NSButton){onAction?(sender.tag)}
        override func layout(){super.layout();let h=label.intrinsicContentSize.height;label.frame=NSRect(x:16,y:(bounds.height-h)/2,width:max(0,bounds.width-136),height:h)
            for (index,button) in buttons.enumerated(){button.frame=NSRect(x:bounds.width-116+CGFloat(index)*28,y:(bounds.height-28)/2,width:28,height:28)}
        }
    }
    func tableView(_ tableView:NSTableView,rowViewForRow row:Int)->NSTableRowView?{WorkspacePanelRow()}
    func tableViewSelectionDidChange(_ notification:Notification){guard !refreshing,profiles.indices.contains(table.selectedRow) else{return};do{try SavedPrintProfiles.select(profiles[table.selectedRow].id)}catch{status.stringValue=error.localizedDescription}}
    @objc private func renameFromField(){guard editingID != nil else{return};act(actions[2])}
    @objc private func act(_ sender:NSButton){
        window?.makeFirstResponder(nil)
        do{let document=try SavedPrintProfiles.load();let original=profiles.first{$0.id == editingID}
            var settings=document.current;settings.viewingCategory=AnalysisTarget.category;settings.viewingChannel=AnalysisTarget.channel.isPrint ? nil:AnalysisTarget.channel
            switch sender.tag{
            case 0,1,2:
                let text=name.stringValue.trimmingCharacters(in:.whitespacesAndNewlines);guard !text.isEmpty else{status.stringValue="Give This Profile A Name";window?.makeFirstResponder(name);return}
                var profile=sender.tag == 0 ? SavedPrintProfile(name:text,description:"",settings:settings):(original ?? SavedPrintProfile(name:text,description:"",settings:settings))
                profile.name=text;if sender.tag != 2{profile.settings=settings};let saved=try SavedPrintProfiles.save(profile);try SavedPrintProfiles.select(saved.id)
            case 3:if let original{let copy=try SavedPrintProfiles.duplicate(original.id);try SavedPrintProfiles.select(copy.id)}
            case 4:if let original{exchange.confirmRemoval(original)}
            case 5:exchange.importFile()
            default:exchange.reload();exchange.exportFile()
            }
            reload()
        }catch{status.stringValue=error.localizedDescription}
    }
    override func layout(){super.layout();let w=max(0,bounds.width-32)
        title.frame=NSRect(x:16,y:16,width:w,height:24);list.frame=NSRect(x:0,y:48,width:bounds.width,height:140);table.tableColumns.first?.width=list.contentSize.width;table.setFrameSize(NSSize(width:list.contentSize.width,height:max(140,CGFloat(profiles.count)*28)))
        name.frame=NSRect(x:16,y:204,width:w,height:32);form.frame=NSRect(x:16,y:252,width:w,height:form.height)
        let start=form.frame.maxY+24,half=(w-16)/2
        let visible=isPopupDesigner ? [0,3,5]:Array(actions.indices)
        for (index,button) in actions.enumerated(){button.isHidden = !visible.contains(index)}
        for (position,index) in visible.enumerated(){actions[index].frame=NSRect(x:16+CGFloat(position%2)*(half+16),y:start+CGFloat(position/2)*32,width:half,height:28)}
        status.frame=NSRect(x:16,y:start+(isPopupDesigner ? 72:136),width:w,height:40)
    }
    override func draw(_ dirtyRect:NSRect){Design.rule.setFill();for y in [CGFloat(196),CGFloat(240)]{NSRect(x:16,y:y,width:max(0,bounds.width-32),height:1).fill()}}
}

/// A private draft: changing these controls never changes the active proof until Save succeeds.
private final class ViewingProfileDropdownForm:NSView {
    private let heading=Design.text("My Profiles",.bodyStrong)
    private let title: NSTextField
    private var profileLabels:[NSTextField]=[]
    private let label=Design.text("Profile Name",.caption)
    private let name=NSTextField(string:"")
    private let form=AnalysisTargetFilter(frame:.zero)
    private let save=SwissButton("Save Profile",.primary),cancel=SwissButton("Cancel",.secondary)
    private let status=Design.text("",.caption,colour:Design.quiet,wraps:true)
    var onResize:(()->Void)?,onCancel:(()->Void)?,onSave:((String,PrintProfileSettings)->Void)?
    var contentHeight:CGFloat{form.height+228+CGFloat(profileLabels.count)*30}
    init(original:SavedPrintProfile?,settings:PrintProfileSettings){
        title=Design.text(original == nil ? "Save Viewing Profile":"Edit Viewing Profile",.bodyStrong)
        super.init(frame:.zero)
        [heading,title,label,name,form,save,cancel,status].forEach{addSubview($0)}
        profileLabels=((try? SavedPrintProfiles.load().profiles) ?? []).map{Design.text($0.name,.body)}
        profileLabels.forEach{addSubview($0)}
        name.stringValue=original?.name ?? "";name.font=Design.Text.body.font();name.textColor=Design.ink;name.drawsBackground=false;name.isBordered=false;name.focusRingType = .none;name.setAccessibilityLabel("Profile Name")
        form.draft=settings;form.changed={ [weak self] in self?.needsLayout=true;self?.onResize?() }
        save.target=self;save.action=#selector(commit);cancel.target=self;cancel.action=#selector(back)
    }
    required init?(coder:NSCoder){fatalError()}
    override var isFlipped:Bool{true}
    func focusName(){window?.makeFirstResponder(name);name.selectText(nil)}
    func showError(_ message:String){status.stringValue=message}
    @objc private func back(){onCancel?()}
    @objc private func commit(){let value=name.stringValue.trimmingCharacters(in:.whitespacesAndNewlines);guard !value.isEmpty else{showError("Enter A Profile Name");focusName();return};if let draft=form.draft{onSave?(value,draft)}}
    override func layout(){super.layout();let w=max(0,bounds.width-32),offset=CGFloat(profileLabels.count)*30
        heading.frame=NSRect(x:16,y:16,width:w,height:20)
        for (i,label) in profileLabels.enumerated(){label.frame=NSRect(x:16,y:44+CGFloat(i)*30,width:w,height:24)}
        title.frame=NSRect(x:16,y:52+offset,width:w,height:20)
        label.frame=NSRect(x:16,y:84+offset,width:w,height:20);name.frame=NSRect(x:16,y:108+offset,width:w,height:28)
        form.frame=NSRect(x:16,y:152+offset,width:w,height:form.height)
        save.frame=NSRect(x:16,y:form.frame.maxY+16,width:156,height:28);cancel.frame=NSRect(x:188,y:form.frame.maxY+16,width:100,height:28)
        status.frame=NSRect(x:16,y:form.frame.maxY+48,width:w,height:28)
    }
    override func draw(_ dirtyRect:NSRect){Design.card.setFill();bounds.fill();Design.rule.setFill();NSRect(x:16,y:44+CGFloat(profileLabels.count)*30,width:max(0,bounds.width-32),height:1).fill();NSRect(x:16,y:name.frame.maxY+1,width:max(0,bounds.width-32),height:1).fill()}
}
