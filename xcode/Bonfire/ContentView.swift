import SpriteKit
import SwiftUI

struct ContentView: View {
    @StateObject private var controller = FireController()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            SpriteView(scene: controller.scene,
                       preferredFramesPerSecond: 60,
                       options: [.ignoresSiblingOrder])
                .ignoresSafeArea()

            rails
            controls
        }
        .background(Color.black)
        .onAppear { controller.onAppear() }
        .onDisappear { controller.onDisappear() }
        #if os(iOS)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        #endif
    }

    // MARK: - Rails
    //
    // Invisible until used, then a thin bar fades in on whichever side is being
    // worked and fades back out.

    private var rails: some View {
        GeometryReader { geo in
            let inset = min(70, geo.size.height * 0.12)
            HStack {
                rail(fraction: controller.fuelDisplay,
                     visible: controller.leftRailVisible,
                     warm: true)
                Spacer()
                rail(fraction: controller.volumeDisplay,
                     visible: controller.rightRailVisible,
                     warm: false)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, inset)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private func rail(fraction: Double, visible: Bool, warm: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Capsule().fill(Color(red: 1, green: 0.67, blue: 0.35).opacity(0.14))
                Capsule()
                    .fill(LinearGradient(
                        colors: warm
                            ? [Color(red: 1, green: 0.84, blue: 0.59), Color(red: 1, green: 0.47, blue: 0.12)]
                            : [Color(red: 1, green: 0.93, blue: 0.85), Color(red: 0.75, green: 0.70, blue: 0.65)],
                        startPoint: .top, endPoint: .bottom))
                    .frame(height: max(0, geo.size.height * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(width: 3)
        .opacity(visible ? 1 : 0)
        .animation(.easeOut(duration: visible ? 0.12 : 0.45), value: visible)
    }

    // MARK: - Buttons

    private var controls: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 10) {
                    button(system: controller.locked ? "lock.fill" : "lock.open",
                           active: controller.locked,
                           label: "Lock the flame where it is") {
                        controller.toggleLock()
                    }
                    button(system: controller.volumeDisplay > 0.01 ? "speaker.wave.2" : "speaker.slash",
                           active: controller.volumeDisplay > 0.01,
                           label: "Sound") {
                        controller.toggleSound()
                    }
                    #if os(macOS)
                    button(system: "arrow.up.left.and.arrow.down.right",
                           active: true,
                           label: "Fullscreen") {
                        NSApplication.shared.keyWindow?.toggleFullScreen(nil)
                    }
                    #endif
                }
                .padding(.trailing, 18)
                .padding(.bottom, 18)
            }
        }
        .opacity(controller.controlsVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.5), value: controller.controlsVisible)
        .allowsHitTesting(controller.controlsVisible)
    }

    private func button(system: String, active: Bool, label: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
                .foregroundColor(Color(red: 1, green: 0.72, blue: 0.47).opacity(active ? 1 : 0.38))
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.08, green: 0.05, blue: 0.03).opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(red: 1, green: 0.67, blue: 0.35).opacity(0.22), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
