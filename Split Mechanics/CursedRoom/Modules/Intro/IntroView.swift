import SwiftUI

struct IntroView: View {

    let playIntroAnimation: Bool
    let onStartInvestigation: () -> Void

    // MARK: - Animation State

    /// Tracks which phase the intro is in.
    private enum Phase: Int, Comparable {
        case intro = 0      // Title fades in over video
        case animating = 1  // Text is sliding upward
        case menu = 2       // Final main menu state

        static func < (lhs: Phase, rhs: Phase) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    @State private var phase: Phase = .intro
    @State private var titleOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var lightsOffOpacity: Double = 0
    @State private var menuContentOpacity: Double = 0
    @State private var titleOffset: CGFloat = 0
    @State private var textGroupOffset: CGFloat = 0
    @State private var buttonOpacity: Double = 0

    init(playIntroAnimation: Bool = true, onStartInvestigation: @escaping () -> Void) {
        self.playIntroAnimation = playIntroAnimation
        self.onStartInvestigation = onStartInvestigation
    }

    var body: some View {
        ZStack {
            // Looping video background - stops looping when main menu comes up
            VideoPlayerBackground(
                resourceName: "background",
                fileExtension: "mp4",
                overlayOpacity: 0.35,
                isLooping: phase < .menu
            )

            // Content layers
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: phase == .menu ? proxy.size.height * 0.48 : proxy.size.height * 0.48)

                    // Title group — starts centered, ends near top.
                    titleGroup
                        .offset(y: titleOffset)

                    subtitleGroup
                        .frame(height: phase >= .animating ? 60 : 0)
                        .clipped()
                        .opacity(subtitleOpacity)
                        .offset(y: textGroupOffset)

                    Spacer()
                        .frame(minHeight: phase >= .animating ? 24 : 0)

                    requirementsPanel
                        .padding(.horizontal, 20)
                        .frame(height: phase >= .animating ? nil : 0)
                        .clipped()
                        .opacity(menuContentOpacity)
                        .offset(y: menuContentOpacity > 0 ? 0 : 30)

                    Spacer()
                        .frame(minHeight: phase == .menu ? 28 : (phase == .animating ? 80 : 0))

                    Button(action: onStartInvestigation) {
                        Text("Start Investigation")
                    }
                    .buttonStyle(GhostPrimaryButtonStyle())
                    .padding(.horizontal, 36)
                    .padding(.bottom, phase == .menu ? 42 : 0)
                    .frame(height: phase == .menu ? nil : 0)
                    .clipped()
                    .opacity(buttonOpacity)
                    .offset(y: buttonOpacity > 0 ? 0 : 20)
                }
                .frame(width: proxy.size.width)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if playIntroAnimation {
                startIntroSequence()
            } else {
                showMenuImmediately()
            }
        }
    }

    // MARK: - Title Group

    private var titleGroup: some View {
        VStack(spacing: 8) {
            Text("GHOST HUNT")
                .ghostHuntTitleStyle(size: 34)
                .opacity(titleOpacity)

            if phase >= .animating {
                Text("CO-OP AR INVESTIGATION")
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .foregroundStyle(Color.ghostWhite.opacity(0.65))
                    .tracking(3)
                    .opacity(subtitleOpacity)
            }
        }
    }

    // MARK: - Subtitle Group ("Lights off. Headphones on.")

    private var subtitleGroup: some View {
        VStack(spacing: 14) {
            // New Divider: [Line] ◆ [Line]
            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color.ghostWhite.opacity(0.2))
                    .frame(width: 80, height: 1)

                Rectangle()
                    .fill(Color.ghostRedBright)
                    .frame(width: 6, height: 6)
                    .rotationEffect(.degrees(45))

                Rectangle()
                    .fill(Color.ghostWhite.opacity(0.2))
                    .frame(width: 80, height: 1)
            }
            .padding(.top, 16)

            HStack(spacing: 4) {
                Text("Lights off.")
                    .foregroundStyle(Color.ghostWhite.opacity(0.6))
                Text("Headphones on.")
                    .foregroundStyle(Color.ghostRedBright)
            }
            .font(.system(size: 13, weight: .medium, design: .serif).italic())
            .opacity(lightsOffOpacity)
        }
    }

    // MARK: - Requirements Row

    private var requirementsPanel: some View {
        HStack(spacing: 0) {
            requirementCard(icon: "person.2.fill", title: "2 PLAYERS", subtitle: "You depend on\neach other.")
            
            verticalDivider
            
            requirementCard(icon: "location.fill.viewfinder", title: "REAL WORLD", subtitle: "Move around to\nfind clues.")
            
            verticalDivider
            
            requirementCard(icon: "headphones", title: "HEADPHONES", subtitle: "Every sound\nmatters.")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.ghostGold.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(Color.ghostWhite.opacity(0.15))
            .frame(width: 1, height: 50)
    }

    private func requirementCard(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(Color.ghostWhite.opacity(0.78))

            Text(title)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(Color.ghostGold)
                .tracking(0.5)
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(Color.ghostGray)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Animation Sequence

    private func startIntroSequence() {
        // Phase 1: Fade in the title over the video
        withAnimation(.easeIn(duration: 1.5)) {
            titleOpacity = 1.0
        }

        // After 2.5s, begin Phase 2 (Subtitle and requirements box fade in + layout expands)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 1.2)) {
                phase = .animating
                subtitleOpacity = 1.0
            }

            // Fade in "Lights off" text
            withAnimation(.easeIn(duration: 0.8).delay(0.3)) {
                lightsOffOpacity = 1.0
            }

            // After subtitle is visible, slide everything up to menu position and show button
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeInOut(duration: 1.5)) {
                    phase = .menu
                    titleOffset = -86
                    textGroupOffset = -76
                    menuContentOpacity = 1.0
                }

                // Transition button opacity with delay, matching layout travel
                withAnimation(.easeIn(duration: 0.8).delay(0.8)) {
                    buttonOpacity = 1.0
                }
            }
        }
    }

    private func showMenuImmediately() {
        phase = .menu
        titleOpacity = 1
        subtitleOpacity = 1
        lightsOffOpacity = 1
        menuContentOpacity = 1
        titleOffset = -86
        textGroupOffset = -76
        buttonOpacity = 1
    }
}

// MARK: - Preview

#Preview {
    IntroView(onStartInvestigation: {})
}
