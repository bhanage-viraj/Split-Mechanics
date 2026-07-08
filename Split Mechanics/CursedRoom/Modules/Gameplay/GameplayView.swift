//
//  GameplayView.swift
//  The Cursed Room
//
//  Phase 7 — keypad overlay for the Seer to enter the blood pool code.
//

import SwiftUI

struct GameplayView: View {
    @ObservedObject private var presenter: GameplayPresenter

    init(presenter: GameplayPresenter) {
        self.presenter = presenter
    }

    var body: some View {
        ZStack {
            backgroundLayer
            roleOverlay
            keypadOverlay
        }
        .sheet(isPresented: $presenter.showLetterSheet) {
            LetterSheetView {
                presenter.dismissLetterAndBeginPhase7()
            }
        }
        .onAppear {
            presenter.onAppear()
        }
        .onDisappear { presenter.onDisappear() }
    }

    // MARK: - Layers

    @ViewBuilder
    private var backgroundLayer: some View {
        if presenter.viewModel.isRoleResolved {
            ARViewContainer(arView: presenter.arView)
                .blur(radius: presenter.viewModel.playerRole == .listener ? 20 : 0)
                .ignoresSafeArea()
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
                SeerView(presenter: presenter)
            case .listener:
                ListenerView(presenter: presenter)
            case .unassigned:
                assigningOverlay
            }

            if presenter.viewModel.isRoleResolved && !presenter.isLetterSpawned {
                huntStatusBanner
                    .allowsHitTesting(false)
            }

            if presenter.sealsCollected > 0 {
                sealProgressBanner
                    .allowsHitTesting(false)
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
    let onDone: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()

                Text("📜 Hidden Letter")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Follow the trail…")
                    .font(.title)
                    .foregroundStyle(.primary)

                Spacer()

                Button("Done") {
                    onDone()
                }
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
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .navigationTitle("Clue")
        }
    }
}
