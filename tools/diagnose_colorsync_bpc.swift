// Standalone diagnostic. Does not build, launch or modify Colorgain.
// Run: swift tools/diagnose_colorsync_bpc.swift /absolute/path/to/CMYK.icc
import AppKit
import ColorSync
import CryptoKit

func key(_ value: Unmanaged<CFString>) -> String { value.takeUnretainedValue() as String }
func profile(_ name: Unmanaged<CFString>) -> ColorSyncProfile {
    ColorSyncProfileCreateWithName(name.takeUnretainedValue())!.takeRetainedValue()
}
func transform(_ source: ColorSyncProfile, _ target: ColorSyncProfile, bpc: Bool) -> ColorSyncTransform {
    let sequence: [[String: Any]] = [
        [key(kColorSyncProfile): source,
         key(kColorSyncTransformTag): kColorSyncTransformDeviceToPCS.takeUnretainedValue(),
         key(kColorSyncRenderingIntent): kColorSyncRenderingIntentRelative.takeUnretainedValue(),
         key(kColorSyncBlackPointCompensation): bpc],
        [key(kColorSyncProfile): target,
         key(kColorSyncTransformTag): kColorSyncTransformPCSToDevice.takeUnretainedValue(),
         key(kColorSyncRenderingIntent): kColorSyncRenderingIntentRelative.takeUnretainedValue(),
         key(kColorSyncBlackPointCompensation): bpc]
    ]
    return ColorSyncTransformCreate(sequence as CFArray,
        [key(kColorSyncConvertQuality): kColorSyncBestQuality.takeUnretainedValue()] as CFDictionary)!.takeRetainedValue()
}
func convert(_ transform: ColorSyncTransform, _ input: [Float], components: Int) -> [Float] {
    var output = [Float](repeating: 0, count: components)
    let success = output.withUnsafeMutableBytes { dst in
        input.withUnsafeBytes { src in
            ColorSyncTransformConvert(transform, 1, 1,
                dst.baseAddress!, kColorSync32BitFloat, 0, dst.count,
                src.baseAddress!, kColorSync32BitFloat, 0, src.count, nil)
        }
    }
    precondition(success && output.allSatisfy(\.isFinite), "Conversion failed")
    return output
}
// Independent standard D50 XYZ-to-Lab calculation, not a display conversion.
func lab(_ xyz: [Float]) -> [Double] {
    func f(_ t: Double) -> Double {
        t > 216.0 / 24389.0 ? cbrt(t) : (24389.0 / 27.0 * t + 16) / 116
    }
    let x = f(Double(xyz[0]) / 0.9642), y = f(Double(xyz[1])), z = f(Double(xyz[2]) / 0.8249)
    return [116 * y - 16, 500 * (x - y), 200 * (y - z)]
}
func formatted<T: BinaryFloatingPoint>(_ values: [T]) -> String {
    values.map { String(format: "%.6f", Double($0)) }.joined(separator: ",")
}

guard CommandLine.arguments.count > 1 else {
    fatalError("Supply one or more installed CMYK ICC file paths; no profiles are installed or modified.")
}
print("OS:", ProcessInfo.processInfo.operatingSystemVersionString)
let xyz = profile(kColorSyncGenericXYZProfile), rgb = profile(kColorSyncSRGBProfile)
for path in CommandLine.arguments.dropFirst() {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let space = CGColorSpace(iccData: data as CFData), space.model == .cmyk,
          let target = ColorSyncProfileCreate(data as CFData, nil)?.takeRetainedValue() else {
        fatalError("Expected a usable CMYK profile: \(path)")
    }
    print("Profile:", path)
    print("SHA256:", SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    let readback = transform(target, xyz, bpc: false)
    print("source,level,bpc,C,M,Y,K,X,Y,Z,L,a,b")
    for (name, source, neutral) in [("XYZ", xyz, [Float(0.9642), 1, 0.8249]),
                                     ("sRGB", rgb, [Float(1), 1, 1])] {
        for bpc in [false, true] {
            let forward = transform(source, target, bpc: bpc)
            for level: Float in [0, 0.2, 0.5, 1] {
                let inks = convert(forward, neutral.map { $0 * level }, components: 4)
                let predicted = convert(readback, inks, components: 3)
                print("\(name),\(level),\(bpc),\(formatted(inks)),\(formatted(predicted)),\(formatted(lab(predicted)))")
            }
        }
    }
}
