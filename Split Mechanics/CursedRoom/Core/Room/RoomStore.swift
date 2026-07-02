import Foundation

/// Simple JSON persistence for the most recent `ScannedRoom`.
/// The room coordinates are stored so they can be reused when the game starts.
enum RoomStore {
    private static let filename = "scanned_room.json"

    private static var fileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
    }

    @discardableResult
    static func save(_ room: ScannedRoom) -> Bool {
        do {
            let data = try JSONEncoder().encode(room)
            try data.write(to: fileURL, options: .atomic)
            print("🗺️ [RoomStore] Saved room (\(room.summary)) → \(fileURL.path)")
            return true
        } catch {
            print("🗺️ [RoomStore] Save failed: \(error.localizedDescription)")
            return false
        }
    }

    static func load() -> ScannedRoom? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(ScannedRoom.self, from: data)
    }
}
