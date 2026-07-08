//
//  ListenerView.swift
//  The Cursed Room
//
//  Phase 6A — visual impairment overlay (vignette) plus a one-time dismissible
//  role popup. Phase 8B — Frequency Scanner overlay once the first seal is found.
//

import Combine
import SwiftUI

struct ListenerView: View {
    @ObservedObject var presenter: GameplayPresenter
    @State private var showRolePopup = true
    @State private var signalBarHeights: [CGFloat] = Array(repeating: 0.2, count: 12)

    var body: some View {
        ZStack {
            vignette

            if presenter.showFrequencyScanner && !showRolePopup {
                scannerCard
            }

            if showRolePopup {
                RoleRevealPopup(
                    roleTitle: String(localized: "You are the Listener"),
                    roleDescription: String(localized: "You can hear the hidden world, but your vision is fading."),
                    onDismiss: { withAnimation(.easeOut(duration: 0.25)) { showRolePopup = false } }
                )
            }
        }
        .ignoresSafeArea()
        .onReceive(Timer.publish(every: 0.18, on: .main, in: .common).autoconnect()) { _ in
            guard presenter.showFrequencyScanner else { return }
            signalBarHeights = signalBarHeights.map { _ in CGFloat.random(in: 0.08...1.0) }
        }
    }

    private var scannerCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("FREQUENCY SCANNER")
                    .font(.caption.bold())
                    .tracking(2)
                    .foregroundStyle(.cyan.opacity(0.75))
                Spacer()
                Image(systemName: "wave.3.right")
                    .foregroundStyle(.cyan.opacity(0.5))
            }
            .padding(.horizontal, 4)

            HStack(alignment: .center, spacing: 3) {
                ForEach(signalBarHeights.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.cyan.opacity(0.85))
                        .frame(width: 4, height: 8 + CGFloat(presenter.signalClarity) * 56)
                        .scaleEffect(y: signalBarHeights[index], anchor: .center)
                }
            }
            .frame(height: 72)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.55)))

            Text("\(Int(presenter.currentFrequencyHz)) Hz")
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan)

            Text("Target: \(Int(presenter.targetFrequencyHz)) Hz")
                .font(.caption)
                .foregroundStyle(.cyan.opacity(0.65))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule()
                        .fill(.green.opacity(0.85))
                        .frame(width: geo.size.width * CGFloat(presenter.signalClarity))
                }
            }
            .frame(height: 6)

            Slider(
                value: Binding(
                    get: { presenter.sliderValue },
                    set: { presenter.updateFrequencySlider($0) }
                ),
                in: 0...1
            )
            .disabled(presenter.isFrequencyLocked)
            .tint(.cyan)

            if presenter.isFrequencyLocked {
                Text("SIGNAL LOCKED")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private var vignette: some View {
        RadialGradient(
            gradient: Gradient(colors: [
                Color.black.opacity(0.35),
                Color.black.opacity(0.92),
                Color.black
            ]),
            center: .center,
            startRadius: 40,
            endRadius: 420
        )
        .ignoresSafeArea()
    }
}
