//
//  SeanceView.swift
//  The Cursed Room
//
//  Phase 4 UI: the shared AR camera feed plus the seance prompt. The View knows
//  nothing about collaboration data or raycasts — only the presenter's view model.
//

import RealityKit
import SwiftUI

// MARK: - AR container

struct ARViewContainer: UIViewRepresentable {
    let arView: ARView

    func makeUIView(context: Context) -> ARView { arView }
    func updateUIView(_ uiView: ARView, context: Context) {}
}

// MARK: - Seance View

struct SeanceView: View {
    @ObservedObject private var presenter: SeancePresenter

    init(presenter: SeancePresenter) {
        self.presenter = presenter
    }

    var body: some View {
        ZStack {
            ARViewContainer(arView: presenter.arView)
                .ignoresSafeArea()

            VStack {
                promptBanner
                Spacer()
                statusBanner
            }
            .padding()
        }
        .onAppear { presenter.onAppear() }
        .onDisappear { presenter.onDisappear() }
    }

    private var promptBanner: some View {
        Text(presenter.viewModel.prompt)
            .font(.headline)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.black.opacity(0.55))
            )
            .padding(.top, 8)
    }

    private var statusBanner: some View {
        HStack(spacing: 10) {
            if presenter.viewModel.showActivity {
                ProgressView()
                    .tint(.white)
            }
            Text(presenter.viewModel.status)
                .font(.subheadline.monospaced())
                .foregroundStyle(.white)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 18)
        .background(
            Capsule().fill(.black.opacity(0.55))
        )
        .padding(.bottom, 12)
    }
}

// MARK: - Phase 5 placeholder

struct Phase5PlaceholderView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text("The Curse Has Begun")
                .font(.largeTitle.bold())
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding()
        }
    }
}
