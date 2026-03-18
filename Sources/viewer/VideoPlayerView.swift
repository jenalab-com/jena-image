import AppKit
import AVKit

/// AVPlayer 기반 영상 재생 뷰
final class VideoPlayerView: NSView {
    var onDoubleClick: (() -> Void)?

    private let playerView = AVPlayerView()
    private var player: AVPlayer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Public

    func play(url: URL) {
        stop()
        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: playerItem)
        player = newPlayer
        playerView.player = newPlayer
        newPlayer.play()
    }

    func stop() {
        player?.pause()
        player = nil
        playerView.player = nil
    }

    // MARK: - Double Click

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            onDoubleClick?()
        }
    }

    // MARK: - Setup

    private func setupViews() {
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.controlsStyle = .floating
        addSubview(playerView)

        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
}
