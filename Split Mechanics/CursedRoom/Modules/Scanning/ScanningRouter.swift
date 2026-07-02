//
//  ScanningRouter.swift
//  The Cursed Room
//

import Combine
import Foundation
import SwiftUI

// MARK: - Router Protocol

@MainActor
protocol ScanningRouterProtocol: AnyObject {
    func finishScanning(with room: ScannedRoom?)
}

// MARK: - Router Implementation

@MainActor
final class ScanningRouter: ObservableObject, ScanningRouterProtocol {
    /// Set when the Host finalizes the scan and the game should begin.
    @Published var shouldStartGame: Bool = false
    @Published var capturedRoom: ScannedRoom?

    func finishScanning(with room: ScannedRoom?) {
        capturedRoom = room
        shouldStartGame = true
        print("[ScanningRouter] Scan finalized → starting game. \(room?.summary ?? "no room")")
    }
}
