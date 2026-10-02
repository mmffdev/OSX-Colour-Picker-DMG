import CoreImage
import ImageIO

// ---------- Palette from image ----------
//
// Core Image's CIKMeans (macOS 10.15+) does the clustering. Three things it needs help with:
//  - seeding: its defaults let clusters collapse, so seeds come from k-means++ over a pixel sample;
//  - colour: with colour management on, its output has gamma applied twice, so the image is
//    converted to sRGB here and the filter runs unmanaged on those values;
//  - choice: k-means is weighted by area, so a big flat background eats the clusters. We ask for
//    more clusters than needed, then pick a spread of distinct colours so small accents survive;
//  - edges: a cluster's average is muddied by anti-aliased pixels (red text on grey averages to
//    pink), so each cluster reports its most common actual colour, and colours that are only a
//    blend of two stronger ones are dropped.

/// Up to `count` distinct colours from the image, most prominent first.
/// Returns fewer when the image has fewer clearly different colours.
func extractPalette(from cgImage: CGImage, count: Int, passes: Int = 12) -> [String] {
    guard count > 0, let bitmap = SRGBBitmap(cgImage, maxSide: 640), let image = bitmap.ciImage else { return [] }

    let k = min(max(count * 3, 16), 32)
    let seeds = kMeansPlusPlusSeeds(bitmap.sample(limit: 4096), k: k)
    guard let means = stripImage(seeds), let filter = CIFilter(name: "CIKMeans") else { return [] }
    filter.setValue(image, forKey: kCIInputImageKey)
    filter.setValue(CIVector(cgRect: image.extent), forKey: kCIInputExtentKey)
    filter.setValue(means, forKey: "inputMeans")
    filter.setValue(seeds.count, forKey: "inputCount")
    filter.setValue(passes, forKey: "inputPasses")
    filter.setValue(false, forKey: "inputPerceptual")
    guard let output = filter.outputImage else { return [] }

    // One pixel per cluster: RGB is the cluster colour, alpha its share of the pixels.
    let n = seeds.count
    var px = [Float](repeating: 0, count: n * 4)
    CIContext(options: [.workingColorSpace: NSNull()]).render(
        output, toBitmap: &px, rowBytes: n * 16,
        bounds: CGRect(x: 0, y: 0, width: n, height: 1), format: .RGBAf, colorSpace: nil)

    var centres: [RGB] = []
    for i in 0..<n where px[i * 4 + 3] > 0 {
        centres.append((min(max(px[i * 4], 0), 1), min(max(px[i * 4 + 1], 0), 1), min(max(px[i * 4 + 2], 0), 1)))
    }
    let clusters = bitmap.clusters(around: centres)
    return pickDistinct(withoutBlends(merged(clusters)), count: count).map { $0.hex }
}

func loadCGImage(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

// MARK: Choosing colours

struct Cluster {
    let rgb: (r: Double, g: Double, b: Double)
    var weight: Double
    var lab: (l: Double, a: Double, b: Double) { labOf(rgb) }
    var chroma: Double { (lab.a * lab.a + lab.b * lab.b).squareRoot() }
    var hex: String {
        String(format: "#%02X%02X%02X", Int((rgb.r * 255).rounded()), Int((rgb.g * 255).rounded()), Int((rgb.b * 255).rounded()))
    }
}

/// Perceptual distance (CIE76 ΔE). ~2 is just noticeable; 10+ is clearly a different colour.
func deltaE(_ x: Cluster, _ y: Cluster) -> Double {
    let p = x.lab, q = y.lab
    return ((p.l - q.l) * (p.l - q.l) + (p.a - q.a) * (p.a - q.a) + (p.b - q.b) * (p.b - q.b)).squareRoot()
}

/// Folds clusters that look the same into the heaviest of them.
func merged(_ clusters: [Cluster], within threshold: Double = 7) -> [Cluster] {
    var out: [Cluster] = []
    for c in clusters.sorted(by: { $0.weight > $1.weight }) {
        if let i = out.firstIndex(where: { deltaE($0, c) < threshold }) { out[i].weight += c.weight }
        else { out.append(c) }
    }
    return out
}

/// Drops colours that sit on the line between two heavier ones — the signature of anti-aliasing
/// and soft edges, not a colour in its own right.
func withoutBlends(_ clusters: [Cluster], tolerance: Double = 6) -> [Cluster] {
    clusters.filter { c in
        let heavier = clusters.filter { $0.weight > c.weight }
        for (i, a) in heavier.enumerated() {
            for b in heavier[(i + 1)...] where isBlend(c, of: a, b, tolerance: tolerance) { return false }
        }
        return true
    }
}

/// True when `c` lies close to the segment from `a` to `b`, away from both ends.
private func isBlend(_ c: Cluster, of a: Cluster, _ b: Cluster, tolerance: Double) -> Bool {
    let p = c.lab, q = a.lab, r = b.lab
    let ab = (r.l - q.l, r.a - q.a, r.b - q.b), ac = (p.l - q.l, p.a - q.a, p.b - q.b)
    let length2 = ab.0 * ab.0 + ab.1 * ab.1 + ab.2 * ab.2
    guard length2 > 1 else { return false }
    let t = (ac.0 * ab.0 + ac.1 * ab.1 + ac.2 * ab.2) / length2
    guard t > 0.12, t < 0.88 else { return false }
    let d = (ac.0 - t * ab.0, ac.1 - t * ab.1, ac.2 - t * ab.2)
    return (d.0 * d.0 + d.1 * d.1 + d.2 * d.2).squareRoot() < tolerance
}

/// Heaviest first, then whichever remaining colour is most different from those already chosen,
/// favouring larger areas and stronger colour. Stops early rather than pad with lookalikes.
func pickDistinct(_ clusters: [Cluster], count: Int, minimumShare: Double = 0.0005,
                  minimumDifference: Double = 14) -> [Cluster] {
    var pool = clusters.filter { $0.weight >= minimumShare }.sorted { $0.weight > $1.weight }
    guard !pool.isEmpty else { return Array(clusters.sorted { $0.weight > $1.weight }.prefix(1)) }
    var chosen = [pool.removeFirst()]
    while chosen.count < count, !pool.isEmpty {
        var best = -1, bestScore = 0.0
        for (i, c) in pool.enumerated() {
            let apart = chosen.map { deltaE($0, c) }.min()!
            guard apart >= minimumDifference else { continue }
            let score = apart * pow(c.weight, 0.25) * (1 + c.chroma / 60)
            if score > bestScore { best = i; bestScore = score }
        }
        guard best >= 0 else { break }
        chosen.append(pool.remove(at: best))
    }
    return chosen
}

// MARK: Pixels and seeding

private typealias RGB = (r: Float, g: Float, b: Float)

/// The image drawn into sRGB at no more than `maxSide` pixels, so wide-gamut sources
/// (Display P3 screenshots) come out as the sRGB hex values a user would expect.
private final class SRGBBitmap {
    let width: Int, height: Int
    private let context: CGContext // owns its pixel memory

    init?(_ cg: CGImage, maxSide: Int) {
        let scale = min(1, CGFloat(maxSide) / CGFloat(max(cg.width, cg.height)))
        width = max(1, Int(CGFloat(cg.width) * scale))
        height = max(1, Int(CGFloat(cg.height) * scale))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)) // transparent areas read as white
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        context = ctx
    }

    var ciImage: CIImage? { context.makeImage().map { CIImage(cgImage: $0, options: [.colorSpace: NSNull()]) } }

    /// Assigns every pixel to its nearest centre. Each cluster reports its most common actual
    /// colour (pixels bucketed at 5 bits a channel) rather than its average.
    func clusters(around centres: [RGB]) -> [Cluster] {
        guard !centres.isEmpty else { return [] }
        struct Bin { var n = 0, r = 0, g = 0, b = 0 }
        var bins = [[Int: Bin]](repeating: [:], count: centres.count)
        var counts = [Int](repeating: 0, count: centres.count)
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        let total = width * height
        for p in 0..<total {
            let r = Int(data[p * 4]), g = Int(data[p * 4 + 1]), b = Int(data[p * 4 + 2])
            let px: RGB = (Float(r) / 255, Float(g) / 255, Float(b) / 255)
            var nearest = 0, best = Float.greatestFiniteMagnitude
            for (i, c) in centres.enumerated() {
                let d = distance2(px, c)
                if d < best { best = d; nearest = i }
            }
            counts[nearest] += 1
            let key = (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
            var bin = bins[nearest][key] ?? Bin()
            bin.n += 1; bin.r += r; bin.g += g; bin.b += b
            bins[nearest][key] = bin
        }
        return centres.indices.compactMap { i in
            guard let mode = bins[i].values.max(by: { $0.n < $1.n }) else { return nil }
            let n = Double(mode.n) * 255
            return Cluster(rgb: (Double(mode.r) / n, Double(mode.g) / n, Double(mode.b) / n),
                           weight: Double(counts[i]) / Double(total))
        }
    }

    func sample(limit: Int) -> [RGB] {
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        let total = width * height, step = max(1, total / limit)
        return stride(from: 0, to: total, by: step).map {
            (Float(data[$0 * 4]) / 255, Float(data[$0 * 4 + 1]) / 255, Float(data[$0 * 4 + 2]) / 255)
        }
    }
}

private func distance2(_ a: RGB, _ b: RGB) -> Float {
    (a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b)
}

/// k-means++: each new seed is picked far from the ones chosen so far. Deterministic for a given image.
private func kMeansPlusPlusSeeds(_ pixels: [RGB], k: Int) -> [RGB] {
    var rng: UInt64 = 0x9E3779B97F4A7C15
    func next() -> Float {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        return Float(rng >> 40) / Float(1 << 24)
    }
    var seeds = [pixels[pixels.count / 2]]
    var best = pixels.map { distance2($0, seeds[0]) }
    while seeds.count < k {
        let total = best.reduce(0, +)
        guard total > 1e-6 else { break } // every remaining pixel already sits on a seed
        var target = next() * total, chosen = pixels.count - 1
        for (i, d) in best.enumerated() { target -= d; if target <= 0 { chosen = i; break } }
        let s = pixels[chosen]
        seeds.append(s)
        for i in pixels.indices { best[i] = min(best[i], distance2(pixels[i], s)) }
    }
    return seeds
}

/// A `seeds.count` x 1 image, one opaque pixel per seed, for CIKMeans's inputMeans.
private func stripImage(_ seeds: [RGB]) -> CIImage? {
    var bytes = [UInt8](repeating: 255, count: seeds.count * 4)
    for (i, s) in seeds.enumerated() {
        bytes[i * 4] = UInt8((s.r * 255).rounded())
        bytes[i * 4 + 1] = UInt8((s.g * 255).rounded())
        bytes[i * 4 + 2] = UInt8((s.b * 255).rounded())
    }
    // The image must own its pixels: Core Image reads them later, after `bytes` is gone.
    return CIImage(bitmapData: Data(bytes), bytesPerRow: seeds.count * 4,
                   size: CGSize(width: seeds.count, height: 1), format: .RGBA8, colorSpace: nil)
}
