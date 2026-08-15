import SpriteKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Draws the fire. Pools of additive sprites, one shared white radial texture
/// so SpriteKit can batch them, and two pre-rendered images for the pyre.
///
/// The simulation keeps the web build's y-down coordinates; this class flips
/// the sign once, in `place`.
final class FireScene: SKScene {

    let sim = FireSim()
    weak var controller: FireController?

    // layers, back to front
    private let world = SKNode()
    private let backArt = SKSpriteNode()
    private let groundGlow = SKSpriteNode()
    private let coalLayer = SKNode()
    private let smokeLayer = SKNode()
    private let flameLayer = SKNode()
    private let frontArt = SKSpriteNode()
    private let crackLayer = SKNode()
    private let sparkLayer = SKNode()
    private let bloomA = SKSpriteNode()
    private let bloomB = SKSpriteNode()
    private var vignette = SKSpriteNode()

    private var flameNodes: [SKSpriteNode] = []
    private var smokeNodes: [SKSpriteNode] = []
    private var sparkNodes: [SKSpriteNode] = []
    private var coalNodes: [SKSpriteNode] = []
    private var crackNodes: [SKSpriteNode] = []

    private var layout = SceneArt.buildLayout()

    private lazy var flameTex = SceneArt.radialTexture(size: 64, core: 0.55, falloff: 2.1)
    private lazy var sparkTex = SceneArt.radialTexture(size: 24, core: 1.6, falloff: 2.6)
    private lazy var smokeTex = SceneArt.radialTexture(size: 80, core: 0, falloff: 1.5)
    private lazy var glowTex = SceneArt.radialTexture(size: 256, core: 0, falloff: 2.4)
    private lazy var emberTex = SceneArt.radialTexture(size: 32, core: 1.4, falloff: 2.2)
    private lazy var lineTex: SKTexture = SceneArt.radialTexture(size: 8, core: 2.0, falloff: 1.2)

    var gesture: Gesture?

    private var lastUpdate: TimeInterval = 0
    private var accumulator: Double = 0
    private var builtForSize: CGSize = .zero
    private var perfWindow: Double = 0
    private var perfFrames: Int = 0

    private let fixedStep = 1.0 / 60.0

    /// unit scale and the base point, both derived from the view size
    private var U: Double = 1
    private var basePoint: CGPoint = .zero

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 5 / 255, green: 4 / 255, blue: 3 / 255, alpha: 1)
        anchorPoint = CGPoint(x: 0, y: 0)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Build

    override func didMove(to view: SKView) {
        view.ignoresSiblingOrder = true
        if world.parent == nil { buildGraph() }
        // The size can arrive before the view does, in which case the art was
        // built without knowing the real pixel scale. Force one rebuild now.
        builtForSize = .zero
        rebuildIfNeeded()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        rebuildIfNeeded()
    }

    private func buildGraph() {
        addChild(world)

        let layers: [(SKNode, CGFloat)] = [
            (backArt, 0), (groundGlow, 1), (coalLayer, 2), (smokeLayer, 3),
            (flameLayer, 4), (frontArt, 5), (crackLayer, 6), (sparkLayer, 7),
            (bloomA, 8), (bloomB, 8.1)
        ]
        for (node, z) in layers {
            node.zPosition = z
            world.addChild(node)
        }
        vignette.zPosition = 20
        vignette.anchorPoint = CGPoint(x: 0, y: 0)
        addChild(vignette)

        for sprite in [groundGlow, bloomA, bloomB] {
            sprite.texture = glowTex
            sprite.blendMode = .add
            sprite.color = .white
            sprite.colorBlendFactor = 0
            sprite.alpha = 0
        }
        backArt.blendMode = .alpha
        frontArt.blendMode = .alpha
        backArt.color = .black
        frontArt.color = .black

        flameNodes = makePool(count: FireSim.maxFlame, texture: flameTex, parent: flameLayer)
        smokeNodes = makePool(count: FireSim.maxSmoke, texture: smokeTex, parent: smokeLayer)
        sparkNodes = makePool(count: FireSim.maxSpark, texture: sparkTex, parent: sparkLayer)
        coalNodes = makePool(count: layout.coals.count, texture: emberTex, parent: coalLayer)

        for c in coalNodes {
            c.color = SKColor(red: 1, green: 190 / 255, blue: 96 / 255, alpha: 1)
            c.colorBlendFactor = 1
        }
        for s in smokeNodes {
            s.color = SKColor(red: 150 / 255, green: 138 / 255, blue: 128 / 255, alpha: 1)
            s.colorBlendFactor = 1
        }
        for s in sparkNodes {
            s.color = SKColor(red: 1, green: 224 / 255, blue: 160 / 255, alpha: 1)
            s.colorBlendFactor = 1
        }

        let crackCount = layout.logs.reduce(0) { $0 + $1.cracks.count }
        crackNodes = makePool(count: crackCount, texture: lineTex, parent: crackLayer)
        for c in crackNodes { c.colorBlendFactor = 1 }

        sim.onCrackle = { [weak self] strength in
            self?.controller?.audio.crackle(strength: strength)
        }
    }

    private func makePool(count: Int, texture: SKTexture, parent: SKNode) -> [SKSpriteNode] {
        var out: [SKSpriteNode] = []
        out.reserveCapacity(count)
        for _ in 0..<count {
            let n = SKSpriteNode(texture: texture)
            n.blendMode = .add
            n.isHidden = true
            parent.addChild(n)
            out.append(n)
        }
        return out
    }

    /// Layout maths, kept identical to the web build's `resize`.
    private func rebuildIfNeeded() {
        guard size.width > 1, size.height > 1 else { return }
        if size == builtForSize { return }
        builtForSize = size

        let W = Double(size.width), H = Double(size.height)
        U = max(0.3, min(W / 640, H / 620))
        sim.U = U
        // keeps the pyre off the floor on tall screens
        basePoint = CGPoint(x: size.width * 0.5,
                            y: size.height - CGFloat(H * 0.5 + min(H * 0.28, 190 * U)))
        world.position = basePoint

        let px = pixelScale()
        if let tex = SceneArt.renderPyre(layout: layout, unit: U, pixelScale: px, front: false) {
            backArt.texture = tex
            backArt.size = CGSize(width: SceneArt.artRect.width * U, height: SceneArt.artRect.height * U)
            backArt.position = artCenter()
        }
        if let tex = SceneArt.renderPyre(layout: layout, unit: U, pixelScale: px, front: true) {
            frontArt.texture = tex
            frontArt.size = backArt.size
            frontArt.position = backArt.position
        }
        if let tex = SceneArt.renderVignette(width: Int(Double(size.width) * px),
                                             height: Int(Double(size.height) * px)) {
            vignette.texture = tex
            vignette.size = size
            vignette.position = .zero
        }
    }

    private func pixelScale() -> Double {
        #if os(iOS)
        return Double(view?.contentScaleFactor ?? UIScreen.main.scale)
        #elseif os(macOS)
        return Double(view?.window?.backingScaleFactor ?? 2)
        #else
        return 2
        #endif
    }

    /// Centre of the art image, converted from web space into scene space.
    private func artCenter() -> CGPoint {
        let cx = SceneArt.artRect.midX * U
        let cy = SceneArt.artRect.midY * U
        return CGPoint(x: cx, y: -cy)      // y-down to y-up
    }

    private func place(_ node: SKSpriteNode, _ x: Double, _ y: Double) {
        node.position = CGPoint(x: x, y: -y)
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        var dt = lastUpdate == 0 ? fixedStep : currentTime - lastUpdate
        lastUpdate = currentTime
        // a backgrounded app or one stalled frame must never dump minutes of
        // simulation into a single step
        if !(dt > 0) || dt > 0.25 { dt = fixedStep }

        accumulator = min(0.25, accumulator + dt)
        var steps = 0
        while accumulator >= fixedStep && steps < 4 {
            sim.step(fixedStep)
            accumulator -= fixedStep
            steps += 1
        }
        syncNodes()

        // adaptive budget: if we are consistently slow, thin the particles out
        perfWindow += dt
        perfFrames += 1
        if perfWindow >= 2 {
            let fps = Double(perfFrames) / perfWindow
            if fps < 42 && sim.quality > 0.45 {
                sim.quality = max(0.45, sim.quality - 0.12)
            } else if fps > 55 && sim.quality < 1 {
                sim.quality = min(1, sim.quality + 0.06)
            }
            perfWindow = 0
            perfFrames = 0
        }

        controller?.publishIfNeeded(fuel: sim.fuel)
    }

    private func syncNodes() {
        let light = sim.light
        let vigor = sim.vigor
        let coalGlow = sim.coalGlow
        let spread = sim.spread
        let T = sim.T

        // --- pyre, multiplied down as the fire dies
        let tint = CGFloat(max(0, min(1, light)))
        backArt.colorBlendFactor = 1 - tint
        frontArt.colorBlendFactor = 1 - tint

        // --- pool of firelight lying on the ground
        groundGlow.alpha = CGFloat(0.17 * light)
        groundGlow.size = CGSize(width: 800 * U * spread, height: 268 * U * spread)
        place(groundGlow, 0, 24 * U * spread)

        // --- coal bed
        for (i, c) in layout.coals.enumerated() {
            var b = c.hot
                * (0.35 + 0.65 * (0.5 + 0.5 * sin(T * c.sp + c.ph)))
                * Noise.at(T * 0.6 + c.ph * 3) * 2.1
            b = min(1, b) * (coalGlow + sim.flare * 0.4)
            let node = coalNodes[i]
            let alpha = b * 0.75
            if alpha <= 0.003 { node.isHidden = true; continue }
            node.isHidden = false
            node.alpha = CGFloat(alpha)
            let d = c.r * U * (3.4 + b * 2.2)
            node.size = CGSize(width: d, height: d)
            place(node, c.x * U, c.y * U)
        }

        // --- smoke
        for (i, p) in sim.smokes.enumerated() {
            let node = smokeNodes[i]
            if p.dead { node.isHidden = true; continue }
            let f = p.age / p.life
            let a = p.a0 * min(1, f * 5) * (1 - f) * (1 - f)
            if a <= 0.002 { node.isHidden = true; continue }
            node.isHidden = false
            node.alpha = CGFloat(a)
            let d = p.size * (0.8 + f * 2.4)
            node.size = CGSize(width: d, height: d)
            place(node, p.x, p.y)
        }

        // --- flames
        let last = SceneArt.ramp.count - 1
        for (i, p) in sim.flames.enumerated() {
            let node = flameNodes[i]
            if p.dead { node.isHidden = true; continue }
            let f = p.age / p.life
            let ci = p.c0 + pow(f, 1.3) * (1 + p.heat) * (Double(last) - p.c0)
            let idx = max(0, min(last, Int(ci)))
            let a = p.a0 * min(1, p.age / 0.05) * pow(1 - f, 1.35) * (0.72 + light * 0.38)
            if a <= 0.002 { node.isHidden = true; continue }
            node.isHidden = false
            node.color = SceneArt.ramp[idx]
            node.colorBlendFactor = 1
            node.alpha = CGFloat(a)
            let d = p.size * (0.55 + f * 1.05)
            node.size = CGSize(width: d, height: d)
            place(node, p.x, p.y)
        }

        // --- glowing cracks, each breathing on its own clock
        var k = 0
        for L in layout.logs {
            for ck in L.cracks {
                let node = crackNodes[k]; k += 1
                let pulse = 0.35 + 0.65 * (0.5 + 0.5 * sin(T * ck.sp + ck.ph)) * Noise.at(T * 0.8 + ck.ph)
                let a = min(0.55, pulse * light * (0.28 + L.char * 0.32))
                if a < 0.02 { node.isHidden = true; continue }
                node.isHidden = false
                node.alpha = CGFloat(a)
                node.color = a > 0.38
                    ? SKColor(red: 1, green: 168 / 255, blue: 72 / 255, alpha: 1)
                    : SKColor(red: 228 / 255, green: 92 / 255, blue: 20 / 255, alpha: 1)

                // crack endpoints in log space, then rotated into web space
                let len = L.len, ht = L.th / 2
                let x0 = ck.u * len, y0 = ck.v * ht * 1.5
                let x1 = x0 + cos(ck.a) * ck.l * len
                let y1 = y0 + sin(ck.a) * ck.l * len * 0.35
                let mx = (x0 + x1) / 2, my = (y0 + y1) / 2
                let dx = x1 - x0, dy = y1 - y0
                let lineLen = max(2.0, (dx * dx + dy * dy).squareRoot())
                let cr = cos(L.rot), sr = sin(L.rot)
                let wx = L.x + mx * cr - my * sr
                let wy = L.y + mx * sr + my * cr
                node.size = CGSize(width: lineLen * U, height: (0.9 + pulse * 1.3) * 2.2 * U)
                node.zRotation = -CGFloat(atan2(dy, dx) + L.rot)   // negated with the y flip
                place(node, wx * U, wy * U)
            }
        }

        // --- sparks
        for (i, p) in sim.sparks.enumerated() {
            let node = sparkNodes[i]
            if p.dead { node.isHidden = true; continue }
            let f = p.age / p.life
            let fk = 0.45 + 0.55 * (0.5 + 0.5 * sin(T * 22 + p.flick))
            let a = (1 - f) * (1 - f) * fk * 0.8
            if a <= 0.002 { node.isHidden = true; continue }
            node.isHidden = false
            node.alpha = CGFloat(a)
            let d = p.size * (2.4 + fk * 1.6)
            node.size = CGSize(width: d, height: d)
            place(node, p.x, p.y)
        }

        // --- bloom
        let gA = 0.01 + vigor * 0.13 + coalGlow * 0.035 + sim.flare * 0.16
        bloomA.alpha = CGFloat(gA)
        bloomA.size = CGSize(width: 700 * U * spread, height: 700 * U * spread)
        place(bloomA, 0, -110 * U * spread)
        bloomB.alpha = CGFloat(gA * 1.1)
        bloomB.size = CGSize(width: 330 * U * spread, height: 330 * U * spread)
        place(bloomB, 0, -30 * U * spread)
    }

    // MARK: - Input
    //
    // Two invisible panes: drag or scroll the left half for the flame, the
    // right half for the volume. A press that never travels 8 points is a tap,
    // and taps feed the fire. Same rules as the web build.

    struct Gesture {
        var lastY: Double
        var right: Bool
        var dragging: Bool
    }

    static let dragSlop: Double = 8

    func beginGesture(at point: CGPoint) {
        gesture = Gesture(lastY: Double(point.y),
                          right: point.x > size.width * 0.5,
                          dragging: false)
        controller?.wake()
    }

    func moveGesture(to point: CGPoint) {
        guard var g = gesture else { return }
        let dy = Double(point.y) - g.lastY
        if !g.dragging && abs(dy) < FireScene.dragSlop { return }
        g.dragging = true
        g.lastY = Double(point.y)
        gesture = g
        // scene coordinates already run y-up, so this is positive when the
        // pointer moves up
        controller?.adjust(right: g.right, delta: dy)
    }

    func endGesture() {
        guard let g = gesture else { return }
        gesture = nil
        if !g.dragging { controller?.tap() }
    }

    #if os(iOS)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        beginGesture(at: t.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        moveGesture(to: t.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endGesture()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        gesture = nil
    }
    #endif

    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        beginGesture(at: event.location(in: self))
    }

    override func mouseDragged(with event: NSEvent) {
        moveGesture(to: event.location(in: self))
    }

    override func mouseUp(with event: NSEvent) {
        endGesture()
    }

    override func scrollWheel(with event: NSEvent) {
        // AppKit's scrollingDeltaY is the negation of the DOM wheel deltaY the
        // web build uses, so this needs no extra sign flip.
        var dy = Double(event.scrollingDeltaY)
        if !event.hasPreciseScrollingDeltas { dy *= 16 }
        let right = event.location(in: self).x > size.width * 0.5
        controller?.adjust(right: right, delta: dy)
    }
    #endif
}
