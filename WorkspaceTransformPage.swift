import AppKit

/// A page-local viewport. Both the cards and their connectors share one world transform;
/// the background grid moves by the same offset while its stroke stays screen-sized.
final class WorkspaceTransformPage: NSView {
    override var isFlipped: Bool { true }
    private let title=Design.text("Transform",.heading)
    private let hint=Design.text("Drag or trackpad scroll to pan · Mouse wheel, ⌘ scroll or pinch to zoom",.caption)
    private let titleGroup=NSView(frame:.zero)
    private let actionbar=WorkspaceViewportBar(footer:false)
    private let closeButton=SwissButton("Done",.quiet)
    private let resetButton=SwissButton("Fit",.quiet)
    private let saveDiagramButton=SwissButton("Diagrams",.quiet)
    private let zoomOut=SwissButton("Zoom Out",.quiet)
    private let zoomIn=SwissButton("Zoom In",.quiet)
    private let canvas=Canvas()
    private let scopes=TransformScopesPanel(frame:.zero)
    private var scopesOpen=false
    private var scopesHeight:CGFloat?
    var onClose:(()->Void)?
    var onChange:((PaletteTransformGraph)->Void)?
    var onSave:((UUID,UUID?)->UUID?)?
    var onSaveDestinations:(()->[(UUID,String)])?
    var onDeleteGraph:(()->Void)?
    var onInspectStage:((UUID)->Void)?
    var onSelectNode:((UUID,Bool)->Void)?
    var onInspectDiagram:(()->Void)?
    var selectedPaletteID:UUID?{canvas.selectedPaletteID}
    var graph:PaletteTransformGraph? { didSet {
        let changedSource=oldValue?.sourcePaletteID != graph?.sourcePaletteID
        canvas.graph=graph
        if changedSource {canvas.fit()}
        scopes.graph=graph
        let retained=scopes.selectedPaletteID.flatMap{id in graph?.nodes.contains(where:{$0.id==id}) == true ? id:nil}
        scopes.selectedPaletteID=changedSource ? graph?.root.id:(canvas.selectedPaletteID ?? retained ?? graph?.root.id)
        title.stringValue=graph.map{"Transform · \($0.root.name)"} ?? "Transform"
    } }

    override init(frame:NSRect) {
        super.init(frame:frame)
        wantsLayer=true;layer?.backgroundColor=Design.card.cgColor;layer?.masksToBounds=true
        title.font=Design.Text.heading.font();hint.font=Design.Text.caption.font()
        actionbar.configureCustomControls()
        addSubview(actionbar)
        for button in [closeButton,resetButton,zoomOut,zoomIn,saveDiagramButton] {actionbar.addSubview(button)}
        closeButton.actionSymbol="checkmark";closeButton.target=self;closeButton.action=#selector(close);closeButton.toolTip="Leave Transform Canvas"
        resetButton.actionSymbol="arrow.up.left.and.arrow.down.right";resetButton.target=self;resetButton.action=#selector(fit);resetButton.toolTip="Fit The Entire Diagram"
        saveDiagramButton.actionSymbol="square.stack";saveDiagramButton.target=self;saveDiagramButton.action=#selector(inspectDiagram);saveDiagramButton.toolTip="Save, Apply Or Import Diagram Presets"
        zoomOut.actionSymbol="minus.magnifyingglass";zoomOut.target=self;zoomOut.action=#selector(out)
        zoomIn.actionSymbol="plus.magnifyingglass";zoomIn.target=self;zoomIn.action=#selector(inside)
        titleGroup.addSubview(title);titleGroup.addSubview(hint)
        actionbar.addSubview(titleGroup);addSubview(canvas);addSubview(scopes)
        actionbar.rightControls=[(view:saveDiagramButton,width:105,height:32,gap:8),(view:resetButton,width:66,height:32,gap:8),(view:zoomOut,width:106,height:32,gap:4),(view:zoomIn,width:94,height:32,gap:12),(view:closeButton,width:82,height:32,gap:0)]
        canvas.wantsLayer=true;canvas.layer?.masksToBounds=true
        canvas.onChange={ [weak self] value in self?.graph=value;self?.onChange?(value) }
        canvas.onSave={ [weak self] id,destination in self?.onSave?(id,destination) }
        canvas.onSaveDestinations={ [weak self] in self?.onSaveDestinations?() ?? [] }
        canvas.onDeleteGraph={ [weak self] in self?.onDeleteGraph?() }
        canvas.onInspectStage={ [weak self] id in self?.onInspectStage?(id) }
        canvas.onSelectNode={ [weak self] id,isTransform in
            if !isTransform {self?.scopes.selectedPaletteID=id}
            self?.onSelectNode?(id,isTransform)
        }
        scopes.onToggle={ [weak self] in self?.toggleScopes() }
        scopes.onResize={ [weak self] delta in
            guard let self else{return}
            self.scopesHeight=min(self.bounds.height-110,max(170,(self.scopesHeight ?? self.bounds.height*0.4)+delta))
            self.needsLayout=true
        }
    }
    required init?(coder:NSCoder){fatalError()}
    override func layout() {
        super.layout()
        let w=bounds.width
        actionbar.frame=NSRect(x:0,y:0,width:w,height:58)
        let textWidth=max(100,w-550)
        titleGroup.frame=NSRect(x:16,y:4,width:textWidth,height:50)
        title.frame=NSRect(x:0,y:24,width:textWidth,height:26)
        hint.frame=NSRect(x:0,y:4,width:textWidth,height:18)
        canvas.frame=NSRect(x:0,y:58,width:w,height:max(0,bounds.height-58))
        let height=min(bounds.height-110,max(170,scopesHeight ?? bounds.height*0.4))
        scopes.frame=NSRect(x:0,y:bounds.height-(scopesOpen ? height+32:32),width:w,height:scopesOpen ? height+32:32)
    }
    @objc private func close(){onClose?()}
    @objc private func inspectDiagram(){onInspectDiagram?()}
    @objc private func fit(){canvas.fit()}
    @objc private func out(){canvas.zoom(by:0.8,around:NSPoint(x:canvas.bounds.midX,y:canvas.bounds.midY))}
    @objc private func inside(){canvas.zoom(by:1.25,around:NSPoint(x:canvas.bounds.midX,y:canvas.bounds.midY))}
    private func toggleScopes() {
        scopesOpen.toggle();scopes.expanded=scopesOpen
        let height=min(bounds.height-110,max(170,scopesHeight ?? bounds.height*0.4))
        let target=NSRect(x:0,y:bounds.height-(scopesOpen ? height+32:32),width:bounds.width,height:scopesOpen ? height+32:32)
        NSAnimationContext.runAnimationGroup { context in
            context.duration=0.24;context.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut)
            scopes.animator().frame=target
        }
    }

    private final class Canvas:NSView {
        override var isFlipped:Bool{true}
        var graph:PaletteTransformGraph? {didSet{
            if oldValue?.sourcePaletteID != graph?.sourcePaletteID {selectedNodeID=graph?.root.id}
            if let graph,selectedNodeID.map({id in graph.nodes.contains(where:{$0.id==id}) || graph.branches.contains(where:{$0.stages.contains(where:{$0.id==id})})}) != true {
                selectedNodeID=graph.root.id
            }
            needsDisplay=true
        }}
        var onChange:((PaletteTransformGraph)->Void)?
        var onSave:((UUID,UUID?)->UUID?)?
        var onSaveDestinations:(()->[(UUID,String)])?
        var onDeleteGraph:(()->Void)?
        var onInspectStage:((UUID)->Void)?
        var onSelectNode:((UUID,Bool)->Void)?
        private var selectedNodeID:UUID?
        var selectedPaletteID:UUID?{selectedNodeID.flatMap{id in graph?.nodes.contains(where:{$0.id==id}) == true ? id:nil}}
        private var pan=NSPoint(x:20,y:8)
        private var scale:CGFloat=1
        private var dragStart:NSPoint?
        private let contextMenu=SwissContextMenu()
        private let cardWidth:CGFloat=252,cardHeight:CGFloat=155,rowHeight:CGFloat=216,unitWidth:CGFloat=378
        private let branchWidth:CGFloat=30,transformWidth:CGFloat=252,transformHeight:CGFloat=155,connectorGap:CGFloat=24
        private var frames:[UUID:NSRect]=[:]
        private var branchFrames:[UUID:NSRect]=[:]
        private var nodeFrames:[UUID:NSRect]=[:]
        private var plusFrames:[UUID:NSRect]=[:]
        private var sliderFrames:[UUID:NSRect]=[:]
        private var dialFrames:[UUID:NSRect]=[:]
        private var degreeFieldFrames:[UUID:NSRect]=[:]
        private var previewFrames:[UUID:NSRect]=[:]
        private var transformTabs:[UUID:NSRect]=[:]
        private var paletteTabs:[UUID:NSRect]=[:]
        private var layoutKey:Int?
        private var adjustingStageID:UUID?
        private var dialDragAnchor:(id:UUID,angle:Double,amount:Double)?
        private var editingDegreeStageID:UUID?
        private var wheelCommit:DispatchWorkItem?
        private var wheelRemainder:Double=0
        private var wheelStageID:UUID?

        override func resetCursorRects() {
            super.resetCursorRects()
            layoutGraph()
            for rect in Array(transformTabs.values)+Array(paletteTabs.values)+Array(branchFrames.values) {
                let screen=NSRect(x:rect.minX*scale+pan.x,y:rect.minY*scale+pan.y,width:rect.width*scale,height:rect.height*scale)
                addCursorRect(screen,cursor:.pointingHand)
            }
        }

        private func layoutGraph() {
            guard let graph,let root=graph.nodes.first else {
                layoutKey=nil;frames.removeAll();branchFrames.removeAll();nodeFrames.removeAll();plusFrames.removeAll()
                sliderFrames.removeAll();dialFrames.removeAll();degreeFieldFrames.removeAll();previewFrames.removeAll();transformTabs.removeAll();paletteTabs.removeAll()
                return
            }
            var signature=Hasher()
            for node in graph.nodes {signature.combine(node.id);signature.combine(node.parentID)}
            for branch in graph.branches {
                signature.combine(branch.id);signature.combine(branch.parentID);signature.combine(branch.outputID)
                signature.combine(branch.sourceBranchID);signature.combine(branch.sourceStageID)
                for stage in branch.stages {signature.combine(stage.id);signature.combine(stage.formula?.rawValue)}
            }
            let key=signature.finalize()
            if layoutKey==key {return}
            layoutKey=key
            frames.removeAll();branchFrames.removeAll();nodeFrames.removeAll();plusFrames.removeAll()
            sliderFrames.removeAll();dialFrames.removeAll();degreeFieldFrames.removeAll();previewFrames.removeAll();transformTabs.removeAll();paletteTabs.removeAll()
            var depths:[UUID:Int]=[:]
            func depth(_ id:UUID,_ d:Int){
                depths[id]=d
                for slot in graph.branches where slot.parentID==id {
                    if let outputID=slot.outputID {depth(outputID,d+1)}
                }
            }
            depth(root.id,0)
            let maxDepth=depths.values.max() ?? 0
            var columnX:[CGFloat]=[38]
            if maxDepth>0 {for level in 0..<maxDepth {
                let slots=graph.branches.filter{depths[$0.parentID]==level}
                let units=max(1,slots.map{graph.firstUnit(of:$0.id)+$0.stages.count}.max() ?? 1)
                columnX.append(columnX[level]+cardWidth+connectorGap+CGFloat(units)*unitWidth)
            }}
            var nextRow=0
            var branchRows:[UUID:Int]=[:]
            func placeBranch(_ slot:PaletteTransformGraph.Branch)->Int {
                let row:Int
                if let outputID=slot.outputID,let child=graph.nodes.first(where:{$0.id==outputID}) {row=place(child)}
                else {row=nextRow;nextRow+=1}
                branchRows[slot.id]=row
                for side in graph.branches where side.sourceBranchID==slot.id {_ = placeBranch(side)}
                return row
            }
            func place(_ node:PaletteTransformGraph.Node)->Int {
                let slots=graph.branches.filter{$0.parentID==node.id && $0.sourceBranchID==nil}
                let row=slots.first.map{placeBranch($0)} ?? nextRow
                if slots.isEmpty {nextRow+=1}
                for slot in slots.dropFirst(){_ = placeBranch(slot)}
                let d=depths[node.id] ?? 0
                let frame=NSRect(x:columnX[d],y:34+CGFloat(row)*rowHeight,width:cardWidth,height:cardHeight)
                frames[node.id]=frame
                paletteTabs[node.id]=NSRect(x:frame.midX-54,y:frame.maxY-1,width:108,height:32)
                return row
            }
            _ = place(root)
            for slot in graph.branches {
                guard let parent=frames[slot.parentID],let row=branchRows[slot.id] else{continue}
                for (offset,stage) in slot.stages.enumerated() {
                    let x=parent.maxX+connectorGap+CGFloat(graph.firstUnit(of:slot.id)+offset)*unitWidth
                    let y=34+CGFloat(row)*rowHeight
                    branchFrames[stage.id]=NSRect(x:x,y:y+(transformHeight-36)/2,width:branchWidth,height:36)
                    let panelX=x+branchWidth+connectorGap
                    nodeFrames[stage.id]=NSRect(x:panelX,y:y,width:transformWidth,height:transformHeight)
                    transformTabs[stage.id]=NSRect(x:panelX+54,y:y+transformHeight-1,width:144,height:32)
                    if let formula=stage.formula {
                        plusFrames[stage.id]=NSRect(x:panelX+transformWidth+connectorGap,y:y+(transformHeight-24)/2,width:24,height:24)
                        if formula == .hueRotate {
                            dialFrames[stage.id]=NSRect(x:panelX,y:y+38,width:58,height:82)
                            degreeFieldFrames[stage.id]=NSRect(x:panelX+96,y:y+63,width:142,height:30)
                        } else if formula.usesPrimaryAmount {
                            sliderFrames[stage.id]=NSRect(x:panelX+16,y:y+65,width:220,height:18)
                        }
                        previewFrames[stage.id]=NSRect(x:panelX+14,y:y+131,width:224,height:18)
                    }
                }
            }
        }
        override func draw(_ dirtyRect:NSRect) {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect:bounds).addClip()
            Design.card.setFill();NSBezierPath(rect:bounds).fill()
            drawGrid()
            guard let graph else{NSGraphicsContext.restoreGraphicsState();return}
            layoutGraph()
            let transform=NSAffineTransform();transform.translateX(by:pan.x,yBy:pan.y);transform.scale(by:scale);transform.concat()
            let visible=NSRect(x:-pan.x/scale,y:-pan.y/scale,width:bounds.width/scale,height:bounds.height/scale).insetBy(dx:-24,dy:-24)
            for slot in graph.branches {
                guard let parent=frames[slot.parentID],let first=slot.stages.first,
                      let branch=branchFrames[first.id] else{continue}
                let line=NSBezierPath()
                let siblings=graph.branches.filter{$0.parentID==slot.parentID && $0.sourceBranchID==slot.sourceBranchID && $0.sourceStageID==slot.sourceStageID}
                if siblings.first?.id == slot.id {
                    let source=slot.sourceStageID.flatMap{plusFrames[$0] ?? nodeFrames[$0]}
                    let origin=source.map{NSPoint(x:$0.maxX,y:$0.midY)} ?? NSPoint(x:parent.maxX,y:parent.midY)
                    line.move(to:origin)
                    line.line(to:NSPoint(x:branch.minX,y:branch.midY))
                    if let last=siblings.last,let lastStage=last.stages.first,let lower=branchFrames[lastStage.id],lower.minY>branch.maxY {
                        // The T trunk leaves the bottom of the branch button, not the palette connector.
                        line.move(to:NSPoint(x:branch.midX,y:branch.maxY))
                        line.line(to:NSPoint(x:branch.midX,y:lower.minY))
                    }
                }
                for (offset,stage) in slot.stages.enumerated() {
                    guard let split=branchFrames[stage.id],let selector=nodeFrames[stage.id] else{continue}
                    line.move(to:NSPoint(x:split.maxX,y:split.midY))
                    line.line(to:NSPoint(x:selector.minX,y:selector.midY))
                    if stage.hidden {
                        line.move(to:NSPoint(x:selector.minX,y:selector.midY))
                        line.line(to:NSPoint(x:selector.maxX,y:selector.midY))
                    }
                    let exit=plusFrames[stage.id] ?? selector
                    if plusFrames[stage.id] != nil {
                        line.move(to:NSPoint(x:selector.maxX,y:selector.midY))
                        line.line(to:NSPoint(x:exit.minX,y:exit.midY))
                    }
                    if offset+1<slot.stages.count,let next=branchFrames[slot.stages[offset+1].id] {
                        line.move(to:NSPoint(x:exit.maxX,y:exit.midY))
                        line.line(to:NSPoint(x:next.minX,y:next.midY))
                    } else if let outputID=slot.outputID,let target=frames[outputID] {
                        line.move(to:NSPoint(x:exit.maxX,y:exit.midY))
                        line.line(to:NSPoint(x:target.minX,y:target.midY))
                    }
                }
                Design.ink.setStroke();line.lineWidth=1.5;line.stroke()
            }
            // Merge wires enter from above, opposite the downward split trunk.
            for slot in graph.branches {for stage in slot.stages where stage.formula == .merge && !stage.bypassed && !stage.hidden {
                guard let sourceID=stage.mergeSourceBranchID,
                      let source=graph.branches.first(where:{$0.id==sourceID}),
                      let outputID=source.outputID,let output=frames[outputID],
                      let junction=branchFrames[stage.id] else{continue}
                let lane=min(output.minY,junction.minY)-20
                let wire=NSBezierPath()
                wire.move(to:NSPoint(x:output.midX,y:output.minY))
                wire.line(to:NSPoint(x:output.midX,y:lane))
                wire.line(to:NSPoint(x:junction.midX,y:lane))
                wire.line(to:NSPoint(x:junction.midX,y:junction.minY))
                Design.ink.setStroke();wire.lineWidth=1.5;wire.stroke()
            }}
            for node in graph.nodes {
                guard let frame=frames[node.id],frame.intersects(visible) else{continue}
                if node.hidden {drawHiddenLink(in:frame,label:"Hidden Palette")}
                else {
                    drawPalette(node,in:frame,isRoot:node.id==graph.root.id)
                    if let tab=paletteTabs[node.id] {drawActionTab(tab,kind:.palette,id:node.id)}
                    if selectedNodeID == node.id,let tab=paletteTabs[node.id] {WorkspaceTabContour.drawSelectedCardContour(card:frame,tab:tab)}
                }
            }
            for slot in graph.branches {for stage in slot.stages {
                guard let branch=branchFrames[stage.id],let selector=nodeFrames[stage.id] else{continue}
                if branch.intersects(visible) {if slot.hidden {drawHiddenLink(in:branch,label:nil)} else {drawBranch(in:branch,merge:stage.formula == .merge)}}
                if selector.intersects(visible) {
                    if stage.hidden {drawHiddenLink(in:selector,label:"Hidden Transform")}
                    else {
                        drawTransform(stage,in:selector)
                        if stage.bypassed {drawBypass(around:selector,stageID:stage.id)}
                        if let tab=transformTabs[stage.id] {drawActionTab(tab,kind:.transform,id:stage.id)}
                        if selectedNodeID == stage.id,let tab=transformTabs[stage.id] {WorkspaceTabContour.drawSelectedCardContour(card:selector,tab:tab)}
                    }
                }
                if let plus=plusFrames[stage.id],plus.intersects(visible) {drawPlus(in:plus)}
            }
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        private func drawGrid() {
            let step:CGFloat=28*scale
            guard step >= 7 else{return}
            let path=NSBezierPath()
            var x=pan.x.truncatingRemainder(dividingBy:step)
            while x<bounds.width {path.move(to:NSPoint(x:x,y:0));path.line(to:NSPoint(x:x,y:bounds.height));x+=step}
            var y=pan.y.truncatingRemainder(dividingBy:step)
            while y<bounds.height {path.move(to:NSPoint(x:0,y:y));path.line(to:NSPoint(x:bounds.width,y:y));y+=step}
            Design.rule.withAlphaComponent(0.28).setStroke();path.lineWidth=0.5;path.stroke()
        }
        private func drawPalette(_ node:PaletteTransformGraph.Node,in rect:NSRect,isRoot:Bool) {
            Design.card.setFill();NSBezierPath(roundedRect:rect,xRadius:8,yRadius:8).fill()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect:rect,xRadius:8,yRadius:8).addClip()
            Design.hex("#161616").setFill();NSBezierPath(rect:NSRect(x:rect.minX,y:rect.minY,width:rect.width,height:32)).fill()
            NSGraphicsContext.restoreGraphicsState()
            Design.rule.setStroke();let outline=NSBezierPath(roundedRect:rect,xRadius:8,yRadius:8);outline.lineWidth=1;outline.stroke()
            let activeStage=graph?.branches.first(where:{$0.outputID==node.id})?.stages.last(where:{$0.formula != nil})
            let code=graph?.code(for:node.id) ?? "A"
            let caption=isRoot ? "\(code) · SOURCE PALETTE":"\(code) · DERIVED · \(activeStage?.title ?? "Pass Through")"
            caption.draw(in:NSRect(x:rect.minX+12,y:rect.minY+8,width:rect.width-24,height:18),withAttributes:[.font:Design.Text.caption.font(),.foregroundColor:Design.hex("#F8F7F5")])
            let name=node.name as NSString
            name.draw(in:NSRect(x:rect.minX+12,y:rect.minY+42,width:rect.width-24,height:20),withAttributes:[.font:Design.Text.bodyStrong.font(),.foregroundColor:Design.ink])
            let colours=node.definitions?.map{$0.master.display} ?? node.hexes.map(Design.hex)
            let count=max(1,colours.count),bandWidth=(rect.width-24)/CGFloat(count)
            for (i,colour) in colours.enumerated(){colour.setFill();NSBezierPath(rect:NSRect(x:rect.minX+12+CGFloat(i)*bandWidth,y:rect.minY+72,width:bandWidth,height:68)).fill()}
        }
        private func drawBranch(in rect:NSRect,merge:Bool=false) {
            Design.card.setFill();NSBezierPath(roundedRect:rect,xRadius:7,yRadius:7).fill()
            Design.rule.setStroke();let line=NSBezierPath(roundedRect:rect,xRadius:7,yRadius:7);line.lineWidth=1;line.stroke()
            let path=NSBezierPath()
            if merge {
                path.move(to:NSPoint(x:rect.minX+7,y:rect.midY));path.line(to:NSPoint(x:rect.maxX-7,y:rect.midY))
                path.move(to:NSPoint(x:rect.midX,y:rect.minY+5));path.line(to:NSPoint(x:rect.midX,y:rect.midY))
            } else {
                path.move(to:NSPoint(x:rect.minX+7,y:rect.minY+11));path.line(to:NSPoint(x:rect.minX+15,y:rect.minY+11))
                path.line(to:NSPoint(x:rect.minX+15,y:rect.minY+25));path.line(to:NSPoint(x:rect.minX+23,y:rect.minY+25))
                path.move(to:NSPoint(x:rect.minX+15,y:rect.minY+11));path.line(to:NSPoint(x:rect.minX+23,y:rect.minY+11))
            }
            Design.ink.setStroke();path.lineWidth=1.5;path.stroke()
            let endpoints=merge ? [NSPoint(x:rect.minX+7,y:rect.midY),NSPoint(x:rect.midX,y:rect.minY+5),NSPoint(x:rect.maxX-7,y:rect.midY)]
                : [NSPoint(x:rect.minX+7,y:rect.minY+11),NSPoint(x:rect.minX+23,y:rect.minY+11),NSPoint(x:rect.minX+23,y:rect.minY+25)]
            for point in endpoints {
                Design.card.setFill();NSBezierPath(ovalIn:NSRect(x:point.x-2,y:point.y-2,width:4,height:4)).fill()
                Design.ink.setStroke();NSBezierPath(ovalIn:NSRect(x:point.x-2,y:point.y-2,width:4,height:4)).stroke()
            }
        }
        private enum TabKind {case transform,palette}
        private func drawActionTab(_ tab:NSRect,kind:TabKind,id:UUID) {
            WorkspaceTabContour.drawCardActionTab(tab)
            let icons=kind == .transform ? ["bypass","eye.slash","square.and.arrow.down","trash"]:["square.and.arrow.down","eye.slash","trash"]
            let cell=tab.width/CGFloat(icons.count)
            for (index,symbol) in icons.enumerated() {
                let rect=NSRect(x:tab.minX+CGFloat(index)*cell+(cell-20)/2,y:tab.minY+6,width:20,height:20)
                if symbol == "bypass" {
                    let active=graph?.branches.flatMap(\.stages).first(where:{$0.id==id})?.formula != nil
                    TransformBypassGlyph.draw(in:rect,enabled:active)
                }
                else {
                    let colour=(kind == .palette && index==0 && graph?.nodes.first(where:{$0.id==id})?.parentID == nil) ? Design.quiet:Design.ink
                    RowMark.image(symbol,colour:colour).draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
                }
            }
        }
        private func drawHiddenLink(in rect:NSRect,label:String?) {
            let wire=NSBezierPath();wire.move(to:NSPoint(x:rect.minX,y:rect.midY));wire.line(to:NSPoint(x:rect.maxX,y:rect.midY))
            Design.quiet.setStroke();wire.lineWidth=1.5;wire.stroke()
            if let label {
                let frame=NSRect(x:rect.midX-58,y:rect.midY-12,width:116,height:24)
                Design.card.setFill();NSBezierPath(roundedRect:frame,xRadius:4,yRadius:4).fill()
                label.draw(in:frame.insetBy(dx:5,dy:4),withAttributes:[.font:Design.Text.caption.font(),.foregroundColor:Design.quiet,.paragraphStyle:centeredText()])
            } else {
                RowMark.image("eye.slash",colour:Design.quiet).draw(in:rect.insetBy(dx:6,dy:9),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            }
        }
        private func drawBypass(around rect:NSRect,stageID:UUID) {
            let before=branchFrames[stageID]
            let after=plusFrames[stageID]
            let incomingX=before.map{($0.maxX+rect.minX)/2} ?? rect.minX-connectorGap/2
            let outgoingX=after.map{(rect.maxX+$0.minX)/2} ?? rect.maxX+connectorGap/2
            let path=NSBezierPath()
            path.move(to:NSPoint(x:incomingX,y:rect.midY))
            path.line(to:NSPoint(x:incomingX,y:rect.minY-14))
            path.line(to:NSPoint(x:outgoingX,y:rect.minY-14))
            path.line(to:NSPoint(x:outgoingX,y:rect.midY))
            Design.ink.setStroke();path.lineWidth=1.5;path.stroke()
            for x in [incomingX,outgoingX] {
                let cross=NSBezierPath()
                cross.move(to:NSPoint(x:x-4,y:rect.midY-4));cross.line(to:NSPoint(x:x+4,y:rect.midY+4))
                cross.move(to:NSPoint(x:x+4,y:rect.midY-4));cross.line(to:NSPoint(x:x-4,y:rect.midY+4))
                NSColor.systemRed.setStroke();cross.lineWidth=2;cross.stroke()
            }
        }
        private func drawTransform(_ stage:PaletteTransformGraph.Stage,in rect:NSRect) {
            Design.card.setFill();NSBezierPath(roundedRect:rect,xRadius:7,yRadius:7).fill()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect:rect,xRadius:7,yRadius:7).addClip()
            Design.houseYellow.setFill();NSBezierPath(rect:NSRect(x:rect.minX,y:rect.minY,width:rect.width,height:32)).fill()
            NSGraphicsContext.restoreGraphicsState()
            Design.rule.setStroke();let outline=NSBezierPath(roundedRect:rect,xRadius:7,yRadius:7);outline.lineWidth=1;outline.stroke()
            let darkInk=Design.hex("#161616")
            let code=graph?.branches.first(where:{$0.stages.contains(where:{$0.id==stage.id})}).map{graph?.branchCode($0.id) ?? "?"} ?? "?"
            ("\(code) · " + (stage.formula == nil ? "Choose Transform":stage.title)).draw(in:NSRect(x:rect.minX+14,y:rect.minY+7,width:rect.width-50,height:20),withAttributes:[.font:Design.Text.bodyStrong.font(),.foregroundColor:darkInk])
            RowMark.image("slider.horizontal.3",colour:darkInk).draw(in:NSRect(x:rect.maxX-31,y:rect.minY+7,width:18,height:18),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            guard let formula=stage.formula else {
                "Select a formula".draw(in:NSRect(x:rect.minX+14,y:rect.minY+42,width:rect.width-28,height:20),withAttributes:[.font:Design.Text.body.font(),.foregroundColor:Design.quiet])
                return
            }
            if formula == .hueRotate,let dial=dialFrames[stage.id],let degree=degreeFieldFrames[stage.id] {
                drawHueDial(in:dial,amount:stage.amount)
                drawDegreeField(in:degree,amount:stage.amount,stageID:stage.id)
            } else if let message=PaletteTransformEngine.availability(stage,colourCount:graph?.root.definitions?.count ?? 0) {
                message.draw(in:NSRect(x:rect.minX+14,y:rect.minY+42,width:rect.width-28,height:58),withAttributes:[.font:Design.Text.body.font(),.foregroundColor:Design.quiet])
            } else if formula == .greyscale {
                "Saturation 0%".draw(in:NSRect(x:rect.minX+14,y:rect.minY+42,width:rect.width-28,height:20),withAttributes:[.font:Design.Text.body.font(),.foregroundColor:Design.quiet])
            } else if let track=sliderFrames[stage.id] {
                let rail=NSRect(x:track.minX,y:track.midY-2,width:track.width,height:4)
                Design.rule.setFill();NSBezierPath(roundedRect:rail,xRadius:2,yRadius:2).fill()
                let range=formula.range,ratio=CGFloat((stage.amount-range.lowerBound)/(range.upperBound-range.lowerBound))
                let thumbX=track.minX+ratio*track.width
                Design.ink.setFill();NSBezierPath(roundedRect:NSRect(x:track.minX,y:rail.minY,width:max(0,thumbX-track.minX),height:4),xRadius:2,yRadius:2).fill()
                Design.card.setFill();NSBezierPath(ovalIn:NSRect(x:thumbX-7,y:track.midY-7,width:14,height:14)).fill()
                Design.ink.setStroke();let thumb=NSBezierPath(ovalIn:NSRect(x:thumbX-7,y:track.midY-7,width:14,height:14));thumb.lineWidth=1.5;thumb.stroke()
                let reading=formula == .exposure ? String(format:"%+.1f stops",stage.amount) : String(format:"%+.0f%%",stage.amount)
                reading.draw(in:NSRect(x:rect.minX+14,y:rect.minY+91,width:rect.width-28,height:17),withAttributes:[.font:Design.Text.caption.font(),.foregroundColor:Design.quiet])
            } else {
                let summary=transformSummary(stage)
                summary.draw(in:NSRect(x:rect.minX+14,y:rect.minY+42,width:rect.width-28,height:50),withAttributes:[.font:Design.Text.body.font(),.foregroundColor:Design.quiet])
            }
            if let toggle=previewFrames[stage.id] {drawPreviewToggle(in:toggle,checked:stage.previewDownstream)}
        }
        private func transformSummary(_ stage:PaletteTransformGraph.Stage)->String {
            let s=stage.settings
            switch stage.formula {
            case .levels:return String(format:"Black %.2f · Gamma %.2f · White %.2f",s.number("black",0),s.number("gamma",1),s.number("white",1))
            case .curves:return "\(s.curve.count) curve points · luminance"
            case .paletteSpacing:return String(format:"L %.2f–%.2f · %d locked",s.number("low",0),s.number("high",1),s.lockedIndices.count)
            case .contrastTarget:return String(format:"Colour %.0f / %.0f · %.1f:1",s.number("foreground",0)+1,s.number("background",1)+1,s.number("ratio",4.5))
            case .gamutFit:return "Target: \(s.choice("target","srgb"))"
            case .whiteBalance:return "\(s.choice("sourceWhite","D50")) → \(s.choice("targetWhite","D65"))"
            case .referenceMatch:return "\(s.references.count) reference colours"
            case .ascCDL:return String(format:"%@ · Sat %.2f",s.choice("space","srgb"),s.number("saturation",1))
            case .applyLUT:return s.sourceName ?? "Choose a LUT in Controls"
            case .spectralRelight:return "\(s.choice("illuminant","D50")) · \(s.references.count) measured colours"
            case .merge:
                let source=stage.mergeSourceBranchID.map{graph?.branchCode($0) ?? "?"} ?? "Choose Branch"
                let mode=s.choice("blend","mix").capitalized
                return "From \(source) · \(mode) · \(Int(s.number("opacity",0.5)*100))%"
            default:return "Open Controls To Edit"
            }
        }
        private func drawHueDial(in rect:NSRect,amount:Double) {
            let centre=NSPoint(x:rect.minX+2,y:rect.midY),radius:CGFloat=40
            let ring=NSBezierPath()
            ring.appendArc(withCenter:centre,radius:radius,startAngle:-90,endAngle:90,clockwise:false)
            Design.rule.setStroke();ring.lineWidth=1;ring.stroke()
            let ticks=NSBezierPath(),strong=NSBezierPath()
            for degree in stride(from:0,to:360,by:5) {
                let prominent=degree % 45 == 0
                let angle=(90+Double(degree)-amount)*Double.pi/180
                if sin(angle)<0 {continue}
                let inner=radius-(prominent ? 10:4)
                let path=prominent ? strong:ticks
                path.move(to:NSPoint(x:centre.x+CGFloat(sin(angle))*inner,y:centre.y-CGFloat(cos(angle))*inner))
                path.line(to:NSPoint(x:centre.x+CGFloat(sin(angle))*radius,y:centre.y-CGFloat(cos(angle))*radius))
            }
            Design.quiet.setStroke();ticks.lineWidth=1;ticks.stroke()
            Design.ink.setStroke();strong.lineWidth=2.5;strong.stroke()
            let measure=NSBezierPath();measure.move(to:NSPoint(x:centre.x+radius-14,y:centre.y));measure.line(to:NSPoint(x:centre.x+radius+1,y:centre.y))
            Design.ink.setStroke();measure.lineWidth=2.5;measure.stroke()
            let zeroAngle=(90-amount)*Double.pi/180
            if sin(zeroAngle)>=0 {
                let marker=NSPoint(x:centre.x+CGFloat(sin(zeroAngle))*(radius-5),y:centre.y-CGFloat(cos(zeroAngle))*(radius-5))
                Design.ink.setFill();NSBezierPath(ovalIn:NSRect(x:marker.x-3,y:marker.y-3,width:6,height:6)).fill()
            }
        }
        private func centeredText()->NSParagraphStyle {
            let style=NSMutableParagraphStyle();style.alignment = .center;return style
        }
        private func drawDegreeField(in rect:NSRect,amount:Double,stageID:UUID) {
            Design.card.setFill();NSBezierPath(roundedRect:rect,xRadius:4,yRadius:4).fill()
            Design.rule.setStroke();let outline=NSBezierPath(roundedRect:rect,xRadius:4,yRadius:4);outline.lineWidth=1;outline.stroke()
            if editingDegreeStageID != stageID {
                "\(Int(amount.rounded()))°".draw(in:rect.insetBy(dx:8,dy:6),withAttributes:[.font:Design.Text.bodyStrong.font(),.foregroundColor:Design.ink,.paragraphStyle:centeredText()])
            }
        }
        private func drawPreviewToggle(in rect:NSRect,checked:Bool) {
            let box=NSRect(x:rect.minX,y:rect.midY-7,width:14,height:14)
            Design.card.setFill();NSBezierPath(rect:box).fill()
            Design.ink.setStroke();let outline=NSBezierPath(rect:box);outline.lineWidth=1;outline.stroke()
            if checked {
                let mark=NSBezierPath();mark.move(to:NSPoint(x:box.minX+3,y:box.midY));mark.line(to:NSPoint(x:box.minX+6,y:box.maxY-3));mark.line(to:NSPoint(x:box.maxX-2,y:box.minY+3))
                Design.ink.setStroke();mark.lineWidth=1.6;mark.stroke()
            }
            "Preview Downstream".draw(in:NSRect(x:rect.minX+20,y:rect.minY+2,width:rect.width-20,height:18),withAttributes:[.font:Design.Text.caption.font(),.foregroundColor:Design.ink])
        }
        private func drawPlus(in rect:NSRect) {
            Design.card.setFill();NSBezierPath(ovalIn:rect).fill()
            Design.rule.setStroke();let ring=NSBezierPath(ovalIn:rect);ring.lineWidth=1;ring.stroke()
            let cross=NSBezierPath()
            cross.move(to:NSPoint(x:rect.midX-5,y:rect.midY));cross.line(to:NSPoint(x:rect.midX+5,y:rect.midY))
            cross.move(to:NSPoint(x:rect.midX,y:rect.midY-5));cross.line(to:NSPoint(x:rect.midX,y:rect.midY+5))
            Design.ink.setStroke();cross.lineWidth=1.5;cross.stroke()
        }
        private func world(_ point:NSPoint)->NSPoint {NSPoint(x:(point.x-pan.x)/scale,y:(point.y-pan.y)/scale)}
        private func selectNode(_ id:UUID,isTransform:Bool) {
            selectedNodeID=id;needsDisplay=true
            onSelectNode?(id,isTransform)
        }
        override func mouseDown(with event:NSEvent) {
            finishWheelInput()
            let point=convert(event.locationInWindow,from:nil)
            let w=world(point)
            if let (id,frame)=nodeFrames.first(where:{NSRect(x:$0.value.minX,y:$0.value.minY,width:$0.value.width,height:32).contains(w)}),
               let graph,let (branch,index)=stageLocation(id,in:graph),!branch.stages[index].hidden {
                if event.clickCount >= 2 {centre(on:frame);return}
                selectNode(id,isTransform:true)
                openFormulaMenu(for:id,event:event)
                return
            }
            if let (id,frame)=frames.first(where:{NSRect(x:$0.value.minX,y:$0.value.minY,width:$0.value.width,height:32).contains(w)}) {
                if event.clickCount >= 2 {centre(on:frame)}
                else {selectNode(id,isTransform:false)}
                return
            }
            if handleActionTab(at:w) {return}
            if let (id,_)=plusFrames.first(where:{$0.value.contains(w)}) {openInsertMenu(after:id,event:event);return}
            if let (id,_)=branchFrames.first(where:{$0.value.contains(w)}) {
                if graph?.branches.flatMap(\.stages).first(where:{$0.id==id})?.formula == .merge {selectNode(id,isTransform:true);onInspectStage?(id)}
                else if let graph,let (branch,_)=stageLocation(id,in:graph),branch.hidden {setBranchShown(branch.id)}
                else {makeBranch(at:id)}
                return
            }
            if let (id,_)=degreeFieldFrames.first(where:{$0.value.contains(w)}) {selectNode(id,isTransform:true);beginDegreeEdit(id);return}
            if let (id,_)=previewFrames.first(where:{$0.value.contains(w)}) {selectNode(id,isTransform:true);togglePreview(id);return}
            if let (id,_)=dialFrames.first(where:{$0.value.contains(w)}) {
                selectNode(id,isTransform:true)
                beginDialDrag(id,at:w)
                return
            }
            if let (id,_)=sliderFrames.first(where:{$0.value.insetBy(dx:-8,dy:-7).contains(w)}) {
                selectNode(id,isTransform:true)
                adjustingStageID=id;adjustStage(id,at:w);return
            }
            if let (id,_)=nodeFrames.first(where:{$0.value.contains(w)}) {
                selectNode(id,isTransform:true)
                if let graph,let (branch,index)=stageLocation(id,in:graph),branch.stages[index].hidden {setTransformHidden(false,id:id)}
                else if graph?.branches.flatMap(\.stages).first(where:{$0.id==id})?.formula == nil {openFormulaMenu(for:id,event:event)}
                else {needsDisplay=true}
                return
            }
            if let (id,_)=frames.first(where:{$0.value.contains(w)}) {
                selectNode(id,isTransform:false)
                if let node=graph?.nodes.first(where:{$0.id==id}) {
                    if node.hidden {setPaletteHidden(false,id:id)}
                }
                return
            }
            dragStart=point
        }
        override func rightMouseDown(with event:NSEvent) {
            finishWheelInput()
            let point=convert(event.locationInWindow,from:nil),target=world(point)
            if let (id,_)=branchFrames.first(where:{$0.value.contains(target)}) {openBranchContext(id,at:point);return}
            if let (id,_)=nodeFrames.first(where:{$0.value.contains(target)}) {openTransformContext(id,at:point);return}
            if let (id,_)=frames.first(where:{$0.value.contains(target)}) {openPaletteContext(id,at:point);return}
            if let (id,_)=transformTabs.first(where:{$0.value.contains(target)}) {openTransformContext(id,at:point);return}
            if let (id,_)=paletteTabs.first(where:{$0.value.contains(target)}) {openPaletteContext(id,at:point);return}
            contextMenu.open([
                HaloAction(id:"fit-canvas",label:"Fit Canvas",symbol:"arrow.up.left.and.arrow.down.right",onSelect:{[weak self] in self?.fit()}),
                HaloAction(id:"zoom-in",label:"Zoom In",symbol:"plus.magnifyingglass",onSelect:{[weak self] in self?.zoom(by:1.25,around:point)}),
                HaloAction(id:"zoom-out",label:"Zoom Out",symbol:"minus.magnifyingglass",onSelect:{[weak self] in self?.zoom(by:0.8,around:point)})
            ],at:point,in:self)
        }
        override func mouseDragged(with event:NSEvent) {
            if let stageID=adjustingStageID {
                let point=world(convert(event.locationInWindow,from:nil))
                if dialFrames[stageID] != nil {adjustDial(stageID,at:point)}
                else {adjustStage(stageID,at:point)}
                return
            }
            guard let start=dragStart else{return}
            let point=convert(event.locationInWindow,from:nil)
            pan.x+=point.x-start.x;pan.y+=point.y-start.y;dragStart=point;needsDisplay=true
        }
        override func mouseUp(with event:NSEvent){
            if let stageID=adjustingStageID {commitStage(stageID)}
            adjustingStageID=nil;dialDragAnchor=nil;dragStart=nil
        }
        override func scrollWheel(with event:NSEvent) {
            let cursor=convert(event.locationInWindow,from:nil)
            let target=world(cursor)
            if let graph,
               let (stageID,_)=nodeFrames.first(where:{$0.value.contains(target)}),
               let (branch,index)=stageLocation(stageID,in:graph),branch.stages[index].formula == .hueRotate,
               (dialFrames[stageID]?.contains(target) == true || event.modifierFlags.contains(.option)) {
                if wheelStageID != stageID {wheelRemainder=0;wheelStageID=stageID}
                wheelRemainder+=Double(event.scrollingDeltaY)/(event.hasPreciseScrollingDeltas ? 8:1)
                let step=Int(wheelRemainder.rounded(.towardZero))
                if step != 0 {
                    wheelRemainder-=Double(step)
                    updateAmount(branch.stages[index].amount+Double(step),stageID:stageID)
                    scheduleWheelCommit(stageID)
                }
                return
            }
            // Cards, tabs and connector controls own their wheel area. They must never
            // accidentally move the canvas while a user is working over a control.
            if nodeFrames.values.contains(where:{$0.contains(target)}) || frames.values.contains(where:{$0.contains(target)}) ||
                transformTabs.values.contains(where:{$0.contains(target)}) || paletteTabs.values.contains(where:{$0.contains(target)}) ||
                plusFrames.values.contains(where:{$0.contains(target)}) || branchFrames.values.contains(where:{$0.contains(target)}) {return}
            if event.modifierFlags.contains(.command) || !event.hasPreciseScrollingDeltas {
                zoom(by:pow(event.hasPreciseScrollingDeltas ? 1.012:1.12,-event.scrollingDeltaY),around:cursor)
            } else {pan.x+=event.scrollingDeltaX;pan.y+=event.scrollingDeltaY;needsDisplay=true}
        }
        override func magnify(with event:NSEvent){zoom(by:1+event.magnification,around:convert(event.locationInWindow,from:nil))}
        func zoom(by factor:CGFloat,around cursor:NSPoint) {
            let next=min(4,max(0.25,scale*factor)),ratio=next/scale
            pan=NSPoint(x:cursor.x-(cursor.x-pan.x)*ratio,y:cursor.y-(cursor.y-pan.y)*ratio)
            scale=next;needsDisplay=true
        }
        func fit(){pan=NSPoint(x:20,y:8);scale=1;needsDisplay=true}
        private func centre(on frame:NSRect) {
            scale=1
            pan=NSPoint(x:bounds.midX-frame.midX,y:bounds.midY-frame.midY)
            needsDisplay=true
        }
        private func stageLocation(_ stageID:UUID,in graph:PaletteTransformGraph)->(PaletteTransformGraph.Branch,Int)? {
            for branch in graph.branches {
                if let index=branch.stages.firstIndex(where:{$0.id==stageID}) {return (branch,index)}
            }
            return nil
        }
        private func adjustStage(_ stageID:UUID,at point:NSPoint) {
            guard let graph,let track=sliderFrames[stageID],
                  let (branch,index)=stageLocation(stageID,in:graph),
                  let formula=branch.stages[index].formula else{return}
            let ratio=min(1,max(0,Double((point.x-track.minX)/track.width)))
            let amount=formula.range.lowerBound+ratio*(formula.range.upperBound-formula.range.lowerBound)
            updateAmount(amount,stageID:stageID)
        }
        private func beginDialDrag(_ stageID:UUID,at point:NSPoint) {
            guard let graph,let dial=dialFrames[stageID],let (branch,index)=stageLocation(stageID,in:graph) else{return}
            let angle=atan2(Double(point.x-dial.minX-2),Double(dial.midY-point.y))
            dialDragAnchor=(stageID,angle,branch.stages[index].amount)
            adjustingStageID=stageID
        }
        private func adjustDial(_ stageID:UUID,at point:NSPoint) {
            guard let dial=dialFrames[stageID],let anchor=dialDragAnchor,anchor.id==stageID else{return}
            let angle=atan2(Double(point.x-dial.minX-2),Double(dial.midY-point.y))
            let delta=atan2(sin(angle-anchor.angle),cos(angle-anchor.angle))*180/Double.pi
            let amount=(anchor.amount+delta+360).truncatingRemainder(dividingBy:360)
            updateAmount(amount,stageID:stageID)
        }
        private func updateAmount(_ amount:Double,stageID:UUID) {
            guard var graph,let (branch,_)=stageLocation(stageID,in:graph) else{return}
            graph.setAmount(amount,in:branch.id,stageID:stageID,previewOnly:true)
            self.graph=graph
        }
        private func commitStage(_ stageID:UUID) {
            guard var graph,let (branch,_)=stageLocation(stageID,in:graph) else{return}
            graph.commitPreview(in:branch.id)
            self.graph=graph
            onChange?(graph)
        }
        private func scheduleWheelCommit(_ stageID:UUID) {
            wheelCommit?.cancel()
            let work=DispatchWorkItem{[weak self] in
                guard let self else{return}
                self.wheelCommit=nil;self.wheelStageID=nil;self.wheelRemainder=0
                self.commitStage(stageID)
            }
            wheelCommit=work
            DispatchQueue.main.asyncAfter(deadline:.now()+0.25,execute:work)
        }
        private func finishWheelInput() {
            guard let stageID=wheelStageID,wheelCommit != nil else{return}
            wheelCommit?.cancel();wheelCommit=nil;wheelStageID=nil;wheelRemainder=0
            commitStage(stageID)
        }
        private func togglePreview(_ stageID:UUID) {
            guard var graph,let (branch,index)=stageLocation(stageID,in:graph) else{return}
            graph.setPreviewDownstream(!branch.stages[index].previewDownstream,in:branch.id,stageID:stageID)
            self.graph=graph;onChange?(graph)
        }
        private func setTransformBypassed(_ enabled:Bool,id:UUID) {
            guard var graph else{return}
            graph.setBypassed(enabled,stageID:id);onChange?(graph)
        }
        private func setTransformHidden(_ enabled:Bool,id:UUID) {
            guard var graph else{return}
            graph.setTransformHidden(enabled,stageID:id);onChange?(graph)
        }
        private func setPaletteHidden(_ enabled:Bool,id:UUID) {
            guard var graph else{return}
            graph.setPaletteHidden(enabled,paletteID:id);onChange?(graph)
        }
        private func setBranchShown(_ id:UUID) {
            guard var graph else{return}
            graph.showBranch(id);onChange?(graph)
        }
        private func deleteTransform(_ id:UUID) {
            guard var graph else{return}
            graph.removeTransform(id);onChange?(graph)
        }
        private func deletePalette(_ id:UUID) {
            guard var graph else{return}
            if id == graph.root.id {onDeleteGraph?()}
            else {graph.removePalette(id);onChange?(graph)}
        }
        private func handleActionTab(at point:NSPoint)->Bool {
            if let (id,tab)=transformTabs.first(where:{$0.value.contains(point)}),
               let graph,let (branch,index)=stageLocation(id,in:graph),!branch.stages[index].hidden {
                switch Int((point.x-tab.minX)/(tab.width/4)) {
                case 0:if branch.stages[index].formula != nil {setTransformBypassed(!branch.stages[index].bypassed,id:id)}
                case 1:setTransformHidden(true,id:id)
                case 2:onInspectStage?(id)
                default:deleteTransform(id)
                }
                return true
            }
            if let (id,tab)=paletteTabs.first(where:{$0.value.contains(point)}),
               let node=graph?.nodes.first(where:{$0.id==id}),!node.hidden {
                switch Int((point.x-tab.minX)/(tab.width/3)) {
                case 0:if node.parentID != nil {openSaveDestinationMenu(for:id,at:NSPoint(x:point.x*scale+pan.x,y:point.y*scale+pan.y))}
                case 1:setPaletteHidden(true,id:id)
                default:deletePalette(id)
                }
                return true
            }
            return false
        }
        private func openBranchContext(_ stageID:UUID,at point:NSPoint) {
            guard let graph,let (branch,_)=stageLocation(stageID,in:graph) else{return}
            let actions:[HaloAction]=[
                HaloAction(id:"branch-hide",label:branch.hidden ? "Show":"Hide",symbol:branch.hidden ? "eye":"eye.slash",onSelect:{[weak self] in
                    guard let self,var graph=self.graph else{return}
                    if branch.hidden {graph.showBranch(branch.id)} else {graph.hideBranch(branch.id)}
                    self.onChange?(graph)
                }),
                HaloAction(id:"branch-delete",label:"Delete",symbol:"trash",onSelect:{[weak self] in
                    guard let self,var graph=self.graph else{return}
                    graph.removeBranch(branch.id);self.onChange?(graph)
                })
            ]
            contextMenu.open(actions,at:point,in:self)
        }
        private func openTransformContext(_ stageID:UUID,at point:NSPoint) {
            guard let graph,let (branch,index)=stageLocation(stageID,in:graph) else{return}
            let stage=branch.stages[index]
            var actions:[HaloAction]=[]
            if !stage.hidden,stage.formula != nil {
                actions.append(HaloAction(id:"transform-bypass",label:stage.bypassed ? "Resume":"Bypass",symbol:"arrow.triangle.branch",onSelect:{[weak self] in self?.setTransformBypassed(!stage.bypassed,id:stageID)}))
                actions.append(HaloAction(id:"transform-controls",label:"Controls & Presets",symbol:"slider.horizontal.3",onSelect:{[weak self] in self?.onInspectStage?(stageID)}))
            }
            actions.append(HaloAction(id:"transform-hide",label:stage.hidden ? "Show":"Hide",symbol:stage.hidden ? "eye":"eye.slash",onSelect:{[weak self] in self?.setTransformHidden(!stage.hidden,id:stageID)}))
            actions.append(HaloAction(id:"transform-delete",label:"Delete",symbol:"trash",onSelect:{[weak self] in self?.deleteTransform(stageID)}))
            contextMenu.open(actions,at:point,in:self)
        }
        private func openPaletteContext(_ paletteID:UUID,at point:NSPoint) {
            guard let node=graph?.nodes.first(where:{$0.id==paletteID}) else{return}
            var actions:[HaloAction]=[]
            if node.parentID != nil,!node.hidden {
                actions.append(HaloAction(id:"save-to",label:"Save To…",symbol:"square.and.arrow.down",children:{[weak self] in self?.saveActions(for:paletteID) ?? []}))
            }
            actions.append(HaloAction(id:"palette-hide",label:node.hidden ? "Show":"Hide",symbol:node.hidden ? "eye":"eye.slash",onSelect:{[weak self] in self?.setPaletteHidden(!node.hidden,id:paletteID)}))
            actions.append(HaloAction(id:"palette-delete",label:"Delete",symbol:"trash",onSelect:{[weak self] in self?.deletePalette(paletteID)}))
            contextMenu.open(actions,at:point,in:self)
        }
        private func beginDegreeEdit(_ stageID:UUID) {
            guard editingDegreeStageID==nil,let graph,let (branch,index)=stageLocation(stageID,in:graph),
                  let rect=degreeFieldFrames[stageID] else{return}
            let stage=branch.stages[index]
            editingDegreeStageID=stageID;needsDisplay=true
            let screen=NSRect(x:rect.minX*scale+pan.x,y:rect.minY*scale+pan.y,width:rect.width*scale,height:rect.height*scale)
            InlineName.edit("\(Int(stage.amount.rounded()))",style:.bodyStrong,in:self,x:screen.minX+8,baseline:screen.minY+18,width:screen.width-16,at:NSPoint(x:screen.midX,y:screen.midY),selectAll:true){[weak self] text in
                guard let self else{return}
                self.editingDegreeStageID=nil;self.needsDisplay=true
                guard let text,let value=Double(text.replacingOccurrences(of:"°",with:"")),var graph=self.graph,
                      let (branch,_)=self.stageLocation(stageID,in:graph) else{return}
                graph.setAmount(value,in:branch.id,stageID:stageID)
                self.graph=graph;self.onChange?(graph)
            }
        }
        private func makeBranch(at stageID:UUID) {
            guard var graph,let (branch,index)=stageLocation(stageID,in:graph) else{return}
            if index==0 {
                if let sourceID=branch.sourceBranchID,let sourceStage=branch.sourceStageID {
                    _ = graph.addBranch(after:branch.parentID,from:sourceID,stageID:sourceStage,passThrough:true)
                } else {_ = graph.addBranch(after:branch.parentID)}
            } else {
                let preceding=branch.stages[index-1]
                _ = graph.addBranch(after:branch.parentID,from:branch.id,stageID:preceding.id,passThrough:branch.stages.prefix(index).contains{$0.formula != nil})
            }
            onChange?(graph)
        }
        private func openInsertMenu(after stageID:UUID,event:NSEvent) {
            guard let graph,let (branch,_)=stageLocation(stageID,in:graph) else{return}
            let actions=[HaloAction(id:"chain-transform",label:"Add Transform Node",symbol:"slider.horizontal.3",onSelect:{[weak self] in
                guard let self,var graph=self.graph else{return}
                _ = graph.insertTransform(after:stageID,in:branch.id);self.onChange?(graph)
            })]
            contextMenu.open(actions,at:convert(event.locationInWindow,from:nil),in:self)
        }
        private func openFormulaMenu(for stageID:UUID,event:NSEvent) {
            guard let graph,let (branch,index)=stageLocation(stageID,in:graph) else{return}
            let current=branch.stages[index].formula
            let actions=PaletteTransformGraph.Formula.Group.allCases.filter{group in group != .branching || !graph.mergeSources(for:branch.id).isEmpty}.map{group in
                HaloAction(id:group.rawValue,label:group.rawValue,symbol:"slider.horizontal.3",children:{ PaletteTransformGraph.Formula.allCases.filter{$0.group==group}.map{formula in
                HaloAction(id:formula.rawValue,label:formula.title,symbol:"slider.horizontal.3",checked:current==formula,onSelect:{[weak self] in
                    guard let self,var graph=self.graph else{return}
                    _ = graph.transform(formula,in:branch.id,stageID:stageID);self.onChange?(graph)
                })
                }})
            }
            contextMenu.open(actions,at:convert(event.locationInWindow,from:nil),in:self)
        }
        private func saveActions(for id:UUID)->[HaloAction] {
            var actions=[HaloAction(id:"library",label:"My Library",symbol:"tray",onSelect:{[weak self] in self?.saveResult(id,to:nil)})]
            for (projectID,name) in onSaveDestinations?() ?? [] {
                actions.append(HaloAction(id:projectID.uuidString,label:name,symbol:"folder",onSelect:{[weak self] in self?.saveResult(id,to:projectID)}))
            }
            return actions
        }
        private func openSaveDestinationMenu(for id:UUID,at point:NSPoint) {
            contextMenu.open(saveActions(for:id),at:point,in:self)
        }
        private func saveResult(_ id:UUID,to destination:UUID?) {
            guard var graph,let index=graph.nodes.firstIndex(where:{$0.id==id}),let savedID=onSave?(id,destination) else{return}
            graph.nodes[index].savedPaletteID=savedID;onChange?(graph)
        }
    }
}
