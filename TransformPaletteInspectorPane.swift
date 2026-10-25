import AppKit

/// The selected palette, its display output, and every transform that produced it.
final class TransformPaletteInspectorPane:NSView,WorkspaceScrollableContent,InfoRailContent {
    override var isFlipped:Bool{true}
    var panelContentPadding:CGFloat{16}
    var minimumContentHeight:CGFloat{pathStart+history.reduce(0){$0+entryHeight($1)}-4}
    private var node:PaletteTransformGraph.Node
    private var graph:PaletteTransformGraph
    private var history:[PaletteTransformGraph.HistoryEntry]
    private var formats:[ColourFormat]{Prefs.cardRows}
    private var rowHeight:CGFloat{48+CGFloat(formats.count)*22}
    private var pathStart:CGFloat{580+CGFloat(node.hexes.count)*rowHeight}

    init(node:PaletteTransformGraph.Node,graph:PaletteTransformGraph) {
        self.node=node;self.graph=graph;self.history=graph.history(for:node.id)
        super.init(frame:.zero)
    }
    required init?(coder:NSCoder){fatalError()}
    func escapeInfoRail()->Bool{false}
    func show(_ value:PaletteTransformGraph.Node,graph:PaletteTransformGraph) {
        node=value;self.graph=graph;history=graph.history(for:value.id)
        needsDisplay=true;needsLayout=true
        var ancestor:NSView?=superview
        while let view=ancestor {
            if let panel=view as? WorkspacePanel {panel.rail?.arrange();break}
            ancestor=view.superview
        }
    }
    private func entryHeight(_ entry:PaletteTransformGraph.HistoryEntry)->CGFloat {
        82+CGFloat(max(1,entry.settings.count))*18
    }
    private func label(_ text:String,_ rect:NSRect,strong:Bool=false,quiet:Bool=false) {
        text.draw(in:rect,withAttributes:[.font:strong ? Design.Text.bodyStrong.font():Design.Text.caption.font(),
                                       .foregroundColor:quiet ? Design.quiet:Design.ink])
    }
    override func draw(_ dirtyRect:NSRect) {
        let width=max(0,bounds.width-32)
        let output=node.definitions ?? node.hexes.compactMap{ColourDefinition.of(hex:$0)}
        let source=graph.root.definitions ?? graph.root.hexes.compactMap{ColourDefinition.of(hex:$0)}
        label("\(graph.code(for:node.id)) · \(node.name)",NSRect(x:16,y:14,width:width,height:24),strong:true)
        PaletteSpectrum.draw(output.map(\.master.display),in:NSRect(x:16,y:48,width:width,height:28))
        label("Hue / Chroma Scope",NSRect(x:16,y:94,width:width,height:22),strong:true)
        label("Source rings → output dots",NSRect(x:16,y:116,width:width,height:18),quiet:true)
        drawPolarScope(source:source,output:output,in:NSRect(x:16,y:140,width:width,height:170))
        label("RGB Output",NSRect(x:16,y:326,width:width,height:22),strong:true)
        label("Display sRGB · unclipped channel values",NSRect(x:16,y:348,width:width,height:18),quiet:true)
        drawRGBScope(output,in:NSRect(x:16,y:378,width:width,height:96))
        label("Swatches",NSRect(x:16,y:490,width:width,height:22),strong:true)
        for index in node.hexes.indices {
            let y=518+CGFloat(index)*rowHeight
            let definition=output.indices.contains(index) ? output[index]:nil
            let key:String
            if let definition {
                key="c:transform-preview-\(node.id.uuidString)-\(index)"
                ColourKeys.register(key,definition)
            } else {key=node.hexes[index]}
            (definition?.master.display ?? Design.hex(node.hexes[index])).setFill()
            NSBezierPath(roundedRect:NSRect(x:16,y:y+4,width:28,height:28),xRadius:4,yRadius:4).fill()
            label(Prefs.showNames ? "Colour \(index+1)" : "Swatch \(index+1)",
                  NSRect(x:54,y:y+7,width:max(0,width-38),height:21),strong:true)
            for (offset,format) in formats.enumerated() {
                let baseline=y+40+CGFloat(offset)*22
                label(format.label,NSRect(x:54,y:baseline,width:64,height:18),quiet:true)
                label(format.text(key,lowercase:Prefs.lowercaseHex),
                      NSRect(x:118,y:baseline,width:max(0,width-102),height:18))
            }
            hairline(x:16,y:y+rowHeight-1,width:width,Design.rule)
        }
        label("Transform Path",NSRect(x:16,y:pathStart-44,width:width,height:22),strong:true)
        var y=pathStart
        for (index,entry) in history.enumerated() {
            drawEntry(entry,number:index+1,in:NSRect(x:16,y:y,width:width,height:entryHeight(entry)))
            y+=entryHeight(entry)
        }
    }
    private func drawPolarScope(source:[ColourDefinition],output:[ColourDefinition],in rect:NSRect) {
        let centre=NSPoint(x:rect.midX,y:rect.midY),radius=min(rect.width,rect.height)*0.39
        let maxChroma=max(0.35,(source+output).map{$0.master.oklch.c}.max() ?? 0.35)
        HueChromaScopeDrawing.background(centre:centre,radius:radius,peak:maxChroma)
        func point(_ colour:ColourDefinition)->NSPoint {
            let lch=colour.master.oklch,angle=(lch.h-90)*Double.pi/180
            let distance=min(1,lch.c/maxChroma)*Double(radius)
            return NSPoint(x:centre.x+CGFloat(cos(angle)*distance),y:centre.y+CGFloat(sin(angle)*distance))
        }
        for index in output.indices {
            let end=point(output[index])
            if source.indices.contains(index),
               hypot(end.x-point(source[index]).x,end.y-point(source[index]).y)>1 {
                let start=point(source[index]),movement=NSBezierPath()
                movement.move(to:start);movement.line(to:end)
                Design.quiet.setStroke();movement.lineWidth=1.2;movement.stroke()
                Design.card.setFill();NSBezierPath(ovalIn:NSRect(x:start.x-4,y:start.y-4,width:8,height:8)).fill()
                Design.ink.setStroke();NSBezierPath(ovalIn:NSRect(x:start.x-4,y:start.y-4,width:8,height:8)).stroke()
            }
            output[index].master.display.setFill()
            NSBezierPath(ovalIn:NSRect(x:end.x-5,y:end.y-5,width:10,height:10)).fill()
            Design.ink.setStroke();NSBezierPath(ovalIn:NSRect(x:end.x-5,y:end.y-5,width:10,height:10)).stroke()
        }
        label("Hue around · chroma outward",NSRect(x:rect.minX,y:rect.maxY-17,width:rect.width,height:17),quiet:true)
    }
    private func drawRGBScope(_ colours:[ColourDefinition],in rect:NSRect) {
        guard !colours.isEmpty else{return}
        let chart=rect.insetBy(dx:24,dy:8)
        for fraction:CGFloat in [0,0.5,1] {
            let y=chart.maxY-fraction*chart.height,rule=NSBezierPath()
            rule.move(to:NSPoint(x:chart.minX,y:y));rule.line(to:NSPoint(x:chart.maxX,y:y))
            Design.rule.setStroke();rule.lineWidth=1;rule.stroke()
        }
        label("1",NSRect(x:rect.minX,y:chart.minY-6,width:20,height:16),quiet:true)
        label("0",NSRect(x:rect.minX,y:chart.maxY-6,width:20,height:16),quiet:true)
        let inks=[NSColor.systemRed,NSColor.systemGreen,NSColor.systemBlue]
        for channel in 0..<3 {
            let line=NSBezierPath()
            for (index,colour) in colours.enumerated() {
                let value=RGBSpace.srgb.values(of:colour.master)[channel]
                let x=chart.minX+(CGFloat(index)+0.5)*chart.width/CGFloat(colours.count)
                let y=chart.maxY-CGFloat(min(1,max(0,value)))*chart.height
                if index==0 {line.move(to:NSPoint(x:x,y:y))} else {line.line(to:NSPoint(x:x,y:y))}
                inks[channel].setFill();NSBezierPath(ovalIn:NSRect(x:x-3,y:y-3,width:6,height:6)).fill()
                if value < 0 || value > 1 {
                    label(value < 0 ? "↓":"↑",NSRect(x:x-5,y:y-14,width:12,height:16),quiet:true)
                }
            }
            inks[channel].setStroke();line.lineWidth=1.5;line.stroke()
        }
    }
    private func drawEntry(_ entry:PaletteTransformGraph.HistoryEntry,number:Int,in rect:NSRect) {
        let card=rect.insetBy(dx:0,dy:4)
        Design.card.setFill();NSBezierPath(roundedRect:card,xRadius:7,yRadius:7).fill()
        Design.rule.setStroke();let border=NSBezierPath(roundedRect:card,xRadius:7,yRadius:7);border.lineWidth=1;border.stroke()
        label("\(number). \(entry.code) · \(entry.title)",
              NSRect(x:rect.minX+12,y:rect.minY+12,width:rect.width-24,height:22),strong:true)
        PaletteSpectrum.draw(entry.colours.map(\.master.display),
                             in:NSRect(x:rect.minX+12,y:rect.minY+40,width:rect.width-24,height:24))
        for (index,setting) in (entry.settings.isEmpty ? [entry.isPalette ? "Palette spectrum":"Default settings"]:entry.settings).enumerated() {
            label(setting,NSRect(x:rect.minX+12,y:rect.minY+70+CGFloat(index)*18,width:rect.width-24,height:17),quiet:true)
        }
    }
}
