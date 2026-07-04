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
        .onAppear { presenter.onAppear() }
        .onDisappear { presenter.onDisappear() }
    }

    // MARK: - Layers

    /// Phase 6A is role assignment only — no AR feed and no doll. The camera
    /// returns once both devices know Seer vs Listener.
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
