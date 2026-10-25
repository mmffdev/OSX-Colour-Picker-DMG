import AppKit
import CoreImage
import ImageIO

/// The live image session keeps its source reference; saved .colimg presets retain settings only.
struct ImagePaletteRecipe: Codable, Equatable {
    enum Method: String, Codable, CaseIterable {
        case perceptual = "Perceptual Clusters"
        case dominant = "Dominant Areas"
        case vibrant = "Vibrant Accents"
        case hue = "Hue Spectrum"
        case tonal = "Light To Dark"
    }
    enum Region: String, Codable, CaseIterable {
        case full = "Full Image", centre = "Centre", left = "Left Half", right = "Right Half", top = "Top Half", bottom = "Bottom Half"
    }
    var version = 1
    var sourcePath: String?
    var sourceName: String?
    var paletteName = "Image Palette"
    var method: Method = .perceptual
    var region: Region = .full
    var minimumColours = 5
    var maximumColours = 12
    var targetColours = 8
    var sampleSide = 480
    var minimumDifference = 8.0
    var minimumShare = 0.001
    var exposure = 0.0
    var contrast = 1.0
    var saturation = 1.0
    var highlights = 1.0
    var shadows = 0.0
    var warmth = 0.0
    var tint = 0.0
}

struct ImagePaletteResult {
    var colours: [ColourDefinition]
    var shares: [Double]
    /// One representative point per swatch, normalised to the graded image.
    /// The full image is sampled; these points identify where chosen colours occur.
    var targets: [CGPoint] = []
}

enum ImagePaletteExtractor {
    private static let sampleSpace=CGColorSpace(name:CGColorSpace.sRGB)
    private static let sampleContext=sampleSpace.map{CIContext(options:[.workingColorSpace:$0])}
    private struct Sampling {
        var bins:[Sample]
        var pixels:[Float]
        var width:Int
        var height:Int

        func target(for colour:Sample)->CGPoint {
            let step=max(1,Int(sqrt(Double(width*height)/12000)))
            let margin=min(max(2,step*2),max(0,min(width,height)/4))
            var best=Double.greatestFiniteMagnitude,bestX=width/2,bestY=height/2
            for y in stride(from:margin,to:max(margin+1,height-margin),by:step) {
                for x in stride(from:margin,to:max(margin+1,width-margin),by:step) {
                    let p=(y*width+x)*4
                    let r=Double(pixels[p]),g=Double(pixels[p+1]),b=Double(pixels[p+2])
                    let match=pow(r-colour.r,2)+pow(g-colour.g,2)+pow(b-colour.b,2)
                    let offset=max(1,step)
                    let left=(y*width+max(0,x-offset))*4
                    let right=(y*width+min(width-1,x+offset))*4
                    let up=(max(0,y-offset)*width+x)*4
                    let down=(min(height-1,y+offset)*width+x)*4
                    let neighbors=[left,right,up,down]
                    let variation=neighbors.reduce(0.0){sum,index in
                        sum+pow(Double(pixels[index])-r,2)+pow(Double(pixels[index+1])-g,2)+pow(Double(pixels[index+2])-b,2)
                    }/4
                    let score=match+variation*0.35
                    if score < best {best=score;bestX=x;bestY=y}
                }
            }
            // Bitmap rows and the flipped preview view both run from top to bottom.
            return CGPoint(x:(CGFloat(bestX)+0.5)/CGFloat(width),
                           y:(CGFloat(bestY)+0.5)/CGFloat(height))
        }
    }
    private struct Sample {
        var r: Double
        var g: Double
        var b: Double
        var weight: Double
        var lab: (l: Double, a: Double, b: Double) { labOf((r, g, b)) }
        var chroma: Double { let v=lab; return hypot(v.a,v.b) }
        var hue: Double { let v=lab; return atan2(v.b,v.a) }
    }

    /// ImageIO delegates JPEG, PNG, GIF, TIFF, HEIC/HEIF and installed camera-RAW
    /// codecs (including supported DNG/ProRAW) to macOS. Animated GIF uses frame zero.
    /// Thumbnail decoding bounds memory even for a very large source photograph.
    static func decode(_ url: URL, maximumSide: Int = 1800) -> CGImage? {
        let options:[CFString:Any]=[
            kCGImageSourceCreateThumbnailFromImageAlways:true,
            kCGImageSourceCreateThumbnailWithTransform:true,
            kCGImageSourceThumbnailMaxPixelSize:maximumSide,
            kCGImageSourceShouldCacheImmediately:true
        ]
        if let source=CGImageSourceCreateWithURL(url as CFURL,nil),CGImageSourceGetCount(source)>0,
           let thumbnail=CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary){return thumbnail}
        // Some RAW decoders expose a Core Image representation but no ImageIO thumbnail.
        guard let raw=CIImage(contentsOf:url) else{return nil}
        let factor=min(1,Double(maximumSide)/Double(max(raw.extent.width,raw.extent.height)))
        let scaled=raw.transformed(by:CGAffineTransform(scaleX:factor,y:factor))
        return CIContext().createCGImage(scaled,from:scaled.extent)
    }

    /// Decode an in-memory drag image with the same bounded ImageIO preview path.
    static func decode(_ data:Data,maximumSide:Int=1800)->CGImage? {
        let options:[CFString:Any]=[
            kCGImageSourceCreateThumbnailFromImageAlways:true,
            kCGImageSourceCreateThumbnailWithTransform:true,
            kCGImageSourceThumbnailMaxPixelSize:maximumSide,
            kCGImageSourceShouldCacheImmediately:true
        ]
        guard let source=CGImageSourceCreateWithData(data as CFData,nil),CGImageSourceGetCount(source)>0 else{return nil}
        return CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary)
    }

    static func grade(_ source: CGImage, recipe: ImagePaletteRecipe) -> CGImage? {
        guard let space=CGColorSpace(name:CGColorSpace.sRGB) else{return nil}
        var image=CIImage(cgImage:source)
        let width=image.extent.width,height=image.extent.height
        let region: CGRect
        switch recipe.region {
        case .full:region=image.extent
        case .centre:region=CGRect(x:width*0.2,y:height*0.2,width:width*0.6,height:height*0.6)
        case .left:region=CGRect(x:0,y:0,width:width*0.5,height:height)
        case .right:region=CGRect(x:width*0.5,y:0,width:width*0.5,height:height)
        case .top:region=CGRect(x:0,y:height*0.5,width:width,height:height*0.5)
        case .bottom:region=CGRect(x:0,y:0,width:width,height:height*0.5)
        }
        image=image.cropped(to:region)
        image=image.applyingFilter("CITemperatureAndTint",parameters:[
            "inputNeutral":CIVector(x:6500,y:0),
            "inputTargetNeutral":CIVector(x:6500+recipe.warmth*800,y:recipe.tint*80)
        ])
        image=image.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:recipe.exposure])
        image=image.applyingFilter("CIHighlightShadowAdjust",parameters:["inputHighlightAmount":recipe.highlights,"inputShadowAmount":recipe.shadows])
        image=image.applyingFilter("CIColorControls",parameters:[kCIInputContrastKey:recipe.contrast,kCIInputSaturationKey:recipe.saturation])
        return CIContext(options:[.workingColorSpace:space]).createCGImage(image,from:region,format:.RGBA8,colorSpace:space)
    }

    static func extract(_ image: CGImage, recipe: ImagePaletteRecipe) -> ImagePaletteResult {
        let maximum=max(2,min(32,recipe.maximumColours))
        let minimum=max(1,min(maximum,recipe.minimumColours))
        let target=max(minimum,min(maximum,recipe.targetColours))
        // A photograph spreads one visible colour across many fine RGB bins.
        // Apply the area threshold to perceptual colour groups, not individual
        // bins, or textured accents disappear while flat neutral walls survive.
        let sampling=samples(image,side:max(128,min(1024,recipe.sampleSide)))
        let rawSamples=sampling.bins
        let candidates=grouped(rawSamples)
        guard !candidates.isEmpty else{return ImagePaletteResult(colours:[],shares:[])}
        let pool=candidates.filter{$0.weight >= max(0,recipe.minimumShare)}
        var picked:[Sample]=[]
        let ordered=(pool.isEmpty ? candidates:pool).sorted {a,b in
            switch recipe.method {
            case .perceptual,.dominant:return a.weight > b.weight
            case .vibrant:return a.weight * (1+a.chroma/18) > b.weight * (1+b.chroma/18)
            case .hue:return a.chroma > b.chroma
            case .tonal:return a.lab.l < b.lab.l
            }
        }
        if recipe.method == .tonal {
            for index in 0..<target {
                let at=Int(Double(index)*Double(max(0,ordered.count-1))/Double(max(1,target-1)))
                if ordered.indices.contains(at) {
                    let separation=picked.map{distance($0,ordered[at])}.min() ?? 100
                    if separation >= max(0.5,recipe.minimumDifference) || picked.count < minimum {
                        if separation >= 0.5 {picked.append(ordered[at])}
                    }
                }
            }
        } else {
            if picked.isEmpty,let first=ordered.first {picked=[first]}
            while picked.count < target {
                let remaining=ordered.filter{candidate in
                    let separation=picked.map{distance($0,candidate)}.min() ?? 100
                    return separation >= 0.5 && (separation >= recipe.minimumDifference || picked.count < minimum)
                }
                guard let best=remaining.max(by:{score($0,against:picked,method:recipe.method)<score($1,against:picked,method:recipe.method)}) else{break}
                picked.append(best)
            }
        }
        // Minimum is a real lower bound, even when the preferred separation is too strict.
        for candidate in ordered where picked.count < minimum {
            if !picked.contains(where:{distance($0,candidate)<0.5}) {picked.append(candidate)}
        }
        picked=Array(picked.prefix(maximum))
        let definitions=picked.map {sample -> ColourDefinition in
            let values=[sample.r,sample.g,sample.b].map{max(0,min(1,$0))}
            return ColourDefinition(source:ColourSource(space:RGBSpace.srgb.rawValue,values:values),master:RGBSpace.srgb.master(of:values),kind:.surface)
        }
        var coverage=[Double](repeating:0,count:picked.count)
        for sample in rawSamples {
            guard let index=picked.indices.min(by:{rgbDistanceSquared(sample,picked[$0]) < rgbDistanceSquared(sample,picked[$1])}) else{continue}
            coverage[index] += sample.weight
        }
        return ImagePaletteResult(colours:definitions,shares:coverage,
                                  targets:picked.map{sampling.target(for:$0)})
    }

    /// Samples a point or a small local area of the displayed, graded image.
    /// Coordinates use the same top-left normalisation as preview targets.
    static func sampleColour(_ image:CGImage,at point:CGPoint,area:Bool)->ColourDefinition? {
        guard let space=sampleSpace,let context=sampleContext else{return nil}
        let x=max(0,min(image.width-1,Int(point.x*CGFloat(image.width))))
        // CI coordinates start at the bottom; preview targets start at the top.
        let y=image.height-1-max(0,min(image.height-1,Int(point.y*CGFloat(image.height))))
        let input=CIImage(cgImage:image)
        let output:CIImage
        let bounds:CGRect
        if area {
            let side=max(3,Int(Double(min(image.width,image.height))*0.04))
            let rectangle=CGRect(x:max(0,x-side/2),y:max(0,y-side/2),
                                 width:min(side,image.width-max(0,x-side/2)),
                                 height:min(side,image.height-max(0,y-side/2)))
            guard let filter=CIFilter(name:"CIAreaAverage") else{return nil}
            filter.setValue(input,forKey:kCIInputImageKey)
            filter.setValue(CIVector(cgRect:rectangle),forKey:kCIInputExtentKey)
            guard let averaged=filter.outputImage else{return nil}
            output=averaged;bounds=averaged.extent
        } else {
            output=input;bounds=CGRect(x:x,y:y,width:1,height:1)
        }
        var pixel=[Float](repeating:0,count:4)
        context.render(output,toBitmap:&pixel,rowBytes:16,bounds:bounds,format:.RGBAf,colorSpace:space)
        let values=pixel.prefix(3).map{max(0,min(1,Double($0)))}
        return ColourDefinition(source:ColourSource(space:RGBSpace.srgb.rawValue,values:values),
                                master:RGBSpace.srgb.master(of:values),kind:.surface)
    }

    /// Merge nearby shades before assessing how much of an image they occupy.
    /// The modest Lab radius keeps distinct hues apart while combining texture,
    /// grain and gentle lighting changes within one material.
    private static func grouped(_ samples:[Sample])->[Sample] {
        struct Group {
            var r:Double,g:Double,b:Double,weight:Double
            var l:Double,a:Double,labB:Double
            var sample:Sample {Sample(r:r,g:g,b:b,weight:weight)}
        }
        var groups:[Group]=[]
        for sample in samples.sorted(by:{$0.weight > $1.weight}) {
            let lab=sample.lab
            var nearest:Int?,best=14.0
            for index in groups.indices {
                let group=groups[index]
                let gap=sqrt(pow(lab.l-group.l,2)+pow(lab.a-group.a,2)+pow(lab.b-group.labB,2))
                if gap < best {nearest=index;best=gap}
            }
            if let index=nearest {
                let old=groups[index],total=old.weight+sample.weight
                let before=old.weight/total,after=sample.weight/total
                groups[index]=Group(r:old.r*before+sample.r*after,
                                    g:old.g*before+sample.g*after,
                                    b:old.b*before+sample.b*after,
                                    weight:total,
                                    l:old.l*before+lab.l*after,
                                    a:old.a*before+lab.a*after,
                                    labB:old.labB*before+lab.b*after)
            } else {
                groups.append(Group(r:sample.r,g:sample.g,b:sample.b,weight:sample.weight,
                                    l:lab.l,a:lab.a,labB:lab.b))
            }
        }
        return groups.map(\.sample)
    }

    private static func rgbDistanceSquared(_ a:Sample,_ b:Sample)->Double {
        pow(a.r-b.r,2)+pow(a.g-b.g,2)+pow(a.b-b.b,2)
    }

    private static func distance(_ a:Sample,_ b:Sample)->Double {
        let x=a.lab,y=b.lab
        return sqrt(pow(x.l-y.l,2)+pow(x.a-y.a,2)+pow(x.b-y.b,2))
    }
    private static func score(_ candidate:Sample,against chosen:[Sample],method:ImagePaletteRecipe.Method)->Double {
        let difference=chosen.map{distance(candidate,$0)}.min() ?? 100
        switch method {
        case .perceptual:return difference * pow(candidate.weight,0.2) * (1+candidate.chroma/60)
        case .dominant:return candidate.weight * 100 + difference * 0.08
        case .vibrant:return difference * (0.3+candidate.chroma/20) * (0.4+sqrt(candidate.weight*100))
        case .hue:
            let hueGap=chosen.map{abs(atan2(sin(candidate.hue-$0.hue),cos(candidate.hue-$0.hue)))}.min() ?? .pi
            return hueGap * 30 + difference * 0.2 + candidate.chroma * 0.5
        case .tonal:return difference
        }
    }
    private static func samples(_ image:CGImage,side:Int)->Sampling {
        guard let space=CGColorSpace(name:CGColorSpace.sRGB) else{return Sampling(bins:[],pixels:[],width:0,height:0)}
        let factor=min(1,Double(side)/Double(max(image.width,image.height)))
        let width=max(1,Int(Double(image.width)*factor)),height=max(1,Int(Double(image.height)*factor))
        let input=CIImage(cgImage:image).transformed(by:CGAffineTransform(scaleX:factor,y:factor))
        var data=[Float](repeating:0,count:width*height*4)
        CIContext(options:[.workingColorSpace:space]).render(input,toBitmap:&data,rowBytes:width*16,bounds:CGRect(x:0,y:0,width:width,height:height),format:.RGBAf,colorSpace:space)
        struct Bin {var n=0;var r=0.0;var g=0.0;var b=0.0}
        var bins:[Int:Bin]=[:]
        for i in stride(from:0,to:width*height,by:max(1,width*height/50000)) {
            let p=i*4
            let r=Double(max(0,min(1,data[p]))),g=Double(max(0,min(1,data[p+1]))),b=Double(max(0,min(1,data[p+2])))
            let key=Int(r*31)<<10 | Int(g*31)<<5 | Int(b*31)
            var bin=bins[key] ?? Bin();bin.n+=1;bin.r+=r;bin.g+=g;bin.b+=b;bins[key]=bin
        }
        let total=Double(bins.values.reduce(0){$0+$1.n})
        let samples=bins.values.filter{$0.n>0}.map{bin in
            let n=Double(bin.n)
            return Sample(r:bin.r/n,g:bin.g/n,b:bin.b/n,weight:n/max(1,total))
        }
        return Sampling(bins:samples,pixels:data,width:width,height:height)
    }
}
