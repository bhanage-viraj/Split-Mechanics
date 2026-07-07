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
    @Published private(set) var statusMessage = "Starting AR…"

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
    private var letterAudioController: AudioPlaybackController?
    private var pendingLetterAnchor: ARAnchor?
    private var pendingLetterTransform: simd_float4x4?

    // MARK: - Phase 7 Private State

    private var bloodPoolAnchorEntity: AnchorEntity?
    private var footstepsAnchorEntity: AnchorEntity?
    private var whisperAudioController: AudioPlaybackController?
    private var hasSpawnedBloodTrail = false

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
    private static let bloodPoolWithSealName = "blood_pool_with_seal"
    private static let footstepsAnchorName = "footsteps_anchor"
    private static let whisperEntityName = "whisper_audio_entity"
    private static let whisperAudioName = "BGM"
    private static let whisperAudioExtension = "mp3"
    private static let whisperAudioSubdirectory = "Sounds"
    private static let bloodTrailWalkFraction: Float = 0.30   // 30% of the room's longest floor dimension

    // MARK: - Phase 6 / 7 Texture Assets (Assets.xcassets)

    private static let letterTextureName = "letter"
    private static let footstepsTextureName = "footsteps"
    private static let bloodPoolTextureName = "blood pool (hint1)"
    private static let sealTextureName = "sealbox(with seal)"

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
        statusMessage = "Look around to merge your worlds…"

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
            statusMessage = "Finding the floor… point at the ground."
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
        statusMessage = "The curse has taken hold…"
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

        let position = transform.columns.3
        finishLetterSpawn(
            on: anchorEntity,
            for: role,
            worldPosition: simd_float3(position.x, position.y, position.z)
        )
    }

    private func attemptLetterSpawn() {
        guard isHost, wantsLetter, !letterAnchorAdded else { return }
        guard localPlayerRole != .unassigned else { return }
        guard let transform = computeLetterTransform() else {
            statusMessage = "Point your camera at a wall…"
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
        statusMessage = "A hidden clue has been placed…"
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
        if let wall = RandomnessMath.pickWall(from: walls, cameraPosition: camera) {
            let lateralLimit = max(0.15, wall.planeExtent.width * 0.35)
            let lateralOffset = RandomnessMath.gaussianClamped(
                stdDev: wall.planeExtent.width * 0.18,
                limit: lateralLimit
            )
            return SpatialMath.letterTransform(on: wall, floorY: floorY, lateralOffset: lateralOffset)
        }

        if let raycastTransform = raycastWallTransform(floorY: floorY) {
            return raycastTransform
        }

        return SpatialMath.letterTransformInFrontOfCamera(frame: frame, floorY: floorY)
    }

    /// Raycasts into vertical planes / scene geometry when tracked wall list is empty.
    private func raycastWallTransform(floorY: Float) -> simd_float4x4? {
        guard arView.bounds.width > 0 else { return nil }
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)

        let targets: [(ARRaycastQuery.Target, ARRaycastQuery.TargetAlignment)] = [
            (.existingPlaneGeometry, .vertical),
            (.estimatedPlane, .vertical),
            (.existingPlaneGeometry, .any)
        ]

        for (target, alignment) in targets {
            guard let query = arView.makeRaycastQuery(
                from: center,
                allowing: target,
                alignment: alignment
            ) else { continue }

            guard let hit = arView.session.raycast(query).first else { continue }
            return SpatialMath.letterTransform(raycastTransform: hit.worldTransform, floorY: floorY)
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
        guard let wall = RandomnessMath.pickWall(
            from: walls,
            cameraPosition: SpatialMath.cameraPosition(from: frame)
        ) else { return }

        let floorY = SpatialMath.floorY(
            from: anchors.filter { $0.alignment == .horizontal },
            fallback: SpatialMath.cameraPosition(from: frame).y - SpatialMath.letterHeightAboveFloor
        )
        let lateralLimit = max(0.15, wall.planeExtent.width * 0.35)
        let lateralOffset = RandomnessMath.gaussianClamped(
            stdDev: wall.planeExtent.width * 0.18,
            limit: lateralLimit
        )
        let transform = SpatialMath.letterTransform(on: wall, floorY: floorY, lateralOffset: lateralOffset)
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
            ? "Listen… something is calling from the walls."
            : "Follow your partner. A clue awaits on the wall."
        print("📜 [AR] Letter spawned for \(role.rawValue) at \(worldPosition)")
    }

    private func attachLetterContent(to anchorEntity: AnchorEntity, for role: PlayerRole) {
        switch role {
        case .seer:
            // Seer sees the letter; no spatial audio (they must rely on the Listener).
            let visual = makeLetterVisual()
            anchorEntity.addChild(visual)
            configureLetterTap()

        case .listener:
            // Listener cannot see the letter — only hears it via RealityKit spatial audio.
            let listenerAudio = Entity()
            listenerAudio.name = Self.letterEntityName + "_listener"
            anchorEntity.addChild(listenerAudio)
            listenerAudio.components.set(SpatialAudioComponent(
                gain: Audio.Decibel(-3),
                directivity: .beam(focus: 0),
                distanceAttenuation: .rolloff(factor: 1.0)
            ))
            Task { await self.startLetterSpatialAudio(on: listenerAudio) }

        case .unassigned:
            break
        }
    }

    // MARK: - Phase 7A — Blood Trail & Pool (Seer visuals)

    /// Called by the interactor once the letter phase is done. Host only: picks a
    /// floor spot ~30% of the room's longest dimension away from the room center,
    /// spawns a trail of red footsteps and a blood pool at the destination.
    func spawnBloodTrailAndPool() {
        guard !hasSpawnedBloodTrail else { return }

        let roomCenter: simd_float3
        if let firstFloor = floorPlanes.values.first {
            roomCenter = SpatialMath.worldCenter(of: firstFloor)
        } else if let frame = arView.session.currentFrame {
            roomCenter = SpatialMath.cameraPosition(from: frame)
        } else {
            print("🩸 [AR] No room reference — skipping blood trail")
            return
        }

        // Compute room radius: longest horizontal extent among floor planes.
        let maxDimension: Float = floorPlanes.values.map { max($0.planeExtent.width, $0.planeExtent.height) }.max() ?? 2.0
        let walkDistance = maxDimension * Self.bloodTrailWalkFraction

        // Pick a destination away from the room center (rejection sample).
        let destination = randomFloorDestination(from: roomCenter, distance: walkDistance)

        // Spawn footsteps trail.
        footstepsAnchorEntity = spawnFootsteps(from: roomCenter, to: destination)

        // Spawn blood pool at the destination.
        let poolAnchor = AnchorEntity(world: SpatialMath.translation(destination))
        let poolEntity = makeBloodPoolEntity()
        poolAnchor.addChild(poolEntity)
        arView.scene.addAnchor(poolAnchor)
        bloodPoolAnchorEntity = poolAnchor
        bloodPoolWorldPosition = destination

        // Asymmetrical visibility: only the Seer can see the blood trail.
        // The Listener gets the whisper audio entity instead.
        if localPlayerRole == .seer {
            footstepsAnchorEntity?.isEnabled = true
            bloodPoolAnchorEntity?.isEnabled = true
        } else {
            footstepsAnchorEntity?.isEnabled = false
            bloodPoolAnchorEntity?.isEnabled = false
            spawnWhisperAudio(at: destination)
        }

        configureBloodPoolTap()
        hasSpawnedBloodTrail = true
        print("🩸 [AR] Blood trail spawned — destination: \(destination)")
    }

    /// Picks a random floor coordinate `distance` metres from `origin`, clamped to
    /// a tracked floor plane and away from obstacles.
    private func randomFloorDestination(from origin: simd_float3, distance: Float) -> simd_float3 {
        let obstacles: [SpatialMath.FloorObstacle] = obstaclePlanes.values.map { plane in
            let c = SpatialMath.worldCenter(of: plane)
            let w = plane.planeExtent.width
            let h = plane.planeExtent.height
            let radius = min(0.75, 0.5 * (w * w + h * h).squareRoot())
            return SpatialMath.FloorObstacle(center: c, radius: radius)
        }

        // Rejection-sample a point at the target distance from origin.
        for _ in 0..<60 {
            let angle = Float.random(in: 0..<(2 * .pi))
            let candidate = simd_float3(
                origin.x + distance * cos(angle),
                origin.y,
                origin.z + distance * sin(angle)
            )
            // Clamp Y to the floor.
            let floorY = SpatialMath.floorY(from: Array(floorPlanes.values), fallback: origin.y)
            let clamped = simd_float3(candidate.x, floorY, candidate.z)

            if SpatialMath.isClear(clamped, of: obstacles, clearance: 0.5) {
                return clamped
            }
        }
        return simd_float3(origin.x + distance, origin.y, origin.z)
    }

    /// Creates a trail of textured footprint decals from `start` to `end`.
    private func spawnFootsteps(from start: simd_float3, to end: simd_float3) -> AnchorEntity {
        let anchor = AnchorEntity(world: matrix_identity_float4x4)
        anchor.name = Self.footstepsAnchorName
        let stepCount = 12
        let footprintSize = planeSize(for: Self.footstepsTextureName, baseWidth: 0.14)
        let material = loadTexturedMaterial(
            named: Self.footstepsTextureName,
            fallbackColor: .init(red: 0.4, green: 0.01, blue: 0.02, alpha: 1.0)
        )

        for i in 0..<stepCount {
            let t = Float(i) / Float(stepCount - 1)
            let position = simd_float3(
                start.x + (end.x - start.x) * t,
                start.y + 0.005,
                start.z + (end.z - start.z) * t
            )
            let step = ModelEntity(
                mesh: .generatePlane(width: footprintSize.width, depth: footprintSize.depth),
                materials: [material]
            )
            let dx = end.x - start.x
            let dz = end.z - start.z
            if dx != 0 || dz != 0 {
                let angle = atan2f(dx, dz)
                step.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
            }
            step.position = position
            step.name = "footstep_\(i)"
            anchor.addChild(step)
        }

        arView.scene.addAnchor(anchor)
        print("🩸 [AR] Footsteps trail placed (\(stepCount) steps)")
        return anchor
    }

    /// Creates the blood pool decal with collision and input targeting.
    private func makeBloodPoolEntity() -> ModelEntity {
        let poolSize = planeSize(for: Self.bloodPoolTextureName, baseWidth: 0.45)
        let mesh = MeshResource.generatePlane(width: poolSize.width, depth: poolSize.depth)
        let material = loadTexturedMaterial(
            named: Self.bloodPoolTextureName,
            fallbackColor: .init(red: 0.35, green: 0.01, blue: 0.03, alpha: 0.95)
        )
        let pool = ModelEntity(mesh: mesh, materials: [material])
        pool.name = Self.bloodPoolEntityName
        pool.generateCollisionShapes(recursive: true)
        pool.components.set(InputTargetComponent())
        return pool
    }

    private func configureBloodPoolTap() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBloodPoolTap(_:)))
        arView.addGestureRecognizer(tap)
    }

    @objc private func handleBloodPoolTap(_ sender: UITapGestureRecognizer) {
        let location = sender.location(in: arView)
        guard let tapped = arView.entity(at: location),
              isBloodPool(tapped) else { return }
        print("🩸 [AR] Blood pool tapped by Seer")
        bloodPoolTapped.send(())
    }

    private func isBloodPool(_ entity: Entity) -> Bool {
        var current: Entity? = entity
        while let node = current {
            if node.name == Self.bloodPoolEntityName { return true }
            current = node.parent
        }
        return false
    }

    // MARK: - Phase 7B — Whispering Ghost (Listener spatial audio)

    /// Called by the interactor once the blood trail is spawned. Host only: places
    /// an invisible entity at the blood pool destination with aggressive spatial
    /// audio attenuation so the Listener must physically walk to find it.
    func spawnWhisperAudio(at destination: simd_float3) {
        let whisperAnchor = AnchorEntity(world: SpatialMath.translation(destination))
        let whisperEntity = Entity()
        whisperEntity.name = Self.whisperEntityName
        whisperAnchor.addChild(whisperEntity)

        whisperEntity.components.set(SpatialAudioComponent(
            gain: Audio.Decibel(-3),
            directivity: .beam(focus: 0),
            distanceAttenuation: .rolloff(factor: 2.0)
        ))

        arView.scene.addAnchor(whisperAnchor)

        Task { await self.startWhisperSpatialAudio(on: whisperEntity) }
        print("🩸 [AR] Whisper audio placed — aggressive attenuation (ref: 0.2m, max: 4.0m)")
    }

    /// Loads BGM.mp3 and loops it from the invisible whisper entity.
    private func startWhisperSpatialAudio(on entity: Entity) async {
        guard whisperAudioController == nil else { return }
        guard let url = whisperAudioURL() else {
            print("🩸 [AR] Whisper audio not found in bundle")
            return
        }

        do {
            let resource = try await AudioFileResource(
                contentsOf: url,
                configuration: .init(shouldLoop: true)
            )
            whisperAudioController = entity.playAudio(resource)
            print("🩸 [AR] Whisper spatial audio playing (BGM.mp3)")
        } catch {
            print("🩸 [AR] Failed to load whisper audio: \(error.localizedDescription)")
        }
    }

    // MARK: - Phase 7C — First Seal Reveal

    /// Removes the blood trail entities (footsteps + blood pool) and the whisper.
    func removeBloodTrailEntities() {
        bloodPoolAnchorEntity.map { arView.scene.removeAnchor($0) }
        bloodPoolAnchorEntity = nil
        footstepsAnchorEntity.map { arView.scene.removeAnchor($0) }
        footstepsAnchorEntity = nil
        whisperAudioController?.stop()
        whisperAudioController = nil
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

    // MARK: - Audio URL Helper

    private func whisperAudioURL() -> URL? {
        let bundle = Bundle.main
        return bundle.url(
            forResource: Self.whisperAudioName,
            withExtension: Self.whisperAudioExtension,
            subdirectory: Self.whisperAudioSubdirectory
        ) ?? bundle.url(
            forResource: Self.whisperAudioName,
            withExtension: Self.whisperAudioExtension
        )
    }

    private func letterAudioURL() -> URL? {
        let bundle = Bundle.main
        return bundle.url(
            forResource: Self.letterAudioName,
            withExtension: Self.letterAudioExtension,
            subdirectory: Self.letterAudioSubdirectory
        ) ?? bundle.url(
            forResource: Self.letterAudioName,
            withExtension: Self.letterAudioExtension
        )
    }

    /// Loads BGM.mp3 and loops it from the invisible listener-only audio entity.
    private func startLetterSpatialAudio(on entity: Entity) async {
        guard letterAudioController == nil else { return }
        guard let url = letterAudioURL() else {
            print("📜 [AR] Letter audio not found in bundle")
            return
        }

        do {
            let resource = try await AudioFileResource(
                contentsOf: url,
                configuration: .init(shouldLoop: true)
            )
            letterAudioController = entity.playAudio(resource)
            print("📜 [AR] Letter spatial audio playing")
        } catch {
            print("📜 [AR] Failed to load letter audio: \(error.localizedDescription)")
        }
    }

    private func makeLetterVisual() -> ModelEntity {
        let letterSize = planeSize(for: Self.letterTextureName, baseWidth: 0.28)
        let mesh = MeshResource.generatePlane(width: letterSize.width, depth: letterSize.depth)
        let material = loadTexturedMaterial(
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
    private func loadTexturedMaterial(named assetName: String, fallbackColor: UIColor) -> Material {
        guard let image = UIImage(named: assetName),
              let cgImage = image.cgImage else {
            print("🖼️ [AR] Missing texture '\(assetName)' — using fallback color")
            return SimpleMaterial(color: .init(cgColor: fallbackColor.cgColor), isMetallic: false)
        }

        do {
            let texture = try TextureResource.generate(
                from: cgImage,
                options: .init(semantic: .color)
            )
            var material = UnlitMaterial()
            material.color = .init(tint: .white, texture: .init(texture))
            return material
        } catch {
            print("🖼️ [AR] Failed to load texture '\(assetName)': \(error.localizedDescription)")
            return SimpleMaterial(color: .init(cgColor: fallbackColor.cgColor), isMetallic: false)
        }
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
        statusMessage = "Summoning the doll…"

        Task { @MainActor in
            let doll = await loadDoll()
            anchorEntity.addChild(doll)
            statusMessage = "The doll has appeared. Tap it."
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
                        self.statusMessage = "Worlds merged. Summoning the doll…"
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
