import Combine
import Foundation
import Network
import SwiftUI
import UIKit

@MainActor
final class LobbyPresenter: ObservableObject {


    @Published var networkState: NetworkState = .disconnected
    @Published var statusMessage: String = ""
    @Published var discoveredPeers: [NWBrowser.Result] = []
    @Published var isConnected: Bool = false
    @Published var receivedMessages: [NetworkEvent] = []
    @Published var latency: LatencyStats = .empty
    @Published var showPeerDisconnectedAlert: Bool = false
    @Published var peerName: String = ""
    @Published var selectedPeer: NWBrowser.Result?
    @Published var didRequestInvestigationStart: Bool = false


    @Published private(set) var playerName: String = UIDevice.current.name

    var isHost: Bool {
        networkState == .hosting || (networkState == .connected && interactor.isHost)
    }


    private let interactor: LobbyInteractor
    private var cancellables = Set<AnyCancellable>()



    init(interactor: LobbyInteractor) {
        self.interactor = interactor
        bindInteractor()
    }


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

        interactor.peerNamePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                guard let self else { return }
                if !name.isEmpty {
                    self.peerName = name
                }
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


    var latencySummary: String {
        guard let last = latency.last else { return String(localized: "No samples yet") }
        return String(format: String(localized: "Last: %.1f ms"), last)
    }

    var latencyDetail: String {
        guard latency.count > 0,
              let avg = latency.average,
              let min = latency.min,
              let max = latency.max else {
            return String(localized: "avg — · min — · max —")
        }
        return String(format: String(localized: "avg %.1f · min %.1f · max %.1f ms (n=%d)"), avg, min, max, latency.count)
    }


    func didTapHost() {
        selectedPeer = nil
        peerName = ""
        interactor.hostGame()
    }

    func didTapJoin() {
        switch networkState {
        case .disconnected:
            selectedPeer = nil
            interactor.joinGame()
        case .browsing:
            guard let selectedPeer else { return }
            peerName = selectedPeer.displayName
            interactor.connectToPeer(selectedPeer)
        default:
            break
        }
    }

    func didTapPeer(_ result: NWBrowser.Result) {
        selectedPeer = result
        peerName = result.displayName
    }

    func didTapContinueConnected() {
        didRequestInvestigationStart = true
        interactor.sendStartScanning()
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
        selectedPeer = nil
        peerName = ""
        didRequestInvestigationStart = false
        interactor.disconnect()
    }
}

private extension NWBrowser.Result {
    var displayName: String {
        if case let .service(name, _, _, _) = endpoint {
            return name
        }
        return "Friend_1"
    }
}
