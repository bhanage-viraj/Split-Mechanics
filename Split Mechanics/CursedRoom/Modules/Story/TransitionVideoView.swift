import AVFoundation
import SwiftUI

struct TransitionVideoView: View {
    let onFinished: () -> Void

    var body: some View {
        _TransitionVideoRepresentable(onFinished: onFinished)
            .ignoresSafeArea()
            .background(Color.black)
    }
}

private struct _TransitionVideoRepresentable: UIViewRepresentable {
    let onFinished: () -> Void

    func makeUIView(context: Context) -> _TransitionVideoUIView {
        let view = _TransitionVideoUIView()
        view.configure(onFinished: onFinished)
        return view
    }

    func updateUIView(_ uiView: _TransitionVideoUIView, context: Context) {}
}

private final class _TransitionVideoUIView: UIView {
    private var player: AVPlayer?
    private var observer: NSObjectProtocol?
    private var timeObserverToken: Any?
    private var onFinished: (() -> Void)?
    private var isFinished = false

    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    func configure(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished

        // Search for transition.mp4 first, fallback to transition.mov, then fallback to background2.mov
        var videoURL = Bundle.main.url(forResource: "transition", withExtension: "mp4")
        if videoURL == nil {
            videoURL = Bundle.main.url(forResource: "transition", withExtension: "mov")
        }
        if videoURL == nil {
            videoURL = Bundle.main.url(forResource: "background2", withExtension: "mov")
            print("⚠️ [TransitionVideo] transition.mp4/mov not found, falling back to background2.mov")
        }

        guard let url = videoURL else { return }

        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = true // un-muted to support audio if desired, or change to true
        player.actionAtItemEnd = .pause

        self.player = player
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill

        setupBoundaryTimeObserver(for: player)
        setupNotification(for: playerItem)
        player.play()
    }

    private func triggerFinish() {
        guard !isFinished else { return }
        isFinished = true
        player?.pause()
        onFinished?()
    }

    private func setupBoundaryTimeObserver(for player: AVPlayer) {
        let times = [NSValue(time: CMTime(seconds: 4.0, preferredTimescale: 600))]
        timeObserverToken = player.addBoundaryTimeObserver(forTimes: times, queue: .main) { [weak self] in
            self?.triggerFinish()
        }
    }

    private func setupNotification(for item: AVPlayerItem) {
        observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.triggerFinish()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            player?.play()
        }
    }

    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
        }
        player?.pause()
        player = nil
    }
}
