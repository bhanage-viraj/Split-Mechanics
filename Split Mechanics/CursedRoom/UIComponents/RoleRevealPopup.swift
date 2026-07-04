//
//  RoleRevealPopup.swift
//  The Cursed Room
//
//  Dismissible modal shown once when a player's role is revealed.
//

import SwiftUI

struct RoleRevealPopup: View {
    let roleTitle: String
    let roleDescription: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 20) {
                Text(roleTitle)
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text(roleDescription)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)

                Button("Got it", action: onDismiss)
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(.white))
            }
            .padding(28)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.black.opacity(0.88))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 32)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}
