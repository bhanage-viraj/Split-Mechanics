//
//  LetterProximityHaptics.swift
//  The Cursed Room
//
//  Phase 6B — continuous CoreHaptics for the Listener, modulated by distance
//  to the hidden letter (max at 0.2 m, silent by 3.0 m).
//

import CoreHaptics
import Foundation

@MainActor
final class LetterProximityHaptics {

    private var engine: CHHapticEngine?
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    private var isRunning = false

    var isSupported: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    // MARK: - Public API

    /// Distance map: 1.0 at ≤near, 0.0 at ≥far.
    static func intensity(for distance: Float, near: Float = 0.2, far: Float = 3.0) -> Float {
        guard distance > near else { return 1.0 }
        guard distance < far else { return 0.0 }
        return 1.0 - (distance - near) / (far - near)
    }

    func start() {
        guard isSupported, !isRunning else { return }

        do {
            let hapticEngine = try CHHapticEngine()

            // Engine recovered from interruption — restart the continuous pattern.
            hapticEngine.resetHandler = { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    try? self.engine?.start()
                    try? self.restartContinuousPattern()
                }
            }

            hapticEngine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.isRunning = false
                }
            }

            try hapticEngine.start()
            self.engine = hapticEngine
            try restartContinuousPattern()
            isRunning = true
            print("📳 [Haptics] Letter proximity engine started")
        } catch {
            print("📳 [Haptics] Failed to start: \(error.localizedDescription)")
        }
    }

    /// Modulate intensity and sharpness based on the caller-provided distance.
    func update(distance: Float) {
        guard isRunning, let continuousPlayer else { return }

        let intensity = Self.intensity(for: distance)
        let sharpness = 0.25 + intensity * 0.55

        let intensityParam = CHHapticDynamicParameter(
            parameterID: .hapticIntensityControl,
            value: intensity,
            relativeTime: 0
        )
        let sharpnessParam = CHHapticDynamicParameter(
            parameterID: .hapticSharpnessControl,
            value: sharpness,
            relativeTime: 0
        )

        do {
            try continuousPlayer.sendParameters([intensityParam, sharpnessParam], atTime: CHHapticTimeImmediate)
        } catch {
            print("📳 [Haptics] Parameter update failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard isRunning else { return }
        try? continuousPlayer?.stop(atTime: CHHapticTimeImmediate)
        continuousPlayer = nil
        engine?.stop(completionHandler: nil)
        engine = nil
        isRunning = false
        print("📳 [Haptics] Letter proximity engine stopped")
    }

    // MARK: - Private

    private func restartContinuousPattern() throws {
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.35)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [intensity, sharpness],
            relativeTime: 0,
            duration: 60
        )
        let pattern = try CHHapticPattern(events: [event], parameters: [])
        continuousPlayer = try engine?.makeAdvancedPlayer(with: pattern)
        try continuousPlayer?.start(atTime: 0)
    }
}
