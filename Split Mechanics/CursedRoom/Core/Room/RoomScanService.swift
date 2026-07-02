import Combine
import Foundation
import RoomPlan
import UIKit

/// Wraps Apple's RoomPlan `RoomCaptureView` + `RoomCaptureSession` and exposes
/// scan state to the VIPER stack. Mirrors the RoomPlan demo's UX, but instead of
/// rendering a 2D/3D model at the end it extracts and stores the room coordinates.
///
/// RoomPlan requires a LiDAR device (iPhone Pro/Pro Max). In this game only the
/// Host runs scanning, so this service is only ever created on the Host device.
@MainActor
final class RoomScanService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published private(set) var isSupported: Bool = RoomCaptureSession.isSupported
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var capturedRoom: CapturedRoom?
    @Published private(set) var scannedRoom: ScannedRoom?
    @Published private(set) var wallCount: Int = 0
    @Published private(set) var doorCount: Int = 0
    @Published private(set) var windowCount: Int = 0
    @Published private(set) var objectCount: Int = 0
    @Published private(set) var errorMessage: String?

    // MARK: - RoomPlan Objects

    let roomCaptureView: RoomCaptureView
    private let captureConfig = RoomCaptureSession.Configuration()
    private let roomBuilder = RoomBuilder(options: [.beautifyObjects])

    // MARK: - Init

    override init() {
        roomCaptureView = RoomCaptureView(frame: .zero)
        super.init()
        roomCaptureView.captureSession.delegate = self
    }

    // MARK: - Control

    func startSession() {
        guard isSupported else {
            errorMessage = "This device doesn't support RoomPlan scanning (LiDAR required)."
            return
        }
        errorMessage = nil
        capturedRoom = nil
        scannedRoom = nil
        isProcessing = false
        isScanning = true

        roomCaptureView.captureSession.run(configuration: captureConfig)
        UIApplication.shared.isIdleTimerDisabled = true
        print("🗺️ [RoomScan] Session started")
    }

    func stopSession() {
        guard isScanning else { return }
        isScanning = false
        isProcessing = true
        roomCaptureView.captureSession.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        print("🗺️ [RoomScan] Session stopped — processing…")
    }

    /// Fully releases the RoomPlan camera so a subsequent `ARSession` (the seance)
    /// can take over. Call before tearing the service down. RoomPlan holds the
    /// camera until its session is stopped, so we always force a stop here.
    func teardown() {
        isScanning = false
        isProcessing = false
        roomCaptureView.captureSession.stop()
        roomCaptureView.captureSession.delegate = nil
        UIApplication.shared.isIdleTimerDisabled = false
        print("🗺️ [RoomScan] Torn down — camera released")
    }

    /// Persists the captured room coordinates to disk. Returns the stored room.
    @discardableResult
    func persist() -> ScannedRoom? {
        guard let scannedRoom else { return nil }
        RoomStore.save(scannedRoom)
        return scannedRoom
    }
}

// MARK: - RoomCaptureSessionDelegate

extension RoomScanService: RoomCaptureSessionDelegate {
    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didEndWith data: CapturedRoomData,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                self.errorMessage = error.localizedDescription
                self.isProcessing = false
                print("🗺️ [RoomScan] Capture error: \(error.localizedDescription)")
                return
            }

            do {
                let room = try await self.roomBuilder.capturedRoom(from: data)
                let scanned = ScannedRoom(from: room)

                self.capturedRoom = room
                self.scannedRoom = scanned
                self.wallCount = scanned.walls.count
                self.doorCount = scanned.doors.count
                self.windowCount = scanned.windows.count
                self.objectCount = scanned.objects.count
                self.isProcessing = false

                RoomStore.save(scanned)
                print("🗺️ [RoomScan] Processed room: \(scanned.summary)")
            } catch {
                self.errorMessage = error.localizedDescription
                self.isProcessing = false
                print("🗺️ [RoomScan] Build error: \(error.localizedDescription)")
            }
        }
    }
}
