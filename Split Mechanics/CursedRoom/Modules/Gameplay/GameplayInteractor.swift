//
//  GameplayInteractor.swift
//  The Cursed Room
//
//  Phase 6A — assigns Seer / Listener roles and keeps the collaborative AR
//  session alive. Phase 6B — letter hunt with Listener proximity haptics.
//

import ARKit
import Combine
import CoreGraphics
import Foundation
import QuartzCore
import RealityKit

@MainActor
final class GameplayInteractor: ObservableObject {

    @Published private(set) var playerRole: PlayerRole = .unassigned
    @Published private(set) var distanceToLetter: Float?

    let arService: ARService
    private let networkService: NetworkService
    private weak var router: GameplayRouterProtocol?

    private var cancellables = Set<AnyCancellable>()
    private var displayLink: CADisplayLink?
    private let letterHaptics = LetterProximityHaptics()

    private var didAssignRoles = false
    private var didRequestLetterSpawn = false
    private var isProximityLoopActive = false

    init(arService: ARService, networkService: NetworkService) {
        self.arService = arService
        self.networkService = networkService
    }

    func setRouter(_ router: GameplayRouterProtocol) {
        self.router = router
    }

    // MARK: - Lifecycle

    func start() {
        bindCollaboration()
        bindRoleAssignment()
        bindLetterSpawn()
        bindLetterNetworkSync()
        bindLetterProximityLoop()
        assignRolesIfNeeded()
        if playerRole != .unassigned {
            beginLetterHunt()
        }
    }

    func stop() {
        stopListenerProximityLoop()
        cancellables.removeAll()
    }

    // MARK: - Role Assignment

    private func assignRolesIfNeeded() {
        guard !didAssignRoles, playerRole == .unassigned else { return }

        if networkService.role == .host {
            let isHostSeer = Bool.random()
            playerRole = isHostSeer ? .seer : .listener
            didAssignRoles = true
            networkService.send(.roleAssignment(hostIsSeer: isHostSeer))
            print("🎭 [Gameplay] Host assigned — local role: \(playerRole.rawValue)")
        } else if let event = networkService.latestEvent(ofType: .roleAssignment) {
            applyGuestRole(from: event.payload)
        }
    }

    private func bindRoleAssignment() {
        networkService.eventPublisher
            .filter { $0.eventType == NetworkEvent.EventType.roleAssignment.rawValue }
            .sink { [weak self] event in
                guard let self, self.networkService.role == .guest else { return }
                self.applyGuestRole(from: event.payload)
            }
            .store(in: &cancellables)
    }

    private func applyGuestRole(from payload: String?) {
        guard !didAssignRoles, playerRole == .unassigned else { return }

        switch payload {
        case "host_is_seer":
            playerRole = .listener
        case "host_is_listener":
            playerRole = .seer
        default:
            print("🎭 [Gameplay] Unrecognized role payload: \(payload ?? "nil")")
            return
        }

        didAssignRoles = true
        print("🎭 [Gameplay] Guest assigned — local role: \(playerRole.rawValue)")
    }

    // MARK: - Phase 6B — Letter Spawn

    private func bindLetterSpawn() {
        $playerRole
            .removeDuplicates()
            .filter { $0 != .unassigned }
            .sink { [weak self] _ in
                self?.beginLetterHunt()
            }
            .store(in: &cancellables)
    }

    /// Once roles are known, configure asymmetrical rendering and let the Host
    /// place the shared letter anchor (Guest receives it via collaboration).
    private func beginLetterHunt() {
        guard playerRole != .unassigned, !didRequestLetterSpawn else { return }
        didRequestLetterSpawn = true

        arService.setLocalPlayerRole(playerRole)
        if networkService.role == .host {
            arService.requestLetterSpawn()
        } else if let event = networkService.latestEvent(ofType: .letterSpawn),
                  let transform = LetterSpawnPayload.decode(event.payload) {
            // Guest may have missed the live event while still on the curse transition.
            arService.spawnLetterAtSyncedTransform(transform, for: playerRole)
        }
        print("📜 [Gameplay] Phase 6B started — role: \(playerRole.rawValue)")
    }

    /// Host broadcasts the letter transform; Guest spawns locally from that payload
    /// so both devices always share the same clue even if AR anchor sync is delayed.
    private func bindLetterNetworkSync() {
        arService.letterSpawned
            .sink { [weak self] transform in
                guard let self, self.networkService.role == .host else { return }
                self.networkService.send(.letterSpawn(transform: transform))
                print("📜 [Gameplay] Host sent letter spawn to Guest")
            }
            .store(in: &cancellables)

        networkService.eventPublisher
            .filter { $0.eventType == NetworkEvent.EventType.letterSpawn.rawValue }
            .sink { [weak self] event in
                guard let self else { return }
                guard let transform = LetterSpawnPayload.decode(event.payload) else { return }
                self.arService.spawnLetterAtSyncedTransform(transform, for: self.playerRole)
                print("📜 [Gameplay] Received letter spawn from Host")
            }
            .store(in: &cancellables)
    }

    // MARK: - Phase 6B — Listener Proximity (60 fps haptics)

    private func bindLetterProximityLoop() {
        arService.$isLetterSpawned
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                self?.startListenerProximityLoopIfNeeded()
            }
            .store(in: &cancellables)

        $playerRole
            .removeDuplicates()
            .sink { [weak self] role in
                guard role == .listener, self?.arService.isLetterSpawned == true else { return }
                self?.startListenerProximityLoopIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func startListenerProximityLoopIfNeeded() {
        guard playerRole == .listener, arService.isLetterSpawned else { return }
        guard !isProximityLoopActive else { return }
        isProximityLoopActive = true

        letterHaptics.start()

        // Use CADisplayLink for true 60fps timing (ARKit's SceneEvents.Update
        // runs at render rate, which varies; CoreAnimation guarantees exactly 60fps).
        displayLink = CADisplayLink(target: self, selector: #selector(tickListenerProximity))
        displayLink?.add(to: .main, forMode: .common)
        print("📳 [Gameplay] Listener proximity loop started (exact 60 fps)")
    }

    @objc
    private func tickListenerProximity() {
        guard playerRole == .listener,
              let letterPosition = arService.letterWorldPosition,
              let frame = arService.arView.session.currentFrame else { return }

        let cameraPosition = SpatialMath.cameraPosition(from: frame)
        let distance = SpatialMath.euclideanDistance(cameraPosition, letterPosition)
        distanceToLetter = distance
        letterHaptics.update(distance: distance)
    }

    private func stopListenerProximityLoop() {
        guard isProximityLoopActive else { return }
        displayLink?.invalidate()
        displayLink = nil
        letterHaptics.stop()
        isProximityLoopActive = false
        distanceToLetter = nil
    }

    // MARK: - AR Collaboration (continues from Seance)

    private func bindCollaboration() {
        arService.outgoingCollaborationData
            .sink { [weak self] payload in
                self?.networkService.sendCollaborationData(payload.data, critical: payload.isCritical)
            }
            .store(in: &cancellables)

        networkService.collaborationDataPublisher
            .sink { [weak self] data in
                self?.arService.update(with: data)
            }
            .store(in: &cancellables)
    }
}
