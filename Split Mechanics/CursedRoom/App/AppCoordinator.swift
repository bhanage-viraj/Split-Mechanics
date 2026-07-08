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
/// Currently drives: Intro/Main Menu → Lobby → Scanning (Host) / Waiting (Guest) → Game
@MainActor
final class AppCoordinator: ObservableObject {
    // MARK: - Published Navigation State
    enum Screen: Equatable {
        case intro
        case lobby
        case scanning     // Phase 3 — Host scans with RoomPlan, Guest waits
        case seance       // Phase 4 — shared AR, worlds merge, doll appears
        case curseBegins  // Phase 5 — black transition after the doll is touched
        case gameplay     // Phase 6 — role assignment & investigation
    }

    @Published var currentScreen: Screen = .intro
    @Published private var hasPlayedIntro = false

    // MARK: - Shared Services
    private let networkService: NetworkService

    // MARK: - Scanning VIPER (Host only). Created on demand and torn down before
    // the seance so RoomPlan releases the camera for the AR session (otherwise the
    // Host's camera passthrough stays black while it still holds the capture).
    private let scanningRouter = ScanningRouter()
    private var roomScanService: RoomScanService?
    private var scanningInteractor: ScanningInteractor?
    private var scanningPresenter: ScanningPresenter?

    // MARK: - Seance VIPER (Phase 4 — both devices run the collaborative AR view)
    private lazy var arService = ARService()
    private lazy var seanceRouter = SeanceRouter()
    private lazy var seanceInteractor = SeanceInteractor(
        arService: arService,
        networkService: networkService
    )
    private lazy var seancePresenter: SeancePresenter = {
        let presenter = SeancePresenter(interactor: seanceInteractor)
        seanceInteractor.setRouter(seanceRouter)
        return presenter
    }()

    // MARK: - Gameplay VIPER (Phase 6 — role assignment & UI impairment)
    private lazy var gameplayRouter = GameplayRouter()
    private lazy var gameplayInteractor = GameplayInteractor(
        arService: arService,
        networkService: networkService
    )
    private lazy var gameplayPresenter: GameplayPresenter = {
        let presenter = GameplayPresenter(interactor: gameplayInteractor)
        gameplayInteractor.setRouter(gameplayRouter)
        return presenter
    }()

    // MARK: - Cancellables
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        self.networkService = NetworkService()

        bindLobbyNavigation()
        bindScanningNavigation()
        bindSeanceNavigation()
    }

    // MARK: - Lobby Navigation

    /// Keeps later game phases from hanging around after a disconnect. Connection
    /// itself stays in the lobby so the connected-ready screen can be shown first.
    private func bindLobbyNavigation() {
        networkService.$state
            .map { $0 == .disconnected }
            .removeDuplicates()
            .sink { [weak self] isDisconnected in
                guard let self else { return }
                if isDisconnected, self.currentScreen != .intro, self.hasPlayedIntro {
                    self.releaseScanningStack()
                    self.transition(to: .lobby)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Scanning Stack Lifecycle

    /// Builds the RoomPlan scanning VIPER stack (Host only).
    private func startHostScanning() {
        guard roomScanService == nil else { return }
        let service = RoomScanService()
        let interactor = ScanningInteractor(roomScanService: service)
        let presenter = ScanningPresenter(interactor: interactor)
        presenter.setRouter(scanningRouter)
        roomScanService = service
        scanningInteractor = interactor
        scanningPresenter = presenter
    }

    /// Releases RoomPlan (and its `RoomCaptureView`) so the camera is freed for AR.
    private func releaseScanningStack() {
        roomScanService?.teardown()
        scanningPresenter = nil
        scanningInteractor = nil
        roomScanService = nil
    }

    // MARK: - Scanning → Seance Handoff (Phase 3 → Phase 4)

    private func bindScanningNavigation() {
        // Host finishes the RoomPlan scan → tell the Guest, then both move to the
        // shared AR seance together.
        scanningRouter.$shouldStartGame
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                guard let self else { return }
                self.networkService.send(.beginSeance())
                // Release RoomPlan's camera before the AR session takes over.
                self.releaseScanningStack()
                self.transition(to: .seance)
            }
            .store(in: &cancellables)

        // Guest receives the "begin seance" cue from the Host.
        networkService.eventPublisher
            .filter { $0.eventType == NetworkEvent.EventType.beginSeance.rawValue }
            .sink { [weak self] _ in
                guard let self, self.currentScreen != .seance else { return }
                self.transition(to: .seance)
            }
            .store(in: &cancellables)

        // Guest receives the "start investigation" cue from the Host after the
        // connected lobby screen. Host calls `startInvestigationFromLobby()`
        // locally from the Continue button.
        networkService.eventPublisher
            .filter { $0.eventType == NetworkEvent.EventType.startScanning.rawValue }
            .sink { [weak self] _ in
                guard let self else { return }
                self.transition(to: .scanning)
            }
            .store(in: &cancellables)
    }

    // MARK: - Seance → Gameplay (doll touched by either player)

    private func bindSeanceNavigation() {
        seanceRouter.$shouldShowPhase5
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                guard let self else { return }
                self.seanceInteractor.prepareForGameplayHandoff()
                self.transition(to: .curseBegins)
            }
            .store(in: &cancellables)
    }

    // MARK: - Screen Factory

    @ViewBuilder
    func makeScreen() -> some View {
        switch currentScreen {
        case .intro:
            IntroView(
                playIntroAnimation: !hasPlayedIntro,
                onStartInvestigation: { [self] in
                    hasPlayedIntro = true
                    transition(to: .lobby)
                }
            )
        case .lobby:
            LobbyView(
                networkService: networkService,
                onBackToMenu: { [self] in
                    networkService.disconnect()
                    hasPlayedIntro = true
                    transition(to: .intro)
                },
                onStartInvestigation: { [self] in
                    startInvestigationFromLobby()
                }
            )
        case .scanning:
            // Only the Host scans the room with RoomPlan. The Guest waits.
            if let scanningPresenter, networkService.role == .host {
                ScanningView(presenter: scanningPresenter)
            } else {
                WaitingForHostView()
            }
        case .seance:
            // Both devices run the collaborative AR view.
            SeanceView(presenter: seancePresenter)
        case .curseBegins:
            CurseBeginsView { [self] in
                transition(to: .gameplay)
            }
        case .gameplay:
            GameplayView(presenter: gameplayPresenter)
        }
    }

    // MARK: - Transitions

    private func startInvestigationFromLobby() {
        if networkService.role == .host {
            startHostScanning()
        }
        transition(to: .scanning)
    }

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
