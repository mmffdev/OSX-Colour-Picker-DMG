import AppKit
import UniformTypeIdentifiers
import ImageIO

final class WorkspaceInspector:NSView,WorkspaceScrollableContent {
    var minimumContentHeight:CGFloat {345}
    var palette:Swatch? {didSet{needsDisplay=true;open.isEnabled=palette != nil;target.isEnabled=palette != nil}}
    var catalogue="" {didSet{needsDisplay=true}}
    var displayColours: [String:NSColor] = [:] {didSet{needsDisplay=true}}
    var total=0 {didSet{needsDisplay=true}}
    var onOpen:(()->Void)?,onTarget:(()->Void)?
    private let open=SwissButton("Open Swatches",.primary),target=SwissButton("Set Picker Target",.secondary)
    override var isFlipped:Bool{true}
    override init(frame:NSRect){super.init(frame:frame);wantsLayer=true;layer?.backgroundColor=Design.card.cgColor
        open.target=self;open.action=#selector(openPalette);target.target=self;target.action=#selector(targetPalette)
        [open,target].forEach{addSubview($0)}
    }
    required init?(coder:NSCoder){fatalError()}
    @objc private func openPalette(){onOpen?()}
    @objc private func targetPalette(){onTarget?()}
    override func layout(){super.layout();open.frame=NSRect(x:16,y:196,width:bounds.width-32,height:32);target.frame=NSRect(x:16,y:236,width:bounds.width-32,height:32)}
    override func draw(_ dirtyRect:NSRect){
        Design.attributed("Selection",.bodyStrong).draw(x:16,baseline:28)
        Design.attributed(palette?.name ?? "Select A Palette",.bodyStrong).draw(x:16,baseline:60,width:bounds.width-32)
        let colours=palette?.entries.map{displayColours[$0.hex] ?? Design.hex($0.hex)} ?? []
        let box=NSRect(x:16,y:76,width:bounds.width-32,height:64)
        if colours.isEmpty{fill(box,Design.mist)}else{for (i,c) in colours.enumerated(){fill(NSRect(x:box.minX+CGFloat(i)*box.width/CGFloat(colours.count),y:box.minY,width:box.width/CGFloat(colours.count)+0.5,height:box.height),c)}}
        Design.attributed(palette.map{"\($0.entries.count) Colours"} ?? "\(total) Palettes In Catalogue",.body,colour:Design.quiet).draw(x:16,baseline:168,width:bounds.width-32)
        hairline(x:0,y:292,width:bounds.width)
        Design.attributed(catalogue,.body,colour:Design.quiet).draw(x:16,baseline:320,width:bounds.width-32)
        hairline(x:0,y:344,width:bounds.width)
    }
}

final class WorkspaceFilmstrip:NSView {
    private final class CarouselScroll:NSScrollView {
        override func scrollWheel(with event:NSEvent) {
            guard let documentView else{return}
            let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
            let step = delta * (event.hasPreciseScrollingDeltas ? 1 : 16)
            let limit = max(0,documentView.bounds.width-contentSize.width)
            let next = max(0,min(limit,contentView.bounds.origin.x-step))
            contentView.scroll(to:NSPoint(x:next,y:0))
            reflectScrolledClipView(contentView)
        }
    }
    final class Strip:ClickCursorView,NSDraggingSource {
    override var handCursorRects:[NSRect]{[NSRect(x:0,y:0,width:min(bounds.width,CGFloat(palettes.count)*112),height:bounds.height)]}

        private var pressedPalette:Swatch?
        private var press:(NSPoint,TimeInterval)=(.zero,0)
        var palettes:[Swatch]=[] {didSet{needsDisplay=true}}
        var selected:UUID? {didSet{needsDisplay=true}}
        var displayColours: [String:NSColor] = [:]
        var onPick:((UUID)->Void)?
        override var isFlipped:Bool{true}
        override func draw(_ dirtyRect:NSRect){for (i,palette) in palettes.enumerated(){let box=NSRect(x:CGFloat(i)*112+8,y:8,width:96,height:48);guard box.insetBy(dx:-8,dy:-8).intersects(dirtyRect) else{continue};let colours=palette.entries;for (j,c) in colours.enumerated(){fill(NSRect(x:box.minX+CGFloat(j)*box.width/CGFloat(max(1,colours.count)),y:box.minY,width:box.width/CGFloat(max(1,colours.count))+0.5,height:box.height),displayColours[c.hex] ?? Design.hex(c.hex))};if selected==palette.id{Design.ink.setStroke();let path=NSBezierPath(rect:box.insetBy(dx:-3,dy:-3));path.lineWidth=2;path.stroke()};Design.attributed(palette.name,.body).draw(x:box.minX,baseline:76,width:96)}}
        private func palette(at point:NSPoint)->Swatch? {
            guard bounds.contains(point) else{return nil}
            let index=Int(point.x/112)
            return palettes.indices.contains(index) ? palettes[index]:nil
        }
        override func mouseDown(with event:NSEvent){
            pressedPalette=palette(at:convert(event.locationInWindow,from:nil))
            press=(event.locationInWindow,event.timestamp)
        }
        override func mouseDragged(with event:NSEvent){
            guard let palette=pressedPalette,PaletteDrag.counts(event,from:press) else{return}
            pressedPalette=nil
            PaletteDrag.begin(palette.id,name:palette.name,colours:palette.entries.map{displayColours[$0.hex] ?? Design.hex($0.hex)},event:event,in:self)
        }
        override func mouseUp(with event:NSEvent){
            defer{pressedPalette=nil}
            guard let pressedPalette,!PaletteDrag.counts(event,from:press),
                  palette(at:convert(event.locationInWindow,from:nil))?.id == pressedPalette.id else{return}
            onPick?(pressedPalette.id)
        }
        func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext)->NSDragOperation {.copy}
    }
    private let scroll=CarouselScroll(),strip=Strip()
    var onPick:((UUID)->Void)?
    override var isFlipped:Bool{true}
    override init(frame:NSRect){super.init(frame:frame);wantsLayer=true;layer?.backgroundColor=Design.card.cgColor;scroll.drawsBackground=false;scroll.hasHorizontalScroller=true;scroll.horizontalScrollElasticity = .none;scroll.verticalScrollElasticity = .none;scroll.autohidesScrollers=true;scroll.documentView=strip;addSubview(scroll);strip.onPick={[weak self] in self?.onPick?($0)};setAccessibilityLabel("Footer palette carousel")}
    required init?(coder:NSCoder){fatalError()}
    func update(_ palettes:[Swatch],selected:UUID?, colours:[String:NSColor] = [:]){strip.displayColours=colours;strip.palettes=palettes;strip.selected=selected;needsLayout=true}
    override func layout(){super.layout();scroll.frame=NSRect(x:8,y:24,width:bounds.width-16,height:bounds.height-24);strip.frame=NSRect(x:0,y:0,width:max(scroll.contentSize.width,CGFloat(strip.palettes.count)*112+8),height:84)}
    override func draw(_ dirtyRect:NSRect){hairline(x:0,y:0,width:bounds.width);Design.attributed("All Palettes · \(strip.palettes.count)",.body,colour:Design.quiet).draw(x:16,baseline:19)}
}
