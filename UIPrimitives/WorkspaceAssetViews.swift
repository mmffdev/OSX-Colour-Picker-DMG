import AppKit
import CoreText
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
    enum Kind:Equatable {case palettes,fonts,images}
    struct Entry {
        enum Content {case palette(UUID,[String]),font(UUID,String),image(String,Date?)}
        let title:String,content:Content
        var identity:String {
            switch content {
            case .palette(let id,_),.font(let id,_):return id.uuidString
            case .image(let path,_):return path
            }
        }
    }
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
        override var handCursorRects:[NSRect]{[NSRect(x:0,y:0,width:min(bounds.width,CGFloat(entries.count)*112),height:bounds.height)]}
        private var pressedEntry:Entry?
        private var press:(NSPoint,TimeInterval)=(.zero,0)
        var entries:[Entry]=[] {didSet{needsDisplay=true}}
        var selected:String? {didSet{needsDisplay=true}}
        var displayColours: [String:NSColor] = [:]
        var imagePreview:((String,Date?)->NSImage?)?
        var onPick:((Entry)->Void)?
        override var isFlipped:Bool{true}
        override func draw(_ dirtyRect:NSRect){
            for (i,entry) in entries.enumerated(){
                let box=NSRect(x:CGFloat(i)*112+8,y:8,width:96,height:48)
                guard box.insetBy(dx:-8,dy:-8).intersects(dirtyRect) else{continue}
                switch entry.content {
                case .palette(_,let colours):
                    if colours.isEmpty{fill(box,Design.mist)}
                    for (j,hex) in colours.enumerated(){fill(NSRect(x:box.minX+CGFloat(j)*box.width/CGFloat(max(1,colours.count)),y:box.minY,width:box.width/CGFloat(max(1,colours.count))+0.5,height:box.height),displayColours[hex] ?? Design.hex(hex))}
                case .font(_,let family):
                    fill(box,Design.mist)
                    let font=NSFont(name:family,size:32) ?? NSFontManager.shared.font(withFamily:family,traits:[],weight:5,size:32) ?? NSFont.systemFont(ofSize:32)
                    let face=CTFontCreateWithName(font.fontName as CFString,32,nil)
                    let sample=NSAttributedString(string:"Aa",attributes:[kCTFontAttributeName as NSAttributedString.Key:face,.foregroundColor:Design.ink])
                    let line=CTLineCreateWithAttributedString(sample)
                    let ink=CTLineGetImageBounds(line,nil)
                    if let context=NSGraphicsContext.current?.cgContext,ink.width > 0,ink.height > 0 {
                        context.saveGState()
                        context.textMatrix=CGAffineTransform(scaleX:1,y:-1)
                        context.textPosition=CGPoint(x:box.midX-ink.midX,y:box.midY+ink.midY)
                        CTLineDraw(line,context)
                        context.restoreGState()
                    }
                case .image(let path,let modified):
                    fill(box,Design.mist)
                    if let image=imagePreview?(path,modified) {
                        let ratio=min(box.width/max(1,image.size.width),box.height/max(1,image.size.height))
                        let size=NSSize(width:image.size.width*ratio,height:image.size.height*ratio)
                        image.draw(in:NSRect(x:box.midX-size.width/2,y:box.midY-size.height/2,width:size.width,height:size.height))
                    }
                }
                if selected == entry.identity {Design.ink.setStroke();let path=NSBezierPath(rect:box.insetBy(dx:-3,dy:-3));path.lineWidth=2;path.stroke()}
                Design.attributed(entry.title,.body).draw(x:box.minX,baseline:76,width:96)
            }
        }
        private func entry(at point:NSPoint)->Entry? {
            guard bounds.contains(point) else{return nil}
            let index=Int(point.x/112)
            return entries.indices.contains(index) ? entries[index]:nil
        }
        override func mouseDown(with event:NSEvent){
            pressedEntry=entry(at:convert(event.locationInWindow,from:nil))
            press=(event.locationInWindow,event.timestamp)
        }
        override func mouseDragged(with event:NSEvent){
            guard let entry=pressedEntry,PaletteDrag.counts(event,from:press) else{return}
            pressedEntry=nil
            if case .palette(let id,let colours)=entry.content {
                PaletteDrag.begin(id,name:entry.title,colours:colours.map{displayColours[$0] ?? Design.hex($0)},event:event,in:self)
            }
        }
        override func mouseUp(with event:NSEvent){
            defer{pressedEntry=nil}
            guard let pressedEntry,!PaletteDrag.counts(event,from:press),
                  entry(at:convert(event.locationInWindow,from:nil))?.identity == pressedEntry.identity else{return}
            onPick?(pressedEntry)
        }
        func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext)->NSDragOperation {.copy}
    }
    private let scroll=CarouselScroll(),strip=Strip()
    private var kind:Kind = .palettes
    var onPick:((Entry)->Void)?
    var imagePreview:((String,Date?)->NSImage?)? {didSet{strip.imagePreview=imagePreview}}
    override var isFlipped:Bool{true}
    override init(frame:NSRect){super.init(frame:frame);wantsLayer=true;layer?.backgroundColor=Design.card.cgColor;scroll.drawsBackground=false;scroll.hasHorizontalScroller=true;scroll.horizontalScrollElasticity = .none;scroll.verticalScrollElasticity = .none;scroll.autohidesScrollers=false;QuietScroller.install(in:scroll);scroll.documentView=strip;addSubview(scroll);strip.onPick={[weak self] in self?.onPick?($0)};setAccessibilityLabel("Asset Carousel")}
    required init?(coder:NSCoder){fatalError()}
    func update(kind:Kind,entries:[Entry],selected:String?,colours:[String:NSColor] = [:]){
        self.kind=kind;strip.displayColours=colours;strip.entries=entries;strip.selected=selected
        setAccessibilityLabel(kind == .palettes ? "Palette Carousel":kind == .fonts ? "Font Carousel":"Image Carousel")
        needsLayout=true;needsDisplay=true
    }
    func update(_ palettes:[Swatch],selected:UUID?,colours:[String:NSColor] = [:]){
        update(kind:.palettes,entries:palettes.map{Entry(title:$0.name,content:.palette($0.id,$0.entries.map(\.hex)))},selected:selected?.uuidString,colours:colours)
    }
    func select(_ identity:String?){strip.selected=identity}
    func imagePreviewReady(){strip.needsDisplay=true}
    override func layout(){super.layout();scroll.frame=NSRect(x:8,y:24,width:bounds.width-16,height:bounds.height-24);strip.frame=NSRect(x:0,y:0,width:max(scroll.contentSize.width,CGFloat(strip.entries.count)*112+8),height:84)}
    override func draw(_ dirtyRect:NSRect){
        hairline(x:0,y:0,width:bounds.width)
        let noun=kind == .palettes ? "Palettes":kind == .fonts ? "Fonts":"Images"
        Design.attributed("\(noun) · \(strip.entries.count)",.body,colour:Design.quiet).draw(x:16,baseline:19)
    }
}
