import Combine
import Foundation
import SwiftUI

@MainActor
final class LobbyRouter: ObservableObject {

    @Published var shouldDismissLobby: Bool = false
    @Published var shouldNavigateToScanning: Bool = false

    private var cancellables = Set<AnyCancellable>()

    func observeConnection(from presenter: LobbyPresenter) {
        presenter.$isConnected
            .removeDuplicates()
            .sink { [weak self] connected in
                self?.shouldDismissLobby = connected
                self?.shouldNavigateToScanning = connected
            }
            .store(in: &cancellables)
    }
}
