//
//  CustomModifiers.swift
//  The Cursed Room
//
//  Design system: colors, typography, and reusable button styles matching the
//  Ghost Hunt mockups.
//

import SwiftUI

// MARK: - Color Palette

extension Color {
    /// Deep black background  — `#0A0A0A`
    static let ghostBlack = Color(red: 0.04, green: 0.04, blue: 0.04)
    /// Blood red accent — `#8B0000`
    static let ghostRed = Color(red: 0.545, green: 0.0, blue: 0.0)
    /// Brighter red for text — `#C0392B`
    static let ghostRedBright = Color(red: 0.753, green: 0.224, blue: 0.169)
    /// Gold / cream for titles — `#C8A96E`
    static let ghostGold = Color(red: 0.784, green: 0.663, blue: 0.431)
    /// Muted gray for subtitles — `#888888`
    static let ghostGray = Color(white: 0.53)
    /// Very dark surface — `#111111`
    static let ghostSurface = Color(white: 0.067)
    /// Dim white for body text
    static let ghostWhite = Color(white: 0.92)
}

// MARK: - Title Style Modifier

/// Applies the "GHOST HUNT" serif-style title treatment.
struct GhostHuntTitleStyle: ViewModifier {
    var size: CGFloat = 36

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .bold, design: .serif))
            .foregroundStyle(Color.ghostGold)
            .tracking(4)
    }
}

extension View {
    func ghostHuntTitleStyle(size: CGFloat = 36) -> some View {
        modifier(GhostHuntTitleStyle(size: size))
    }
}

// MARK: - Red Accent Text (for "FRIENDS", "PLAYER", etc.)

struct RedAccentStyle: ViewModifier {
    var size: CGFloat = 28
    var italic: Bool = true

    func body(content: Content) -> some View {
        content
            .font(italic
                ? .system(size: size, weight: .bold, design: .serif).italic()
                : .system(size: size, weight: .bold, design: .serif))
            .foregroundStyle(Color.ghostRedBright)
    }
}

extension View {
    func redAccentStyle(size: CGFloat = 28, italic: Bool = true) -> some View {
        modifier(RedAccentStyle(size: size, italic: italic))
    }
}

// MARK: - Primary Button Style (white fill, dark text — "Start Investigation", "Continue")

struct GhostPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Disabled/Dim Button Style (dark translucent fill)

struct GhostDimButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.7))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.16))
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Secondary Button Style (dark fill, white border — "HOST GAME", "Join Game")

struct GhostSecondaryButtonStyle: ButtonStyle {
    var borderColor: Color = .white.opacity(0.3)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.ghostSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Danger Button Style (red text, dark fill — "Cancel Invitation", "Exit")

struct GhostDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.ghostRedBright)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.ghostRedBright.opacity(0.4), lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Small Capsule Badge (player name pill)

struct PlayerBadge: View {
    let name: String
    var accentColor: Color = .ghostRedBright

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(accentColor.opacity(0.15))
                    .overlay(
                        Capsule()
                            .stroke(accentColor.opacity(0.4), lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - Section Label ("Lobby" red label at top)

struct SectionLabel: View {
    let text: String
    var color: Color = .ghostRedBright

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .tracking(1)
    }
}
