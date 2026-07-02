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

/// A single event exchanged between Host and Guest over the network connection.
struct NetworkEvent: Codable, Sendable {
    enum EventType: String, Codable, Sendable {
        case hello
        case testMessage
        case ping
        case pong
    }

    let eventType: String
    let payload: String?

    static func hello(_ message: String = "Hello Network") -> NetworkEvent {
        NetworkEvent(eventType: EventType.hello.rawValue, payload: message)
    }

    static func testMessage(_ message: String) -> NetworkEvent {
        NetworkEvent(eventType: EventType.testMessage.rawValue, payload: message)
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
