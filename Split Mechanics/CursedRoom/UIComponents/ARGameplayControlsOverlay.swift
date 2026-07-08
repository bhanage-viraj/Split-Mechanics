//
//  ARGameplayControlsOverlay.swift
//  The Cursed Room
//
//  AR gameplay controls: leading items via toolbar(content:), role-specific glass tool stack mid-trailing.
//

import SwiftUI

struct ARGameplayControlsOverlay: View {
    let playerRole: PlayerRole
    @Binding var isFlashlightOn: Bool

    init(playerRole: PlayerRole = .seer, isFlashlightOn: Binding<Bool> = .constant(false)) {
        self.playerRole = playerRole
        _isFlashlightOn = isFlashlightOn
    }

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets

            toolButtons
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, insets.trailing + 16)
        }
        .ignoresSafeArea()
        .toolbar(content: toolbarContent)
    }

    @ViewBuilder
    private var toolButtons: some View {
        VStack(spacing: 14) {
            switch playerRole {
            case .seer:
                

                flashlightButton

                ARGlassToolButton(
                    systemName: "circle.lefthalf.filled",
                    iconColor: Color(red: 0.82, green: 0.68, blue: 0.42),
                    accessibilityLabel: "Left seal"
                ) {
                    print("[ARGameplayControls] Left seal tapped")
                }

                ARGlassToolButton(
                    systemName: "circle.righthalf.filled",
                    iconColor: Color(red: 0.82, green: 0.68, blue: 0.42),
                    accessibilityLabel: "Right seal"
                ) {
                    print("[ARGameplayControls] Right seal tapped")
                }

            case .listener:
                flashlightButton

                ARGlassToolButton(
                    systemName: "sensor",
                    iconColor: .white,
                    accessibilityLabel: "Sensor"
                ) {
                    print("[ARGameplayControls] Sensor tapped")
                }

            case .unassigned:
                EmptyView()
            }
        }
    }

    private var flashlightButton: some View {
        ARGlassToolButton(
            systemName: isFlashlightOn ? "flashlight.on.fill" : "flashlight.slash",
            iconColor: .white,
            accessibilityLabel: isFlashlightOn ? "Flashlight on" : "Flashlight off"
        ) {
            isFlashlightOn.toggle()
            print("[ARGameplayControls] Flashlight tapped -> \(isFlashlightOn ? "on" : "off")")
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Menu", systemImage: "line.3.horizontal") {
                print("[ARGameplayControls] Menu tapped")
            }
        }

        ToolbarSpacer(.fixed, placement: .topBarLeading)

        ToolbarItem(placement: .topBarLeading) {
            Button("Info", systemImage: "info.circle") {
                print("[ARGameplayControls] Info tapped")
            }
        }
    }
}

// MARK: - Glass tool button

private struct ARGlassToolButton: View {
    let systemName: String
    let iconColor: Color
    let accessibilityLabel: String
    let action: () -> Void

    private let size: CGFloat = 50
    private let cornerRadius: CGFloat = 18

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: size, height: size)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: cornerRadius))
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Test harness

struct ARGameplayControlsTestScreen: View {
    @State private var previewRole: PlayerRole = .seer
    @State private var isFlashlightOn = false

    var body: some View {
        ZStack {
            Group {
                if isFlashlightOn {
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.14, blue: 0.18),
                            Color(red: 0.06, green: 0.07, blue: 0.09)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    Color.black
                }
            }
            .ignoresSafeArea()

            ARGameplayControlsOverlay(
                playerRole: previewRole,
                isFlashlightOn: $isFlashlightOn
            )

            VStack {
                Picker("Role", selection: $previewRole) {
                    Text("Seer").tag(PlayerRole.seer)
                    Text("Listener").tag(PlayerRole.listener)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Spacer()
            }
        }
        .navigationTitle("AR Controls")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

#Preview("Seer Layout") {
    NavigationStack {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.14, blue: 0.18),
                    Color(red: 0.06, green: 0.07, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ARGameplayControlsOverlay(playerRole: .seer, isFlashlightOn: .constant(true))
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

#Preview("Listener Layout") {
    NavigationStack {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.14, blue: 0.18),
                    Color(red: 0.06, green: 0.07, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ARGameplayControlsOverlay(playerRole: .listener, isFlashlightOn: .constant(true))
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
