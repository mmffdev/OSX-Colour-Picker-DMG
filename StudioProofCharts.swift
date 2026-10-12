import AppKit

/// The settings rail scrolls independently of the report; its controls keep the same baseline phase.
final class ProofSettingsBody: StudioRail.RailBody {
    var onLayout: (() -> Void)?
    var configurationCount = 0
    override var height: CGFloat { CGFloat(48 + configurationCount*2) * Design.App.unit }
    override func layout() { super.layout(); onLayout?() }
    override func draw(_ dirtyRect: NSRect) {
        let width = bounds.width-inset-insetRight
        Design.attributed("Saved Configurations · \(configurationCount)",.bodyStrong).draw(x:inset,baseline:SettingsSheet.baseline(43),width:width)
        if configurationCount == 0 { Design.attributed("No configurations saved",.caption,colour:Design.quiet).draw(x:inset,baseline:SettingsSheet.baseline(45),width:width) }
        for (title,row) in [("ΔE limit · User tolerance",18),("Ink limit · User review %",21)] {
            Design.attributed(title,.caption,colour:Design.quiet).draw(x:inset,baseline:SettingsSheet.baseline(CGFloat(row)),width:width)
            hairline(x:inset,y:SettingsSheet.baseline(CGFloat(row+1))+5,width:width,Design.rule)
        }
    }
}

enum ProofChartKind: Int, CaseIterable {
    case distribution, error, difference, lightness, density
    var title: String {
        switch self {
        case .distribution: return "Colour distribution · a* / b*"
        case .error: return "Colour error · Δa* / Δb*"
        case .difference: return "Patch difference · ΔE"
        case .lightness: return "Lightness error · ΔL*"
        case .density: return "Density operating range · Simulation"
        }
    }
    var legend: String {
        switch self {
        case .distribution: return "Hollow: reference. Filled: sample. Lines connect matching IDs. All L* levels; not a gamut boundary."
        case .error: return "Sample minus reference. Right: redder; up: yellower. The origin is zero chromatic error; lightness is separate."
        case .difference: return "Source patch order → · ΔE ↑ · Yellow line: user tolerance. Gaps indicate unevaluated patches."
        case .lightness: return "Source patch order → · ΔL* ↑ · Positive: lighter; negative: darker. Zero means matching lightness."
        case .density: return "Illustrative model · Density → · ΔE ↑ · Yellow: tolerance. Shaded interval: simulated operating range. Black marker: current; grey: optimum."
        }
    }
}

/// Deliberately separate from ProofEngine: these are editable illustrative assumptions, never measurements.
final class ProofDensitySimulation {
    var current = 1.61, optimum = 1.67, minimum = 1.30, curvature = 88.89, tolerance = 2.5
    func difference(at density: Double) -> Double { minimum + curvature * pow(density-optimum,2) }
    var radius: Double? { tolerance >= minimum ? sqrt((tolerance-minimum)/curvature) : nil }
    var interval: ClosedRange<Double>? { radius.map { max(0,optimum-$0)...(optimum+$0) } }
}

/// House diagonal arrow, with a full control target, hover, keyboard focus and accessible name.
final class ProofChartArrow: NSButton {
    var contracts = false
    private var hover = false
    private var tracking: NSTrackingArea?
    init(_ title: String, contracts: Bool = false) {
        super.init(frame:.zero); self.contracts=contracts; self.title=title
        isBordered=false; setAccessibilityLabel(title); toolTip=title
    }
    required init?(coder:NSCoder) { fatalError() }
    override func draw(_ dirtyRect:NSRect) {
        if hover { fill(bounds,Design.mist) }
        Design.arrow(16,back:contracts).draw(in:NSRect(x:(bounds.width-16)/2,y:(bounds.height-16)/2,width:16,height:16),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        if window?.firstResponder === self { Design.ink.setStroke(); NSBezierPath(rect:bounds.insetBy(dx:1,dy:1)).stroke() }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(tracking!)
    }
    override func mouseEntered(with event:NSEvent) { hover=true;needsDisplay=true;NSCursor.pointingHand.set() }
    override func mouseExited(with event:NSEvent) { hover=false;needsDisplay=true;NSCursor.arrow.set() }
}

final class ProofChartView: NSView {
    let kind: ProofChartKind
    let simulation: ProofDensitySimulation
    var results: [ProofResult] = []
    var options = ProofOptions()
    var selected = 0
    var onSelect: ((Int)->Void)?
    var onExpand: (()->Void)?
    var expanded = false { didSet { arrow.isHidden=expanded } }
    var attentionOnly = false
    private var plotHits: [(NSPoint,Int)] = []
    private let arrow: ProofChartArrow
    init(kind:ProofChartKind,simulation:ProofDensitySimulation) {
        self.kind=kind;self.simulation=simulation;arrow=ProofChartArrow("Expand " + kind.title)
        super.init(frame:.zero);addSubview(arrow);arrow.target=self;arrow.action=#selector(expand)
        setAccessibilityLabel(kind.title + ". " + kind.legend)
    }
    required init?(coder:NSCoder) { fatalError() }
    override var isFlipped:Bool { true }
    override func layout() { super.layout();arrow.frame=NSRect(x:bounds.width-32,y:0,width:32,height:32) }
    @objc private func expand() { onExpand?() }
    override func draw(_ dirtyRect:NSRect) {
        plotHits=[]
        Design.attributed(kind.title,.bodyStrong).draw(x:0,baseline:17,width:bounds.width-40)
        let frame=NSRect(x:0,y:28,width:bounds.width,height:max(100,bounds.height-112))
        switch kind {
        case .distribution: drawPlot(frame,delta:false)
        case .error: drawPlot(frame,delta:true)
        case .difference: drawSeries(frame,lightness:false)
        case .lightness: drawSeries(frame,lightness:true)
        case .density: drawDensity(frame)
        }
        SettingsSheet.paragraph(kind.legend,x:0,firstBaseline:bounds.height-56+17,width:bounds.width,height:56,colour:Design.quiet)
    }
    override func resetCursorRects() { super.resetCursorRects();addCursorRect(bounds,cursor:.crosshair) }
    override func mouseDown(with event:NSEvent) {
        let p=convert(event.locationInWindow,from:nil)
        if let hit=plotHits.min(by:{hypot($0.0.x-p.x,$0.0.y-p.y)<hypot($1.0.x-p.x,$1.0.y-p.y)}), hypot(hit.0.x-p.x,hit.0.y-p.y)<14 { onSelect?(hit.1) }
    }
    private func drawPlot(_ frame:NSRect,delta:Bool) {
        let side = min(frame.width-72, frame.height-40)
        let rect=NSRect(x:frame.midX-side/2,y:frame.minY+20,width:side,height:side)
        let maxError=results.compactMap { r -> Double? in guard let b=r.sample else{return nil}; return max(abs(b.a-r.reference.a),abs(b.b-r.reference.b)) }.max() ?? 5
        let extent=delta ? max(5,ceil(maxError/5)*5) : max(100,ceil((results.map{max(abs($0.reference.a),abs($0.reference.b),abs($0.sample?.a ?? 0),abs($0.sample?.b ?? 0))}.max() ?? 100)/20)*20)
        func point(_ a:Double,_ b:Double)->NSPoint { NSPoint(x:rect.midX+CGFloat(a/extent)*rect.width/2,y:rect.midY-CGFloat(b/extent)*rect.height/2) }
        for i in -2...2 {
            let f=CGFloat(i)/2
            hairline(x:rect.minX,y:rect.midY-f*rect.height/2,width:rect.width,i==0 ? Design.quiet : Design.rule)
            fill(NSRect(x:rect.midX+f*rect.width/2,y:rect.minY,width:1,height:rect.height),i==0 ? Design.quiet : Design.rule)
            let value=String(format:"%g",Double(f)*extent)
            Design.attributed(value,.caption,colour:Design.quiet).draw(x:rect.midX+f*rect.width/2-10,baseline:rect.maxY+16)
            Design.attributed(value,.caption,colour:Design.quiet).draw(x:rect.minX-36,baseline:rect.midY-f*rect.height/2+4,width:32)
        }
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect:rect.insetBy(dx:-4,dy:-4)).addClip()
        for (i,r) in results.enumerated() {
            if attentionOnly && r.status(options) == .withinTolerance { continue }
            let a=r.reference.lab
            let p:NSPoint
            if delta { guard let b=r.sample else {continue}; p=point(b.a-a.a,b.b-a.b) }
            else {
                let ref=point(a.a,a.b)
                Design.quiet.setStroke(); NSBezierPath(ovalIn:NSRect(x:ref.x-3,y:ref.y-3,width:6,height:6)).stroke()
                if let b=r.sample { p=point(b.a,b.b); let line=NSBezierPath();line.move(to:ref);line.line(to:p);Design.rule.setStroke();line.stroke() } else {p=ref}
            }
            if delta || r.sample != nil { a.xyz.display.setFill(); NSBezierPath(ovalIn:NSRect(x:p.x-3,y:p.y-3,width:6,height:6)).fill() }
            if i==selected {Design.ink.setStroke();let ring=NSBezierPath(ovalIn:NSRect(x:p.x-6,y:p.y-6,width:12,height:12));ring.lineWidth=2;ring.stroke()}
            plotHits.append((p,i))
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    private func drawSeries(_ frame:NSRect, lightness:Bool) {
        let rect=frame.insetBy(dx:36,dy:20)
        let values=results.map { r -> Double? in lightness ? r.sample.map{$0.l-r.reference.l} : r.difference }
        let top=max(lightness ? 5 : options.tolerance*1.2,ceil(values.compactMap{$0}.map{abs($0)}.max() ?? 1))
        func y(_ v:Double)->CGFloat { lightness ? rect.midY-CGFloat(v/top)*rect.height/2 : rect.maxY-CGFloat(v/top)*rect.height }
        for tick in 0...4 {
            let value=lightness ? top*(Double(tick)/2-1) : top*Double(tick)/4
            hairline(x:rect.minX,y:y(value),width:rect.width,abs(value)<0.0001 ? Design.quiet : Design.rule)
            Design.attributed(String(format:"%.1f",value),.caption,colour:Design.quiet).draw(x:frame.minX,baseline:y(value)+4,width:32)
        }
        if !lightness { hairline(x:rect.minX,y:y(options.tolerance),width:rect.width,Design.houseYellow) }
        for (i,v) in values.enumerated() {
            guard let v else {continue}
            if attentionOnly && results[i].status(options) == .withinTolerance { continue }
            let x=rect.minX+(CGFloat(i)+0.5)/CGFloat(max(1,values.count))*rect.width
            let p=NSPoint(x:x,y:y(v)), line=NSBezierPath()
            line.move(to:NSPoint(x:x,y:y(0)));line.line(to:p);Design.rule.setStroke();line.stroke()
            results[i].reference.lab.xyz.display.setFill();NSBezierPath(ovalIn:NSRect(x:x-2,y:p.y-2,width:4,height:4)).fill()
            if i==selected { Design.ink.setStroke();NSBezierPath(ovalIn:NSRect(x:x-5,y:p.y-5,width:10,height:10)).stroke() }
            plotHits.append((p,i))
        }
        Design.attributed("1",.caption,colour:Design.quiet).draw(x:rect.minX,baseline:rect.maxY+16)
        Design.attributed(String(results.count),.caption,colour:Design.quiet).draw(x:rect.maxX-24,baseline:rect.maxY+16)
    }
    private func drawDensity(_ frame:NSRect) {
        let s=simulation, rect=frame.insetBy(dx:44,dy:20)
        let spread=max(0.25, min(1.5,(s.radius ?? 0.2)*1.8),abs(s.current-s.optimum)*1.2)
        let low=max(0,s.optimum-spread), high=s.optimum+spread
        let ymax=max(3,s.tolerance*1.5,s.minimum+1,s.difference(at:s.current)*1.1,min(15,max(s.difference(at:low),s.difference(at:high))))
        func x(_ d:Double)->CGFloat { rect.minX+CGFloat((d-low)/(high-low))*rect.width }
        func y(_ d:Double)->CGFloat { rect.maxY-CGFloat(d/ymax)*rect.height }
        if let range=s.interval {
            let lo=max(low,range.lowerBound),hi=min(high,range.upperBound)
            fill(NSRect(x:x(lo),y:rect.minY,width:max(0,x(hi)-x(lo)),height:rect.height),Design.houseYellow.withAlphaComponent(0.12))
        }
        for i in 0...4 {
            let v=Double(i)*ymax/4,d=low+Double(i)*(high-low)/4
            hairline(x:rect.minX,y:y(v),width:rect.width,Design.rule)
            Design.attributed(String(format:"%.1f",v),.caption,colour:Design.quiet).draw(x:0,baseline:y(v)+4,width:36)
            Design.attributed(String(format:"%.2f",d),.caption,colour:Design.quiet).draw(x:x(d)-14,baseline:rect.maxY+17,width:40)
        }
        NSGraphicsContext.saveGraphicsState();NSBezierPath(rect:rect).addClip()
        let curve=NSBezierPath();curve.lineWidth=2
        for i in 0...200 { let d=low+Double(i)*(high-low)/200,p=NSPoint(x:x(d),y:y(s.difference(at:d))); if i==0 {curve.move(to:p)} else {curve.line(to:p)} }
        Design.ink.setStroke();curve.stroke()
        hairline(x:rect.minX,y:y(s.tolerance),width:rect.width,Design.houseYellow)
        for (d,colour) in [(s.optimum,Design.quiet),(s.current,Design.ink)] {
            let path=NSBezierPath();path.move(to:NSPoint(x:x(d),y:rect.maxY));path.line(to:NSPoint(x:x(d),y:y(s.difference(at:d))));path.setLineDash([4,4],count:2,phase:0);colour.setStroke();path.stroke()
            colour.setFill();NSBezierPath(ovalIn:NSRect(x:x(d)-4,y:y(s.difference(at:d))-4,width:8,height:8)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Expanded charts keep their plot and independently scrolling data/controls visible together.
final class ProofChartDetail: NSView {
    private let chart: ProofChartView
    private let controls: ProofChartControls
    private let scroll = FittedScrollView()
    private let close = ProofChartArrow("Contract chart",contracts:true)
    private var session: ProofSession
    var onClose: (()->Void)?
    var onSelect: ((Int)->Void)?
    var onOptions: ((ProofOptions)->Void)?
    var onSimulation: (()->Void)?
    init(kind:ProofChartKind,simulation:ProofDensitySimulation,session:ProofSession,results:[ProofResult],selected:Int) {
        self.session=session
        chart=ProofChartView(kind:kind,simulation:simulation)
        controls=ProofChartControls(kind:kind,simulation:simulation,session:session,results:results,selected:selected)
        super.init(frame:.zero)
        chart.expanded=true;chart.results=results;chart.options=session.options;chart.selected=selected
        chart.onSelect={ [weak self] in self?.onSelect?($0) }
        controls.onSelect={ [weak self] in self?.onSelect?($0) }
        controls.onOptions={ [weak self] in self?.onOptions?($0) }
        controls.onFilter={ [weak self] in self?.chart.attentionOnly=$0;self?.chart.needsDisplay=true }
        controls.onSimulation={ [weak self] in self?.chart.needsDisplay=true;self?.onSimulation?() }
        close.target=self;close.action=#selector(contract)
        scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.documentView=controls
        addSubview(chart);addSubview(scroll);addSubview(close)
        setAccessibilityLabel("Expanded " + kind.title)
    }
    required init?(coder:NSCoder) { fatalError() }
    override var isFlipped:Bool { true }
    @objc private func contract() { onClose?() }
    func refresh(session:ProofSession,results:[ProofResult],selected:Int) {
        self.session=session;chart.results=results;chart.options=session.options;chart.selected=selected;chart.needsDisplay=true
        controls.session=session;controls.results=results;controls.selected=selected;controls.needsDisplay=true;needsDisplay=true
    }
    override func layout() {
        super.layout()
        let right:CGFloat=320,split=bounds.width-right-32
        close.frame=NSRect(x:bounds.width-32,y:0,width:32,height:32)
        chart.frame=NSRect(x:0,y:56,width:max(240,split),height:bounds.height-56)
        scroll.frame=NSRect(x:split+32,y:56,width:right,height:bounds.height-56)
        controls.frame=NSRect(x:0,y:0,width:scroll.contentSize.width,height:controls.documentHeight)
    }
    override func draw(_ dirtyRect:NSRect) {
        Design.attributed(chart.kind == .density ? "Density simulation · Editable assumptions" : session.reference.name + " · " + session.options.mode,.heading).draw(x:0,baseline:17,width:bounds.width-56)
        hairline(x:0,y:39,width:bounds.width,Design.rule)
    }
}

private final class ProofChartControls: NSView, NSTextFieldDelegate {
    let kind:ProofChartKind,simulation:ProofDensitySimulation
    var session:ProofSession,results:[ProofResult],selected:Int
    var onSelect:((Int)->Void)?,onOptions:((ProofOptions)->Void)?,onFilter:((Bool)->Void)?,onSimulation:(()->Void)?
    private var fields:[NSTextField]=[]
    private var menus:[(SwissDropdown,CGFloat)]=[]
    private var problem=""
    var documentHeight:CGFloat { (kind == .density ? 29 : 36)*Design.App.unit }
    override var isFlipped:Bool { true }
    init(kind:ProofChartKind,simulation:ProofDensitySimulation,session:ProofSession,results:[ProofResult],selected:Int) {
        self.kind=kind;self.simulation=simulation;self.session=session;self.results=results;self.selected=selected
        super.init(frame:.zero)
        if kind == .density {
            for (i,value) in [simulation.current,simulation.optimum,simulation.minimum,simulation.curvature,simulation.tolerance].enumerated() {
                field(["Current density","Optimum density","Minimum ΔE","Curve coefficient","Simulation tolerance"][i],value:value,tag:i)
            }
        } else {
            menu("Difference formula",value:DifferenceMethod(rawValue:session.options.method)?.label ?? "CIEDE2000",options:DifferenceMethod.allCases.map(\.label),row:12) { [weak self] value in
                guard let self else{return};var o=self.session.options;o.method=DifferenceMethod.allCases.first{$0.label==value}!.rawValue;self.onOptions?(o)
            }
            let profileOptions=PressProfiles.all.map(\.name)
            menu("Output profile · Prediction only",value:session.options.profile,options:profileOptions,row:15) { [weak self] value in
                guard let self else{return};var o=self.session.options;o.profile=value;self.onOptions?(o)
            }
            menu("Plot patches",value:"All patches",options:["All patches","Needs attention"],row:18) { [weak self] in self?.onFilter?($0 == "Needs attention") }
            field("User ΔE tolerance",value:session.options.tolerance,tag:0)
            let prev=SwissButton("Previous",.secondary,target:self,action:#selector(previous)),next=SwissButton("Next",.secondary,target:self,action:#selector(nextPatch))
            for b in [prev,next] {addSubview(b)}
            prev.frame=NSRect(x:0,y:SettingsSheet.buttonTop(baseline:SettingsSheet.baseline(9)),width:prev.intrinsicContentSize.width,height:32)
            next.frame=NSRect(x:prev.frame.maxX+16,y:prev.frame.minY,width:next.intrinsicContentSize.width,height:32)
        }
    }
    required init?(coder:NSCoder) { fatalError() }
    private func field(_ label:String,value:Double,tag:Int) {
        let f=NSTextField(string:String(format:"%.2f",value));f.font=Design.Text.body.font();f.textColor=Design.ink
        f.isBordered=false;f.drawsBackground=false;f.focusRingType = .none;f.delegate=self;f.tag=tag;f.setAccessibilityLabel(label);f.target=self;f.action=#selector(commit(_:));addSubview(f);fields.append(f)
    }
    private func menu(_ label:String,value:String,options:[String],row:CGFloat,change:@escaping(String)->Void) {
        let m=SwissDropdown(label,value:value,options:options,allowsOwn:false,width:304);m.onChange=change;addSubview(m);menus.append((m,row))
    }
    override func layout() {
        super.layout()
        for (m,row) in menus {
            for c in m.constraints where c.firstAttribute == .width {c.constant=bounds.width}
            m.layoutSubtreeIfNeeded();m.frame=NSRect(x:0,y:SettingsSheet.baseline(row)-11,width:bounds.width,height:m.fittingSize.height)
        }
        for (i,f) in fields.enumerated() {
            let row:CGFloat=kind == .density ? CGFloat(12+i*3) : 22
            f.frame=NSRect(x:0,y:SettingsSheet.baseline(row)-14,width:bounds.width,height:22)
        }
    }
    @objc private func previous() { if !results.isEmpty {onSelect?((selected+results.count-1)%results.count)} }
    @objc private func nextPatch() { if !results.isEmpty {onSelect?((selected+1)%results.count)} }
    func controlTextDidEndEditing(_ obj:Notification) { if let f=obj.object as? NSTextField {commit(f)} }
    @objc private func commit(_ sender:NSTextField) {
        guard let v=Double(sender.stringValue),v.isFinite else {problem="Enter a finite numeric value.";needsDisplay=true;return}
        if kind == .density {
            let valid = sender.tag==3 ? (1...500).contains(v) : sender.tag<2 ? (0...3).contains(v) : (0...10).contains(v)
            guard valid else {problem=sender.tag==3 ? "Curve coefficient: 1–500." : sender.tag<2 ? "Density: 0–3." : "ΔE: 0–10.";needsDisplay=true;return}
            switch sender.tag {case 0:simulation.current=v;case 1:simulation.optimum=v;case 2:simulation.minimum=v;case 3:simulation.curvature=v;default:simulation.tolerance=v}
            problem="";onSimulation?();needsDisplay=true
        } else {
            guard (0.01...100).contains(v) else{problem="Tolerance: 0.01–100.";needsDisplay=true;return}
            problem="";var o=session.options;o.tolerance=v;onOptions?(o);needsDisplay=true
        }
    }
    private func text(_ value:String,_ row:CGFloat,_ style:Design.Text = .caption) {
        Design.attributed(value,style).draw(x:0,baseline:SettingsSheet.baseline(row),width:bounds.width)
    }
    private func paragraph(_ value:String,_ row:CGFloat,_ rows:CGFloat) {
        SettingsSheet.paragraph(value,x:0,firstBaseline:SettingsSheet.baseline(row),width:bounds.width,height:rows*28,colour:Design.quiet)
    }
    private func num(_ n:Double)->String{String(format:"%.2f",n)}
    override func draw(_ dirtyRect:NSRect) {
        if kind == .density {
            text("Simulated values",0,.bodyStrong)
            text("Current ΔE   " + num(simulation.difference(at:simulation.current)),2,.body)
            text("Best ΔE   " + num(simulation.minimum),3,.body)
            text("Optimum − current density   " + num(simulation.optimum-simulation.current),4,.body)
            text(simulation.interval.map{"Operating range   " + num($0.lowerBound) + "–" + num($0.upperBound)} ?? "No density meets the tolerance",6,.body)
            paragraph("ΔE(D) = Minimum + Coefficient × (D − Optimum)². Edit a value, then press Return. These assumptions do not alter the proof report.",8,3)
            for (i,label) in ["Current density · 0–3","Optimum density · 0–3","Minimum ΔE · 0–10","Curve coefficient · 1–500","Simulation tolerance · 0–10"].enumerated() {
                let row=CGFloat(11+i*3);text(label,row);hairline(x:0,y:SettingsSheet.baseline(row+1)+5,width:bounds.width,Design.rule)
            }
            paragraph(problem.isEmpty ? "Simulation only. A real operating range needs a measured density series for the ink and substrate." : problem,27,2)
        } else {
            text("Selected patch",0,.bodyStrong)
            if results.indices.contains(selected) {
                let r=results[selected],a=r.reference.lab
                text(r.reference.name + " · ID " + r.reference.id,1,.bodyStrong)
                text("L* / a* / b*",2)
                text("Reference   \(num(a.l)) / \(num(a.a)) / \(num(a.b))",3,.body)
                text(r.sample.map{"Sample   \(num($0.l)) / \(num($0.a)) / \(num($0.b))"} ?? "Sample unavailable",4,.body)
                text("ΔE   " + (r.difference.map(num) ?? "—") + " · " + r.status(session.options).rawValue,6,.body)
                paragraph(r.issue ?? "Select any chart point, or step through source patch order below.",7,2)
            }
            text("User ΔE tolerance · Return applies",21);hairline(x:0,y:SettingsSheet.baseline(22)+5,width:bounds.width,Design.rule)
            let summary=ProofEngine.summary(results,options:session.options)
            text("\(summary.evaluated) / \(summary.count) evaluated · \(summary.passed) within",24,.body)
            paragraph("\(session.reference.name)\n\(session.reference.conditions)\n\(session.options.mode) · \(session.options.intent) · BPC off",26,4)
            paragraph(problem.isEmpty ? (ProofEngine.conditionsIssue(session) ?? "Profiles affect predictions only. Formula and tolerance update the proof; the plot filter changes this view only. The a*/b* projection is not a tolerance ellipse.") : problem,31,4)
        }
    }
}
