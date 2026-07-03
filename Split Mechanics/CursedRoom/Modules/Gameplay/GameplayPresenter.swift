//
//  GameplayPresenter.swift
//  The Cursed Room
//
//  Formats GameplayInteractor state into a view model for Phase 6A overlays.
//

import Combine
import Foundation
import RealityKit

@MainActor
final class GameplayPresenter: ObservableObject {

    struct ViewModel: Equatable {
        var playerRole: PlayerRole
        var isRoleResolved: Bool
    }

    @Published private(set) var viewModel: ViewModel

    private let interactor: GameplayInteractor
    private var cancellables = Set<AnyCancellable>()

    var arView: ARView { interactor.arService.arView }

    init(interactor: GameplayInteractor) {
        self.interactor = interactor
        self.viewModel = ViewModel(playerRole: .unassigned, isRoleResolved: false)
        bind()
    }

    private func bind() {
        interactor.$playerRole
            .receive(on: DispatchQueue.main)
            .sink { [weak self] role in
                self?.viewModel = ViewModel(
                    playerRole: role,
                    isRoleResolved: role != .unassigned
                )
            }
            .store(in: &cancellables)
    }

    // MARK: - Intents

    func onAppear() {
        interactor.start()
    }

    func onDisappear() {
        interactor.stop()
    }
}
