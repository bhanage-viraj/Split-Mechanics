//
//  ScanningInteractor.swift
//  The Cursed Room
//
//  RoomPlan-based scanning business logic (Host only).
//

import Foundation

// MARK: - Interactor Protocol

@MainActor
protocol ScanningBusinessLogic: AnyObject {
    var roomScanService: RoomScanService { get }
    func startScanning()
    func finishScanning()
    func finalizeAndStore() -> ScannedRoom?
}

// MARK: - Interactor Implementation

@MainActor
final class ScanningInteractor: ScanningBusinessLogic {
    let roomScanService: RoomScanService

    init(roomScanService: RoomScanService) {
        self.roomScanService = roomScanService
    }

    func startScanning() {
        roomScanService.startSession()
    }

    func finishScanning() {
        roomScanService.stopSession()
    }

    /// Persists the captured coordinates and returns the stored room.
    func finalizeAndStore() -> ScannedRoom? {
        roomScanService.persist()
    }
}
