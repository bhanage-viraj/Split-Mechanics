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
    @Published var showLetterSheet = false

    // Phase 7C — code keypad overlay
    @Published var showCodeKeypad = false
    @Published var keypadErrorMessage: String?

    // Seal progress
    @Published private(set) var sealsCollected: Int = 0

    // Phase 7C — keypad digit entry
    @Published private(set) var enteredDigits: [String] = []

    private let interactor: GameplayInteractor
    var cancellables = Set<AnyCancellable>()

    var arView: ARView { interactor.arService.arView }
    var interactorRef: GameplayInteractor { interactor }
    var huntStatusMessage: String { interactor.arService.statusMessage }
    var isLetterSpawned: Bool { interactor.arService.isLetterSpawned }

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

        interactor.arService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        interactor.arService.letterTapped
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showLetterSheet = true
            }
            .store(in: &cancellables)

        // Phase 7 — keypad
        interactor.$showCodeKeypad
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                self?.showCodeKeypad = show
                if show { self?.keypadErrorMessage = nil }
            }
            .store(in: &cancellables)

        interactor.$keypadErrorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in
                self?.keypadErrorMessage = msg
                if msg != nil {
                    self?.clearEnteredDigits()
                }
            }
            .store(in: &cancellables)

        interactor.$sealsCollected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.sealsCollected = count
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

    /// Submit the code entered by the Seer.
    func submitCode(_ code: String) {
        interactor.submitCode(code)
    }

    /// Dismiss the letter sheet and advance to Phase 7 (footsteps + blood pool).
    func dismissLetterAndBeginPhase7() {
        showLetterSheet = false
        interactor.beginBloodTrailPhase()
    }

    // MARK: - Keypad Helpers

    func appendDigit(_ digit: String) {
        guard enteredDigits.count < 3 else { return }
        enteredDigits.append(digit)
    }

    func submitCurrentCode() {
        submitCode(enteredDigits.joined())
    }

    func clearEnteredDigits() {
        enteredDigits = []
    }
}
