//
//  SeancePresenter.swift
//  The Cursed Room
//
//  Formats ARService state into a view model for the Seance screen.
//

import Combine
import Foundation
import RealityKit

@MainActor
final class SeancePresenter: ObservableObject {

    struct ViewModel: Equatable {
        var prompt: String
        var status: String
        var showActivity: Bool
    }

    @Published private(set) var viewModel: ViewModel

    private let interactor: SeanceInteractor
    private var cancellables = Set<AnyCancellable>()

    /// The live collaborative AR view the SwiftUI layer embeds.
    var arView: ARView { interactor.arService.arView }

    init(interactor: SeanceInteractor) {
        self.interactor = interactor
        self.viewModel = ViewModel(
            prompt: String(localized: "Stand shoulder-to-shoulder and look at the center of the room."),
            status: String(localized: "Starting AR…"),
            showActivity: true
        )
        bind()
    }

    private func bind() {
        let service = interactor.arService
        Publishers.CombineLatest3(
            service.$hasMergedWorlds,
            service.$isDollSpawned,
            service.$statusMessage
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] merged, dollSpawned, status in
            self?.viewModel = ViewModel(
                prompt: dollSpawned
                    ? String(localized: "Tap the doll…")
                    : String(localized: "Stand shoulder-to-shoulder and look at the center of the room."),
                status: status,
                showActivity: !merged || !dollSpawned
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
