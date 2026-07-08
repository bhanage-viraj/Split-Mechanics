//
//  ScanningPresenter.swift
//  The Cursed Room
//

import Combine
import Foundation
import RoomPlan

// MARK: - View Model

struct ScanningViewModel: Equatable {
    var isSupported: Bool
    var isScanning: Bool
    var isProcessing: Bool
    var canStartGame: Bool
    var wallCount: Int
    var doorCount: Int
    var windowCount: Int
    var objectCount: Int
    var title: String
    var subtitle: String
    var primaryButtonTitle: String
    var primaryButtonEnabled: Bool
    var errorMessage: String?

    static func initial(isSupported: Bool) -> ScanningViewModel {
        ScanningViewModel(
            isSupported: isSupported,
            isScanning: false,
            isProcessing: false,
            canStartGame: false,
            wallCount: 0,
            doorCount: 0,
            windowCount: 0,
            objectCount: 0,
            title: isSupported ? "Preparing Scanner…" : "Unsupported Device",
            subtitle: isSupported
                ? "Point your phone at the room to begin."
                : "RoomPlan scanning requires a LiDAR-equipped iPhone Pro.",
            primaryButtonTitle: "Finish Scanning",
            primaryButtonEnabled: false,
            errorMessage: nil
        )
    }
}

// MARK: - Presenter

@MainActor
final class ScanningPresenter: ObservableObject {
    @Published private(set) var viewModel: ScanningViewModel
    @Published var showBeforeYouBegin: Bool = true

    private let interactor: ScanningBusinessLogic
    private weak var router: ScanningRouterProtocol?
    private var cancellables = Set<AnyCancellable>()

    /// The live RoomPlan view the SwiftUI layer embeds.
    var roomCaptureView: RoomCaptureView { interactor.roomScanService.roomCaptureView }

    init(interactor: ScanningBusinessLogic) {
        self.interactor = interactor
        self.viewModel = .initial(isSupported: interactor.roomScanService.isSupported)
        bind()
    }

    func setRouter(_ router: ScanningRouterProtocol) {
        self.router = router
    }

    // MARK: - Binding

    private func bind() {
        let service = interactor.roomScanService

        let core = Publishers.CombineLatest4(
            service.$isScanning,
            service.$isProcessing,
            service.$scannedRoom,
            service.$errorMessage
        )

        let counts = Publishers.CombineLatest4(
            service.$wallCount,
            service.$doorCount,
            service.$windowCount,
            service.$objectCount
        )

        core.combineLatest(counts)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] core, counts in
                guard let self else { return }
                let (isScanning, isProcessing, scanned, error) = core
                let (walls, doors, windows, objects) = counts
                self.rebuild(
                    isScanning: isScanning,
                    isProcessing: isProcessing,
                    scanned: scanned,
                    error: error,
                    walls: walls,
                    doors: doors,
                    windows: windows,
                    objects: objects
                )
            }
            .store(in: &cancellables)
    }

    private func rebuild(
        isScanning: Bool,
        isProcessing: Bool,
        scanned: ScannedRoom?,
        error: String?,
        walls: Int,
        doors: Int,
        windows: Int,
        objects: Int
    ) {
        let isSupported = interactor.roomScanService.isSupported
        let canStartGame = scanned != nil && !isScanning && !isProcessing

        let title: String
        let subtitle: String
        let buttonTitle: String
        let buttonEnabled: Bool

        if !isSupported {
            title = "Unsupported Device"
            subtitle = "RoomPlan scanning requires a LiDAR-equipped iPhone Pro."
            buttonTitle = "Finish Scanning"
            buttonEnabled = false
        } else if isScanning {
            title = "Scanning Room"
            subtitle = "Move slowly around the room to capture walls and furniture."
            buttonTitle = "Finish Scanning"
            buttonEnabled = true
        } else if isProcessing {
            title = "Processing…"
            subtitle = "Building your room layout."
            buttonTitle = "Processing…"
            buttonEnabled = false
        } else if canStartGame {
            title = "Scan Complete"
            subtitle = "Captured \(walls) walls · \(objects) objects. Ready to begin."
            buttonTitle = "Start Game"
            buttonEnabled = true
        } else {
            title = "Preparing Scanner…"
            subtitle = "Point your phone at the room to begin."
            buttonTitle = "Finish Scanning"
            buttonEnabled = false
        }

        viewModel = ScanningViewModel(
            isSupported: isSupported,
            isScanning: isScanning,
            isProcessing: isProcessing,
            canStartGame: canStartGame,
            wallCount: walls,
            doorCount: doors,
            windowCount: windows,
            objectCount: objects,
            title: title,
            subtitle: subtitle,
            primaryButtonTitle: buttonTitle,
            primaryButtonEnabled: buttonEnabled,
            errorMessage: error
        )
    }

    // MARK: - Intents from View

    func onAppear() {
        if !showBeforeYouBegin {
            interactor.startScanning()
        }
    }

    func startScanningClicked() {
        showBeforeYouBegin = false
        interactor.startScanning()
    }

    func primaryAction() {
        if viewModel.isScanning {
            interactor.finishScanning()
        } else if viewModel.canStartGame {
            let room = interactor.finalizeAndStore()
            router?.finishScanning(with: room)
        }
    }
}
