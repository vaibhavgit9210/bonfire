import Foundation
import Security

/// mulberry32, ported so the Swift build produces the same numbers as the web
/// build for a given seed. Handy when comparing the two side by side.
struct Mulberry32 {
    private var a: UInt32

    init(seed: UInt32) { a = seed }

    mutating func next() -> Double {
        a = a &+ 0x6D2B79F5
        var t = (a ^ (a >> 15)) &* (a | 1)
        t = (t &+ ((t ^ (t >> 7)) &* (t | 61))) ^ t
        return Double(t ^ (t >> 14)) / 4294967296.0
    }

    /// Uniform in [lo, hi).
    mutating func next(_ lo: Double, _ hi: Double) -> Double {
        lo + next() * (hi - lo)
    }
}

/// Value noise over a hashed lattice. Cheap, and seamless enough for turbulence.
enum Noise {
    private static let perm: [UInt8] = {
        var p = [UInt8](0...255)
        var r = Mulberry32(seed: 7717)
        var i = 255
        while i > 0 {
            let j = Int(r.next() * Double(i + 1))
            p.swapAt(i, j)
            i -= 1
        }
        return p
    }()

    private static func lat(_ i: Int, _ j: Int) -> Double {
        let a = Int(perm[i & 255])
        return Double(perm[(a + (j & 255)) & 255]) / 255.0
    }

    private static func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    static func at(_ x: Double, _ y: Double) -> Double {
        let xi = Int(x.rounded(.down)), yi = Int(y.rounded(.down))
        let xf = smooth(x - x.rounded(.down)), yf = smooth(y - y.rounded(.down))
        let a = lat(xi, yi), b = lat(xi + 1, yi)
        let c = lat(xi, yi + 1), d = lat(xi + 1, yi + 1)
        let top = a + (b - a) * xf
        let bottom = c + (d - c) * xf
        return top + (bottom - top) * yf
    }

    static func at(_ x: Double) -> Double { at(x, 0.5) }
}

/// Crackle timing gets its own stream, seeded from the system CSPRNG so that
/// two launches never produce the same pattern.
enum Entropy {
    static func seed() -> UInt32 {
        var v: UInt32 = 0
        let ok = withUnsafeMutableBytes(of: &v) { buf in
            SecRandomCopyBytes(kSecRandomDefault, buf.count, buf.baseAddress!) == errSecSuccess
        }
        if !ok || v == 0 {
            v = UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970 * 1000)) ^ 0x9E37_79B9
        }
        return v
    }
}
