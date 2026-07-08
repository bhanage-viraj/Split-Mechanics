//
//  SpatialAudioEmitter.swift
//  The Cursed Room
//
//  Reusable RealityKit spatial audio helper. Places an invisible emitter at an
//  exact world position so panning always matches the clue coordinates.
//

import Foundation
import RealityKit
import simd

@MainActor
enum SpatialAudioEmitter {

    struct Config {
        var gain: Audio.Decibel = Audio.Decibel(-3)
        var rolloffFactor: Float = 1.0
        var loops: Bool = true
        var entityName: String = "spatial_audio_emitter"
    }

    struct Handle {
        let anchor: AnchorEntity?
        let attachedEmitter: Entity?
        let controller: AudioPlaybackController

        func stop(in scene: RealityKit.Scene) {
            controller.stop()
            if let anchor {
                scene.removeAnchor(anchor)
            } else {
                attachedEmitter?.removeFromParent()
            }
        }
    }

    /// Resolves a bundled audio file from the main bundle.
    static func bundleURL(
        named resourceName: String,
        extension fileExtension: String,
        subdirectory: String? = nil
    ) -> URL? {
        let bundle = Bundle.main
        if let subdirectory {
            return bundle.url(
                forResource: resourceName,
                withExtension: fileExtension,
                subdirectory: subdirectory
            ) ?? bundle.url(forResource: resourceName, withExtension: fileExtension)
        }
        return bundle.url(forResource: resourceName, withExtension: fileExtension)
    }

    /// Spawns an invisible emitter at `worldPosition` and starts playback.
    static func play(
        in scene: RealityKit.Scene,
        audioURL: URL,
        at worldPosition: simd_float3,
        config: Config = Config()
    ) async throws -> Handle {
        let anchor = AnchorEntity(world: SpatialMath.translation(worldPosition))
        let emitter = Entity()
        emitter.name = config.entityName
        anchor.addChild(emitter)

        emitter.components.set(SpatialAudioComponent(
            gain: config.gain,
            directivity: .beam(focus: 0),
            distanceAttenuation: .rolloff(factor: Double(config.rolloffFactor))
        ))

        scene.addAnchor(anchor)

        let resource = try await AudioFileResource(
            contentsOf: audioURL,
            configuration: .init(shouldLoop: config.loops)
        )
        let controller = emitter.playAudio(resource)
        return Handle(anchor: anchor, attachedEmitter: nil, controller: controller)
    }

    /// Attaches a spatial-audio emitter as a child of an existing anchor so audio
    /// and visuals share the exact same world transform.
    static func attach(
        to parent: AnchorEntity,
        audioURL: URL,
        config: Config = Config()
    ) async throws -> Handle {
        let emitter = Entity()
        emitter.name = config.entityName
        emitter.position = .zero
        parent.addChild(emitter)

        emitter.components.set(SpatialAudioComponent(
            gain: config.gain,
            directivity: .beam(focus: 0),
            distanceAttenuation: .rolloff(factor: Double(config.rolloffFactor))
        ))

        let resource = try await AudioFileResource(
            contentsOf: audioURL,
            configuration: .init(shouldLoop: config.loops)
        )
        let controller = emitter.playAudio(resource)
        return Handle(anchor: nil, attachedEmitter: emitter, controller: controller)
    }
}
