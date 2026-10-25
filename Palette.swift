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
//    blend of two stronger ones are dropped only when they lack a solid interior.

/// Up to `count` distinct colours from the image, most prominent first.
/// Returns fewer when the image has fewer clearly different colours.
func extractPalette(from cgImage: CGImage, count: Int, passes: Int = 12) -> [String] {
    extractPaletteDefinitions(from:cgImage,count:count,passes:passes).map { RGBSpace.srgb.text($0.source.values) }
}

/// The same extraction without quantising its chosen colours to display hex.
func extractPaletteDefinitions(from cgImage: CGImage, count: Int, passes: Int = 12) -> [ColourDefinition] {
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
    let n=seeds.count
    var px=[Float](repeating:0,count:n*4)
    CIContext(options:[.workingColorSpace:NSNull()]).render(output,toBitmap:&px,rowBytes:n*16,bounds:CGRect(x:0,y:0,width:n,height:1),format:.RGBAf,colorSpace:nil)
    let centres=(0..<n).filter{px[$0*4+3]>0}.map{index -> RGB in
        (min(max(px[index*4],0),1),min(max(px[index*4+1],0),1),min(max(px[index*4+2],0),1))
    }
    return pickDistinct(withoutBlends(merged(bitmap.clusters(around:centres))),count:count).map { cluster in
        let values=[cluster.rgb.r,cluster.rgb.g,cluster.rgb.b]
        return ColourDefinition(source:ColourSource(space:RGBSpace.srgb.rawValue,values:values),master:RGBSpace.srgb.master(of:values),kind:.surface)
    }
}

func loadCGImage(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

// MARK: Choosing colours

struct Cluster {
    let rgb: (r: Double, g: Double, b: Double)
    var weight: Double
    var hasSolidInterior = false
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
        if let i = out.firstIndex(where: { deltaE($0, c) < threshold }) {
            out[i].weight += c.weight
            out[i].hasSolidInterior = out[i].hasSolidInterior || c.hasSolidInterior
        }
        else { out.append(c) }
    }
    return out
}

/// Drops edge-only blends between two heavier colours. A flat interior is evidence of a real
/// surface: grey panels and deliberate intermediate shades must not disappear as "blends".
func withoutBlends(_ clusters: [Cluster], tolerance: Double = 6) -> [Cluster] {
    clusters.filter { c in
        if c.hasSolidInterior { return true }
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
                  minimumDifference: Double = 7) -> [Cluster] {
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
    private let pixels:[Float]

    init?(_ cg: CGImage, maxSide: Int) {
        let scale = min(1, CGFloat(maxSide) / CGFloat(max(cg.width, cg.height)))
        width = max(1, Int(CGFloat(cg.width) * scale))
        height = max(1, Int(CGFloat(cg.height) * scale))
        guard let space=CGColorSpace(name:CGColorSpace.sRGB) else{return nil}
        let image=CIImage(cgImage:cg).transformed(by:CGAffineTransform(scaleX:CGFloat(width)/CGFloat(cg.width),y:CGFloat(height)/CGFloat(cg.height)))
        let white=CIImage(color:CIColor(red:1,green:1,blue:1,alpha:1)).cropped(to:CGRect(x:0,y:0,width:width,height:height))
        var data=[Float](repeating:0,count:width*height*4)
        CIContext(options:[.workingColorSpace:space]).render(image.composited(over:white),toBitmap:&data,rowBytes:width*16,bounds:CGRect(x:0,y:0,width:width,height:height),format:.RGBAf,colorSpace:space)
        pixels=data
    }

    var ciImage: CIImage? {
        pixels.withUnsafeBytes { bytes in
            CIImage(bitmapData:Data(bytes),bytesPerRow:width*16,size:CGSize(width:width,height:height),format:.RGBAf,colorSpace:nil)
        }
    }

    /// Assigns every pixel to its nearest centre. Each cluster reports its most common actual
    /// colour (pixels bucketed at 5 bits a channel) rather than its average.
    func clusters(around centres: [RGB]) -> [Cluster] {
        guard !centres.isEmpty else { return [] }
        struct Bin { var n = 0; var r = 0.0, g = 0.0, b = 0.0; var interior = 0 }
        var bins = [[Int: Bin]](repeating: [:], count: centres.count)
        var counts = [Int](repeating: 0, count: centres.count)
        let data = pixels
        let total = width * height
        func pixelKey(at p: Int) -> Int {
            Int(min(31,max(0,data[p*4]*32))) << 10 | Int(min(31,max(0,data[p*4+1]*32))) << 5 | Int(min(31,max(0,data[p*4+2]*32)))
        }
        for p in 0..<total {
            let r = min(1,max(0,data[p * 4])), g = min(1,max(0,data[p * 4 + 1])), b = min(1,max(0,data[p * 4 + 2]))
            let px: RGB = (r,g,b)
            var nearest = 0, best = Float.greatestFiniteMagnitude
            for (i, c) in centres.enumerated() {
                let d = distance2(px, c)
                if d < best { best = d; nearest = i }
            }
            counts[nearest] += 1
            let key = Int(min(31,r*32)) << 10 | Int(min(31,g*32)) << 5 | Int(min(31,b*32))
            var bin = bins[nearest][key] ?? Bin()
            bin.n += 1; bin.r += Double(r); bin.g += Double(g); bin.b += Double(b)
            let x = p % width, y = p / width
            if x > 0, x < width - 1, y > 0, y < height - 1 {
                var solid = true
                for dy in -1...1 {
                    for dx in -1...1 where pixelKey(at: p + dy * width + dx) != key { solid = false }
                }
                if solid { bin.interior += 1 }
            }
            bins[nearest][key] = bin
        }
        return centres.indices.compactMap { i in
            guard let mode = bins[i].values.max(by: { $0.n < $1.n }) else { return nil }
            let n = Double(mode.n)
            return Cluster(rgb: (Double(mode.r) / n, Double(mode.g) / n, Double(mode.b) / n),
                           weight: Double(counts[i]) / Double(total),
                           hasSolidInterior: mode.interior >= max(4, Int(ceil(Double(total) * 0.0005))))
        }
    }

    func sample(limit: Int) -> [RGB] {
        let data = pixels
        let total = width * height, step = max(1, total / limit)
        return stride(from: 0, to: total, by: step).map {
            (data[$0 * 4], data[$0 * 4 + 1], data[$0 * 4 + 2])
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
    var bytes = [Float](repeating: 1, count: seeds.count * 4)
    for (i, s) in seeds.enumerated() {
        bytes[i * 4] = s.r
        bytes[i * 4 + 1] = s.g
        bytes[i * 4 + 2] = s.b
    }
    // The image must own its pixels: Core Image reads them later, after `bytes` is gone.
    return bytes.withUnsafeBytes { raw in
        CIImage(bitmapData:Data(raw),bytesPerRow:seeds.count*16,
                size:CGSize(width:seeds.count,height:1),format:.RGBAf,colorSpace:nil)
    }
}
