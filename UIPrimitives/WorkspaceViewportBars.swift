import AppKit
import UniformTypeIdentifiers
import ImageIO

enum WorkspaceImageSort: String, CaseIterable {
    case captureTime = "Capture Time", checkedState = "Checked State", fileName = "File Name"
    case fileType = "File Type", mediaType = "Media Type", off = "Off"
}

/// A text-first, underline-selected control shared by intake and footer view modes.
final class WorkspaceChoiceControl:NSView {
    let labels:[String]
    var selectedSegment=0 {didSet{needsDisplay=true}}
    var onChange:((Int)->Void)?
    private var hovered:Int?
    override var isFlipped:Bool{true}
    init(labels:[String]){self.labels=labels;super.init(frame:.zero);setAccessibilityRole(.radioGroup)}
    required init?(coder:NSCoder){fatalError()}
    override func draw(_ dirtyRect:NSRect){
        let width=bounds.width/CGFloat(max(1,labels.count))
        for (i,label) in labels.enumerated(){
            let box=NSRect(x:CGFloat(i)*width,y:0,width:width,height:bounds.height)
            let on=i == selectedSegment
            Design.attributed(label,on ? .bodyStrong:.body,colour:on ? Design.ink:Design.quiet).draw(x:box.minX+8,baseline:bounds.midY+5,width:box.width-16)
            if on {fill(NSRect(x:box.minX+8,y:bounds.maxY-2,width:max(0,box.width-16),height:2),Design.ink)}
            else if hovered == i {hairline(x:box.minX+8,y:bounds.maxY-1,width:max(0,box.width-16),Design.rule)}
        }
    }
    private func segment(_ event:NSEvent)->Int{min(labels.count-1,max(0,Int(convert(event.locationInWindow,from:nil).x/max(1,bounds.width)*CGFloat(labels.count))))}
    override func mouseDown(with event:NSEvent){let next=segment(event);guard next != selectedSegment else{return};selectedSegment=next;onChange?(next)}
    override func updateTrackingAreas(){super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea);addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseMoved,.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self))}
    override func mouseMoved(with event:NSEvent){let next=segment(event);if hovered != next{hovered=next;needsDisplay=true}}
    override func mouseExited(with event:NSEvent){hovered=nil;needsDisplay=true}
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
}

/// Mutually exclusive choices using the shared filled-square checkbox treatment.
final class WorkspaceToggleChoiceControl: NSView {
    private let buttons: [SwissCheckbox]
    var selectedSegment = 0 { didSet { updateSelection() } }
    var onChange: ((Int) -> Void)?
    override var isFlipped: Bool { true }
    init(labels: [String]) {
        buttons = labels.map { SwissCheckbox($0) }
        super.init(frame: .zero)
        for (index, button) in buttons.enumerated() {
            button.tag = index; button.target = self; button.action = #selector(choose(_:))
            addSubview(button)
        }
        updateSelection()
    }
    required init?(coder: NSCoder) { fatalError() }
    private func updateSelection() {
        for (index, button) in buttons.enumerated() { button.state = index == selectedSegment ? .on : .off; button.needsDisplay = true }
    }
    @objc private func choose(_ sender: SwissCheckbox) {
        let changed = selectedSegment != sender.tag
        selectedSegment = sender.tag
        if changed { onChange?(selectedSegment) }
    }
    override func layout() {
        super.layout()
        let width = bounds.width / CGFloat(max(1, buttons.count))
        for (index, button) in buttons.enumerated() { button.frame = NSRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height) }
    }
}

final class WorkspaceMenuControl:NSView {
    var title="Sort: Off"{didSet{needsDisplay=true}}
    var onPress:(()->Void)?
    private var hovering=false
    override var isFlipped:Bool{true}
    override func draw(_ dirtyRect:NSRect){
        Design.attributed(title,.body,colour:Design.ink).draw(x:8,baseline:bounds.midY+5,width:max(0,bounds.width-24))
        let x=bounds.width-9,y=bounds.midY-1
        let path=NSBezierPath();path.lineWidth=hovering ? 2:1.5;path.move(to:NSPoint(x:x-3,y:y-2));path.line(to:NSPoint(x:x,y:y+1));path.line(to:NSPoint(x:x+3,y:y-2));Design.ink.setStroke();path.stroke()
    }
    override func mouseDown(with event:NSEvent){onPress?()}
    override func updateTrackingAreas(){super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea);addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self))}
    override func mouseEntered(with event:NSEvent){hovering=true;needsDisplay=true}
    override func mouseExited(with event:NSEvent){hovering=false;needsDisplay=true}
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
}

final class WorkspaceTextActionControl:NSView {
    var title:String {didSet{needsDisplay=true}}
    var onPress:(()->Void)?
    private var hovering=false
    override var isFlipped:Bool{true}
    init(_ title:String){self.title=title;super.init(frame:.zero);setAccessibilityRole(.button);setAccessibilityLabel(title)}
    required init?(coder:NSCoder){fatalError()}
    override func draw(_ dirtyRect:NSRect){
        let text=Design.attributed(title,.bodyStrong,colour:Design.ink)
        text.draw(x:0,baseline:bounds.midY+5,width:bounds.width)
        if hovering{hairline(x:0,y:bounds.maxY-1,width:min(bounds.width,text.size().width),Design.ink)}
    }
    override func mouseDown(with event:NSEvent){onPress?()}
    override func updateTrackingAreas(){super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea);addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self))}
    override func mouseEntered(with event:NSEvent){hovering=true;needsDisplay=true}
    override func mouseExited(with event:NSEvent){hovering=false;needsDisplay=true}
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
}

/// Static import guidance belongs to the page content, outside the actionbar.
final class WorkspaceImportPanel:NSView {
    var destination="Photography"{didSet{heading.stringValue="Import To "+destination}}
    var onImport:(()->Void)?
    private let icon=PaletteAssetIcon(frame:.zero)
    private let heading=Design.text("Import To Photography",.bodyStrong)
    private let explanation=Design.text("Choose a folder, review its images, then copy, move or reference the selected files.",.body,wraps:true)
    override var isFlipped:Bool{true}
    override init(frame:NSRect){super.init(frame:frame);[icon,heading,explanation].forEach(addSubview);icon.symbol="square.and.arrow.down";icon.setAccessibilityLabel("Import Images");icon.toolTip="Choose Images To Import";icon.run={ [weak self] in self?.onImport?() }}
    required init?(coder:NSCoder){fatalError()}
    override func layout(){super.layout();icon.ink=Design.ink;icon.frame=NSRect(x:16,y:16,width:40,height:40);heading.frame=NSRect(x:72,y:16,width:max(0,bounds.width-88),height:22);explanation.frame=NSRect(x:72,y:44,width:max(0,bounds.width-88),height:52)}
    override func draw(_ dirtyRect:NSRect){Design.rule.setStroke();NSBezierPath(rect:bounds.insetBy(dx:0.5,dy:0.5)).stroke()}
}

/// Rail geometry stays independent of page actions and import presentation.
enum WorkspaceResponsiveGeometry {
    static func singleRail(_ width:CGFloat)->Bool{width < Design.App.railWidth*2+722}
    static func rails(width:CGFloat,selection:Int,library:Bool,analysis:Bool)->(CGFloat,CGFloat){
        let rail=Design.App.railWidth
        if singleRail(width){switch selection{case 0:return (rail,0);case 1:return (0,rail);default:return (0,0)}}
        return (library ? rail:0,analysis ? rail:0)
    }
}

/// Shared asset ordering. Missing dates stay last in either direction.
enum GridAssetOrder:String,CaseIterable {
    case original="Filter By", name="Name A–Z", nameReverse="Name Z–A"
    case newest="Date Created: Newest", oldest="Date Created: Oldest"
    case modified="Date Modified: Newest", modifiedOldest="Date Modified: Oldest"
    case captured="Date Captured: Newest", capturedOldest="Date Captured: Oldest"
    func sorted(_ items:[TileGrid.Item])->[TileGrid.Item] {
        guard self != .original else {return items}
        return items.enumerated().sorted { a,b in
            if self == .name || self == .nameReverse {
                let comparison=a.element.title.localizedStandardCompare(b.element.title)
                if comparison != .orderedSame {return comparison == (self == .name ? .orderedAscending:.orderedDescending)}
            } else {
                let x:Date?,y:Date?
                switch self {
                case .newest,.oldest:x=a.element.createdAt;y=b.element.createdAt
                case .modified,.modifiedOldest:x=a.element.modifiedAt;y=b.element.modifiedAt
                default:x=a.element.captureDate;y=b.element.captureDate
                }
                if let x,let y,x != y {return self == .oldest || self == .modifiedOldest || self == .capturedOldest ? x < y:x > y}
                if (x == nil) != (y == nil) {return x != nil}
            }
            return a.offset < b.offset
        }.map(\.element)
    }
}

final class WorkspaceViewportBar:NSView {
    static let actionbarHeight:CGFloat=58
    var preferredHeight:CGFloat=WorkspaceViewportBar.actionbarHeight
    static let footerHeight:CGFloat=42
    var usesHeaderSurface=false {didSet{needsDisplay=true}}
    private let selectionCountLabel=NSTextField(labelWithString:"")
    func setSelectionCount(_ count:Int,total:Int) {
        guard !imageBrowser else{return}
        selectionCountLabel.stringValue="\(count) of \(total) Selected"
        selectionCountLabel.setAccessibilityLabel(selectionCountLabel.stringValue)
        selectionCountLabel.isHidden = !isFooter || total == 0
        needsLayout=true
    }
    private let isFooter:Bool
    private let gridButton=PaletteAssetIcon(frame:.zero),listButton=PaletteAssetIcon(frame:.zero)
    private let previousImage=PaletteAssetIcon(frame:.zero),nextImage=PaletteAssetIcon(frame:.zero)
    private var imageBrowser=false
    private var customControls=false
    var onImagePage:((Int)->Void)?
    private let libraryRailButton=PaletteAssetIcon(frame:.zero),analysisRailButton=PaletteAssetIcon(frame:.zero)
    var onLibraryRail:(()->Void)?
    var onAnalysisRail:(()->Void)?
    func setRailControls(library:Bool,analysis:Bool,visible:Bool) {
        guard isFooter else {return}
        for (button,open,label) in [(libraryRailButton,library,"Workspace Rail"),(analysisRailButton,analysis,"Analysis Rail")] {
            button.isHidden = !visible; button.state = open ? .on:.off
            button.ink = Design.ink; button.active = open
            let action=(open ? "Hide ":"Show ")+label
            button.toolTip=action;button.setAccessibilityLabel(action)
        }
    }
    private let pageHelp=Help_HexButton(page:"palette-page",title:"Palette Page")
    private let assetImport=SwissButton("Import Palettes…",.secondary)
    var onPaletteImport:(()->Void)?
    private var paletteImportActive=false
    func configurePaletteImport(active:Bool){
        guard !isFooter else{return}
        paletteImportActive=active
        assetImport.isHidden = !active
        pageHelp.isHidden=intake
        needsLayout=true
    }
    @objc private func assetImportPressed(){if paletteImportActive {onPaletteImport?()}}
    let channels=WorkspaceChannelControls(frame:.zero)
    private let cancelButton=SwissButton("Cancel", .quiet)
    private let allImages=SwissCheckbox("Select All")
    private let imageCount=NSTextField(labelWithString:"0 Images")
    private let intakeView=WorkspaceChoiceControl(labels:["Grid","Full"])
    private let sortButton=WorkspaceMenuControl()
    private let imageFilter=WorkspaceToggleChoiceControl(labels:["All Files","New Only"])
    private let metadataFilterButton=WorkspaceMenuControl()
    private let assetOrderMenu=AnalysisMenu("Filter By",GridAssetOrder.allCases.map(\.rawValue))
    var onAssetOrder:((GridAssetOrder)->Void)?
    var filtersNewRow=false {didSet{needsLayout=true}}
    func setAssetOrder(_ order:GridAssetOrder){assetOrderMenu.selectItem(withTitle:order.rawValue);needsLayout=true}

    private let importLinkChoice=WorkspaceToggleChoiceControl(labels:["Import","Link"])
    private let importTypeMenu=AnalysisMenu("Artefact Type",WorkspaceImport.types)
    var onImportType:((String)->Void)?
    private var intakeSort=WorkspaceImageSort.off
    private var sortChoices=WorkspaceImageSort.allCases
    var onImport:(()->Void)?
    var onIntakeMode:((Bool)->Void)?
    var onCancel:(()->Void)?
    var onSelectAllImages:((Bool)->Void)?
    var onImageFilter:((Bool)->Void)?
    var onImageSort:((WorkspaceImageSort)->Void)?
    var onImageView:((Bool)->Void)?
    var onMetadataFilter:(()->Void)?
    var onImportLinking:((Bool)->Void)?
    private var offersImport=false
    private var intake=false
    private var linking=false
    private var imageIntake=false
    private var imageAssetType=true
    var onMode:((Bool)->Void)?
    var listMode=false { didSet{updateButtons()} }
    override var isFlipped:Bool{true}
    init(footer:Bool) {
        isFooter=footer;super.init(frame:.zero)
        wantsLayer=true;layer?.backgroundColor=Design.card.cgColor;layer?.masksToBounds=false;clipsToBounds=false
        NotificationCenter.default.addObserver(self,selector:#selector(refreshAppearance),name:.themeDidChange,object:nil)
        assetOrderMenu.borderless=true;assetOrderMenu.isHidden=footer
        assetOrderMenu.changed={ [weak self] index in
            guard let self else{return}
            if GridAssetOrder.allCases.indices.contains(index) {self.onAssetOrder?(GridAssetOrder.allCases[index])}
        }
        if !footer {addSubview(assetOrderMenu)}
        metadataFilterButton.title="Filter by Meta"
        metadataFilterButton.onPress={[weak self] in self?.onMetadataFilter?()}
        if footer {
            selectionCountLabel.font=Design.Text.body.font();selectionCountLabel.alignment = .center
            selectionCountLabel.textColor=Design.ink;selectionCountLabel.isHidden=true;addSubview(selectionCountLabel)
            previousImage.symbol="chevron.left";nextImage.symbol="chevron.right"
            previousImage.toolTip="Previous Image";nextImage.toolTip="Next Image"
            previousImage.setAccessibilityLabel("Previous Image");nextImage.setAccessibilityLabel("Next Image")
            previousImage.run={ [weak self] in self?.onImagePage?(-1) }
            nextImage.run={ [weak self] in self?.onImagePage?(1) }
            for button in [previousImage,nextImage]{button.isHidden=true;addSubview(button)}
            for (button,symbol) in [(libraryRailButton,"sidebar.left"),(analysisRailButton,"sidebar.right")] {
                button.symbol=symbol;button.setButtonType(.toggle);button.isHidden=true;addSubview(button)
            }
            libraryRailButton.run={ [weak self] in self?.onLibraryRail?() }
            analysisRailButton.run={ [weak self] in self?.onAnalysisRail?() }
            for (button,symbol,label) in [(gridButton,"square.grid.2x2","Grid View"),(listButton,"list.bullet","List View")] {
                button.symbol=symbol;button.setButtonType(.toggle)
                button.run={ [weak self,weak button] in guard let self,let button else{return};self.choose(button) }
                button.toolTip=label;button.setAccessibilityLabel(label)
                addSubview(button)
            }
            intakeView.onChange={[weak self] segment in self?.onImageView?(segment == 1)}
            sortButton.onPress={[weak self] in self?.openSortMenu()}
            [intakeView,sortButton,metadataFilterButton].forEach(addSubview)
            intakeView.isHidden=true;sortButton.isHidden=true;metadataFilterButton.isHidden=true
            updateButtons()
        } else {
            for (button,action) in [(assetImport,#selector(assetImportPressed))] {
                button.target=self;button.action=action;button.isHidden=true;addSubview(button)
            }
            allImages.target=self;allImages.action=#selector(selectAllChanged)
            allImages.state = .on
            imageFilter.onChange={[weak self] segment in self?.onImageFilter?(segment == 1)}
            importLinkChoice.onChange={[weak self] segment in self?.onImportLinking?(segment == 1)}
            importTypeMenu.borderless=true
            importTypeMenu.changed={ [weak self] index in
                let types=WorkspaceImport.types
                guard types.indices.contains(index) else{return}
                self?.onImportType?(types[index])
            }
            imageCount.font=Design.Text.body.font();imageCount.textColor=Design.quiet;imageCount.alignment = .right
            [pageHelp,allImages,imageFilter,imageCount,metadataFilterButton,importLinkChoice,importTypeMenu].forEach(addSubview)
            setIntakeMode(false)
        }
    }
    required init?(coder:NSCoder){fatalError()}
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func refreshAppearance(){updateButtons()}
    private func updateButtons(){gridButton.state=listMode ? .off:.on;listButton.state=listMode ? .on:.off;gridButton.ink=ThemedButton.readable(on:Design.card);listButton.ink=ThemedButton.readable(on:Design.card);needsDisplay=true}
    @objc private func choose(_ sender:NSButton){listMode=sender === listButton;onMode?(listMode)}
    func setIntakeMode(_ active:Bool,linking:Bool=false){
        intake=active;self.linking=linking
        pageHelp.isHidden=active
        importTypeMenu.isHidden = !active
        importLinkChoice.isHidden = true
        allImages.isHidden = !active;imageFilter.isHidden = !active;imageCount.isHidden = !active
        if active && !imageIntake {imageFilter.selectedSegment=0}
        needsLayout=true
    }
    /// A route that owns all controls supplies them through leadingControls/rightControls.
    func configureCustomControls() {
        guard !isFooter else { return }
        customControls=true
        [pageHelp,allImages,imageFilter,imageCount,metadataFilterButton,importLinkChoice,importTypeMenu,assetOrderMenu].forEach { $0.isHidden=true }
        needsLayout=true
    }
    func configureImageIntake(_ active:Bool,kind:String="Photographs",linking:Bool=false,selectAll:Bool,newOnly:Bool,fullView:Bool,sort:WorkspaceImageSort,imageCount:Int,selectedCount:Int,columns:Int){
        imageIntake=active
        if !isFooter {
            imageAssetType=kind == "Photographs" || kind == "Images"
            setIntakeMode(active,linking:linking)
            importTypeMenu.selectItem(withTitle:kind)
            importLinkChoice.selectedSegment=linking ? 1:0
            allImages.state=selectAll ? .on:.off
            imageFilter.selectedSegment=newOnly ? 1:0
            self.imageCount.stringValue="\(imageCount) Files · \(selectedCount) Selected"
            if active {assetOrderMenu.isHidden=true;metadataFilterButton.isHidden=true}
        } else {
            intakeView.isHidden=true
            sortButton.isHidden = !active
            gridButton.isHidden=active;listButton.isHidden=active
            intakeView.selectedSegment=fullView ? 1:0
            if active {sortChoices=kind == "Photographs" || kind == "Images" ? WorkspaceImageSort.allCases:[.checkedState,.fileName,.fileType,.off]}
            intakeSort=sort;sortButton.title="Sort: \(sort.rawValue)"
        }
        needsLayout=true;needsDisplay=true
    }
    func configureImageBrowser(active:Bool,fullView:Bool,index:Int,total:Int,sort:WorkspaceImageSort?=nil,view:Bool=true,paginated:Bool=true){
        guard isFooter else{return}
        imageBrowser=active
        if active {
            intakeView.isHidden = !view;intakeView.selectedSegment=fullView ? 1:0
            sortButton.isHidden=sort == nil;gridButton.isHidden=true;listButton.isHidden=true
            sortChoices=[.fileName,.fileType,.off]
            if let sort{intakeSort=sort;sortButton.title="Sort: \(sort.rawValue)"}
            selectionCountLabel.stringValue=fullView && total > 0 ? "\(index) of \(total)":"\(total) Images"
            selectionCountLabel.isHidden=false
        } else {
            selectionCountLabel.isHidden=true
        }
        let navigable=active && paginated && fullView && total > 1
        previousImage.isHidden = !navigable;nextImage.isHidden = !navigable
        needsLayout=true
    }
    @objc private func selectAllChanged(){onSelectAllImages?(allImages.state == .on)}
    @objc private func beginImport(){onImport?()}
    func configureMetadataFilter(visible:Bool,active:Bool){guard !isFooter else{return};metadataFilterButton.isHidden = !visible;assetOrderMenu.isHidden = !visible;metadataFilterButton.title=active ? "Metadata Filter: On" : "Filter by Meta";needsLayout=true}
    @objc private func openSortMenu(){
        guard let win=window else{return}
        if let old=droppedSort {old.parent?.removeChildWindow(old);old.orderOut(nil);droppedSort=nil;return}
        let items=sortChoices.map(\.rawValue)
        let panel=SwissDropdown.MenuPanel(items:items,chosen:intakeSort.rawValue,width:196){[weak self] index in
            guard let self,self.sortChoices.indices.contains(index) else{return}
            self.intakeSort=self.sortChoices[index];self.sortButton.title="Sort: \(self.intakeSort.rawValue)"
            self.onImageSort?(self.intakeSort);self.droppedSort?.parent?.removeChildWindow(self.droppedSort!);self.droppedSort?.orderOut(nil);self.droppedSort=nil
        }
        let rect=win.convertToScreen(sortButton.convert(sortButton.bounds,to:nil));panel.place(anchoredTo:rect,preferAbove:true,within:win);win.addChildWindow(panel,ordered:.above);droppedSort=panel
    }
    private var droppedSort:SwissDropdown.MenuPanel?
    /// The right-hand controls, left to right, each with its width, its height and the gap before it; the bar steps them left from `rightInset`, so their last edge is the swatches' at any width.
    var trailingControlsNewRow=false {didSet{needsLayout=true}}
    var rightControls:[(view:NSView,width:CGFloat,height:CGFloat,gap:CGFloat)]=[] { didSet{needsLayout=true} }
    var leadingControls:[(view:NSView,width:CGFloat,height:CGFloat,gap:CGFloat)]=[] {didSet{needsLayout=true}}
    var leftInset:CGFloat=16 { didSet{needsLayout=true;needsDisplay=true} }
    var rightInset:CGFloat=16 { didSet{needsLayout=true} }
    /// Leading actions claim their actual width before filters are positioned.
    var leadingContentInset:CGFloat {leftInset+(assetImport.isHidden ? 0:162)}
    var hasCentredImport:Bool{false}
    func importLeadingWidth(for width:CGFloat)->CGFloat{max(160,width/2-leftInset-64)}
    override func layout(){
        let contentHeight=bounds.height-(trailingControlsNewRow && !isFooter ? 40:0)-(filtersNewRow && !isFooter ? 40:0)
        let trailingWidth=rightControls.reduce(CGFloat(0)){$0+$1.width+$1.gap}
        super.layout();gridButton.frame=NSRect(x:leftInset,y:4,width:28,height:24);listButton.frame=NSRect(x:leftInset+32,y:4,width:28,height:24)
        libraryRailButton.frame=NSRect(x:leftInset+72,y:4,width:28,height:24)
        analysisRailButton.frame=NSRect(x:leftInset+104,y:4,width:28,height:24)
        intakeView.frame=NSRect(x:leftInset,y:2,width:128,height:28)
        sortButton.frame=NSRect(x:leftInset+148,y:2,width:128,height:28)
        allImages.frame=NSRect(x:leftInset,y:3,width:136,height:26)
        imageFilter.frame=NSRect(x:leftInset+148,y:2,width:226,height:28)
        imageCount.frame=NSRect(x:bounds.width-rightInset-300,y:6,width:284,height:20)
        importLinkChoice.frame=NSRect(x:leftInset+550,y:2,width:160,height:28)
        pageHelp.frame=Help_HexButton.frame(width:bounds.width,height:contentHeight)
        if isFooter {
            metadataFilterButton.isHidden=true;metadataFilterButton.frame = .zero
            intakeView.frame = .zero
            sortButton.frame=NSRect(x:leftInset+(libraryRailButton.isHidden ? 0:148),y:2,width:160,height:28)
        } else if intake {
            metadataFilterButton.frame=NSRect(x:leftInset+384,y:2,width:156,height:28)
        } else {
            metadataFilterButton.frame=NSRect(x:max(12,bounds.width-rightInset-156-40-(trailingControlsNewRow ? 0:trailingWidth+(rightControls.isEmpty ? 0:16))),y:2,width:156,height:28)
        }
        selectionCountLabel.textColor=Design.ink
        selectionCountLabel.frame=NSRect(x:bounds.midX-100,y:(bounds.height-20)/2,width:200,height:20)
        previousImage.frame=NSRect(x:bounds.midX-132,y:4,width:28,height:24)
        nextImage.frame=NSRect(x:bounds.midX+104,y:4,width:28,height:24)
        var right=bounds.width-rightInset-(!isFooter && !trailingControlsNewRow ? 40:0)
        for c in rightControls.reversed() {
            let width = (c.view as? PrintProfileSelector).map { min(c.width, $0.preferredControlWidth) } ?? c.width
            c.view.frame=NSRect(x:right-width,y:((bounds.height-c.height)/2).rounded(),width:width,height:c.height)
            right-=width+c.gap
        }
        var left=leadingContentInset
        for c in leadingControls {
            c.view.frame=NSRect(x:left,y:((bounds.height-c.height)/2).rounded(),width:c.width,height:c.height)
            left+=c.width+c.gap
        }
        let filter=leadingControls.first(where:{$0.view is PaletteFilterControls})?.view
        for view in subviews {
            var frame=view.frame
            if rightControls.contains(where:{$0.view === view}){
                frame.origin.y=trailingControlsNewRow ? bounds.height-12-frame.height:((contentHeight-frame.height)/2).rounded()
            } else if trailingControlsNewRow && filter == nil {frame.origin.y=((contentHeight-frame.height)/2).rounded()
            } else if let filter,contentHeight > Self.actionbarHeight {
                frame.origin.y=view === filter || view === assetImport ? 12:contentHeight-12-frame.height
            } else {frame.origin.y=((contentHeight-frame.height)/2).rounded()}
            view.frame=frame
        }
        if !isFooter,!assetOrderMenu.isHidden {
            let y=filtersNewRow ? contentHeight+6 : (contentHeight-28)/2
            let metaX=filtersNewRow ? bounds.width-rightInset-156 : metadataFilterButton.frame.minX
            metadataFilterButton.frame=NSRect(x:metaX,y:y,width:156,height:28)
            let orderWidth=min(max(80,metaX-leftInset-16),min(230,max(100,assetOrderMenu.fittedWidth)))
            assetOrderMenu.frame=NSRect(x:metaX-orderWidth-16,y:y,width:orderWidth,height:28)
            if intake { importLinkChoice.frame.origin.x=leftInset+384 }
            if filtersNewRow && !pageHelp.isHidden {pageHelp.frame.origin.y=y}
        }
        if !isFooter && intake {
            let centreY=(bounds.height-28)/2
            importTypeMenu.frame=NSRect(x:leftInset,y:centreY,width:min(190,max(130,bounds.width-200)),height:28)
            importLinkChoice.frame = .zero
            let room=bounds.width-rightInset-importTypeMenu.frame.maxX
            allImages.isHidden=room<160
            imageFilter.isHidden=room<350
            imageCount.isHidden=room<600
            allImages.frame=NSRect(x:importTypeMenu.frame.maxX+12,y:centreY,width:136,height:28)
            imageFilter.frame=NSRect(x:allImages.frame.maxX+12,y:centreY,width:188,height:28)
            imageCount.frame=NSRect(x:bounds.width-rightInset-220,y:(bounds.height-20)/2,width:220,height:20)
        }
        if !isFooter && paletteImportActive {
            assetImport.frame=NSRect(x:leftInset,y:((contentHeight-32)/2).rounded(),width:150,height:32)
        }
    }
    override func draw(_ dirtyRect:NSRect){
        if hasCentredImport{
            // Straight rules pass behind the opaque circular control.
            fill(bounds,Design.card);Design.rule.setStroke()
            let border=NSBezierPath(rect:bounds.insetBy(dx:0.5,dy:0.5));border.lineWidth=1;border.stroke();return
        }
        if usesHeaderSurface{fill(bounds,Design.card);WorkspacePanelSurface.draw(in:bounds,selected:false)}
        hairline(x:0,y:isFooter ? 0:bounds.height-1,width:bounds.width)
        if !isFooter && intake {hairline(x:0,y:bounds.height-1,width:bounds.width,Design.rule)}
        if isFooter {
            if !gridButton.isHidden {fill(NSRect(x:leftInset+(listMode ? 32:0),y:bounds.height-3,width:28,height:2),Design.ink)}
        } else if !usesHeaderSurface && !customControls {
            Design.rule.setStroke()
            let border=NSBezierPath(rect:bounds.insetBy(dx:0.5,dy:0.5));border.lineWidth=1;border.stroke()

        }
    }
}
