import Foundation

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
