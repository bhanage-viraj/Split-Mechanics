import Combine
import Foundation
import Network

/// Interactor: owns the `NetworkService` and drives all business logic.
///
/// The Presenter calls into this interactor — the Interactor never touches UI.
@MainActor
final class LobbyInteractor {

    // MARK: - Dependencies

    private let networkService: NetworkService

    // MARK: - Output Subjects

    private let stateSubject = PassthroughSubject<NetworkState, Never>()
    private let statusSubject = PassthroughSubject<String, Never>()
    private let peerListSubject = PassthroughSubject<[NWBrowser.Result], Never>()
    private let messageSubject = PassthroughSubject<NetworkEvent, Never>()
    private let latencySubject = PassthroughSubject<LatencyStats, Never>()
    private let peerDisconnectSubject = PassthroughSubject<Bool, Never>()

    // MARK: - Cancellables

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(networkService: NetworkService) {
        self.networkService = networkService
        bindNetworkService()
    }

    // MARK: - Binding

    private func bindNetworkService() {
        networkService.$state
            .sink { [weak self] state in
                self?.stateSubject.send(state)
            }
            .store(in: &cancellables)

        networkService.$statusMessage
            .sink { [weak self] message in
                self?.statusSubject.send(message)
            }
            .store(in: &cancellables)

        networkService.$discoveredPeers
            .sink { [weak self] peers in
                self?.peerListSubject.send(peers)
            }
            .store(in: &cancellables)

        networkService.$receivedMessages
            .sink { [weak self] events in
                if let last = events.last {
                    self?.messageSubject.send(last)
                }
            }
            .store(in: &cancellables)

        networkService.$latency
            .sink { [weak self] stats in
                self?.latencySubject.send(stats)
            }
            .store(in: &cancellables)

        networkService.$peerDisconnected
            .sink { [weak self] didDisconnect in
                self?.peerDisconnectSubject.send(didDisconnect)
            }
            .store(in: &cancellables)
    }

    // MARK: - Intents from Presenter

    func hostGame() {
        networkService.disconnect()
        networkService.startHosting()
    }

    func joinGame() {
        networkService.disconnect()
        networkService.startBrowsing()
    }

    func connectToPeer(_ result: NWBrowser.Result) {
        networkService.connect(to: result)
    }

    func sendTestMessage() {
        networkService.send(.hello())
    }

    // MARK: - Latency Testing Intents

    func pingOnce() {
        networkService.sendPing()
    }

    func startPingLoop() {
        networkService.startPingLoop()
    }

    func stopPingLoop() {
        networkService.stopPingLoop()
    }

    func resetLatency() {
        networkService.resetLatencyStats()
    }

    func acknowledgePeerDisconnect() {
        networkService.acknowledgePeerDisconnect()
    }

    func disconnect() {
        networkService.disconnect()
    }
}

// MARK: - Output Publishers (for Presenter subscription)

extension LobbyInteractor {
    var statePublisher: AnyPublisher<NetworkState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var statusPublisher: AnyPublisher<String, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    var peerListPublisher: AnyPublisher<[NWBrowser.Result], Never> {
        peerListSubject.eraseToAnyPublisher()
    }

    var messagePublisher: AnyPublisher<NetworkEvent, Never> {
        messageSubject.eraseToAnyPublisher()
    }

    var latencyPublisher: AnyPublisher<LatencyStats, Never> {
        latencySubject.eraseToAnyPublisher()
    }

    var peerDisconnectPublisher: AnyPublisher<Bool, Never> {
        peerDisconnectSubject.eraseToAnyPublisher()
    }
}
