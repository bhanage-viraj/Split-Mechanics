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
    private let whisperHaptics = LetterProximityHaptics()

    // Phase 7
    private let clueCode: String = "427"
    @Published private(set) var sealsCollected: Int = 0
    @Published private(set) var showCodeKeypad = false
    @Published private(set) var keypadErrorMessage: String?

    private var didAssignRoles = false
    private var didRequestLetterSpawn = false
    private var isProximityLoopActive = false
    private var isBloodTrailPhaseActive = false
    private var didSpawnBloodTrail = false

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
        bindBloodPoolTap()
        bindSealEvents()
        bindListenerWhisperHints()
        bindClueCodeFromHost()
        bindBloodTrailSync()
        assignRolesIfNeeded()
        if playerRole != .unassigned {
            beginLetterHunt()
        }
    }

    func stop() {
        stopListenerProximityLoop()
        stopWhisperProximityLoop()
        letterHaptics.stop()
        whisperHaptics.stop()
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

    // MARK: - Phase 7A — Blood Pool Tap & Code Validation

    private func bindBloodPoolTap() {
        arService.bloodPoolTapped
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleBloodPoolTapped()
            }
            .store(in: &cancellables)
    }

    private func handleBloodPoolTapped() {
        guard playerRole == .seer else { return }
        guard !isBloodTrailPhaseActive else { return }
        isBloodTrailPhaseActive = true
        showCodeKeypad = true
        print("🔢 [Gameplay] Seer tapped blood pool — showing keypad")
    }

    /// Called by the view when the Seer submits a 3-digit code.
    func submitCode(_ code: String) {
        guard isBloodTrailPhaseActive else { return }

        if code == clueCode {
            keypadErrorMessage = nil
            showCodeKeypad = false
            isBloodTrailPhaseActive = false
            print("🔓 [Gameplay] Correct code entered — revealing First Seal")

            // Reveal the seal in AR.
            if let position = arService.bloodPoolWorldPosition {
                arService.revealFirstSeal(at: position)
            }

            // Update local seal count.
            sealsCollected = 1

            // Notify the other device.
            networkService.send(.sealCollected(sealNumber: 1))

            // Stop Listener proximity to letter.
            stopListenerProximityLoop()
        } else {
            keypadErrorMessage = "Wrong code. Try again."
            print("🔒 [Gameplay] Wrong code: \(code)")
        }
    }

    // MARK: - Phase 7C — Seal Events (cross-device sync)

    private func bindSealEvents() {
        networkService.eventPublisher
            .filter { $0.eventType == NetworkEvent.EventType.sealCollected.rawValue }
            .sink { [weak self] event in
                guard let self, let payload = event.payload, let count = Int(payload) else { return }
                self.sealsCollected = max(self.sealsCollected, count)
                print("✨ [Gameplay] Received seal update — total: \(self.sealsCollected)")
            }
            .store(in: &cancellables)

        // Sync local seal state back to AR so both devices show the seal.
        $sealsCollected
            .removeDuplicates()
            .filter { $0 > 0 }
            .sink { [weak self] count in
                guard let self, count > 0, self.arService.isFirstSealRevealed else { return }
            }
            .store(in: &cancellables)
    }

    // MARK: - Phase 7B — Listener Whisper Proximity Hints

    private func bindListenerWhisperHints() {
        // When the blood trail is active, start a proximity loop for the Listener
        // to guide them toward the whisper via haptics (stronger = closer).
        arService.$bloodPoolWorldPosition
            .removeDuplicates()
            .filter { $0 != nil }
            .sink { [weak self] position in
                guard let self, let whisperPos = position, self.playerRole == .listener else { return }
                self.startWhisperProximityLoop(targetPosition: whisperPos)
            }
            .store(in: &cancellables)
    }

    private var whisperDisplayLink: CADisplayLink?
    private var isWhisperProximityActive = false

    private func startWhisperProximityLoop(targetPosition: simd_float3) {
        guard !isWhisperProximityActive else { return }
        isWhisperProximityActive = true

        whisperDisplayLink = CADisplayLink(target: self, selector: #selector(tickWhisperProximity))
        whisperDisplayLink?.add(to: .main, forMode: .common)

        // Store target for the tick method.
        whisperTargetPosition = targetPosition
        print("🩸 [Gameplay] Listener whisper proximity loop started")
    }

    private var whisperTargetPosition: simd_float3?

    @objc
    private func tickWhisperProximity() {
        guard playerRole == .listener,
              let target = whisperTargetPosition,
              let frame = arService.arView.session.currentFrame else { return }

        let cameraPosition = SpatialMath.cameraPosition(from: frame)
        let distance = SpatialMath.euclideanDistance(cameraPosition, target)
        let intensity = SpatialMath.letterProximityIntensity(distance: distance, near: 0.3, far: 4.0)
        whisperHaptics.update(distance: distance)
    }

    private func stopWhisperProximityLoop() {
        whisperDisplayLink?.invalidate()
        whisperDisplayLink = nil
        isWhisperProximityActive = false
        whisperTargetPosition = nil
    }

    // MARK: - Blood Trail Spawning (triggered after letter phase)

    /// Call this after the Seer dismisses the letter sheet to start Phase 7A.
    func beginBloodTrailPhase() {
        guard playerRole == .seer else { return }
        guard !didSpawnBloodTrail else { return }

        if networkService.role == .host {
            performAuthoritativeBloodTrailSpawn()
        } else {
            networkService.send(.requestBloodTrail())
            print("🩸 [Gameplay] Guest Seer requested blood trail from Host")
        }

        stopListenerProximityLoop()
    }

    private func performAuthoritativeBloodTrailSpawn() {
        guard !didSpawnBloodTrail else { return }
        guard let result = arService.spawnBloodTrailAndPool() else {
            print("🩸 [Gameplay] Blood trail spawn failed — will retry on next Done tap")
            return
        }

        didSpawnBloodTrail = true
        networkService.send(.bloodTrailSpawn(destination: result.destination, bendSide: result.bendSide))
        networkService.send(.clueCode(code: clueCode))
        print("🔢 [Gameplay] Host sent clue code and blood trail sync")
        print("🩸 [Gameplay] Phase 7 blood trail phase started")
    }

    private func applySyncedBloodTrail(destination: simd_float3, bendSide: Float) {
        guard !didSpawnBloodTrail else { return }
        guard arService.spawnBloodTrailAtSyncedDestination(destination, bendSide: bendSide) != nil else {
            print("🩸 [Gameplay] Synced blood trail spawn failed")
            return
        }

        didSpawnBloodTrail = true
        print("🩸 [Gameplay] Synced blood trail spawned at \(destination)")
    }

    private func bindBloodTrailSync() {
        networkService.eventPublisher
            .filter { $0.eventType == NetworkEvent.EventType.requestBloodTrail.rawValue }
            .sink { [weak self] _ in
                guard let self, self.networkService.role == .host else { return }
                self.performAuthoritativeBloodTrailSpawn()
            }
            .store(in: &cancellables)

        networkService.eventPublisher
            .filter { $0.eventType == NetworkEvent.EventType.bloodTrailSpawn.rawValue }
            .sink { [weak self] event in
                guard let self else { return }
                guard self.networkService.role == .guest else { return }
                guard let sync = BloodTrailSpawnPayload.decode(event.payload) else { return }
                self.applySyncedBloodTrail(destination: sync.destination, bendSide: sync.bendSide)
            }
            .store(in: &cancellables)
    }

    /// Guest receives the clue code from the Host.
    private func bindClueCodeFromHost() {
        networkService.eventPublisher
            .filter { $0.eventType == NetworkEvent.EventType.clueCode.rawValue }
            .sink { [weak self] event in
                guard let self, let code = event.payload else { return }
                // Store the code for the Listener to hear from the whisper audio.
                self.receivedClueCode = code
                print("🔢 [Gameplay] Guest received clue code: \(code)")
            }
            .store(in: &cancellables)
    }

    private var receivedClueCode: String?
}
