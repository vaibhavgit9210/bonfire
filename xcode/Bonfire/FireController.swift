import Combine
import SpriteKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Owns the scene and the audio, and is the only thing SwiftUI observes.
///
/// The fuel changes 60 times a second, so it is deliberately *not* published on
/// every frame: only while a rail is on screen, which is the only time anything
/// in SwiftUI depends on it.
final class FireController: ObservableObject {

    let scene: FireScene
    let audio = CrackleAudio()

    /// 0...1, mirrored for the rails. Not live unless a rail is showing.
    @Published private(set) var fuelDisplay: Double = 1
    @Published private(set) var volumeDisplay: Double = 0.7
    @Published private(set) var leftRailVisible = false
    @Published private(set) var rightRailVisible = false
    @Published private(set) var locked = false
    @Published var controlsVisible = true

    private var railHideLeft: DispatchWorkItem?
    private var railHideRight: DispatchWorkItem?
    private var idleHide: DispatchWorkItem?

    init() {
        scene = FireScene(size: CGSize(width: 800, height: 600))
        scene.controller = self
        volumeDisplay = audio.volume
        wake()
    }

    func onAppear() {
        audio.start()
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
    }

    func onDisappear() {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
    }

    // MARK: - Input, mirrored from the web build

    /// Full range over 60% of the screen height, relative to where the drag began.
    func dragSpan() -> Double { max(1, Double(scene.size.height) * 0.6) }

    /// A tap anywhere: throw something on the fire.
    func tap() {
        if locked {
            audio.crackle(strength: 0.35)
            return
        }
        scene.sim.feed(0.12)
        audio.crackle(strength: 0.55 + Double.random(in: 0...0.35))
        wake()
    }

    /// `delta` is in points, positive up.
    func adjust(right: Bool, delta: Double) {
        let v = delta / dragSpan()
        if right {
            audio.volume += v
            volumeDisplay = audio.volume
            showRail(right: true)
        } else {
            if !locked { scene.sim.setFuel(scene.sim.fuel + v) }
            fuelDisplay = scene.sim.fuel
            showRail(right: false)
        }
        wake()
    }

    func toggleLock() {
        locked.toggle()
        scene.sim.locked = locked
        wake()
    }

    func toggleSound() {
        if audio.isOn {
            audio.volume = 0
        } else {
            audio.volume = 0.7
        }
        volumeDisplay = audio.volume
        showRail(right: true)
        wake()
    }

    // MARK: - Rails and chrome

    private func showRail(right: Bool) {
        if right {
            rightRailVisible = true
            railHideRight?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.rightRailVisible = false }
            railHideRight = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
        } else {
            leftRailVisible = true
            railHideLeft?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.leftRailVisible = false }
            railHideLeft = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
        }
    }

    /// Hide the buttons once nothing has been touched for a while.
    func wake() {
        controlsVisible = true
        idleHide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.controlsVisible = false }
        idleHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
    }

    /// Called every frame by the scene, but only forwarded while it matters.
    func publishIfNeeded(fuel: Double) {
        guard leftRailVisible else { return }
        if abs(fuel - fuelDisplay) > 0.002 { fuelDisplay = fuel }
    }
}
