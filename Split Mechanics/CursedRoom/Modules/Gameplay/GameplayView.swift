//
//  GameplayView.swift
//  The Cursed Room
//
//  Phase 7 — keypad overlay for the Seer to enter the blood pool code.
//

import SwiftUI

struct GameplayView: View {
    @ObservedObject private var presenter: GameplayPresenter
    @State private var isFlashlightOn = false

    init(presenter: GameplayPresenter) {
        self.presenter = presenter
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundLayer
                roleOverlay
                arControlsOverlay
                keypadOverlay
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $presenter.showLetterSheet) {
            LetterSheetView()
        }
        .onAppear {
            presenter.onAppear()
            presenter.setCameraFeedEnabled(isFlashlightOn)
        }
        .onChange(of: isFlashlightOn) { _, enabled in
            presenter.setCameraFeedEnabled(enabled)
        }
        .onDisappear { presenter.onDisappear() }
    }

    // MARK: - Layers

    @ViewBuilder
    private var backgroundLayer: some View {
        if presenter.viewModel.isRoleResolved {
            if isFlashlightOn {
                ARViewContainer(arView: presenter.arView)
                    .blur(radius: presenter.viewModel.playerRole == .listener ? 20 : 0)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
        } else {
            Color.black.ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var roleOverlay: some View {
        if !presenter.viewModel.isRoleResolved {
            assigningOverlay
        } else {
            switch presenter.viewModel.playerRole {
            case .seer:
                SeerView()
            case .listener:
                ListenerView()
            case .unassigned:
                assigningOverlay
            }

            if presenter.viewModel.isRoleResolved && !presenter.isLetterSpawned {
                huntStatusBanner
            }

            if presenter.sealsCollected > 0 {
                sealProgressBanner
            }
        }
    }

    private var huntStatusBanner: some View {
        VStack {
            Spacer()
            Text(presenter.huntStatusMessage)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Capsule().fill(.black.opacity(0.6)))
                .padding(.bottom, 28)
        }
    }

    private var sealProgressBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "seal.fill")
                .foregroundStyle(.blue)
            Text("Seals: \(presenter.sealsCollected)/2")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.black.opacity(0.7), in: Capsule())
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - AR Controls Overlay

    @ViewBuilder
    private var arControlsOverlay: some View {
        if presenter.viewModel.isRoleResolved && !presenter.showCodeKeypad {
            ARGameplayControlsOverlay(
                playerRole: presenter.viewModel.playerRole,
                isFlashlightOn: $isFlashlightOn,
                showLeftSealButton: presenter.showLeftSealButton,
                showRightSealButton: presenter.showRightSealButton
            )
        }
    }

    @ViewBuilder
    private var debugOverlay: some View {
        if presenter.viewModel.isRoleResolved {
            GameplayDebugOverlay(
                lines: presenter.debugStatusLines,
                events: presenter.debugEvents
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 12)
        }
    }

    // MARK: - Code Keypad (Phase 7C)

    @ViewBuilder
    private var keypadOverlay: some View {
        if presenter.showCodeKeypad {
            ZStack {
                Color.black.opacity(0.75)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    VStack(spacing: 8) {
                        Text("A dark pool blocks your path…")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        Text("Enter the 3-digit code")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 32)

                    HStack(spacing: 16) {
                        ForEach(0..<3, id: \.self) { index in
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.5), lineWidth: 2)
                                    .frame(width: 64, height: 80)

                                Text(presenter.enteredDigits.indices.contains(index) ? presenter.enteredDigits[index] : "_")
                                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(.vertical, 8)

                    if let error = presenter.keypadErrorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    VStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { row in
                            HStack(spacing: 12) {
                                ForEach(1...3, id: \.self) { col in
                                    let digit = row * 3 + col
                                    KeypadDigitButton(digit: "\(digit)") {
                                        presenter.appendDigit("\(digit)")
                                    }
                                }
                            }
                        }
                        HStack(spacing: 12) {
                            Spacer()
                            KeypadDigitButton(digit: "0") {
                                presenter.appendDigit("0")
                            }
                            Spacer()
                            KeypadActionButton(title: "Unlock") {
                                presenter.submitCurrentCode()
                            }
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 32)

                    Spacer()
                }
                .padding(.top, 60)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var assigningOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.3)
            Text("The curse is choosing your fate…")
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Keypad Subviews

private struct KeypadDigitButton: View {
    let digit: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(digit)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct KeypadActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline.bold())
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(
                    LinearGradient(
                        colors: [.blue, .blue.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: RoundedRectangle(cornerRadius: 14)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Letter Sheet

struct LetterSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("📜 Hidden Letter")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Follow the trail…")
                    .font(.title)
                    .foregroundColor(.gray)

                Spacer()
            }
            .navigationTitle("Clue")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct GameplayDebugOverlay: View {
    let lines: [String]
    let events: [String]

    var body: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DEBUG")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)

                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(.caption.monospaced())
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !events.isEmpty {
                    Divider()
                        .overlay(.white.opacity(0.18))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("EVENTS")
                            .font(.caption2.bold())
                            .foregroundStyle(.yellow)

                        ForEach(events.reversed(), id: \.self) { event in
                            Text(event)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.white.opacity(0.92))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: 250, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            )

            Spacer()
        }
        .allowsHitTesting(false)
    }
}
