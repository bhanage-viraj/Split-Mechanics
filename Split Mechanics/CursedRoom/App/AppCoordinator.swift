//
//  AppCoordinator.swift
//  The Cursed Room
//
//  Created by Viraj Bhanage on 2/7/26.
//

import SwiftUI
import Combine

/// Root coordinator that owns the navigation state machine for all game phases.
///
/// Currently drives: Lobby → Scanning (Host) / Waiting (Guest) → Game
@MainActor
final class AppCoordinator: ObservableObject {
    // MARK: - Published Navigation State
    enum Screen: Equatable {
        case lobby
        case scanning
        case game
    }

    @Published var currentScreen: Screen = .lobby

    // MARK: - Shared Services
    private let networkService: NetworkService

    // MARK: - Scanning VIPER (Host only — lazily created so the Guest, which may
    // not support RoomPlan, never instantiates the RoomCaptureView).
    private lazy var roomScanService = RoomScanService()
    private lazy var scanningInteractor = ScanningInteractor(roomScanService: roomScanService)
    private lazy var scanningRouter = ScanningRouter()
    private lazy var scanningPresenter: ScanningPresenter = {
        let presenter = ScanningPresenter(interactor: scanningInteractor)
        presenter.setRouter(scanningRouter)
        return presenter
    }()

    // MARK: - Cancellables
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        self.networkService = NetworkService()

        bindLobbyNavigation()
        bindScanningNavigation()
    }

    // MARK: - Lobby Navigation

    /// Drives navigation directly from the shared `NetworkService` state so the
    /// Lobby's own VIPER stack doesn't need to be re-wired into the coordinator.
    /// - Becoming `.connected` from the lobby advances the Host to Scanning.
    /// - Any disconnect returns to the lobby from wherever we are.
    private func bindLobbyNavigation() {
        networkService.$state
            .map { $0 == .connected }
            .removeDuplicates()
            .sink { [weak self] isConnected in
                guard let self else { return }
                if isConnected {
                    if self.currentScreen == .lobby {
                        self.transition(to: .scanning)
                    }
                } else {
                    self.transition(to: .lobby)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Scanning Navigation

    private func bindScanningNavigation() {
        scanningRouter.$shouldStartGame
            .removeDuplicates()
            .sink { [weak self] shouldStart in
                if shouldStart {
                    self?.transition(to: .game)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Screen Factory

    @ViewBuilder
    func makeScreen() -> some View {
        switch currentScreen {
        case .lobby:
            LobbyView(networkService: networkService)
        case .scanning:
            // Only the Host scans the room with RoomPlan. The Guest waits.
            if networkService.role == .guest {
                WaitingForHostView()
            } else {
                ScanningView(presenter: scanningPresenter)
            }
        case .game:
            GameStartView(room: scanningRouter.capturedRoom)
        }
    }

    // MARK: - Transitions

    private func transition(to screen: Screen) {
        withAnimation(.easeInOut(duration: 0.4)) {
            currentScreen = screen
        }
    }
}

// MARK: - Waiting For Host (Guest view during scanning)

struct WaitingForHostView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.4)

                Image(systemName: "camera.metering.matrix")
                    .font(.system(size: 44))
                    .foregroundStyle(.cyan)

                Text("Waiting for Host")
                    .font(.title.bold())
                    .foregroundStyle(.white)

                Text("The host is scanning the room.\nHold tight — you'll join once the map is ready.")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }
}

// MARK: - Game Start (after scan is stored)

struct GameStartView: View {
    let room: ScannedRoom?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)

                Text("Room Captured")
                    .font(.title.bold())
                    .foregroundStyle(.white)

                if let room {
                    Text(room.summary)
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                } else {
                    Text("No room data available.")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }

                Text("Coordinates stored — the game starts from here.")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - AppCoordinatorView (Root SwiftUI View)

struct AppCoordinatorView: View {
    @StateObject private var coordinator = AppCoordinator()

    var body: some View {
        coordinator.makeScreen()
    }
}

#Preview {
    AppCoordinatorView()
}
