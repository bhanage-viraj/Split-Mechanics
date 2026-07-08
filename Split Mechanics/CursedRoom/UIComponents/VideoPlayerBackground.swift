//
//  VideoPlayerBackground.swift
//  The Cursed Room
//
//  Reusable full-screen looping video background using AVQueuePlayer + AVPlayerLooper.
//

import AVFoundation
import SwiftUI
import UIKit

// MARK: - VideoPlayerBackground (SwiftUI View)

/// A seamlessly looping video background that fills its container.
///
/// Usage:
/// ```swift
/// VideoPlayerBackground(resourceName: "background", fileExtension: "mp4")
/// ```
struct VideoPlayerBackground: View {
    let resourceName: String
    let fileExtension: String
    var overlayOpacity: Double = 0.3
    var isLooping: Bool = true
    var showsLastFrameOnly: Bool = false

    var body: some View {
        _VideoPlayerRepresentable(
            resourceName: resourceName,
            fileExtension: fileExtension,
            isLooping: isLooping,
            showsLastFrameOnly: showsLastFrameOnly
        )
        .ignoresSafeArea()
        .overlay(Color.black.opacity(overlayOpacity))
    }
}

// MARK: - UIViewRepresentable Wrapper

private struct _VideoPlayerRepresentable: UIViewRepresentable {
    let resourceName: String
    let fileExtension: String
    let isLooping: Bool
    let showsLastFrameOnly: Bool

    func makeUIView(context: Context) -> _LoopingVideoView {
        let view = _LoopingVideoView()
        view.configure(
            resourceName: resourceName,
            fileExtension: fileExtension,
            isLooping: isLooping,
            showsLastFrameOnly: showsLastFrameOnly
        )
        return view
    }

    func updateUIView(_ uiView: _LoopingVideoView, context: Context) {
        uiView.updateLooping(isLooping)
    }
}

// MARK: - UIKit Looping Video View

/// Wraps `AVPlayer` in a `UIView` with an `AVPlayerLayer` that fills the view
/// using `.resizeAspectFill`. Performs smooth looping via NotificationCenter.
private final class _LoopingVideoView: UIView {

    private var player: AVPlayer?
    private var resourceName: String?
    private var fileExtension: String?
    private var isLooping: Bool = true
    private var showsLastFrameOnly: Bool = false
    private var observer: NSObjectProtocol?

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    func configure(resourceName: String, fileExtension: String, isLooping: Bool, showsLastFrameOnly: Bool) {
        self.resourceName = resourceName
        self.fileExtension = fileExtension
        self.isLooping = isLooping
        self.showsLastFrameOnly = showsLastFrameOnly

        guard let url = Bundle.main.url(forResource: resourceName, withExtension: fileExtension) else {
            print("⚠️ [Video] Could not find \(resourceName).\(fileExtension) in bundle")
            return
        }

        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = true
        player.actionAtItemEnd = .pause

        self.player = player
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill

        setupNotification(for: playerItem)

        if showsLastFrameOnly {
            // Seek to a point far in the future to clamp to the end frame, and pause/don't play
            player.seek(to: CMTime(value: 9999, timescale: 1), toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.play()
        }
    }

    func updateLooping(_ isLooping: Bool) {
        self.isLooping = isLooping
    }

    private func setupNotification(for item: AVPlayerItem) {
        removeNotification()

        observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, let player = self.player else { return }
            if self.isLooping {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                player.play()
            }
        }
    }

    private func removeNotification() {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil && !showsLastFrameOnly {
            player?.play()
        }
    }

    deinit {
        removeNotification()
        player?.pause()
        player = nil
    }
}
