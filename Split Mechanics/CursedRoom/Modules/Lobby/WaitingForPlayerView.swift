//
//  WaitingForPlayerView.swift
//  The Cursed Room
//
//  Shown after the host starts hosting — displays an animated hourglass and
//  "INVITATION SENT" while waiting for a guest to connect.
//

import SwiftUI

struct WaitingForPlayerView: View {

    let playerName: String
    let onCancel: () -> Void

    @State private var hourglassRotation: Double = 0

    var body: some View {
        ZStack {
            VideoPlayerBackground(
                resourceName: "background2",
                fileExtension: "mov",
                overlayOpacity: 0.62,
                isLooping: false,
                showsLastFrameOnly: true
            )

            VStack(spacing: 0) {
                // Top bar with back button
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(Color.ghostSurface.opacity(0.6))
                            )
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                SectionLabel(text: "Lobby")
                    .padding(.top, 46)

                diamondDivider
                    .padding(.top, 14)

                HStack(spacing: 8) {
                    Text("WAITING FOR")
                        .font(.system(size: 19, weight: .bold, design: .serif))
                        .foregroundStyle(Color.ghostGold)
                        .tracking(2)

                    Text("PLAYER")
                        .redAccentStyle(size: 19, italic: true)
                        .tracking(2)
                }
                .padding(.top, 14)

                // Player badge
                PlayerBadge(name: playerName)
                    .padding(.top, 8)

                gothicDivider
                    .padding(.top, 24)

                Spacer()

                VStack(spacing: 0) {
                    Spacer()

                    Image(systemName: "hourglass")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(Color.ghostGold)
                        .rotationEffect(.degrees(hourglassRotation))

                    Spacer()
                        .frame(height: 32)

                    Text("INVITATION SENT")
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .foregroundStyle(Color.ghostGold)
                        .tracking(2.5)

                    Text("Waiting for Player to join")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.ghostWhite.opacity(0.72))
                        .padding(.top, 8)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(0.54))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.ghostGold.opacity(0.12), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 28)

                Spacer()

                // Cancel button
                Button(action: onCancel) {
                    Text("Cancel Invitation")
                }
                .buttonStyle(GhostDangerButtonStyle())
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            // Slowly rotating hourglass animation
            withAnimation(
                .linear(duration: 8.0)
                .repeatForever(autoreverses: false)
            ) {
                hourglassRotation = 360.0
            }
        }
    }

    private var diamondDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.ghostWhite.opacity(0.18))
                .frame(width: 44, height: 1)

            Rectangle()
                .fill(Color.ghostRedBright)
                .frame(width: 6, height: 6)
                .rotationEffect(.degrees(45))

            Rectangle()
                .fill(Color.ghostWhite.opacity(0.18))
                .frame(width: 44, height: 1)
        }
    }

    private var gothicDivider: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.ghostRed.opacity(0.55))
                .frame(height: 1)

            Circle()
                .fill(Color.ghostRedBright)
                .frame(width: 8, height: 8)
                .padding(.horizontal, 6)

            Rectangle()
                .fill(Color.ghostRed.opacity(0.55))
                .frame(height: 1)
        }
        .padding(.horizontal, 44)
    }
}

#Preview {
    WaitingForPlayerView(
        playerName: "SquidxGhost",
        onCancel: {}
    )
}
