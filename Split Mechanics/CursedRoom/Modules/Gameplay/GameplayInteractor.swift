//
//  GameplayInteractor.swift
//  The Cursed Room
//
//  Phase 6A — assigns Seer / Listener roles and keeps the collaborative AR
//  session alive. All role logic lives here; the View only renders overlays.
//

import Combine
import Foundation

@MainActor
final class GameplayInteractor: ObservableObject {

    @Published private(set) var playerRole: PlayerRole = .unassigned

    let arService: ARService
    private let networkService: NetworkService
    private weak var router: GameplayRouterProtocol?

    private var cancellables = Set<AnyCancellable>()
    private var didAssignRoles = false

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
        assignRolesIfNeeded()
    }

    func stop() {
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
