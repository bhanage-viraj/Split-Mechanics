//
//  RandomnessMath.swift
//  The Cursed Room
//
//  Randomised sampling helpers (e.g. finding a clear floor spot for the doll).
//

import ARKit
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

    // MARK: - Gaussian Sampling (Phase 6B — bounded wall selection)

    /// Box–Muller transform: one sample from N(mean, stdDev²).
    static func gaussianSample(mean: Float = 0, stdDev: Float) -> Float {
        let u1 = Float.random(in: Float.ulpOfOne...1)
        let u2 = Float.random(in: 0..<1)
        let z0 = (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        return mean + stdDev * z0
    }

    /// Gaussian sample clamped to ±`limit` — keeps spawns inside the wall bounds.
    static func gaussianClamped(mean: Float = 0, stdDev: Float, limit: Float) -> Float {
        max(-limit, min(limit, gaussianSample(mean: mean, stdDev: stdDev)))
    }

    /// Picks one element using normalised weights (e.g. Gaussian wall weights).
    static func weightedRandomElement<T>(_ elements: [T], weights: [Float]) -> T? {
        guard elements.count == weights.count, !elements.isEmpty else { return nil }
        let total = weights.reduce(0, +)
        guard total > 0 else { return elements.randomElement() }

        var pick = Float.random(in: 0..<total)
        for (index, weight) in weights.enumerated() {
            pick -= weight
            if pick <= 0 { return elements[index] }
        }
        return elements.last
    }

    /// Picks a random vertical wall. Every spawnable wall has equal odds.
    static func pickWall(from walls: [ARPlaneAnchor]) -> ARPlaneAnchor? {
        walls.randomElement()
    }
}
