import Foundation

/// A bounded LUT evaluated in floating point. The input/output RGB space is stored on the node.
struct PaletteLUT {
    let size: Int
    let table: [[Double]]
    let domainMin: [Double]
    let domainMax: [Double]
    let isThreeDimensional: Bool
    var redFastest = true
    var steps: [Step] = []

    enum Step {
        case table(PaletteLUT)
        case matrix([[Double]], [Double])
        case cdl(slope:[Double],offset:[Double],power:[Double],saturation:Double,clamp:Bool)
        case range(minIn:Double,maxIn:Double,minOut:Double,maxOut:Double)
        func sample(_ input:[Double])->[Double] {
            switch self {
            case .table(let table):return table.sample(input)
            case .matrix(let rows,let offsets):
                return (0..<3).map{channel in zip(rows[channel],input).reduce(offsets[channel]){$0+$1.0*$1.1}}
            case .cdl(let slope,let offset,let power,let saturation,let clamp):
                let sop=(0..<3).map{channel -> Double in
                    let value=input[channel]*slope[channel]+offset[channel]
                    let bounded=clamp ? min(1,max(0,value)):value
                    return bounded<0 ? -pow(-bounded,power[channel]):pow(bounded,power[channel])
                }
                let y=0.2126*sop[0]+0.7152*sop[1]+0.0722*sop[2]
                let output=sop.map{y+($0-y)*saturation}
                return clamp ? output.map{min(1,max(0,$0))}:output
            case .range(let minIn,let maxIn,let minOut,let maxOut):
                let span=maxIn-minIn
                return input.map{minOut+($0-minIn)/span*(maxOut-minOut)}
            }
        }
    }

    static func read(_ data: Data, name: String) throws -> PaletteLUT {
        guard data.count <= 16 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else {
            throw failure("The LUT must be UTF-8 and at most 16 MB.")
        }
        if name.lowercased().hasSuffix(".clf") {return try readCLF(data,text:text)}
        guard name.lowercased().hasSuffix(".cube") else {throw failure("Choose a .cube or .clf file.")}
        var size = 0, threeD = false, rows: [[Double]] = []
        var low = [0.0, 0, 0], high = [1.0, 1, 1]
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.split(separator: "#", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if line.isEmpty { continue }
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let first = parts.first else { continue }
            switch first.uppercased() {
            case "TITLE": continue
            case "LUT_1D_SIZE", "LUT_3D_SIZE":
                let is3D = first.uppercased() == "LUT_3D_SIZE"
                guard size == 0, parts.count == 2, let count = Int(parts[1]),
                      (2...(is3D ? 65 : 65_536)).contains(count) else { throw failure("Invalid LUT size.") }
                size = count; threeD = is3D
            case "DOMAIN_MIN", "DOMAIN_MAX":
                guard parts.count == 4 else { throw failure("Invalid LUT domain.") }
                let numbers = parts.dropFirst().compactMap(Double.init)
                guard numbers.count == 3, numbers.allSatisfy(\.isFinite) else { throw failure("Invalid LUT domain.") }
                if first.uppercased() == "DOMAIN_MIN" { low = numbers } else { high = numbers }
            default:
                let numbers = parts.compactMap(Double.init)
                guard parts.count == 3, numbers.count == 3, numbers.allSatisfy(\.isFinite), size > 0 else { throw failure("Unsupported or malformed LUT instruction.") }
                rows.append(numbers)
                guard rows.count <= (threeD ? 65 * 65 * 65 : 65_536) else { throw failure("The LUT exceeds the supported size.") }
            }
        }
        guard size > 0, rows.count == (threeD ? size * size * size : size),
              zip(low, high).allSatisfy({ $0.0 < $0.1 }) else { throw failure("The LUT has an incomplete table or invalid domain.") }
        return PaletteLUT(size: size, table: rows, domainMin: low, domainMax: high, isThreeDimensional: threeD)
    }

    func sample(_ input: [Double]) -> [Double] {
        guard input.count == 3 else { return input }
        if !steps.isEmpty {return steps.reduce(input){value,step in step.sample(value)}}
        let maximum = Double(size - 1)
        var scaled: [Double] = []
        for channel in 0..<3 {
            let fraction = (input[channel] - domainMin[channel]) / (domainMax[channel] - domainMin[channel])
            scaled.append(min(maximum, max(0, fraction * maximum)))
        }
        if !isThreeDimensional {
            return (0..<3).map { channel in
                let lo = Int(floor(scaled[channel])), hi = min(size - 1, lo + 1), t = scaled[channel] - Double(lo)
                return table[lo][channel] * (1 - t) + table[hi][channel] * t
            }
        }
        func value(_ r: Int, _ g: Int, _ b: Int) -> [Double] {
            table[redFastest ? r + size * (g + size * b) : b + size * (g + size * r)]
        }
        let base = scaled.map { Int(floor($0)) }, top = base.map { min(size - 1, $0 + 1) }
        let t = zip(scaled, base).map { $0.0 - Double($0.1) }
        var output = [0.0, 0, 0]
        for r in 0...1 { for g in 0...1 { for b in 0...1 {
            let weight = (r == 0 ? 1 - t[0] : t[0]) * (g == 0 ? 1 - t[1] : t[1]) * (b == 0 ? 1 - t[2] : t[2])
            let row = value(r == 0 ? base[0] : top[0], g == 0 ? base[1] : top[1], b == 0 ? base[2] : top[2])
            for channel in 0..<3 { output[channel] += row[channel] * weight }
        } } }
        return output
    }

    private static func readCLF(_ data:Data,text:String) throws -> PaletteLUT {
        let declarations=text.uppercased()
        guard !declarations.contains("<!DOCTYPE"),!declarations.contains("<!ENTITY") else {throw failure("CLF external declarations are not allowed.")}
        let xml=try XMLDocument(data:data,options:[])
        guard let root=xml.rootElement(),root.name?.split(separator:":").last == "ProcessList" else {throw failure("The CLF needs a ProcessList root.")}
        let elements=root.children?.compactMap{$0 as? XMLElement} ?? []
        guard !elements.isEmpty,elements.count <= 64 else {throw failure("The CLF process list is empty or too large.")}
        var steps:[Step]=[]
        var previousDepth:String?
        for element in elements {
            let name=String(element.name?.split(separator:":").last ?? "")
            if ["Description","InputDescriptor","OutputDescriptor","Info"].contains(name) {continue}
            let inputDepth=element.attribute(forName:"inBitDepth")?.stringValue ?? "32f"
            let outputDepth=element.attribute(forName:"outBitDepth")?.stringValue ?? "32f"
            guard ["16f","32f"].contains(inputDepth),["16f","32f"].contains(outputDepth) else {throw failure("This CLF node needs floating-point input and output.")}
            guard previousDepth == nil || previousDepth == inputDepth else {throw failure("The CLF process bit depths do not connect.")}
            previousDepth=outputDepth
            switch name {
            case "LUT1D","LUT3D":
                let interpolation=element.attribute(forName:"interpolation")?.stringValue ?? (name == "LUT3D" ? "trilinear":"linear")
                guard interpolation == (name == "LUT3D" ? "trilinear":"linear") else {throw failure("This CLF interpolation is not yet supported.")}
                guard let array=element.elements(forName:"Array").first,
                      let dimensions=array.attribute(forName:"dim")?.stringValue?.split(whereSeparator:{$0.isWhitespace}).compactMap({Int($0)}),
                      let size=dimensions.first,(2...(name == "LUT3D" ? 65 : 65_536)).contains(size),
                      (name == "LUT1D" ? (dimensions == [size,3] || dimensions == [size,1]) : dimensions == [size,size,size,3]),
                      let numbers=numbers(array.stringValue),
                      numbers.count==(name == "LUT3D" ? size*size*size*3:size*dimensions.last!) else {throw failure("The CLF LUT array is incomplete.")}
                let rows=dimensions.last == 1 ? numbers.map{[$0,$0,$0]} : stride(from:0,to:numbers.count,by:3).map{Array(numbers[$0..<$0+3])}
                var table=PaletteLUT(size:size,table:rows,domainMin:[0,0,0],domainMax:[1,1,1],isThreeDimensional:name == "LUT3D")
                table.redFastest=name != "LUT3D"
                steps.append(.table(table))
            case "Matrix":
                guard let array=element.elements(forName:"Array").first,
                      let dimensions=array.attribute(forName:"dim")?.stringValue?.split(whereSeparator:{$0.isWhitespace}).compactMap({Int($0)}),
                      [[3,3],[3,4],[3,3,3],[3,4,3]].contains(dimensions),
                      let values=numbers(array.stringValue),[9,12].contains(values.count) else {throw failure("The CLF Matrix must be 3×3 or 3×4.")}
                let columns=values.count/3
                let rows=(0..<3).map{Array(values[$0*columns..<$0*columns+3])}
                let offsets=columns==4 ? (0..<3).map{values[$0*columns+3]}:[0.0,0,0]
                steps.append(.matrix(rows,offsets))
            case "ASC_CDL":
                let sop=element.elements(forName:"SOPNode").first
                let sat=element.elements(forName:"SatNode").first
                let slope=try triple(sop?.elements(forName:"Slope").first?.stringValue,defaultValue:1)
                let offset=try triple(sop?.elements(forName:"Offset").first?.stringValue,defaultValue:0)
                let power=try triple(sop?.elements(forName:"Power").first?.stringValue,defaultValue:1)
                let saturation=numbers(sat?.elements(forName:"Saturation").first?.stringValue)?.first ?? 1
                guard slope.allSatisfy({$0>=0}),power.allSatisfy({$0>0}),saturation>=0 else {throw failure("Invalid CLF CDL parameters.")}
                let style=element.attribute(forName:"style")?.stringValue ?? "Fwd"
                guard ["Fwd","FwdNoClamp"].contains(style) else {throw failure("This CLF CDL style is not supported.")}
                steps.append(.cdl(slope:slope,offset:offset,power:power,saturation:saturation,clamp:style == "Fwd"))
            case "Range":
                func value(_ key:String,_ fallback:Double)->Double {Double(element.elements(forName:key).first?.stringValue ?? "") ?? fallback}
                let minIn=value("minInValue",0),maxIn=value("maxInValue",1)
                let minOut=value("minOutValue",0),maxOut=value("maxOutValue",1)
                guard maxIn>minIn else {throw failure("Invalid CLF Range domain.")}
                steps.append(.range(minIn:minIn,maxIn:maxIn,minOut:minOut,maxOut:maxOut))
            default:throw failure("Unsupported CLF process: \(name). The palette was not changed.")
            }
        }
        return PaletteLUT(size:0,table:[],domainMin:[0,0,0],domainMax:[1,1,1],isThreeDimensional:false,steps:steps)
    }
    private static func numbers(_ text:String?)->[Double]? {
        guard let text else{return nil}
        let parts=text.split(whereSeparator:{$0.isWhitespace})
        let result=parts.compactMap{Double($0)}
        return result.count==parts.count && result.allSatisfy(\.isFinite) ? result:nil
    }
    private static func triple(_ text:String?,defaultValue:Double) throws -> [Double] {
        guard let text else{return [defaultValue,defaultValue,defaultValue]}
        guard let values=numbers(text),values.count==3 else {throw failure("Invalid CLF CDL triplet.")}
        return values
    }
}
