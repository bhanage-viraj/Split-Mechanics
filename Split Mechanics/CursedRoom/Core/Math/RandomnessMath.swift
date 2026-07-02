//
//  RandomnessMath.swift
//  The Cursed Room
//
//  Randomised sampling helpers (e.g. finding a clear floor spot for the doll).
//

import simd

enum RandomnessMath {

    /// A uniformly-random point inside a disk of `radius` around `center`
    /// (on the floor plane — `y` is preserved from `center`).
    static func randomPointInDisk(center: simd_float3, radius: Float) -> simd_float3 {
        let angle = Float.random(in: 0..<(2 * .pi))
        // sqrt keeps the distribution uniform over the disk area.
        let r = radius * Float.random(in: 0...1).squareRoot()
        return simd_float3(center.x + r * cos(angle), center.y, center.z + r * sin(angle))
    }

    /// Rejection-samples for a floor point that clears all obstacles. Returns the
    /// preferred point if no clear candidate is found within `attempts`.
    static func clearFloorPoint(
        preferred: simd_float3,
        searchRadius: Float,
        obstacles: [SpatialMath.FloorObstacle],
        clearance: Float,
        attempts: Int = 40
    ) -> simd_float3 {
        if SpatialMath.isClear(preferred, of: obstacles, clearance: clearance) {
            return preferred
        }
        for _ in 0..<attempts {
            let candidate = randomPointInDisk(center: preferred, radius: searchRadius)
            if SpatialMath.isClear(candidate, of: obstacles, clearance: clearance) {
                return candidate
            }
        }
        return preferred
    }
}
