import SwiftUI

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
                    slide1View
                        .tag(0)

                    slide2View
                        .tag(1)

                    slide3View
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
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Slide Views

    private var slide1View: some View {
        VStack(spacing: 16) {
            storyImage(name: "hastar_statue", placeholderSymbol: "flame.fill")

            storyTitle

            VStack(alignment: .leading, spacing: 14) {
                Text("Long before humans, the Goddess of Prosperity gave birth to her first child — Hastar. He was greedy beyond measure. He desired all the gold... and all the food... and everything that was never meant to be his.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.ghostWhite.opacity(0.85))
                    .lineSpacing(4)

                Text("The Goddess cursed him and sealed him inside her womb, beneath the earth, never to be worshipped again.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.ghostWhite.opacity(0.85))
                    .lineSpacing(4)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.ghostGold.opacity(0.12), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 28)

            Spacer()
        }
        .padding(.top, 24)
    }

    private var slide2View: some View {
        VStack(spacing: 16) {
            storyImage(name: "hastar_dungeon", placeholderSymbol: "square.split.bottomrightquarter")

            storyTitle

            VStack(spacing: 12) {
                Text("Prologue")
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundStyle(Color.ghostRedBright)
                    .italic()
                    .padding(.bottom, 4)

                Text("Centuries later, a ritual performed by unknown hands weakens the seal. A fragment of Hastar's power escapes and attaches itself to an ordinary place.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.ghostWhite.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                Text("Now, Hastar feeds on greed, divides souls, and turns unity into darkness.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.ghostWhite.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.ghostGold.opacity(0.12), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 28)

            Spacer()
        }
        .padding(.top, 24)
    }

    private var slide3View: some View {
        VStack(spacing: 16) {
            storyImage(name: "hastar_briefing", placeholderSymbol: "person.3.fill")

            storyTitle

            VStack(spacing: 16) {
                Text("Mission Briefing")
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundStyle(Color.ghostRedBright)
                    .italic()
                    .padding(.bottom, 4)

                Text("Work together to investigate the space. Gather clues, solve the mystery, and uncover what is hidden.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.ghostWhite.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 12)

                // 3 Column details
                HStack(spacing: 0) {
                    briefingColumn(icon: "magnifyingglass", title: "Look for\nthe clues")
                    Spacer()
                    briefingColumn(icon: "person.2.fill", title: "Help your\npartner")
                    Spacer()
                    briefingColumn(icon: "lock.fill", title: "Solve\nthe mystery")
                }
                .padding(.top, 8)
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.ghostGold.opacity(0.12), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 28)

            Spacer()
        }
        .padding(.top, 24)
    }

    // MARK: - Subcomponents

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
        .padding(.vertical, 8)
    }

    private func storyImage(name: String, placeholderSymbol: String) -> some View {
        Image(name)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(height: 200)
            .clipped()
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .background(
                // Fallback background if image asset is not present
                LinearGradient(
                    colors: [Color.ghostBlack, Color.ghostRed.opacity(0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .overlay(
                    Image(systemName: placeholderSymbol)
                        .font(.system(size: 40))
                        .foregroundStyle(Color.ghostGold.opacity(0.3))
                )
                .cornerRadius(12)
            )
            .padding(.horizontal, 28)
    }

    private func briefingColumn(icon: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.ghostRedBright)
                .frame(width: 38, height: 38)
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
