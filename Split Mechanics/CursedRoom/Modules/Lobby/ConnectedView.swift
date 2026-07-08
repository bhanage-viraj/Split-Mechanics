//
//  ConnectedView.swift
//  The Cursed Room
//
//  Shown when both players are connected — displays two player avatars,
//  "Both investigators are ready!", and Continue (host) or Exit (guest) button.
//

import SwiftUI

struct ConnectedView: View {

    let playerName: String
    let peerName: String
    let isHost: Bool
    let onContinue: () -> Void
    let onExit: () -> Void

    @State private var linkScale: CGFloat = 0.5
    @State private var linkOpacity: Double = 0
    @State private var avatarsOpacity: Double = 0
    @State private var messageOpacity: Double = 0

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
                // Top bar
                HStack {
                    Button(action: onExit) {
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

                Text("CONNECTED")
                    .font(.system(size: 23, weight: .bold, design: .serif))
                    .foregroundStyle(Color.ghostGold)
                    .tracking(3)
                    .padding(.top, 8)

                // Player badge
                PlayerBadge(name: playerName)
                    .padding(.top, 8)

                gothicDivider
                    .padding(.top, 20)

                Spacer()

                VStack(spacing: 0) {
                    HStack(spacing: 26) {
                        playerAvatar(name: playerName)

                        Image(systemName: "link")
                            .font(.system(size: 31, weight: .semibold))
                            .foregroundStyle(Color.ghostRedBright)
                            .scaleEffect(linkScale)
                            .opacity(linkOpacity)

                        playerAvatar(name: peerName)
                    }
                    .opacity(avatarsOpacity)

                    Text("Both investigators are ready!")
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundStyle(Color.ghostGold)
                        .padding(.top, 28)
                        .opacity(messageOpacity)

                    Text(isHost ? "The investigation can now continue." : "Wait for the Host to start the investigation.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.ghostWhite.opacity(0.58))
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                        .opacity(messageOpacity)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 288)
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

                if isHost {
                    Button(action: onContinue) {
                        Text("Continue")
                    }
                    .buttonStyle(GhostPrimaryButtonStyle())
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
                    .opacity(messageOpacity)
                } else {
                    Button(action: onExit) {
                        Text("Exit")
                    }
                    .buttonStyle(GhostDangerButtonStyle())
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
                    .opacity(messageOpacity)
                }
            }
        }
        .onAppear {
            // Animate entrance
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
                linkScale = 1.0
                linkOpacity = 1.0
            }
            withAnimation(.easeIn(duration: 0.6).delay(0.5)) {
                avatarsOpacity = 1.0
            }
            withAnimation(.easeIn(duration: 0.5).delay(0.9)) {
                messageOpacity = 1.0
            }
        }
    }

    // MARK: - Player Avatar

    private func playerAvatar(name: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                // Outer glow ring
                Circle()
                    .stroke(Color.ghostRedBright.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 72, height: 72)

                // Avatar circle
                Image(systemName: "person.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.ghostRedBright)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle()
                            .fill(Color.ghostRedBright.opacity(0.12))
                    )
            }

            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.ghostGray)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 86)
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
    ConnectedView(
        playerName: "SquidxGhost",
        peerName: "Friend_1",
        isHost: true,
        onContinue: {},
        onExit: {}
    )
}
