import Combine
import Foundation
import Network
import SwiftUI

/// Presenter: transforms interactor output into View state and passes user intents to the Interactor.
@MainActor
final class LobbyPresenter: ObservableObject {

    // MARK: - Published View State

    @Published var networkState: NetworkState = .disconnected
    @Published var statusMessage: String = ""
    @Published var discoveredPeers: [NWBrowser.Result] = []
    @Published var isConnected: Bool = false
    @Published var receivedMessages: [NetworkEvent] = []
    @Published var latency: LatencyStats = .empty
    @Published var showPeerDisconnectedAlert: Bool = false

    // MARK: - Private

    private let interactor: LobbyInteractor
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(interactor: LobbyInteractor) {
        self.interactor = interactor
        bindInteractor()
    }

    // MARK: - Binding

    private func bindInteractor() {
        interactor.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.networkState = state
                self?.isConnected = (state == .connected)
            }
            .store(in: &cancellables)

        interactor.statusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.statusMessage = message
            }
            .store(in: &cancellables)

        interactor.peerListPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] peers in
                self?.discoveredPeers = peers
            }
            .store(in: &cancellables)

        interactor.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.receivedMessages.append(event)
            }
            .store(in: &cancellables)

        interactor.latencyPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stats in
                self?.latency = stats
            }
            .store(in: &cancellables)

        interactor.peerDisconnectPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] didDisconnect in
                if didDisconnect {
                    self?.showPeerDisconnectedAlert = true
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Formatted Latency

    var latencySummary: String {
        guard let last = latency.last else { return "No samples yet" }
        return String(format: "Last: %.1f ms", last)
    }

    var latencyDetail: String {
        guard latency.count > 0,
              let avg = latency.average,
              let min = latency.min,
              let max = latency.max else {
            return "avg — · min — · max —"
        }
        return String(format: "avg %.1f · min %.1f · max %.1f ms (n=%d)", avg, min, max, latency.count)
    }

    // MARK: - Intents from View

    func didTapHost() {
        interactor.hostGame()
    }

    func didTapJoin() {
        interactor.joinGame()
    }

    func didTapPeer(_ result: NWBrowser.Result) {
        interactor.connectToPeer(result)
    }

    func didTapSendTest() {
        interactor.sendTestMessage()
    }

    func didTapPingOnce() {
        interactor.pingOnce()
    }

    func didTapToggleAutoPing() {
        if latency.isLooping {
            interactor.stopPingLoop()
        } else {
            interactor.startPingLoop()
        }
    }

    func didTapResetLatency() {
        interactor.resetLatency()
    }

    func didDismissPeerDisconnectedAlert() {
        showPeerDisconnectedAlert = false
        interactor.acknowledgePeerDisconnect()
    }

    func didTapDisconnect() {
        interactor.disconnect()
    }
}
