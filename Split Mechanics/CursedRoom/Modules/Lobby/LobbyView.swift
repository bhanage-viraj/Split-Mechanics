import Network
import SwiftUI

struct LobbyView: View {

    @StateObject private var presenter: LobbyPresenter
    @StateObject private var router: LobbyRouter

    init(networkService: NetworkService) {
        let interactor = LobbyInteractor(networkService: networkService)
        let presenter = LobbyPresenter(interactor: interactor)
        _presenter = StateObject(wrappedValue: presenter)
        _router = StateObject(wrappedValue: LobbyRouter())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.04)
                    .ignoresSafeArea()

                if router.shouldNavigateToScanning {
                    connectedPlaceholder
                } else {
                    lobbyContent
                }
            }
            .navigationTitle("Lobby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Disconnect") {
                        presenter.didTapDisconnect()
                    }
                    .foregroundStyle(.red)
                    .disabled(presenter.networkState == .disconnected)
                }
            }
            .onAppear {
                router.observeConnection(from: presenter)
            }
            .alert(
                "Player Disconnected",
                isPresented: $presenter.showPeerDisconnectedAlert
            ) {
                Button("Back to Lobby", role: .cancel) {
                    presenter.didDismissPeerDisconnectedAlert()
                }
            } message: {
                Text("The other player left the game. You've been returned to the lobby.")
            }
        }
    }

    private var lobbyContent: some View {
        VStack(spacing: 24) {
            Text("The Cursed Room")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)

            Text("Local Co-Op Lobby")
                .font(.title3)
                .foregroundStyle(.gray)

            Spacer()

            VStack(spacing: 16) {
                Button(action: presenter.didTapHost) {
                    HStack {
                        Image(systemName: "wifi.router")
                        Text("Host Game")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(presenter.networkState == .hosting ? Color.red : Color.blue)
                    )
                }
                .disabled(presenter.networkState != .disconnected)

                Button(action: presenter.didTapJoin) {
                    HStack {
                        Image(systemName: "person.2.fill")
                        Text("Join Game")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(presenter.networkState == .browsing ? Color.red : Color.green)
                    )
                }
                .disabled(presenter.networkState != .disconnected)
            }
            .padding(.horizontal, 32)

            if presenter.networkState == .browsing {
                peerListSection
            }

            statusSection

            if !presenter.receivedMessages.isEmpty {
                messagesSection
            }

            if presenter.isConnected {
                debugSection
                latencySection
            }

            Spacer()
        }
        .padding()
    }

    private var connectedPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Connected")
                .font(.title.bold())
                .foregroundStyle(.white)

            Text("Lobby dismissed — ready for Phase 3 (Scanning).")
                .font(.subheadline)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)

            if !presenter.receivedMessages.isEmpty {
                messagesSection
            }

            if presenter.isConnected {
                debugSection
                latencySection
            }
        }
        .padding()
    }

    private var peerListSection: some View {
        Group {
            Text("Discovered Hosts")
                .font(.headline)
                .foregroundStyle(.gray)

            if presenter.discoveredPeers.isEmpty {
                Text("Scanning…")
                    .foregroundStyle(.gray)
                    .italic()
            } else {
                List(presenter.discoveredPeers, id: \.self) { peer in
                    Button {
                        presenter.didTapPeer(peer)
                    } label: {
                        HStack {
                            Image(systemName: "wifi.router")
                            if case let .service(name, _, _, _) = peer.endpoint {
                                Text(name)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.gray)
                        }
                        .foregroundStyle(.white)
                    }
                }
                .listStyle(.plain)
                .frame(height: CGFloat(min(presenter.discoveredPeers.count, 5)) * 50)
            }
        }
    }

    private var statusSection: some View {
        Text(presenter.statusMessage)
            .font(.caption)
            .foregroundStyle(presenter.networkState == .connected ? .green : .yellow)
            .multilineTextAlignment(.center)
    }

    private var messagesSection: some View {
        Group {
            Text("Received Messages")
                .font(.headline)
                .foregroundStyle(.gray)

            ForEach(Array(presenter.receivedMessages.enumerated()), id: \.offset) { _, event in
                HStack {
                    Text("◉ \(event.eventType)")
                        .foregroundStyle(.green)
                    if let payload = event.payload {
                        Text("— \(payload)")
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .font(.subheadline)
            }
        }
    }

    private var debugSection: some View {
        Group {
            Divider()
                .background(Color.gray)

            Text("DEBUG")
                .font(.caption.bold())
                .foregroundStyle(.orange)

            Button("Send \"Hello Network\"") {
                presenter.didTapSendTest()
            }
            .disabled(presenter.networkState != .connected)
            .font(.subheadline)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.2))
            .foregroundStyle(.orange)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Latency Test Section

    private var latencySection: some View {
        VStack(spacing: 10) {
            Divider()
                .background(Color.gray)

            Text("LATENCY TEST")
                .font(.caption.bold())
                .foregroundStyle(.cyan)

            Text(presenter.latencySummary)
                .font(.title3.monospacedDigit().bold())
                .foregroundStyle(.white)

            Text(presenter.latencyDetail)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.gray)

            HStack(spacing: 12) {
                Button("Ping Once") {
                    presenter.didTapPingOnce()
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)

                Button(presenter.latency.isLooping ? "Stop Auto" : "Auto Ping") {
                    presenter.didTapToggleAutoPing()
                }
                .buttonStyle(.borderedProminent)
                .tint(presenter.latency.isLooping ? .red : .blue)

                Button("Reset") {
                    presenter.didTapResetLatency()
                }
                .buttonStyle(.bordered)
                .tint(.gray)
            }
            .font(.subheadline)
            .disabled(presenter.networkState != .connected)
        }
    }
}

#Preview {
    LobbyView(networkService: NetworkService())
}
