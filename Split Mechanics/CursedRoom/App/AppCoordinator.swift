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
        case transitionVideo
        case storyIntro
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
                self.transition(to: .transitionVideo)
            }
            .store(in: &cancellables)

        // Guest receives the "begin seance" cue from the Host.
        networkService.eventPublisher
            .filter { $0.eventType == NetworkEvent.EventType.beginSeance.rawValue }
            .sink { [weak self] _ in
                guard let self, self.currentScreen != .transitionVideo else { return }
                self.transition(to: .transitionVideo)
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
                ScanningView(presenter: scanningPresenter, onCancel: { [self] in
                    networkService.disconnect()
                    releaseScanningStack()
                    transition(to: .lobby)
                })
            } else {
                WaitingForHostView(
                    playerName: UIDevice.current.name,
                    hostName: networkService.connectedPeerName.isEmpty ? "Host" : networkService.connectedPeerName,
                    onExit: { [self] in
                        networkService.disconnect()
                        transition(to: .lobby)
                    }
                )
            }
        case .transitionVideo:
            TransitionVideoView(onFinished: { [self] in
                transition(to: .storyIntro)
            })
        case .storyIntro:
            StoryIntroView(
                onFinished: { [self] in
                    transition(to: .seance)
                },
                onBack: { [self] in
                    networkService.disconnect()
                    transition(to: .lobby)
                }
            )
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
    let playerName: String
    let hostName: String
    let onExit: () -> Void

    @State private var hourglassRotation: Double = 0

    var body: some View {
        ZStack {
            VideoPlayerBackground(
                resourceName: "background2",
                fileExtension: "mov",
                overlayOpacity: 0.62,
                isLooping: false,
                showsLastFrameOnly: true
            )

            VStack(spacing: 0) {
                // Top bar (No back button)
                HStack {
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                SectionLabel(text: "Lobby")
                    .padding(.top, 46)

                diamondDivider
                    .padding(.top, 14)

                HStack(spacing: 8) {
                    Text("ROOM")
                        .font(.system(size: 19, weight: .bold, design: .serif))
                        .foregroundStyle(Color.ghostGold)
                        .tracking(2)

                    Text("SCANNING")
                        .redAccentStyle(size: 19, italic: true)
                        .tracking(2)
                }
                .padding(.top, 14)

                // Player badge
                PlayerBadge(name: playerName)
                    .padding(.top, 8)

                gothicDivider
                    .padding(.top, 24)

                Spacer()

                // Central Card (Height 420 to fit all text and guidelines nicely)
                VStack(spacing: 0) {
                    Spacer()

                    Image(systemName: "hourglass")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(Color.ghostGold)
                        .rotationEffect(.degrees(hourglassRotation))

                    Spacer()
                        .frame(height: 24)

                    Text("Please wait while your partner\nscans the environment.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ghostWhite.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    // Before You Begin Divider
                    HStack {
                        Rectangle()
                            .fill(Color.ghostGold.opacity(0.2))
                            .frame(height: 1)
                        Text("Before You Begin")
                            .font(.system(size: 12, weight: .bold, design: .serif))
                            .foregroundStyle(Color.ghostGold)
                            .tracking(1)
                            .padding(.horizontal, 8)
                        Rectangle()
                            .fill(Color.ghostGold.opacity(0.2))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)

                    // Guidelines
                    VStack(alignment: .leading, spacing: 16) {
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

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 420)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(0.54))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.ghostGold.opacity(0.12), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 28)

                Spacer()

                // Exit button
                Button(action: onExit) {
                    Text("Exit")
                }
                .buttonStyle(GhostDangerButtonStyle())
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            // Slowly rotating hourglass animation
            withAnimation(
                .linear(duration: 8.0)
                .repeatForever(autoreverses: false)
            ) {
                hourglassRotation = 360.0
            }
        }
    }

    private var diamondDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.ghostWhite.opacity(0.18))
                .frame(width: 44, height: 1)

            Rectangle()
                .fill(Color.ghostRedBright)
                .frame(width: 6, height: 6)
                .rotationEffect(.degrees(45))

            Rectangle()
                .fill(Color.ghostWhite.opacity(0.18))
                .frame(width: 44, height: 1)
        }
    }

    private var gothicDivider: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.ghostRed.opacity(0.55))
                .frame(height: 1)

            Circle()
                .fill(Color.ghostRedBright)
                .frame(width: 8, height: 8)
                .padding(.horizontal, 6)

            Rectangle()
                .fill(Color.ghostRed.opacity(0.55))
                .frame(height: 1)
        }
        .padding(.horizontal, 44)
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
