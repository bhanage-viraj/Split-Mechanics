import Combine
import Foundation
import Network
import UIKit

/// Central networking manager for the game.
///
/// Uses Apple's modern `Network` framework with Bonjour for service discovery.
/// - One device acts as **Host** (runs an `NWListener`).
/// - The other acts as **Guest** (runs an `NWBrowser` to find the Host).
/// - After discovery, a bidirectional `NWConnection` is established.
///
/// ## Info.plist requirements
/// Before running on device, add these keys to **Info.plist**:
///
/// | Key                              | Value |
/// |----------------------------------|-------|
/// | `NSLocalNetworkUsageDescription` | `"This app needs local network access to connect two devices for a co-op AR experience."` |
/// | `NSBonjourServices` (array)      | `"_arcurse._tcp"` |
@MainActor
final class NetworkService: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var state: NetworkState = .disconnected
    @Published private(set) var role: NetworkRole = .none
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var discoveredPeers: [NWBrowser.Result] = []
    @Published private(set) var receivedMessages: [NetworkEvent] = []
    @Published private(set) var latency: LatencyStats = .empty

    /// Set to `true` when the *other* device drops the connection (not a local
    /// button press). The UI observes this to show a "peer disconnected" prompt.
    @Published var peerDisconnected: Bool = false

    // MARK: - Private Properties

    private let serviceType = "_arcurse._tcp"
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var isReceiving = false
    private var pendingSends: [Data] = []
    private var isSending = false
    private var isConnecting = false

    // Latency testing
    private var latencySamples: [Double] = []
    private var pingSequence = 0
    private var pingTimer: Timer?

    // MARK: - Diagnostics

    /// Temporary verbose logging so we can see exactly what the network layer
    /// does. Watch the Xcode console for the "🌐 [Net]" prefix.
    private func log(_ message: String) {
        print("🌐 [Net] \(message)")
    }

    // MARK: - Hosting

    func startHosting() {
        log("startHosting() called — current state: \(state.rawValue)")
        guard state == .disconnected else {
            log("startHosting() ignored — not in .disconnected state")
            return
        }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            let listener = try NWListener(using: parameters, on: 0)
            listener.service = NWListener.Service(name: UIDevice.current.name, type: serviceType)
            log("Listener created, advertising '\(UIDevice.current.name)' as \(serviceType)")

            setupListenerCallbacks(listener)
            listener.start(queue: DispatchQueue.main)

            self.listener = listener
            self.role = .host
            self.state = .hosting
            self.statusMessage = "Hosting… Waiting for a guest."
        } catch {
            self.statusMessage = "Failed to host: \(error.localizedDescription)"
            self.state = .disconnected
        }
    }

    // MARK: - Browsing (Guest)

    func startBrowsing() {
        guard state == .disconnected else { return }

        let parameters = NWParameters.tcp
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: serviceType, domain: "local."),
            using: parameters
        )

        setupBrowserCallbacks(browser)
        browser.start(queue: DispatchQueue.main)

        self.browser = browser
        self.state = .browsing
        self.statusMessage = "Browsing for hosts…"
    }

    func connect(to result: NWBrowser.Result) {
        log("connect(to:) called — current state: \(state.rawValue), endpoint: \(result.endpoint)")
        guard case let .service(name, type, domain, _) = result.endpoint else {
            self.statusMessage = "Selected peer is not a service endpoint."
            log("connect() aborted — endpoint is not a Bonjour service")
            return
        }

        browser?.cancel()
        browser = nil
        isConnecting = true
        self.role = .guest

        self.statusMessage = "Connecting to \(name)…"
        log("Opening connection to service name='\(name)' type='\(type)' domain='\(domain)'")

        let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
        let parameters = NWParameters.tcp
        let connection = NWConnection(to: endpoint, using: parameters)

        setupConnectionCallbacks(connection)
        connection.start(queue: DispatchQueue.main)

        self.connection = connection
    }

    // MARK: - Disconnect

    /// Local, user-initiated disconnect (e.g. the Disconnect button).
    func disconnect() {
        peerDisconnected = false
        teardown(status: "Disconnected.")
    }

    /// Called when the connection drops or fails.
    /// Distinguishes an established peer leaving from a failed connect attempt.
    private func connectionDidDrop(reason: String = "") {
        if state == .connected {
            // We had a live connection and it dropped — the peer left.
            log("connectionDidDrop while CONNECTED (\(reason)) → peer disconnected")
            peerDisconnected = true
            teardown(status: "The other player disconnected.")
        } else if isConnecting {
            // The connection failed while we were still establishing it.
            log("connectionDidDrop while CONNECTING (\(reason)) → connect failed")
            teardown(status: "Could not connect to host.")
        } else {
            log("connectionDidDrop ignored (state: \(state.rawValue), reason: \(reason))")
        }
    }

    /// Shared cleanup used by every disconnect path.
    private func teardown(status: String) {
        stopPingLoop()

        listener?.cancel()
        listener = nil

        browser?.cancel()
        browser = nil

        connection?.cancel()
        connection = nil

        receiveBuffer.removeAll()
        isReceiving = false
        pendingSends.removeAll()
        isSending = false
        isConnecting = false
        latencySamples.removeAll()
        latency = .empty
        role = .none
        state = .disconnected
        statusMessage = status
        discoveredPeers.removeAll()
    }

    /// Called by the UI after it has shown the "peer disconnected" prompt.
    func acknowledgePeerDisconnect() {
        peerDisconnected = false
    }

    // MARK: - Send / Receive

    func send(_ event: NetworkEvent) {
        enqueue(event)
        if state == .connected {
            statusMessage = "Sent: \(event.eventType)"
        }
    }

    /// Frames and queues an event for sending (one send in flight at a time).
    private func enqueue(_ event: NetworkEvent) {
        guard let connection, connection.state == .ready else {
            self.statusMessage = "Cannot send — not connected."
            return
        }

        do {
            let payload = try JSONEncoder().encode(event)
            var length = UInt32(payload.count).bigEndian
            var framed = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
            framed.append(payload)
            pendingSends.append(framed)
            flushSendQueue(on: connection)
        } catch {
            self.statusMessage = "Send failed: \(error.localizedDescription)"
        }
    }

    private func flushSendQueue(on connection: NWConnection) {
        guard !isSending, let next = pendingSends.first else { return }

        isSending = true
        connection.send(content: next, completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isSending = false

                if let error {
                    self.pendingSends.removeAll()
                    self.statusMessage = "Send failed: \(error.localizedDescription)"
                    return
                }

                if !self.pendingSends.isEmpty {
                    self.pendingSends.removeFirst()
                }

                self.flushSendQueue(on: connection)
            }
        })
    }

    // MARK: - Latency Testing

    /// Sends a single ping. The peer echoes it back and we measure round-trip time.
    func sendPing() {
        guard state == .connected, connection?.state == .ready else {
            statusMessage = "Cannot ping — not connected."
            return
        }
        pingSequence += 1
        enqueue(.ping(sequence: pingSequence, sentAt: Date().timeIntervalSince1970))
    }

    /// Repeatedly pings at a fixed interval to gather average/min/max latency.
    func startPingLoop(intervalMilliseconds: Double = 500) {
        guard state == .connected else {
            statusMessage = "Cannot ping — not connected."
            return
        }
        stopPingLoop()
        resetLatencyStats()
        latency.isLooping = true

        sendPing()
        let timer = Timer.scheduledTimer(withTimeInterval: intervalMilliseconds / 1000.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendPing() }
        }
        pingTimer = timer
    }

    func stopPingLoop() {
        pingTimer?.invalidate()
        pingTimer = nil
        latency.isLooping = false
    }

    func resetLatencyStats() {
        latencySamples.removeAll()
        latency = LatencyStats(
            last: nil, average: nil, min: nil, max: nil, count: 0, isLooping: latency.isLooping
        )
    }

    private func handlePong(_ event: NetworkEvent) {
        guard let payload = event.payload else { return }
        let parts = payload.split(separator: "|")
        guard parts.count == 2, let sentAt = Double(parts[1]) else { return }

        let rttMs = (Date().timeIntervalSince1970 - sentAt) * 1000.0
        recordLatency(rttMs)
    }

    private func recordLatency(_ milliseconds: Double) {
        latencySamples.append(milliseconds)
        if latencySamples.count > 100 { latencySamples.removeFirst() }

        latency.last = milliseconds
        latency.count = latencySamples.count
        latency.min = latencySamples.min()
        latency.max = latencySamples.max()
        latency.average = latencySamples.reduce(0, +) / Double(latencySamples.count)

        statusMessage = String(format: "RTT: %.1f ms", milliseconds)
    }

    // MARK: - Private Setup

    private func setupListenerCallbacks(_ listener: NWListener) {
        listener.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                guard let self else { return }
                self.log("listener state → \(newState)")
                switch newState {
                case .ready:
                    self.statusMessage = "Host is ready. Waiting for a guest…"
                case .waiting(let error):
                    self.log("listener WAITING: \(error) — \(self.diagnose(error))")
                    self.statusMessage = "Host waiting: \(error.localizedDescription)"
                case .failed(let error):
                    self.log("listener FAILED: \(error) — \(self.diagnose(error))")
                    self.statusMessage = "Listener failed: \(error.localizedDescription)"
                    self.state = .disconnected
                case .cancelled:
                    self.statusMessage = "Hosting cancelled."
                    self.state = .disconnected
                default:
                    break
                }
            }
        }

        listener.newConnectionHandler = { [weak self] newConnection in
            Task { @MainActor in
                guard let self else { return }
                self.log("newConnectionHandler — incoming connection from \(newConnection.endpoint)")

                // Only accept the first guest. Reject extras so a second
                // incoming connection can't clobber the live one.
                guard self.connection == nil else {
                    self.log("Rejecting extra incoming connection — already have one")
                    newConnection.cancel()
                    return
                }

                self.connection = newConnection
                self.setupConnectionCallbacks(newConnection)
                newConnection.start(queue: DispatchQueue.main)
                self.state = .connected
                self.statusMessage = "Guest connected!"

                self.listener?.cancel()
                self.listener = nil
            }
        }
    }

    private func setupBrowserCallbacks(_ browser: NWBrowser) {
        browser.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                guard let self else { return }
                switch newState {
                case .ready:
                    self.statusMessage = "Looking for hosts…"
                case .failed(let error):
                    self.statusMessage = "Browse failed: \(error.localizedDescription)"
                    self.state = .disconnected
                case .cancelled:
                    if !self.isConnecting && self.connection == nil {
                        self.statusMessage = "Browsing cancelled."
                        self.state = .disconnected
                    }
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self else { return }
                self.discoveredPeers = Array(results)
                if results.isEmpty {
                    self.statusMessage = "No hosts found."
                } else {
                    self.statusMessage = "Found \(results.count) host(s). Tap to connect."
                }
            }
        }
    }

    private func setupConnectionCallbacks(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                guard let self else { return }
                self.log("connection state → \(newState)")
                switch newState {
                case .ready:
                    self.isConnecting = false
                    self.state = .connected
                    self.statusMessage = "Connected!"
                    self.beginReceiving(on: connection)
                case .waiting(let error):
                    // The connection can't proceed yet (often Local Network
                    // permission, no route, or the host went away). It may retry
                    // on its own, so we surface it but don't tear down.
                    self.log("connection WAITING: \(error) — \(self.diagnose(error))")
                    self.statusMessage = "Waiting: \(error.localizedDescription)"
                case .failed(let error):
                    self.log("connection FAILED: \(error) — \(self.diagnose(error))")
                    self.statusMessage = "Connection failed: \(error.localizedDescription)"
                    self.connectionDidDrop(reason: "failed: \(error)")
                case .cancelled:
                    self.connectionDidDrop(reason: "cancelled")
                default:
                    break
                }
            }
        }
    }

    /// Turns common `NWError`s into a plain-English hint.
    private func diagnose(_ error: NWError) -> String {
        switch error {
        case .posix(let code):
            switch code {
            case .ECONNREFUSED: return "Host refused the connection (listener gone?)."
            case .ETIMEDOUT:    return "Timed out — devices may be on different networks."
            case .ENETDOWN, .ENETUNREACH:
                return "Network unreachable — check Wi-Fi / Local Network permission."
            case .EHOSTUNREACH: return "Host unreachable — check same Wi-Fi network."
            default:            return "POSIX error \(code.rawValue)."
            }
        case .dns:
            return "DNS/Bonjour resolution failed — the host stopped advertising."
        default:
            return "Check Settings ▸ Privacy ▸ Local Network for this app."
        }
    }

    private func beginReceiving(on connection: NWConnection) {
        guard !isReceiving else { return }
        isReceiving = true
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }

                if let data, !data.isEmpty {
                    self.processReceived(data)
                }

                if isComplete || error != nil {
                    self.isReceiving = false
                    self.connectionDidDrop()
                    return
                }

                self.receive(on: connection)
            }
        }
    }

    private func processReceived(_ data: Data) {
        receiveBuffer.append(data)

        let headerSize = MemoryLayout<UInt32>.size

        while receiveBuffer.count >= headerSize {
            // Read the 4-byte big-endian length WITHOUT `load(as:)`, which requires
            // 4-byte alignment and crashes on unaligned reads after the buffer has
            // been sliced. Copying to a UInt8 array is alignment-safe.
            let header = [UInt8](receiveBuffer.prefix(headerSize))
            let length =
                (UInt32(header[0]) << 24) |
                (UInt32(header[1]) << 16) |
                (UInt32(header[2]) << 8) |
                 UInt32(header[3])
            let frameSize = headerSize + Int(length)

            guard length > 0, length <= 1_000_000, receiveBuffer.count >= frameSize else { break }

            // Extract the JSON body and rebuild the remaining buffer as a fresh
            // `Data` (startIndex 0) so subsequent iterations use valid indices.
            let frame = [UInt8](receiveBuffer.prefix(frameSize))
            let jsonData = Data(frame[headerSize..<frameSize])
            receiveBuffer = Data(receiveBuffer.dropFirst(frameSize))

            guard let event = try? JSONDecoder().decode(NetworkEvent.self, from: jsonData) else {
                log("Dropped unreadable frame (\(length) bytes)")
                statusMessage = "Received unreadable data."
                continue
            }

            switch event.eventType {
            case NetworkEvent.EventType.ping.rawValue:
                // Echo it straight back so the sender can measure round-trip time.
                if let payload = event.payload {
                    enqueue(.pong(echoing: payload))
                }
            case NetworkEvent.EventType.pong.rawValue:
                handlePong(event)
            default:
                receivedMessages.append(event)
                statusMessage = "Received: \(event.eventType)"
            }
        }
    }
}
