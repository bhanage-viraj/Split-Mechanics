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

                        Text("Speak the name from the riddle")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 32)

                    TextField("Answer", text: $presenter.enteredAnswer)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { presenter.submitCurrentAnswer() }
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(.white.opacity(0.45), lineWidth: 1.5)
                                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08)))
                        )
                        .padding(.horizontal, 32)

                    if let error = presenter.keypadErrorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    KeypadActionButton(title: "Unlock") {
                        presenter.submitCurrentAnswer()
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 8)

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

// MARK: - Unlock Button

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
