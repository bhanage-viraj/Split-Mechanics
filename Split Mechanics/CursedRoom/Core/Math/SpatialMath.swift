//
//  SpatialMath.swift
//  The Cursed Room
//
//  Small geometry helpers for placing AR content in world space.
//

import ARKit
import simd

enum SpatialMath {

    /// Eye/chest height above the floor for wall-mounted clues.
    static let letterHeightAboveFloor: Float = 1.4

    /// Builds a translation-only 4x4 transform at the given world position.
    static func translation(_ position: simd_float3) -> simd_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = simd_float4(position.x, position.y, position.z, 1)
        return matrix
    }

    /// Horizontal (floor-plane) distance between two points, ignoring height.
    static func distanceXZ(_ a: simd_float3, _ b: simd_float3) -> Float {
        let dx = a.x - b.x
        let dz = a.z - b.z
        return (dx * dx + dz * dz).squareRoot()
    }

    /// Full 3D Euclidean distance (Phase 6C / haptic proximity).
    static func euclideanDistance(_ a: simd_float3, _ b: simd_float3) -> Float {
        simd_distance(a, b)
    }

    /// Maps letter distance to haptic intensity: 1.0 at ≤0.2 m, 0.0 at ≥3.0 m.
    static func letterProximityIntensity(distance: Float, near: Float = 0.2, far: Float = 3.0) -> Float {
        guard distance > near else { return 1.0 }
        guard distance < far else { return 0.0 }
        return 1.0 - (distance - near) / (far - near)
    }

    /// World-space centre of an `ARPlaneAnchor`.
    static func worldCenter(of plane: ARPlaneAnchor) -> simd_float3 {
        let local = simd_float4(plane.center.x, plane.center.y, plane.center.z, 1)
        let world = plane.transform * local
        return simd_float3(world.x, world.y, world.z)
    }

    /// Outward-facing normal of a vertical wall plane.
    static func wallNormal(of plane: ARPlaneAnchor) -> simd_float3 {
        let n = plane.transform.columns.2
        return simd_normalize(simd_float3(n.x, n.y, n.z))
    }

    /// Horizontal tangent along the wall surface (for Gaussian lateral offset).
    static func wallRight(of plane: ARPlaneAnchor) -> simd_float3 {
        let r = plane.transform.columns.0
        return simd_normalize(simd_float3(r.x, r.y, r.z))
    }

    /// Lowest tracked floor Y, or the camera height minus a fallback if no floor yet.
    static func floorY(from floors: [ARPlaneAnchor], fallback: Float) -> Float {
        floors.map { worldCenter(of: $0).y }.min() ?? fallback
    }

    /// Builds a world transform for a letter flush on a wall at eye level.
    static func letterTransform(
        on wall: ARPlaneAnchor,
        floorY: Float,
        lateralOffset: Float
    ) -> simd_float4x4 {
        let center = worldCenter(of: wall)
        let right = wallRight(of: wall)
        let normal = wallNormal(of: wall)

        var position = center + right * lateralOffset
        position.y = floorY + letterHeightAboveFloor
        // Nudge slightly off the drywall so the plane doesn't z-fight.
        position -= normal * 0.015

        return orientedTransform(position: position, forward: -normal)
    }

    /// Builds a letter transform from a raycast hit on any vertical surface.
    static func letterTransform(
        raycastTransform: simd_float4x4,
        floorY: Float,
        lateralOffset: Float = 0
    ) -> simd_float4x4 {
        let right = simd_normalize(simd_float3(
            raycastTransform.columns.0.x,
            raycastTransform.columns.0.y,
            raycastTransform.columns.0.z
        ))
        let normal = simd_normalize(simd_float3(
            raycastTransform.columns.2.x,
            raycastTransform.columns.2.y,
            raycastTransform.columns.2.z
        ))
        let hit = raycastTransform.columns.3
        var position = simd_float3(hit.x, hit.y, hit.z) + right * lateralOffset
        position.y = floorY + letterHeightAboveFloor
        position -= normal * 0.02
        return orientedTransform(position: position, forward: -normal)
    }

    /// Places a letter ~2.5 m in front of the camera when no wall planes exist yet.
    static func letterTransformInFrontOfCamera(frame: ARFrame, floorY: Float) -> simd_float4x4 {
        let camera = frame.camera.transform
        let camPos = cameraPosition(from: frame)
        let forward = -simd_normalize(simd_float3(
            camera.columns.2.x,
            camera.columns.2.y,
            camera.columns.2.z
        ))
        var position = camPos + forward * 1.5
        position.y = floorY + letterHeightAboveFloor
        return orientedTransform(position: position, forward: forward)
    }

    /// Builds a rotation matrix with `forward` as local +Z.
    static func orientedTransform(position: simd_float3, forward: simd_float3) -> simd_float4x4 {
        let worldUp = simd_float3(0, 1, 0)
        let right = simd_normalize(simd_cross(worldUp, forward))
        let up = simd_cross(forward, right)

        var matrix = matrix_identity_float4x4
        matrix.columns.0 = simd_float4(right.x, right.y, right.z, 0)
        matrix.columns.1 = simd_float4(up.x, up.y, up.z, 0)
        matrix.columns.2 = simd_float4(forward.x, forward.y, forward.z, 0)
        matrix.columns.3 = simd_float4(position.x, position.y, position.z, 1)
        return matrix
    }

    /// Camera position from an AR frame.
    static func cameraPosition(from frame: ARFrame) -> simd_float3 {
        let t = frame.camera.transform.columns.3
        return simd_float3(t.x, t.y, t.z)
    }

    /// A floor obstacle approximated as a disk: its centre projected onto the
    /// floor plus a `radius` covering its footprint.
    struct FloorObstacle {
        let center: simd_float3
        let radius: Float
    }

    /// True when `point` keeps at least `clearance` metres from every obstacle's
    /// footprint (measured on the floor plane).
    static func isClear(_ point: simd_float3, of obstacles: [FloorObstacle], clearance: Float) -> Bool {
        for obstacle in obstacles
        where distanceXZ(point, obstacle.center) < (clearance + obstacle.radius) {
            return false
        }
        return true
    }

    /// Projects a world point onto the floor plane.
    static func projectToFloor(_ point: simd_float3, floorY: Float) -> simd_float3 {
        simd_float3(point.x, floorY, point.z)
    }

    /// Evenly samples a quadratic Bézier curve — the imaginary arc for footprint trails.
    static func quadraticBezierPath(
        from start: simd_float3,
        control: simd_float3,
        to end: simd_float3,
        stepCount: Int
    ) -> [simd_float3] {
        guard stepCount > 1 else { return [start, end] }

        return (0..<stepCount).map { index in
            let t = Float(index) / Float(stepCount - 1)
            let inverse = 1 - t
            let x = inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x
            let y = inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
            let z = inverse * inverse * start.z + 2 * inverse * t * control.z + t * t * end.z
            return simd_float3(x, y, z)
        }
    }

    /// Samples a smooth Catmull-Rom spline through `waypoints` on the floor plane.
    static func catmullRomPath(waypoints: [simd_float3], samplesPerSegment: Int) -> [simd_float3] {
        guard waypoints.count >= 2 else { return waypoints }
        guard samplesPerSegment > 0 else { return waypoints }

        var control = waypoints
        control.insert(waypoints[0], at: 0)
        control.append(waypoints[waypoints.count - 1])

        var path: [simd_float3] = []
        for index in 0..<(control.count - 3) {
            let p0 = control[index]
            let p1 = control[index + 1]
            let p2 = control[index + 2]
            let p3 = control[index + 3]
            let segmentSamples = index == control.count - 4 ? samplesPerSegment + 1 : samplesPerSegment
            for sample in 0..<segmentSamples {
                let t = Float(sample) / Float(samplesPerSegment)
                path.append(catmullRomSample(p0: p0, p1: p1, p2: p2, p3: p3, t: t))
            }
        }
        return path
    }

    private static func catmullRomSample(
        p0: simd_float3,
        p1: simd_float3,
        p2: simd_float3,
        p3: simd_float3,
        t: Float
    ) -> simd_float3 {
        simd_float3(
            catmullRomScalar(p0: p0.x, p1: p1.x, p2: p2.x, p3: p3.x, t: t),
            catmullRomScalar(p0: p0.y, p1: p1.y, p2: p2.y, p3: p3.y, t: t),
            catmullRomScalar(p0: p0.z, p1: p1.z, p2: p2.z, p3: p3.z, t: t)
        )
    }

    private static func catmullRomScalar(
        p0: Float,
        p1: Float,
        p2: Float,
        p3: Float,
        t: Float
    ) -> Float {
        let t2 = t * t
        let t3 = t2 * t

        let a = 2 * p1
        let b = (-p0 + p2) * t
        let c = (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
        let d = (-p0 + 3 * p1 - 3 * p2 + p3) * t3

        return 0.5 * (a + b + c + d)
    }
}
