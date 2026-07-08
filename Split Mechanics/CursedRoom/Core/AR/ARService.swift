//
//  ARService.swift
//  The Cursed Room
//
//  Phase 4 — World Merging & The Doll's Curse.
//
//  Wraps a collaborative RealityKit `ARView`. Both Host and Guest run a
//  world-tracking session with `isCollaborationEnabled`, exchange collaboration
//  data over the game's TCP `NetworkService`, and — once the maps merge — render
//  a single shared "Doll" that either player can tap.
//

import ARKit
import AVFoundation
import Combine
import RealityKit
import UIKit

@MainActor
final class ARService: NSObject, ObservableObject {

    // MARK: - Published State (observed by the interactor / presenter)

    /// Becomes `true` once an `ARParticipantAnchor` appears — i.e. the two devices'
    /// worlds have merged into a shared coordinate space.
    @Published private(set) var hasMergedWorlds = false

    /// `true` after the shared doll entity has been rendered locally.
    @Published private(set) var isDollSpawned = false

    /// `true` after the first objective (The Letter) has been placed locally.
    @Published private(set) var isLetterSpawned = false

    /// World position of the letter once spawned (used by Phase 6C proximity checks).
    @Published private(set) var letterWorldPosition: simd_float3?

    /// Human-readable tracking status for the on-screen prompt.
    @Published private(set) var statusMessage = String(localized: "Starting AR…")

    // MARK: - Outputs to the interactor (VIPER bridge)

    /// A collaboration blob plus whether ARKit marked it `.critical` (must arrive)
    /// vs `.optional` (droppable). Lets the network layer shed optional data under
    /// backpressure without stalling the world merge.
    struct CollaborationPayload {
        let data: Data
        let isCritical: Bool
    }

    /// Emits locally-produced collaboration blobs to be shipped to the peer.
    let outgoingCollaborationData = PassthroughSubject<CollaborationPayload, Never>()

    /// Emits when the local player taps the doll.
    let dollTapped = PassthroughSubject<Void, Never>()

    /// Emits the world transform once the Host places the letter (for network sync).
    let letterSpawned = PassthroughSubject<simd_float4x4, Never>()

    /// Emits when the Listener taps the letter entity.
    let letterTapped = PassthroughSubject<Void, Never>()

    // MARK: - Phase 7 Events

    /// Emits when the Seer taps the blood pool entity.
    let bloodPoolTapped = PassthroughSubject<Void, Never>()

    /// Emits the blood pool spawn transform so the interactor can expose it for validation.
    @Published private(set) var bloodPoolWorldPosition: simd_float3?

    /// Emits when the first seal has been revealed (blood pool replaced).
    @Published private(set) var isFirstSealRevealed = false

    // MARK: - Phase 8A Events

    /// Emits when the Seer taps the frequency clue entity.
    let frequencyClueTapped = PassthroughSubject<Void, Never>()

    /// Emits when the Seer taps the second seal entity.
    let seal2Tapped = PassthroughSubject<Void, Never>()

    /// World position of the stone slab once spawned.
    @Published private(set) var stoneSlabWorldPosition: simd_float3?

    /// `true` after the second seal has been revealed on the stone slab.
    @Published private(set) var isSecondSealRevealed = false

    /// `true` after the frequency phase content has been spawned.
    @Published private(set) var isFrequencyPhaseSpawned = false

    // MARK: - AR View

    let arView: ARView

    // MARK: - Private

    private var isHost = false
    private var wantsDoll = false          // Host requested a spawn (post-merge)
    private var dollAnchorAdded = false    // Host has added the ARAnchor once
    private var dollAnchorEntity: AnchorEntity?
    private var hasStarted = false

    private var floorPlanes: [UUID: ARPlaneAnchor] = [:]
    private var wallPlanes: [UUID: ARPlaneAnchor] = [:]
    private var obstaclePlanes: [UUID: ARPlaneAnchor] = [:]

    private var localPlayerRole: PlayerRole = .unassigned
    private var wantsLetter = false
    private var letterAnchorAdded = false
    private var letterAnchorEntity: AnchorEntity?
    private var letterAudioHandle: SpatialAudioEmitter.Handle?
    private var pendingLetterAnchor: ARAnchor?
    private var pendingLetterTransform: simd_float4x4?

    // MARK: - Phase 7 Private State

    private var bloodPoolAnchorEntity: AnchorEntity?
    private var footstepsAnchorEntity: AnchorEntity?
    private var whisperAudioHandle: SpatialAudioEmitter.Handle?
    private var hasSpawnedBloodTrail = false
    private var hasConfiguredBloodPoolTap = false

    // MARK: - Phase 8A Private State

    private var goldCoinsAnchorEntity: AnchorEntity?
    private var stoneSlabAnchorEntity: AnchorEntity?
    private var frequencyClueAnchorEntity: AnchorEntity?
    private var barrierAnchorEntity: AnchorEntity?
    private var seal2AnchorEntity: AnchorEntity?
    private var hasSpawnedFrequencyPhase = false

    // MARK: - Phase 8B Private State

    private var frequencyEmitterAnchor: AnchorEntity?
    private var frequencyEmitterEntity: Entity?
    private var hasSpawnedFrequencyEmitter = false

    private static let dollAnchorName = "cursed_doll_anchor"
    private static let dollEntityName = "cursed_doll_entity"
    private static let dollModelName = "Hitem3d-1783040308176"
    private static let dollTargetHeight: Float = 0.45

    private static let letterAnchorName = "cursed_letter_anchor"
    private static let letterEntityName = "cursed_letter_entity"
    private static let letterAudioName = "BGM"
    private static let letterAudioExtension = "mp3"
    private static let letterAudioSubdirectory = "Sounds"

    private static let minimumWallExtent: Float = 0.25

    // MARK: - Phase 7 Constants

    private static let bloodPoolAnchorName = "blood_pool_anchor"
    private static let bloodPoolEntityName = "blood_pool_entity"
    private static let bloodPoolTapVolumeName = "blood_pool_tap_volume"
    private static let bloodPoolWithSealName = "blood_pool_with_seal"
    private static let footstepsAnchorName = "footsteps_anchor"
    private static let whisperEntityName = "whisper_audio_entity"
    private static let whisperAudioName = "BGM"
    private static let whisperAudioExtension = "mp3"
    private static let whisperAudioSubdirectory = "Sounds"
    private static let bloodTrailWalkFraction: Float = 0.40
    private static let footprintBaseWidth: Float = 0.32
    private static let footprintStepSpacing: Float = 0.42
    private static let footprintMaxLateralBend: Float = 0.30
    private static let footprintFloorOffset: Float = 0.006
    private static let bloodPoolTapProximityMeters: Float = 2.2
    private static let bloodPoolTapScreenRadius: CGFloat = 160

    // MARK: - Phase 6 / 7 Texture Assets (Assets.xcassets)

    private static let letterTextureName = "letter"
    private static let footstepsTextureName = "footsteps"
    private static let bloodPoolTextureName = "blood pool (hint1)"
    private static let sealTextureName = "sealbox(with seal)"
    private static let goldCoinsTextureName = "gold coins"

    // MARK: - Phase 8A Constants

    private static let goldCoinsAnchorName = "goldCoins"
    private static let stoneSlabEntityName = "stoneSlab"
    private static let frequencyClueEntityName = "frequencyClue"
    private static let barrierEntityName = "barrier"
    private static let seal2EntityName = "seal2"
    private static let coinTrailWalkFraction: Float = 0.35
    private static let coinCount = 14

    // MARK: - Phase 8B Constants

    private static let frequencyEmitterEntityName = "frequency_emitter_entity"
    private static let stoneButtonAudioName = "Stone button"
    private static let stoneButtonAudioExtension = "wav"
    private static let frequencyToneAudioName = "Frequency"
    private static let frequencyToneAudioExtension = "wav"
    private static let frequencyEmitterReferenceDistance: Float = 0.3
    private static let frequencyEmitterMaximumDistance: Float = 5.0
    private static let frequencyEmitterRolloffFactor: Float = 2.0

    // MARK: - Init

    override init() {
        arView = ARView(frame: .zero)
        super.init()
        arView.session.delegate = self
        // Deliver delegate callbacks on main so we can safely touch RealityKit.
        arView.session.delegateQueue = .main
        configureTapGesture()
    }

    // MARK: - Session Lifecycle

    func start(isHost: Bool) {
        guard !hasStarted else { return }
        hasStarted = true
        self.isHost = isHost

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        config.environmentTexturing = .automatic
        config.isCollaborationEnabled = true

        // LiDAR mesh collision lets spatial audio occlude through walls / adjacent rooms.
        arView.environment.sceneUnderstanding.options.insert(.collision)
        if arView.environment.sceneUnderstanding.options.contains(.occlusion) == false {
            arView.environment.sceneUnderstanding.options.insert(.occlusion)
        }

        UIApplication.shared.isIdleTimerDisabled = true
        // GameAudioSession.activatePlayback() already called in AppDelegate on launch.
        statusMessage = String(localized: "Look around to merge your worlds…")

        // On the Host, RoomPlan just released the camera. Give iOS a beat to hand
        // the capture over to ARKit, otherwise the passthrough stays black.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.hasStarted else { return }
            self.arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            print("🕯️ [AR] Session running (host: \(isHost))")
        }
        print("🕯️ [AR] Session start requested (host: \(isHost))")
    }

    func stop() {
        guard hasStarted else { return }
        hasStarted = false
        arView.session.pause()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Collaboration In

    /// Feeds an incoming collaboration payload from the peer into the local session.
    func update(with collaborationData: Data) {
        guard let collab = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: ARSession.CollaborationData.self,
            from: collaborationData
        ) else {
            print("🕯️ [AR] Failed to decode collaboration data")
            return
        }
        arView.session.update(with: collab)
    }

    // MARK: - Doll Spawning (Host authority)

    /// Called by the interactor when the worlds merge. Only the Host creates the
    /// anchor; collaboration then syncs it to the Guest, where both devices render
    /// the doll off the shared `ARAnchor` (see `session(_:didAdd:)`).
    func requestDollSpawn() {
        guard isHost else { return }
        wantsDoll = true
        attemptDollSpawn()
    }

    private func attemptDollSpawn() {
        guard isHost, wantsDoll, !dollAnchorAdded else { return }
        guard let transform = floorSpawnTransform() ?? raycastFloorFallback() else {
            statusMessage = String(localized: "Finding the floor… point at the ground.")
            return
        }
        let anchor = ARAnchor(name: Self.dollAnchorName, transform: transform)
        arView.session.add(anchor: anchor)
        dollAnchorAdded = true
        print("🕯️ [AR] Doll anchor added on floor")
    }

    /// Fallback when no floor plane is tracked yet: raycast from the screen centre
    /// to a horizontal surface and drop the doll there (translation only, upright).
    private func raycastFloorFallback() -> simd_float4x4? {
        guard arView.bounds.width > 0 else { return nil }
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        guard let query = arView.makeRaycastQuery(
            from: center,
            allowing: .estimatedPlane,
            alignment: .horizontal
        ), let hit = arView.session.raycast(query).first else {
            return nil
        }
        let t = hit.worldTransform.columns.3
        return SpatialMath.translation(simd_float3(t.x, t.y, t.z))
    }

    /// Picks a clear spot on the floor: the largest/lowest floor plane's centre,
    /// nudged away from walls and furniture via rejection sampling.
    private func floorSpawnTransform() -> simd_float4x4? {
        let floors = Array(floorPlanes.values)
        guard let floor = floors.min(by: { $0.transform.columns.3.y < $1.transform.columns.3.y })
        else { return nil }

        let centerLocal = simd_float4(floor.center.x, floor.center.y, floor.center.z, 1)
        let centerWorld4 = floor.transform * centerLocal
        let floorCenter = simd_float3(centerWorld4.x, centerWorld4.y, centerWorld4.z)

        // Keep the doll clear of walls and furniture, using each plane's footprint
        // (half-diagonal, capped so a large wall doesn't blank out the whole floor).
        let obstacles: [SpatialMath.FloorObstacle] = obstaclePlanes.values.map { plane in
            let c = plane.transform * simd_float4(plane.center.x, plane.center.y, plane.center.z, 1)
            let w = plane.planeExtent.width
            let h = plane.planeExtent.height
            let radius = min(0.75, 0.5 * (w * w + h * h).squareRoot())
            return SpatialMath.FloorObstacle(center: simd_float3(c.x, c.y, c.z), radius: radius)
        }

        // Search within the floor's smaller half-extent so we stay on the floor.
        let halfExtent = min(floor.planeExtent.width, floor.planeExtent.height) / 2
        let searchRadius = max(0.3, halfExtent * 0.8)

        let spot = RandomnessMath.clearFloorPoint(
            preferred: floorCenter,
            searchRadius: searchRadius,
            obstacles: obstacles,
            clearance: 0.4
        )
        return SpatialMath.translation(spot)
    }

    /// Removes the shared doll from the scene when the curse is activated.
    func removeDoll() {
        guard isDollSpawned || dollAnchorEntity != nil || dollAnchorAdded else { return }

        if let anchorEntity = dollAnchorEntity {
            arView.scene.removeAnchor(anchorEntity)
            dollAnchorEntity = nil
        }

        if isHost, dollAnchorAdded {
            for anchor in arView.session.currentFrame?.anchors ?? [] where anchor.name == Self.dollAnchorName {
                arView.session.remove(anchor: anchor)
            }
            dollAnchorAdded = false
        }

        wantsDoll = false
        isDollSpawned = false
        statusMessage = String(localized: "The curse has taken hold…")
        print("🕯️ [AR] Doll removed — curse activated")
    }

    // MARK: - Letter Spawning (Phase 6B — Host authority)

    /// Stores the local asymmetrical role before spawning the letter.
    func setLocalPlayerRole(_ role: PlayerRole) {
        localPlayerRole = role

        if let transform = pendingLetterTransform, !isLetterSpawned {
            pendingLetterTransform = nil
            spawnLetterAtSyncedTransform(transform, for: role)
        } else if let anchor = pendingLetterAnchor, !isLetterSpawned {
            spawnLetterEntity(on: anchor, for: role)
            pendingLetterAnchor = nil
        } else if isHost {
            attemptLetterSpawn()
        }
    }

    /// Host-only: Gaussian-pick a wall and add a shared anchor once roles are known.
    func requestLetterSpawn() {
        guard isHost else { return }
        wantsLetter = true
        attemptLetterSpawn()
    }

    /// Guest (or Host fallback): place the letter at an exact synced world transform.
    func spawnLetterAtSyncedTransform(_ transform: simd_float4x4, for role: PlayerRole) {
        guard !isLetterSpawned else { return }
        guard role != .unassigned else {
            pendingLetterTransform = transform
            print("📜 [AR] Letter transform queued — waiting for role")
            return
        }

        let anchorEntity = AnchorEntity(world: transform)
        letterAnchorEntity = anchorEntity
        arView.scene.addAnchor(anchorEntity)

        let worldPosition = SpatialMath.worldPosition(from: transform)
        finishLetterSpawn(
            on: anchorEntity,
            for: role,
            worldPosition: worldPosition
        )
    }

    private func attemptLetterSpawn() {
        guard isHost, wantsLetter, !letterAnchorAdded else { return }
        guard localPlayerRole != .unassigned else { return }
        guard let transform = computeLetterTransform() else {
            statusMessage = String(localized: "Point your camera at a wall…")
            print("📜 [AR] Letter spawn waiting — no wall transform yet")
            return
        }

        let anchor = ARAnchor(name: Self.letterAnchorName, transform: transform)
        arView.session.add(anchor: anchor)
        letterAnchorAdded = true

        if !isLetterSpawned {
            spawnLetterAtSyncedTransform(transform, for: localPlayerRole)
        }

        letterSpawned.send(transform)
        statusMessage = String(localized: "A hidden clue has been placed…")
        print("📜 [AR] Letter placed (\(spawnableWalls().count) wall candidates)")
    }

    private func computeLetterTransform() -> simd_float4x4? {
        guard let frame = arView.session.currentFrame else { return nil }

        let camera = SpatialMath.cameraPosition(from: frame)
        let floorY = SpatialMath.floorY(
            from: Array(floorPlanes.values),
            fallback: camera.y - SpatialMath.letterHeightAboveFloor
        )

        let walls = spawnableWalls()
        if let wall = RandomnessMath.pickWall(from: walls) {
            let lateralLimit = max(0.15, wall.planeExtent.width * 0.35)
            let lateralOffset = RandomnessMath.gaussianClamped(
                stdDev: wall.planeExtent.width * 0.18,
                limit: lateralLimit
            )
            return SpatialMath.letterTransform(
                on: wall,
                floorY: floorY,
                lateralOffset: lateralOffset
            )
        }

        return raycastWallTransform(floorY: floorY)
    }

    /// Raycasts into vertical planes / scene mesh when tracked wall list is empty.
    private func raycastWallTransform(floorY: Float) -> simd_float4x4? {
        guard arView.bounds.width > 0 else { return nil }

        var targets: [(ARRaycastQuery.Target, ARRaycastQuery.TargetAlignment)] = [
            (.existingPlaneGeometry, .vertical),
            (.estimatedPlane, .vertical),
            (.existingPlaneInfinite, .vertical)
        ]
        // LiDAR mesh hits use estimatedPlane + any alignment; filter to vertical below.
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
            || ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            targets.append((.estimatedPlane, .any))
        }

        let screenPoints = [
            CGPoint(x: arView.bounds.midX, y: arView.bounds.midY),
            CGPoint(x: arView.bounds.midX, y: arView.bounds.midY * 0.85),
            CGPoint(x: arView.bounds.midX * 0.75, y: arView.bounds.midY),
            CGPoint(x: arView.bounds.midX * 1.25, y: arView.bounds.midY)
        ]

        for point in screenPoints {
            for (target, alignment) in targets {
                guard let query = arView.makeRaycastQuery(
                    from: point,
                    allowing: target,
                    alignment: alignment
                ) else { continue }

                guard let hit = arView.session.raycast(query).first else { continue }
                guard SpatialMath.isVerticalWallHit(hit.worldTransform) else { continue }
                return SpatialMath.letterTransform(raycastTransform: hit.worldTransform, floorY: floorY)
            }
        }
        return nil
    }

    /// Filters vertical wall planes across all scanned rooms (tracked + live session).
    private func spawnableWalls() -> [ARPlaneAnchor] {
        var merged: [UUID: ARPlaneAnchor] = wallPlanes

        for anchor in arView.session.currentFrame?.anchors ?? [] {
            guard let plane = anchor as? ARPlaneAnchor else { continue }
            guard plane.alignment == .vertical else { continue }
            merged[plane.identifier] = plane
        }

        return Array(merged.values).filter { wall in
            max(wall.planeExtent.width, wall.planeExtent.height) >= Self.minimumWallExtent
        }
    }

    /// Host picks a wall from `anchors` using Gaussian weighting and places the letter
    /// at eye level (1.4 m above the floor).
    func spawnLetter(on anchors: [ARPlaneAnchor], for role: PlayerRole) {
        guard !isLetterSpawned else { return }
        guard let frame = arView.session.currentFrame else { return }

        let walls = anchors.filter {
            $0.alignment == .vertical
                && max($0.planeExtent.width, $0.planeExtent.height) >= Self.minimumWallExtent
        }
        guard let wall = RandomnessMath.pickWall(from: walls) else { return }

        let floorY = SpatialMath.floorY(
            from: anchors.filter { $0.alignment == .horizontal },
            fallback: SpatialMath.cameraPosition(from: frame).y - SpatialMath.letterHeightAboveFloor
        )
        let lateralLimit = max(0.15, wall.planeExtent.width * 0.35)
        let lateralOffset = RandomnessMath.gaussianClamped(
            stdDev: wall.planeExtent.width * 0.18,
            limit: lateralLimit
        )
        let transform = SpatialMath.letterTransform(
            on: wall,
            floorY: floorY,
            lateralOffset: lateralOffset
        )
        spawnLetterAtSyncedTransform(transform, for: role)
    }

    private func spawnLetterEntity(on anchor: ARAnchor, for role: PlayerRole) {
        guard !isLetterSpawned else { return }
        guard role != .unassigned else {
            pendingLetterAnchor = anchor
            return
        }

        spawnLetterAtSyncedTransform(anchor.transform, for: role)
    }

    private func finishLetterSpawn(on anchorEntity: AnchorEntity, for role: PlayerRole, worldPosition: simd_float3) {
        isLetterSpawned = true
        letterWorldPosition = worldPosition

        attachLetterContent(to: anchorEntity, for: role)

        statusMessage = role == .listener
            ? String(localized: "Listen… something is calling from the walls.")
            : String(localized: "Follow your partner. A clue awaits on the wall.")
        print("📜 [AR] Letter spawned for \(role.rawValue) at \(worldPosition)")
    }

    private func attachLetterContent(
        to anchorEntity: AnchorEntity,
        for role: PlayerRole
    ) {
        switch role {
        case .seer:
            // Seer sees the letter; no spatial audio (they must rely on the Listener).
            let visual = makeLetterVisual()
            anchorEntity.addChild(visual)
            configureLetterTap()

        case .listener:
            // Audio rides on the same anchor as the letter so both share one coordinate.
            Task { [weak self] in
                guard let self, self.letterAudioHandle == nil else { return }
                self.letterAudioHandle = await self.attachSpatialClueAudio(
                    to: anchorEntity,
                    resourceName: Self.letterAudioName,
                    fileExtension: Self.letterAudioExtension,
                    subdirectory: Self.letterAudioSubdirectory,
                    config: .init(
                        gain: Audio.Decibel(-3),
                        rolloffFactor: 1.0,
                        entityName: Self.letterEntityName + "_listener_audio"
                    )
                )
            }

        case .unassigned:
            break
        }
    }

    // MARK: - Phase 7A — Blood Trail & Pool (Seer visuals)

    struct BloodTrailSpawnResult {
        let destination: simd_float3
        let bendSide: Float
    }

    /// Host authority: picks destination, lays footprints on a curved line, spawns pool.
    @discardableResult
    func spawnBloodTrailAndPool() -> BloodTrailSpawnResult? {
        let bendSide: Float = Bool.random() ? 1 : -1
        return spawnBloodTrailAndPool(destination: nil, bendSide: bendSide)
    }

    /// Guest (or Host resync): uses the synced destination and curve direction.
    @discardableResult
    func spawnBloodTrailAtSyncedDestination(
        _ destination: simd_float3,
        bendSide: Float
    ) -> BloodTrailSpawnResult? {
        spawnBloodTrailAndPool(destination: destination, bendSide: bendSide)
    }

    @discardableResult
    private func spawnBloodTrailAndPool(
        destination syncedDestination: simd_float3?,
        bendSide: Float
    ) -> BloodTrailSpawnResult? {
        guard !hasSpawnedBloodTrail else { return nil }
        guard let floorY = resolvedFloorY() else {
            print("🩸 [AR] No floor height — skipping blood trail")
            return nil
        }

        let trailStart: simd_float3
        if let letterPosition = letterWorldPosition {
            trailStart = SpatialMath.projectToFloor(letterPosition, floorY: floorY)
        } else if let frame = arView.session.currentFrame {
            trailStart = SpatialMath.projectToFloor(
                SpatialMath.cameraPosition(from: frame),
                floorY: floorY
            )
        } else {
            print("🩸 [AR] No trail start — skipping blood trail")
            return nil
        }

        let destination: simd_float3
        if let syncedDestination {
            destination = SpatialMath.projectToFloor(syncedDestination, floorY: floorY)
        } else {
            let maxDimension: Float = floorPlanes.values
                .map { max($0.planeExtent.width, $0.planeExtent.height) }
                .max() ?? 3.0
            let walkDistance = max(1.4, maxDimension * Self.bloodTrailWalkFraction)
            destination = randomFloorDestination(from: trailStart, distance: walkDistance, floorY: floorY)
        }

        let curvedPath = generateCurvedFootstepPath(
            from: trailStart,
            to: destination,
            floorY: floorY,
            bendSide: bendSide
        )
        guard !curvedPath.isEmpty else {
            print("🩸 [AR] Empty footprint path — skipping blood trail")
            return nil
        }

        footstepsAnchorEntity = spawnFootsteps(along: curvedPath, floorY: floorY)

        let poolAnchor = AnchorEntity(world: SpatialMath.translation(destination))
        let poolSize = planeSize(for: Self.bloodPoolTextureName, baseWidth: 0.58)
        let poolEntity = makeBloodPoolEntity(poolSize: poolSize)
        poolAnchor.addChild(poolEntity)
        poolAnchor.addChild(makeBloodPoolTapVolume(poolSize: poolSize))
        arView.scene.addAnchor(poolAnchor)
        bloodPoolAnchorEntity = poolAnchor
        bloodPoolWorldPosition = destination

        if localPlayerRole == .seer {
            footstepsAnchorEntity?.isEnabled = true
            bloodPoolAnchorEntity?.isEnabled = true
            statusMessage = String(localized: "Follow the trail — tap the blood pool at the end")
        } else {
            footstepsAnchorEntity?.isEnabled = false
            bloodPoolAnchorEntity?.isEnabled = false
            spawnWhisperAudio(at: destination)
        }

        configureBloodPoolTap()
        hasSpawnedBloodTrail = true
        print("🩸 [AR] Blood trail spawned — \(curvedPath.count) steps to \(destination)")
        return BloodTrailSpawnResult(destination: destination, bendSide: bendSide)
    }

    private func resolvedFloorY() -> Float? {
        if !floorPlanes.isEmpty {
            return SpatialMath.floorY(from: Array(floorPlanes.values), fallback: 0)
        }
        if let letterPosition = letterWorldPosition {
            return letterPosition.y - SpatialMath.letterHeightAboveFloor
        }
        if let frame = arView.session.currentFrame {
            return SpatialMath.cameraPosition(from: frame).y - SpatialMath.letterHeightAboveFloor
        }
        return nil
    }

    private func floorObstacles() -> [SpatialMath.FloorObstacle] {
        obstaclePlanes.values.map { plane in
            let center = SpatialMath.worldCenter(of: plane)
            let extent = plane.planeExtent
            let radius = min(0.75, 0.5 * (extent.width * extent.width + extent.height * extent.height).squareRoot())
            return SpatialMath.FloorObstacle(center: center, radius: radius)
        }
    }

    /// Picks a random floor coordinate `distance` metres from `origin`, away from obstacles.
    private func randomFloorDestination(
        from origin: simd_float3,
        distance: Float,
        floorY: Float
    ) -> simd_float3 {
        let obstacles = floorObstacles()

        for _ in 0..<80 {
            let angle = Float.random(in: 0..<(2 * .pi))
            let candidate = SpatialMath.projectToFloor(
                simd_float3(
                    origin.x + distance * cos(angle),
                    floorY,
                    origin.z + distance * sin(angle)
                ),
                floorY: floorY
            )

            if SpatialMath.isClear(candidate, of: obstacles, clearance: 0.5) {
                return candidate
            }
        }

        return SpatialMath.projectToFloor(
            simd_float3(origin.x + distance, floorY, origin.z),
            floorY: floorY
        )
    }

    /// Lays footsteps on a single curved Bézier arc from the letter to the blood pool.
    private func generateCurvedFootstepPath(
        from start: simd_float3,
        to end: simd_float3,
        floorY: Float,
        bendSide: Float
    ) -> [simd_float3] {
        let startPoint = SpatialMath.projectToFloor(start, floorY: floorY)
        let endPoint = SpatialMath.projectToFloor(end, floorY: floorY)
        let travel = simd_float3(endPoint.x - startPoint.x, 0, endPoint.z - startPoint.z)
        let travelLength = simd_length(travel)

        guard travelLength > 0.15 else {
            return [startPoint, endPoint]
        }

        let forward = travel / travelLength
        let right = simd_float3(-forward.z, 0, forward.x)
        let midpoint = (startPoint + endPoint) * 0.5
        let control = SpatialMath.projectToFloor(
            midpoint + right * (Self.footprintMaxLateralBend * bendSide),
            floorY: floorY
        )
        let stepCount = max(8, min(22, Int(travelLength / Self.footprintStepSpacing) + 1))

        return SpatialMath.quadraticBezierPath(
            from: startPoint,
            control: control,
            to: endPoint,
            stepCount: stepCount
        )
    }

    /// Creates a trail of textured footprint decals along a curved floor path.
    private func spawnFootsteps(along path: [simd_float3], floorY: Float) -> AnchorEntity {
        let anchor = AnchorEntity(world: SpatialMath.translation(path[0]))
        anchor.name = Self.footstepsAnchorName
        let footprintSize = planeSize(for: Self.footstepsTextureName, baseWidth: Self.footprintBaseWidth)
        let material = loadDecalMaterial(
            named: Self.footstepsTextureName,
            fallbackColor: .init(red: 0.4, green: 0.01, blue: 0.02, alpha: 1.0)
        )

        for index in 0..<path.count {
            let current = path[index]
            let previous = path[max(index - 1, 0)]
            let next = path[min(index + 1, path.count - 1)]
            let tangent = simd_float3(next.x - previous.x, 0, next.z - previous.z)
            let tangentLength = simd_length(tangent)
            let direction = tangentLength > 0.001 ? tangent / tangentLength : simd_float3(0, 0, 1)
            let sideways = simd_float3(-direction.z, 0, direction.x)
            let sideOffset = (index % 2 == 0 ? 1.0 : -1.0) * footprintSize.width * 0.28

            var position = current + sideways * sideOffset
            position.y = floorY + Self.footprintFloorOffset
            position -= path[0]

            let step = ModelEntity(
                mesh: .generatePlane(width: footprintSize.width, depth: footprintSize.depth),
                materials: [material]
            )
            step.orientation = simd_quatf(angle: atan2f(direction.x, direction.z), axis: [0, 1, 0])
            step.position = position
            step.name = "footstep_\(index)"
            anchor.addChild(step)
        }

        arView.scene.addAnchor(anchor)
        print("🩸 [AR] Footsteps trail placed (\(path.count) steps)")
        return anchor
    }

    /// Creates the blood pool decal with collision and input targeting.
    private func makeBloodPoolEntity(poolSize: (width: Float, depth: Float)) -> ModelEntity {
        let mesh = MeshResource.generatePlane(width: poolSize.width, depth: poolSize.depth)
        let material = loadDecalMaterial(
            named: Self.bloodPoolTextureName,
            fallbackColor: .init(red: 0.35, green: 0.01, blue: 0.03, alpha: 0.95)
        )
        let pool = ModelEntity(mesh: mesh, materials: [material])
        pool.name = Self.bloodPoolEntityName
        pool.generateCollisionShapes(recursive: true)
        pool.components.set(InputTargetComponent())
        return pool
    }

    /// Invisible volume above the pool so taps are not swallowed by the LiDAR floor mesh.
    private func makeBloodPoolTapVolume(poolSize: (width: Float, depth: Float)) -> ModelEntity {
        let hitHeight: Float = 0.5
        let size = simd_float3(poolSize.width * 1.4, hitHeight, poolSize.depth * 1.4)
        let material = SimpleMaterial(
            color: .init(red: 0, green: 0, blue: 0, alpha: 0.01),
            isMetallic: false
        )

        let volume = ModelEntity(
            mesh: .generateBox(size: size),
            materials: [material]
        )
        volume.name = Self.bloodPoolTapVolumeName
        volume.position.y = hitHeight * 0.5
        volume.components.set(InputTargetComponent())
        volume.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
        return volume
    }

    private func configureBloodPoolTap() {
        guard !hasConfiguredBloodPoolTap else { return }
        hasConfiguredBloodPoolTap = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBloodPoolTap(_:)))
        arView.addGestureRecognizer(tap)
    }

    @objc private func handleBloodPoolTap(_ sender: UITapGestureRecognizer) {
        let location = sender.location(in: arView)
        guard isBloodPoolTap(at: location) else { return }
        print("🩸 [AR] Blood pool tapped by Seer")
        bloodPoolTapped.send(())
    }

    private func isBloodPoolTap(at location: CGPoint) -> Bool {
        if let tapped = arView.entity(at: location), isBloodPool(tapped) {
            return true
        }
        return isBloodPoolProximityTap(at: location)
    }

    /// Fallback when the reconstructed floor mesh wins the hit test instead of the decal.
    private func isBloodPoolProximityTap(at location: CGPoint) -> Bool {
        guard let poolPosition = bloodPoolWorldPosition,
              bloodPoolAnchorEntity?.isEnabled != false,
              let frame = arView.session.currentFrame else { return false }

        let cameraPosition = SpatialMath.cameraPosition(from: frame)
        guard SpatialMath.distanceXZ(cameraPosition, poolPosition) <= Self.bloodPoolTapProximityMeters else {
            return false
        }

        let aimPoint = simd_float3(poolPosition.x, poolPosition.y + 0.04, poolPosition.z)
        guard let projected = arView.project(aimPoint) else { return false }

        let dx = location.x - projected.x
        let dy = location.y - projected.y
        return (dx * dx + dy * dy).squareRoot() <= Self.bloodPoolTapScreenRadius
    }

    private func isBloodPool(_ entity: Entity) -> Bool {
        var current: Entity? = entity
        while let node = current {  
            if node.name == Self.bloodPoolEntityName
                || node.name == Self.bloodPoolTapVolumeName { return true }
            current = node.parent
        }
        return false
    }

    // MARK: - Phase 7B — Whispering Ghost (Listener spatial audio)

    /// Called by the interactor once the blood trail is spawned. Host only: places
    /// an invisible entity at the blood pool destination with aggressive spatial
    /// audio attenuation so the Listener must physically walk to find it.
    func spawnWhisperAudio(at destination: simd_float3) {
        Task { [weak self] in
            guard let self, self.whisperAudioHandle == nil else { return }
            self.whisperAudioHandle = await self.playSpatialClueAudio(
                resourceName: Self.whisperAudioName,
                fileExtension: Self.whisperAudioExtension,
                subdirectory: Self.whisperAudioSubdirectory,
                at: destination,
                config: .init(
                    gain: Audio.Decibel(-3),
                    rolloffFactor: 2.0,
                    entityName: Self.whisperEntityName
                )
            )
        }
        print("🩸 [AR] Whisper audio placed at \(destination)")
    }

    // MARK: - Phase 7C — First Seal Reveal

    /// Removes the blood trail entities (footsteps + blood pool) and the whisper.
    func removeBloodTrailEntities() {
        bloodPoolAnchorEntity.map { arView.scene.removeAnchor($0) }
        bloodPoolAnchorEntity = nil
        footstepsAnchorEntity.map { arView.scene.removeAnchor($0) }
        footstepsAnchorEntity = nil
        whisperAudioHandle?.stop(in: arView.scene)
        whisperAudioHandle = nil
        bloodPoolWorldPosition = nil
        hasSpawnedBloodTrail = false
        print("🩸 [AR] Blood trail entities removed")
    }

    /// Replaces the blood pool with a glowing seal placeholder at the same position.
    func revealFirstSeal(at position: simd_float3) {
        removeBloodTrailEntities()

        let sealAnchor = AnchorEntity(world: SpatialMath.translation(position))
        let seal = makeFirstSealEntity()
        sealAnchor.addChild(seal)
        arView.scene.addAnchor(sealAnchor)
        isFirstSealRevealed = true
        print("✨ [AR] First Seal revealed")
    }

    /// Creates the first seal using the sealbox texture from the asset catalog.
    private func makeFirstSealEntity() -> ModelEntity {
        let sealSize = planeSize(for: Self.sealTextureName, baseWidth: 0.32)
        let mesh = MeshResource.generatePlane(width: sealSize.width, depth: sealSize.depth)
        let material = loadTexturedMaterial(
            named: Self.sealTextureName,
            fallbackColor: .init(red: 0.1, green: 0.5, blue: 1.0, alpha: 1.0)
        )
        let seal = ModelEntity(mesh: mesh, materials: [material])
        seal.name = Self.bloodPoolWithSealName
        seal.generateCollisionShapes(recursive: true)
        seal.components.set(InputTargetComponent())

        Task { @MainActor in
            let baseScale: Float = 1.0
            let pulseRange: Float = 0.12
            let speed: Float = 2.0
            let startTime = CACurrentMediaTime()
            while seal.scene != nil {
                let elapsed = CACurrentMediaTime() - startTime
                let s = baseScale + pulseRange * sinf(Float(elapsed) * speed)
                seal.scale = SIMD3<Float>(repeating: s)
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }

        return seal
    }

    // MARK: - Phase 8A — Gold Coins, Stone Slab & Frequency Clue

    /// Spawns a trail of gold coins leading to a stone slab with a frequency clue.
    /// Seer-only visuals; hidden from the Listener via `isEnabled`.
    func spawnFrequencyPhase(at slabDestination: simd_float3? = nil) {
        guard !hasSpawnedFrequencyPhase else { return }

        let roomCenter: simd_float3
        if let firstFloor = floorPlanes.values.first {
            roomCenter = SpatialMath.worldCenter(of: firstFloor)
        } else if let frame = arView.session.currentFrame {
            roomCenter = SpatialMath.cameraPosition(from: frame)
        } else {
            print("🪙 [AR] No room reference — skipping frequency phase spawn")
            return
        }

        let maxDimension: Float = floorPlanes.values
            .map { max($0.planeExtent.width, $0.planeExtent.height) }
            .max() ?? 2.0
        let walkDistance = maxDimension * Self.coinTrailWalkFraction
        let floorY = resolvedFloorY() ?? roomCenter.y
        let destination = slabDestination ?? randomFloorDestination(
            from: roomCenter,
            distance: walkDistance,
            floorY: floorY
        )

        goldCoinsAnchorEntity = spawnGoldCoins(from: roomCenter, to: destination)
        stoneSlabAnchorEntity = spawnStoneSlab(at: destination)
        stoneSlabWorldPosition = destination

        frequencyClueAnchorEntity = spawnFrequencyClue(near: destination)
        barrierAnchorEntity = spawnBarrier(between: roomCenter, and: destination)

        let seerVisible = localPlayerRole == .seer
        goldCoinsAnchorEntity?.isEnabled = seerVisible
        stoneSlabAnchorEntity?.isEnabled = seerVisible
        frequencyClueAnchorEntity?.isEnabled = seerVisible
        barrierAnchorEntity?.isEnabled = seerVisible

        configureFrequencyPhaseTaps()
        hasSpawnedFrequencyPhase = true
        isFrequencyPhaseSpawned = true
        statusMessage = seerVisible
            ? String(localized: "A trail of gold glimmers across the floor…")
            : statusMessage
        print("🪙 [AR] Frequency phase spawned — slab at \(destination)")
    }

    /// Creates a trail of small shiny gold cylinders from `start` to `end`.
    private func spawnGoldCoins(from start: simd_float3, to end: simd_float3) -> AnchorEntity {
        let anchor = AnchorEntity(world: matrix_identity_float4x4)
        anchor.name = Self.goldCoinsAnchorName

        let coinSize = planeSize(for: Self.goldCoinsTextureName, baseWidth: 0.06)
        let material = loadDecalMaterial(
            named: Self.goldCoinsTextureName,
            fallbackColor: .init(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
        )

        for i in 0..<Self.coinCount {
            let t = Float(i) / Float(Self.coinCount - 1)
            let position = simd_float3(
                start.x + (end.x - start.x) * t,
                start.y + 0.012,
                start.z + (end.z - start.z) * t
            )
            let coin = ModelEntity(
                mesh: .generatePlane(width: coinSize.width, depth: coinSize.depth),
                materials: [material]
            )
            coin.name = "\(Self.goldCoinsAnchorName)_\(i)"
            coin.position = position
            anchor.addChild(coin)
        }

        arView.scene.addAnchor(anchor)
        return anchor
    }

    /// Creates a flat gray stone slab with a recessed hole in the center.
    private func spawnStoneSlab(at position: simd_float3) -> AnchorEntity {
        let anchor = AnchorEntity(world: SpatialMath.translation(position))

        let slabMaterial = SimpleMaterial(
            color: .init(red: 0.45, green: 0.43, blue: 0.40, alpha: 1.0),
            roughness: 0.85,
            isMetallic: false
        )
        let slab = ModelEntity(
            mesh: .generateBox(size: [0.55, 0.04, 0.55]),
            materials: [slabMaterial]
        )
        slab.name = Self.stoneSlabEntityName
        slab.position.y = 0.02
        anchor.addChild(slab)

        // Dark recessed hole in the center.
        let holeMaterial = SimpleMaterial(
            color: .init(red: 0.08, green: 0.07, blue: 0.06, alpha: 1.0),
            isMetallic: false
        )
        let hole = ModelEntity(
            mesh: .generateCylinder(height: 0.05, radius: 0.09),
            materials: [holeMaterial]
        )
        hole.position.y = 0.01
        anchor.addChild(hole)

        arView.scene.addAnchor(anchor)
        return anchor
    }

    /// Places a glowing clue plane beside the slab (wall-adjacent or floor offset).
    private func spawnFrequencyClue(near slabPosition: simd_float3) -> AnchorEntity {
        let offset = simd_float3(0.35, 0.0, 0.0)
        let cluePosition = simd_float3(
            slabPosition.x + offset.x,
            slabPosition.y + SpatialMath.letterHeightAboveFloor * 0.5,
            slabPosition.z + offset.z
        )

        let anchor = AnchorEntity(world: SpatialMath.translation(cluePosition))

        let material = SimpleMaterial(
            color: .init(red: 0.9, green: 0.75, blue: 0.2, alpha: 0.95),
            roughness: 0.2,
            isMetallic: true
        )
        let clue = ModelEntity(
            mesh: .generatePlane(width: 0.18, depth: 0.18),
            materials: [material]
        )
        clue.name = Self.frequencyClueEntityName
        clue.generateCollisionShapes(recursive: true)
        clue.components.set(InputTargetComponent())

        // Subtle glow pulse.
        Task { @MainActor in
            let startTime = CACurrentMediaTime()
            while clue.scene != nil {
                let elapsed = CACurrentMediaTime() - startTime
                let glow = 0.85 + 0.15 * sinf(Float(elapsed * 2.5))
                clue.scale = SIMD3<Float>(repeating: Float(glow))
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }

        anchor.addChild(clue)
        arView.scene.addAnchor(anchor)
        return anchor
    }

    /// Invisible-to-gameplay barrier the Seer must pass after the frequency puzzle.
    private func spawnBarrier(between start: simd_float3, and end: simd_float3) -> AnchorEntity {
        let midpoint = simd_float3(
            (start.x + end.x) * 0.5,
            start.y + 0.6,
            (start.z + end.z) * 0.5
        )
        let anchor = AnchorEntity(world: SpatialMath.translation(midpoint))

        let material = SimpleMaterial(
            color: .init(red: 0.15, green: 0.12, blue: 0.2, alpha: 0.55),
            isMetallic: false
        )
        let barrier = ModelEntity(
            mesh: .generateBox(size: [1.2, 1.2, 0.06]),
            materials: [material]
        )
        barrier.name = Self.barrierEntityName

        let dx = end.x - start.x
        let dz = end.z - start.z
        if dx != 0 || dz != 0 {
            let angle = atan2f(dx, dz)
            barrier.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
        }

        anchor.addChild(barrier)
        arView.scene.addAnchor(anchor)
        return anchor
    }

    /// Removes the hidden barrier blocking the Seer's path.
    func removeBarrier() {
        barrierAnchorEntity.map { arView.scene.removeAnchor($0) }
        barrierAnchorEntity = nil
        print("🪙 [AR] Barrier removed")
    }

    /// Spawns the second seal rising from the stone slab's central hole.
    func revealSecondSeal() {
        guard !isSecondSealRevealed else { return }
        guard let slabPosition = stoneSlabWorldPosition else {
            print("🪙 [AR] Cannot reveal second seal — no slab position")
            return
        }

        let sealPosition = simd_float3(slabPosition.x, slabPosition.y + 0.12, slabPosition.z)
        let sealAnchor = AnchorEntity(world: SpatialMath.translation(sealPosition))
        let seal = makeSecondSealEntity()
        sealAnchor.addChild(seal)
        arView.scene.addAnchor(sealAnchor)
        seal2AnchorEntity = sealAnchor
        isSecondSealRevealed = true
        statusMessage = String(localized: "The Second Seal has risen…")
        print("✨ [AR] Second Seal revealed")
    }

    /// Creates the glowing green second seal placeholder.
    private func makeSecondSealEntity() -> ModelEntity {
        let sealSize = planeSize(for: Self.sealTextureName, baseWidth: 0.18)
        let mesh = MeshResource.generatePlane(width: sealSize.width, depth: sealSize.depth)
        let material = loadTexturedMaterial(
            named: "sealbox(empty)",
            fallbackColor: .init(red: 0.1, green: 0.85, blue: 0.3, alpha: 1.0)
        )
        let seal = ModelEntity(mesh: mesh, materials: [material])
        seal.name = Self.seal2EntityName
        seal.generateCollisionShapes(recursive: true)
        seal.components.set(InputTargetComponent())

        Task { @MainActor in
            let startTime = CACurrentMediaTime()
            while seal.scene != nil {
                let elapsed = CACurrentMediaTime() - startTime
                let bob = 0.12 * sinf(Float(elapsed * 1.8))
                seal.position.y = bob
                let s = 1.0 + 0.1 * sinf(Float(elapsed * 2.5))
                seal.scale = SIMD3<Float>(repeating: s)
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }

        return seal
    }

    private func configureFrequencyPhaseTaps() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleFrequencyPhaseTap(_:)))
        arView.addGestureRecognizer(tap)
    }

    @objc private func handleFrequencyPhaseTap(_ sender: UITapGestureRecognizer) {
        let location = sender.location(in: arView)
        guard let tapped = arView.entity(at: location) else { return }

        if isFrequencyClue(tapped) {
            print("🪙 [AR] Frequency clue tapped by Seer")
            frequencyClueTapped.send(())
        } else if isSeal2(tapped) {
            print("✨ [AR] Second seal tapped by Seer")
            seal2Tapped.send(())
        }
    }

    private func isFrequencyClue(_ entity: Entity) -> Bool {
        var current: Entity? = entity
        while let node = current {
            if node.name == Self.frequencyClueEntityName { return true }
            current = node.parent
        }
        return false
    }

    private func isSeal2(_ entity: Entity) -> Bool {
        var current: Entity? = entity
        while let node = current {
            if node.name == Self.seal2EntityName { return true }
            current = node.parent
        }
        return false
    }

    // MARK: - Phase 8B — Frequency Scanner Emitter (Spatial Audio)

    /// Spawns an invisible spatial-audio emitter the Listener hunts by ear.
    /// Host picks the position; Guest uses the synced coordinate from the network.
    @discardableResult
    func spawnFrequencyEmitter(at syncedPosition: simd_float3? = nil) -> simd_float3? {
        guard !hasSpawnedFrequencyEmitter else { return frequencyEmitterWorldPosition }
        guard let floorY = resolvedFloorY() else { return nil }

        let position: simd_float3
        if let syncedPosition {
            position = SpatialMath.projectToFloor(syncedPosition, floorY: floorY)
        } else if let slab = stoneSlabWorldPosition {
            position = simd_float3(slab.x + 0.9, floorY + 0.1, slab.z + 0.4)
        } else if let frame = arView.session.currentFrame {
            let origin = SpatialMath.cameraPosition(from: frame)
            position = randomFloorDestination(from: origin, distance: 1.8, floorY: floorY)
        } else {
            return nil
        }
        let anchor = AnchorEntity(world: SpatialMath.translation(position))
        let entity = Entity()
        entity.name = Self.frequencyEmitterEntityName
        anchor.addChild(entity)

        entity.components.set(SpatialAudioComponent(
            gain: Audio.Decibel(-60),
            directivity: .beam(focus: 0),
            distanceAttenuation: .rolloff(factor: Double(Self.frequencyEmitterRolloffFactor))
        ))

        arView.scene.addAnchor(anchor)
        frequencyEmitterAnchor = anchor
        frequencyEmitterEntity = entity
        hasSpawnedFrequencyEmitter = true

        Task { await self.startFrequencyTone(on: entity) }
        print("📡 [AR] Frequency emitter spawned at \(position)")
        return position
    }

    var frequencyEmitterWorldPosition: simd_float3? {
        guard let entity = frequencyEmitterEntity else { return nil }
        let worldTransform = entity.transformMatrix(relativeTo: nil)
        return simd_float3(
            worldTransform.columns.3.x,
            worldTransform.columns.3.y,
            worldTransform.columns.3.z
        )
    }

    func playStoneButtonPress() {
        guard let entity = frequencyEmitterEntity else { return }
        Task {
            guard let url = stoneButtonAudioURL() else {
                print("🔊 [AR] Stone button audio not found in bundle")
                return
            }
            do {
                let resource = try await AudioFileResource(contentsOf: url)
                _ = entity.playAudio(resource)
                print("🔊 [AR] Stone button pressed")
            } catch {
                print("🔊 [AR] Failed to play stone button audio: \(error.localizedDescription)")
            }
        }
    }

    func updateFrequencyAudio(signalClarity: Double, distanceMeters: Double) {
        guard let entity = frequencyEmitterEntity else { return }
        guard var spatial = entity.components[SpatialAudioComponent.self] else { return }

        let clarity = Float(signalClarity)
        let clarityGain: Float
        if clarity <= 0.01 {
            clarityGain = -60
        } else {
            clarityGain = -60 + 57 * clarity
        }

        spatial.gain = Audio.Decibel(clarityGain)
        entity.components.set(spatial)
    }

    func removeFrequencyEmitter() {
        guard let anchor = frequencyEmitterAnchor else { return }
        arView.scene.removeAnchor(anchor)
        frequencyEmitterAnchor = nil
        frequencyEmitterEntity = nil
        hasSpawnedFrequencyEmitter = false
        print("📡 [AR] Frequency emitter removed")
    }

    private func startFrequencyTone(on entity: Entity) async {
        guard let url = frequencyToneAudioURL() else {
            print("🔊 [AR] Frequency tone not found — using silent emitter placeholder")
            return
        }
        do {
            let resource = try await AudioFileResource(
                contentsOf: url,
                configuration: .init(shouldLoop: true)
            )
            _ = entity.playAudio(resource)
        } catch {
            print("🔊 [AR] Failed to start frequency tone: \(error.localizedDescription)")
        }
    }

    private func stoneButtonAudioURL() -> URL? {
        bundleAudioURL(named: Self.stoneButtonAudioName, extension: Self.stoneButtonAudioExtension)
    }

    private func frequencyToneAudioURL() -> URL? {
        bundleAudioURL(named: Self.frequencyToneAudioName, extension: Self.frequencyToneAudioExtension)
    }

    private func bundleAudioURL(named name: String, extension ext: String) -> URL? {
        let bundle = Bundle.main
        return bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Sounds")
    }

    // MARK: - Spatial Audio

    /// Pins looping spatial audio onto an existing letter anchor (shared coordinate).
    private func attachSpatialClueAudio(
        to anchorEntity: AnchorEntity,
        resourceName: String,
        fileExtension: String,
        subdirectory: String?,
        config: SpatialAudioEmitter.Config
    ) async -> SpatialAudioEmitter.Handle? {
        guard let url = SpatialAudioEmitter.bundleURL(
            named: resourceName,
            extension: fileExtension,
            subdirectory: subdirectory
        ) else {
            print("🔊 [AR] Audio not found: \(resourceName).\(fileExtension)")
            return nil
        }

        do {
            let handle = try await SpatialAudioEmitter.attach(
                to: anchorEntity,
                audioURL: url,
                config: config
            )
            let position = SpatialMath.worldPosition(from: anchorEntity.transformMatrix(relativeTo: nil))
            print("🔊 [AR] Spatial audio attached to letter at \(position)")
            return handle
        } catch {
            print("🔊 [AR] Failed to attach spatial audio: \(error.localizedDescription)")
            return nil
        }
    }

    /// Starts looping spatial audio at an exact world coordinate.
    private func playSpatialClueAudio(
        resourceName: String,
        fileExtension: String,
        subdirectory: String?,
        at worldPosition: simd_float3,
        config: SpatialAudioEmitter.Config
    ) async -> SpatialAudioEmitter.Handle? {
        guard let url = SpatialAudioEmitter.bundleURL(
            named: resourceName,
            extension: fileExtension,
            subdirectory: subdirectory
        ) else {
            print("🔊 [AR] Audio not found: \(resourceName).\(fileExtension)")
            return nil
        }

        do {
            let handle = try await SpatialAudioEmitter.play(
                in: arView.scene,
                audioURL: url,
                at: worldPosition,
                config: config
            )
            print("🔊 [AR] Spatial audio playing at \(worldPosition)")
            return handle
        } catch {
            print("🔊 [AR] Failed to start spatial audio: \(error.localizedDescription)")
            return nil
        }
    }

    private func makeLetterVisual() -> ModelEntity {
        let letterSize = planeSize(for: Self.letterTextureName, baseWidth: 0.28)
        let mesh = MeshResource.generatePlane(width: letterSize.width, depth: letterSize.depth)
        let material = loadDecalMaterial(
            named: Self.letterTextureName,
            fallbackColor: .white
        )
        let letter = ModelEntity(mesh: mesh, materials: [material])
        letter.name = Self.letterEntityName
        letter.generateCollisionShapes(recursive: true)
        letter.components.set(InputTargetComponent())
        return letter
    }

    private func configureLetterTap() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleLetterTap(_:)))
        arView.addGestureRecognizer(tap)
    }

    @objc private func handleLetterTap(_ sender: UITapGestureRecognizer) {
        let location = sender.location(in: arView)
        guard let tapped = arView.entity(at: location),
              let entity = tapped as? ModelEntity,
              entity.name == Self.letterEntityName else { return }
        print("📜 [AR] Letter tapped by Seer")
        letterTapped.send(())
    }

    // MARK: - Textured AR Billboards

    /// Loads an unlit textured material from the asset catalog, with a solid-color fallback.
    /// Transparent PNG regions are rendered correctly (no black fill) via alpha blending.
    private func loadTexturedMaterial(named assetName: String, fallbackColor: UIColor) -> Material {
        guard let image = UIImage(named: assetName)?.withRenderingMode(.alwaysOriginal),
              let cgImage = image.cgImage else {
            print("🖼️ [AR] Missing texture '\(assetName)' — using fallback color")
            return SimpleMaterial(color: .init(cgColor: fallbackColor.cgColor), roughness: 0.8, isMetallic: false)
        }

        let hasAlpha = imageHasAlpha(cgImage)

        do {
            let texture = try TextureResource(
                image: cgImage,
                options: .init(semantic: .color)
            )

            var material = UnlitMaterial()
            // Slightly transparent tint forces RealityKit to honour the texture alpha channel.
            material.color = .init(
                tint: hasAlpha ? .white.withAlphaComponent(0.9999) : .white,
                texture: .init(texture)
            )
            if hasAlpha {
                material.blending = .transparent(opacity: .init(floatLiteral: 1.0))
            }
            material.faceCulling = .none
            return material
        } catch {
            print("🖼️ [AR] Failed to load texture '\(assetName)': \(error.localizedDescription)")
            return SimpleMaterial(color: .init(cgColor: fallbackColor.cgColor), roughness: 0.8, isMetallic: false)
        }
    }

    private func imageHasAlpha(_ cgImage: CGImage) -> Bool {
        switch cgImage.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            return true
        }
    }

    /// Loads a floor decal texture with alpha blending and dark-pixel removal.
    private func loadDecalMaterial(named assetName: String, fallbackColor: UIColor) -> Material {
        guard let source = UIImage(named: assetName)?.cgImage else {
            print("🖼️ [AR] Missing decal '\(assetName)' — using fallback color")
            return SimpleMaterial(color: .init(cgColor: fallbackColor.cgColor), isMetallic: false)
        }

        let cgImage = cgImageByStrippingDarkBackground(source) ?? source

        do {
            let texture = try TextureResource.generate(
                from: cgImage,
                options: .init(semantic: .color)
            )
            var material = UnlitMaterial()
            material.color = .init(tint: .white, texture: .init(texture))
            material.blending = .transparent(opacity: .init(scale: 1.0))
            return material
        } catch {
            print("🖼️ [AR] Failed to load decal '\(assetName)': \(error.localizedDescription)")
            return SimpleMaterial(color: .init(cgColor: fallbackColor.cgColor), isMetallic: false)
        }
    }

    /// Converts near-black pixels to transparent so decal PNGs don't show a square backdrop.
    private func cgImageByStrippingDarkBackground(_ source: CGImage, threshold: UInt8 = 42) -> CGImage? {
        let width = source.width
        let height = source.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }

        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)
        for offset in stride(from: 0, to: width * height * bytesPerPixel, by: bytesPerPixel) {
            let red = pixels[offset]
            let green = pixels[offset + 1]
            let blue = pixels[offset + 2]
            if red <= threshold, green <= threshold, blue <= threshold {
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 0
            }
        }

        return context.makeImage()
    }

    /// Returns plane width/depth preserving the source image aspect ratio.
    private func planeSize(for assetName: String, baseWidth: Float) -> (width: Float, depth: Float) {
        guard let image = UIImage(named: assetName), image.size.height > 0 else {
            return (baseWidth, baseWidth)
        }
        let aspect = Float(image.size.width / image.size.height)
        return (baseWidth, baseWidth / aspect)
    }

    // MARK: - Doll Rendering (both devices)

    private func spawnDollEntity(on anchor: ARAnchor) {
        guard !isDollSpawned else { return }
        isDollSpawned = true

        let anchorEntity = AnchorEntity(anchor: anchor)
        dollAnchorEntity = anchorEntity
        arView.scene.addAnchor(anchorEntity)
        statusMessage = String(localized: "Summoning the doll…")

        Task { @MainActor in
            let doll = await loadDoll()
            anchorEntity.addChild(doll)
            statusMessage = String(localized: "The doll has appeared. Tap it.")
            print("🕯️ [AR] Doll entity rendered")
        }
    }

    private func dollModelURL() -> URL? {
        let bundle = Bundle.main
        return bundle.url(
            forResource: Self.dollModelName,
            withExtension: "usdz",
            subdirectory: "Models"
        ) ?? bundle.url(forResource: Self.dollModelName, withExtension: "usdz")
    }

    /// Loads the scanned doll USDZ from the app bundle, falling back to a purple
    /// placeholder if the asset is missing or fails to decode.
    private func loadDoll() async -> Entity {
        guard let url = dollModelURL() else {
            print("🕯️ [AR] Doll USDZ not found in bundle — using placeholder")
            return makePlaceholderDoll()
        }

        do {
            let model = try await Entity(contentsOf: url)
            return configureLoadedDoll(model)
        } catch {
            print("🕯️ [AR] Failed to load doll USDZ: \(error.localizedDescription)")
            return makePlaceholderDoll()
        }
    }

    private func configureLoadedDoll(_ model: Entity) -> Entity {
        let container = Entity()
        container.name = Self.dollEntityName

        let bounds = model.visualBounds(relativeTo: nil)
        if bounds.extents.y > 0 {
            let scale = Self.dollTargetHeight / bounds.extents.y
            model.scale = simd_float3(repeating: scale)
        }
        let scaledBounds = model.visualBounds(relativeTo: nil)
        model.position.y = -scaledBounds.min.y

        container.addChild(model)
        container.generateCollisionShapes(recursive: true)
        container.components.set(InputTargetComponent())
        return container
    }

    /// Purple placeholder doll (body + head). Tappable via collision + input target.
    private func makePlaceholderDoll() -> ModelEntity {
        let bodyHeight = Self.dollTargetHeight
        let material = SimpleMaterial(color: .purple, roughness: 0.4, isMetallic: false)

        let body = ModelEntity(
            mesh: .generateBox(size: [0.18, bodyHeight, 0.14], cornerRadius: 0.04),
            materials: [material]
        )
        body.position.y = bodyHeight / 2
        body.name = Self.dollEntityName

        let head = ModelEntity(mesh: .generateSphere(radius: 0.11), materials: [material])
        head.position.y = bodyHeight / 2 + 0.16
        head.name = Self.dollEntityName
        body.addChild(head)

        body.generateCollisionShapes(recursive: true)
        body.components.set(InputTargetComponent())
        return body
    }

    // MARK: - Tap Handling

    private func configureTapGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tap)
    }

    @objc private func handleTap(_ sender: UITapGestureRecognizer) {
        guard isDollSpawned else { return }
        let location = sender.location(in: arView)
        guard let tapped = arView.entity(at: location), isDoll(tapped) else { return }
        print("🕯️ [AR] Doll tapped locally")
        dollTapped.send(())
    }

    private func isDoll(_ entity: Entity) -> Bool {
        var current: Entity? = entity
        while let node = current {
            if node.name == Self.dollEntityName { return true }
            current = node.parent
        }
        return false
    }

    // MARK: - Plane Bookkeeping

    private func track(_ plane: ARPlaneAnchor) {
        switch plane.classification {
        case .floor:
            floorPlanes[plane.identifier] = plane
            wallPlanes.removeValue(forKey: plane.identifier)
            obstaclePlanes.removeValue(forKey: plane.identifier)
        case .wall, .door, .window:
            wallPlanes[plane.identifier] = plane
            obstaclePlanes[plane.identifier] = plane
        case .ceiling, .table, .seat:
            obstaclePlanes[plane.identifier] = plane
        default:
            if plane.alignment == .horizontal {
                floorPlanes[plane.identifier] = plane
                wallPlanes.removeValue(forKey: plane.identifier)
                obstaclePlanes.removeValue(forKey: plane.identifier)
            } else if plane.alignment == .vertical {
                wallPlanes[plane.identifier] = plane
                obstaclePlanes[plane.identifier] = plane
            } else {
                obstaclePlanes[plane.identifier] = plane
            }
        }
    }
}

// MARK: - ARSessionDelegate

extension ARService: ARSessionDelegate {

    nonisolated func session(
        _ session: ARSession,
        didOutputCollaborationData data: ARSession.CollaborationData
    ) {
        let isCritical = (data.priority == .critical)
        guard let encoded = try? NSKeyedArchiver.archivedData(
            withRootObject: data,
            requiringSecureCoding: true
        ) else { return }

        MainActor.assumeIsolated {
            self.outgoingCollaborationData.send(
                CollaborationPayload(data: encoded, isCritical: isCritical)
            )
        }
    }

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        MainActor.assumeIsolated {
            for anchor in anchors {
                if anchor is ARParticipantAnchor {
                    if !self.hasMergedWorlds {
                        self.hasMergedWorlds = true
                        self.statusMessage = String(localized: "Worlds merged. Summoning the doll…")
                        print("🕯️ [AR] Participant anchor detected — worlds merged")
                    }
                } else if anchor.name == Self.dollAnchorName {
                    self.spawnDollEntity(on: anchor)
                } else if anchor.name == Self.letterAnchorName {
                    if !self.isLetterSpawned {
                        self.spawnLetterEntity(on: anchor, for: self.localPlayerRole)
                    }
                } else if let plane = anchor as? ARPlaneAnchor {
                    self.track(plane)
                    self.attemptDollSpawn()
                    self.attemptLetterSpawn()
                }
            }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        MainActor.assumeIsolated {
            for anchor in anchors where anchor is ARPlaneAnchor {
                if let plane = anchor as? ARPlaneAnchor {
                    self.track(plane)
                }
            }
            self.attemptDollSpawn()
            self.attemptLetterSpawn()
        }
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        MainActor.assumeIsolated {
            for anchor in anchors {
                self.floorPlanes.removeValue(forKey: anchor.identifier)
                self.wallPlanes.removeValue(forKey: anchor.identifier)
                self.obstaclePlanes.removeValue(forKey: anchor.identifier)
            }
        }
    }
}
