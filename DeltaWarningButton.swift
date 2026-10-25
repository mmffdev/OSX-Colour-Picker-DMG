import AppKit

/// Global comparison state. Illuminant choices are requests, never synthetic relighting.
enum PaletteViewing {
    enum Illuminant:String,CaseIterable {case normal="Normal",d50="D50",d65="D65",a="A"}
    static var illuminant:Illuminant {
        get{Illuminant(rawValue:AppPreferences.shared.string(forKey:"workspace.viewingIlluminant") ?? "") ?? .normal}
        set{AppPreferences.shared.set(newValue.rawValue,forKey:"workspace.viewingIlluminant");NotificationCenter.default.post(name:.prefsDidChange,object:nil)}
    }
    static var enabled:Bool{Prefs.deltaWarningsEnabled || illuminant != .normal}
    struct Row {let label:String;let colours:[NSColor]?;let unavailable:String?;var cells:[NSColor?]? = nil}
    static func rows(original:[NSColor],proof:[NSColor]?,output:Bool,illuminant:Illuminant,spectral:[NSColor?]? = nil)->[Row]{
        var result=[Row(label:"Original",colours:original,unavailable:nil)]
        if output {result.append(Row(label:"Output Proof",colours:proof?.count == original.count ? proof:nil,unavailable:"Unavailable — Select A Supported Output Target"))}
        if illuminant != .normal {
            let cells=spectral?.count == original.count ? spectral:nil
            result.append(Row(label:illuminant.rawValue,colours:nil,unavailable:"Unavailable — Link Spectral Measurement",cells:cells))
        }
        return result
    }
    static var accessibilitySummary:String{"Output Proof "+(Prefs.deltaWarningsEnabled ? "On":"Off")+". Viewing Illuminant "+illuminant.rawValue+(illuminant == .normal ? ".":". Linked spectral measurements only.")}
    static let explanation="Display predictions, not measured approvals. Original: stored colour preview. Output Proof: selected target prediction. D50, D65 and A: linked opaque, non-fluorescent material spectra, ICC LWL 10 nm weights and the observer selected in Settings. Fixed D65 display reference includes the illuminant cast; no ambient-adaptation model. Unlinked or changed colours remain unavailable. Out-of-display-gamut predictions are clipped. 10° XYZ uses standard 2° RGB for an approximate screen preview, not an exact observer conversion. Δ describes output difference, not illuminant difference."
    static func draw(original:[NSColor],proof:[NSColor]?,spectral:[NSColor?]? = nil,showsIlluminant:Bool = true,in rect:NSRect){
        guard !original.isEmpty,rect.width>0,rect.height>0 else{return}
        let rows=rows(original:original,proof:proof,output:Prefs.deltaWarningsEnabled,illuminant:showsIlluminant ? illuminant:.normal,spectral:spectral)
        let gutter=min(96,max(40,rect.width-48)),height=rect.height/CGFloat(rows.count)
        NSGraphicsContext.saveGraphicsState();NSBezierPath(rect:rect).addClip()
        for (index,row) in rows.enumerated(){
            let band=NSRect(x:rect.minX,y:rect.minY+CGFloat(index)*height,width:rect.width,height:height)
            let spectrum=NSRect(x:band.minX+gutter,y:band.minY,width:max(0,band.width-gutter),height:height)
            Design.card.setFill();band.fill()
            Design.attributed(row.label,.caption,colour:Design.ink).draw(x:band.minX+4,baseline:band.midY+4,width:max(0,gutter-8))
            if let cells=row.cells,!cells.isEmpty {
                let width=spectrum.width/CGFloat(cells.count)
                for (i,colour) in cells.enumerated() {
                    let cell=NSRect(x:spectrum.minX+CGFloat(i)*width,y:spectrum.minY,width:width+0.5,height:spectrum.height)
                    (colour ?? Design.mist).setFill();cell.fill()
                    if colour == nil {Design.attributed("No Measurement",.caption,colour:Design.ink).draw(x:cell.minX+6,baseline:cell.midY+4,width:max(0,cell.width-12))}
                }
            } else if let colours=row.colours,!colours.isEmpty {
                let width=spectrum.width/CGFloat(colours.count)
                for (i,colour) in colours.enumerated(){colour.setFill();NSRect(x:spectrum.minX+CGFloat(i)*width,y:spectrum.minY,width:width+0.5,height:spectrum.height).fill()}
            }else{
                Design.mist.setFill();spectrum.fill()
                let full=row.unavailable ?? "Unavailable",label=Design.attributed(full,.caption).size().width <= spectrum.width-12 ? full:"Unavailable"
                Design.attributed(label,.caption,colour:Design.ink).draw(x:spectrum.minX+6,baseline:spectrum.midY+4,width:max(0,spectrum.width-12))
            }
            if index>0{Design.rule.setFill();NSRect(x:band.minX,y:band.minY,width:band.width,height:1).fill()}
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class PaletteViewingControls:NSView,Overlay {
    static let width:CGFloat=288
    var showsIlluminant=true {didSet{if oldValue != showsIlluminant{dismissOverlay();light.isHidden = !showsIlluminant;needsLayout=true}}}
    var opensUpward=false {didSet{output.opensUpward=opensUpward;light.opensUpward=opensUpward;output.needsDisplay=true;light.needsDisplay=true}}
    var controlWidth:CGFloat{output.fittedWidth+(showsIlluminant ? 16+light.fittedWidth:0)}
    private let output=DropdownButton(),light=DropdownButton()
    private var dropped:SwissDropdown.MenuPanel?
    private var keyboardMonitor:Any?
    var onChange:(()->Void)?
    var overlayWindows:[NSWindow]{dropped.map{[$0]} ?? []}
    var dismissOnOutsideClick:Bool{true}
    func handleOverlayEscape()->Bool{dismissOverlay();return true}
    func dismissOverlay(){if let keyboardMonitor{NSEvent.removeMonitor(keyboardMonitor);self.keyboardMonitor=nil};if let dropped{dropped.parent?.removeChildWindow(dropped);dropped.orderOut(nil)};dropped=nil;Overlays.closed(self)}
    override init(frame:NSRect){super.init(frame:frame)
        for (i,button) in [output,light].enumerated(){button.borderless=true;button.tag=i;button.target=self;button.action=#selector(open(_:));addSubview(button)}
        output.toolTip="Output Proof · Compare the master display preview with the selected output target. Δ reports the colour difference."
        light.toolTip="Viewing Illuminant · Enable Spectral Viewing and link measured samples in Settings → Colour Management. Fixed D65 display reference; prediction only."
        NotificationCenter.default.addObserver(self,selector:#selector(refresh),name:.prefsDidChange,object:nil);refresh()
    }
    required init?(coder:NSCoder){fatalError()}
    deinit{NotificationCenter.default.removeObserver(self);if let keyboardMonitor{NSEvent.removeMonitor(keyboardMonitor)}}
    override var isFlipped:Bool{true}
    override func viewWillMove(toWindow newWindow:NSWindow?){if newWindow == nil{dismissOverlay()};super.viewWillMove(toWindow:newWindow)}
    @objc private func refresh(){output.title="Output Proof: "+(Prefs.deltaWarningsEnabled ? "On":"Off");light.title=PaletteViewing.illuminant.rawValue;output.setAccessibilityLabel(output.title);light.setAccessibilityLabel("Viewing Illuminant: "+light.title+(PaletteViewing.illuminant == .normal ? "":". Linked spectral measurements only"));needsLayout=true;needsDisplay=true;onChange?()}
    override func layout(){super.layout();output.frame=NSRect(x:0,y:0,width:output.fittedWidth,height:28);light.frame=NSRect(x:output.fittedWidth+16,y:0,width:light.fittedWidth,height:28)}
    @objc private func open(_ sender:NSButton){
        guard let owner=window else{return};dismissOverlay()
        let spectralEnabled=SpectralStore.shared.snapshot().enabled
        let labels=sender.tag == 0 ? ["Off","On"]:PaletteViewing.Illuminant.allCases.map { $0 == .normal || spectralEnabled ? $0.rawValue:$0.rawValue+" — Enable In Settings" }
        let selected=sender.tag == 0 ? (Prefs.deltaWarningsEnabled ? 1:0):(PaletteViewing.Illuminant.allCases.firstIndex(of:PaletteViewing.illuminant) ?? 0)
        let isOutput=sender.tag == 0
        let choose:(Int)->Void = { [weak self] index in
            guard isOutput || spectralEnabled || index == 0 else { return }
            self?.dismissOverlay()
            if isOutput{Prefs.deltaWarningsEnabled=index == 1}else{PaletteViewing.illuminant=PaletteViewing.Illuminant.allCases[index]}
        }
        let panel=SwissDropdown.MenuPanel(items:labels,chosen:"",width:isOutput ? 176:240,chosenIndex:selected,pick:choose)
        var keyboardIndex=selected
        panel.highlight(selected)
        keyboardMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){[weak self,weak panel] event in
            guard let panel,self?.dropped === panel,event.window === panel else{return event}
            switch event.keyCode{
            case 125,126:keyboardIndex=(isOutput || spectralEnabled) ? (keyboardIndex+(event.keyCode == 125 ? 1:labels.count-1))%labels.count : 0;panel.highlight(keyboardIndex);return nil
            case 36,76,49:choose(keyboardIndex);return nil
            default:return event
            }
        }
        if sender.tag == 1 && !spectralEnabled{panel.configure(disabled:Set(1..<labels.count));panel.setWarnings(Set(1..<labels.count))}
        let anchor=owner.convertToScreen(sender.convert(sender.bounds,to:nil));panel.place(anchoredTo:anchor,preferAbove:opensUpward,within:owner)
        owner.addChildWindow(panel,ordered:.above);dropped=panel;panel.makeKeyAndOrderFront(nil);Overlays.opened(self)
    }
}
