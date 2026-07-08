import Network
import SwiftUI

struct LobbyView: View {

    @StateObject private var presenter: LobbyPresenter
    private let onBackToMenu: () -> Void
    private let onStartInvestigation: () -> Void

    init(
        networkService: NetworkService,
        onBackToMenu: @escaping () -> Void = {},
        onStartInvestigation: @escaping () -> Void = {}
    ) {
        let interactor = LobbyInteractor(networkService: networkService)
        let presenter = LobbyPresenter(interactor: interactor)
        _presenter = StateObject(wrappedValue: presenter)
        self.onBackToMenu = onBackToMenu
        self.onStartInvestigation = onStartInvestigation
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if presenter.networkState == .connected {
                    ConnectedView(
                        playerName: presenter.playerName,
                        peerName: presenter.peerName.isEmpty ? "Friend_1" : presenter.peerName,
                        isHost: presenter.isHost,
                        onContinue: {
                            presenter.didTapContinueConnected()
                            onStartInvestigation()
                        },
                        onExit: { presenter.didTapDisconnect() }
                    )
                } else if presenter.networkState == .hosting {
                    WaitingForPlayerView(
                        playerName: presenter.playerName,
                        onCancel: { presenter.didTapDisconnect() }
                    )
                } else {
                    lobbyContent
                }
            }
        }
        .onAppear {
            presenter.didRequestInvestigationStart = false
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

    private var lobbyContent: some View {
        ZStack {
            VideoPlayerBackground(
                resourceName: "background2",
                fileExtension: "mov",
                overlayOpacity: 0.35
            )

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 10)

                SectionLabel(text: "Lobby")
                    .padding(.top, 46)

                diamondDivider
                    .padding(.top, 14)

                playWithFriendsTitle
                    .padding(.top, 14)

                PlayerBadge(name: presenter.playerName)
                    .padding(.top, 8)

                gothicDivider
                    .padding(.top, 24)

                if presenter.networkState == .browsing {
                    friendSelectList
                        .padding(.top, 12)
                        .padding(.horizontal, 28)
                }

                Spacer()

                bottomButtons
                    .padding(.horizontal, 26)
                    .padding(.bottom, 40)
            }
        }
    }


    private var topBar: some View {
        HStack {
            Button(action: {
                presenter.didTapDisconnect()
                onBackToMenu()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Color.ghostSurface.opacity(0.6))
                    )
            }

            Spacer()
        }
        .padding(.horizontal, 20)
    }


    private var playWithFriendsTitle: some View {
        HStack(spacing: 8) {
            Text("PLAY WITH")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(Color.ghostGold)
                .tracking(2)

            Text("FRIENDS")
                .redAccentStyle(size: 22, italic: true)
                .tracking(2)
        }
    }

    private var gothicDivider: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.ghostRed.opacity(0.55))
                .frame(height: 1)

            Circle()
                .fill(Color.ghostRedBright)
                .frame(width: 8, height: 8)
                .padding(.horizontal, 6)

            Rectangle()
                .fill(Color.ghostRed.opacity(0.55))
                .frame(height: 1)
        }
        .padding(.horizontal, 44)
    }

    private var diamondDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.ghostWhite.opacity(0.18))
                .frame(width: 44, height: 1)

            Rectangle()
                .fill(Color.ghostRedBright)
                .frame(width: 6, height: 6)
                .rotationEffect(.degrees(45))

            Rectangle()
                .fill(Color.ghostWhite.opacity(0.18))
                .frame(width: 44, height: 1)
        }
    }


    private var friendSelectList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SELECT A FRIEND")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.ghostWhite)
                .tracking(1)

            if presenter.discoveredPeers.isEmpty {
                HStack {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                    Text("Scanning…")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ghostGray)
                }
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(presenter.discoveredPeers.enumerated()), id: \.offset) { index, peer in
                        Button {
                            presenter.didTapPeer(peer)
                        } label: {
                            friendRow(
                                peer: peer,
                                isSelected: presenter.selectedPeer?.displayName == peer.displayName
                            )
                        }

                        if index < presenter.discoveredPeers.count - 1 {
                            Divider()
                                .background(Color.white.opacity(0.06))
                                .padding(.horizontal, 10)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.20))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.ghostGold.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func friendRow(peer: NWBrowser.Result, isSelected: Bool) -> some View {
        HStack {
            Image(systemName: "person.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.ghostRedBright)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.ghostRedBright.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(peer.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Investigator")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ghostGray)
            }

            Spacer()

            Circle()
                .stroke(isSelected ? Color.ghostRedBright : Color.ghostGray.opacity(0.4), lineWidth: 1.5)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .fill(isSelected ? Color.ghostRedBright : Color.clear)
                        .frame(width: 12, height: 12)
                )
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
    }

    private var bottomButtons: some View {
        VStack(spacing: 0) {
            if presenter.networkState == .disconnected {
                Button(action: presenter.didTapHost) {
                    Text("HOST GAME")
                }
                .buttonStyle(GhostPrimaryButtonStyle())

                diamondDivider
                    .padding(.vertical, 14)

                Button(action: presenter.didTapJoin) {
                    Text("Join Game")
                }
                .buttonStyle(GhostDimButtonStyle())
            } else if presenter.networkState == .browsing {
                Button(action: presenter.didTapJoin) {
                    Text("Join Game")
                }
                .buttonStyle(GhostPrimaryButtonStyle())
                .disabled(presenter.selectedPeer == nil)
                .opacity(presenter.selectedPeer == nil ? 0.55 : 1)
            }
        }
    }
}

private extension NWBrowser.Result {
    var displayName: String {
        if case let .service(name, _, _, _) = endpoint {
            return name
        }
        return "Friend_1"
    }
}

#Preview {
    LobbyView(networkService: NetworkService())
}
