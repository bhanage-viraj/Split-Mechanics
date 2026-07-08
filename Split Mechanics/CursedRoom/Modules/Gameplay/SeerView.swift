//
//  SeerView.swift
//  The Cursed Room
//
//  Phase 6A — clean AR feed with a one-time dismissible role popup.
//  Phase 8A — unclosable frequency note overlay for the Seer.
//

import SwiftUI

struct SeerView: View {
    @ObservedObject var presenter: GameplayPresenter
    @State private var showRolePopup = true

    var body: some View {
        ZStack {
            if showRolePopup {
                RoleRevealPopup(
                    roleTitle: "You are the Seer",
                    roleDescription: "You can see the hidden world, but you cannot hear it.",
                    onDismiss: { withAnimation(.easeOut(duration: 0.25)) { showRolePopup = false } }
                )
            }

            if presenter.showFrequencyNote {
                FrequencyNoteView(frequencyHz: presenter.targetFrequencyHz)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: presenter.showFrequencyNote)
        .allowsHitTesting(showRolePopup || presenter.showFrequencyNote)
    }
}

// MARK: - Phase 8A Frequency Note

/// A 2D note the Seer cannot dismiss — they must shout the number to the Listener.
struct FrequencyNoteView: View {
    let frequencyHz: Double

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "waveform")
                    .font(.system(size: 36))
                    .foregroundStyle(.yellow)

                Text("Ancient Note")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.6))
                    .textCase(.uppercase)
                    .tracking(2)

                Text(formattedFrequency)
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundStyle(.yellow)
                    .shadow(color: .yellow.opacity(0.4), radius: 12)

                Text("Shout this number to your partner.\nYou cannot close this note.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(36)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.black.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(.yellow.opacity(0.4), lineWidth: 1.5)
                    )
            )
            .padding(.horizontal, 28)
        }
    }

    private var formattedFrequency: String {
        if frequencyHz.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(frequencyHz)) Hz"
        }
        return String(format: "%.1f Hz", frequencyHz)
    }
}
