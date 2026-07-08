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
    private func log(_ message: String) {
        print("🎮 [GameplayPresenter] \(message)")
    }

    private func pushDebugEvent(_ message: String) {
        let event = "[\(timestampString())] \(message)"
        debugEvents.append(event)
        if debugEvents.count > maxDebugEvents {
            debugEvents.removeFirst(debugEvents.count - maxDebugEvents)
        }
        log(message)
    }

    private func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    struct ViewModel: Equatable {
        var playerRole: PlayerRole
        var isRoleResolved: Bool
    }

    @Published private(set) var viewModel: ViewModel
    @Published var showLetterSheet = false
    @Published private(set) var debugEvents: [String] = []

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
    private let maxDebugEvents = 8

    var arView: ARView { interactor.arService.arView }
    var interactorRef: GameplayInteractor { interactor }
    var huntStatusMessage: String { interactor.arService.statusMessage }
    var isLetterSpawned: Bool { interactor.arService.isLetterSpawned }
    var hasMergedWorlds: Bool { interactor.arService.hasMergedWorlds }
    var showLeftSealButton: Bool { false }
    var showRightSealButton: Bool { false }
    var distanceToLetterText: String {
        guard let distance = interactor.distanceToLetter else { return "--" }
        return String(format: "%.2fm", distance)
    }
    var debugStatusLines: [String] {
        [
            "Role: \(viewModel.playerRole.rawValue)",
            "Merged: \(hasMergedWorlds ? "yes" : "no")",
            "Letter: \(isLetterSpawned ? "spawned" : "pending")",
            "Keypad: \(showCodeKeypad ? "open" : "closed")",
            "Seals: \(sealsCollected)/2",
            "Distance: \(distanceToLetterText)",
            "Status: \(huntStatusMessage)"
        ]
    }

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
                self?.pushDebugEvent("role updated -> \(role.rawValue)")
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
                self?.pushDebugEvent("letter tapped -> presenting clue sheet")
            }
            .store(in: &cancellables)

        // Phase 7 — keypad
        interactor.$showCodeKeypad
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                self?.showCodeKeypad = show
                if show { self?.keypadErrorMessage = nil }
                self?.pushDebugEvent("showCodeKeypad -> \(show)")
            }
            .store(in: &cancellables)

        interactor.$keypadErrorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in
                self?.keypadErrorMessage = msg
                if msg != nil {
                    self?.clearEnteredDigits()
                }
                if let msg {
                    self?.pushDebugEvent("keypad error -> \(msg)")
                }
            }
            .store(in: &cancellables)

        interactor.$sealsCollected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.sealsCollected = count
                self?.pushDebugEvent("sealsCollected -> \(count)")
            }
            .store(in: &cancellables)

        interactor.arService.$statusMessage
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.pushDebugEvent("statusMessage -> \(status)")
            }
            .store(in: &cancellables)

        interactor.arService.$hasMergedWorlds
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] merged in
                self?.pushDebugEvent("hasMergedWorlds -> \(merged)")
            }
            .store(in: &cancellables)

        interactor.arService.$isLetterSpawned
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] spawned in
                self?.pushDebugEvent("isLetterSpawned -> \(spawned)")
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
        pushDebugEvent("GameplayView onAppear")
        interactor.start()
    }

    func onDisappear() {
        pushDebugEvent("GameplayView onDisappear")
        interactor.stop()
    }

    func setCameraFeedEnabled(_ enabled: Bool) {
        interactor.arService.setCameraFeedEnabled(enabled)
        pushDebugEvent("camera feed -> \(enabled ? "enabled" : "disabled")")
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
        pushDebugEvent("digit appended -> \(enteredDigits.joined())")
    }

    func submitCurrentCode() {
        pushDebugEvent("submitCurrentCode -> \(enteredDigits.joined())")
        submitCode(enteredDigits.joined())
    }

    func clearEnteredDigits() {
        enteredDigits = []
        pushDebugEvent("entered digits cleared")
    }
}
