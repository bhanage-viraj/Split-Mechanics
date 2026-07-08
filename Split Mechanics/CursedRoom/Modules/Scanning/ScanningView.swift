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
    let onCancel: () -> Void

    init(presenter: ScanningPresenter, onCancel: @escaping () -> Void = {}) {
        self.presenter = presenter
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            RoomCaptureContainer(roomCaptureView: presenter.roomCaptureView)
                .ignoresSafeArea()

            if presenter.showBeforeYouBegin {
                // "Before You Begin" popup overlay
                Color.black.opacity(0.4)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top bar with back button
                    HStack {
                        Button(action: onCancel) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle()
                                        .fill(Color.ghostSurface.opacity(0.6))
                                )
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                    Spacer()

                    // Guidelines Card
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Before You Begin")
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundStyle(Color.ghostWhite)
                            .padding(.bottom, 8)

                        BeforeYouBeginGuidelineRow(
                            iconName: "headphones",
                            title: "Wear headphones",
                            subtitle: "For the best immersive experience."
                        )

                        BeforeYouBeginGuidelineRow(
                            iconName: "house.fill",
                            title: "Play indoors",
                            subtitle: "In a dark and quiet environment."
                        )

                        BeforeYouBeginGuidelineRow(
                            iconName: "doc.text",
                            title: "Follow instructions",
                            subtitle: "On-screen guidance will lead the way."
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.black.opacity(0.45))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 28)

                    Spacer()

                    // Scan the Space Button
                    Button(action: {
                        presenter.startScanningClicked()
                    }) {
                        Text("Scan the Space")
                    }
                    .buttonStyle(GhostSecondaryButtonStyle())
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
                }
            } else {
                // Actual scanning UI overlay
                VStack {
                    topStatusSection
                    Spacer()
                    bottomControlSection
                }
                .padding()
            }
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

// MARK: - Guidelines Row Helper

struct BeforeYouBeginGuidelineRow: View {
    let iconName: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 20))
                .foregroundStyle(Color.ghostWhite)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.ghostWhite)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ghostWhite.opacity(0.6))
            }
            Spacer()
        }
    }
}
