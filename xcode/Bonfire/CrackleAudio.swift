import AVFoundation

/// Crackles only. No bed, no roar, no hiss, silence in between, same as the web
/// build. Every pop is synthesised on the spot: a burst of brown noise through
/// a bandpass with a fast exponential decay, and a woody thump under the loud
/// snaps. Nothing is loaded from disk.
final class CrackleAudio {

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var started = false
    private var noise: [Float] = []
    private var rng = Mulberry32(seed: Entropy.seed())

    /// 0...1. Zero is muted.
    var volume: Double = 0.7 {
        didSet {
            volume = min(1, max(0, volume))
            engine.mainMixerNode.outputVolume = Float(volume)
        }
    }

    var isOn: Bool { volume > 0.01 }

    init() {
        // four seconds of brown noise, reused forever
        let n = 4 * 48_000
        noise.reserveCapacity(n)
        var last = 0.0
        var r = Mulberry32(seed: 31337)
        for _ in 0..<n {
            let white = r.next() * 2 - 1
            last = (last + 0.022 * white) / 1.022
            noise.append(Float(last * 3.2))
        }
    }

    // MARK: - Engine

    func start() {
        guard !started else { return }
        started = true
        configureSession()

        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        // A handful of players so overlapping clusters mix instead of queueing
        // up behind each other.
        for _ in 0..<6 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = Float(volume)
        do {
            try engine.start()
            players.forEach { $0.play() }
        } catch {
            started = false
        }
    }

    func stop() {
        players.forEach { $0.stop() }
        engine.stop()
        started = false
        players.removeAll()
    }

    private func configureSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        // Ambient so it mixes with whatever else is playing and respects the
        // ring switch. This is background scenery, not a media app.
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
    }

    // MARK: - Synthesis

    /// One crackle: a short cluster of pops, rendered into a single buffer.
    func crackle(strength: Double) {
        guard started, isOn, !players.isEmpty else { return }
        let sr = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        guard sr > 0 else { return }

        let count = 1 + Int(rng.next() * (1 + strength * 4))
        var pops: [(strength: Double, delay: Double)] = []
        var tail = 0.0
        for i in 0..<count {
            let d = Double(i) * (0.012 + rng.next() * 0.075)
            let s = strength * (0.45 + rng.next() * 0.55)
            pops.append((s, d))
            tail = max(tail, d + 0.02 + rng.next() * 0.07 + s * 0.16 + (s > 0.6 ? 0.2 : 0.05))
        }

        let frames = Int((tail + 0.05) * sr)
        guard frames > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
        else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        guard let out = buffer.floatChannelData?[0] else { return }
        for i in 0..<frames { out[i] = 0 }

        for pop in pops { render(pop.strength, at: pop.delay, into: out, frames: frames, sr: sr) }

        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    private func render(_ strength: Double, at delay: Double,
                        into out: UnsafeMutablePointer<Float>, frames: Int, sr: Double) {
        let start = Int(delay * sr)
        guard start < frames else { return }

        let dur = 0.018 + rng.next() * 0.07 + strength * 0.16
        let n = min(frames - start, Int(dur * sr))
        guard n > 8 else { return }

        // bandpass, RBJ cookbook, constant skirt gain
        let freq = 600 + rng.next() * 3600 * (1 - strength * 0.45)
        let q = 1.2 + rng.next() * 7
        let w0 = 2 * Double.pi * freq / sr
        let alpha = sin(w0) / (2 * q)
        let b0 = alpha, b1 = 0.0, b2 = -alpha
        let a0 = 1 + alpha, a1 = -2 * cos(w0), a2 = 1 - alpha
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

        let peak = 0.08 + strength * 0.5
        let rate = 0.55 + rng.next() * 1.7            // resamples the noise, shifting its colour
        var pos = rng.next() * Double(noise.count - Int(dur * sr * 2) - 2)
        if pos < 0 { pos = 0 }
        let attack = max(1.0, 0.004 * sr)
        let decayK = Foundation.log(0.0001 / max(peak, 1e-6)) / Double(n)

        for i in 0..<n {
            let idx = Int(pos)
            let x = idx + 1 < noise.count ? Double(noise[idx]) : 0
            pos += rate

            let y = (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
            x2 = x1; x1 = x; y2 = y1; y1 = y

            let t = Double(i)
            let env = t < attack ? peak * (t / attack) : peak * exp(decayK * (t - attack))
            out[start + i] += Float(y * env)
        }

        // loud snaps get a woody thump underneath
        guard strength > 0.6 else { return }
        let tn = min(frames - start, Int(0.19 * sr))
        guard tn > 8 else { return }
        let f0 = 150 + rng.next() * 90
        var phase = 0.0
        for i in 0..<tn {
            let t = Double(i) / sr
            let f = f0 * exp(Foundation.log(52 / f0) * min(1, t / 0.12))
            phase += 2 * Double.pi * f / sr
            let env = 0.11 * strength * exp(-t / 0.045)
            out[start + i] += Float(sin(phase) * env)
        }
    }
}
