//
//  SpatialMath.swift
//  The Cursed Room
//
//  Small geometry helpers for placing AR content in world space.
//

import simd

enum SpatialMath {

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
}
