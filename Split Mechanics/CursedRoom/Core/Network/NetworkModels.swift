import Foundation
import simd

/// The current state of the network layer.
enum NetworkState: String, Codable, Sendable, CaseIterable, Identifiable {
    case disconnected
    case hosting
    case browsing
    case connected

    var id: String { rawValue }
}

/// Which side of the connection this device is playing.
/// The Host scans the room (LiDAR); the Guest waits until the scan is done.
enum NetworkRole: String, Codable, Sendable {
    case none
    case host
    case guest
}

/// Asymmetrical gameplay role assigned after the doll is touched (Phase 6).
enum PlayerRole: String, Codable, Sendable, Equatable {
    case seer
    case listener
    case unassigned
}

/// A single event exchanged between Host and Guest over the network connection.
struct NetworkEvent: Codable, Sendable {
    enum EventType: String, Codable, Sendable {
        case hello
        case testMessage
        case ping
        case pong
        case beginSeance = "begin_seance"
        case dollTouched = "doll_touched"
        case roleAssignment = "role_assignment"
        case letterSpawn = "letter_spawn"
    }

    let eventType: String
    let payload: String?

    static func hello(_ message: String = "Hello Network") -> NetworkEvent {
        NetworkEvent(eventType: EventType.hello.rawValue, payload: message)
    }

    static func testMessage(_ message: String) -> NetworkEvent {
        NetworkEvent(eventType: EventType.testMessage.rawValue, payload: message)
    }

    /// Host → Guest: room scan finished, move both devices into the seance (Phase 4).
    static func beginSeance() -> NetworkEvent {
        NetworkEvent(eventType: EventType.beginSeance.rawValue, payload: nil)
    }

    /// Either player → the other: the doll was touched, move both to Phase 5.
    static func dollTouched() -> NetworkEvent {
        NetworkEvent(eventType: EventType.dollTouched.rawValue, payload: nil)
    }

    /// Host → Guest: declares who is the Seer. Payload is `"host_is_seer"` or
    /// `"host_is_listener"` so the Guest can take the opposite role.
    static func roleAssignment(hostIsSeer: Bool) -> NetworkEvent {
        let payload = hostIsSeer ? "host_is_seer" : "host_is_listener"
        return NetworkEvent(eventType: EventType.roleAssignment.rawValue, payload: payload)
    }

    /// Host → Guest: exact world transform for the shared letter (Phase 6B).
    static func letterSpawn(transform: simd_float4x4) -> NetworkEvent {
        let payload = LetterSpawnPayload.encode(transform)
        return NetworkEvent(eventType: EventType.letterSpawn.rawValue, payload: payload)
    }

    /// A latency probe. Payload encodes `"<sequence>|<sendTimeInterval>"` so the
    /// original sender can compute round-trip time when the echo returns.
    static func ping(sequence: Int, sentAt: TimeInterval) -> NetworkEvent {
        NetworkEvent(eventType: EventType.ping.rawValue, payload: "\(sequence)|\(sentAt)")
    }

    /// An echo of a received ping — carries the *same* payload straight back.
    static func pong(echoing payload: String) -> NetworkEvent {
        NetworkEvent(eventType: EventType.pong.rawValue, payload: payload)
    }
}

/// Round-trip latency statistics for the debug/testing tools.
struct LatencyStats: Equatable, Sendable {
    var last: Double?
    var average: Double?
    var min: Double?
    var max: Double?
    var count: Int
    var isLooping: Bool

    static let empty = LatencyStats(
        last: nil, average: nil, min: nil, max: nil, count: 0, isLooping: false
    )
}

/// Encodes a 4×4 letter spawn matrix for the Host → Guest network sync.
enum LetterSpawnPayload {
    static func encode(_ matrix: simd_float4x4) -> String {
        let c = matrix.columns
        let values: [Float] = [
            c.0.x, c.0.y, c.0.z, c.0.w,
            c.1.x, c.1.y, c.1.z, c.1.w,
            c.2.x, c.2.y, c.2.z, c.2.w,
            c.3.x, c.3.y, c.3.z, c.3.w
        ]
        return values.map { String($0) }.joined(separator: ",")
    }

    static func decode(_ payload: String?) -> simd_float4x4? {
        guard let payload else { return nil }
        let parts = payload.split(separator: ",").compactMap { Float($0) }
        guard parts.count == 16 else { return nil }

        var matrix = matrix_identity_float4x4
        matrix.columns.0 = simd_float4(parts[0], parts[1], parts[2], parts[3])
        matrix.columns.1 = simd_float4(parts[4], parts[5], parts[6], parts[7])
        matrix.columns.2 = simd_float4(parts[8], parts[9], parts[10], parts[11])
        matrix.columns.3 = simd_float4(parts[12], parts[13], parts[14], parts[15])
        return matrix
    }
}
