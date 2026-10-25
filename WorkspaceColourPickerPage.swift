import AppKit

/// Saved UI swatches are value copies; source palettes and colours remain independent.
enum WorkspaceCustomColours {
    static let key="Workspace.NodeColours.Custom"
    static func all()->[String]{AppPreferences.shared.stringArray(forKey:key) ?? []}
    @discardableResult static func add(_ hexes:[String])->Int {
        var colours=all(),seen=Set(colours)
        let additions=hexes.map{$0.uppercased()}.filter{seen.insert($0).inserted}
        guard !additions.isEmpty else{return 0}
        colours.append(contentsOf:additions)
        AppPreferences.shared.set(colours,forKey:key)
        return additions.count
    }
}

/// Three independently configurable colour palettes inside the centre Viewport-Page.
final class WorkspaceColourPickerPage:NSView {
    struct Props {var background=true;var text=true;var border=true}
    struct NodeDesign:Codable,Equatable {
        var id:UUID
        var name:String
        var background:String?
        var text:String?
        var border:String?
    }
    private final class Canvas:NSView {override var isFlipped:Bool{true}}
    private final class Rule:NSView {
        override var isFlipped:Bool{true}
        override func draw(_ dirtyRect:NSRect){hairline(x:0,y:0,width:bounds.width,Design.rule)}
    }
    private final class Swatch:ClickCursorButton {
        let hex:String?
        var onContext:((Swatch,NSPoint)->Void)?
        var isCurrent=false {didSet{if oldValue != isCurrent{needsDisplay=true}}}
        var isMarked=false {didSet{if oldValue != isMarked{needsDisplay=true}}}
        init(_ hex:String?){self.hex=hex;super.init(frame:.zero);isBordered=false;setAccessibilityLabel(hex.map{"Choose \($0)"} ?? "No Colour");toolTip=hex ?? "No Colour"}
        required init?(coder:NSCoder){fatalError()}
        override func draw(_ rect:NSRect){
            let highlighted=isCurrent || isMarked
            let box=bounds.insetBy(dx:highlighted ? 3:1,dy:highlighted ? 3:1)
            if let hex {Design.hex(hex).setFill();NSBezierPath(roundedRect:box,xRadius:2,yRadius:2).fill()}
            else {
                Design.card.setFill();NSBezierPath(roundedRect:box,xRadius:2,yRadius:2).fill()
                Design.quiet.setStroke();let slash=NSBezierPath();slash.move(to:NSPoint(x:box.minX+3,y:box.maxY-3));slash.line(to:NSPoint(x:box.maxX-3,y:box.minY+3));slash.lineWidth=2;slash.stroke()
            }
            Design.rule.setStroke();let outline=NSBezierPath(roundedRect:box,xRadius:2,yRadius:2);outline.lineWidth=1;outline.stroke()
            if highlighted {ColourTargetBarberPole.draw(in:bounds.insetBy(dx:0.5,dy:0.5),radius:3,thickness:2)}
        }
        override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
        override func rightMouseDown(with event:NSEvent){
            guard onContext != nil else {super.rightMouseDown(with:event);return}
            onContext?(self,convert(event.locationInWindow,from:nil))
        }
    }
    private final class Palette:NSView {
        override var isFlipped:Bool{true}
        let channel:WorkspaceColourMode.Channel
        var onChoose:((WorkspaceColourMode.Channel,String?)->Void)?
        var onAddToCustom:((String,NSPoint,NSView)->Void)?
        private let heading=NSTextField(labelWithString:"")
        private let caption=NSTextField(labelWithString:"Bright hues · Full tonal range")
        private let noColour=Swatch(nil)
        private let canvas=Canvas()
        private let scroll=NSScrollView()
        private let currentScroll=NSScrollView()
        private let currentCanvas=Canvas()
        private let currentLabel=NSTextField(labelWithString:"Current")
        private var currentSwatches:[Swatch]=[]
        private var swatches:[Swatch]=[]
        private var greyLabels:[NSTextField]=[]
        private let families:[Double]=[2,19,32,49,62,80,118,150,179,197,216,247,278,308,335]
        init(_ channel:WorkspaceColourMode.Channel){
            self.channel=channel;super.init(frame:.zero)
            switch channel {
            case .background:heading.stringValue="Background"
            case .text:heading.stringValue="Text"
            case .border:heading.stringValue="Border"
            }
            heading.font=Design.Text.heading.font();heading.textColor=Design.ink
            caption.font=Design.Text.caption.font();caption.textColor=Design.quiet
            noColour.target=self;noColour.action=#selector(picked(_:))
            [heading,caption,scroll].forEach{addSubview($0)}
            scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;scroll.autohidesScrollers=true;scroll.scrollerStyle = .overlay;scroll.documentView=canvas
            currentScroll.drawsBackground=false;currentScroll.hasVerticalScroller=false;currentScroll.hasHorizontalScroller=true;currentScroll.autohidesScrollers=true;currentScroll.scrollerStyle = .overlay;currentScroll.documentView=currentCanvas
            currentLabel.font=Design.Text.caption.font();currentLabel.textColor=Design.quiet
            currentCanvas.addSubview(currentLabel);canvas.addSubview(currentScroll);currentScroll.isHidden=true
            for hue in families {
                for row in 0..<12 {
                    let light:Double
                    let saturation:Double
                    if row < 4 {
                        let vivid=hue < 45 || hue > 300 ? [60.0,55,49,43] : hue < 90 ? [69.0,63,56,48] : hue < 210 ? [68.0,61,53,45] : [62.0,56,49,42]
                        light=vivid[row];saturation=Double(94-row*2)
                    } else {light=[94.0,84,73,62,51,40,29,18][row-4];saturation=70}
                    let swatch=Swatch(WorkspaceColourPickerPage.hslHex(hue,saturation,light))
                    swatch.onContext={ [weak self] swatch,point in guard let hex=swatch.hex else{return};self?.onAddToCustom?(hex,point,swatch) }
                    swatch.target=self;swatch.action=#selector(picked(_:));canvas.addSubview(swatch);swatches.append(swatch)
                }
            }
            for (index,name) in ["Warm greys","Cold greys","Natural greys"].enumerated(){
                let label=NSTextField(labelWithString:name);label.font=Design.Text.caption.font();label.textColor=Design.quiet;canvas.addSubview(label);greyLabels.append(label)
                for step in 0..<12 {
                    let swatch=Swatch(WorkspaceColourPickerPage.hslHex(index == 0 ? 30:index == 1 ? 210:0,index == 2 ? 0:index == 0 ? 8:9,12+Double(step)*7.4))
                    swatch.onContext={ [weak self] swatch,point in guard let hex=swatch.hex else{return};self?.onAddToCustom?(hex,point,swatch) }
                    swatch.target=self;swatch.action=#selector(picked(_:));canvas.addSubview(swatch);swatches.append(swatch)
                }
            }
            canvas.addSubview(noColour)
        }
        required init?(coder:NSCoder){fatalError()}
        @objc private func picked(_ sender:Swatch){onChoose?(channel,sender.hex)}
        func setCurrent(hexes:Set<String>,includesNoColour:Bool){
            noColour.isCurrent=includesNoColour
            for swatch in swatches {swatch.isCurrent=swatch.hex.map(hexes.contains) ?? false}
            let gridHexes=Set(swatches.compactMap{$0.hex})
            let customHexes=hexes.subtracting(gridHexes).sorted()
            if customHexes != currentSwatches.compactMap({$0.hex}) {
                currentSwatches.forEach{$0.removeFromSuperview()}
                currentSwatches=customHexes.map{hex in
                    let swatch=Swatch(hex);swatch.isCurrent=true;swatch.target=self;swatch.action=#selector(picked(_:))
                    swatch.onContext={ [weak self] swatch,point in guard let hex=swatch.hex else{return};self?.onAddToCustom?(hex,point,swatch) }
                    currentCanvas.addSubview(swatch);return swatch
                }
                currentScroll.isHidden=currentSwatches.isEmpty
                needsLayout=true
            }
        }
        override func layout(){
            super.layout()
            let width=bounds.width
            heading.frame=NSRect(x:0,y:0,width:width,height:29)
            caption.frame=NSRect(x:0,y:34,width:width,height:17)
            scroll.frame=NSRect(x:0,y:66,width:width,height:max(0,bounds.height-66))
            let gap:CGFloat=6
            let swatchWidth=max(15,min(25.5,floor((width-14*gap)/15)))
            let pitch=swatchWidth+gap
            let hueWidth=CGFloat(15)*swatchWidth+14*gap
            let greySwatchWidth=CGFloat(12)*swatchWidth+11*gap
            let greyX=hueWidth-greySwatchWidth
            let contentWidth=max(width,hueWidth)
            let hueStart:CGFloat=40
            let greyStart=hueStart+CGFloat(12)*pitch+18
            let canvasHeight=greyStart+CGFloat(3)*pitch+12
            canvas.frame=NSRect(x:0,y:0,width:contentWidth,height:canvasHeight)
            currentScroll.frame=NSRect(x:0,y:0,width:max(0,CGFloat(14)*pitch-gap),height:swatchWidth)
            currentCanvas.frame=NSRect(x:0,y:0,width:max(currentScroll.bounds.width,64+CGFloat(currentSwatches.count)*pitch),height:swatchWidth)
            currentLabel.frame=NSRect(x:0,y:(swatchWidth-17)/2,width:60,height:17)
            for (index,swatch) in currentSwatches.enumerated(){swatch.frame=NSRect(x:64+CGFloat(index)*pitch,y:0,width:swatchWidth,height:swatchWidth)}
            noColour.frame=NSRect(x:CGFloat(14)*pitch,y:0,width:swatchWidth,height:swatchWidth)
            for index in families.indices {
                let x=CGFloat(index)*pitch
                for row in 0..<12 {swatches[index*12+row].frame=NSRect(x:x,y:hueStart+CGFloat(row)*pitch+(row >= 4 ? 10:0),width:swatchWidth,height:swatchWidth)}
            }
            let greyIndex=families.count*12
            for group in 0..<3 {
                let y=greyStart+CGFloat(group)*pitch
                greyLabels[group].frame=NSRect(x:0,y:y+2,width:max(0,greyX-8),height:20)
                for step in 0..<12 {swatches[greyIndex+group*12+step].frame=NSRect(x:greyX+CGFloat(step)*pitch,y:y,width:swatchWidth,height:swatchWidth)}
            }
        }
    }
    private final class CustomPalette:NSView {
        override var isFlipped:Bool{true}
        var onApply:((String,NSPoint,NSView)->Void)?
        var onSample:(()->Void)?
        var onRepeatSample:(()->Void)?
        var onRemove:(([String],NSPoint,NSView)->Void)?
        private let heading=NSTextField(labelWithString:"Custom Colours")
        private let sample=PaletteAssetIcon(frame:.zero)
        private let repeatSample=PaletteAssetIcon(frame:.zero)
        private let scroll=NSScrollView()
        private let canvas=Canvas()
        private var swatches:[Swatch]=[]
        private var current:Set<String>=[]
        private var marked:Set<Int>=[]
        private var anchor:Int?
        override init(frame:NSRect){
            super.init(frame:frame)
            heading.font=Design.Text.heading.font();heading.textColor=Design.ink
            sample.symbol="eyedropper";sample.matchesHeaderGlyph=true;sample.toolTip="Sample A Screen Colour";sample.setAccessibilityLabel("Sample A Screen Colour")
            sample.run={ [weak self] in self?.onSample?() }
            repeatSample.symbol="eyedropper";repeatSample.matchesHeaderGlyph=true;repeatSample.badgePlus=true
            repeatSample.toolTip="Keep Sampling Screen Colours";repeatSample.setAccessibilityLabel("Keep Sampling Screen Colours")
            repeatSample.run={ [weak self] in self?.onRepeatSample?() }
            addSubview(heading);canvas.addSubview(sample);canvas.addSubview(repeatSample)
            scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=false;scroll.autohidesScrollers=true;scroll.scrollerStyle = .overlay;scroll.documentView=canvas;addSubview(scroll)
        }
        required init?(coder:NSCoder){fatalError()}
        func setColours(_ colours:[String]){
            swatches.forEach{$0.removeFromSuperview()}
            marked=[];anchor=nil
            swatches=colours.map{hex in
                let swatch=Swatch(hex);swatch.target=self;swatch.action=#selector(picked(_:));swatch.isCurrent=current.contains(hex)
                swatch.onContext={ [weak self] swatch,point in
                    guard let self,let index=self.swatches.firstIndex(where:{$0 === swatch}) else{return}
                    if !self.marked.contains(index){self.marked=[index];self.anchor=index;self.refreshMarks()}
                    let colours=self.marked.sorted().compactMap{self.swatches[$0].hex}
                    self.onRemove?(colours,point,swatch)
                }
                canvas.addSubview(swatch);return swatch
            }
            needsLayout=true
        }
        func setCurrent(_ hexes:Set<String>){current=hexes;for swatch in swatches{swatch.isCurrent=swatch.hex.map(hexes.contains) ?? false}}
        func contentHeight(for width:CGFloat)->CGFloat {
            let gap:CGFloat=6,pitch:CGFloat=31.5
            let columns=max(1,min(15,Int((width+gap)/pitch)))
            let rows=(swatches.count+columns-1)/columns
            return 36+CGFloat(min(rows,4))*pitch+40
        }
        private func refreshMarks(){for (index,swatch) in swatches.enumerated(){swatch.isMarked=marked.contains(index)}}
        @objc private func picked(_ sender:Swatch){
            guard let hex=sender.hex,let index=swatches.firstIndex(where:{$0 === sender}) else{return}
            let flags=NSApp.currentEvent?.modifierFlags ?? []
            if flags.contains(.shift) {
                let start=anchor ?? index
                marked=Set(min(start,index)...max(start,index))
                refreshMarks();return
            }
            if flags.contains(.command) {
                if marked.contains(index){marked.remove(index)}else{marked.insert(index)}
                anchor=index;refreshMarks();return
            }
            marked=[index];anchor=index;refreshMarks()
            onApply?(hex,NSPoint(x:sender.bounds.midX,y:sender.bounds.maxY),sender)
        }
        override func layout(){
            super.layout()
            heading.frame=NSRect(x:0,y:0,width:bounds.width,height:29)
            scroll.frame=NSRect(x:0,y:36,width:bounds.width,height:max(0,bounds.height-36))
            let gap:CGFloat=6,swatchWidth:CGFloat=25.5,pitch=swatchWidth+gap
            let columns=max(1,min(15,Int((bounds.width+gap)/pitch)))
            let rows=(swatches.count+columns-1)/columns
            canvas.frame=NSRect(x:0,y:0,width:bounds.width,height:max(scroll.bounds.height,CGFloat(rows)*pitch+36))
            for (index,swatch) in swatches.enumerated(){swatch.frame=NSRect(x:CGFloat(index % columns)*pitch,y:CGFloat(index / columns)*pitch,width:swatchWidth,height:swatchWidth)}
            sample.frame=NSRect(x:0,y:CGFloat(rows)*pitch+4,width:28,height:28)
            repeatSample.frame=NSRect(x:34,y:CGFloat(rows)*pitch+4,width:28,height:28)
        }
    }
    private final class DesignPreview:ClickCursorButton {
        private final class NameButton:ClickCursorButton {
            var name="" {didSet{needsDisplay=true}}
            var editing=false {didSet{needsDisplay=true}}
            var run:((NSPoint)->Void)?
            override init(frame:NSRect){super.init(frame:frame);isBordered=false;target=self;action=#selector(pressed)}
            required init?(coder:NSCoder){fatalError()}
            @objc private func pressed(){run?(convert(NSApp.currentEvent?.locationInWindow ?? .zero,from:nil))}
            override func draw(_ dirtyRect:NSRect){
                guard !editing else{return}
                (name as NSString).draw(in:NSRect(x:2,y:1,width:bounds.width-4,height:20),withAttributes:[.font:Design.Text.body.font(),.foregroundColor:Design.ink])
            }
            override func resetCursorRects(){addCursorRect(bounds,cursor:.iBeam)}
        }
        override var isFlipped:Bool{true}
        var design:NodeDesign? {didSet{nameButton.name=design?.name ?? "Current selection";needsDisplay=true}}
        var isTargeted=false {didSet{if oldValue != isTargeted{needsDisplay=true}}}
        var nodeName="Example node" {didSet{needsDisplay=true}}
        var onContext:((DesignPreview,NSPoint)->Void)?
        var onRename:((NodeDesign,String)->Void)?
        var onDelete:((NodeDesign)->Void)?
        private let nameButton=NameButton(frame:.zero)
        private let renameIcon=PaletteAssetIcon(frame:.zero)
        private let deleteIcon=PaletteAssetIcon(frame:.zero)
        override init(frame:NSRect){
            super.init(frame:frame);isBordered=false;setAccessibilityRole(.button)
            nameButton.name="Current selection";nameButton.setAccessibilityLabel("Rename Design")
            nameButton.run={ [weak self] point in self?.beginRename(selectAll:false,at:point) }
            renameIcon.symbol="pencil";renameIcon.toolTip="Rename Design";renameIcon.setAccessibilityLabel("Rename Design")
            renameIcon.run={ [weak self] in self?.beginRename(selectAll:true,at:.zero) }
            deleteIcon.symbol="trash";deleteIcon.toolTip="Remove Design";deleteIcon.setAccessibilityLabel("Remove Design")
            deleteIcon.run={ [weak self] in guard let self,let design=self.design else{return};self.onDelete?(design) }
            [nameButton,renameIcon,deleteIcon].forEach(addSubview)
            nameButton.isEnabled=false;renameIcon.isHidden=true;deleteIcon.isHidden=true
        }
        required init?(coder:NSCoder){fatalError()}
        var showsActions=false {didSet{renameIcon.isHidden = !showsActions;deleteIcon.isHidden = !showsActions;nameButton.isEnabled=showsActions;needsLayout=true}}
        override func layout(){
            super.layout()
            nameButton.frame=NSRect(x:0,y:0,width:max(0,bounds.width-(showsActions ? 52:0)),height:22)
            renameIcon.frame=NSRect(x:bounds.width-44,y:0,width:20,height:20)
            deleteIcon.frame=NSRect(x:bounds.width-20,y:0,width:20,height:20)
        }
        func beginRename(selectAll:Bool,at point:NSPoint){
            guard showsActions,let design,!nameButton.editing else{return}
            nameButton.editing=true
            // Start with an empty insertion point on the label's own baseline.
            // Empty Return and Escape both leave the saved name untouched.
            InlineName.edit("",style:.body,in:nameButton,x:2,baseline:13,width:max(60,nameButton.bounds.width-4),at:.zero){[weak self] name in
                guard let self else{return}
                self.nameButton.editing=false
                if let name,self.design?.id == design.id {self.onRename?(design,name)}
            }
        }
        override func rightMouseDown(with event:NSEvent){onContext?(self,convert(event.locationInWindow,from:nil))}
        override func draw(_ dirtyRect:NSRect){
            let box=NSRect(x:0,y:27,width:bounds.width,height:28)
            let fill=design?.background.map(Design.hex) ?? Design.card
            let ink=design?.text.map(Design.hex) ?? (Theme.takesLightText(on:hexOf(fill) ?? "#FFFFFF") ? NSColor.white:NSColor.black)
            fill.setFill();NSBezierPath(roundedRect:box,xRadius:7,yRadius:7).fill()
            if let border=design?.border {
                Design.hex(border).setStroke();let outline=NSBezierPath(roundedRect:box.insetBy(dx:0.5,dy:0.5),xRadius:7,yRadius:7);outline.lineWidth=1.5;outline.stroke()
            }
            if isTargeted {ColourTargetBarberPole.draw(in:box.insetBy(dx:-2.5,dy:-2.5),radius:9.5,thickness:2)}
            let arrow=NSBezierPath();arrow.move(to:NSPoint(x:15,y:39));arrow.line(to:NSPoint(x:20,y:44));arrow.line(to:NSPoint(x:25,y:39));arrow.lineWidth=1.3;ink.setStroke();arrow.stroke()
            let name=nodeName.isEmpty ? "Example node":nodeName
            (name as NSString).draw(in:NSRect(x:34,y:32,width:bounds.width-48,height:20),withAttributes:[.font:Design.Text.body.font(),.foregroundColor:ink])
        }
    }
    private final class MyDesigns:NSView {
        override var isFlipped:Bool{true}
        var onSave:(()->Void)?
        var onApply:((NodeDesign)->Void)?
        var onRemove:((NodeDesign,NSPoint,NSView)->Void)?
        var onRename:((NodeDesign,String)->Void)?
        var onDelete:((NodeDesign)->Void)?
        private let heading=NSTextField(labelWithString:"My Designs")
        private let hint=NSTextField(labelWithString:"Save this node style, then click a design to apply it to selected nodes.")
        private let live=DesignPreview(frame:.zero)
        private let save=SwissButton("Save As Design",.secondary)
        private var tiles:[DesignPreview]=[]
        private var activeDesignID:UUID?
        private var selected:NodeDesign?
        private var selectedCount=0
        override init(frame:NSRect){
            super.init(frame:frame)
            heading.font=Design.Text.heading.font();heading.textColor=Design.ink
            hint.font=Design.Text.caption.font();hint.textColor=Design.quiet
            live.isEnabled=false
            save.actionSymbol="square.and.arrow.down"
            save.target=self;save.action=#selector(saveCurrent);save.setAccessibilityLabel("Save Current Node Style As Design")
            [heading,hint,live,save].forEach(addSubview)
        }
        required init?(coder:NSCoder){fatalError()}
        @objc private func saveCurrent(){onSave?()}
        func setCurrent(_ design:NodeDesign?,nodeName:String,count:Int=1){
            selected=design;selectedCount=count;live.design=design;live.nodeName=nodeName
            live.isTargeted=false
            save.isEnabled=design != nil
            hint.stringValue=count > 1 ? "Previewing the first of \(count) selected nodes · A design applies to all selected nodes." : "Save this node style, then click a design to apply it to selected nodes."
        }
        func setDesigns(_ values:[NodeDesign]){
            tiles.forEach{$0.removeFromSuperview()};tiles=[]
            for design in values {
                let tile=DesignPreview(frame:.zero);tile.design=design;tile.nodeName="Example node";tile.showsActions=true;tile.isTargeted=design.id == activeDesignID
                tile.setAccessibilityLabel("Apply \(design.name) to selected nodes")
                tile.toolTip="Apply \(design.name)"
                tile.target=self;tile.action=#selector(apply(_:))
                tile.onContext={ [weak self] view,point in self?.onRemove?(design,point,view) }
                tile.onRename={ [weak self] design,name in self?.onRename?(design,name) }
                tile.onDelete={ [weak self] design in self?.onDelete?(design) }
                addSubview(tile);tiles.append(tile)
            }
            setCurrent(selected,nodeName:live.nodeName,count:selectedCount)
            needsLayout=true
        }
        func clearActiveDesign(){activeDesignID=nil;for tile in tiles{tile.isTargeted=false}}
        @objc private func apply(_ sender:DesignPreview){
            guard let design=sender.design else{return}
            activeDesignID=design.id
            for tile in tiles{tile.isTargeted=tile.design?.id == design.id}
            onApply?(design)
        }
        func contentHeight(for width:CGFloat)->CGFloat {
            let columns=max(1,Int((width+16)/276))
            let rows=(tiles.count+columns-1)/columns
            return 146+CGFloat(rows)*80
        }
        override func layout(){
            super.layout()
            heading.frame=NSRect(x:0,y:0,width:bounds.width,height:29)
            hint.frame=NSRect(x:0,y:33,width:bounds.width,height:18)
            live.frame=NSRect(x:0,y:62,width:260,height:58)
            save.frame=NSRect(x:276,y:87,width:150,height:32)
            let columns=max(1,Int((bounds.width+16)/276))
            for (index,tile) in tiles.enumerated(){
                tile.frame=NSRect(x:CGFloat(index % columns)*276,y:146+CGFloat(index / columns)*80,width:260,height:58)
            }
        }
    }
    override var isFlipped:Bool{true}
    var props=Props(){didSet{needsLayout=true}}
    var onChoose:((WorkspaceColourMode.Channel,String?)->Void)?
    var onApplyDesign:((NodeDesign)->Void)?
    var onClose:(()->Void)?
    private let closeButton=ClickCursorButton(title:"Done · Esc",target:nil,action:nil)
    private let backgroundPalette=Palette(.background)
    private let textPalette=Palette(.text)
    private let borderPalette=Palette(.border)
    private let customPalette=CustomPalette(frame:.zero)
    private let lowerScroll=NSScrollView()
    private let lowerCanvas=Canvas()
    private let customRule=Rule(frame:.zero)
    private let myDesigns=MyDesigns(frame:.zero)
    private let contextMenu=SwissContextMenu()
    private var sampler:NSColorSampler?
    private var repeatSampling=false
    private let customKey=WorkspaceCustomColours.key
    private let designsKey="Workspace.NodeColours.Designs"
    private var customColours:[String]=[]
    private var savedDesigns:[NodeDesign]=[]
    private var selection:[WorkspaceColourMode.Target]=[]
    private var selectionIDs:[String]=[]
    override init(frame:NSRect){
        super.init(frame:frame);wantsLayer=true;layer?.backgroundColor=Design.card.cgColor
        closeButton.isBordered=false;closeButton.font=Design.Text.body.font();closeButton.contentTintColor=Design.ink
        closeButton.target=self;closeButton.action=#selector(close)
        [closeButton,backgroundPalette,textPalette,borderPalette,lowerScroll].forEach{addSubview($0)}
        lowerScroll.drawsBackground=false;lowerScroll.hasVerticalScroller=true;lowerScroll.hasHorizontalScroller=false;lowerScroll.autohidesScrollers=true;lowerScroll.scrollerStyle = .overlay
        lowerScroll.documentView=lowerCanvas
        [customPalette,customRule,myDesigns].forEach{lowerCanvas.addSubview($0)}
        customColours=WorkspaceCustomColours.all()
        customPalette.setColours(customColours)
        if let data=AppPreferences.shared.data(forKey:designsKey) {savedDesigns=(try? JSONDecoder().decode([NodeDesign].self,from:data)) ?? []}
        myDesigns.setDesigns(savedDesigns)
        for palette in [backgroundPalette,textPalette,borderPalette] {
            palette.onChoose={ [weak self] channel,hex in self?.onChoose?(channel,hex);self?.refreshCustomSelection() }
            palette.onAddToCustom={ [weak self] hex,point,view in self?.showAddToCustom(hex,at:point,in:view) }
        }
        customPalette.onApply={ [weak self] hex,point,view in self?.showApplyCustom(hex,at:point,in:view) }
        customPalette.onSample={ [weak self] in self?.sampleScreen() }
        customPalette.onRepeatSample={ [weak self] in self?.sampleScreen(repeating:true) }
        customPalette.onRemove={ [weak self] hexes,point,view in self?.showRemoveCustom(hexes,at:point,in:view) }
        myDesigns.onSave={ [weak self] in self?.saveCurrentDesign() }
        myDesigns.onApply={ [weak self] design in self?.onApplyDesign?(design) }
        myDesigns.onRemove={ [weak self] design,point,view in self?.showRemoveDesign(design,at:point,in:view) }
        myDesigns.onRename={ [weak self] design,name in self?.renameDesign(design,to:name) }
        myDesigns.onDelete={ [weak self] design in self?.deleteDesign(design) }
    }
    required init?(coder:NSCoder){fatalError()}
    @objc private func close(){repeatSampling=false;onClose?()}
    func setSelection(_ targets:[WorkspaceColourMode.Target]){
        let storedColours=WorkspaceCustomColours.all()
        if storedColours != customColours {customColours=storedColours;customPalette.setColours(storedColours);needsLayout=true}
        let ids=targets.map(\.id)
        if ids != selectionIDs {myDesigns.clearActiveDesign();selectionIDs=ids}
        selection=targets
        for (channel,palette) in [(WorkspaceColourMode.Channel.background,backgroundPalette),(.text,textPalette),(.border,borderPalette)] {
            let values=targets.map{$0.visible(channel).flatMap(hexOf)?.uppercased()}
            palette.setCurrent(hexes:Set(values.compactMap{$0}),includesNoColour:values.contains{$0 == nil})
        }
        refreshCustomSelection()
        let target=targets.first
        let design=target.map{target in NodeDesign(id:UUID(),name:"Current selection",background:target.visible(.background).flatMap(hexOf)?.uppercased(),text:target.visible(.text).flatMap(hexOf)?.uppercased(),border:target.visible(.border).flatMap(hexOf)?.uppercased())}
        myDesigns.setCurrent(design,nodeName:target?.name ?? "Select a node",count:targets.count)
    }
    private func refreshCustomSelection(){
        let colours=selection.flatMap{target in
            [WorkspaceColourMode.Channel.background,.text,.border].compactMap{target.visible($0).flatMap(hexOf)?.uppercased()}
        }
        customPalette.setCurrent(Set(colours))
    }
    private func showApplyCustom(_ hex:String,at point:NSPoint,in view:NSView){
        let choices:[(WorkspaceColourMode.Channel,String)]=[(.background,"Apply To Background"),(.text,"Apply To Text"),(.border,"Apply To Border")]
        contextMenu.open(choices.map{channel,label in
            HaloAction(id:"apply-custom-\(label)",label:label,symbol:"paintbrush",onSelect:{[weak self] in
                self?.onChoose?(channel,hex)
                self?.refreshCustomSelection()
            })
        },at:point,in:view)
    }
    @discardableResult func addCustomColours(_ hexes:[String])->Int {
        let added=WorkspaceCustomColours.add(hexes)
        guard added > 0 else{return 0}
        customColours=WorkspaceCustomColours.all()
        customPalette.setColours(customColours)
        needsLayout=true
        return added
    }
    private func showAddToCustom(_ hex:String,at point:NSPoint,in view:NSView){
        contextMenu.open([HaloAction(id:"add-custom",label:"Add To Custom Palette",symbol:"plus.square.fill",onSelect:{[weak self] in _ = self?.addCustomColours([hex])})],at:point,in:view)
    }
    private func showRemoveCustom(_ hexes:[String],at point:NSPoint,in view:NSView){
        let label=hexes.count == 1 ? "Remove From Custom Palette" : "Remove \(hexes.count) From Custom Palette"
        contextMenu.open([HaloAction(id:"remove-custom",label:label,symbol:"minus.square",onSelect:{[weak self] in
            guard let self else{return};let removing=Set(hexes);self.customColours.removeAll{removing.contains($0)};AppPreferences.shared.set(self.customColours,forKey:self.customKey);self.customPalette.setColours(self.customColours);self.needsLayout=true
        })],at:point,in:view)
    }
    private func sampleScreen(repeating:Bool=false){
        guard sampler == nil else{return}
        repeatSampling=repeating
        showNextSample()
    }
    private func showNextSample(){
        let picker=NSColorSampler();sampler=picker
        picker.show { [weak self] colour in
            guard let self else{return};self.sampler=nil
            guard let colour else{self.repeatSampling=false;return}
            if let hex=hexOf(colour){_ = self.addCustomColours([hex])}
            if self.repeatSampling {DispatchQueue.main.async{[weak self] in self?.showNextSample()}}
        }
    }
    private func saveCurrentDesign(){
        guard let target=selection.first else{return}
        let number=(savedDesigns.compactMap{design -> Int? in
            guard design.name.hasPrefix("Design ") else{return nil}
            return Int(design.name.dropFirst(7))
        }.max() ?? 0)+1
        let design=NodeDesign(id:UUID(),name:"Design \(number)",background:target.visible(.background).flatMap(hexOf)?.uppercased(),text:target.visible(.text).flatMap(hexOf)?.uppercased(),border:target.visible(.border).flatMap(hexOf)?.uppercased())
        savedDesigns.append(design);persistDesigns()
    }
    private func showRemoveDesign(_ design:NodeDesign,at point:NSPoint,in view:NSView){
        contextMenu.open([
            HaloAction(id:"rename-design",label:"Rename \(design.name)",symbol:"pencil",onSelect:{[weak view] in
                (view as? DesignPreview)?.beginRename(selectAll:true,at:.zero)
            }),
            HaloAction(id:"remove-design",label:"Remove \(design.name)",symbol:"minus.square",onSelect:{[weak self] in
                self?.deleteDesign(design)
            })
        ],at:point,in:view)
    }
    private func renameDesign(_ design:NodeDesign,to name:String){
        guard let index=savedDesigns.firstIndex(where:{$0.id == design.id}) else{return}
        savedDesigns[index].name=name;persistDesigns()
    }
    private func deleteDesign(_ design:NodeDesign){
        savedDesigns.removeAll{$0.id == design.id};persistDesigns()
    }
    private func persistDesigns(){
        if let data=try? JSONEncoder().encode(savedDesigns){AppPreferences.shared.set(data,forKey:designsKey)}
        myDesigns.setDesigns(savedDesigns)
        needsLayout=true
    }
    override func layout(){
        super.layout()
        let minimumGap:CGFloat=28,top:CGFloat=52
        closeButton.frame=NSRect(x:max(minimumGap,bounds.width-118),y:14,width:88,height:27)
        let palettes=[(backgroundPalette,props.background),(textPalette,props.text),(borderPalette,props.border)]
        let visible=palettes.filter{$0.1}.map{$0.0}
        let count=CGFloat(max(1,visible.count))
        let fullGridWidth:CGFloat=15*25.5+14*6
        let paletteWidth=min(fullGridWidth,max(0,(bounds.width-minimumGap*(count+1))/count))
        let gap=max(0,(bounds.width-CGFloat(visible.count)*paletteWidth)/(count+1))
        let paletteHeight=min(612,max(240,bounds.height-top-250))
        for (palette,enabled) in palettes {palette.isHidden = !enabled}
        for (index,palette) in visible.enumerated(){palette.frame=NSRect(x:gap+CGFloat(index)*(paletteWidth+gap),y:top,width:paletteWidth,height:paletteHeight)}
        let lowerTop=top+paletteHeight+20
        let lowerWidth=max(0,bounds.width-2*gap)
        lowerScroll.frame=NSRect(x:gap,y:lowerTop,width:lowerWidth,height:max(0,bounds.height-lowerTop-12))
        let customHeight=customPalette.contentHeight(for:paletteWidth)
        let designsTop=customHeight+24
        let designHeight=myDesigns.contentHeight(for:lowerWidth)
        lowerCanvas.frame=NSRect(x:0,y:0,width:lowerWidth,height:designsTop+designHeight+8)
        customPalette.frame=NSRect(x:0,y:0,width:paletteWidth,height:customHeight)
        customRule.frame=NSRect(x:0,y:customHeight+12,width:lowerWidth,height:1)
        myDesigns.frame=NSRect(x:0,y:designsTop,width:lowerWidth,height:designHeight)
        needsDisplay=true
    }
    override func draw(_ dirtyRect:NSRect){
        fill(bounds,Design.card)
        hairline(x:0,y:0,width:bounds.width,Design.rule)
        ("Choose node colours" as NSString).draw(in:NSRect(x:28,y:17,width:max(0,bounds.width-168),height:24),
            withAttributes:[.font:Design.Text.heading.font(),.foregroundColor:Design.ink])
        let visible=[backgroundPalette,textPalette,borderPalette].filter{!$0.isHidden}
        if let first=visible.first,let last=visible.last {
            let start=first.frame.minX
            hairline(x:start,y:first.frame.maxY+8,width:max(0,last.frame.maxX-start),Design.rule)
        }
    }
    private static func hslHex(_ hue:Double,_ saturation:Double,_ lightness:Double)->String{
        let h=hue/360,s=saturation/100,l=lightness/100
        let q=l < 0.5 ? l*(1+s):l+s-l*s,p=2*l-q
        func channel(_ offset:Double)->Int{
            var t=h+offset
            if t < 0{t += 1};if t > 1{t -= 1}
            let value=t < 1/6 ? p+(q-p)*6*t:t < 1/2 ? q:t < 2/3 ? p+(q-p)*(2/3-t)*6:p
            return Int((value*255).rounded())
        }
        return String(format:"#%02X%02X%02X",channel(1/3),channel(0),channel(-1/3))
    }
}
