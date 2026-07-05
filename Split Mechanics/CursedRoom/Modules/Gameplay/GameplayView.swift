//
//  GameplayView.swift
//  The Cursed Room
//
//  Phase 6A — routes the AR camera feed to role-specific overlays once the
//  Host syncs Seer / Listener assignment over the network.
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
        }
        .sheet(isPresented: $presenter.showLetterSheet) {
            LetterSheetView()
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
                SeerView()
            case .listener:
                ListenerView()
            case .unassigned:
                assigningOverlay
            }

            if presenter.viewModel.isRoleResolved && !presenter.isLetterSpawned {
                huntStatusBanner
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

// MARK: - Letter Sheet

struct LetterSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("📜 Hidden Letter")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Hello")
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