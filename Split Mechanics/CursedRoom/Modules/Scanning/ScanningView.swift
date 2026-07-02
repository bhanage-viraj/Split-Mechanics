//
//  ScanningView.swift
//  The Cursed Room
//
//  RoomPlan-based room scanning UI (Host only).
//

import RoomPlan
import SwiftUI

// MARK: - RoomPlan container

struct RoomCaptureContainer: UIViewRepresentable {
    let roomCaptureView: RoomCaptureView

    func makeUIView(context: Context) -> RoomCaptureView {
        roomCaptureView
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}

// MARK: - ScanningView

struct ScanningView: View {
    @ObservedObject private var presenter: ScanningPresenter

    init(presenter: ScanningPresenter) {
        self.presenter = presenter
    }

    var body: some View {
        ZStack {
            RoomCaptureContainer(roomCaptureView: presenter.roomCaptureView)
                .ignoresSafeArea()

            VStack {
                topStatusSection
                Spacer()
                bottomControlSection
            }
            .padding()
        }
        .onAppear { presenter.onAppear() }
        .alert(
            "Scan Error",
            isPresented: Binding(
                get: { presenter.viewModel.errorMessage != nil },
                set: { _ in }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(presenter.viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Top Status

    private var topStatusSection: some View {
        VStack(spacing: 4) {
            Text(presenter.viewModel.title)
                .font(.title2.bold())
                .foregroundStyle(presenter.viewModel.canStartGame ? .green : .white)

            Text(presenter.viewModel.subtitle)
                .font(.subheadline)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.top, 16)
    }

    // MARK: - Bottom Controls

    private var bottomControlSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                benchmarkCard(icon: "square.split.bottomrightquarter", label: "Walls", value: "\(presenter.viewModel.wallCount)", color: .purple)
                benchmarkCard(icon: "door.left.hand.closed", label: "Doors", value: "\(presenter.viewModel.doorCount)", color: .cyan)
                benchmarkCard(icon: "window.vertical.closed", label: "Windows", value: "\(presenter.viewModel.windowCount)", color: .teal)
                benchmarkCard(icon: "sofa", label: "Objects", value: "\(presenter.viewModel.objectCount)", color: .orange)
            }

            Button(action: presenter.primaryAction) {
                HStack {
                    if presenter.viewModel.isProcessing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: presenter.viewModel.isScanning ? "stop.circle.fill" : "play.circle.fill")
                    }
                    Text(presenter.viewModel.primaryButtonTitle)
                        .fontWeight(.semibold)
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(buttonColor)
                )
            }
            .disabled(!presenter.viewModel.primaryButtonEnabled)
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 24)
    }

    private var buttonColor: Color {
        if !presenter.viewModel.primaryButtonEnabled { return Color.gray.opacity(0.4) }
        if presenter.viewModel.canStartGame { return .green }
        if presenter.viewModel.isScanning { return .red }
        return .blue
    }

    private func benchmarkCard(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.gray)
            Text(value)
                .font(.headline.bold())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
