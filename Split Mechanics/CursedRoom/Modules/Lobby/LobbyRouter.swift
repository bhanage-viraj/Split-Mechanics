import Combine
import Foundation
import SwiftUI

/// Router: owns navigation logic. Dismisses the lobby when a connection is established.
@MainActor
final class LobbyRouter: ObservableObject {

    @Published var shouldDismissLobby: Bool = false
    @Published var shouldNavigateToScanning: Bool = false

    private var cancellables = Set<AnyCancellable>()

    func observeConnection(from presenter: LobbyPresenter) {
        presenter.$isConnected
            .removeDuplicates()
            .sink { [weak self] connected in
                // Mirror the connection state directly: entering `.connected`
                // moves past the lobby; dropping back returns both phones to it.
                self?.shouldDismissLobby = connected
                self?.shouldNavigateToScanning = connected
            }
            .store(in: &cancellables)
    }
}
