//
//  GameAudioSession.swift
//  The Cursed Room
//
//  Activates the device speaker for RealityKit spatial audio playback.
//

import AVFoundation

enum GameAudioSession {
    static func activatePlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            print("🔊 [Audio] Playback session active")
        } catch {
            print("🔊 [Audio] Failed to activate session: \(error.localizedDescription)")
        }
    }
}
