import AppKit
import SceneKit

// ---------- The lighthouse: the splash's picture, one level a section ----------
//
// A spiral-striped lighthouse on a turfed slate island in a cut-away block of turquoise sea, drawn in
// SceneKit from the motion study in design/lighthouse-demo (demo.js, sceneFor('spiral', true)): true
// perspective with upright verticals, the camera's axis horizontal and the picture shifted up in the
// projection. Seven stages: the island, four tower sections, the gallery, the lantern. Each section of
// the splash raises one: a 120 ms lead-in of smoke at the construction joint, then the section grows
// upward, twisting about its axis as it comes, overshoots, compresses, rebounds and settles over
// 1.25 s. A step back collapses it in 600 ms and releases the same smoke ring as it goes. The water
// moves the whole time: edge waves, foam at the shore, three island-shaped ripples expanding and
// fading. With Reduce Motion on, levels simply appear and the water holds still.
//
// Agreed with Rick on 2026-10-09 on the demo's spiral tower.

final class LighthouseView: NSView, SCNSceneRendererDelegate {
    /// How far each level has risen, 0 to 1: the island, four sections of the tower, the gallery, the lamp.
    private(set) var progress: [CGFloat] = Array(repeating: 0, count: 7)
    /// Kept for the splash's layout; the camera frames the scene itself.
    var headroom: CGFloat = 84
    private struct Move { let from: CGFloat, to: CGFloat, start: TimeInterval, length: TimeInterval }
    private struct Burst { let start: TimeInterval, length: TimeInterval }
    private var moves: [Int: Move] = [:]
    private var bursts: [Int: Burst] = [:]
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private let scnView = SCNView()
    private let scene = SCNScene()
    private let camera = SCNCamera()
    private var stages: [SCNNode] = []
    private var smokeRings: [SmokeRing] = []
    private var halo: SCNNode?
    private var edge: SCNNode?, ripples: [SCNNode] = [], foam: [SCNNode] = []
    private var outline: [(CGFloat, CGFloat)] = []
    private var shore: [(CGFloat, CGFloat)] = []
    private var seed: UInt32 = 83
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private struct SmokeRing {
        let joint: SCNNode
        let puffs: [Puff]
        let radius: CGFloat
        struct Puff { let node: SCNNode; let material: SCNMaterial; let size: CGFloat; let angle: CGFloat; let spread: CGFloat; let lift: CGFloat }
    }

    // MARK: Numbers from the study

    private static let tau = CGFloat.pi * 2
    private func random() -> CGFloat { seed = seed &* 1664525 &+ 1013904223; return CGFloat(seed) / 4294967296 }
    private static let slate: [UInt32] = [0x454e60, 0x576174, 0x65717b, 0x384655]
    private static let grass: [UInt32] = [0xb4c960, 0xc8d56a, 0x9eb95b, 0xd4db7a, 0x85a760]
    private static func colour(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }
    private static func material(_ hex: UInt32, doubleSided: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = colour(hex)
        m.roughness.contents = 0.88
        m.metalness.contents = 0
        m.isDoubleSided = doubleSided
        return m
    }
    private let cream = LighthouseView.material(0xf5efdc), iron = LighthouseView.material(0x33434c), coral = LighthouseView.material(0xe56f5d), sand = LighthouseView.material(0xd8cda4)
    private static let towerBase: CGFloat = 1.01, sectionHeight: CGFloat = 1.34

    // MARK: Building the scene

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        scnView.scene = scene
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = false
        scnView.delegate = self
        scnView.rendersContinuously = true
        scnView.isPlaying = true
        addSubview(scnView)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        scnView.frame = bounds
        // The camera's axis is horizontal, so verticals stay vertical; the picture is then shifted up in the projection,
        // as the study does, so the island sits in the frame with the tower above it.
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let f = 1 / tan(camera.fieldOfView * .pi / 360), zn = camera.zNear, zf = camera.zFar
        var p = SCNMatrix4Identity
        p.m11 = f / (size.width / size.height); p.m22 = f
        p.m33 = (zf + zn) / (zn - zf); p.m34 = -1; p.m43 = 2 * zf * zn / (zn - zf); p.m44 = 0
        p.m32 = -1.34
        camera.projectionTransform = p
    }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); needsLayout = true }

    private func build() {
        seed = 83
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        camera.fieldOfView = 28
        camera.projectionDirection = .vertical
        camera.zNear = 0.1; camera.zFar = 100
        cameraNode.position = SCNVector3(19, 11.6, 26)
        cameraNode.look(at: SCNVector3(0, 11.6, 0))
        scene.rootNode.addChildNode(cameraNode)

        let sky = SCNLight(); sky.type = .ambient; sky.color = Self.colour(0xcfd9df); sky.intensity = 900
        let skyNode = SCNNode(); skyNode.light = sky; scene.rootNode.addChildNode(skyNode)
        let sun = SCNLight(); sun.type = .directional; sun.color = Self.colour(0xfff0d1); sun.intensity = 1400
        sun.castsShadow = true; sun.shadowMode = .deferred; sun.shadowRadius = 3; sun.shadowSampleCount = 8
        sun.shadowColor = NSColor.black.withAlphaComponent(0.28); sun.orthographicScale = 10; sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        let sunNode = SCNNode(); sunNode.light = sun; sunNode.position = SCNVector3(-6, 15, 7); sunNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(sunNode)

        // The pale studio surface takes the island's shadow and nothing else.
        let ground = SCNNode(geometry: SCNPlane(width: 200, height: 200))
        let shadowOnly = SCNMaterial(); shadowOnly.lightingModel = .shadowOnly; shadowOnly.transparency = 0.12
        ground.geometry?.materials = [shadowOnly]
        ground.eulerAngles.x = -.pi / 2; ground.position.y = -2.27
        scene.rootNode.addChildNode(ground)

        let root = SCNNode(); scene.rootNode.addChildNode(root)
        let island = SCNNode(); root.addChildNode(island)
        stages = [island]
        let bed = SCNNode(geometry: SCNBox(width: 8.6, height: 0.15, length: 8.6, chamferRadius: 0))
        bed.geometry?.materials = [sand]; bed.position.y = -2.15; island.addChildNode(bed)
        for _ in 0..<32 { let a = random() * Self.tau, r = 2.8 + random() * 1.2; rock(island, cos(a) * r, sin(a) * r, 0.16 + random() * 0.37, 0.18 + random() * 0.55, -2.02) }
        // A quiet web of refracted light on the visible seabed.
        var web: [SCNVector3] = []
        for i in 0..<21 { let z = -4.15 + CGFloat(i) * 0.41; for j in 0...32 { let x = -4.2 + CGFloat(j) * 0.262; web.append(SCNVector3(x, -2.062, z + 0.1 * sin(CGFloat(j) * 0.95 + CGFloat(i)))) } }
        island.addChildNode(lines(web, runs: 21, each: 33, colour: 0xbef0d4, opacity: 0.24))
        sea(in: island)
        shore = turf(island)
        // Large rear outcrops and smaller shore rocks frame the tower without hiding its doorway.
        for (x, z, r, h) in [(-1.45, -0.95, 0.65, 1.8), (-1.95, -0.1, 0.53, 1.05), (1.4, -1.15, 0.7, 1.55), (2, -0.45, 0.48, 1.15), (-2.1, 1.03, 0.57, 0.95), (1.9, 1.25, 0.62, 0.9), (-0.8, -1.8, 0.6, 1.4), (0.3, -2, 0.45, 1.05)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            rock(island, x, z, r, h, 0.35)
            let cap = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: r * 0.46, height: 0.035))
            (cap.geometry as? SCNCone)?.radialSegmentCount = 6
            cap.geometry?.materials = [Self.material(Self.grass[Int(random() * 5) % 5])]
            cap.position = SCNVector3(x, 0.35 + h + 0.01 + 0.0175, z); cap.eulerAngles.y = 0.3
            island.addChildNode(cap)
        }
        for _ in 0..<18 { let a = random() * Self.tau, r = 1.4 + random() * 1.35; rock(island, cos(a) * r, sin(a) * r, 0.10 + random() * 0.18, 0.16 + random() * 0.24, 0.67) }
        // A narrow sandy path curves from the doorway down to the water.
        let path: [(CGFloat, CGFloat, CGFloat)] = [(0.2, 0.99, 0.7), (0.45, 0.99, 1.2), (0.18, 0.91, 1.65), (0.65, 0.77, 2.13), (0.95, 0.55, 2.57)]
        var pv: [SCNVector3] = []
        for i in 0..<(path.count - 1) {
            let a = path[i], b = path[i + 1], w: CGFloat = 0.14
            pv += [SCNVector3(a.0 - w, a.1 + 0.03, a.2), SCNVector3(a.0 + w, a.1 + 0.03, a.2), SCNVector3(b.0 - w, b.1 + 0.03, b.2),
                   SCNVector3(a.0 + w, a.1 + 0.03, a.2), SCNVector3(b.0 + w, b.1 + 0.03, b.2), SCNVector3(b.0 - w, b.1 + 0.03, b.2)]
        }
        island.addChildNode(SCNNode(geometry: flat(pv, material: Self.material(0xe1d39a, doubleSided: true))))
        // Blades of grass, sixty of them, each a sliver.
        for i in 0..<60 {
            let a = random() * Self.tau, r = 1.05 + random() * 1.55, x = cos(a) * r, z = sin(a) * r
            let g = flat([SCNVector3(x, 0.94, z), SCNVector3(x + 0.04, 0.94, z), SCNVector3(x - 0.02, 1.07 + random() * 0.16, z + 0.02)], material: Self.material(Self.grass[i % 5], doubleSided: true))
            island.addChildNode(SCNNode(geometry: g))
        }
        for _ in 0..<3 { let n = lines([SCNVector3](repeating: SCNVector3(0, 0, 0), count: 145), runs: 1, each: 145, colour: 0xeaffed, opacity: 0.5); island.addChildNode(n); ripples.append(n) }
        for _ in 0..<12 { let n = lines([SCNVector3](repeating: SCNVector3(0, 0, 0), count: 12), runs: 1, each: 12, colour: 0xf5ffef, opacity: 0.68); island.addChildNode(n); foam.append(n) }

        // The tower: four sections, each a frustum with the spiral stripe wound on, windows on the way up and the door at the foot.
        let spiral = spiralImage()
        for i in 0..<4 {
            let group = SCNNode(); group.position.y = Self.towerBase + CGFloat(i) * Self.sectionHeight; root.addChildNode(group); stages.append(group)
            let r0 = 0.83 - CGFloat(i) * 0.105, r1 = 0.83 - CGFloat(i + 1) * 0.105
            let striped = SCNMaterial()
            striped.lightingModel = .physicallyBased; striped.roughness.contents = 0.88; striped.metalness.contents = 0
            striped.diffuse.contents = spiral; striped.diffuse.wrapS = .repeat; striped.diffuse.wrapT = .repeat
            group.addChildNode(SCNNode(geometry: frustum(bottom: r0, top: r1, height: Self.sectionHeight, sides: 12, material: striped, uvRow: CGFloat(i), uvRows: 4)))
            window(on: group, radius: (r0 + r1) / 2 + 0.017, y: 0.43, angle: .pi / 6, door: i == 0)
            if i == 0 { window(on: group, radius: r0 - 0.02, y: 0.54, angle: -.pi / 3) }
        }
        // The gallery: a flare of cream, an iron deck, two open rails on twelve posts.
        let gallery = SCNNode(); gallery.position.y = Self.towerBase + 4 * Self.sectionHeight; root.addChildNode(gallery); stages.append(gallery)
        cylinder(in: gallery, bottom: 0.42, top: 0.69, height: 0.23, material: cream, y: 0)
        cylinder(in: gallery, bottom: 0.76, top: 0.76, height: 0.11, material: iron, y: 0.23)
        for y in [0.43, 0.72] as [CGFloat] {
            let rail = SCNNode(geometry: SCNTorus(ringRadius: 0.71, pipeRadius: 0.022)); rail.geometry?.materials = [iron]
            (rail.geometry as? SCNTorus)?.ringSegmentCount = 12; (rail.geometry as? SCNTorus)?.pipeSegmentCount = 4
            rail.position.y = y; gallery.addChildNode(rail)
        }
        for i in 0..<12 { let a = CGFloat(i) / 12 * Self.tau; let post = cylinderNode(bottom: 0.018, top: 0.018, height: 0.4, sides: 5, material: iron); post.position = SCNVector3(sin(a) * 0.71, 0.53, cos(a) * 0.71); gallery.addChildNode(post) }
        // The lantern: amber glass in an iron frame under a coral cap, the bulb, its glow, and the halo.
        let lamp = SCNNode(); lamp.position.y = Self.towerBase + 4 * Self.sectionHeight + 0.34; root.addChildNode(lamp); stages.append(lamp)
        let glass = Self.material(0xffd580); glass.transparency = 0.47; glass.roughness.contents = 0.16; glass.emission.contents = Self.colour(0xffb944).withAlphaComponent(0.2); glass.writesToDepthBuffer = false
        cylinder(in: lamp, bottom: 0.43, top: 0.43, height: 0.79, material: glass, y: 0)
        cylinder(in: lamp, bottom: 0.46, top: 0.46, height: 0.065, material: iron, y: 0.79)
        for i in 0..<8 { let a = CGFloat(i) / 8 * Self.tau; let bar = cylinderNode(bottom: 0.018, top: 0.018, height: 0.79, sides: 5, material: iron); bar.position = SCNVector3(sin(a) * 0.435, 0.395, cos(a) * 0.435); lamp.addChildNode(bar) }
        cylinder(in: lamp, bottom: 0.62, top: 0.05, height: 0.48, material: coral, y: 0.85, sides: 8)
        cylinder(in: lamp, bottom: 0.075, top: 0.035, height: 0.2, material: iron, y: 1.32, sides: 8)
        let bulb = SCNNode(geometry: SCNSphere(radius: 0.145)); (bulb.geometry as? SCNSphere)?.segmentCount = 12
        let bulbMaterial = Self.material(0xffeaa1); bulbMaterial.emission.contents = Self.colour(0xffbd45); bulb.geometry?.materials = [bulbMaterial]
        bulb.position.y = 0.41; lamp.addChildNode(bulb)
        let glow = SCNLight(); glow.type = .omni; glow.color = Self.colour(0xffb94e); glow.intensity = 600; glow.attenuationEndDistance = 3
        let glowNode = SCNNode(); glowNode.light = glow; glowNode.position.y = 0.4; lamp.addChildNode(glowNode)
        let haloNode = SCNNode(geometry: SCNPlane(width: 2.2, height: 2.2))
        let haloMaterial = SCNMaterial(); haloMaterial.lightingModel = .constant; haloMaterial.diffuse.contents = haloImage(); haloMaterial.blendMode = .alpha
        haloMaterial.writesToDepthBuffer = false; haloMaterial.isDoubleSided = true
        haloNode.geometry?.materials = [haloMaterial]; haloNode.position.y = 0.41; haloNode.constraints = [SCNBillboardConstraint()]
        lamp.addChildNode(haloNode); halo = haloNode

        // Smoke lives in world space at each construction joint, never in the twisting tower group: overlapping lobes begin as
        // a continuous horizontal cloud ring, then separate into uneven puffs.
        let puffGeometry = SCNSphere(radius: 1); puffGeometry.segmentCount = 10
        for index in 0..<6 {
            let joint = SCNNode(); joint.position.y = stages[index + 1].position.y + 0.035; root.addChildNode(joint); joint.isHidden = true
            var puffs: [SmokeRing.Puff] = []
            for j in 0..<20 {
                let group = SCNNode(); joint.addChildNode(group)
                let m = SCNMaterial(); m.lightingModel = .physicallyBased; m.diffuse.contents = Self.colour(0xf7f3e8); m.roughness.contents = 1; m.transparency = 0; m.writesToDepthBuffer = false
                let size = 0.21 + random() * 0.14
                for k in 0..<3 {
                    let cloud = SCNNode(geometry: puffGeometry); cloud.geometry = puffGeometry.copy() as? SCNGeometry; cloud.geometry?.materials = [m]
                    cloud.position = SCNVector3(k == 0 ? 0 : (k == 1 ? -0.075 : 0.08), k == 0 ? 0 : 0.035, k == 0 ? 0 : (random() - 0.5) * 0.11)
                    let s = k == 0 ? 1 : 0.65 + random() * 0.2; cloud.scale = SCNVector3(s, s, s); group.addChildNode(cloud)
                }
                puffs.append(SmokeRing.Puff(node: group, material: m, size: size, angle: CGFloat(j) / 20 * Self.tau + (random() - 0.5) * 0.06, spread: 0.83 + random() * 0.35, lift: random() * 0.18))
            }
            smokeRings.append(SmokeRing(joint: joint, puffs: puffs, radius: index < 4 ? 0.83 - CGFloat(index) * 0.105 : 0.67))
        }
        // Everything starts down but the island, which the splash raises when it opens.
        for (i, s) in stages.enumerated() where i > 0 { s.isHidden = true }
        island.isHidden = true
    }

    /// The cut-away sea: a translucent surface and four walls, the waves written into their vertices by a shader on every frame.
    private func sea(in island: SCNNode) {
        let waves = """
        #pragma arguments
        float motion;
        #pragma body
        float t = scn_frame.time * motion;
        float x = _geometry.position.x, z = _geometry.position.z;
        float w = 0.045 * sin(x * 2.3 + z * 0.9 + t * 1.4) + 0.025 * sin(z * 3.1 - x * 0.8 - t * 1.1);
        _geometry.position.y += w * step(-0.5, _geometry.position.y);
        """
        func seaMaterial(_ hex: UInt32, opacity: CGFloat) -> SCNMaterial {
            let m = SCNMaterial(); m.lightingModel = .physicallyBased; m.diffuse.contents = Self.colour(hex); m.transparency = opacity
            m.roughness.contents = 0.2; m.metalness.contents = 0; m.isDoubleSided = true; m.writesToDepthBuffer = false
            m.shaderModifiers = [.geometry: waves]; m.setValue(NSNumber(value: reduceMotion ? 0 : 1), forKey: "motion")
            return m
        }
        // The surface: a 44 by 44 grid at the waterline.
        var v: [SCNVector3] = []
        let n = 44, half: CGFloat = 4.3, cell = 8.6 / CGFloat(n)
        for i in 0..<n { for j in 0..<n {
            let x0 = -half + CGFloat(j) * cell, z0 = -half + CGFloat(i) * cell, x1 = x0 + cell, z1 = z0 + cell
            v += [SCNVector3(x0, 0, z0), SCNVector3(x0, 0, z1), SCNVector3(x1, 0, z0), SCNVector3(x1, 0, z0), SCNVector3(x0, 0, z1), SCNVector3(x1, 0, z1)]
        } }
        let surface = SCNNode(geometry: flat(v, material: seaMaterial(0x188e9f, opacity: 0.62), up: true)); surface.renderingOrder = 2; island.addChildNode(surface)
        // The walls, in world space so the shader's x and z are the sea's own: each a strip of 50 panels from the bed to the waterline.
        for side in 0..<4 {
            var w: [SCNVector3] = []
            for j in 0..<50 {
                let q0 = -half + CGFloat(j) * 8.6 / 50, q1 = q0 + 8.6 / 50
                func at(_ q: CGFloat, _ y: CGFloat) -> SCNVector3 {
                    switch side { case 0: return SCNVector3(q, y, -half); case 1: return SCNVector3(half, y, q); case 2: return SCNVector3(-q, y, half); default: return SCNVector3(-half, y, -q) }
                }
                w += [at(q0, -2.1), at(q1, -2.1), at(q0, 0), at(q1, -2.1), at(q1, 0), at(q0, 0)]
            }
            let wall = SCNNode(geometry: flat(w, material: seaMaterial(side == 2 ? 0x08728d : 0x169ea9, opacity: 0.48), up: true)); wall.renderingOrder = 3; island.addChildNode(wall)
        }
        // The rim: a light line round the waterline, moved with the waves on every frame.
        outline = []
        for side in 0..<4 { for j in 0..<65 { let q = -4.3 + CGFloat(j) / 64 * 8.6; outline.append(side == 0 ? (q, -4.3) : side == 1 ? (4.3, q) : side == 2 ? (-q, 4.3) : (-4.3, -q)) } }
        outline.append(outline[0])
        let rim = lines(outline.map { SCNVector3($0.0, 0, $0.1) }, runs: 1, each: outline.count, colour: 0xe6ffff, opacity: 0.85); rim.renderingOrder = 5; island.addChildNode(rim); edge = rim
    }

    // MARK: Geometry

    /// Triangles with a flat normal each, as the study's flat shading gives.
    private func flat(_ v: [SCNVector3], colours: [NSColor]? = nil, uvs: [CGPoint]? = nil, material: SCNMaterial, up: Bool = false) -> SCNGeometry {
        var normals: [SCNVector3] = []
        var i = 0
        while i + 2 < v.count {
            let a = v[i], b = v[i + 1], c = v[i + 2]
            let u = SCNVector3(b.x - a.x, b.y - a.y, b.z - a.z), w = SCNVector3(c.x - a.x, c.y - a.y, c.z - a.z)
            var n = SCNVector3(u.y * w.z - u.z * w.y, u.z * w.x - u.x * w.z, u.x * w.y - u.y * w.x)
            let l = max(1e-6, sqrt(n.x * n.x + n.y * n.y + n.z * n.z)); n = SCNVector3(n.x / l, n.y / l, n.z / l)
            if up && n.y < 0 { n = SCNVector3(-n.x, -n.y, -n.z) }
            normals += [n, n, n]; i += 3
        }
        var sources = [SCNGeometrySource(vertices: v), SCNGeometrySource(normals: normals)]
        if let uvs = uvs { sources.append(SCNGeometrySource(textureCoordinates: uvs)) }
        if let colours = colours {
            var data = Data()
            for c in colours { var f = [Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent), Float(1)]; data.append(Data(bytes: &f, count: 16)) }
            sources.append(SCNGeometrySource(data: data, semantic: .color, vectorCount: colours.count, usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16))
        }
        var indices = (0..<v.count).map { Int32($0) }
        let element = SCNGeometryElement(data: Data(bytes: &indices, count: indices.count * 4), primitiveType: .triangles, primitiveCount: v.count / 3, bytesPerIndex: 4)
        let g = SCNGeometry(sources: sources, elements: [element]); g.materials = [material]
        return g
    }
    /// Line runs of `each` points, `runs` of them, in one geometry.
    private func lines(_ v: [SCNVector3], runs: Int, each: Int, colour: UInt32, opacity: CGFloat) -> SCNNode {
        var indices: [Int32] = []
        for r in 0..<runs { for j in 0..<(each - 1) { indices += [Int32(r * each + j), Int32(r * each + j + 1)] } }
        let element = SCNGeometryElement(data: Data(bytes: &indices, count: indices.count * 4), primitiveType: .line, primitiveCount: indices.count / 2, bytesPerIndex: 4)
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: v)], elements: [element])
        let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = Self.colour(colour); m.transparency = opacity; m.writesToDepthBuffer = false
        g.materials = [m]
        return SCNNode(geometry: g)
    }
    /// Moves a line node's points, keeping its element and material.
    private func move(_ node: SCNNode, to v: [SCNVector3]) {
        guard let g = node.geometry, let element = g.elements.first else { return }
        let n = SCNGeometry(sources: [SCNGeometrySource(vertices: v)], elements: [element]); n.materials = g.materials
        node.geometry = n
    }
    /// A tapered cylinder with flat sides and caps, its sides' texture row `uvRow` of `uvRows`.
    private func frustum(bottom r0: CGFloat, top r1: CGFloat, height h: CGFloat, sides n: Int, material: SCNMaterial, uvRow: CGFloat = 0, uvRows: CGFloat = 1) -> SCNGeometry {
        var v: [SCNVector3] = [], uv: [CGPoint] = []
        for i in 0..<n {
            let a0 = CGFloat(i) / CGFloat(n) * Self.tau, a1 = CGFloat(i + 1) / CGFloat(n) * Self.tau
            let b0 = SCNVector3(sin(a0) * r0, 0, cos(a0) * r0), b1 = SCNVector3(sin(a1) * r0, 0, cos(a1) * r0)
            let t0 = SCNVector3(sin(a0) * r1, h, cos(a0) * r1), t1 = SCNVector3(sin(a1) * r1, h, cos(a1) * r1)
            let u0 = CGFloat(i) / CGFloat(n), u1 = CGFloat(i + 1) / CGFloat(n), v0 = uvRow / uvRows, v1 = (uvRow + 1) / uvRows
            v += [b0, t0, b1, b1, t0, t1]
            uv += [CGPoint(x: u0, y: v0), CGPoint(x: u0, y: v1), CGPoint(x: u1, y: v0), CGPoint(x: u1, y: v0), CGPoint(x: u0, y: v1), CGPoint(x: u1, y: v1)]
            v += [SCNVector3(0, h, 0), t1, t0, SCNVector3(0, 0, 0), b0, b1]
            uv += [CGPoint](repeating: CGPoint(x: 0.5, y: v0), count: 6)
        }
        return flat(v, uvs: uv, material: material)
    }
    private func cylinderNode(bottom r0: CGFloat, top r1: CGFloat, height h: CGFloat, sides: Int = 12, material: SCNMaterial) -> SCNNode {
        SCNNode(geometry: frustum(bottom: r0, top: r1, height: h, sides: sides, material: material))
    }
    private func cylinder(in parent: SCNNode, bottom r0: CGFloat, top r1: CGFloat, height h: CGFloat, material: SCNMaterial, y: CGFloat, sides: Int = 12) {
        let n = cylinderNode(bottom: r0, top: r1, height: h, sides: sides, material: material); n.position.y = y; parent.addChildNode(n)
    }
    /// A slate rock: three rings of six, a point on top.
    private func rock(_ parent: SCNNode, _ x: CGFloat, _ z: CGFloat, _ size: CGFloat, _ height: CGFloat, _ y: CGFloat) {
        let n = 6
        var rings: [[SCNVector3]] = [[], [], []]
        for i in 0..<n {
            let a = CGFloat(i) / CGFloat(n) * Self.tau, r = 0.85 + random() * 0.25
            rings[0].append(SCNVector3(cos(a) * size * r, 0, sin(a) * size * r * 0.85))
            rings[1].append(SCNVector3(cos(a + 0.16) * size * r * 0.9, height * 0.48, sin(a + 0.16) * size * r * 0.8))
            rings[2].append(SCNVector3(cos(a) * size * r * 0.43, height, sin(a) * size * r * 0.43))
        }
        var v: [SCNVector3] = []
        for k in 0..<2 { for i in 0..<n { let j = (i + 1) % n; v += [rings[k][i], rings[k + 1][i], rings[k][j], rings[k][j], rings[k + 1][i], rings[k + 1][j]] } }
        for i in 0..<n { v += [rings[2][i], SCNVector3(0, height, 0), rings[2][(i + 1) % n]] }
        let node = SCNNode(geometry: flat(v, material: Self.material(Self.slate[Int(random() * CGFloat(Self.slate.count)) % Self.slate.count], doubleSided: true)))
        node.position = SCNVector3(x, y, z)
        parent.addChildNode(node)
    }
    /// The turf: an irregular ring of grass over a slate cliff, with the shore ring returned for the ripples.
    private func turf(_ parent: SCNNode) -> [(CGFloat, CGFloat)] {
        let n = 18
        var outer: [SCNVector3] = [], inner: [SCNVector3] = []
        for i in 0..<n {
            let a = CGFloat(i) / CGFloat(n) * Self.tau, r = 2.35 + random() * 0.48
            outer.append(SCNVector3(cos(a) * r, 0.58 + random() * 0.3, sin(a) * r))
            inner.append(SCNVector3(cos(a) * r * 0.6, 1.01 + random() * 0.09, sin(a) * r * 0.6))
        }
        // One geometry per shade: SceneKit's physically based shading leaves vertex colours alone.
        var byShade: [UInt32: [SCNVector3]] = [:]
        func tri(_ a: SCNVector3, _ b: SCNVector3, _ d: SCNVector3, _ hex: UInt32) { byShade[hex, default: []] += [a, b, d] }
        for i in 0..<n {
            let j = (i + 1) % n
            let b = SCNVector3(outer[i].x * 1.04, -0.5, outer[i].z * 1.04), bj = SCNVector3(outer[j].x * 1.04, -0.5, outer[j].z * 1.04)
            tri(outer[i], outer[j], inner[i], Self.grass[i % 5])
            tri(outer[j], inner[j], inner[i], Self.grass[(i + 2) % 5])
            tri(inner[i], inner[j], SCNVector3(0, 1.06, 0), Self.grass[(i + 1) % 5])
            tri(outer[i], b, outer[j], Self.slate[i % 4])
            tri(b, bj, outer[j], Self.slate[(i + 1) % 4])
        }
        for (hex, v) in byShade { parent.addChildNode(SCNNode(geometry: flat(v, material: Self.material(hex, doubleSided: true)))) }
        return outer.map { ($0.x, $0.z) }
    }
    private func shoreRadius(_ a: CGFloat) -> CGFloat {
        let f = ((a / Self.tau).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * CGFloat(shore.count)
        let i = Int(f) % shore.count, u = f - CGFloat(Int(f)), p = shore[i], q = shore[(i + 1) % shore.count]
        return hypot(p.0, p.1) * (1 - u) + hypot(q.0, q.1) * u
    }
    /// A window, or the door at the foot: a cream frame, a dark pane, an iron bar and a sill.
    private func window(on parent: SCNNode, radius r: CGFloat, y: CGFloat, angle: CGFloat, door: Bool = false) {
        let holder = SCNNode(); holder.position = SCNVector3(sin(angle) * r, y, cos(angle) * r); holder.eulerAngles.y = angle; parent.addChildNode(holder)
        let w: CGFloat = door ? 0.29 : 0.17, h: CGFloat = door ? 0.56 : 0.33
        func box(_ bw: CGFloat, _ bh: CGFloat, _ bd: CGFloat, _ m: SCNMaterial, _ x: CGFloat, _ by: CGFloat, _ z: CGFloat) {
            let b = SCNNode(geometry: SCNBox(width: bw, height: bh, length: bd, chamferRadius: 0)); b.geometry?.materials = [m]; b.position = SCNVector3(x, by, z); holder.addChildNode(b)
        }
        box(w + 0.07, h + 0.06, 0.045, cream, 0, h / 2, 0)
        box(w, h, 0.052, Self.material(door ? 0x624c3e : 0x253e4b), 0, h / 2, 0.025)
        if !door { box(0.022, h, 0.015, iron, 0, h / 2, 0.055); box(w + 0.1, 0.035, 0.09, cream, 0, -0.015, 0.02) }
    }
    /// The spiral stripe: coral parallelograms on cream, wound round the tower as it rises.
    private func spiralImage() -> NSImage {
        let size = NSSize(width: 1024, height: 2048)
        return NSImage(size: size, flipped: true) { _ in
            Self.colour(0xf5efdc).setFill(); NSRect(origin: .zero, size: size).fill()
            Self.colour(0xe56f5d).setFill()
            for i in -5..<6 {
                let y = CGFloat(i) * 1024
                let p = NSBezierPath(); p.move(to: NSPoint(x: 0, y: y)); p.line(to: NSPoint(x: 1024, y: y - 1024)); p.line(to: NSPoint(x: 1024, y: y - 610)); p.line(to: NSPoint(x: 0, y: y + 414)); p.close(); p.fill()
            }
            return true
        }
    }
    /// The lamp's halo: warm light fading out from its centre.
    private func haloImage() -> NSImage {
        let size = NSSize(width: 128, height: 128)
        return NSImage(size: size, flipped: false) { _ in
            let g = NSGradient(colorsAndLocations: (Self.colour(0xffd979, 0.55), 0), (Self.colour(0xffd979, 0.13), 0.3), (Self.colour(0xffd979, 0), 1))
            g?.draw(in: NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)), relativeCenterPosition: .zero)
            return true
        }
    }

    // MARK: Motion

    private var now: TimeInterval { CACurrentMediaTime() }
    /// Raises level `i` into place, or sinks it away: a lead-in of smoke, the twisting rise and the settle, or the collapse and the smoke after it.
    func set(level i: Int, to value: CGFloat) {
        guard progress.indices.contains(i) else { return }
        if i == 0 { progress[0] = value; stages[0].isHidden = value < 0.001; return }
        if reduceMotion { progress[i] = value; moves[i] = nil; bursts[i] = nil; return }
        let rising = value > progress[i]
        if let m = moves[i], m.to == value { return }
        bursts[i] = Burst(start: now + (rising ? 0 : 0.6), length: 1.4)
        moves[i] = Move(from: progress[i], to: value, start: now + (rising ? 0.12 : 0), length: rising ? 1.25 : 0.6)
    }
    /// A damped spring that crosses its destination twice: rise, overshoot, compression, a small rebound, settle.
    private static func spring(_ t: CGFloat) -> CGFloat { t >= 1 ? 1 : 1 - exp(-7 * t) * (cos(13 * t) + 0.18 * sin(13 * t)) }
    private static func wave(_ x: CGFloat, _ z: CGFloat, _ t: CGFloat) -> CGFloat { 0.045 * sin(x * 2.3 + z * 0.9 + t * 1.4) + 0.025 * sin(z * 3.1 - x * 0.8 - t * 1.1) }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let t = now
        for (i, m) in moves {
            let u = CGFloat(max(0, min(1, (t - m.start) / m.length)))
            let e = m.to > m.from ? Self.spring(u) : u * u * (3 - 2 * u)
            progress[i] = m.from + (m.to - m.from) * e
            if u >= 1 { progress[i] = m.to; moves[i] = nil }
        }
        let time = reduceMotion ? 0 : CGFloat(t)
        for (i, g) in stages.enumerated() where i > 0 {
            let v = progress[i]
            g.isHidden = v <= 0.001
            g.scale = SCNVector3(1 + max(0, v - 1) * -0.16, max(0.001, v), 1 + max(0, v - 1) * -0.16)
            g.eulerAngles.y = (1 - v) * -.pi * 1.35
        }
        if !reduceMotion {
            if let e = edge { move(e, to: outline.map { SCNVector3($0.0, Self.wave($0.0, $0.1, time) + 0.012, $0.1) }) }
            for (k, l) in ripples.enumerated() {
                let phase = (time * 0.13 + CGFloat(k) / 3).truncatingRemainder(dividingBy: 1)
                var v: [SCNVector3] = []
                for j in 0..<145 { let a = CGFloat(j) / 144 * Self.tau, r = shoreRadius(a) + 0.12 + phase * 1.12, x = cos(a) * r, z = sin(a) * r; v.append(SCNVector3(x, Self.wave(x, z, time) + 0.055, z)) }
                move(l, to: v); l.geometry?.firstMaterial?.transparency = sin(phase * .pi) * 0.42
            }
            for (k, l) in foam.enumerated() {
                var v: [SCNVector3] = []
                for j in 0..<12 { let a = CGFloat(k) / 12 * Self.tau + CGFloat(j) / 11 * 0.22, r = shoreRadius(a) + 0.12 + 0.04 * sin(time * 1.5 + CGFloat(k)), x = cos(a) * r, z = sin(a) * r; v.append(SCNVector3(x, Self.wave(x, z, time) + 0.07, z)) }
                move(l, to: v); l.geometry?.firstMaterial?.transparency = 0.4 + 0.2 * sin(time + CGFloat(k))
            }
        }
        smoke(at: t)
        halo?.geometry?.firstMaterial?.transparency = 0.45 + 0.12 * sin(time * 1.7)
    }
    private func smoke(at t: TimeInterval) {
        for (index, ring) in smokeRings.enumerated() {
            let age: CGFloat = bursts[index + 1].map { CGFloat((t - $0.start) / $0.length) } ?? 2
            let live = !reduceMotion && age >= 0 && age < 1
            ring.joint.isHidden = !live
            if age >= 1 { bursts[index + 1] = nil }
            guard live else { continue }
            let expansion = 1 - pow(1 - age, 2), appear = min(1, age / 0.07)
            for (j, p) in ring.puffs.enumerated() {
                let radius = ring.radius + 0.06 + expansion * 1.3 * p.spread
                let angle = p.angle + sin(CGFloat(j) * 2.1) * age * 0.07
                p.node.position = SCNVector3(sin(angle) * radius, 0.025 + age * p.lift + sin(age * .pi) * 0.085, cos(angle) * radius)
                let evaporation = 1 - pow(max(0, (age - 0.58) / 0.42), 1.3)
                let size = p.size * (0.82 + expansion * 0.65) * evaporation
                p.node.scale = SCNVector3(size, size * (0.78 + age * 0.35), size)
                p.material.transparency = 0.86 * appear * pow(1 - age, 1.15)
            }
        }
    }
}
