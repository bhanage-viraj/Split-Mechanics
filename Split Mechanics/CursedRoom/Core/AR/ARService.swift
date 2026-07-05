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
    private var pendingLetterAnchor: ARAnchor?
    private var pendingLetterTransform: simd_float4x4?

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

    private static let letterSpatialGainSeer: Audio.Decibel = -60
    private static let letterSpatialGainListener: Audio.Decibel = 20
    private static let letterSpatialRolloffListener: Float = 15.0
    private static let letterSpatialReferenceDistance: Float = 3.0

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
            // Seer sees the letter but cannot hear it (audio muted at -60 dB)
            let visual = makeLetterVisual()
            anchorEntity.addChild(visual)

            // Letter is clickable for the seer
            configureLetterTap(on: visual)

            // Seer gets a silent audio emitter (kept for consistency, -60 dB is inaudible)
            let audioEmitter = Entity()
            audioEmitter.name = Self.letterEntityName + "_audio"
            anchorEntity.addChild(audioEmitter)
            startLetterSpatialAudio(on: audioEmitter, for: role)

        case .listener:
            // Listener only hears — no visual, no tap
            let audioEmitter = Entity()
            audioEmitter.name = Self.letterEntityName
            anchorEntity.addChild(audioEmitter)
            startLetterSpatialAudio(on: audioEmitter, for: role)

        case .unassigned:
            break
        }
    }

    private func makeLetterVisual() -> ModelEntity {
        let mesh = MeshResource.generatePlane(width: 0.2, depth: 0.2)
        let material = SimpleMaterial(color: .white, isMetallic: false)
        let letter = ModelEntity(mesh: mesh, materials: [material])
        letter.name = Self.letterEntityName
        letter.generateCollisionShapes(recursive: true)
        letter.components.set(InputTargetComponent())
        return letter
    }

    private func configureLetterTap(on visual: ModelEntity) {
        let tap = CoherentTapGestureRecognizer(target: self, action: #selector(handleLetterTap(_:)))
        visual.addGestureRecognizer(tap)
    }

    @objc private func handleLetterTap(_ sender: UITapGestureRecognizer) {
        print("📜 [AR] Letter tapped by Seer")
        letterTapped.send(())
    }

    /// Listener-only: boosted gain + wider rolloff so the sound is audible across
    /// the entire room, not just when standing 20 cm away. Seer gets -60 dB (muted).
    ///
    /// Design rationale:
    ///   • Listener gain: +20 dB — audible throughout a typical room.
    ///   • Rolloff 15.0 — gentle attenuation; the source stays loud from 0.5–5 m.
    ///   • Seer gain: -60 dB — effectively silent; Seer must rely on the Listener.
    private func configureLetterSpatialAudio(on entity: Entity, for role: PlayerRole) {
        switch role {
        case .seer:
            let spatial = SpatialAudioComponent(
                gain: Self.letterSpatialGainSeer,
                directivity: .beam(focus: 0),
                distanceAttenuation: .rolloff(factor: Self.letterSpatialRolloffListener)
            )
            entity.components.set(spatial)
            print("📜 [AR] Seer letter audio — muted (-60 dB)")
        case .listener:
            let spatial = SpatialAudioComponent(
                gain: Self.letterSpatialGainListener,
                directivity: .beam(focus: 0),
                distanceAttenuation: .rolloff(factor: Self.letterSpatialRolloffListener)
            )
            entity.components.set(spatial)
            print("📜 [AR] Listener letter audio — gain +20 dB, rolloff 15.0, omnidirectional")
        case .unassigned:
            break
        }
    }

    private func startLetterSpatialAudio(on entity: Entity, for role: PlayerRole) {
        configureLetterSpatialAudio(on: entity, for: role)

        Task { @MainActor in
            guard let resource = await loadLetterAudioResource() else {
                print("📜 [AR] Letter audio missing — check BGM.mp3 is in Copy Bundle Resources")
                return
            }
            entity.playAudio(resource)
            print("📜 [AR] Letter spatial audio playing for \(role.rawValue)")
        }
    }

    private func loadLetterAudioResource() async -> AudioFileResource? {
        let bundle = Bundle.main
        let candidateURLs = [
            bundle.url(forResource: Self.letterAudioName, withExtension: Self.letterAudioExtension, subdirectory: Self.letterAudioSubdirectory),
            bundle.url(forResource: Self.letterAudioName, withExtension: Self.letterAudioExtension),
            bundle.url(forResource: "\(Self.letterAudioName).\(Self.letterAudioExtension)", withExtension: nil)
        ].compactMap { $0 }

        guard let url = candidateURLs.first else {
            print("📜 [AR] \(Self.letterAudioName).\(Self.letterAudioExtension) not found in bundle")
            return nil
        }

        var config = AudioFileResource.Configuration()
        config.shouldLoop = true

        do {
            return try await AudioFileResource(contentsOf: url, configuration: config)
        } catch {
            print("📜 [AR] Async audio load failed: \(error.localizedDescription)")
            do {
                return try AudioFileResource.load(
                    contentsOf: url,
                    withName: Self.letterAudioName,
                    configuration: config
                )
            } catch {
                print("📜 [AR] Sync audio load failed: \(error.localizedDescription)")
                return nil
            }
        }
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
