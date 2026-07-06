//
//  LetterAudioEngine.swift
//  The Cursed Room
//
//  Phase 6B — Doppler-aware spatial audio for the letter clue.
//
//  This engine implements the two physical principles from the architecture spec:
//  1. Distance attenuation — inverse-distance rolloff (OpenAL-style):
//       gain = referenceGain × (referenceDistance / (referenceDistance + rolloff × (d - referenceDistance)))
//     which matches the inverse-square law at moderate distances.
//
//  2. Doppler effect — pitch shift from relative velocity:
//       f' = ((c ± v_o) / (c ∓ v_s)) × f
//     clamped to ±2 octaves to avoid audible artifacts.
//
//  World positions and velocities are supplied by the GameplayInteractor every
//  frame via `update(listenerPosition:listenerVelocity:letterPosition:)`, keeping
//  the physics and audio threads in sync.

import AVFoundation
import Combine
import Foundation

@MainActor
final class LetterAudioEngine: ObservableObject {

    @Published private(set) var isPlaying = false

    // MARK: - Physics Constants

    private static let speedOfSound: Float = 343.0
    private static let referenceDistance: Float = 0.5
    private static let rolloffFactor: Float = 1.0
    private static let minDistance: Float = 0.1
    private static let maxDopplerRatio: Float = 2.0
    private static let dopplerTransitionSpeed: Float = 4.0

    // MARK: - Audio Nodes

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var pitchNode: AVAudioUnitVarispeed?
    private var reverbNode: AVAudioUnitReverb?

    private var audioFile: AVAudioFile?
    private var currentDopplerRatio: Float = 1.0

    private var previousLetterPosition: simd_float3?
    private var previousListenerPosition: simd_float3?
    private var previousTimestamp: TimeInterval?

    // MARK: - Public API

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let pitch = AVAudioUnitVarispeed()
        let reverb = AVAudioUnitReverb()

        engine.attach(player)
        engine.attach(pitch)
        engine.attach(reverb)

        engine.connect(player, to: pitch, format: nil)
        engine.connect(pitch, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)

        reverb.loadFactoryPreset(.mediumRoom)
        reverb.wetDryMix = 20.0

        try engine.start()
        self.engine = engine
        self.playerNode = player
        self.pitchNode = pitch
        self.reverbNode = reverb

        guard let file = try loadAudioFile() else {
            stop()
            return
        }
        self.audioFile = file

        player.scheduleSegment(
            file,
            startingFrame: AVAudioFramePosition(0),
            frameCount: AVAudioFrameCount(file.length),
            at: nil,
            completionHandler: { [weak self] in
                Task { @MainActor in
                    self?.isPlaying = false
                }
            }
        )
        player.play()
        isPlaying = true

        print("🔊 [AudioEngine] Letter audio started (Doppler + reverb)")
    }

    func update(
        listenerPosition: simd_float3,
        listenerVelocity: simd_float3?,
        letterPosition: simd_float3,
        deltaTime: TimeInterval
    ) {
        let distance = simd_distance(listenerPosition, letterPosition)
        let gain = Self.distanceGain(distance: distance)
        applyGain(gain)

        let currentTime = CACurrentMediaTime()
        let relativeVelocity = computeRelativeVelocity(
            listenerPosition: listenerPosition,
            listenerVelocity: listenerVelocity,
            letterPosition: letterPosition,
            currentTime: currentTime
        )
        applyDoppler(
            relativeVelocity: relativeVelocity,
            listenerPosition: listenerPosition,
            letterPosition: letterPosition,
            deltaTime: deltaTime
        )

        previousListenerPosition = listenerPosition
        previousLetterPosition = letterPosition
        previousTimestamp = currentTime
    }

    func stop() {
        playerNode?.stop()
        engine?.stop()
        engine = nil
        playerNode = nil
        pitchNode = nil
        reverbNode = nil
        audioFile = nil
        isPlaying = false
        currentDopplerRatio = 1.0
        previousLetterPosition = nil
        previousListenerPosition = nil
        previousTimestamp = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        print("🔊 [AudioEngine] Letter audio stopped")
    }

    // MARK: - Private Physics

    private static func distanceGain(distance: Float) -> Float {
        guard distance > minDistance else { return 1.0 }
        let clamped = min(distance, 30.0)
        let numerator = referenceDistance
        let denominator = referenceDistance + rolloffFactor * (clamped - referenceDistance)
        let raw = numerator / max(denominator, 0.01)
        return min(max(raw, 0.0), 1.0)
    }

    private static func dopplerRatio(
        listenerVelocity: simd_float3,
        sourceVelocity: simd_float3,
        listenerPosition: simd_float3,
        sourcePosition: simd_float3
    ) -> Float {
        let direction = simd_normalize(sourcePosition - listenerPosition)
        let vListener = simd_dot(listenerVelocity, direction)
        let vSource = simd_dot(sourceVelocity, direction)
        let numerator = speedOfSound + vListener
        let denominator = speedOfSound - vSource
        guard denominator > 1.0 else { return maxDopplerRatio }
        let ratio = numerator / denominator
        return min(max(ratio, 1.0 / maxDopplerRatio), maxDopplerRatio)
    }

    private func computeRelativeVelocity(
        listenerPosition: simd_float3,
        listenerVelocity: simd_float3?,
        letterPosition: simd_float3,
        currentTime: TimeInterval
    ) -> simd_float3 {
        if let v = listenerVelocity {
            return v
        }

        let prevListener = previousListenerPosition ?? listenerPosition
        let prevLetter = previousLetterPosition ?? letterPosition
        let prevTime = previousTimestamp ?? currentTime
        let dt = Float(currentTime - prevTime)

        guard dt > 0.001 else { return .zero }
        let vListener = (listenerPosition - prevListener) / dt
        let vSource = (letterPosition - prevLetter) / dt
        return vListener - vSource
    }

    private func applyGain(_ gain: Float) {
        guard let output = engine?.mainMixerNode else { return }
        output.outputVolume = min(gain, 1.0)
    }

    private func applyDoppler(
        relativeVelocity: simd_float3,
        listenerPosition: simd_float3,
        letterPosition: simd_float3,
        deltaTime: TimeInterval
    ) {
        let direction = simd_normalize(letterPosition - listenerPosition)
        let radialVelocity = simd_dot(relativeVelocity, direction)
        let vListener = simd_float3(repeating: radialVelocity)
        let vSource = simd_float3(repeating: 0)

        let ratio = Self.dopplerRatio(
            listenerVelocity: vListener,
            sourceVelocity: vSource,
            listenerPosition: listenerPosition,
            sourcePosition: letterPosition
        )

        let dt = Float(deltaTime)
        let smoothing = Self.dopplerTransitionSpeed * dt
        currentDopplerRatio = currentDopplerRatio + (ratio - currentDopplerRatio) * min(smoothing, 1.0)

        pitchNode?.rate = currentDopplerRatio
    }

    // MARK: - Audio File Loading

    private func loadAudioFile() throws -> AVAudioFile? {
        let candidates = [
            Bundle.main.url(
                forResource: "BGM",
                withExtension: "mp3",
                subdirectory: "Sounds"
            ),
            Bundle.main.url(forResource: "BGM", withExtension: "mp3"),
        ]

        for url in candidates.compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: url.path) {
                return try AVAudioFile(forReading: url)
            }
        }

        print("🔊 [AudioEngine] BGM.mp3 not found in bundle")
        return nil
    }
}
