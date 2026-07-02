import Foundation
import RoomPlan
import simd

// MARK: - simd helpers

extension simd_float4x4 {
    /// World-space position (translation) stored in the 4th column.
    var position: simd_float3 {
        simd_float3(columns.3.x, columns.3.y, columns.3.z)
    }

    /// Rough Euler-angle decomposition (radians) — matches the RoomPlan demo.
    var eulerAngles: simd_float3 {
        simd_float3(
            x: asin(-self[2][1]),
            y: atan2(self[2][0], self[2][2]),
            z: atan2(self[0][1], self[1][1])
        )
    }
}

// MARK: - Codable vector

/// A `Codable`/`Sendable` 3-component vector so scanned geometry can be stored
/// on disk or sent over the network later.
struct Vector3: Codable, Sendable, Equatable {
    var x: Float
    var y: Float
    var z: Float

    init(_ v: simd_float3) {
        x = v.x
        y = v.y
        z = v.z
    }

    var simd: simd_float3 { simd_float3(x, y, z) }
}

// MARK: - Scanned room model

/// A lightweight, serializable snapshot of a RoomPlan `CapturedRoom`.
/// We keep only the coordinates/dimensions the game needs — no 3D mesh.
struct ScannedRoom: Codable, Sendable, Equatable {

    struct Surface: Codable, Sendable, Equatable {
        var category: String
        var position: Vector3
        var dimensions: Vector3
        var rotation: Vector3
    }

    struct Object: Codable, Sendable, Equatable {
        var category: String
        var position: Vector3
        var dimensions: Vector3
        var rotation: Vector3
    }

    var walls: [Surface]
    var doors: [Surface]
    var windows: [Surface]
    var openings: [Surface]
    var floor: Surface?
    var objects: [Object]
    var createdAt: Date
}

// MARK: - Extraction from RoomPlan

extension ScannedRoom {
    init(from room: CapturedRoom) {
        func surface(_ s: CapturedRoom.Surface, _ category: String) -> Surface {
            Surface(
                category: category,
                position: Vector3(s.transform.position),
                dimensions: Vector3(s.dimensions),
                rotation: Vector3(s.transform.eulerAngles)
            )
        }

        walls = room.walls.map { surface($0, "wall") }
        doors = room.doors.map { surface($0, "door") }
        windows = room.windows.map { surface($0, "window") }
        openings = room.openings.map { surface($0, "opening") }

        if let firstFloor = room.floors.first {
            floor = surface(firstFloor, "floor")
        } else {
            floor = nil
        }

        objects = room.objects.map { object in
            Object(
                category: "\(object.category)",
                position: Vector3(object.transform.position),
                dimensions: Vector3(object.dimensions),
                rotation: Vector3(object.transform.eulerAngles)
            )
        }

        createdAt = Date()
    }

    var summary: String {
        "\(walls.count) walls · \(doors.count) doors · \(windows.count) windows · \(objects.count) objects"
    }
}
