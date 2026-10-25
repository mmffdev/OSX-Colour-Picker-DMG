import AppKit

/// A fixed-lightness OKLCH field: hue runs clockwise, chroma increases radially.
enum HueChromaScopeDrawing {
    static func background(centre:NSPoint,radius:CGFloat,peak:Double) {
        let spokes=96,bands=24
        for band in 0..<bands {
            let inner=CGFloat(band)/CGFloat(bands)*radius
            let outer=CGFloat(band+1)/CGFloat(bands)*radius+0.5
            let chroma=(Double(band)+0.5)/Double(bands)*peak
            for spoke in 0..<spokes {
                let hue=(Double(spoke)+0.5)*360/Double(spokes)
                let rgb=screenRGB(OKLCH(l:0.76,c:chroma,h:hue))
                NSColor(srgbRed:rgb.r,green:rgb.g,blue:rgb.b,alpha:1).setFill()
                func point(_ distance:CGFloat,_ degrees:Double)->NSPoint {
                    let angle=(degrees-90)*Double.pi/180
                    return NSPoint(x:centre.x+CGFloat(cos(angle))*distance,
                                   y:centre.y+CGFloat(sin(angle))*distance)
                }
                let start=Double(spoke)*360/Double(spokes)
                let end=Double(spoke+1)*360/Double(spokes)
                let segment=NSBezierPath()
                segment.move(to:point(inner,start));segment.line(to:point(outer,start))
                segment.line(to:point(outer,end));segment.line(to:point(inner,end));segment.close()
                segment.fill()
            }
        }
        for fraction:CGFloat in [0.5,1] {
            let ring=NSBezierPath(ovalIn:NSRect(x:centre.x-radius*fraction,y:centre.y-radius*fraction,
                                               width:radius*2*fraction,height:radius*2*fraction))
            Design.ink.withAlphaComponent(0.32).setStroke();ring.lineWidth=1;ring.stroke()
        }
        let axes=NSBezierPath()
        axes.move(to:NSPoint(x:centre.x-radius,y:centre.y));axes.line(to:NSPoint(x:centre.x+radius,y:centre.y))
        axes.move(to:NSPoint(x:centre.x,y:centre.y-radius));axes.line(to:NSPoint(x:centre.x,y:centre.y+radius))
        Design.ink.withAlphaComponent(0.18).setStroke();axes.lineWidth=1;axes.stroke()
    }
}

private final class ScopeEndsToggle:ClickCursorButton {
    override var isFlipped:Bool{true}
    override func draw(_ dirtyRect:NSRect) {
        let selected=state == .on
        (selected ? Design.houseYellow:Design.card).setFill()
        let shape=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:4,yRadius:4)
        shape.fill();Design.rule.setStroke();shape.lineWidth=1;shape.stroke()
        let style=NSMutableParagraphStyle();style.alignment = .center
        "Ends Only".draw(in:bounds.insetBy(dx:6,dy:6),withAttributes:[
            .font:Design.Text.body.font(),
            .foregroundColor:selected ? Design.hex("#161616"):Design.ink,
            .paragraphStyle:style
        ])
    }
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
}

/// Bottom viewport drawer for comparing every colour state along a selected path.
final class TransformScopesPanel:NSView {
    override var isFlipped:Bool{true}
    var onToggle:(()->Void)?
    var onResize:((CGFloat)->Void)?
    var expanded=false {didSet{needsDisplay=true}}
    var graph:PaletteTransformGraph? {didSet{refresh()}}
    var selectedPaletteID:UUID? {didSet{refresh()}}
    private let title=Design.text("Scopes",.bodyStrong)
    private let kindMenu=AnalysisMenu("Scope Data",["Hue / Chroma","RGB Parade","Luminance","CIE xy","Spectrum"])
    private let endsOnly=ScopeEndsToggle(frame:.zero)
    private let source=TransformScopesContent(frame:.zero)
    private let scroll=FittedScrollView(frame:.zero)
    private let content=TransformScopesContent(frame:.zero)
    private var paletteEntries:[PaletteTransformGraph.HistoryEntry]=[]
    private var resizeStart:NSPoint?
    private let pinnedWidth:CGFloat=276
    private var tab:NSRect {NSRect(x:(bounds.width-116)/2,y:0,width:116,height:32)}

    override init(frame:NSRect) {
        super.init(frame:frame)
        wantsLayer=true;layer?.masksToBounds=true
        title.stringValue="Scopes · Source"
        addSubview(title);addSubview(endsOnly);addSubview(kindMenu);addSubview(source);addSubview(scroll)
        source.showsTrailingDivider=true
        scroll.documentView=content;scroll.drawsBackground=false
        scroll.hasHorizontalScroller=true;scroll.hasVerticalScroller=false
        scroll.autohidesScrollers=false
        scroll.horizontalScrollElasticity = .none
        QuietScroller.install(in:scroll)
        endsOnly.setButtonType(.toggle)
        endsOnly.target=self;endsOnly.action=#selector(toggleEndsOnly)
        endsOnly.toolTip="Compare the source with the final palette"
        endsOnly.setAccessibilityLabel("Show only source and final palette scopes")
        kindMenu.changed={[weak self] index in
            guard let self else{return}
            let kind=max(0,min(4,index))
            self.source.kind=kind;self.content.kind=kind
        }
        setAccessibilityLabel("Scopes")
    }
    required init?(coder:NSCoder){fatalError()}
    @objc private func toggleEndsOnly(){updateEntries();endsOnly.needsDisplay=true}
    private func refresh() {
        guard let graph else {paletteEntries=[];source.entries=[];content.entries=[];return}
        let target=selectedPaletteID ?? graph.root.id
        paletteEntries=graph.history(for:target).filter(\.isPalette)
        updateEntries()
        title.stringValue="Scopes · \(graph.code(for:target))"
        needsLayout=true
    }
    private func updateEntries() {
        source.entries=Array(paletteEntries.prefix(1))
        var route=Array(paletteEntries.dropFirst())
        for index in route.indices {
            route[index].inputColours=index == 0 ? paletteEntries.first?.colours:route[index-1].colours
        }
        if endsOnly.state == .on, var final=route.last {
            final.inputColours=paletteEntries.first?.colours
            content.entries=[final]
        } else {content.entries=route}
        endsOnly.isEnabled=route.count>1
        scroll.contentView.scroll(to:.zero);scroll.reflectScrolledClipView(scroll.contentView)
        needsLayout=true
    }
    override func layout() {
        super.layout()
        title.frame=NSRect(x:16,y:42,width:max(80,bounds.width-388),height:23)
        endsOnly.frame=NSRect(x:max(16,bounds.width-356),y:37,width:112,height:30)
        kindMenu.frame=NSRect(x:max(16,bounds.width-232),y:37,width:216,height:30)
        scroll.frame=NSRect(x:pinnedWidth,y:73,width:max(0,bounds.width-pinnedWidth),height:max(0,bounds.height-73))
        scroll.tile()
        let cardWidth:CGFloat=244,gap:CGFloat=14
        source.frame=NSRect(x:0,y:73,width:pinnedWidth,height:max(160,scroll.contentSize.height))
        content.frame=NSRect(x:0,y:0,width:max(scroll.contentSize.width,16+CGFloat(content.entries.count)*(cardWidth+gap)),
                             height:max(160,scroll.contentSize.height))
    }
    override func draw(_ dirtyRect:NSRect) {
        let body=NSRect(x:0,y:32,width:bounds.width,height:max(0,bounds.height-32))
        Design.card.setFill();NSBezierPath(rect:body).fill()
        let t=tab,c=WorkspaceTabContour.curve,h=t.maxY-1
        let path=NSBezierPath()
        path.move(to:NSPoint(x:t.minX-c,y:h))
        path.curve(to:NSPoint(x:t.minX,y:t.minY+1),
                   controlPoint1:NSPoint(x:t.minX-c/2,y:h),controlPoint2:NSPoint(x:t.minX-c/2,y:t.minY+1))
        path.line(to:NSPoint(x:t.maxX,y:t.minY+1))
        path.curve(to:NSPoint(x:t.maxX+c,y:h),
                   controlPoint1:NSPoint(x:t.maxX+c/2,y:t.minY+1),controlPoint2:NSPoint(x:t.maxX+c/2,y:h))
        let ground=path.copy() as! NSBezierPath
        ground.line(to:NSPoint(x:t.maxX+c,y:t.maxY));ground.line(to:NSPoint(x:t.minX-c,y:t.maxY));ground.close()
        Design.card.setFill();ground.fill()
        Design.rule.setStroke();path.lineWidth=1;path.stroke()
        let rule=NSBezierPath();rule.move(to:NSPoint(x:0,y:body.minY));rule.line(to:NSPoint(x:t.minX-c,y:body.minY))
        rule.move(to:NSPoint(x:t.maxX+c,y:body.minY));rule.line(to:NSPoint(x:bounds.maxX,y:body.minY))
        rule.lineWidth=1;rule.stroke()
        let captionStyle=NSMutableParagraphStyle();captionStyle.alignment = .center
        "Scopes".draw(in:NSRect(x:t.minX+14,y:t.minY+7,width:t.width-28,height:20),
                      withAttributes:[.font:Design.Text.bodyStrong.font(),.foregroundColor:Design.ink,.paragraphStyle:captionStyle])
        if expanded {
            let grip=NSBezierPath()
            grip.move(to:NSPoint(x:bounds.midX-18,y:35));grip.line(to:NSPoint(x:bounds.midX+18,y:35))
            Design.quiet.setStroke();grip.lineWidth=2;grip.stroke()
            let separator=NSBezierPath();separator.move(to:NSPoint(x:0,y:72.5));separator.line(to:NSPoint(x:bounds.width,y:72.5))
            Design.rule.setStroke();separator.lineWidth=1;separator.stroke()
        }
    }
    override func mouseDown(with event:NSEvent) {
        let point=convert(event.locationInWindow,from:nil)
        if tab.insetBy(dx:-10,dy:0).contains(point) {onToggle?();return}
        if expanded && point.y>=32 && point.y<=44 && abs(point.x-bounds.midX)<70 {resizeStart=point}
    }
    override func mouseDragged(with event:NSEvent) {
        guard let start=resizeStart else{return}
        let current=convert(event.locationInWindow,from:nil)
        resizeStart=current
        onResize?(start.y-current.y)
    }
    override func mouseUp(with event:NSEvent){resizeStart=nil}
}

private final class TransformScopesContent:NSView {
    override var isFlipped:Bool{true}
    var showsTrailingDivider=false
    var entries:[PaletteTransformGraph.HistoryEntry]=[] {didSet{needsDisplay=true;needsLayout=true}}
    var kind=0 {didSet{needsDisplay=true}}
    override func draw(_ dirtyRect:NSRect) {
        Design.card.setFill();NSBezierPath(rect:bounds).fill()
        let width:CGFloat=244,gap:CGFloat=14
        for (index,entry) in entries.enumerated() {
            let rect=NSRect(x:16+CGFloat(index)*(width+gap),y:16,width:width,height:max(132,bounds.height-40))
            guard rect.intersects(dirtyRect) else{continue}
            Design.mist.setFill();NSBezierPath(roundedRect:rect,xRadius:7,yRadius:7).fill()
            Design.rule.setStroke();let border=NSBezierPath(roundedRect:rect,xRadius:7,yRadius:7);border.lineWidth=1;border.stroke()
            let label="\(entry.code) · \(entry.title)" as NSString
            label.draw(in:NSRect(x:rect.minX+12,y:rect.minY+12,width:rect.width-24,height:38),
                       withAttributes:[.font:Design.Text.bodyStrong.font(),.foregroundColor:Design.ink])
            let plot=NSRect(x:rect.minX+12,y:rect.minY+57,width:rect.width-24,height:max(68,rect.height-104))
            let previous=entry.inputColours ?? (index>0 ? entries[index-1].colours:nil)
            drawScope(entry.colours,previous:previous,in:plot)
            PaletteSpectrum.draw(entry.colours.map(\.master.display),
                                 in:NSRect(x:rect.minX+12,y:rect.maxY-34,width:rect.width-24,height:20))
        }
        if showsTrailingDivider {Design.rule.setFill();NSRect(x:bounds.maxX-1,y:0,width:1,height:bounds.height).fill()}
    }
    private func drawScope(_ colours:[ColourDefinition],previous:[ColourDefinition]?,in rect:NSRect) {
        guard !colours.isEmpty else{return}
        switch kind {
        case 0:
            let centre=NSPoint(x:rect.midX,y:rect.midY),radius=min(rect.height,rect.width)*0.42
            let peak=max(0.35,(colours+(previous ?? [])).map{$0.master.oklch.c}.max() ?? 0.35)
            HueChromaScopeDrawing.background(centre:centre,radius:radius,peak:peak)
            func point(_ colour:ColourDefinition)->NSPoint {
                let value=colour.master.oklch,angle=(value.h-90)*Double.pi/180
                let distance=min(1,value.c/peak)*Double(radius)
                return NSPoint(x:centre.x+CGFloat(cos(angle)*distance),y:centre.y+CGFloat(sin(angle)*distance))
            }
            for (index,colour) in colours.enumerated() {
                let end=point(colour)
                if let previous,previous.indices.contains(index),
                   hypot(end.x-point(previous[index]).x,end.y-point(previous[index]).y)>1 {
                    let start=point(previous[index]),line=NSBezierPath()
                    line.move(to:start);line.line(to:end);Design.quiet.setStroke();line.lineWidth=1;line.stroke()
                    Design.card.setFill();NSBezierPath(ovalIn:NSRect(x:start.x-3,y:start.y-3,width:6,height:6)).fill()
                    Design.ink.setStroke();NSBezierPath(ovalIn:NSRect(x:start.x-3,y:start.y-3,width:6,height:6)).stroke()
                }
                colour.master.display.setFill();NSBezierPath(ovalIn:NSRect(x:end.x-5,y:end.y-5,width:10,height:10)).fill()
                Design.ink.setStroke();NSBezierPath(ovalIn:NSRect(x:end.x-5,y:end.y-5,width:10,height:10)).stroke()
            }
        case 1,2:
            let channels=kind==1 ? 3:1,inks=[NSColor.systemRed,NSColor.systemGreen,NSColor.systemBlue]
            for channel in 0..<channels {
                let line=NSBezierPath()
                for (index,colour) in colours.enumerated() {
                    let value=kind==1 ? RGBSpace.srgb.values(of:colour.master)[channel]:colour.master.y
                    let x=rect.minX+(CGFloat(index)+0.5)*rect.width/CGFloat(colours.count)
                    let y=rect.maxY-CGFloat(min(1,max(0,value)))*rect.height
                    if index==0 {line.move(to:NSPoint(x:x,y:y))} else {line.line(to:NSPoint(x:x,y:y))}
                    (kind==1 ? inks[channel]:Design.ink).setFill()
                    NSBezierPath(ovalIn:NSRect(x:x-3,y:y-3,width:6,height:6)).fill()
                }
                (kind==1 ? inks[channel]:Design.ink).setStroke();line.lineWidth=1.5;line.stroke()
            }
        case 3:
            drawChromaticity(colours,previous:previous,in:rect)
        default:
            PaletteSpectrum.draw(colours.map(\.master.display),in:rect.insetBy(dx:0,dy:rect.height*0.3))
        }
    }
    private func drawChromaticity(_ colours:[ColourDefinition],previous:[ColourDefinition]?,in rect:NSRect) {
        // The graph's gamut and spectral locus use D65. GamutMaths.xy adapts our D50
        // master before plotting, so a transformed swatch and the sRGB outline agree.
        let side=min(rect.width-26,rect.height-36)
        let diagram=NSRect(x:rect.midX-side/2,y:rect.midY-side/2-4,width:side,height:side)
        func point(_ xy:GamutPoint)->NSPoint {
            NSPoint(x:diagram.minX+CGFloat(xy.x/0.8)*diagram.width,
                    y:diagram.maxY-CGFloat(xy.y/0.9)*diagram.height)
        }
        let locus=NSBezierPath()
        for (index,xy) in GamutMaths.locus(in:.xy).enumerated() {
            if index==0 {locus.move(to:point(xy))} else {locus.line(to:point(xy))}
        }
        if let first=GamutMaths.locus(in:.xy).first {locus.line(to:point(first))}
        locus.close()
        Design.card.setFill();NSBezierPath(rect:diagram).fill()
        Design.mist.setFill();locus.fill()
        for tick in 1...4 {
            let fraction=CGFloat(tick)/5
            let grid=NSBezierPath()
            grid.move(to:NSPoint(x:diagram.minX+fraction*diagram.width,y:diagram.minY))
            grid.line(to:NSPoint(x:diagram.minX+fraction*diagram.width,y:diagram.maxY))
            grid.move(to:NSPoint(x:diagram.minX,y:diagram.minY+fraction*diagram.height))
            grid.line(to:NSPoint(x:diagram.maxX,y:diagram.minY+fraction*diagram.height))
            Design.rule.withAlphaComponent(0.45).setStroke();grid.lineWidth=0.5;grid.stroke()
        }
        let triangle=NSBezierPath()
        for (index,xy) in GamutMaths.corners(of:.srgb,in:.xy).enumerated() {
            if index==0 {triangle.move(to:point(xy))} else {triangle.line(to:point(xy))}
        }
        triangle.close()
        NSGraphicsContext.saveGraphicsState()
        triangle.addClip()
        let rows=Int(max(80,min(180,diagram.height)))
        for row in 0..<rows {
            let y=diagram.minY+CGFloat(row)*diagram.height/CGFloat(rows)
            let chromaY=Double((diagram.maxY-y)/diagram.height)*0.9
            let stops=(0...16).map { index -> NSColor in
                let xy=GamutPoint(x:Double(index)*0.8/16,y:chromaY)
                let rgb=GamutMaths.display(xy:xy)
                return NSColor(srgbRed:rgb[0],green:rgb[1],blue:rgb[2],alpha:1)
            }
            NSGradient(colors:stops)?.draw(in:NSRect(x:diagram.minX,y:y,width:diagram.width,
                                                     height:diagram.height/CGFloat(rows)+0.5),angle:0)
        }
        NSGraphicsContext.restoreGraphicsState()
        Design.rule.setStroke();locus.lineWidth=1;locus.stroke()
        Design.ink.withAlphaComponent(0.7).setStroke();triangle.lineWidth=1;triangle.stroke()
        let white=point(GamutMaths.white)
        Design.ink.setFill();NSBezierPath(ovalIn:NSRect(x:white.x-2,y:white.y-2,width:4,height:4)).fill()
        for (index,colour) in colours.enumerated() {
            let end=point(GamutMaths.xy(colour.master))
            if let previous,previous.indices.contains(index) {
                let start=point(GamutMaths.xy(previous[index].master))
                if hypot(end.x-start.x,end.y-start.y)>1 {
                    let movement=NSBezierPath();movement.move(to:start);movement.line(to:end)
                    Design.ink.withAlphaComponent(0.75).setStroke();movement.lineWidth=1.4;movement.stroke()
                    Design.card.setFill();NSBezierPath(ovalIn:NSRect(x:start.x-4,y:start.y-4,width:8,height:8)).fill()
                    Design.ink.setStroke();NSBezierPath(ovalIn:NSRect(x:start.x-4,y:start.y-4,width:8,height:8)).stroke()
                }
            }
            colour.master.display.setFill();NSBezierPath(ovalIn:NSRect(x:end.x-5,y:end.y-5,width:10,height:10)).fill()
            Design.ink.setStroke();NSBezierPath(ovalIn:NSRect(x:end.x-5,y:end.y-5,width:10,height:10)).stroke()
        }
        let captionStyle=NSMutableParagraphStyle();captionStyle.alignment = .center
        "CIE 1931 xy · sRGB / D65".draw(in:NSRect(x:rect.minX,y:diagram.maxY+7,width:rect.width,height:18),
                                       withAttributes:[.font:Design.Text.caption.font(),.foregroundColor:Design.ink,.paragraphStyle:captionStyle])
    }
}
