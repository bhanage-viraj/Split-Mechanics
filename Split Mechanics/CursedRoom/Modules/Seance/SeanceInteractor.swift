//
//  SeanceInteractor.swift
//  The Cursed Room
//
//  Phase 4 bridge: routes collaboration data and doll triggers between the
//  ARService and the NetworkService. Holds all cross-service wiring so neither
//  the View nor the ARService need to know about the network (strict VIPER).
//

import Combine
import Foundation

@MainActor
final class SeanceInteractor {

    let arService: ARService
    private let networkService: NetworkService
    private weak var router: SeanceRouterProtocol?

    private var cancellables = Set<AnyCancellable>()
    private var didRouteToPhase5 = false

    init(arService: ARService, networkService: NetworkService) {
        self.arService = arService
        self.networkService = networkService
    }

    func setRouter(_ router: SeanceRouterProtocol) {
        self.router = router
    }

    // MARK: - Start

    func start() {
        bind()
        arService.start(isHost: networkService.role == .host)
    }

    func stop() {
        arService.stop()
        cancellables.removeAll()
    }

    // MARK: - Wiring

    private func bind() {
        // Outgoing collaboration data → peer over TCP.
        arService.outgoingCollaborationData
            .sink { [weak self] payload in
                self?.networkService.sendCollaborationData(payload.data, critical: payload.isCritical)
            }
            .store(in: &cancellables)

        // Incoming collaboration data from peer → local ARSession.
        networkService.collaborationDataPublisher
            .sink { [weak self] data in
                self?.arService.update(with: data)
            }
            .store(in: &cancellables)

        // Worlds merged → the Host spawns the doll (Guest gets it via collaboration).
        arService.$hasMergedWorlds
            .filter { $0 }
            .sink { [weak self] _ in
                self?.arService.requestDollSpawn()
            }
            .store(in: &cancellables)

        // Local tap on the doll → tell the peer, then advance ourselves.
        arService.dollTapped
            .sink { [weak self] in
                guard let self else { return }
                self.networkService.send(.dollTouched())
                self.advanceToPhase5()
            }
            .store(in: &cancellables)

        // Peer tapped the doll → advance ourselves.
        networkService.eventPublisher
            .filter { $0.eventType == NetworkEvent.EventType.dollTouched.rawValue }
            .sink { [weak self] _ in
                self?.advanceToPhase5()
            }
            .store(in: &cancellables)
    }

    private func advanceToPhase5() {
        guard !didRouteToPhase5 else { return }
        didRouteToPhase5 = true
        router?.routeToPhase5()
    }
}
