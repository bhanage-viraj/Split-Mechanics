//
//  GameSoundtrack.swift
//  The Cursed Room
//
//  Non-spatial soundtrack cues mapped to the game flow chart:
//  entrance → curse start → role wind → letter heartbeat → seal unlock.
//

import AVFoundation
import Foundation

extension Notification.Name {
    /// Posted when the one-shot curse-start sting finishes (wind / letter phase may begin).
    static let gameCurseStartFinished = Notification.Name("gameCurseStartFinished")
}

@MainActor
final class GameSoundtrack: NSObject {

    static let shared = GameSoundtrack()

    private(set) var didFinishCurseStart = false

    private var entrancePlayer: AVAudioPlayer?
    private var curseStartPlayer: AVAudioPlayer?
    private var windPlayer: AVAudioPlayer?
    private var heartbeatPlayer: AVAudioPlayer?
    private var sealUnlockPlayer: AVAudioPlayer?

    private var windShouldResumeAfterHeartbeat = false

    private override init() {
        super.init()
    }

    // MARK: - Flow Chart: Story → Seance (entrance)

    func playEntrance() {
        playLoop(named: "enterance", ext: "wav", into: &entrancePlayer)
    }

    func stopEntrance() {
        entrancePlayer?.stop()
        entrancePlayer = nil
    }

    // MARK: - Flow Chart: Doll touched (curse start → then wind for Seer)

    func playCurseStart() {
        didFinishCurseStart = false
        stopEntrance()
        guard playOneShot(
            named: "after curse",
            ext: "wav",
            into: &curseStartPlayer
        ) else {
            didFinishCurseStart = true
            NotificationCenter.default.post(name: .gameCurseStartFinished, object: nil)
            return
        }
    }

    func playWindForSeer() {
        guard playLoop(named: "wind", ext: "wav", into: &windPlayer)
            || playLoop(named: "wind_ambient", ext: "wav", into: &windPlayer) else {
            print("🔊 [Soundtrack] wind.wav not found — add it to Sounds/ for Seer ambience")
            return
        }
        print("🔊 [Soundtrack] Seer wind loop started")
    }

    func stopWind() {
        windPlayer?.stop()
        windPlayer = nil
        windShouldResumeAfterHeartbeat = false
    }

    // MARK: - Flow Chart: Letter sheet (heartbeat for both)

    func beginLetterReading() {
        if windPlayer?.isPlaying == true {
            windShouldResumeAfterHeartbeat = true
            windPlayer?.pause()
        }

        guard playLoop(named: "Heartbeat", ext: "wav", into: &heartbeatPlayer)
            || playLoop(named: "heartbeat", ext: "wav", into: &heartbeatPlayer) else {
            print("🔊 [Soundtrack] Heartbeat.wav not found — add it to Sounds/ for letter reading")
            return
        }
        print("🔊 [Soundtrack] Heartbeat loop started (letter sheet)")
    }

    func endLetterReading() {
        heartbeatPlayer?.stop()
        heartbeatPlayer = nil

        if windShouldResumeAfterHeartbeat {
            windShouldResumeAfterHeartbeat = false
            windPlayer?.play()
        }
    }

    // MARK: - Flow Chart: First seal revealed

    func playSealUnlock() {
        _ = playOneShot(named: "Seal unlock", ext: "wav", into: &sealUnlockPlayer)
    }

    // MARK: - Teardown

    func stopAll() {
        didFinishCurseStart = false
        stopEntrance()
        curseStartPlayer?.stop()
        curseStartPlayer = nil
        stopWind()
        heartbeatPlayer?.stop()
        heartbeatPlayer = nil
        sealUnlockPlayer?.stop()
        sealUnlockPlayer = nil
    }

    // MARK: - Bundle loading

    @discardableResult
    private func playLoop(
        named resourceName: String,
        ext fileExtension: String,
        into player: inout AVAudioPlayer?
    ) -> Bool {
        guard let url = bundleURL(named: resourceName, ext: fileExtension) else { return false }
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.numberOfLoops = -1
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
            return true
        } catch {
            print("🔊 [Soundtrack] Failed to loop \(resourceName).\(fileExtension): \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    private func playOneShot(
        named resourceName: String,
        ext fileExtension: String,
        into player: inout AVAudioPlayer?
    ) -> Bool {
        guard let url = bundleURL(named: resourceName, ext: fileExtension) else { return false }
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
            return true
        } catch {
            print("🔊 [Soundtrack] Failed to play \(resourceName).\(fileExtension): \(error.localizedDescription)")
            return false
        }
    }

    private func bundleURL(named resourceName: String, ext fileExtension: String) -> URL? {
        let bundle = Bundle.main
        return bundle.url(forResource: resourceName, withExtension: fileExtension, subdirectory: "Sounds")
            ?? bundle.url(forResource: resourceName, withExtension: fileExtension)
    }
}

// MARK: - AVAudioPlayerDelegate

extension GameSoundtrack: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard player === self.curseStartPlayer else { return }
            self.curseStartPlayer = nil
            self.didFinishCurseStart = true
            NotificationCenter.default.post(name: .gameCurseStartFinished, object: nil)
            print("🔊 [Soundtrack] Curse start finished")
        }
    }
}
