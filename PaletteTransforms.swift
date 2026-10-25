import Foundation

/// Palette snapshots are separated by repeatable [branch | transform] gutter units.
/// A source palette can change or disappear without rewriting its saved derivation.
struct PaletteTransformGraph: Codable, Equatable {
    struct Stage: Codable, Equatable, Identifiable {
        var id: UUID = UUID()
        var formula: Formula? = nil
        var amount: Double = 20
        var previewDownstream: Bool = true
        var bypassed: Bool = false
        var hidden: Bool = false
        var settings = TransformSettings()
        /// A Merge reads the completed output of this other branch. The UUID belongs to
        /// the diagram, so it is deliberately separate from portable .coltra settings.
        var mergeSourceBranchID: UUID? = nil

        private enum CodingKeys:String,CodingKey {case id,formula,amount,previewDownstream,bypassed,hidden,settings,mergeSourceBranchID}
        init(id:UUID=UUID(),formula:Formula?=nil,amount:Double?=nil,previewDownstream:Bool=true) {
            self.id=id;self.formula=formula;self.amount=amount ?? formula?.defaultAmount ?? 20
            self.previewDownstream=previewDownstream
        }
        init(from decoder:Decoder) throws {
            let c=try decoder.container(keyedBy:CodingKeys.self)
            id=try c.decode(UUID.self,forKey:.id)
            formula=try c.decodeIfPresent(Formula.self,forKey:.formula)
            amount=try c.decodeIfPresent(Double.self,forKey:.amount) ?? formula?.defaultAmount ?? 20
            previewDownstream=try c.decodeIfPresent(Bool.self,forKey:.previewDownstream) ?? true
            bypassed=try c.decodeIfPresent(Bool.self,forKey:.bypassed) ?? false
            hidden=try c.decodeIfPresent(Bool.self,forKey:.hidden) ?? false
            settings=try c.decodeIfPresent(TransformSettings.self,forKey:.settings) ?? TransformSettings()
            mergeSourceBranchID=try c.decodeIfPresent(UUID.self,forKey:.mergeSourceBranchID)
        }
        var title:String {formula?.title(amount:amount) ?? "Choose Transform"}
    }
    struct Branch: Codable, Equatable, Identifiable {
        var id: UUID = UUID()
        var code: String = ""
        var parentID: UUID
        var outputID: UUID? = nil
        var sourceBranchID: UUID? = nil
        var sourceStageID: UUID? = nil
        var stages: [Stage] = [Stage()]
        var hidden: Bool = false

        private enum CodingKeys:String,CodingKey {case id,code,parentID,outputID,sourceBranchID,sourceStageID,stages,hidden}
        init(id:UUID=UUID(),code:String="",parentID:UUID,outputID:UUID?=nil,sourceBranchID:UUID?=nil,sourceStageID:UUID?=nil,stages:[Stage]=[Stage()]) {
            self.id=id;self.code=code;self.parentID=parentID;self.outputID=outputID
            self.sourceBranchID=sourceBranchID;self.sourceStageID=sourceStageID;self.stages=stages
        }
        init(from decoder:Decoder) throws {
            let c=try decoder.container(keyedBy:CodingKeys.self)
            id=try c.decode(UUID.self,forKey:.id)
            code=try c.decodeIfPresent(String.self,forKey:.code) ?? ""
            parentID=try c.decode(UUID.self,forKey:.parentID)
            outputID=try c.decodeIfPresent(UUID.self,forKey:.outputID)
            sourceBranchID=try c.decodeIfPresent(UUID.self,forKey:.sourceBranchID)
            sourceStageID=try c.decodeIfPresent(UUID.self,forKey:.sourceStageID)
            stages=try c.decodeIfPresent([Stage].self,forKey:.stages) ?? []
            hidden=try c.decodeIfPresent(Bool.self,forKey:.hidden) ?? false
        }
    }
    struct Node: Codable, Equatable, Identifiable {
        var id: UUID = UUID()
        var parentID: UUID?
        var name: String
        var sourceKeys: [String]
        /// Authoritative snapshots. `hexes` is only the sRGB card preview and legacy fallback.
        var definitions: [ColourDefinition]? = nil
        var hexes: [String]
        var formula: Formula?
        var savedPaletteID: UUID? = nil
        var hidden: Bool = false

        private enum CodingKeys:String,CodingKey {case id,parentID,name,sourceKeys,definitions,hexes,formula,savedPaletteID,hidden}
        init(id:UUID=UUID(),parentID:UUID?,name:String,sourceKeys:[String],definitions:[ColourDefinition]?=nil,hexes:[String],formula:Formula?,savedPaletteID:UUID?=nil,hidden:Bool=false) {
            self.id=id;self.parentID=parentID;self.name=name;self.sourceKeys=sourceKeys;self.definitions=definitions;self.hexes=hexes
            self.formula=formula;self.savedPaletteID=savedPaletteID;self.hidden=hidden
        }
        init(from decoder:Decoder) throws {
            let c=try decoder.container(keyedBy:CodingKeys.self)
            id=try c.decode(UUID.self,forKey:.id)
            parentID=try c.decodeIfPresent(UUID.self,forKey:.parentID)
            name=try c.decode(String.self,forKey:.name)
            sourceKeys=try c.decode([String].self,forKey:.sourceKeys)
            definitions=try c.decodeIfPresent([ColourDefinition].self,forKey:.definitions)
            hexes=try c.decode([String].self,forKey:.hexes)
            formula=try c.decodeIfPresent(Formula.self,forKey:.formula)
            savedPaletteID=try c.decodeIfPresent(UUID.self,forKey:.savedPaletteID)
            hidden=try c.decodeIfPresent(Bool.self,forKey:.hidden) ?? false
        }
    }

    enum Formula: String, Codable, CaseIterable {
        case hueRotate, lighter, darker, greyscale
        case lightness, chroma, neutralise, levels, curves, exposure, paletteSpacing, contrastTarget
        case gamutFit, whiteBalance, referenceMatch, ascCDL, applyLUT, spectralRelight, merge
        enum Group: String, CaseIterable {case perceptual="Perceptual", tonal="Tonal", palette="Palette", output="Output & Viewing", cinema="Video & VFX", measured="Measured Colour", branching="Branching"}
        var group:Group {
            switch self {
            case .hueRotate,.lighter,.darker,.greyscale,.lightness,.chroma,.neutralise:return .perceptual
            case .levels,.curves,.exposure:return .tonal
            case .paletteSpacing,.contrastTarget:return .palette
            case .gamutFit,.whiteBalance:return .output
            case .ascCDL,.applyLUT:return .cinema
            case .referenceMatch,.spectralRelight:return .measured
            case .merge:return .branching
            }
        }
        var defaultAmount:Double {
            switch self {case .hueRotate:return 30;case .neutralise:return 100;case .exposure:return 0;default:return 20}
        }
        var usesPrimaryAmount:Bool {
            switch self {case .hueRotate,.lighter,.darker,.lightness,.chroma,.neutralise,.exposure:return true;default:return false}
        }
        var title: String {
            switch self {
            case .hueRotate: return "Hue Rotate +30°"
            case .lighter: return "Lighter 20%"
            case .darker: return "Darker 20%"
            case .greyscale: return "Greyscale"
            case .lightness:return "Lightness"
            case .chroma:return "Chroma"
            case .neutralise:return "Neutralise"
            case .levels:return "Levels"
            case .curves:return "Curves"
            case .exposure:return "Exposure"
            case .paletteSpacing:return "Palette Spacing"
            case .contrastTarget:return "Contrast Target"
            case .gamutFit:return "Gamut Fit"
            case .whiteBalance:return "White Balance"
            case .referenceMatch:return "Reference Match"
            case .ascCDL:return "ASC CDL"
            case .applyLUT:return "Apply LUT / CLF"
            case .spectralRelight:return "Spectral Relight"
            case .merge:return "Merge Branches"
            }
        }
        func title(amount:Double)->String {
            switch self {
            case .hueRotate:return "Hue Rotate +\(Int(amount.rounded()))°"
            case .lighter:return "Lighter \(Int(amount.rounded()))%"
            case .darker:return "Darker \(Int(amount.rounded()))%"
            case .greyscale:return "Greyscale"
            case .merge:return "Merge Branches"
            default:return title
            }
        }
        var range:ClosedRange<Double> {
            switch self {
            case .hueRotate:return 0...360
            case .lighter,.darker:return 0...100
            case .greyscale:return 0...0
            case .lightness,.chroma:return -100...100
            case .neutralise:return 0...100
            case .exposure:return -10...10
            default:return 0...100
            }
        }
        func apply(to colour: ColourDefinition,amount:Double) -> ColourDefinition {
            let fraction=max(0,min(1,amount/100))
            // Keep the original HSL controls in an encoded RGB space that can hold the colour.
            // Colours outside every bounded RGB space use unclipped OKLCH, including HDR lights.
            let space:RGBSpace? = [.srgb,.displayP3,.prophoto].first{colour.master.fits($0)}
            let master:XYZ
            if let space {
                let values=space.values(of:colour.master)
                let hsl=Self.hsl(values)
                let adjusted:(h:Double,s:Double,l:Double)
                switch self {
                case .hueRotate:adjusted=(hsl.h+amount,hsl.s,hsl.l)
                case .lighter:adjusted=(hsl.h,hsl.s,hsl.l+(1-hsl.l)*fraction)
                case .darker:adjusted=(hsl.h,hsl.s,hsl.l*(1-fraction))
                case .greyscale:adjusted=(hsl.h,0,hsl.l)
                default:return colour
                }
                master=space.master(of:Self.rgb(adjusted))
            } else {
                var value=colour.master.oklch
                switch self {
                case .hueRotate:value.h+=amount
                case .lighter:value.l+=max(1-value.l,value.l)*fraction
                case .darker:value.l*=1-fraction
                case .greyscale:value.c=0
                default:return colour
                }
                master=XYZ(oklch:value)
            }
            return ColourDefinition(source:ColourSource(space:"xyz",values:[master.x,master.y,master.z]),master:master,kind:colour.kind)
        }

        private static func hsl(_ rgb:[Double])->(h:Double,s:Double,l:Double) {
            let r=rgb[0],g=rgb[1],b=rgb[2]
            let high=max(r,g,b),low=min(r,g,b),delta=high-low,lightness=(high+low)/2
            let saturation=delta == 0 ? 0 : delta/(1-abs(2*lightness-1))
            guard delta > 0 else{return (0,0,lightness)}
            var hue:Double
            if high == r {hue=((g-b)/delta).truncatingRemainder(dividingBy:6)}
            else if high == g {hue=(b-r)/delta+2}
            else {hue=(r-g)/delta+4}
            hue*=60
            return (hue < 0 ? hue+360:hue,saturation,lightness)
        }

        private static func rgb(_ hsl:(h:Double,s:Double,l:Double))->[Double] {
            let hue=(hsl.h.truncatingRemainder(dividingBy:360)+360).truncatingRemainder(dividingBy:360)
            let chroma=(1-abs(2*hsl.l-1))*hsl.s
            let x=chroma*(1-abs((hue/60).truncatingRemainder(dividingBy:2)-1))
            let offset=hsl.l-chroma/2
            let channels:[Double]
            switch hue {
            case ..<60:channels=[chroma,x,0]
            case ..<120:channels=[x,chroma,0]
            case ..<180:channels=[0,chroma,x]
            case ..<240:channels=[0,x,chroma]
            case ..<300:channels=[x,0,chroma]
            default:channels=[chroma,0,x]
            }
            return channels.map{$0+offset}
        }
    }

    var sourcePaletteID: UUID
    var nodes: [Node]
    var branches: [Branch]
    var root: Node { nodes[0] }

    /// Stable, human-readable diagram labels. IDs remain authoritative in saved files.
    func branchCode(_ id:UUID)->String {
        branches.first(where:{$0.id==id})?.code ?? "?"
    }
    private static func code(for number:Int)->String {
        var value=number,code=""
        repeat {value-=1;code=String(UnicodeScalar(65+value%26)!)+code;value/=26} while value>0
        return code
    }
    private func nextBranchCode()->String {
        let used=Set(branches.map(\.code));var number=1
        while used.contains(Self.code(for:number)) {number+=1}
        return Self.code(for:number)
    }
    func code(for nodeID:UUID)->String {
        if nodeID == root.id {return branches.first.map{branchCode($0.id)} ?? "A"}
        return branches.first(where:{$0.outputID==nodeID}).map{branchCode($0.id)} ?? "?"
    }

    /// A source must have an output and must not depend on the receiving branch.
    func mergeSources(for receiverID:UUID)->[Branch] {
        func depends(_ candidate:UUID,on sought:UUID,seen:inout Set<UUID>)->Bool {
            if candidate == sought {return true}
            guard seen.insert(candidate).inserted,let branch=branches.first(where:{$0.id==candidate}) else{return false}
            var upstream=[UUID]()
            if let source=branch.sourceBranchID {upstream.append(source)}
            if let producer=branches.first(where:{$0.outputID==branch.parentID}) {upstream.append(producer.id)}
            upstream += branch.stages.compactMap(\.mergeSourceBranchID)
            return upstream.contains{depends($0,on:sought,seen:&seen)}
        }
        return branches.filter { branch in
            guard branch.outputID != nil,branch.id != receiverID else{return false}
            var sourceSeen=Set<UUID>(),receiverSeen=Set<UUID>()
            let alreadyConnected=branches.first(where:{$0.id==receiverID})?.stages.contains(where:{$0.mergeSourceBranchID==branch.id}) == true
            return !depends(branch.id,on:receiverID,seen:&sourceSeen)
                && (alreadyConnected || !depends(receiverID,on:branch.id,seen:&receiverSeen))
        }
    }

    /// A rounded display value only. Absorb floating-point matrix noise at exact byte midpoints;
    /// never feed this value back into the graph's colour calculations.
    private static func previewHex(_ definition:ColourDefinition)->String {
        let values=RGBSpace.srgb.values(of:definition.master).map{min(max($0+1e-12,0),1)}
        return RGBSpace.srgb.text(values)
    }

    init(sourcePaletteID: UUID, name: String, keys: [String], definitions: [ColourDefinition]? = nil) {
        self.sourcePaletteID=sourcePaletteID
        let snapshot=definitions?.count == keys.count ? definitions! : keys.compactMap{ColourKeys.definition(of:$0) ?? ColourDefinition.of(hex:$0)}
        nodes=[Node(parentID:nil,name:name,sourceKeys:keys,definitions:snapshot,hexes:snapshot.map(Self.previewHex),formula:nil)]
        branches=[Branch(code:"A",parentID:nodes[0].id)]
    }

    /// Apply a saved diagram to a different palette without carrying its old colour snapshots or Library saves.
    func applied(to paletteID: UUID, name: String, keys: [String], definitions: [ColourDefinition]) -> PaletteTransformGraph {
        var copy = self
        copy.sourcePaletteID = paletteID
        guard !copy.nodes.isEmpty, definitions.count == keys.count else { return PaletteTransformGraph(sourcePaletteID: paletteID, name: name, keys: keys, definitions: definitions) }
        copy.nodes[0].name = name
        copy.nodes[0].sourceKeys = keys
        copy.nodes[0].definitions = definitions
        copy.nodes[0].hexes = definitions.map(Self.previewHex)
        for index in copy.nodes.indices { copy.nodes[index].savedPaletteID = nil }
        for branch in copy.branches.indices {for stage in copy.branches[branch].stages.indices where copy.branches[branch].stages[stage].formula == .spectralRelight {
            copy.branches[branch].stages[stage].settings.references=[]
        }}
        copy.recompute()
        return copy
    }

    /// Portable flow data excludes the source palette's colour records and generated snapshots.
    func template() -> PaletteTransformGraph {
        var copy=self
        copy.sourcePaletteID=UUID()
        for index in copy.nodes.indices {
            copy.nodes[index].sourceKeys=[];copy.nodes[index].definitions=[];copy.nodes[index].hexes=[];copy.nodes[index].savedPaletteID=nil
        }
        for branch in copy.branches.indices {for stage in copy.branches[branch].stages.indices where copy.branches[branch].stages[stage].formula == .spectralRelight {
            copy.branches[branch].stages[stage].settings.references=[]
        }}
        return copy
    }

    /// Upgrade a canvas written before master snapshots existed, using its original colour keys.
    /// Newer canvases retain their snapshots even if the source palette has since changed.
    @discardableResult mutating func restoreLegacySource(using resolve:(String)->ColourDefinition?)->Bool {
        guard !nodes.isEmpty,nodes[0].definitions == nil else{return false}
        let recovered=nodes[0].sourceKeys.compactMap{resolve($0) ?? ColourKeys.definition(of:$0) ?? ColourDefinition.of(hex:$0)}
        guard recovered.count == nodes[0].hexes.count else{return false}
        nodes[0].definitions=recovered
        recompute()
        return true
    }

    private enum CodingKeys: String, CodingKey {case sourcePaletteID,nodes,branches}
    init(from decoder: Decoder) throws {
        let container=try decoder.container(keyedBy:CodingKeys.self)
        sourcePaletteID=try container.decode(UUID.self,forKey:.sourcePaletteID)
        nodes=try container.decode([Node].self,forKey:.nodes)
        branches=try container.decodeIfPresent([Branch].self,forKey:.branches) ?? []
        // Canvases saved before branch slots existed keep every generated palette.
        for node in nodes {
            if !branches.contains(where:{$0.parentID==node.id}) {
                let children=nodes.filter{$0.parentID==node.id}
                branches += children.isEmpty
                    ? [Branch(parentID:node.id)]
                    : children.map{Branch(id:$0.id,parentID:node.id,outputID:$0.id,stages:[Stage(formula:$0.formula)])}
            }
        }
        for index in branches.indices where branches[index].stages.isEmpty {
            let formula=branches[index].outputID.flatMap{id in nodes.first{$0.id==id}?.formula}
            branches[index].stages=[Stage(formula:formula)]
        }
        var used=Set(branches.map(\.code).filter{!$0.isEmpty})
        for index in branches.indices where branches[index].code.isEmpty {
            var number=1
            while used.contains(Self.code(for:number)) {number+=1}
            branches[index].code=Self.code(for:number);used.insert(branches[index].code)
        }
    }
    func encode(to encoder: Encoder) throws {
        var container=encoder.container(keyedBy:CodingKeys.self)
        try container.encode(sourcePaletteID,forKey:.sourcePaletteID)
        try container.encode(nodes,forKey:.nodes)
        try container.encode(branches,forKey:.branches)
    }

    /// One repeatable unit contains a branch control and a transform cell.
    func firstUnit(of branchID:UUID)->Int {
        guard let branch=branches.first(where:{$0.id==branchID}),
              let sourceID=branch.sourceBranchID,
              let source=branches.first(where:{$0.id==sourceID}),
              let stageID=branch.sourceStageID,
              let stage=source.stages.firstIndex(where:{$0.id==stageID}) else{return 0}
        return firstUnit(of:sourceID)+stage+1
    }

    @discardableResult mutating func addBranch(after parentID:UUID,from branchID:UUID?=nil,stageID:UUID?=nil,passThrough:Bool=false)->UUID? {
        guard nodes.contains(where:{$0.id==parentID}) else{return nil}
        if let branchID, !branches.contains(where:{$0.id==branchID}) {return nil}
        let branch=Branch(code:nextBranchCode(),parentID:parentID,sourceBranchID:branchID,sourceStageID:stageID)
        branches.append(branch)
        if passThrough {makeOutput(for:branch.id)}
        recompute(from:branch.id)
        return branch.id
    }

    @discardableResult mutating func insertTransform(after stageID:UUID,in branchID:UUID)->UUID? {
        guard let index=branches.firstIndex(where:{$0.id==branchID}),
              let stage=branches[index].stages.firstIndex(where:{$0.id==stageID}) else{return nil}
        let inserted=Stage()
        branches[index].stages.insert(inserted,at:stage+1)
        return inserted.id
    }

    @discardableResult mutating func transform(_ formula:Formula,in branchID:UUID,stageID:UUID?=nil)->UUID? {
        guard let index=branches.firstIndex(where:{$0.id==branchID}),!branches[index].stages.isEmpty else{return nil}
        let selected=stageID.flatMap{id in branches[index].stages.firstIndex{$0.id==id}} ?? 0
        if branches[index].stages[selected].formula != formula {
            branches[index].stages[selected].amount=formula.defaultAmount
        }
        if formula == .merge {
            guard let source=mergeSources(for:branchID).last else{return nil}
            branches[index].stages[selected].mergeSourceBranchID=source.id
        } else {branches[index].stages[selected].mergeSourceBranchID=nil}
        branches[index].stages[selected].formula=formula
        makeOutput(for:branchID)
        recompute(from:branchID)
        return branches[index].outputID
    }

    mutating func setAmount(_ amount:Double,in branchID:UUID,stageID:UUID,previewOnly:Bool=false) {
        guard let index=branches.firstIndex(where:{$0.id==branchID}),
              let stage=branches[index].stages.firstIndex(where:{$0.id==stageID}),
              let formula=branches[index].stages[stage].formula,formula != .greyscale else{return}
        let step:Double=formula == .exposure ? 10:1
        branches[index].stages[stage].amount=min(formula.range.upperBound,max(formula.range.lowerBound,(amount*step).rounded()/step))
        recompute(from:branchID,includeDescendants:!previewOnly || branches[index].stages[stage].previewDownstream)
    }

    mutating func configure(_ stageID: UUID, amount: Double? = nil, settings: TransformSettings, mergeSourceBranchID:UUID?=nil) {
        guard let branchIndex=branches.firstIndex(where:{$0.stages.contains(where:{$0.id==stageID})}),
              let stageIndex=branches[branchIndex].stages.firstIndex(where:{$0.id==stageID}) else{return}
        if let amount { branches[branchIndex].stages[stageIndex].amount=amount }
        branches[branchIndex].stages[stageIndex].settings=settings
        if branches[branchIndex].stages[stageIndex].formula == .merge {
            let receiver=branches[branchIndex].id
            branches[branchIndex].stages[stageIndex].mergeSourceBranchID=mergeSources(for:receiver).contains(where:{$0.id==mergeSourceBranchID}) ? mergeSourceBranchID:nil
        }
        recompute(from:branches[branchIndex].id)
    }

    mutating func commitPreview(in branchID:UUID) {recompute(from:branchID)}

    mutating func setPreviewDownstream(_ enabled:Bool,in branchID:UUID,stageID:UUID) {
        guard let index=branches.firstIndex(where:{$0.id==branchID}),
              let stage=branches[index].stages.firstIndex(where:{$0.id==stageID}) else{return}
        branches[index].stages[stage].previewDownstream=enabled
    }

    mutating func setBypassed(_ enabled:Bool,stageID:UUID) {
        guard let index=branches.firstIndex(where:{$0.stages.contains(where:{$0.id==stageID})}),
              let stage=branches[index].stages.firstIndex(where:{$0.id==stageID}) else{return}
        branches[index].stages[stage].bypassed=enabled
        recompute(from:branches[index].id)
    }

    mutating func setTransformHidden(_ enabled:Bool,stageID:UUID) {
        guard let index=branches.firstIndex(where:{$0.stages.contains(where:{$0.id==stageID})}),
              let stage=branches[index].stages.firstIndex(where:{$0.id==stageID}) else{return}
        branches[index].stages[stage].hidden=enabled
        recompute(from:branches[index].id)
    }

    mutating func setPaletteHidden(_ enabled:Bool,paletteID:UUID) {
        guard let index=nodes.firstIndex(where:{$0.id==paletteID}) else{return}
        nodes[index].hidden=enabled
    }

    mutating func hideBranch(_ branchID:UUID) {
        guard let index=branches.firstIndex(where:{$0.id==branchID}) else{return}
        let children=Set(branches.filter{$0.sourceBranchID==branchID}.map(\.id))
        let output=branches[index].outputID
        branches[index].outputID=nil
        branches[index].hidden=true
        prune(branches:children,nodes:Set(output.map{[$0]} ?? []))
    }

    mutating func showBranch(_ branchID:UUID) {
        guard let index=branches.firstIndex(where:{$0.id==branchID}) else{return}
        branches[index].hidden=false
        if branches[index].stages.contains(where:{$0.formula != nil && !$0.hidden}) {makeOutput(for:branchID)}
        recompute(from:branchID)
    }

    private mutating func makeOutput(for branchID:UUID) {
        guard let index=branches.firstIndex(where:{$0.id==branchID}),!branches[index].hidden,branches[index].outputID==nil,
              let parent=nodes.first(where:{$0.id==branches[index].parentID}) else{return}
        let child=Node(parentID:parent.id,name:parent.name,sourceKeys:parent.hexes,definitions:parent.definitions,hexes:parent.hexes,formula:nil)
        nodes.append(child);branches[index].outputID=child.id
        branches.append(Branch(code:nextBranchCode(),parentID:child.id))
    }

    mutating func removeBranch(_ branchID:UUID) {
        guard branches.contains(where:{$0.id==branchID}) else{return}
        prune(branches:[branchID],nodes:[])
        ensurePaletteControls()
    }

    mutating func removeTransform(_ stageID:UUID) {
        guard let index=branches.firstIndex(where:{$0.stages.contains(where:{$0.id==stageID})}),
              let position=branches[index].stages.firstIndex(where:{$0.id==stageID}) else{return}
        if position==0 {removeBranch(branches[index].id);return}
        let removed=Set(branches[index].stages[position...].map(\.id))
        let output=branches[index].outputID
        let children=Set(branches.filter{$0.sourceBranchID==branches[index].id && $0.sourceStageID.map(removed.contains)==true}.map(\.id))
        branches[index].stages=Array(branches[index].stages[..<position])
        branches[index].outputID=nil
        prune(branches:children,nodes:Set(output.map{[$0]} ?? []))
        ensurePaletteControls()
    }

    mutating func removePalette(_ paletteID:UUID) {
        guard paletteID != root.id,let producer=branches.firstIndex(where:{$0.outputID==paletteID}) else{return}
        branches[producer].outputID=nil
        prune(branches:[],nodes:[paletteID])
        ensurePaletteControls()
    }

    private mutating func prune(branches initialBranches:Set<UUID>,nodes initialNodes:Set<UUID>) {
        var removedBranches=initialBranches,removedNodes=initialNodes
        var changed=true
        while changed {
            changed=false
            for branch in branches where removedBranches.contains(branch.id) || removedNodes.contains(branch.parentID) || branch.sourceBranchID.map(removedBranches.contains)==true {
                if removedBranches.insert(branch.id).inserted {changed=true}
                if let output=branch.outputID,removedNodes.insert(output).inserted {changed=true}
            }
        }
        branches.removeAll{removedBranches.contains($0.id)}
        nodes.removeAll{removedNodes.contains($0.id)}
        for branchIndex in branches.indices {for stageIndex in branches[branchIndex].stages.indices {
            if let source=branches[branchIndex].stages[stageIndex].mergeSourceBranchID,
               (removedBranches.contains(source) || branches.first(where:{$0.id==source})?.outputID == nil) {
                branches[branchIndex].stages[stageIndex].mergeSourceBranchID=nil
            }
        }}
        recompute()
    }

    private mutating func ensurePaletteControls() {
        for node in nodes where !branches.contains(where:{$0.parentID==node.id && $0.sourceBranchID==nil}) {
            branches.append(Branch(code:nextBranchCode(),parentID:node.id))
        }
    }

    /// The exact colours entering a stage, including any earlier transforms on its path.
    func inputDefinitions(for stageID:UUID)->[ColourDefinition]? {
        var visiting=Set<UUID>()
        func evaluate(_ branchID:UUID,until target:UUID,includeTarget:Bool)->[ColourDefinition]? {
            guard visiting.insert(branchID).inserted,let branch=branches.first(where:{$0.id==branchID}) else{return nil}
            defer{visiting.remove(branchID)}
            let input:[ColourDefinition]
            if let source=branch.sourceBranchID,let sourceStage=branch.sourceStageID {
                guard let colours=evaluate(source,until:sourceStage,includeTarget:true) else{return nil}
                input=colours
            } else {
                guard let node=nodes.first(where:{$0.id==branch.parentID}) else{return nil}
                input=node.definitions ?? node.hexes.compactMap{ColourDefinition.of(hex:$0)}
            }
            var colours=input
            for stage in branch.stages {
                if stage.id == target && !includeTarget {return colours}
                if let formula=stage.formula,!stage.bypassed,!stage.hidden {
                    if formula == .merge,let source=stage.mergeSourceBranchID,
                       let other=branches.first(where:{$0.id==source}),let last=other.stages.last,
                       let mergeInput=evaluate(source,until:last.id,includeTarget:true) {
                        colours=PaletteTransformEngine.merge(colours,with:mergeInput,settings:stage.settings)
                    } else {colours=PaletteTransformEngine.apply(formula,to:colours,stage:stage)}
                }
                if stage.id == target {return colours}
            }
            return nil
        }
        guard let branch=branches.first(where:{$0.stages.contains(where:{$0.id==stageID})}) else{return nil}
        return evaluate(branch.id,until:stageID,includeTarget:false)
    }

    struct HistoryEntry {
        var id:UUID
        var code:String
        var title:String
        var settings:[String]
        var colours:[ColourDefinition]
        var isPalette:Bool
        var inputColours:[ColourDefinition]?=nil
    }

    /// Walk the actual producer path, including side inputs to Merge, for RailInfo.
    func history(for paletteID:UUID)->[HistoryEntry] {
        guard let root=nodes.first else{return []}
        let rootColours=root.definitions ?? root.hexes.compactMap{ColourDefinition.of(hex:$0)}
        let rootEntry=HistoryEntry(id:root.id,code:code(for:root.id),title:"Source · \(root.name)",settings:[],colours:rootColours,isPalette:true)
        var visiting=Set<UUID>()
        func stageSettings(_ stage:Stage)->[String] {
            var parts=[String]()
            var shown=Set<String>()
            func number(_ key:String,_ label:String,_ fallback:Double) {
                shown.insert(key)
                parts.append("\(label) \(String(format:"%.3f",stage.settings.number(key,fallback)))")
            }
            func choice(_ key:String,_ label:String,_ fallback:String) {
                shown.insert(key)
                parts.append("\(label) \(stage.settings.choice(key,fallback))")
            }
            if stage.formula?.usesPrimaryAmount == true {parts.append(String(format:"Amount %.3f",stage.amount))}
            switch stage.formula {
            case .levels,.curves:
                choice("channel","Channel","Luminance");choice("space","RGB Space","linearSRGB")
                number("black","Input Black",0);number("white","Input White",1)
                if stage.formula == .levels {number("gamma","Midpoint Gamma",1);number("outputWhite","Output White",1)}
                else {parts.append("\(stage.settings.curve.count) curve points")}
            case .paletteSpacing:
                number("low","Low Lightness",0);number("high","High Lightness",1);number("strength","Strength",1)
            case .contrastTarget:
                number("foreground","Foreground",0);number("background","Background",1);number("ratio","Target Ratio",4.5)
            case .gamutFit:
                choice("target","Destination","srgb");choice("intent","Rendering Intent","relative")
                if stage.settings.choice("target","srgb") == "print" {choice("press","Print Condition",PressProfiles.generic)}
            case .whiteBalance:
                choice("sourceWhite","Source White","D50");choice("targetWhite","Target White","D65")
            case .referenceMatch:number("strength","Strength",1)
            case .ascCDL:
                choice("space","Working RGB","srgb");choice("style","CDL Style","Fwd")
                for channel in 0..<3 {
                    let label=["Red","Green","Blue"][channel]
                    number("slope\(channel)","\(label) Slope",1)
                    number("offset\(channel)","\(label) Offset",0)
                    number("power\(channel)","\(label) Power",1)
                }
                number("saturation","Saturation",1)
            case .applyLUT:choice("space","Input / Output RGB","srgb")
            case .spectralRelight:choice("illuminant","Illuminant","D50")
            case .merge:
                parts.append("Source Branch \(stage.mergeSourceBranchID.map{branchCode($0)} ?? "None")")
                choice("blend","Blend","mix");number("opacity","Strength",0.5)
            default:break
            }
            for key in stage.settings.numbers.keys.sorted() where !shown.contains(key) {parts.append("\(key) \(String(format:"%.3f",stage.settings.numbers[key] ?? 0))")}
            for key in stage.settings.choices.keys.sorted() where !shown.contains(key) {parts.append("\(key) \(stage.settings.choices[key] ?? "")")}
            if !stage.settings.lockedIndices.isEmpty {parts.append("Fixed colours \(stage.settings.lockedIndices.map{$0+1}.map(String.init).joined(separator:", "))")}
            if let source=stage.settings.sourceName {parts.append(source)}
            if !stage.settings.references.isEmpty {parts.append("\(stage.settings.references.count) reference colours")}
            if !stage.previewDownstream {parts.append("Downstream preview paused")}
            if stage.bypassed {parts.append("Bypassed")}
            if stage.hidden {parts.append("Hidden")}
            return parts
        }
        func branchPath(_ branch:Branch,through stop:UUID?=nil)->[HistoryEntry] {
            guard visiting.insert(branch.id).inserted else{return []}
            defer{visiting.remove(branch.id)}
            var entries:[HistoryEntry]
            if let sourceID=branch.sourceBranchID,let sourceStage=branch.sourceStageID,
               let source=branches.first(where:{$0.id==sourceID}) {
                entries=branchPath(source,through:sourceStage)
            } else {entries=nodePath(branch.parentID)}
            var colours=entries.last?.colours ?? rootColours
            for stage in branch.stages {
                if let formula=stage.formula {
                    let before=colours
                    if !stage.bypassed && !stage.hidden {
                        if formula == .merge,let sourceID=stage.mergeSourceBranchID,
                           let source=branches.first(where:{$0.id==sourceID}),let output=source.outputID {
                            let sourcePath=nodePath(output)
                            let seen=Set(entries.map(\.id))
                            entries += sourcePath.filter{!seen.contains($0.id)}.map { entry in
                                var copy=entry;copy.title="Merge Input · "+entry.title;return copy
                            }
                            if let incoming=sourcePath.last?.colours {colours=PaletteTransformEngine.merge(colours,with:incoming,settings:stage.settings)}
                        } else {colours=PaletteTransformEngine.apply(formula,to:colours,stage:stage)}
                    }
                    entries.append(HistoryEntry(id:stage.id,code:branch.code,title:stage.title,settings:stageSettings(stage),colours:colours,isPalette:false,inputColours:before))
                }
                if stage.id == stop {break}
            }
            return entries
        }
        func nodePath(_ id:UUID)->[HistoryEntry] {
            guard id != root.id,let node=nodes.first(where:{$0.id==id}),
                  let producer=branches.first(where:{$0.outputID==id}) else{return [rootEntry]}
            var entries=branchPath(producer)
            let colours=node.definitions ?? node.hexes.compactMap{ColourDefinition.of(hex:$0)}
            entries.append(HistoryEntry(id:node.id,code:producer.code,title:"Palette · \(node.name)",settings:[],colours:colours,isPalette:true))
            return entries
        }
        return nodePath(paletteID)
    }

    /// Recalculate one changed path and its dependants. During a preview with downstream
    /// disabled, the first output still follows the controller while later cards hold still.
    private mutating func recompute(from changedBranchID:UUID?=nil,includeDescendants:Bool=true) {
        let allBranches=branches
        let branchIndex=Dictionary(uniqueKeysWithValues:allBranches.enumerated().map{($0.element.id,$0.offset)})
        let nodeIndex=Dictionary(uniqueKeysWithValues:nodes.enumerated().map{($0.element.id,$0.offset)})
        let producers=Dictionary(uniqueKeysWithValues:allBranches.compactMap{branch -> (UUID,UUID)? in
            branch.outputID.map{($0,branch.id)}
        })
        var dependants:[UUID:[UUID]]=[:]
        var siblingCounts:[UUID:Int]=[:],siblingOrdinal:[UUID:Int]=[:]
        for branch in allBranches {
            siblingCounts[branch.parentID,default:0]+=1
            siblingOrdinal[branch.id]=siblingCounts[branch.parentID]
            if let source=branch.sourceBranchID {dependants[source,default:[]].append(branch.id)}
            if let producer=producers[branch.parentID] {dependants[producer,default:[]].append(branch.id)}
            for source in branch.stages.compactMap(\.mergeSourceBranchID) {dependants[source,default:[]].append(branch.id)}
        }
        var affected=Set(changedBranchID.map{[$0]} ?? allBranches.map(\.id))
        if includeDescendants,var queue=changedBranchID.map{[$0]} {
            var cursor=0
            while cursor<queue.count {
                let current=queue[cursor];cursor+=1
                for dependant in dependants[current] ?? [] {
                    if affected.insert(dependant).inserted {queue.append(dependant)}
                }
            }
        }
        var updated=nodes
        var snapshots:[UUID:[UUID:[ColourDefinition]]]=[:]
        var visiting:Set<UUID>=[]
        func evaluate(_ id:UUID)->[UUID:[ColourDefinition]]? {
            if let value=snapshots[id] {return value}
            guard let position=branchIndex[id],visiting.insert(id).inserted else{return nil}
            let branch=allBranches[position]
            let input:[ColourDefinition]
            if let sourceID=branch.sourceBranchID,let stageID=branch.sourceStageID {
                guard let colours=evaluate(sourceID)?[stageID] else{visiting.remove(id);return nil}
                input=colours
            } else {
                if let producer=producers[branch.parentID],affected.contains(producer) {_ = evaluate(producer)}
                guard let parent=nodeIndex[branch.parentID] else{visiting.remove(id);return nil}
                input=updated[parent].definitions ?? updated[parent].hexes.compactMap{ColourDefinition.of(hex:$0)}
            }
            var colours=input,values:[UUID:[ColourDefinition]]=[:]
            for stage in branch.stages {
                if let formula=stage.formula,!stage.bypassed,!stage.hidden {
                    if formula == .merge,let source=stage.mergeSourceBranchID,
                       let sourceBranch=allBranches.first(where:{$0.id==source}),
                       let sourceOutput=sourceBranch.outputID,let sourceIndex=nodeIndex[sourceOutput] {
                        _ = evaluate(source)
                        let other=updated[sourceIndex].definitions ?? updated[sourceIndex].hexes.compactMap{ColourDefinition.of(hex:$0)}
                        colours=PaletteTransformEngine.merge(colours,with:other,settings:stage.settings)
                    } else {colours=PaletteTransformEngine.apply(formula,to:colours,stage:stage)}
                }
                values[stage.id]=colours
            }
            snapshots[id]=values
            if affected.contains(id),let outputID=branch.outputID,let index=nodeIndex[outputID] {
                let sibling=siblingOrdinal[id] ?? 1
                let suffix=sibling==1 ? "":" \(sibling)"
                let title=branch.stages.last(where:{$0.formula != nil})?.title ?? "Pass Through"
                let parentName=nodeIndex[branch.parentID].map{updated[$0].name} ?? updated[0].name
                let derived=colours.map{ colour -> ColourDefinition in
                    let master=colour.master
                    return ColourDefinition(source:ColourSource(space:"xyz",values:[master.x,master.y,master.z]),master:master,kind:colour.kind)
                }
                if updated[index].definitions != derived {updated[index].savedPaletteID=nil}
                updated[index].name="\(parentName) · \(title)\(suffix)"
                updated[index].sourceKeys=input.map(Self.previewHex)
                updated[index].definitions=derived
                updated[index].hexes=derived.map(Self.previewHex)
                updated[index].formula=branch.stages.compactMap(\.formula).last
            }
            visiting.remove(id)
            return values
        }
        for id in affected {_ = evaluate(id)}
        nodes=updated
    }

    @discardableResult mutating func append(_ formula:Formula,after parentID:UUID)->UUID? {
        let slot=branches.first(where:{$0.parentID==parentID && $0.outputID==nil && $0.sourceBranchID==nil})?.id ?? addBranch(after:parentID)
        return slot.flatMap{transform(formula,in:$0)}
    }
}

enum PaletteTransformStore {
    static func graph(for paletteID: UUID, in store: LibraryStore) -> PaletteTransformGraph? {
        CatalogueTree.catalogue(in:store.root)?.paletteTransformGraphs?.first{$0.sourcePaletteID==paletteID}
    }
    static func save(_ graph: PaletteTransformGraph, in store: LibraryStore) throws {
        try Handler_File_Manager.shared.withTransaction(home:store.root) {
            try Handler_File_Manager.shared.update(store.url) { object in
                let data=try object["paletteTransformGraphs"].map{try JSONSerialization.data(withJSONObject:$0)}
                var graphs=try data.map{try ColourFiles.decoder().decode([PaletteTransformGraph].self,from:$0)} ?? []
                if let index=graphs.firstIndex(where:{$0.sourcePaletteID==graph.sourcePaletteID}) { graphs[index]=graph }
                else { graphs.append(graph) }
                object["paletteTransformGraphs"]=try JSONSerialization.jsonObject(with:ColourFiles.encoder().encode(graphs))
            }
        }
    }
    static func remove(for paletteID:UUID,in store:LibraryStore) throws {
        try Handler_File_Manager.shared.withTransaction(home:store.root) {
            try Handler_File_Manager.shared.update(store.url) { object in
                guard let value=object["paletteTransformGraphs"] else{return}
                let data=try JSONSerialization.data(withJSONObject:value)
                var graphs=try ColourFiles.decoder().decode([PaletteTransformGraph].self,from:data)
                graphs.removeAll{$0.sourcePaletteID==paletteID}
                object["paletteTransformGraphs"]=try JSONSerialization.jsonObject(with:ColourFiles.encoder().encode(graphs))
            }
        }
    }
}
