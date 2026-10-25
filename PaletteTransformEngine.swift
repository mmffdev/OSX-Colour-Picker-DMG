import Foundation

/// Versioned, portable settings for one transform. No display hex or rounded channel value is an input.
struct TransformSettings: Codable, Equatable {
    var algorithmVersion = 1
    var workingSpace = "oklch"
    var gamutRule = "preserve"
    var numbers: [String: Double] = [:]
    var choices: [String: String] = [:]
    var curve: [TransformPoint] = []
    var references: [XYZ] = []
    var lockedIndices: [Int] = []
    var sourceName: String? = nil
    var sourceDigest: String? = nil
    var sourceData: Data? = nil
    func number(_ key: String, _ fallback: Double) -> Double { numbers[key] ?? fallback }
    func choice(_ key: String, _ fallback: String) -> String { choices[key] ?? fallback }
}

struct TransformPoint: Codable, Equatable {
    var x: Double
    var y: Double
}

enum PaletteTransformEngine {
    typealias Formula = PaletteTransformGraph.Formula
    typealias Stage = PaletteTransformGraph.Stage

    static func availability(_ stage: Stage, colourCount: Int) -> String? {
        guard let formula = stage.formula else { return "Choose a transform" }
        switch formula {
        case .referenceMatch where stage.settings.references.count != colourCount:
            return "Choose a reference palette with \(colourCount) colours"
        case .contrastTarget where colourCount < 2:
            return "Contrast Target needs at least two colours"
        case .applyLUT where stage.settings.sourceData == nil:
            return "Choose a .cube or .clf transform"
        case .applyLUT where (try? PaletteLUT.read(stage.settings.sourceData ?? Data(), name: stage.settings.sourceName ?? "")) == nil:
            return "The transform file cannot be read"
        case .spectralRelight where stage.settings.references.count != colourCount:
            return "Link measured spectra to every colour"
        case .gamutFit where stage.settings.choice("target", "srgb") == "print" && PressProfiles.space(named:stage.settings.choice("press", PressProfiles.generic)) == nil:
            return "Choose an installed print condition"
        case .merge where stage.mergeSourceBranchID == nil:
            return "Choose another branch to merge"
        default:return nil
        }
    }

    static func apply(_ formula: Formula, to colours: [ColourDefinition], stage: Stage) -> [ColourDefinition] {
        guard availability(stage, colourCount: colours.count) == nil else { return colours }
        let settings = stage.settings
        switch formula {
        case .merge:
            // The graph supplies the second branch; a standalone preset cannot.
            return colours
        case .hueRotate:
            return colours.map { colour in
                var value=colour.master.oklch
                value.h=(value.h+stage.amount).truncatingRemainder(dividingBy:360)
                return replaced(colour,with:XYZ(oklch:value))
            }
        case .lighter, .darker, .greyscale:
            return colours.map { formula.apply(to: $0, amount: stage.amount) }
        case .lightness:
            return colours.map { colour in
                var v = colour.master.oklch
                let change = stage.amount / 100
                v.l = change >= 0 ? v.l + (1 - v.l) * change : v.l * (1 + change)
                return replaced(colour, with: XYZ(oklch: v))
            }
        case .chroma:
            return colours.map { colour in
                var v = colour.master.oklch
                v.c = max(0, v.c * (1 + stage.amount / 100))
                return replaced(colour, with: XYZ(oklch: v))
            }
        case .neutralise:
            return colours.map { colour in
                var v = colour.master.oklch
                v.c *= 1 - min(100, max(0, stage.amount)) / 100
                return replaced(colour, with: XYZ(oklch: v))
            }
        case .exposure:
            let multiplier = pow(2, min(10, max(-10, stage.amount)))
            return colours.map { c in replaced(c, with: XYZ(x: c.master.x * multiplier, y: c.master.y * multiplier, z: c.master.z * multiplier)) }
        case .levels, .curves:
            let black = settings.number("black", 0), white = max(black + 0.001, settings.number("white", 1))
            let gamma = max(0.01, settings.number("gamma", 1))
            let points = formula == .curves ? preparedCurve(settings.curve) : []
            func map(_ input:Double)->Double {
                let normalized=min(1,max(0,(input-black)/(white-black)))
                let mapped=formula == .curves ? curveValue(normalized,points):pow(normalized,1/gamma)
                return mapped*settings.number("outputWhite",1)
            }
            let channel=settings.choice("channel","Luminance")
            if channel != "Luminance" {
                let space=RGBSpace(rawValue:settings.choice("space","linearSRGB")) ?? .linearSRGB
                return colours.map { c in
                    var values=space.linearValues(of:c.master)
                    for index in 0..<3 where channel == "RGB" || channel == ["Red","Green","Blue"][index] { values[index]=map(values[index]) }
                    return replaced(c,with:space.master(of:values.map(space.encoded)))
                }
            }
            return colours.map { c in
                let y=c.master.y,output=map(y),ratio=y == 0 ? 0:output/y
                return replaced(c,with:XYZ(x:c.master.x*ratio,y:output,z:c.master.z*ratio))
            }
        case .paletteSpacing:
            guard colours.count > 1 else { return colours }
            let sorted = colours.indices.sorted { colours[$0].master.oklch.l < colours[$1].master.oklch.l }
            let low = settings.number("low", colours[sorted[0]].master.oklch.l)
            let high = settings.number("high", colours[sorted.last!].master.oklch.l)
            let strength = min(1, max(0, settings.number("strength", 1)))
            var result = colours
            for (rank, index) in sorted.enumerated() where !settings.lockedIndices.contains(index) {
                var v = colours[index].master.oklch
                let target = low + (high - low) * Double(rank) / Double(colours.count - 1)
                v.l += (target - v.l) * strength
                result[index] = replaced(colours[index], with: XYZ(oklch: v))
            }
            return result
        case .contrastTarget:
            let foreground = min(colours.count - 1, max(0, Int(settings.number("foreground", 0))))
            let background = min(colours.count - 1, max(0, Int(settings.number("background", 1))))
            guard foreground != background else { return colours }
            let target = max(1, min(21, settings.number("ratio", 4.5)))
            let otherY = max(0, colours[background].master.adapted(to: Illuminant.allCases.first { $0.name == "D65" && $0.observer == 2 }!).y)
            let original = colours[foreground].master.oklch
            func ratio(_ v: OKLCH) -> Double {
                let y = max(0, XYZ(oklch: v).adapted(to: Illuminant.allCases.first { $0.name == "D65" && $0.observer == 2 }!).y)
                return (max(y, otherY) + 0.05) / (min(y, otherY) + 0.05)
            }
            var candidate = original
            let darken = colours[foreground].master.y < colours[background].master.y
            var lo = darken ? 0.0 : original.l, hi = darken ? original.l : 1.0
            for _ in 0..<32 {
                let mid = (lo + hi) / 2
                candidate.l = mid
                if (ratio(candidate) >= target) == darken { lo = mid } else { hi = mid }
            }
            candidate.l = darken ? lo : hi
            var result = colours
            if ratio(candidate) >= target { result[foreground] = replaced(colours[foreground], with: XYZ(oklch: candidate)) }
            return result
        case .gamutFit:
            let target = settings.choice("target", "srgb")
            if target == "print" {
                let press=settings.choice("press",PressProfiles.generic)
                let intent=RenderingIntent(rawValue:settings.choice("intent","relative")) ?? .relative
                return colours.map { c in
                    guard let build = PrintBuild.of(c.master, press: press, intent: intent) else { return c }
                    return replaced(c, with: build.printed)
                }
            }
            guard let space = RGBSpace(rawValue: target) else { return colours }
            return colours.map { c in
                if c.master.fits(space) { return c }
                var value = c.master.oklch
                var lo = 0.0, hi = value.c
                for _ in 0..<28 {
                    let mid = (lo + hi) / 2
                    value.c = mid
                    if XYZ(oklch: value).fits(space) { lo = mid } else { hi = mid }
                }
                value.c = lo
                return replaced(c, with: XYZ(oklch: value))
            }
        case .whiteBalance:
            let source = settings.choice("sourceWhite", "D50"), destination = settings.choice("targetWhite", "D65")
            guard let a = Illuminant.allCases.first(where: { $0.name == source && $0.observer == 2 }),
                  let b = Illuminant.allCases.first(where: { $0.name == destination && $0.observer == 2 }) else { return colours }
            let matrix = bradford(from: a.white.chromaticity, to: b.white.chromaticity)
            return colours.map { c in
                let v = multiply(matrix, [c.master.x, c.master.y, c.master.z])
                return replaced(c, with: XYZ(x: v[0], y: v[1], z: v[2]))
            }
        case .referenceMatch:
            let strength = min(1, max(0, settings.number("strength", 1)))
            return zip(colours, settings.references).map { c, reference in
                replaced(c, with: XYZ(x: c.master.x + (reference.x - c.master.x) * strength,
                                      y: c.master.y + (reference.y - c.master.y) * strength,
                                      z: c.master.z + (reference.z - c.master.z) * strength))
            }
        case .ascCDL:
            let space = RGBSpace(rawValue: settings.choice("space", "srgb")) ?? .srgb
            let noClamp=settings.choice("style","Fwd") == "FwdNoClamp"
            let weights=(0..<3).map { channel -> Double in
                var basis=[0.0,0,0];basis[channel]=1
                return space.master(of:basis).y
            }
            let weightTotal=max(1e-12,weights.reduce(0,+))
            return colours.map { c in
                let rgb = space.values(of: c.master)
                let sop = (0..<3).map { channel -> Double in
                    let slope = settings.number("slope\(channel)", 1)
                    let offset = settings.number("offset\(channel)", 0)
                    let power = max(0.001, settings.number("power\(channel)", 1))
                    let base=rgb[channel]*slope+offset
                    let bounded=noClamp ? base:min(1,max(0,base))
                    return bounded < 0 ? -pow(-bounded,power):pow(bounded,power)
                }
                let luminance = zip(weights,sop).reduce(0){$0+$1.0*$1.1}/weightTotal
                let saturation = max(0, settings.number("saturation", 1))
                let output=sop.map { luminance + ($0 - luminance) * saturation }
                return replaced(c, with: space.master(of: noClamp ? output:output.map{min(1,max(0,$0))}))
            }
        case .applyLUT:
            guard let data = settings.sourceData,
                  let table = try? PaletteLUT.read(data, name: settings.sourceName ?? "") else { return colours }
            let space = RGBSpace(rawValue: settings.choice("space", "srgb")) ?? .srgb
            return colours.map { replaced($0, with: space.master(of: table.sample(space.values(of: $0.master)))) }
        case .spectralRelight:
            // The references are XYZ predictions from linked measured reflectances under the chosen illuminant.
            return zip(colours, settings.references).map { replaced($0.0, with: $0.1) }
        }
    }

    /// Blend two matching palettes in linear-light RGB, retaining floating-point values.
    /// Subtractive is a CMY-style channel approximation, not spectral paint mixing.
    static func merge(_ base:[ColourDefinition],with source:[ColourDefinition],settings:TransformSettings)->[ColourDefinition] {
        guard base.count == source.count else{return base}
        let amount=min(1,max(0,settings.number("opacity",0.5)))
        let mode=settings.choice("blend","mix")
        return zip(base,source).map { first,second in
            let a=RGBSpace.linearSRGB.linearValues(of:first.master)
            let b=RGBSpace.linearSRGB.linearValues(of:second.master)
            let result=zip(a,b).map { x,y -> Double in
                let blended:Double
                switch mode {
                case "add":blended=x+y
                case "subtract":blended=max(0,x)*max(0,y)
                case "screen":blended=1-(1-x)*(1-y)
                case "difference":blended=abs(x-y)
                default:blended=y
                }
                return x+(blended-x)*amount
            }
            let master=RGBSpace.linearSRGB.master(of:result)
            return ColourDefinition(source:ColourSource(space:"xyz",values:[master.x,master.y,master.z]),master:master,kind:first.kind)
        }
    }

    private static func replaced(_ colour: ColourDefinition, with master: XYZ) -> ColourDefinition {
        ColourDefinition(source: ColourSource(space: "xyz", values: [master.x, master.y, master.z]), master: master, kind: colour.kind)
    }
    private static func preparedCurve(_ points: [TransformPoint]) -> [TransformPoint] {
        let entries = points.filter { $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }.sorted { $0.x < $1.x }
        return [TransformPoint(x: 0, y: 0)] + entries + [TransformPoint(x: 1, y: 1)]
    }
    static func curveValue(_ x: Double, _ points: [TransformPoint]) -> Double {
        guard points.count > 1 else { return x }
        let ordered=points.sorted{$0.x<$1.x}
        let deltas=zip(ordered,ordered.dropFirst()).map{pair in (pair.1.y-pair.0.y)/max(1e-9,pair.1.x-pair.0.x)}
        var slopes=[Double](repeating:0,count:ordered.count)
        slopes[0]=deltas[0];slopes[ordered.count-1]=deltas.last ?? 0
        if ordered.count > 2 {
            for i in 1..<(ordered.count-1) {
                let a=deltas[i-1],b=deltas[i]
                if a*b > 0 {
                    let h0=ordered[i].x-ordered[i-1].x,h1=ordered[i+1].x-ordered[i].x
                    let w0=2*h1+h0,w1=h1+2*h0
                    slopes[i]=(w0+w1)/(w0/a+w1/b)
                }
            }
        }
        for i in 0..<(ordered.count-1) where x <= ordered[i+1].x {
            let a=ordered[i],b=ordered[i+1],span=b.x-a.x
            guard span > 1e-9 else{return b.y}
            let t=min(1,max(0,(x-a.x)/span)),t2=t*t,t3=t2*t
            let y=(2*t3-3*t2+1)*a.y+(t3-2*t2+t)*span*slopes[i]+(-2*t3+3*t2)*b.y+(t3-t2)*span*slopes[i+1]
            return min(1,max(0,y))
        }
        return ordered.last?.y ?? 1
    }
}
