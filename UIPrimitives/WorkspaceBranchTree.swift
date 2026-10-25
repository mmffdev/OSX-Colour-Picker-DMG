import AppKit
import UniformTypeIdentifiers
import ImageIO

/// Shared rail tree: compact branching lanes, ten-step depth colours and node rings.
/// Native outline semantics retain independent expansion and keyboard/multiple selection.
final class WorkspaceBranchTree: NSOutlineView {
    enum SwatchFamily { case drives, charcoal, yellow }
    /// Rounded cards need a small, consistent outside separation: 3 + 2 + 3 = 8 pt.
    static let rowSpacing:CGFloat=2
    static let surfaceInset:CGFloat=3
    static let edgePadding:CGFloat=3
    static let paletteRowHeight:CGFloat=64
    static let paletteContentInset:CGFloat=4
    static func rowsHeight(_ count:Int,rowHeight:CGFloat=34)->CGFloat {
        guard count > 0 else{return 0}
        return CGFloat(count)*rowHeight+CGFloat(count-1)*rowSpacing
    }
    private static let driveSwatches = ["#1F2933", "#323F4B", "#3E4C59", "#52606D", "#616E7C", "#7B8794", "#9AA5B1", "#CBD2D9", "#E4E7EB", "#F5F7FA"]
    private static let charcoalSwatches = ["#242424", "#414141", "#585858", "#707070", "#888888", "#A0A0A0", "#B8B8B8", "#CFCFCF", "#E3E3E3", "#F5F5F5"]
    private static let yellowSwatches = ["#F4BE00", "#F5C526", "#F6CC4B", "#F7D371", "#F8DA96", "#F9E2B4", "#FAE9CD", "#FCF0DF", "#FDF6ED", "#FEFBF6"]
    var swatchFamily:SwatchFamily = .charcoal
    /// Source browsers use the same tree geometry with clear, outlined rows.
    var outlinedRows = false
    /// Source selectors can mark their single current row with the shared
    /// black-and-white selection band without enabling node-colour editing.
    var selectedBarberPole = false
    /// A projected section can start a new root tree without a sibling trunk.
    var rootConnectorBreak:((Any)->Bool)?
    var swatchFamilyForItem:((Any)->SwatchFamily)?
    static func tint(_ depth:Int,family:SwatchFamily = .charcoal)->NSColor {
        let colours=family == .drives ? driveSwatches:family == .yellow ? yellowSwatches:charcoalSwatches
        return Design.hex(colours[min(max(0,depth),colours.count-1)])
    }
    private func tint(_ row:Int,item:Any)->NSColor {Self.tint(visualDepth(row),family:swatchFamilyForItem?(item) ?? swatchFamily)}
    private func background(_ row:Int,item:Any)->NSColor {rowColour?(item) ?? tint(row,item:item)}
    private func ink(_ row:Int,item:Any)->NSColor {
        if let ink=rowInk?(item){return ink}
        if rowClear?(item) == true || outlinedRows && rowFill?(item) != true { return Design.ink }
        return Theme.takesLightText(on:hexOf(background(row,item:item)) ?? "#FFFFFF") ? .white:.black
    }
    /// Read the same live row sources used by drawing; older nodes need no appearance migration.
    func renderedColour(for item:Any,channel:WorkspaceColourMode.Channel)->NSColor? {
        let row=row(forItem:item)
        guard row >= 0 else{return nil}
        let clear=rowClear?(item) == true || (outlinedRows && rowFill?(item) != true)
        switch channel {
        case .background:return clear ? Design.card:background(row,item:item)
        case .text:return ink(row,item:item)
        case .border:return rowBorder?(item) ?? (clear || rowLeadingAccent?(item) != nil ? Design.rule:nil)
        }
    }
    /// Destination pickers select owners without collapsing their descendants.
    var expandsOnSelection = true
    var leadingDisclosure=false
    var depthOffset=0
    var connectsFromParent=false
    private func visualDepth(_ row:Int)->Int{level(forRow:row)+depthOffset}
    var showsConnectors=true
    var isDropTarget:((Any)->Bool)?
    var paletteDragActive=false {didSet{enumerateAvailableRowViews{row,_ in row.needsDisplay=true}}}
    var reorderLineY:CGFloat? {didSet{connectorOverlay.needsDisplay=true}}
    var onContext:((Any,NSPoint,NSView)->Void)?
    /// When set, every row click selects a colour target instead of activating row controls or navigating.
    var onColourModeClick:((Int,NSEvent)->Void)?
    var colourModeActive:Bool {onColourModeClick != nil}
    func colourTargetRowHeight(for item:Any,base:CGFloat)->CGFloat {
        let index=row(forItem:item)
        return colourModeActive && index >= 0 && selectedRowIndexes.contains(index) ? base+4:base
    }
    func refreshColourTargetGeometry(_ rows:IndexSet) {
        guard !rows.isEmpty else{return}
        noteHeightOfRows(withIndexesChanged:rows)
        needsLayout=true
        var ancestor=superview
        while let view=ancestor {
            view.needsLayout=true
            if let panel=view as? WorkspacePanel {panel.rail?.arrange();break}
            ancestor=view.superview
        }
    }
    var rowColour:((Any)->NSColor?)?
    var rowInk:((Any)->NSColor?)?
    var rowBorder:((Any)->NSColor?)?
    /// Filled feature rows can coexist with outlined rows in the same tree.
    var rowFill:((Any)->Bool)?
    /// Clear asset rows use the same light rule as the surrounding app rails.
    var rowClear:((Any)->Bool)?
    /// A slim coloured marker for a clear row, such as an asset inside a Collection.
    var rowLeadingAccent:((Any)->NSColor?)?
    private var hoverRow = -1
    private var tracking: NSTrackingArea?
    private var ancestors:[[Int]]=[]
    private var branchEnds:[Int:Int]=[:]
    private var previousSiblings:[Int:Int]=[:]
    private lazy var connectorOverlay=Connectors(tree:self)
    private static let laneStep:CGFloat=14 // Nine-point nodes, five-point horizontal gap.
    // The outer connector ring begins at the same 16 pt panel inset as other content.
    private static func lane(_ depth:Int)->CGFloat {18 + CGFloat(depth)*laneStep}
    static var accent:NSColor {
        Theme.takesLightText(on:hexOf(Design.card) ?? "#FFFFFF") ? Design.hex("#C7C7C7"):Design.hex("#6D6D6D")
    }
    private static let trailingActionCentreInset:CGFloat=18
    private static var paletteCellTrailingInset:CGFloat {13}
    override func frameOfOutlineCell(atRow row:Int)->NSRect {
        let box=rect(ofRow:row)
        if leadingDisclosure {return NSRect(x:showsConnectors ? Self.lane(visualDepth(row))+21:16,y:box.minY+(min(34,box.height)-20)/2,width:20,height:20)}
        return NSRect(x:max(0,bounds.width-Self.trailingActionCentreInset-10),y:box.midY-10,width:20,height:20)
    }
    override func frameOfCell(atColumn column:Int,row:Int)->NSRect {
        let box=rect(ofRow:row)
        if (item(atRow:row) as? WorkspaceCatalogues.Node)?.key == "icc-content"{return box}
        let disclosure=leadingDisclosure && isExpandable(item(atRow:row))
        let start:CGFloat=(showsConnectors ? Self.lane(visualDepth(row))+21:16)+(disclosure ? 22:0)
        let isPalette:Bool={
            if let node=item(atRow:row) as? WorkspaceCatalogues.Node {if case .palette=node.place{return true};return node.fontID != nil}
            if let node=item(atRow:row) as? WorkspaceCollectionsPane.Node,case .asset(let asset,_)=node.value {
                return ["Palette","Palettes","Font","Fonts"].contains(asset.kind)
            }
            return false
        }()
        let isCatalogue=(item(atRow:row) as? WorkspaceCatalogues.Node)?.catalogue != nil
        let trailing=leadingDisclosure || isCatalogue || isPalette ? Self.paletteCellTrailingInset:34
        return NSRect(x:start,y:box.minY,width:max(0,bounds.width-start-trailing),height:box.height)
    }
    private final class Disclosure:ClickCursorButton {
        weak var tree:WorkspaceBranchTree?
        var rowInk:NSColor? {didSet{needsDisplay=true}}
        override func draw(_ dirtyRect:NSRect) {
            guard let tree else{return}
            let attachedRow=tree.row(for:self)
            let point=tree.convert(NSPoint(x:bounds.midX,y:bounds.midY),from:self)
            let row=attachedRow >= 0 ? attachedRow:tree.row(at:point)
            let colour:NSColor
            if row >= 0,let item=tree.item(atRow:row) {colour=tree.ink(row,item:item)}
            else if let rowInk {colour=rowInk}
            else {colour=WorkspaceBranchTree.accent}
            let path=NSBezierPath();path.lineWidth=1.3
            if tree.leadingDisclosure {
                if state == .on {let dy:CGFloat=isFlipped ? 1:-1;path.move(to:NSPoint(x:bounds.midX-3,y:bounds.midY-2*dy));path.line(to:NSPoint(x:bounds.midX,y:bounds.midY+dy));path.line(to:NSPoint(x:bounds.midX+3,y:bounds.midY-2*dy))}
                else {path.move(to:NSPoint(x:bounds.midX-2,y:bounds.midY+3));path.line(to:NSPoint(x:bounds.midX+1,y:bounds.midY));path.line(to:NSPoint(x:bounds.midX-2,y:bounds.midY-3))}
            } else {
                path.move(to:NSPoint(x:bounds.midX-3,y:bounds.midY));path.line(to:NSPoint(x:bounds.midX+3,y:bounds.midY))
                if state != .on {path.move(to:NSPoint(x:bounds.midX,y:bounds.midY-3));path.line(to:NSPoint(x:bounds.midX,y:bounds.midY+3))}
            }
            colour.withAlphaComponent(isHighlighted ? 1:0.75).setStroke();path.stroke()
        }
        override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
    }
    final class Star:ClickCursorButton {
        var favourite=false
        var run:(()->Void)?
        init(){super.init(frame:.zero);isBordered=false;target=self;action=#selector(pressed)}
        required init?(coder:NSCoder){fatalError()}
        @objc private func pressed(){run?()}
        override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
        override func draw(_ dirtyRect:NSRect){
            let ink=contentTintColor ?? Design.ink
            let mark=Design.attributed(favourite ? "★":"☆",.body,colour:ink)
            mark.draw(at:NSPoint(x:(bounds.width-mark.size().width)/2,y:(bounds.height-mark.size().height)/2))
        }
    }
    final class Cell:NSTableCellView,NSDraggingSource {
        let star=Star()
        let grip=SchemaGrip(frame:.zero)
        var reorderDrag:((NSEvent)->Void)?
        let pin=PaletteAssetIcon(frame:.zero)
        var leadingDisclosure=false
        let catalogueAction=PaletteAssetIcon(frame:.zero)
        let target=PaletteAssetIcon(frame:.zero)
        /// Tags, between the gear and the count on a palette row; opens the palette's tags in railInfo.
        let tagIcon=PaletteAssetIcon(frame:.zero)
        let review=PaletteReviewControls(frame:.zero)
        var spectrumColours:[NSColor]=[] {didSet{needsDisplay=true}}
        var twoLines=false {didSet{needsLayout=true;needsDisplay=true}}
        var isPalette=false {didSet{target.isHidden = !isPalette;tagIcon.isHidden = !isPalette;review.isHidden = !isPalette;needsLayout=true}}
        var renamePalette:((String)->Void)?
        private var editingName=false
        override var isFlipped:Bool{true}
        var paletteDrag:(UUID,String,[NSColor])?
        var fontDrag:(UUID,String)?
        var fontFamily:String?
        var selectPalette:(()->Void)?
        var selectFont:(()->Void)?
        var dragChanged:((Bool)->Void)?
        private var press:(NSPoint,TimeInterval)?
        override func hitTest(_ point:NSPoint)->NSView? {
            let hit=super.hitTest(point)
            if !grip.isHidden,grip.frame.insetBy(dx:-4,dy:-7).contains(convert(point,from:superview)){return self}
            guard paletteDrag != nil || fontDrag != nil,let hit else{return hit}
            if hit === star || hit === colourButton || hit === target || hit === tagIcon || hit === pin || hit.isDescendant(of:review) || hit is InlineName {return hit}
            return self
        }
        override func mouseDown(with event:NSEvent){
            if !grip.isHidden,grip.frame.insetBy(dx:-4,dy:-7).contains(convert(event.locationInWindow,from:nil)) {
                reorderDrag?(event);return
            }
            if activate(at:convert(event.locationInWindow,from:nil)){press=nil;return}
            guard paletteDrag != nil || fontDrag != nil else{super.mouseDown(with:event);return}
            if event.clickCount == 2,beginRenaming(with:event){return}
            press=(event.locationInWindow,event.timestamp)
        }
        override func mouseDragged(with event:NSEvent){
            guard let press,PaletteDrag.counts(event,from:press) else{return}
            self.press=nil;dragChanged?(true)
            if let (id,name,colours)=paletteDrag {PaletteDrag.begin(id,name:name,colours:colours,event:event,in:self)}
            else if let (id,name)=fontDrag {FontDrag.begin(id,name:name,event:event,in:self)}
        }
        override func mouseUp(with event:NSEvent){
            defer{press=nil}
            if press != nil,bounds.contains(convert(event.locationInWindow,from:nil)) {if fontDrag != nil {selectFont?()}else{selectPalette?()}}
        }
        func activate(at point:NSPoint)->Bool {
            for button in [star,colourButton,target,tagIcon,catalogueAction,pin] as [NSButton] where !button.isHidden && button.frame.contains(point){button.performClick(nil);return true}
            if isPalette,review.frame.contains(point){return review.activate(at:convert(point,to:review))}
            return false
        }
        @discardableResult func beginRenaming(with event:NSEvent)->Bool {
            let point=convert(event.locationInWindow,from:nil)
            guard isPalette,let field=textField,field.frame.contains(point),!editingName else{return false}
            editingName=true;field.isHidden=true;press=nil
            InlineName.edit(field.stringValue,style:.body,in:self,x:field.frame.minX,baseline:twoLines ? 19+WorkspaceBranchTree.paletteContentInset:bounds.midY+5,width:field.frame.width,at:point,colour:field.textColor ?? Design.ink){ [weak self,weak field] value in
                self?.editingName=false;field?.isHidden=false
                if let value {self?.renamePalette?(value)}
            };return true
        }
        func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext)->NSDragOperation {.copy}
        func draggingSession(_ session:NSDraggingSession,endedAt screenPoint:NSPoint,operation:NSDragOperation){dragChanged?(false)}
        let countLabel=NSTextField(labelWithString:"")
        final class ColourButton:ClickCursorButton {
            var colour=Design.card {didSet{needsDisplay=true}}
            var run:(()->Void)?
            init(){super.init(frame:.zero);isBordered=false;target=self;action=#selector(pressed)}
            required init?(coder:NSCoder){fatalError()}
            @objc private func pressed(){run?()}
            override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
            override func draw(_ dirtyRect:NSRect){
                let box=NSRect(x:(bounds.width-12)/2,y:(bounds.height-12)/2,width:12,height:12)
                colour.setFill();box.fill()
                (Theme.takesLightText(on:hexOf(colour) ?? "#FFFFFF") ? NSColor.white:NSColor.black).setStroke()
                NSBezierPath(rect:box.insetBy(dx:0.5,dy:0.5)).stroke()
            }
        }
        let colourButton=ColourButton()
        var creationAction=false
        var compactMetadata=false
        /// Collection edit and count form one inline trailing group, without the tree's reserved action gap.
        var inlineActionBeforeCount=false
        /// A shared right edge for every navigational node, regardless of nesting depth.
        var trailingGearAndCount=false
        var warning=false
        var isAssetCategory=false
        var symbol:String? {didSet{needsLayout=true;needsDisplay=true}}
        override init(frame:NSRect){
            super.init(frame:frame);addSubview(grip);grip.isHidden=true;addSubview(pin);pin.isHidden=true;addSubview(star);addSubview(colourButton);colourButton.isHidden=true
            addSubview(target);addSubview(review);target.isHidden=true;review.isHidden=true
            addSubview(tagIcon);tagIcon.isHidden=true;tagIcon.symbol="tag";tagIcon.toolTip="Tags";tagIcon.setAccessibilityLabel("Tags")
            addSubview(catalogueAction);catalogueAction.isHidden=true
            countLabel.font=Design.Text.body.font();countLabel.alignment = .right;countLabel.isHidden=true;addSubview(countLabel)
        }
        required init?(coder:NSCoder){fatalError()}
        override func layout() {
            super.layout()
            let height=textField?.intrinsicContentSize.height ?? 18
            let paletteTop=twoLines ? WorkspaceBranchTree.paletteContentInset:0
            let offset:CGFloat=grip.isHidden ? 0:18
            grip.frame=NSRect(x:0,y:(bounds.height-16)/2,width:10,height:16)
            let inset:CGFloat=(symbol == nil ? 0:24)+offset
            let countWidth:CGFloat=(countLabel.isHidden && pin.isHidden) ? 0:max(leadingDisclosure ? 32:24,countLabel.intrinsicContentSize.width+8)
            let reviewWidth=PaletteReviewControls.width
            let pinWidth:CGFloat=pin.isHidden ? 0:28
            if trailingGearAndCount {
                let countSlot:CGFloat=twoLines && isPalette ? max(28,ceil(countLabel.intrinsicContentSize.width)+8):40
                let gearSlot:CGFloat=26,tagSlot:CGFloat=tagIcon.isHidden ? 0:26
                let gearX=bounds.width-countSlot-tagSlot-gearSlot
                catalogueAction.frame=NSRect(x:gearX,y:paletteTop,width:gearSlot,height:twoLines ? 28:bounds.height)
                tagIcon.frame=NSRect(x:gearX+gearSlot,y:paletteTop,width:tagSlot,height:twoLines ? 28:bounds.height)
                countLabel.frame=NSRect(x:bounds.width-countSlot,y:paletteTop+((twoLines ? CGFloat(28):bounds.height)-height)/2,width:countSlot-5,height:height)
                if twoLines {
                    review.frame=NSRect(x:bounds.width-reviewWidth,y:paletteTop+28,width:reviewWidth,height:28)
                    textField?.frame=NSRect(x:inset,y:paletteTop+(28-height)/2,width:max(0,gearX-inset-8),height:height)
                    star.frame=NSRect(x:-5,y:paletteTop+28,width:24,height:28)
                    target.frame=NSRect(x:star.frame.maxX,y:paletteTop+28,width:24,height:28)
                } else {
                    textField?.frame=NSRect(x:inset,y:(bounds.height-height)/2,width:max(0,gearX-inset-8),height:height)
                }
                return
            }
            if inlineActionBeforeCount && !catalogueAction.isHidden && !countLabel.isHidden {
                let countWidth=ceil(countLabel.intrinsicContentSize.width)
                countLabel.frame=NSRect(x:bounds.width-8-countWidth,y:(bounds.height-height)/2,width:countWidth,height:height)
                catalogueAction.frame=NSRect(x:countLabel.frame.minX-22,y:0,width:22,height:bounds.height)
                textField?.frame=NSRect(x:inset,y:(bounds.height-height)/2,width:max(0,catalogueAction.frame.minX-inset-8),height:height)
                return
            }
            if (isAssetCategory || leadingDisclosure && !isPalette) && !compactMetadata {
                // Right-edge slots stay fixed across every tree depth and count state:
                // pin/edit, add/action, then count. Empty slots remain reserved.
                let countSlot:CGFloat=48,actionSlot:CGFloat=44,pinSlot:CGFloat=28
                let pinX=bounds.width-countSlot-actionSlot-pinSlot
                let actionX=bounds.width-countSlot-actionSlot
                pin.frame=NSRect(x:pinX,y:0,width:pinSlot,height:bounds.height)
                catalogueAction.frame=NSRect(x:actionX,y:0,width:actionSlot,height:bounds.height)
                countLabel.frame=NSRect(x:bounds.width-countSlot,y:(bounds.height-height)/2,width:countSlot-4,height:height)
                let labelEnd=pin.isHidden ? (catalogueAction.isHidden ? bounds.width-countSlot:actionX):pinX
                textField?.frame=NSRect(x:inset,y:(bounds.height-height)/2,width:max(0,labelEnd-inset-8),height:height)
                return
            }
            pin.frame=NSRect(x:bounds.width-countWidth-pinWidth,y:paletteTop,width:pin.isHidden ? 0:28,height:twoLines ? 28:bounds.height)
            if !catalogueAction.isHidden {
                catalogueAction.frame=NSRect(x:max(0,bounds.width-(creationAction ? 60:28)),y:0,width:28,height:bounds.height)
                // Creation stays on the header action column; focus gets its own slot.
                if creationAction && !pin.isHidden {
                    pin.frame=NSRect(x:max(0,catalogueAction.frame.minX-36),y:0,width:28,height:bounds.height)
                }
                let labelEnd=creationAction && !pin.isHidden ? pin.frame.minX:catalogueAction.frame.minX
                textField?.frame=NSRect(x:inset,y:(bounds.height-height)/2,width:max(0,labelEnd-inset-8),height:height)
                return
            }
            if compactMetadata {
                textField?.frame=NSRect(x:inset,y:(bounds.height-height)/2,width:max(0,bounds.width-inset-countWidth-8),height:height)
                countLabel.frame=NSRect(x:bounds.width-countWidth,y:(bounds.height-height)/2,width:countWidth,height:height)
                return
            }
            if twoLines {
                review.frame=NSRect(x:bounds.width-reviewWidth,y:paletteTop+28,width:reviewWidth,height:28)
                let nameEnd=bounds.width-countWidth-8
                textField?.frame=NSRect(x:inset,y:paletteTop+(28-height)/2,width:max(0,nameEnd-inset),height:height)
                countLabel.frame=NSRect(x:bounds.width-countWidth,y:paletteTop+(28-height)/2,width:max(0,countWidth-4),height:height)
                // The palette glyph is centred at x=7 in its shared 14 pt icon lane.
                star.frame=NSRect(x:-5,y:paletteTop+28,width:24,height:28)
                if !pin.isHidden{pin.frame=NSRect(x:star.frame.maxX,y:paletteTop+28,width:24,height:28)}
                target.frame=NSRect(x:star.frame.maxX+(pin.isHidden ? 0:24),y:paletteTop+28,width:24,height:28)
                return
            }
            // Parent cells reserve their disclosure lane; counts share the palette count column.
            if leadingDisclosure && !isPalette {
                countLabel.frame=NSRect(x:bounds.width-countWidth,y:(bounds.height-height)/2,width:countWidth,height:height)
                textField?.frame=NSRect(x:inset,y:(bounds.height-height)/2,width:max(0,bounds.width-inset-countWidth-pinWidth-8),height:height)
                return
            }
            let parentCorrection:CGFloat=isPalette ? 0:34-WorkspaceBranchTree.paletteCellTrailingInset
            let nameStart:CGFloat=isPalette ? inset+44+(colourButton.isHidden ? 0:22):inset
            let trailing:CGFloat=countLabel.isHidden ? 0:reviewWidth+countWidth+4-parentCorrection
            textField?.frame=NSRect(x:nameStart,y:(bounds.height-height)/2,width:max(0,bounds.width-nameStart-trailing),height:height)
            star.frame=NSRect(x:isPalette ? inset+(colourButton.isHidden ? 0:22):bounds.width-22,y:0,width:22,height:bounds.height)
            target.frame=NSRect(x:star.frame.maxX,y:0,width:22,height:bounds.height)
            review.frame=NSRect(x:bounds.width-reviewWidth+parentCorrection,y:0,width:reviewWidth,height:bounds.height)
            countLabel.frame=NSRect(x:review.frame.minX-countWidth-4,y:(bounds.height-height)/2,width:max(0,countWidth-4),height:height)
            colourButton.frame=NSRect(x:inset,y:0,width:22,height:bounds.height)
        }
        override func draw(_ dirtyRect:NSRect){
            super.draw(dirtyRect)
            if isPalette,twoLines,!spectrumColours.isEmpty {
                let start=target.frame.maxX+8
                let end=review.frame.minX+review.ratingGlyphSpan.lowerBound-8
                if end > start {
                    let spectrum=NSRect(x:start,y:WorkspaceBranchTree.paletteContentInset+36,width:end-start,height:12)
                    let width=spectrum.width/CGFloat(spectrumColours.count)
                    NSGraphicsContext.saveGraphicsState();NSBezierPath(rect:spectrum).addClip()
                    for (index,colour) in spectrumColours.enumerated(){colour.setFill();NSRect(x:spectrum.minX+CGFloat(index)*width,y:spectrum.minY,width:width+0.5,height:spectrum.height).fill()}
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
            guard let symbol,let label=textField else{return}
            if warning {ResultGlyph.warning.draw(in:NSRect(x:0,y:(twoLines ? WorkspaceBranchTree.paletteContentInset:0)+((twoLines ? 28:bounds.height)-16)/2,width:16,height:16));return}
            let image=RowMark.image(symbol,colour:label.textColor ?? Design.ink),size=image.size
            image.draw(in:NSRect(x:(14-size.width)/2+(grip.isHidden ? 0:18),y:(twoLines ? WorkspaceBranchTree.paletteContentInset:0)+((twoLines ? 28:bounds.height)-size.height)/2,width:size.width,height:size.height),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        }
    }
    override func makeView(withIdentifier identifier:NSUserInterfaceItemIdentifier,owner:Any?)->NSView? {
        if identifier == NSOutlineView.disclosureButtonIdentifier {
            let button=Disclosure(frame:NSRect(x:0,y:0,width:20,height:20))
            button.tree=self;button.identifier=identifier;button.setButtonType(.onOff);button.isBordered=false
            button.target=self;button.action=#selector(toggleFolder(_:));return button
        }
        return super.makeView(withIdentifier:identifier,owner:owner)
    }
    @objc private func toggleFolder(_ sender:NSButton) {
        let index=row(for:sender)
        guard index >= 0,let item=item(atRow:index) else{return}
        if isItemExpanded(item){collapseItem(item)}else{expandItem(item)}
        sender.state=isItemExpanded(item) ? .on:.off;refreshSurfaces()
    }
    override func keyDown(with event:NSEvent){
        if colourModeActive {return}
        if (event.keyCode == 125 || event.keyCode == 126),event.modifierFlags.intersection([.command,.control,.option,.shift]).isEmpty,numberOfRows > 0 {
            let step = event.keyCode == 125 ? 1 : -1
            var next = selectedRow < 0 ? (step > 0 ? 0 : numberOfRows - 1) : selectedRow + step
            while next >= 0 && next < numberOfRows {
                if let item = item(atRow: next), delegate?.outlineView?(self, shouldSelectItem: item) != false {
                    selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
                    scrollRowToVisible(next); return
                }
                next += step
            }
            return
        }
        super.keyDown(with:event)
    }
    override func mouseDown(with event:NSEvent) {
        let point=convert(event.locationInWindow,from:nil),index=row(at:point)
        if let onColourModeClick {
            if index >= 0 {window?.makeFirstResponder(self);onColourModeClick(index,event)}
            return
        }
        if index >= 0,let cell=view(atColumn:0,row:index,makeIfNecessary:false) as? Cell {
            let local=cell.convert(event.locationInWindow,from:nil)
            if cell.activate(at:local){return}
            if event.clickCount == 2,cell.beginRenaming(with:event){return}
        }
        window?.makeFirstResponder(self)
        let node=index >= 0 ? item(atRow:index):nil
        let expanded=node.map{isItemExpanded($0)} ?? false
        let disclosure=index >= 0 && (frameOfOutlineCell(atRow:index).contains(point) || (!leadingDisclosure && point.x >= bounds.width-56))
        super.mouseDown(with:event)
        guard expandsOnSelection,let node,isExpandable(node),!disclosure,event.clickCount == 1,
              event.modifierFlags.intersection([.shift,.command,.control,.option]).isEmpty else{return}
        if expanded{collapseItem(node)}else{expandItem(node)}
        refreshSurfaces()
    }
    override func rightMouseDown(with event:NSEvent){
        if colourModeActive {return}
        let point=convert(event.locationInWindow,from:nil),index=row(at:point)
        guard index >= 0,let node=item(atRow:index) else{return}
        onContext?(node,point,self)
    }
    override func hitTest(_ point:NSPoint)->NSView? {
        if colourModeActive,let parent=superview {
            let local=convert(point,from:parent)
            if row(at:local) >= 0 {return self}
        }
        return super.hitTest(point)
    }
    override func mouseDragged(with event:NSEvent){if !colourModeActive {super.mouseDragged(with:event)}}
    override func draggingExited(_ sender:NSDraggingInfo?){super.draggingExited(sender);paletteDragActive=false}
    override func draggingEnded(_ sender:NSDraggingInfo){super.draggingEnded(sender);paletteDragActive=false}
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking{removeTrackingArea(tracking)}
        let area=NSTrackingArea(rect:.zero,options:[.mouseMoved,.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area);tracking=area
    }
    private func setHover(_ index:Int) {
        guard hoverRow != index else{return}
        let old=hoverRow;hoverRow=index
        connectorOverlay.needsDisplay=true
        for row in [old,index] where row >= 0 && row < numberOfRows {rowView(atRow:row,makeIfNecessary:false)?.needsDisplay=true}
    }
    override func mouseMoved(with event:NSEvent){setHover(row(at:convert(event.locationInWindow,from:nil)))}
    override func mouseExited(with event:NSEvent){setHover(-1)}
    override func resetCursorRects(){super.resetCursorRects();let range=rows(in:visibleRect);guard range.location != NSNotFound else{return};for row in range.location..<NSMaxRange(range){ClickCursor.register([rect(ofRow:row)],in:self)}}
    func refreshCell(_ index:Int) {
        guard index >= 0,let item=item(atRow:index),let cell=view(atColumn:0,row:index,makeIfNecessary:false) as? Cell else{return}
        let currentInk=ink(index,item:item)
        if let family=cell.fontFamily {
            cell.textField?.font=NSFontManager.shared.font(withFamily:family,traits:[],weight:5,size:TextSize.body) ?? Design.Text.body.font()
        } else {
            cell.textField?.font=(isItemExpanded(item) ? Design.Text.bodyStrong:Design.Text.body).font()
        }
        cell.textField?.textColor=currentInk
        if let row=rowView(atRow:index,makeIfNecessary:false) {
            func refreshDisclosure(in view:NSView) {
                if let disclosure=view as? Disclosure {disclosure.rowInk=currentInk}
                else {view.subviews.forEach{refreshDisclosure(in:$0)}}
            }
            refreshDisclosure(in:row)
        }
        cell.colourButton.colour=background(index,item:item)
        cell.star.contentTintColor=cell.textField?.textColor;cell.star.needsDisplay=true
        cell.target.ink=cell.textField?.textColor ?? Design.ink;cell.review.ink=cell.textField?.textColor ?? Design.ink
        cell.tagIcon.ink=cell.textField?.textColor ?? Design.ink
        cell.catalogueAction.ink=cell.textField?.textColor ?? Design.ink
        cell.pin.ink=cell.textField?.textColor ?? Design.ink
        cell.grip.ink=cell.textField?.textColor ?? Design.ink
        cell.countLabel.font=cell.textField?.font
        cell.countLabel.textColor=cell.textField?.textColor
        cell.needsDisplay=true
    }
    func refreshSurfaces() {
        // Cache visible ancestry once per expansion; drawing never scans the folder list.
        ancestors=[];branchEnds=[:];previousSiblings=[:]
        var stack:[Int]=[]
        for index in 0..<numberOfRows {
            let depth=level(forRow:index)
            if stack.count > depth {stack.removeLast(stack.count-depth)}
            ancestors.append(stack)
            let parent=stack.last ?? -1 // The root folders share their own trunk.
            if (item(atRow:index) as? WorkspaceCatalogues.Node)?.key == "workspace-focus-back"{continue}
            if parent < 0,let item=item(atRow:index),rootConnectorBreak?(item) == true {
                previousSiblings[index]=nil
            } else {
                previousSiblings[index]=branchEnds[parent]
            }
            branchEnds[parent]=index
            stack.append(index)
        }
        enumerateAvailableRowViews { [weak self] row,index in row.needsDisplay=true;self?.refreshCell(index) }
        needsDisplay=true;connectorOverlay.needsDisplay=true
    }
    /// Appearance presets only recolour existing cells and connector strokes.
    /// Tree ancestry and row geometry are unchanged by a colour selection.
    func repaintColours() {
        enumerateAvailableRowViews { [weak self] row,index in
            row.needsDisplay = true
            self?.refreshCell(index)
        }
        needsDisplay = true
        connectorOverlay.needsDisplay = true
    }
    func installConnectors(in host:NSView){host.addSubview(connectorOverlay);connectorOverlay.isHidden = !showsConnectors}
    func layoutConnectors(){connectorOverlay.frame=frame;connectorOverlay.isHidden = !showsConnectors || isHidden;connectorOverlay.needsDisplay=true}
    private func terminal(_ index:Int)->Bool {
        guard index < ancestors.count else{return false}
        return branchEnds[ancestors[index].last ?? -1] == index
    }
    private func active(_ index:Int)->Bool {
        isRowSelected(index) || hoverRow == index || item(atRow:index).map{isItemExpanded($0)} == true
    }
    private func nodeRadius(_ index:Int)->CGFloat {active(index) || terminal(index) ? 8:4.5}
    /// One transparent canvas spans every row, so a curve is never split at a cell seam.
    private final class Connectors:NSView {
        weak var tree:WorkspaceBranchTree?
        init(tree:WorkspaceBranchTree){self.tree=tree;super.init(frame:.zero)}
        required init?(coder:NSCoder){fatalError()}
        override var isFlipped:Bool {true}
        override func hitTest(_ point:NSPoint)->NSView? {nil}
        override func draw(_ dirtyRect:NSRect){
            guard let tree else{return}
            let ink=WorkspaceBranchTree.accent
            let lines=NSBezierPath();lines.lineWidth=1.2
            for index in 0..<min(tree.numberOfRows,tree.ancestors.count) {
                if (tree.item(atRow:index) as? WorkspaceCatalogues.Node)?.key == "icc-content" {
                    if let parent=tree.ancestors[index].last {
                        let x=WorkspaceBranchTree.lane(tree.visualDepth(parent))
                        lines.move(to:NSPoint(x:x,y:tree.rect(ofRow:parent).midY+tree.nodeRadius(parent)))
                        lines.line(to:NSPoint(x:x,y:tree.rect(ofRow:index).minY))
                    }
                    continue
                }
                let parent=tree.ancestors[index].last ?? -1
                let x=WorkspaceBranchTree.lane(tree.visualDepth(index))
                let y=tree.rect(ofRow:index).midY-tree.nodeRadius(index)
                if let previous=tree.previousSiblings[index] {
                    let start=tree.rect(ofRow:previous).midY+tree.nodeRadius(previous)
                    guard NSRect(x:x-1,y:start,width:2,height:max(1,y-start)).intersects(dirtyRect) else{continue}
                    lines.move(to:NSPoint(x:x,y:start));lines.line(to:NSPoint(x:x,y:y))
                } else if parent < 0 && tree.connectsFromParent && index == 0 {
                    let px=WorkspaceBranchTree.lane(max(0,tree.visualDepth(index)-1))
                    lines.move(to:NSPoint(x:px,y:0))
                    lines.curve(to:NSPoint(x:x,y:y),controlPoint1:NSPoint(x:px,y:y*0.65),controlPoint2:NSPoint(x:x,y:y*0.35))
                } else if parent >= 0 {
                    let px=WorkspaceBranchTree.lane(tree.visualDepth(parent))
                    let start=tree.rect(ofRow:parent).midY+tree.nodeRadius(parent)
                    guard NSRect(x:px-1,y:start,width:x-px+2,height:max(1,y-start)).intersects(dirtyRect) else{continue}
                    // The bend sits halfway between the two node centres, not between the node edges:
                    // a big ring above and a small dot below would otherwise push it down the lane.
                    let mid=(tree.rect(ofRow:parent).midY+tree.rect(ofRow:index).midY)/2
                    let half=max(0,min(mid-start,y-mid))
                    let a=mid-half,b=mid+half,reach=half*1.3
                    lines.move(to:NSPoint(x:px,y:start))
                    if a > start {lines.line(to:NSPoint(x:px,y:a))}
                    lines.curve(to:NSPoint(x:x,y:b),
                        controlPoint1:NSPoint(x:px,y:a+reach),
                        controlPoint2:NSPoint(x:x,y:b-reach))
                    if y > b {lines.line(to:NSPoint(x:x,y:y))}
                }
            }
            ink.withAlphaComponent(0.65).setStroke();lines.stroke()
            for index in 0..<tree.numberOfRows {
                guard let item=tree.item(atRow:index) else{continue}
                if (item as? WorkspaceCatalogues.Node)?.key == "icc-content"{continue}
                let row=tree.rect(ofRow:index)
                guard row.intersects(dirtyRect) else{continue}
                let x=WorkspaceBranchTree.lane(tree.visualDepth(index)),y=row.midY
                let depth=tree.visualDepth(index)
                let ground=tree.outlinedRows ? Design.card:(depth > 0 ? Design.mix(Design.card,tree.tint(index,item:item),0.045):Design.card)
                let ring=tree.active(index) || tree.terminal(index)
                if ring {
                    let outer=NSBezierPath(ovalIn:NSRect(x:x-8,y:y-8,width:16,height:16))
                    ground.setFill();outer.fill();ink.withAlphaComponent(0.65).setStroke();outer.lineWidth=1;outer.stroke()
                }
                let dot=NSBezierPath(ovalIn:NSRect(x:x-4.5,y:y-4.5,width:9,height:9))
                (tree.active(index) ? ink:ground).setFill();dot.fill()
                ink.setStroke();dot.lineWidth=1;dot.stroke()
            }
            if let y=tree.reorderLineY {
                Design.orange.setFill()
                NSBezierPath(roundedRect:NSRect(x:24,y:y-1,width:max(0,bounds.width-32),height:2),xRadius:1,yRadius:1).fill()
            }
        }
    }
    final class Row:NSTableRowView {
        weak var accordion:WorkspaceBranchTree?
        override func drawBackground(in dirtyRect:NSRect) {
            guard let tree=accordion else{return}
            let index=tree.row(for:self)
            guard index >= 0,let item=tree.item(atRow:index) else{return}
            if (item as? WorkspaceCatalogues.Node)?.key == "icc-content"{Design.card.setFill();bounds.fill();return}
            let depth=tree.visualDepth(index)
            let lane=WorkspaceBranchTree.lane(depth)
            if depth > 0 && !tree.outlinedRows && tree.rowClear?(item) != true {
                fill(bounds,Design.mix(Design.card,tree.tint(index,item:item),0.045))
            }
            let inset:CGFloat=tree.showsConnectors ? lane+13:8
            // The node's outer right edge uses the panel's 16 pt content margin.
            // Plain tree cards already begin at that same margin; connector rings
            // provide the left edge for branching trees.
            let trailingInset:CGFloat=10
            let targeting=tree.colourModeActive && isSelected
            let surfaceInset=WorkspaceBranchTree.surfaceInset+(targeting ? 2:0)
            let box=NSRect(x:inset,y:surfaceInset,width:max(0,bounds.width-inset-trailingInset),height:bounds.height-2*surfaceInset)
            let colour=tree.background(index,item:item)
            let customBorder=tree.rowBorder?(item)
            let path=NSBezierPath(roundedRect:box,xRadius:7,yRadius:7)
            if let accent=tree.rowLeadingAccent?(item) {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect:NSRect(x:box.minX,y:box.minY,width:5,height:box.height)).addClip()
                accent.setFill();path.fill()
                NSGraphicsContext.restoreGraphicsState()
                (customBorder ?? Design.rule).setStroke()
                path.lineWidth=customBorder == nil ? 1:1.5;path.stroke()
            } else if tree.rowClear?(item) == true {
                (customBorder ?? Design.rule).setStroke();path.lineWidth=customBorder == nil ? 1:1.5;path.stroke()
            } else if tree.outlinedRows && tree.rowFill?(item) != true {
                let navigationSelected=isSelected && !tree.colourModeActive
                let border=customBorder ?? tree.rowColour?(item) ?? (navigationSelected ? Design.ink:Design.rule)
                border.setStroke();path.lineWidth=navigationSelected || customBorder != nil ? 1.5:1;path.stroke()
            } else {
                colour.setFill();path.fill()
                if let customBorder {customBorder.setStroke();path.lineWidth=1.5;path.stroke()}
                else if (isSelected && !tree.colourModeActive) || tree.hoverRow == index {
                    tree.ink(index,item:item).withAlphaComponent(isSelected && !tree.colourModeActive ? 0.65:0.35).setStroke()
                    path.lineWidth=isSelected && !tree.colourModeActive ? 1.5:1;path.stroke()
                }
            }
            if targeting {
                // The selected row grows by four points, keeping its card size and
                // editable border while leaving two more points before the target band.
                let marker=box.insetBy(dx:-4.5,dy:-4.5)
                ColourTargetBarberPole.draw(in:marker,radius:11.5,thickness:2)
            } else if tree.selectedBarberPole && isSelected {
                ColourTargetBarberPole.draw(in:box.insetBy(dx:-2,dy:-2),radius:9,thickness:3)
            }
            if tree.paletteDragActive,tree.isDropTarget?(item) == true {
                Design.houseYellow.setStroke()
                let box=NSRect(x:lane+13,y:2,width:max(0,bounds.width-lane-18),height:bounds.height-4)
                let path=NSBezierPath(roundedRect:box,xRadius:7,yRadius:7);path.lineWidth=2;path.stroke()
            }
            tree.refreshCell(index)
        }
        override func drawSelection(in dirtyRect:NSRect) {} // Selection belongs to the timeline surface.
    }
}
