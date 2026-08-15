import CoreGraphics
import Foundation
import SpriteKit

/// Everything that is drawn once and then reused: the sprite textures, the
/// pyre, the ground, and the vignette.
///
/// The static art is rendered at full firelight and then multiplied down each
/// frame (`colorBlendFactor` toward black is exactly a multiply), which is how
/// the pyre dims as the fire dies without re-rendering anything.
enum SceneArt {

    // MARK: - Bitmap helpers

    static func context(_ w: Int, _ h: Int) -> CGContext? {
        guard w > 0, h > 0 else { return nil }
        let ctx = CGContext(data: nil, width: w, height: h,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        // Flip to y-down so the drawing code below can use the same coordinates
        // as the web build.
        ctx?.translateBy(x: 0, y: CGFloat(h))
        ctx?.scaleBy(x: 1, y: -1)
        return ctx
    }

    // MARK: - Radial sprite

    /// A white radial blob with the alpha falloff baked in. Everything additive
    /// uses this one texture and tints it, which keeps the draw calls batched.
    static func radialTexture(size: Int, core: Double, falloff: Double) -> SKTexture {
        var px = [UInt8](repeating: 0, count: size * size * 4)
        let mid = Double(size) / 2
        for y in 0..<size {
            for x in 0..<size {
                let dx = (Double(x) - mid + 0.5) / mid
                let dy = (Double(y) - mid + 0.5) / mid
                let dist = (dx * dx + dy * dy).squareRoot()
                var a = dist >= 1 ? 0 : pow(1 - dist, falloff)
                a = min(1, a * (1 + core * pow(max(0, 1 - dist * 2.2), 2)))
                let i = (y * size + x) * 4
                let v = UInt8(max(0, min(255, a * 255)))
                px[i] = v; px[i + 1] = v; px[i + 2] = v; px[i + 3] = v  // premultiplied white
            }
        }
        return texture(from: px, size: size) ?? SKTexture()
    }

    private static func texture(from px: [UInt8], size: Int) -> SKTexture? {
        guard let provider = CGDataProvider(data: Data(px) as CFData),
              let img = CGImage(width: size, height: size,
                                bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: size * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                provider: provider, decode: nil,
                                shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return SKTexture(cgImage: img)
    }

    // MARK: - Pyre layout

    struct Crack {
        var u = 0.0, v = 0.0, l = 0.0, a = 0.0, ph = 0.0, sp = 0.0
    }

    struct Log {
        var x = 0.0, y = 0.0, len = 0.0, th = 0.0, rot = 0.0
        var front = false, char = 0.0
        var cracks: [Crack] = []
        var grain: [(v: Double, u0: Double, u1: Double)] = []
    }

    struct Stone { var x = 0.0, y = 0.0, w = 0.0, h = 0.0, rot = 0.0, tone = 0.0, near = 0.0 }
    struct Coal { var x = 0.0, y = 0.0, r = 0.0, ph = 0.0, sp = 0.0, hot = 0.0 }

    struct Layout {
        var logs: [Log] = []
        var stones: [Stone] = []
        var coals: [Coal] = []
    }

    /// Deterministic: same pyre every launch.
    static func buildLayout() -> Layout {
        var r = Mulberry32(seed: 0x1F5A37)
        var out = Layout()

        // gravel + ash chunks scattered over the pit floor
        for _ in 0..<90 {
            let a = r.next() * .pi * 2
            let rr = 0.25 + r.next().squareRoot() * 0.75
            out.stones.append(Stone(x: cos(a) * rr * 250,
                                    y: 20 + sin(a) * rr * 74,
                                    w: 2.5 + r.next() * 7,
                                    h: 1.6 + r.next() * 3.6,
                                    rot: (r.next() - 0.5) * 0.8,
                                    tone: 0.35 + r.next() * 0.65,
                                    near: 1 - rr))
        }
        out.stones.sort { $0.y < $1.y }

        func log(_ x: Double, _ y: Double, _ len: Double, _ th: Double,
                 _ rot: Double, _ front: Bool, _ char: Double) {
            var o = Log(x: x, y: y, len: len, th: th, rot: rot, front: front, char: char)
            for _ in 0..<(5 + Int(r.next() * 6)) {
                o.cracks.append(Crack(u: (r.next() - 0.5) * 0.86,
                                      v: 0.1 + r.next() * 0.45,   // mostly on the fire-facing side
                                      l: 0.015 + r.next() * 0.055,
                                      a: (r.next() - 0.5) * 2.2,
                                      ph: r.next() * 6.28,
                                      sp: 0.7 + r.next() * 1.9))
            }
            for _ in 0..<(5 + Int(r.next() * 4)) {
                o.grain.append((v: (r.next() - 0.5) * 0.8,
                                u0: (r.next() - 0.5) * 0.7,
                                u1: 0.1 + r.next() * 0.5))
            }
            out.logs.append(o)
        }

        // back: leaning teepee. front: the two logs lying across the ashes.
        log(-66, -34, 250, 30, -0.78, false, 0.5)
        log(58, -40, 262, 32, 0.74, false, 0.45)
        log(4, -52, 236, 26, -1.32, false, 0.4)
        log(-90, 4, 214, 30, -0.10, false, 0.8)
        log(-18, 26, 268, 40, 0.05, true, 0.9)
        log(46, 14, 232, 34, -0.13, true, 0.85)

        // glowing coal bed
        for _ in 0..<110 {
            let t = r.next() * .pi * 2
            let rr = r.next().squareRoot()
            out.coals.append(Coal(x: cos(t) * rr * 92,
                                  y: 12 + sin(t) * rr * 22,
                                  r: 2.4 + r.next() * 6.5,
                                  ph: r.next() * 6.28,
                                  sp: 0.4 + r.next() * 1.6,
                                  hot: 0.35 + r.next() * 0.65))
        }
        return out
    }

    // MARK: - Static art

    /// Web-space bounds of the drawn art, in sim units.
    static let artRect = CGRect(x: -290, y: -190, width: 580, height: 300)

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> CGColor {
        CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                components: [CGFloat(r / 255), CGFloat(g / 255), CGFloat(b / 255), 1])!
    }

    /// Ground, gravel and back logs in one image; front logs in another, so the
    /// flames can be drawn between them.
    static func renderPyre(layout: Layout, unit U: Double, pixelScale: Double, front: Bool) -> SKTexture? {
        // Rendered at device pixels, displayed at points, or it goes soft on a
        // Retina screen.
        let scale = U * pixelScale
        let w = Int((artRect.width * scale).rounded(.up))
        let h = Int((artRect.height * scale).rounded(.up))
        guard w > 0, h > 0, w < 8192, h < 8192, let ctx = context(w, h) else { return nil }

        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        ctx.translateBy(x: -artRect.minX, y: -artRect.minY)

        let light = 1.0                      // rendered lit; the node multiplies it down

        if !front {
            drawGround(ctx, layout: layout, light: light)
        }
        for l in layout.logs where l.front == front {
            drawLog(ctx, l, light: light)
        }
        guard let img = ctx.makeImage() else { return nil }
        return SKTexture(cgImage: img)
    }

    private static func drawGround(_ ctx: CGContext, layout: Layout, light: Double) {
        // ash and scorched dirt under the pyre
        ctx.saveGState()
        ctx.translateBy(x: 0, y: 18)
        ctx.scaleBy(x: 1, y: 0.3)            // squash a circle so the falloff stays soft all round
        let cs = CGColorSpaceCreateDeviceRGB()
        let colors = [rgb(26 + light * 26, 20 + light * 15, 17 + light * 9),
                      CGColor(colorSpace: cs, components: [CGFloat((14 + light * 12) / 255),
                                                           CGFloat((11 + light * 7) / 255),
                                                           CGFloat((10 + light * 5) / 255), 0.75])!,
                      CGColor(colorSpace: cs, components: [6 / 255, 5 / 255, 5 / 255, 0])!]
        if let grad = CGGradient(colorsSpace: cs, colors: colors as CFArray,
                                 locations: [0, 0.5, 1]) {
            ctx.drawRadialGradient(grad, startCenter: .zero, startRadius: 14,
                                   endCenter: .zero, endRadius: 275, options: [])
        }
        ctx.restoreGState()

        for s in layout.stones {
            let lit = light * s.tone * (0.25 + s.near * 0.95)
            ctx.setFillColor(rgb(10 + lit * 78, 9 + lit * 40, 8 + lit * 22))
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(s.x), y: CGFloat(s.y))
            ctx.rotate(by: CGFloat(s.rot))
            ctx.fillEllipse(in: CGRect(x: -s.w, y: -s.h, width: s.w * 2, height: s.h * 2))
            ctx.restoreGState()
        }
    }

    private static func drawLog(_ ctx: CGContext, _ L: Log, light: Double) {
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(L.x), y: CGFloat(L.y))
        ctx.rotate(by: CGFloat(L.rot))
        let len = L.len, th = L.th, hl = len / 2, ht = th / 2
        let lit = light * (1 - L.char * 0.5)

        // body: dark on top, ember-lit underside
        let cs = CGColorSpaceCreateDeviceRGB()
        let stops = [rgb(8 + lit * 10, 7 + lit * 7, 6 + lit * 6),
                     rgb(15 + lit * 30, 11 + lit * 16, 9 + lit * 10),
                     rgb(26 + lit * 86, 16 + lit * 40, 11 + lit * 16),
                     rgb(16 + lit * 44, 11 + lit * 20, 9 + lit * 9)]
        ctx.saveGState()
        let body = CGPath(roundedRect: CGRect(x: -hl, y: -ht, width: len, height: th),
                          cornerWidth: CGFloat(ht * 0.35), cornerHeight: CGFloat(ht * 0.35),
                          transform: nil)
        ctx.addPath(body)
        ctx.clip()
        if let grad = CGGradient(colorsSpace: cs, colors: stops as CFArray,
                                 locations: [0, 0.4, 0.82, 1]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: -ht),
                                   end: CGPoint(x: 0, y: ht), options: [])
        }
        ctx.restoreGState()

        // sawn end, lit from the fire side
        ctx.saveGState()
        let endRect = CGRect(x: hl - ht * 0.18 - ht * 0.34, y: -ht * 0.98,
                             width: ht * 0.68, height: ht * 1.96)
        ctx.addEllipse(in: endRect)
        ctx.clip()
        let endStops = [rgb(30 + lit * 96, 20 + lit * 52, 14 + lit * 24),
                        rgb(14 + lit * 30, 10 + lit * 16, 8 + lit * 8)]
        if let grad = CGGradient(colorsSpace: cs, colors: endStops as CFArray, locations: [0, 1]) {
            ctx.drawRadialGradient(grad,
                                   startCenter: CGPoint(x: hl - ht * 0.2, y: 0), startRadius: CGFloat(ht * 0.1),
                                   endCenter: CGPoint(x: hl - ht * 0.2, y: 0), endRadius: CGFloat(ht),
                                   options: [.drawsAfterEndLocation])
        }
        ctx.restoreGState()

        // bark grain + charred blotches
        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        ctx.setAlpha(0.34)
        ctx.setStrokeColor(CGColor(colorSpace: cs, components: [0, 0, 0, 0.75])!)
        ctx.setLineWidth(1.3)
        for g in L.grain {
            ctx.move(to: CGPoint(x: g.u0 * len, y: g.v * ht * 1.6))
            ctx.addLine(to: CGPoint(x: (g.u0 + g.u1) * len, y: (g.v + 0.06) * ht * 1.6))
            ctx.strokePath()
            ctx.setFillColor(CGColor(colorSpace: cs, components: [0, 0, 0, 0.5])!)
            ctx.fillEllipse(in: CGRect(x: (g.u0 + g.u1 * 0.5) * len - len * 0.07,
                                       y: g.v * ht * 1.3 - ht * 0.42,
                                       width: len * 0.14, height: ht * 0.84))
        }
        ctx.restoreGState()
        ctx.restoreGState()
    }

    // MARK: - Vignette

    /// Radial darkening plus a hair of baked-in noise. Dark radial gradients
    /// band badly on a good display without it.
    static func renderVignette(width: Int, height: Int) -> SKTexture? {
        guard width > 0, height > 0, let ctx = context(width, height) else { return nil }
        let cs = CGColorSpaceCreateDeviceRGB()
        let r = CGFloat(max(width, height)) * 0.78
        let colors = [CGColor(colorSpace: cs, components: [0, 0, 0, 0])!,
                      CGColor(colorSpace: cs, components: [0, 0, 0, 0.35])!,
                      CGColor(colorSpace: cs, components: [0, 0, 0, 0.92])!]
        let c = CGPoint(x: CGFloat(width) * 0.5, y: CGFloat(height) * 0.62)
        if let grad = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: [0, 0.62, 1]) {
            ctx.drawRadialGradient(grad, startCenter: c, startRadius: r * 0.28,
                                   endCenter: c, endRadius: r, options: [.drawsAfterEndLocation])
        }

        var dither = Mulberry32(seed: 4242)
        ctx.setBlendMode(.normal)
        for _ in 0..<(width * height / 24) {
            let x = CGFloat(dither.next() * Double(width))
            let y = CGFloat(dither.next() * Double(height))
            ctx.setFillColor(CGColor(colorSpace: cs, components: [1, 1, 1, CGFloat(dither.next() * 0.016)])!)
            ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }

        guard let img = ctx.makeImage() else { return nil }
        return SKTexture(cgImage: img)
    }

    // MARK: - Flame ramp

    /// hot -> cold, the same twelve steps the web build bakes into its sprites.
    static let ramp: [SKColor] = [
        SKColor(red: 255 / 255, green: 253 / 255, blue: 240 / 255, alpha: 1),
        SKColor(red: 255 / 255, green: 244 / 255, blue: 202 / 255, alpha: 1),
        SKColor(red: 255 / 255, green: 228 / 255, blue: 148 / 255, alpha: 1),
        SKColor(red: 255 / 255, green: 203 / 255, blue: 92 / 255, alpha: 1),
        SKColor(red: 255 / 255, green: 172 / 255, blue: 52 / 255, alpha: 1),
        SKColor(red: 252 / 255, green: 140 / 255, blue: 28 / 255, alpha: 1),
        SKColor(red: 242 / 255, green: 108 / 255, blue: 16 / 255, alpha: 1),
        SKColor(red: 222 / 255, green: 78 / 255, blue: 10 / 255, alpha: 1),
        SKColor(red: 190 / 255, green: 50 / 255, blue: 6 / 255, alpha: 1),
        SKColor(red: 150 / 255, green: 30 / 255, blue: 4 / 255, alpha: 1),
        SKColor(red: 108 / 255, green: 16 / 255, blue: 3 / 255, alpha: 1),
        SKColor(red: 66 / 255, green: 8 / 255, blue: 2 / 255, alpha: 1)
    ]
}
