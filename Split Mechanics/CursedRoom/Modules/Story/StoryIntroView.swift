import SwiftUI
import UIKit

struct StoryIntroView: View {
    let onFinished: () -> Void
    let onBack: () -> Void

    @State private var currentTab = 0

    var body: some View {
        ZStack {
            Color.ghostBlack.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Navigation Bar
                HStack {
                    Button(action: {
                        if currentTab > 0 {
                            withAnimation {
                                currentTab -= 1
                            }
                        } else {
                            onBack()
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(Color.ghostSurface.opacity(0.6))
                            )
                    }

                    Spacer()

                    // Slide Index
                    Text("\(currentTab + 1)/3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ghostWhite.opacity(0.6))

                    Spacer()

                    if currentTab == 2 {
                        // Checkmark confirm button on slide 3
                        Button(action: onFinished) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle()
                                        .fill(Color.white)
                                )
                        }
                    } else {
                        // Spacer to keep balance
                        Spacer()
                            .frame(width: 40)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                // Divider line with gold and red accents
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.ghostRed.opacity(0.55))
                        .frame(height: 1)

                    Circle()
                        .fill(Color.ghostRedBright)
                        .frame(width: 6, height: 6)
                        .padding(.horizontal, 6)

                    Rectangle()
                        .fill(Color.ghostRed.opacity(0.55))
                        .frame(height: 1)
                }
                .padding(.horizontal, 44)
                .padding(.top, 12)

                // TabView for pages
                TabView(selection: $currentTab) {
                    slideView(index: 0)
                        .tag(0)

                    slideView(index: 1)
                        .tag(1)

                    slideView(index: 2)
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Custom Dot Indicator
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(currentTab == index ? Color.ghostGold : Color.ghostWhite.opacity(0.24))
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private func slideView(index: Int) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                // Image at the top of the card
                let imageName = getImageName(for: index)
                let placeholderSymbol = getPlaceholderSymbol(for: index)
                storyImage(name: imageName, placeholderSymbol: placeholderSymbol)

                // Title
                storyTitle
                    .padding(.top, 16)

                // Internal Divider
                gothicCardDivider
                    .padding(.top, 6)

                // Narrative Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        if index == 0 {
                            Text("Long before humans, the Goddess of Prosperity gave birth to her first child — Hastar. He was greedy beyond measure. He desired all the gold... and all the food... and everything that was never meant to be his.")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Color.ghostWhite.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)

                            Text("The Goddess cursed him and sealed him inside her womb, beneath the earth, never to be worshipped again.")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Color.ghostWhite.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                        } else if index == 1 {
                            Text("Prologue")
                                .font(.system(size: 14, weight: .bold, design: .serif))
                                .foregroundStyle(Color.ghostRedBright)
                                .italic()
                                .padding(.bottom, 4)

                            Text("Centuries later, a ritual performed by unknown hands weakens the seal. A fragment of Hastar's power escapes and attaches itself to an ordinary place.")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Color.ghostWhite.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)

                            Text("Now, Hastar feeds on greed, divides souls, and turns unity into darkness.")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Color.ghostWhite.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                        } else {
                            Text("Mission Briefing")
                                .font(.system(size: 14, weight: .bold, design: .serif))
                                .foregroundStyle(Color.ghostRedBright)
                                .italic()
                                .padding(.bottom, 4)

                            Text("Work together to investigate the space. Gather clues, solve the mystery, and uncover what is hidden.")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Color.ghostWhite.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                                .padding(.bottom, 8)

                            // 3 Column details
                            HStack(spacing: 0) {
                                briefingColumn(icon: "magnifyingglass", title: "Look for\nthe clues")
                                Spacer()
                                briefingColumn(icon: "person.2.fill", title: "Help your\npartner")
                                Spacer()
                                briefingColumn(icon: "lock.fill", title: "Solve\nthe mystery")
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 560)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.ghostGold.opacity(0.12), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func getImageName(for index: Int) -> String {
        switch index {
        case 0: return "hastar_statue"
        case 1: return "hastar_dungeon"
        default: return "hastar_briefing"
        }
    }

    private func getPlaceholderSymbol(for index: Int) -> String {
        switch index {
        case 0: return "flame.fill"
        case 1: return "square.split.bottomrightquarter"
        default: return "person.3.fill"
        }
    }

    private func storyImage(name: String, placeholderSymbol: String) -> some View {
        Group {
            if let uiImage = UIImage(named: name) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Premium Fallback Gradient
                LinearGradient(
                    colors: [Color.ghostBlack, Color.ghostRed.opacity(0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .overlay(
                    Image(systemName: placeholderSymbol)
                        .font(.system(size: 44))
                        .foregroundStyle(Color.ghostGold.opacity(0.4))
                )
            }
        }
        .frame(height: 240)
        .frame(maxWidth: .infinity)
        .clipped()
        .cornerRadius(14, corners: [.topLeft, .topRight])
    }

    private var storyTitle: some View {
        HStack(spacing: 6) {
            Text("THE CURSE OF")
                .font(.system(size: 19, weight: .bold, design: .serif))
                .foregroundStyle(Color.ghostGold)
                .tracking(2)

            Text("HASTAR")
                .redAccentStyle(size: 19, italic: true)
                .tracking(2)
        }
    }

    private var gothicCardDivider: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.ghostRed.opacity(0.45))
                .frame(height: 1)

            Circle()
                .fill(Color.ghostRedBright)
                .frame(width: 5, height: 5)
                .padding(.horizontal, 4)

            Rectangle()
                .fill(Color.ghostRed.opacity(0.45))
                .frame(height: 1)
        }
        .padding(.horizontal, 44)
    }

    private func briefingColumn(icon: String, title: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.ghostRedBright)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Color.ghostRed.opacity(0.15))
                )

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.ghostWhite.opacity(0.72))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 80)
    }
}

// MARK: - View Corners Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
