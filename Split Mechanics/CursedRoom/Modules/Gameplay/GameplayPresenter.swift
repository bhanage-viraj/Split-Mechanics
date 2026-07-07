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

    // Phase 8A — unclosable frequency note overlay
    @Published private(set) var showFrequencyNote = false
    @Published private(set) var targetFrequencyHz: Double = 440.0

    // Phase 8B — frequency scanner
    @Published private(set) var isFrequencyMatchResolved = false
    @Published private(set) var sliderValue: Double = 0.5
    @Published private(set) var signalClarity: Double = 0.0
    @Published private(set) var frequencyDelta: Double = 0.0

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

        interactor.$showFrequencyNote
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                self?.showFrequencyNote = show
            }
            .store(in: &cancellables)

        interactor.$didFrequencyMatch
            .receive(on: DispatchQueue.main)
            .sink { [weak self] matched in
                self?.isFrequencyMatchResolved = matched
            }
            .store(in: &cancellables)

        interactor.$sliderValue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.sliderValue = value
            }
            .store(in: &cancellables)

        interactor.$signalClarity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] clarity in
                self?.signalClarity = clarity
            }
            .store(in: &cancellables)

        interactor.$frequencyDelta
            .receive(on: DispatchQueue.main)
            .sink { [weak self] delta in
                self?.frequencyDelta = delta
            }
            .store(in: &cancellables)

        // Target frequency is fixed for this session (GameStateSeed placeholder).
        targetFrequencyHz = interactor.frequencyTargetHz
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

    func updateFrequencySlider(_ value: Double) {
        interactor.updateSliderValue(value)
    }

    var currentFrequencyHz: Double {
        100.0 + sliderValue * 900.0
    }

    var isFrequencyLocked: Bool { isFrequencyMatchResolved }
    var showFrequencyScanner: Bool { sealsCollected > 0 }

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
