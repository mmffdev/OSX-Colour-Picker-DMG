import AppKit
import QuartzCore
import UniformTypeIdentifiers
import ImageIO

/// The tiles: `across` to a row, or as many as there are when fewer, 16 apart and justified to the block
/// so the first and last meet the Rule's ends; each a Card with its colour block 116 high over a name and
/// a caption. A colour tile carries one colour and its hex; a palette card a strip of its colours
/// and its count, and opens the palette.
final class TileGrid: ClickCursorView, NSDraggingSource {
    override var handCursorRects:[NSRect]{
        let stride:CGFloat=listView ? listRowHeight:gridStride,multiplier=listView ? 1:columns
        let first=min(items.count,max(0,Int(floor((visibleRect.minY-contentInset)/stride)))*multiplier)
        let last=min(items.count,max(0,Int(ceil((visibleRect.maxY-contentInset)/stride))+1)*multiplier)
        return (first..<max(first,last)).filter{items[$0].hex != nil || items[$0].id != nil || displaysImages}.map{rect($0)}+markHits.map{$0.0}+noteHits.map{$0.0}+tagHits.map{$0.0}
    }

    struct Item { let title: String; let caption: String; let colours: [NSColor]; let hex: String?; let id: UUID?; var sourceCMYK: String? = nil; var image:NSImage? = nil; var imagePath:String? = nil; var captureDate:Date? = nil; var metadata:[String:String] = [:]; var paletteColourCount:Int=0; var paletteBars:[NSColor]=[]; var linkedReference=false; var editingLocked=false; var createdAt:Date?=nil; var modifiedAt:Date?=nil; var selectionID:String?=nil }
    var paletteReview:((UUID)->(name:String,review:PaletteReview)?)?
    var onPaletteRating:((UUID,Int)->Void)?
    var onPaletteFlag:((UUID,PaletteReview.Flag?)->Void)?
    private var reviews:[UUID:PaletteReviewControls]=[:]
    private struct CopyRow:Hashable {let item:Int;let row:Int}
    private var valueCopyButtons:[CopyRow:PaletteAssetIcon]=[:]
    private var cardPreferenceObserver:NSObjectProtocol?
    private var cardPreferenceKey=""
    private struct CardTextKey: Hashable {
        let hex:String
        let caption:String
        let sourceCMYK:String?
        let format:ColourFormat
        let lowercase:Bool
    }
    private var cardTextCache:[CardTextKey:String]=[:]
    private var cardFormats:[ColourFormat]=[]
    private var lowercaseCardValues=false
    private var maximumValueRows=0
    private var hasSwatches=false
    private var cardShowsNames=true
    private var swatchBlockHeight:CGFloat=TileGrid.block
    private var swatchMinimumWidth:CGFloat=240
    private var showsPaletteBars=false
    private func cardText(_ item:Item,_ format:ColourFormat,_ lowercase:Bool)->String {
        guard let hex=item.hex else{return ""}
        let key=CardTextKey(hex:hex,caption:item.caption,sourceCMYK:item.sourceCMYK,format:format,lowercase:lowercase)
        if let cached=cardTextCache[key]{return cached}
        let text:String
        if format == .cmyk,item.caption.hasPrefix("CMYK") {text=item.caption}
        else if item.sourceCMYK != nil,format != .cmyk,format != .hex {text=format.label+" Unavailable — No Source ICC"}
        else {text=format.label+" "+(format == .cmyk ? item.sourceCMYK ?? format.text(hex):format.text(hex,lowercase:lowercase))}
        if cardTextCache.count >= 8192 {cardTextCache.removeAll(keepingCapacity:true)}
        cardTextCache[key]=text
        return text
    }
    private func refreshCardSettings(force:Bool=false){
        let formats=Prefs.houseCardRows
        let key=formats.map(\.rawValue).joined(separator:",")+"|\(Prefs.showNames)|\(Prefs.tileSize.rawValue)|\(Prefs.showPaletteBars)|\(Prefs.lowercaseHex)"
        guard force || key != cardPreferenceKey else{return}
        let oldCardHeight=gridCardHeight,oldListHeight=listRowHeight,oldColumns=columns
        if force {cardTextCache.removeAll()}
        cardPreferenceKey=key;cardShowsNames=Prefs.showNames;hasSwatches=items.contains{$0.hex != nil}
        swatchBlockHeight=CGFloat(Prefs.tileSize.points)+32
        swatchMinimumWidth=[CGFloat(224),272,336][Prefs.tileSize.rawValue]
        showsPaletteBars=Prefs.showPaletteBars
        cardFormats=formats
        lowercaseCardValues=Prefs.lowercaseHex
        maximumValueRows=hasSwatches ? formats.count:0
        // A fixed value column keeps card geometry stable while rows are formatted on demand.
        // No colour conversion or text measurement is needed for off-screen cards.
        captionMinimumWidth=hasSwatches && !formats.isEmpty ? 280:0
        let geometryChanged=force || oldCardHeight != gridCardHeight || oldListHeight != listRowHeight || oldColumns != columns
        if force {clearReviewControls()}
        if geometryChanged {onResize?();needsLayout=true}
        else {syncReviewControls()}
        setNeedsDisplay(visibleRect)
    }
    private func valueRows(for item:Item)->[String] {
        guard item.hex != nil else{return []}
        return cardFormats.map{cardText(item,$0,lowercaseCardValues)}
    }

    private var clipObserver:NSObjectProtocol?
    private func clearReviewControls(){reviews.values.forEach{$0.dismissOverlay();$0.removeFromSuperview()};reviews=[:];valueCopyButtons.values.forEach{$0.removeFromSuperview()};valueCopyButtons=[:]}
    deinit{pendingBandClick?.invalidate();if let cardPreferenceObserver{NotificationCenter.default.removeObserver(cardPreferenceObserver)};if let clipObserver{NotificationCenter.default.removeObserver(clipObserver)}}
    override func viewDidMoveToWindow(){
        super.viewDidMoveToWindow()
        if cardPreferenceObserver == nil {cardPreferenceObserver=NotificationCenter.default.addObserver(forName:.prefsDidChange,object:nil,queue:.main){ [weak self] _ in self?.refreshCardSettings() }}
        refreshCardSettings()
        if let clipObserver{NotificationCenter.default.removeObserver(clipObserver)};clipObserver=nil
        if let clip=enclosingScrollView?.contentView,window != nil {
            clip.postsBoundsChangedNotifications=true
            clipObserver=NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:clip,queue:.main){ [weak self] _ in self?.syncReviewControls() }
        }
        syncReviewControls()
    }
    override func layout(){super.layout();syncReviewControls()}
    private func syncReviewControls(){
        guard window != nil,!displaysImages else{clearReviewControls();return}
        let visible=visibleRect
        let stride:CGFloat=listView ? listRowHeight:gridStride
        let firstRow=max(0,Int(floor((visible.minY-contentInset)/stride))),lastRow=max(firstRow,Int(ceil((visible.maxY-contentInset)/stride))+1)
        let multiplier=listView ? 1:columns,first=min(items.count,firstRow*multiplier),last=min(items.count,lastRow*multiplier)
        var keep=Set<UUID>(),copyKeep=Set<CopyRow>()
        for i in first..<last {
            if let hex=items[i].hex {
                for (row,text) in valueRows(for:items[i]).enumerated() {
                    let key=CopyRow(item:i,row:row);copyKeep.insert(key)
                    let item=items[i],button=valueCopyButtons[key] ?? PaletteAssetIcon(frame:.zero)
                    if valueCopyButtons[key] == nil{valueCopyButtons[key]=button;addSubview(button)}
                    let r=rect(i),baseline=captionBaseline(r)+CGFloat(row)*Design.App.unit
                    let x=listView ? colourBlock(r).maxX+16:r.minX+cardInset
                    button.symbol="doc.on.doc";button.ink=ink(on:canvasColour,secondary:true)
                    button.frame=NSRect(x:x,y:baseline-15,width:18,height:20)
                    button.setAccessibilityLabel("Copy "+text);button.toolTip="Copy "+text
                    button.isEnabled = !text.contains("Unavailable")
                    button.run={ [weak self] in ColourCopies.copy(hex,text:text,sourceCMYK:item.sourceCMYK);self?.onCopy?(text) }
                }
            }
            guard let id=items[i].id,let palette=paletteReview?(id) else{continue}
            keep.insert(id)
            let controls:PaletteReviewControls
            if let existing=reviews[id]{controls=existing}else{
                controls=PaletteReviewControls(frame:.zero);reviews[id]=controls;addSubview(controls)
                controls.onRating={ [weak self] value in self?.onPaletteRating?(id,value) }
                controls.onFlag={ [weak self] value in self?.onPaletteFlag?(id,value) }
            }
            controls.configure(name:palette.name,review:palette.review)
            controls.isReadOnly = items[i].editingLocked
            let r=rect(i),baseline=listView ? r.minY+25:r.minY+cardHeader+Self.block+Design.App.textBaseline
            controls.ink=ink(on:isSelected(items[i]) ? Design.mist:canvasColour)
            controls.frame=NSRect(x:r.maxX-cardInset-PaletteReviewControls.width-(items[i].linkedReference && listView ? 24:0),y:baseline-17,width:PaletteReviewControls.width,height:24)
        }
        for i in Array(valueCopyButtons.keys) where !copyKeep.contains(i){valueCopyButtons[i]?.removeFromSuperview();valueCopyButtons.removeValue(forKey:i)}
        for id in Array(reviews.keys) where !keep.contains(id){reviews[id]?.dismissOverlay();reviews[id]?.removeFromSuperview();reviews.removeValue(forKey:id)}
    }
    func refreshReviewControls(){syncReviewControls();setNeedsDisplay(visibleRect)}
    private var selection = AssetSelection<String>()
    private var focusedAsset: String?
    var selectionScope = "" { didSet {
        if oldValue != selectionScope { selection = AssetSelection(); focusedAsset = nil; needsDisplay = true }
    } }
    var onSelectionChanged: (() -> Void)?
    var onSelectionEdited: (() -> Void)?
    var onDeleteSelection: (() -> Void)?
    var onCopySelection: (() -> Void)?
    @objc func copy(_ sender:Any?) {onCopySelection?()}
    override func selectAll(_ sender:Any?) {selection.ids=Set(selectionOrder);selection.anchor=selectionOrder.first;selectionChanged()}
    var selectedItems: [Item] { items.filter(isSelected) }
    var selectedCount: Int { selectedItems.count }
    var onImageSelectionChanged: ((Set<String>) -> Void)?
    private var selectionOrder: [String] { items.map(identity) }
    func hasSameIdentities(as other:[Item])->Bool {
        items.count == other.count && zip(items,other).allSatisfy{identity($0.0)==identity($0.1)}
    }
    private func isSelected(_ item: Item) -> Bool {
        imageIntake ? item.imagePath.map(selectedImagePaths.contains) == true : selection.ids.contains(identity(item))
    }
    private func selectionChanged() {
        if imageIntake {
            let paths = Set(items.filter { selection.ids.contains(identity($0)) }.compactMap(\.imagePath))
            selectedImagePaths = paths; onImageSelectionChanged?(paths)
        }
        setAccessibilityLabel("Asset Grid, \(selection.ids.count) Selected")
        setAccessibilityHelp("Click to select. Shift-click selects a range. Command-click adds or removes an asset. Double-click opens.")
        needsDisplay = true; syncReviewControls(); onSelectionChanged?(); onSelectionEdited?()
    }
    private func selectAsset(_ index: Int, modifiers: NSEvent.ModifierFlags) {
        guard items.indices.contains(index) else { return }
        if imageIntake { selection.ids = Set(items.filter { $0.imagePath.map(selectedImagePaths.contains) == true }.map(identity)) }
        let key = identity(items[index]); focusedAsset = key
        selection.click(key, order: selectionOrder, extend: modifiers.contains(.shift), toggle: modifiers.contains(.command))
        selectionChanged()
    }
    private var pendingBandClick:Timer?
    private var pressedPalette:Item?
    private var palettePress:(NSPoint,TimeInterval)=(.zero,0)
    var items: [Item] = [] { didSet {
        itemKeys=Set(items.map(identity))
        imageIndexByPath=Dictionary(items.enumerated().compactMap{index,item -> (String,Int)? in item.imagePath.map{($0,index)}},uniquingKeysWith:{first,_ in first})
        selection.retain(selectionOrder)
        if let focusedAsset, !selectionOrder.contains(focusedAsset) { self.focusedAsset = nil }
        if let focusedImagePath,let index=items.firstIndex(where:{$0.imagePath==focusedImagePath}){currentImageIndex=index}
        else{currentImageIndex=min(currentImageIndex,max(0,items.count-1))}
        if items.indices.contains(currentImageIndex){focusedImagePath=items[currentImageIndex].imagePath}
        refreshCardSettings(force:true)
        pendingPrintItems.removeAll();pendingPrintKeys.removeAll();splitOverrides=[:];needsLayout=true;onSelectionChanged?()
    } }
    /// Words shown in place of tiles when there are none, as a member's notes on its Information page; nil says Nothing Found.
    var note: String? { didSet { needsDisplay = true } }
    var across = 8 { didSet { onResize?() } }
    var imageIntake=false {didSet{needsDisplay=true}}
    /// Palette files in Import use the same framed card geometry as Library palettes.
    /// Import selection is the only additional control on that card.
    var importPaletteCards=false {didSet{guard oldValue != importPaletteCards else{return};needsLayout=true;needsDisplay=true}}
    var imageLibrary=false {didSet{needsDisplay=true;onResize?()}}
    private var displaysImages:Bool {imageIntake || imageLibrary}
    var onImagePreview:((String,Date?)->NSImage?)?
    private var imageIndexByPath:[String:Int]=[:]
    func imagePreviewReady(at path:String) {
        guard let index=imageIndexByPath[path] else{return}
        let area=rect(index)
        if area.intersects(visibleRect){setNeedsDisplay(area)}
    }
    var fullResolutionImage:NSImage? {didSet{needsDisplay=true}}
    var fullResolutionPath:String?
    var imageFullView=false {didSet{guard oldValue != imageFullView else{return};enclosingScrollView?.contentView.scroll(to:.zero);needsDisplay=true;onResize?()}}
    var fullImageViewportHeight:CGFloat=0 {didSet{needsDisplay=true}}
    var selectedImagePaths=Set<String>() {didSet{
        onSelectionChanged?()
        needsDisplay=true
        let changed=oldValue.symmetricDifference(selectedImagePaths)
        guard !changed.isEmpty else{return}
        for (i,item) in items.enumerated() where item.imagePath.map(changed.contains) == true {
            if imageFullView && i != currentImageIndex {continue}
            let r=rect(i)
            let inset:CGFloat = imageFullView ? 16 : 8
            setNeedsDisplay(NSRect(x:r.minX+inset,y:r.minY+inset,width:16,height:16))
        }
    }}
    var onImageSelectionToggle:((String)->Void)?
    private(set) var currentImageIndex=0
    private var focusedImagePath:String?
    private var lastFullWheelNavigation=Date.distantPast
    var onImagePageChanged:((Int,Int)->Void)?
    private func moveFullImage(_ offset:Int){
        guard displaysImages,imageFullView,!items.isEmpty else{return}
        currentImageIndex=(currentImageIndex+offset+items.count)%items.count
        focusedImagePath=items[currentImageIndex].imagePath
        fullResolutionImage=nil;fullResolutionPath=nil
        onImagePageChanged?(currentImageIndex+1,items.count)
        enclosingScrollView?.contentView.scroll(to:.zero);needsDisplay=true
    }
    var listView=false { didSet {
        guard listView != oldValue else{return}
        enclosingScrollView?.contentView.scroll(to:.zero)
        onResize?();needsLayout=true;syncReviewControls();needsDisplay=true
    } }
    var selectedPalette: UUID? { didSet { needsDisplay = true } }
    var contentInset: CGFloat = 0
    var canvasColour: NSColor = Design.card { didSet {
        wantsLayer = true; layer?.backgroundColor = canvasColour.cgColor; needsDisplay = true
    } }
    private var contentWidth: CGFloat { max(0, width - contentInset * 2) }
    /// Use actual sRGB contrast, including saturated grounds, rather than appearance mode.
    private func ink(on background: NSColor, secondary: Bool = false) -> NSColor {
        func luminance(_ colour: NSColor) -> CGFloat {
            let c = colour.usingColorSpace(.sRGB) ?? .white
            func linear(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v/12.92 : pow((v+0.055)/1.055, 2.4) }
            return 0.2126*linear(c.redComponent)+0.7152*linear(c.greenComponent)+0.0722*linear(c.blueComponent)
        }
        let ground = luminance(background)
        func contrast(_ colour: NSColor) -> CGFloat {
            let value = luminance(colour)
            return (max(value,ground)+0.05)/(min(value,ground)+0.05)
        }
        let primary: NSColor = contrast(Design.ink) >= 4.5 ? Design.ink : (ground > 0.179 ? .black : .white)
        guard secondary else { return primary }
        if contrast(Design.quiet) >= 4.5 { return Design.quiet }
        let muted = primary.blended(withFraction: 0.2, of: background) ?? primary
        return contrast(muted) >= 4.5 ? muted : primary
    }
    var width: CGFloat = 600
    var chosenHex: String? { didSet { needsDisplay = true } }
    struct PrintPreview { let colour:NSColor; let delta:Double }
    var deltaTolerance:Double=2 {didSet{needsDisplay=true}}
    static func hasDeltaWarning(_ previews:[PrintPreview],tolerance:Double)->Bool {
        previews.contains{$0.delta.isFinite && $0.delta > tolerance}
    }
    var canHover:((Item)->Bool)?
    var onPrint:((Item)->[PrintPreview])?
    var onSpectral:((Item)->[NSColor?])?
    var onOriginal:((Item)->[NSColor]?)?
    private var printPreviews:[String:[PrintPreview]] = [:]
    private var printPreviewOrder:[String]=[]
    private var itemKeys=Set<String>()
    private var pendingPrintItems:[(String,Item)]=[]
    private var pendingPrintKeys=Set<String>()
    private var printGeneration=0
    private var printWorkScheduled=false
    private let printQueue=DispatchQueue(label:"Colorgain.TileGrid.PrintPredictions",qos:.userInitiated)
    private var splitOverrides:[String:Bool]=[:]
    var suppressesEmptyMessage=false
    var showsIlluminant=false
    var deltaEnabled=false {didSet{if deltaEnabled != oldValue{splitOverrides=[:];needsDisplay=true}}}
    func invalidatePrintPreviews(){printGeneration+=1;printPreviews=[:];printPreviewOrder.removeAll();pendingPrintItems.removeAll();pendingPrintKeys.removeAll();needsDisplay=true}
    private func requestPrintPreview(_ item:Item,key:String) {
        guard onPrint != nil,printPreviews[key] == nil,pendingPrintKeys.insert(key).inserted else{return}
        pendingPrintItems.append((key,item))
        schedulePrintWork()
    }
    private func schedulePrintWork() {
        guard !printWorkScheduled,!pendingPrintItems.isEmpty else{return}
        printWorkScheduled=true
        let generation=printGeneration
        let batch=Array(pendingPrintItems.prefix(8))
        pendingPrintItems.removeFirst(batch.count)
        let convert=onPrint
        printQueue.async{[weak self] in
            let results=batch.map{($0.0,convert?($0.1) ?? [])}
            DispatchQueue.main.async{[weak self] in
                guard let self else{return}
                self.printWorkScheduled=false
                guard generation == self.printGeneration else{self.schedulePrintWork();return}
                var changed=false
                for (key,prediction) in results {
                    self.pendingPrintKeys.remove(key)
                    guard self.itemKeys.contains(key) else{continue}
                    self.printPreviews[key]=prediction
                    self.printPreviewOrder.append(key)
                    changed=true
                }
                if self.printPreviewOrder.count > 2048 {
                    for key in self.printPreviewOrder.prefix(512){self.printPreviews.removeValue(forKey:key)}
                    self.printPreviewOrder.removeFirst(512)
                }
                if changed{self.setNeedsDisplay(self.visibleRect)}
                self.schedulePrintWork()
            }
        }
    }
    var onPaletteHalo:((UUID,NSRect)->Void)?
    var onImageHalo:((String,NSRect)->Void)?
    var onNotes:((Item)->Void)?
    var onTags:((Item)->Void)?
    var notePaletteID: UUID?
    var noteScope: String?
    var onImageContextActions:((String)->[HaloAction])?
    private let imageContextMenu=SwissContextMenu()
    var onImageContextAction:((String,Int)->Void)?
    func showImageFull(_ path:String){
        guard let index=items.firstIndex(where:{$0.imagePath==path}) else{return}
        currentImageIndex=index;focusedImagePath=path;imageFullView=true
        onImagePageChanged?(currentImageIndex+1,items.count)
        window?.makeFirstResponder(self);needsDisplay=true
    }
    func changeImagePage(_ offset:Int){moveFullImage(offset)}
    var currentImagePath:String? {items.indices.contains(currentImageIndex) ? items[currentImageIndex].imagePath:nil}
    private func itemIndex(at point:NSPoint)->Int?{
        if displaysImages && imageFullView{return items.indices.contains(currentImageIndex) && rect(currentImageIndex).contains(point) ? currentImageIndex:nil}
        return items.indices.first{rect($0).contains(point)}
    }
    private func identity(_ item:Item)->String { item.selectionID ?? item.imagePath.map { "file:"+$0 } ?? item.hex.map { "colour:"+$0 } ?? item.id.map { "asset:"+$0.uuidString } ?? "name:"+item.title }
    func togglePrintPreview(hex:String? = nil, palette:UUID? = nil) {
        guard items.contains(where:{ hex != nil ? $0.hex == hex : palette != nil && $0.id == palette }) else{return}
        Prefs.deltaWarningsEnabled.toggle()
        needsDisplay=true
    }
    private func pageScroll(_ event:NSEvent) { enclosingScrollView?.scrollWheel(with:event) }
    override func scrollWheel(with event:NSEvent){
        if displaysImages && imageFullView {
            let now=Date()
            if (event.phase == .began || event.phase == []) && now.timeIntervalSince(lastFullWheelNavigation)>0.22 {
                let delta=event.scrollingDeltaY == 0 ? event.scrollingDeltaX:event.scrollingDeltaY
                if delta != 0 {moveFullImage(delta > 0 ? -1:1);lastFullWheelNavigation=now}
            }
            return
        }
        pageScroll(event)
    }
    override func keyDown(with event:NSEvent){
        if displaysImages && imageFullView && event.keyCode == 53 {
            if let path=currentImagePath{onImageContextAction?(path,3)}
            return
        }
        if displaysImages && imageFullView {
            switch event.keyCode {case 123,126:moveFullImage(-1);return;case 124,125:moveFullImage(1);return;default:break}
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "a" {
            selection.ids = Set(selectionOrder); selection.anchor = selectionOrder.first; selectionChanged(); return
        }
        if event.keyCode == 51 || event.keyCode == 117 { onDeleteSelection?(); return }
        if event.keyCode == 53 { selection = AssetSelection(); selectionChanged(); return }
        if [123, 124, 125, 126].contains(event.keyCode), !items.isEmpty {
            let current = focusedAsset.flatMap { selectionOrder.firstIndex(of: $0) }
            let step = (event.keyCode == 123 ? -1 : event.keyCode == 124 ? 1 : (event.keyCode == 126 ? -1 : 1) * (listView ? 1 : columns))
            let next = current.map { min(items.count-1, max(0, $0+step)) } ?? (step < 0 ? items.count-1 : 0)
            selectAsset(next, modifiers: event.modifierFlags); scrollToVisible(rect(next)); return
        }
        if event.keyCode == 36, let key = focusedAsset, let i = selectionOrder.firstIndex(of:key) {
            if let id=items[i].id {onOpen?(id)} else if let hex=items[i].hex {onPreviewSwatch?(hex)}
            return
        }
        super.keyDown(with:event)
    }
    var onPreviewSwatch: ((String) -> Void)?
    var onContext: ((String, NSPoint) -> Void)?
    var onAssetContext: ((UUID, NSPoint) -> Void)?
    var onPick: ((String) -> Void)?
    var onOpen: ((UUID) -> Void)?
    var onPreviewPaletteColour:((UUID,Int)->Void)?
    var onSelectPalette:((UUID)->Void)?
    var onResize: (() -> Void)?
    /// A click on the colour itself copies the caption's value; the halo mark at the right of the caption opens the halo over it.
    var onCopy: ((String) -> Void)?
    var onHalo: ((String, NSRect) -> Void)?
    var showsHalo = true
    private var markHits: [(NSRect, Int)] = []
    private var noteHits: [(NSRect, Int)] = []
    private var tagHits: [(NSRect, Int)] = []
    /// On the beat: a block of five units, two units of words with the title and the caption on their lines, a unit between rows; across, the page's own gutter.
    static var block: CGFloat { Design.App.unit * 5 }
    static var words: CGFloat { Design.App.unit * 2 }
    static var rowGap: CGFloat { Design.App.unit + 24 }
    static let gap: CGFloat = 16
    private var captionMinimumWidth:CGFloat=0
    private var framedGrid:Bool {!listView && (!displaysImages || importPaletteCards)}
    private var cardInset:CGFloat {framedGrid ? 12:6}
    private var cardHeader:CGFloat {framedGrid ? 36:0}
    private var swatchBarHeight:CGFloat {hasSwatches && showsPaletteBars ? 8:0}
    private var titleRowHeight:CGFloat {hasSwatches && !cardShowsNames ? 0:Design.App.unit}
    private var listRowHeight:CGFloat {hasSwatches ? max(64,16+Design.App.unit+CGFloat(maximumValueRows)*Design.App.unit):64}
    private var gridCardHeight:CGFloat {
        if hasSwatches && !imageIntake{return cardHeader+swatchBlockHeight+swatchBarHeight+titleRowHeight+CGFloat(maximumValueRows)*Design.App.unit+12}
        return Self.block+Self.words+(framedGrid ? (items.first?.id != nil || importPaletteCards ? 12:48):0)
    }
    private var gridStride:CGFloat {gridCardHeight+(imageIntake ? 24:Self.rowGap)}
    private func colourBlock(_ r:NSRect)->NSRect {
        if listView{return NSRect(x:r.minX+8,y:r.minY+8,width:min(240,r.width*0.4),height:hasSwatches ? max(40,listRowHeight-16-swatchBarHeight):48)}
        if displaysImages && imageFullView{return NSRect(x:r.minX+8,y:r.minY+8,width:max(0,r.width-16),height:max(0,r.height-64))}
        return NSRect(x:r.minX+(framedGrid ? cardInset:0),y:r.minY+cardHeader,width:max(0,r.width-(framedGrid ? cardInset*2:0)),height:hasSwatches && !imageIntake ? swatchBlockHeight:Self.block)
    }
    private func captionBaseline(_ r:NSRect)->CGFloat {
        if hasSwatches && !imageIntake{return (listView ? r.minY+8+Design.App.unit:colourBlock(r).maxY+swatchBarHeight+titleRowHeight)+Design.App.textBaseline}
        return listView ? r.minY+45:r.minY+cardHeader+Self.block+Design.App.unit+Design.App.textBaseline
    }
    private func statusBaseline(_ r:NSRect)->CGFloat {framedGrid || (listView && hasSwatches) ? r.minY+24:captionBaseline(r)}
    private func importCheckbox(_ r:NSRect,_ block:NSRect)->NSRect {
        importPaletteCards ? NSRect(x:r.maxX-cardInset-20,y:r.minY+9,width:16,height:16)
            : NSRect(x:block.minX+8,y:block.minY+8,width:16,height:16)
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// How many tiles a row holds: the slider's count, or fewer when there are fewer tiles, so one row always fills the block.
    var paletteTileWidth:CGFloat {left(1)-Self.gap}
    private var columns: Int {
        let minimumWidth:CGFloat=displaysImages ? 160:max(hasSwatches ? swatchMinimumWidth:240,captionMinimumWidth)
        let fitting=max(1,Int((contentWidth+Self.gap)/(minimumWidth+Self.gap)))
        return max(1,min(across,fitting,max(items.count,1)))
    }
    /// A column's left edge: the row justified to the block, every edge on a whole point, the last tile's right edge on the block's.
    private func left(_ c: Int) -> CGFloat { (CGFloat(c) * (contentWidth + Self.gap) / CGFloat(columns)).rounded() }
    var height: CGFloat {
        if displaysImages && imageFullView { return max(1,fullImageViewportHeight) }
        if listView { return CGFloat(items.count)*listRowHeight + contentInset*2 }
        let rows = (items.count + columns - 1) / columns
        return CGFloat(rows) * gridStride + contentInset*2
    }
    func revealPalette(_ id: UUID) {
        guard let index = items.firstIndex(where: {$0.id == id}) else { return }
        scrollToVisible(rect(index))
    }
    func reveal(_ hex: String) {
        guard let index = items.firstIndex(where: { $0.hex == hex }) else { return }
        scrollToVisible(rect(index))
    }
    private func rect(_ i: Int) -> NSRect {
        if displaysImages && imageFullView { return NSRect(x:contentInset,y:contentInset,width:contentWidth,height:max(1,fullImageViewportHeight-contentInset*2)) }
        if listView { return NSRect(x:contentInset,y:contentInset+CGFloat(i)*listRowHeight,width:contentWidth,height:listRowHeight) }
        let c = i % columns, x = left(c)
        return NSRect(x: contentInset+x, y: contentInset+CGFloat(i / columns) * gridStride, width: left(c + 1) - Self.gap - x, height: gridCardHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        markHits = []
        noteHits = []
        tagHits = []
        let visible=visibleRect.union(dirtyRect)
        let drawRange:Range<Int>
        if displaysImages && imageFullView {
            drawRange=items.indices.contains(currentImageIndex) ? currentImageIndex..<(currentImageIndex+1) : 0..<0
        } else if listView {
            let first=max(0,Int(floor((visible.minY-contentInset)/listRowHeight)))
            let last=min(items.count,Int(ceil((visible.maxY-contentInset)/listRowHeight))+1)
            drawRange=first..<max(first,last)
        } else {
            let stride=gridStride
            let firstRow=max(0,Int(floor((visible.minY-contentInset)/stride)))
            let lastRow=min((items.count+columns-1)/columns,Int(ceil((visible.maxY-contentInset)/stride))+1)
            let first=min(items.count,firstRow*columns),last=min(items.count,max(firstRow,lastRow)*columns)
            drawRange=first..<max(first,last)
        }
        for i in drawRange {
            let it=items[i]
            if displaysImages && imageFullView && i != currentImageIndex { continue }
            let r = rect(i)
            let hasNotch = !imageIntake && !listView && !(displaysImages && imageFullView)
                && AssetNotes.key(for:it,palette:notePaletteID,scope:noteScope) != nil
            let notchRect = NSRect(x:r.midX-62-WorkspaceTabContour.curve,y:r.maxY-1,
                                   width:124+2*WorkspaceTabContour.curve,height:24)
            // The notch lives below the card. During scrolling AppKit can invalidate only
            // that exposed strip, leaving the card itself outside the dirty rectangle.
            guard r.intersects(dirtyRect) || hasNotch && notchRect.intersects(dirtyRect) else { continue }
            let hasAssetActions = showsHalo && (it.imagePath != nil || ((it.hex != nil || it.id != nil) && (canHover?(it) ?? true)))
            if hasAssetActions && (listView || (displaysImages && imageFullView)) {
                let baseline=statusBaseline(r)
                let hit=NSRect(x:r.maxX-cardInset-16,y:baseline-13,width:16,height:16)
                markHits.append((hit.insetBy(dx:-4,dy:-4),i))
            }
            if hasNotch && notchRect.intersects(dirtyRect) {
                let tab = NSRect(x: r.midX-62, y: r.maxY-1, width: 124, height: 24)
                let notch = NSBezierPath()
                let curve=WorkspaceTabContour.curve,halfCurve=curve/2
                notch.move(to: NSPoint(x:tab.minX-curve,y:tab.minY))
                notch.curve(to:NSPoint(x:tab.minX,y:tab.maxY-1),controlPoint1:NSPoint(x:tab.minX-halfCurve,y:tab.minY),controlPoint2:NSPoint(x:tab.minX-halfCurve,y:tab.maxY-1))
                notch.line(to:NSPoint(x:tab.maxX,y:tab.maxY-1))
                notch.curve(to:NSPoint(x:tab.maxX+curve,y:tab.minY),controlPoint1:NSPoint(x:tab.maxX+halfCurve,y:tab.maxY-1),controlPoint2:NSPoint(x:tab.maxX+halfCurve,y:tab.minY))
                let fillPath = notch.copy() as! NSBezierPath
                fillPath.close(); Design.card.setFill(); fillPath.fill()
                notch.lineWidth=1;Design.rule.setStroke();notch.stroke()
                let iconY=tab.minY+3
                let notesRect=NSRect(x:tab.midX-42,y:iconY,width:16,height:16)
                let tagsRect=NSRect(x:tab.midX-8,y:iconY,width:16,height:16)
                let haloRect=NSRect(x:tab.midX+26,y:iconY,width:16,height:16)
                if hasAssetActions {Design.haloMark(in:haloRect,colour:Design.ink);markHits.append((haloRect.insetBy(dx:-6,dy:-4),i))}
                let hasNote=AssetNotes.key(for:it,palette:notePaletteID,scope:noteScope).map{key in
                    AssetNotes.hasNoteForDrawing(key){[weak self] in self?.setNeedsDisplay(self?.visibleRect ?? .zero)}
                } ?? false
                RowMark.image(hasNote ? "note.text" : "note.text",colour:hasNote ? Design.ink:Design.quiet.withAlphaComponent(0.48)).draw(in:notesRect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
                noteHits.append((notesRect.insetBy(dx:-6,dy:-4),i))
                if it.id != nil || it.hex != nil {
                    RowMark.image("tag",colour:Design.ink).draw(in:tagsRect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
                    tagHits.append((tagsRect.insetBy(dx:-6,dy:-4),i))
                }
            }
            guard r.intersects(dirtyRect) else { continue }
            // The grid card owns its frame, padded colour block and separate proof-status row.
            if isSelected(it) && !importPaletteCards {
                fill(r, Design.mist)
                Design.ink.withAlphaComponent(0.65).setStroke()
                let selectedBorder = NSBezierPath(rect: r.insetBy(dx: 1.5, dy: 1.5)); selectedBorder.lineWidth = 3; selectedBorder.stroke()
            }
            if framedGrid {Design.rule.setStroke();let border=NSBezierPath(rect:r.insetBy(dx:0.5,dy:0.5));border.lineWidth=1;border.stroke()}
            let block = colourBlock(r)
            if it.linkedReference {
                RowMark.image("link", colour: Design.orange).draw(in: NSRect(x: r.maxX-cardInset-18, y: r.minY+9, width: 18, height: 18), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            let thumbnail=it.image ?? it.imagePath.flatMap{onImagePreview?($0,it.modifiedAt)}
            let preview=displaysImages && imageFullView && fullResolutionPath == it.imagePath ? (fullResolutionImage ?? thumbnail):thumbnail
            if let image=preview, image.size.width > 0, image.size.height > 0 {
                if displaysImages {
                    Design.rule.setStroke();let card=NSBezierPath(rect:block.insetBy(dx:0.5,dy:0.5));card.lineWidth=1;card.stroke()
                    let inner=block.insetBy(dx:8,dy:8)
                    let scale=min(inner.width/image.size.width,inner.height/image.size.height)
                    let size=NSSize(width:image.size.width*scale,height:image.size.height*scale)
                    image.draw(in:NSRect(x:inner.midX-size.width/2,y:inner.midY-size.height/2,width:size.width,height:size.height))
                } else {
                    let scale=min(block.width/image.size.width,block.height/image.size.height)
                    let size=NSSize(width:image.size.width*scale,height:image.size.height*scale)
                    image.draw(in:NSRect(x:block.midX-size.width/2,y:block.midY-size.height/2,width:size.width,height:size.height))
                }
            } else if it.colours.isEmpty {
                fill(block, Design.mist)
                if imageIntake { RowMark.image("doc.text",colour:Design.quiet).draw(in:NSRect(x:block.midX-22,y:block.midY-22,width:44,height:44),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
            }
            else {
                // A palette's colours share the block as equal bands, a single colour takes it whole.
                let bw = block.width / CGFloat(it.colours.count)
                for (k, c) in it.colours.enumerated() { fill(NSRect(x: block.minX + CGFloat(k) * bw, y: block.minY, width: k == it.colours.count - 1 ? block.width - CGFloat(k) * bw : bw + 0.5, height: block.height), c) }
            }
            if imageIntake {
                let checked=it.imagePath.map{selectedImagePaths.contains($0)} ?? false
                let box=importCheckbox(r,block)
                Design.card.setFill();NSBezierPath(rect:box).fill();Design.rule.setStroke();NSBezierPath(rect:box.insetBy(dx:0.5,dy:0.5)).stroke()
                if checked {Design.ink.setStroke();let tick=NSBezierPath();tick.lineWidth=2;tick.move(to:NSPoint(x:box.minX+3,y:box.midY));tick.line(to:NSPoint(x:box.minX+7,y:box.maxY-3));tick.line(to:NSPoint(x:box.maxX-2,y:box.minY+3));tick.stroke()}
            }
            let key=identity(it)
            let eligible=canHover?(it) ?? (it.hex != nil || it.id != nil)
            if eligible,printPreviews[key] == nil {requestPrintPreview(it,key:key)}
            let prediction=printPreviews[key] ?? []
            if preview == nil,(Prefs.deltaWarningsEnabled || (showsIlluminant && PaletteViewing.illuminant != .normal)),let original=onOriginal?(it),!original.isEmpty {
                let proof=prediction.count >= original.count ? Array(prediction.prefix(original.count)).map(\.colour):nil
                PaletteViewing.draw(original:original,proof:proof,spectral:showsIlluminant ? onSpectral?(it):nil,showsIlluminant:showsIlluminant,in:block)
            }
            let ground = it.id != nil && it.id == selectedPalette ? Design.mist : canvasColour
            let primaryInk = ink(on: ground), secondaryInk = ink(on: ground, secondary: true)
            let textX = listView ? block.maxX+16 : r.minX+cardInset
            if it.hex == nil || cardShowsNames {
            Design.attributed(it.hex == nil ? it.title:it.title.components(separatedBy:" / ").first ?? it.title, .bodyStrong, colour: primaryInk).draw(x:textX,baseline:listView ? r.minY+25 : block.maxY+swatchBarHeight+Design.App.textBaseline,width:listView ? max(0,r.maxX-textX-(it.hex != nil ? 130:(it.id.flatMap{reviews[$0]} == nil ? 0:PaletteReviewControls.width+14)-(it.linkedReference ? 24:0))) : max(0,r.width-cardInset*2-(it.id.flatMap{reviews[$0]} == nil ? 0:PaletteReviewControls.width+12)))
            }
            if it.hex != nil,showsPaletteBars,!it.paletteBars.isEmpty {
                let width=block.width/CGFloat(it.paletteBars.count)
                for (index,colour) in it.paletteBars.enumerated(){fill(NSRect(x:block.minX+CGFloat(index)*width,y:block.maxY+2,width:width,height:4),colour)}
            }
            let capB = captionBaseline(r)
            let statusB = statusBaseline(r)
            if listView { hairline(x:r.minX,y:r.maxY-1,width:r.width) }
            let hasHalo=hasAssetActions && (listView || (displaysImages && imageFullView))
            let delta=eligible ? (prediction.map{$0.delta}.max().map{String(format:it.hex == nil ? "Δmax %.1f":"Δ %.1f",$0)} ?? "Δ —") : ""
            let deltaText=Design.attributed(delta,.caption,colour:secondaryInk)
            let warning=eligible && Self.hasDeltaWarning(prediction,tolerance:deltaTolerance)
            let statusRight=r.maxX-cardInset-(it.linkedReference && framedGrid ? 24:0)
            let right=statusRight-(hasHalo ? 24:0)-(warning ? 22:0)
            let deltaX=max(r.minX+cardInset,right-deltaText.size().width)
            let valueX=textX+(it.hex == nil ? 0:24)
            let paletteCountInHeader=framedGrid && (it.id != nil || importPaletteCards)
            if it.hex != nil {
                for (row,text) in valueRows(for:it).enumerated(){
                    let trailing=r.maxX-cardInset
                    Design.attributed(text,.caption,colour:secondaryInk).draw(x:valueX,baseline:capB+CGFloat(row)*Design.App.unit,width:max(0,trailing-valueX))
                }
            } else {
                Design.attributed(it.caption,.caption,colour:secondaryInk).draw(x:paletteCountInHeader ? r.minX+cardInset:valueX,baseline:paletteCountInHeader ? statusB:capB,width:max(0,(paletteCountInHeader ? deltaX-8:(framedGrid ? r.maxX-cardInset:deltaX-8))-(paletteCountInHeader ? r.minX+cardInset:valueX)))
            }
            if eligible{deltaText.draw(x:deltaX,baseline:statusB)}
            if warning {ResultGlyph.warning.draw(in:NSRect(x:statusRight-(hasHalo ? 24:0)-16,y:statusB-13,width:16,height:16))}
            if hasHalo {Design.haloMark(in:NSRect(x:statusRight-16,y:statusB-13,width:16,height:16),colour:secondaryInk)}
            if let h = it.hex, h == chosenHex {
                // The chosen tile: a one-point ring in the Rule, the same grey that edges the panels.
                Design.rule.setStroke()
                let p = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)); p.lineWidth = 1; p.stroke()
            }
        }
        if items.isEmpty, let n = note {
            // Words in place of tiles, a member's notes: the Lead, no wider than 34em, every line on the beat and the first on the first unit's line.
            let font = Design.Text.lead.font(), p = NSMutableParagraphStyle()
            p.minimumLineHeight = Design.App.unit; p.maximumLineHeight = Design.App.unit
            let text = NSAttributedString(string: n, attributes: [.font: font, .foregroundColor: ink(on: canvasColour), .kern: Design.Text.lead.size * Design.Text.lead.tracking, .paragraphStyle: p])
            // A fixed line sets its glyphs at its foot, the descender clear of it: the first line's top is where that puts the baseline on the line.
            let top = Design.App.textBaseline - (Design.App.unit + font.descender)
            text.draw(with: NSRect(x: contentInset, y: top+contentInset, width: min(contentWidth, Design.Text.lead.size * 34), height: max(0,bounds.height - top)), options: [.usesLineFragmentOrigin])
        } else if items.isEmpty && !suppressesEmptyMessage { Design.attributed("Nothing found", .lead, colour: ink(on: canvasColour, secondary: true)).draw(x: contentInset, baseline: contentInset+Design.App.textBaseline) }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = itemIndex(at:p), items[i].hex != nil {
            toolTip = nil
        } else if let i=itemIndex(at:p),items[i].id != nil,!imageIntake {
            toolTip=nil
        } else if displaysImages,let i=itemIndex(at:p) {
            let values=items[i].metadata
            toolTip=values.isEmpty ? items[i].title : values.sorted{$0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending}.prefix(8).map{"\($0.key): \($0.value)"}.joined(separator:"\n")
        } else { toolTip = nil }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index=itemIndex(at:point),!isSelected(items[index]) {selectAsset(index,modifiers:[])}
        if displaysImages,let index=itemIndex(at:point),let path=items[index].imagePath {
            let actions = onImageContextActions?(path) ?? []
            imageContextMenu.open(actions,at:point,in:self)
            return
        }
        guard let index=itemIndex(at:point) else{return}
        if let hex = items[index].hex { onContext?(hex, point) }
        else if let id = items[index].id { onAssetContext?(id, point) }
    }
    override func mouseDown(with event: NSEvent) {
        pendingBandClick?.invalidate();pendingBandClick=nil
        window?.makeFirstResponder(self)
        pressedPalette=nil
        let p = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command) {
            if let index=itemIndex(at:p) {selectAsset(index, modifiers:event.modifierFlags)}
            return
        }
        if imageIntake, let i=itemIndex(at:p),let path=items[i].imagePath {
            let r=rect(i),box=importCheckbox(r,colourBlock(r))
            if box.insetBy(dx:-4,dy:-4).contains(p){onImageSelectionToggle?(path);return}
        }
        if let m = noteHits.first(where: { $0.0.contains(p) }) { onNotes?(items[m.1]); return }
        if let m = tagHits.first(where: { $0.0.contains(p) }) { onTags?(items[m.1]); return }
        if let m = markHits.first(where: { $0.0.contains(p) }) {if let h=items[m.1].hex{onPick?(h);onHalo?(h,m.0)}else if let id=items[m.1].id{onPaletteHalo?(id,m.0)}else if let path=items[m.1].imagePath{onImageHalo?(path,m.0)};return}
        guard let i = itemIndex(at:p) else { selection = AssetSelection(); selectionChanged(); return }
        selectAsset(i, modifiers: event.modifierFlags)
        if displaysImages {
            if event.clickCount >= 2, let path=items[i].imagePath { onImageContextAction?(path,2) }
            return
        }
        if let h = items[i].hex {
            guard event.clickCount >= 2 else { onPick?(h); return }
            onPick?(h)
            if let onPreviewSwatch { onPreviewSwatch(h);return }
            // The colour block itself copies its value; the words beneath only choose.
            let r=rect(i)
            let block = NSRect(x:r.minX+(framedGrid ? cardInset:0),y:r.minY+cardHeader,width:max(0,r.width-(framedGrid ? cardInset*2:0)),height:Self.block)
            if block.contains(p) {
                let text = Prefs.copyFormat == .cmyk ? (items[i].sourceCMYK ?? Prefs.copyText(h)) : Prefs.copyText(h)
                ColourCopies.copy(h, text: text, sourceCMYK: items[i].sourceCMYK)
                onCopy?(text)
            }
        }
        else if items[i].id != nil {pressedPalette=items[i];palettePress=(event.locationInWindow,event.timestamp)}
    }
    override func mouseDragged(with event:NSEvent){
        guard let item=pressedPalette,let id=item.id,canHover?(item) == true,PaletteDrag.counts(event,from:palettePress) else{return}
        pressedPalette=nil
        PaletteDrag.begin(id,name:item.title,colours:item.colours,event:event,in:self)
    }
    override func mouseUp(with event:NSEvent){
        defer{pressedPalette=nil}
        guard let item=pressedPalette,let id=item.id,!PaletteDrag.counts(event,from:palettePress),
              let index=itemIndex(at:convert(event.locationInWindow,from:nil)),items[index].id == id else{return}
        if event.clickCount >= 2 {onOpen?(id);return}
        selectedPalette=id;onSelectPalette?(id)
    }

    func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext)->NSDragOperation {.copy}
}
