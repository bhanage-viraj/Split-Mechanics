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

    // MARK: - AR View

    let arView: ARView

    // MARK: - Private

    private var isHost = false
    private var wantsDoll = false          // Host requested a spawn (post-merge)
    private var dollAnchorAdded = false    // Host has added the ARAnchor once
    private var hasStarted = false

    private var floorPlanes: [UUID: ARPlaneAnchor] = [:]
    private var obstaclePlanes: [UUID: ARPlaneAnchor] = [:]

    private static let dollAnchorName = "cursed_doll_anchor"
    private static let dollEntityName = "cursed_doll_entity"

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
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        config.environmentTexturing = .automatic
        config.isCollaborationEnabled = true

        UIApplication.shared.isIdleTimerDisabled = true
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

    // MARK: - Doll Rendering (both devices)

    private func spawnDollEntity(on anchor: ARAnchor) {
        guard !isDollSpawned else { return }

        let anchorEntity = AnchorEntity(anchor: anchor)
        anchorEntity.addChild(makeDoll())
        arView.scene.addAnchor(anchorEntity)

        isDollSpawned = true
        statusMessage = "The doll has appeared. Tap it."
        print("🕯️ [AR] Doll entity rendered")
    }

    /// Purple placeholder doll (body + head). Tappable via collision + input target.
    private func makeDoll() -> ModelEntity {
        let bodyHeight: Float = 0.45
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
            obstaclePlanes.removeValue(forKey: plane.identifier)
        case .wall, .ceiling, .table, .seat, .window, .door:
            // Walls and furniture the doll should avoid.
            obstaclePlanes[plane.identifier] = plane
        default:
            // Unclassified (`.none`) — fall back to alignment: horizontal is a
            // candidate floor, vertical is an obstacle.
            if plane.alignment == .horizontal {
                floorPlanes[plane.identifier] = plane
                obstaclePlanes.removeValue(forKey: plane.identifier)
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
                } else if let plane = anchor as? ARPlaneAnchor {
                    self.track(plane)
                    self.attemptDollSpawn()
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
        }
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        MainActor.assumeIsolated {
            for anchor in anchors {
                self.floorPlanes.removeValue(forKey: anchor.identifier)
                self.obstaclePlanes.removeValue(forKey: anchor.identifier)
            }
        }
    }
}
