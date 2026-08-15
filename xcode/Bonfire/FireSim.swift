import Foundation

/// The whole fire, with no drawing in it. This is a straight port of the
/// simulation in `index.html`, right down to the constants, so the two builds
/// behave the same and either one can be read against the other.
///
/// Coordinates keep the web convention: origin at the middle of the pyre,
/// **y grows downward**, so a rising particle has negative y. The scene flips
/// the sign once when it places nodes.
final class FireSim {

    // MARK: - Particles

    struct P {
        var x = 0.0, y = 0.0, vx = 0.0, vy = 0.0
        var age = 0.0, life = 1.0, size = 1.0, a0 = 1.0
        var heat = 0.0, c0 = 0.0, swirl = 0.0, flick = 0.0
        var dead = true
    }

    static let maxFlame = 900, maxSmoke = 150, maxSpark = 260

    private(set) var flames = [P](repeating: P(), count: FireSim.maxFlame)
    private(set) var smokes = [P](repeating: P(), count: FireSim.maxSmoke)
    private(set) var sparks = [P](repeating: P(), count: FireSim.maxSpark)

    // MARK: - State

    /// Unit scale. Every constant below is expressed in these units.
    var U: Double = 1

    private(set) var T: Double = 0          // seconds since ignition
    private(set) var gust: Double = 0       // slow wind
    private(set) var breath: Double = 1     // slow intensity swell
    private(set) var flare: Double = 0      // brief bump after a loud crackle
    private(set) var litness: Double = 0    // 0..1 ignition ramp

    /// The fire burns down over `burnSeconds` if nobody touches it, then sits
    /// as embers until it is fed again. 0 = out, 1 = full blaze.
    private(set) var fuel: Double = 1
    /// Flame strength derived from fuel: zero below the ember line.
    private(set) var flameLevel: Double = 1

    var locked = false
    var quality: Double = 1

    static let burnSeconds: Double = 30 * 60

    /// Fired when a crackle event happens, with its strength in 0...1.
    var onCrackle: ((Double) -> Void)?

    private var flameAcc = 0.0, coreAcc = 0.0, smokeAcc = 0.0, sparkAcc = 0.0
    private var nextCrackle: Double = 1.2
    private var rnd = Mulberry32(seed: 0x5EED)
    private var arnd = Mulberry32(seed: Entropy.seed())

    init() {}

    /// Makes a run repeatable, for screenshots and comparisons.
    func seedDeterministically() {
        rnd = Mulberry32(seed: 0x5EED)
        arnd = Mulberry32(seed: 0xC0FFEE)
    }

    // MARK: - Fuel

    func setFuel(_ v: Double) { fuel = min(1, max(0, v)) }

    func setLit() { litness = 1 }

    /// A tap: throw something on the fire.
    @discardableResult
    func feed(_ amount: Double) -> Bool {
        guard !locked else { return false }
        setFuel(fuel + amount)
        flare = max(flare, 0.6 + amount * 1.6)
        for _ in 0..<(12 + Int(amount * 90)) { emitSpark(burst: true) }
        // Fresh wood wakes it up, so do not sit out a long silence that was
        // drawn back when the fire was nearly dead.
        nextCrackle = min(nextCrackle, T + 1 + arnd.next() * 6)
        return true
    }

    // MARK: - Emitters

    private struct Emitter { let x: Double; let w: Double; let weight: Double; let ph: Double }

    private let emitters = [
        Emitter(x: -58, w: 34, weight: 0.80, ph: 0.0),
        Emitter(x: -2, w: 42, weight: 1.00, ph: 2.1),
        Emitter(x: 54, w: 34, weight: 0.85, ph: 4.3)
    ]

    private func pickEmitter() -> Emitter {
        let pick = rnd.next() * 2.65
        var sum = 0.0
        for e in emitters {
            sum += e.weight
            if pick <= sum { return e }
        }
        return emitters[1]
    }

    private func freeIndex(_ pool: [P]) -> Int? {
        for i in 0..<pool.count where pool[i].dead { return i }
        return nil
    }

    private func emitFlame(core: Bool) {
        guard let i = freeIndex(flames) else { return }
        let e = pickEmitter()
        let wob = (Noise.at(T * 0.5 + e.ph) - 0.5) * 24
        let sp = rnd.next() + rnd.next() - 1
        let bed = 0.42 + flameLevel * 0.58        // a low fire sits on a narrower bed

        var p = P()
        p.x = (e.x * bed + wob * bed + sp * e.w * bed) * U
        p.y = (10 + (rnd.next() - 0.5) * 18) * U
        p.vx = sp * -12 * U + (rnd.next() - 0.5) * 30 * U   // converge toward the middle
        p.vy = -(core ? 150 : 95) * U * (0.7 + rnd.next() * 0.6) * (0.8 + flameLevel * 0.2)
        p.age = 0
        // A small fire narrows and dims far more than it shortens, otherwise the
        // last flames hide inside the pyre and it reads as coals too early.
        p.life = (core ? 0.24 + rnd.next() * 0.32 : 0.8 + rnd.next() * 0.85) * (0.7 + flameLevel * 0.3)
        p.size = (core ? 14 + rnd.next() * 18 : 36 + rnd.next() * 48) * U * (0.55 + flameLevel * 0.45)
        p.a0 = core ? 0.13 + rnd.next() * 0.12 : 0.13 + rnd.next() * 0.13
        p.heat = core ? 0 : rnd.next() * 0.3
        p.c0 = core ? 0 : 1.4                     // only the core burns white
        p.swirl = (rnd.next() - 0.5) * 2
        if !core && rnd.next() < 0.06 {           // the odd tongue that licks higher
            p.life *= 1.35; p.vy *= 1.5; p.size *= 0.75; p.a0 *= 1.2
        }
        p.dead = false
        flames[i] = p
    }

    private func emitSmoke() {
        guard let i = freeIndex(smokes) else { return }
        var p = P()
        p.x = (rnd.next() - 0.5) * 150 * U
        p.y = -(300 + rnd.next() * 200) * U
        p.vx = (rnd.next() - 0.5) * 34 * U
        p.vy = -(46 + rnd.next() * 40) * U
        p.age = 0
        p.life = 3.4 + rnd.next() * 3.6
        p.size = (60 + rnd.next() * 70) * U
        p.a0 = 0.010 + rnd.next() * 0.016
        _ = rnd.next()      // the web build draws a rotation here and never uses
                            // it; consumed so both builds stay on the same stream
        p.dead = false
        smokes[i] = p
    }

    private func emitSpark(burst: Bool) {
        guard let i = freeIndex(sparks) else { return }
        var p = P()
        if burst {
            let a = rnd.next() * .pi * 2
            let s = (40 + rnd.next() * 170) * U
            p.x = (rnd.next() - 0.5) * 90 * U
            p.y = (rnd.next() - 0.5) * 30 * U
            p.vx = cos(a) * s
            p.vy = sin(a) * s * 0.55 - 120 * U
        } else {
            // embers lifting off the coals: lazy when the fire is low, torn away when it is up
            p.x = (rnd.next() - 0.5) * 86 * U * (0.5 + flameLevel * 0.5)
            p.y = -(rnd.next() * 60) * U
            p.vx = (rnd.next() - 0.5) * 40 * U
            p.vy = -(150 + rnd.next() * 220) * U * (0.22 + flameLevel * 0.78)
        }
        p.age = 0
        p.life = 1.1 + rnd.next() * 3.4
        p.size = (1.6 + rnd.next() * 3.2) * U
        p.flick = rnd.next() * 6.28
        p.dead = false
        sparks[i] = p
    }

    // MARK: - Crackles
    //
    // A clustered point process, not a metronome. A log pops a few times over a
    // second or two, then the fire can say nothing for minutes.
    //
    //   - within a cluster: another pop follows with probability `clFollow`,
    //     which makes cluster size geometric, a second or so apart
    //   - between clusters: the gap is log-normal. That is what gives the long
    //     tail. A plain Poisson process is memoryless but its tail dies off
    //     exponentially, so it would almost never go quiet for minutes.

    private let clMedian = 12.0, clSigma = 1.5, clFollow = 0.45, clMax = 900.0

    /// Standard normal, Box-Muller. u comes from (0,1] so the log never blows up.
    private func gauss() -> Double {
        let u = 1 - arnd.next(), v = arnd.next()
        return (-2 * Foundation.log(u)).squareRoot() * cos(2 * .pi * v)
    }

    private func scheduleCrackle() {
        var gap: Double
        if arnd.next() < clFollow {
            gap = 0.35 + arnd.next() * arnd.next() * 2.6      // same log, still settling
        } else {
            gap = exp(Foundation.log(clMedian) + clSigma * gauss())
            gap /= (0.22 + flameLevel * 0.78)                 // a dying fire has less to say
            gap = min(gap, clMax)
        }
        nextCrackle = T + gap
    }

    private func crackle() {
        // mostly small ticks, rarely a loud snap. Embers still tick, just quietly.
        let strength = Foundation.pow(rnd.next(), 2.1) * (0.28 + flameLevel * 0.72)
        for _ in 0..<(2 + Int(strength * 26)) { emitSpark(burst: true) }
        if strength > 0.55 { flare = max(flare, strength) }
        onCrackle?(strength)
        scheduleCrackle()
    }

    // MARK: - Step

    func step(_ dt: Double) {
        T += dt
        litness = min(1, litness + dt * 0.55)

        // burn down: full to out over burnSeconds unless it is fed or locked
        if !locked { setFuel(fuel - dt / FireSim.burnSeconds) }
        // flames give out before the fuel does, leaving a bed of embers behind
        flameLevel = fuel <= 0.05 ? 0 : (fuel - 0.05) / 0.95

        // slow breathing so it never looks looped
        gust = (Noise.at(T * 0.085) - 0.5) * 2
        breath = 0.78 + Noise.at(T * 0.13 + 40) * 0.5
        let vigor = breath * litness * flameLevel
        // A small fire is still bright, just smaller. Additive density falls off
        // with the square of the particle count, so the rate drops slower than
        // the size.
        let emitK = breath * litness * Foundation.pow(flameLevel, 0.4)
        flare *= Foundation.pow(0.05, dt)

        let windX = gust * 46 * U * (0.6 + breath * 0.5)

        // ---- emission (accumulators keep rates frame-rate independent)
        let q = quality
        flameAcc += dt * 480 * emitK * q
        while flameAcc >= 1 { emitFlame(core: false); flameAcc -= 1 }
        coreAcc += dt * 150 * emitK * q
        while coreAcc >= 1 { emitFlame(core: true); coreAcc -= 1 }
        smokeAcc += dt * 15 * vigor * q
        while smokeAcc >= 1 { emitSmoke(); smokeAcc -= 1 }
        // embers keep lifting off even with the flames gone
        sparkAcc += dt * (2.2 + fuel * 2.5 + vigor * 6) * q * litness
        while sparkAcc >= 1 { emitSpark(burst: false); sparkAcc -= 1 }

        if T >= nextCrackle { crackle() }

        // ---- flames
        for i in 0..<flames.count {
            if flames[i].dead { continue }
            flames[i].age += dt
            if flames[i].age >= flames[i].life { flames[i].dead = true; continue }
            let f = flames[i].age / flames[i].life

            // turbulence: two octaves of noise scrolling upward = rising eddies
            let t1 = Noise.at(flames[i].x * 0.010, flames[i].y * 0.010 - T * 0.55) - 0.5
            let t2 = Noise.at(flames[i].x * 0.034 + 17.3, flames[i].y * 0.034 - T * 1.7) - 0.5
            let turb = (t1 * 170 + t2 * 105) * U

            flames[i].vx += (turb + flames[i].swirl * 20 * U + windX * (0.25 + f * 1.1)) * dt
            // buoyancy dies as the particle cools, and a smaller fire pushes less air
            flames[i].vy -= (345 * (1 - f * 0.7) + 75 * breath) * U * dt * (0.78 + flameLevel * 0.22)
            flames[i].vx -= flames[i].x * 1.8 * dt          // necking: pull toward the core
            flames[i].vx *= Foundation.pow(0.16, dt)
            flames[i].vy *= Foundation.pow(0.42, dt)

            flames[i].x += flames[i].vx * dt
            flames[i].y += flames[i].vy * dt
        }

        // ---- smoke
        for i in 0..<smokes.count {
            if smokes[i].dead { continue }
            smokes[i].age += dt
            if smokes[i].age >= smokes[i].life { smokes[i].dead = true; continue }
            let f = smokes[i].age / smokes[i].life
            let s1 = Noise.at(smokes[i].x * 0.006 + 91, smokes[i].y * 0.006 - T * 0.22) - 0.5
            smokes[i].vx += (s1 * 90 + windX * 1.5) * U * dt * 0.6
            smokes[i].vy -= 40 * U * dt * (1 - f * 0.6)
            smokes[i].vx *= Foundation.pow(0.55, dt)
            smokes[i].vy *= Foundation.pow(0.7, dt)
            smokes[i].x += smokes[i].vx * dt
            smokes[i].y += smokes[i].vy * dt
        }

        // ---- sparks
        for i in 0..<sparks.count {
            if sparks[i].dead { continue }
            sparks[i].age += dt
            if sparks[i].age >= sparks[i].life { sparks[i].dead = true; continue }
            let k1 = Noise.at(sparks[i].x * 0.02 + 5, sparks[i].y * 0.02 - T * 1.1) - 0.5
            sparks[i].vx += (k1 * 260 * U + windX * 1.4) * dt
            sparks[i].vy += 150 * U * dt                    // gravity wins as it cools
            sparks[i].vy -= 210 * U * dt * max(0, 1 - sparks[i].age / (sparks[i].life * 0.5))
            sparks[i].vx *= Foundation.pow(0.5, dt)
            sparks[i].vy *= Foundation.pow(0.62, dt)
            sparks[i].x += sparks[i].vx * dt
            sparks[i].y += sparks[i].vy * dt
            if sparks[i].y > 40 * U { sparks[i].dead = true }
        }
    }

    // MARK: - Derived values the renderer needs

    var vigor: Double { breath * litness * flameLevel }

    /// How hard the fire lights everything around it. Goes to near nothing when
    /// the flames are out, leaving the coals as the only source.
    var coalGlow: Double { litness * (0.085 + Foundation.pow(fuel, 0.95) * 0.915) }

    var light: Double { min(1.35, 0.06 + vigor * 0.62 + coalGlow * 0.34 + flare * 0.5) }

    /// A small fire throws a small pool of light, not a dim wide one.
    var spread: Double { 0.3 + 0.7 * max(flameLevel, coalGlow * 0.5) }
}
