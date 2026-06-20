import AppKit

/// 비교 후보 이미지를 가로로 나열하는 strip. 항목 클릭 → onSelect.
final class CompareCandidateStrip: NSView {
    var onSelect: ((ImageFile) -> Void)?

    private let scrollView = NSScrollView()
    private let stack = NSStackView()
    private let imageService: ImageServiceProtocol
    private let files: [ImageFile]
    private static let thumbSize = CGSize(width: 72, height: 54)

    init(files: [ImageFile], imageService: ImageServiceProtocol) {
        self.files = files
        self.imageService = imageService
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (i, file) in files.enumerated() {
            let button = NSButton()
            button.bezelStyle = .smallSquare
            button.imageScaling = .scaleProportionallyUpOrDown
            button.title = ""
            button.tag = i
            button.target = self
            button.action = #selector(thumbTapped(_:))
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: Self.thumbSize.width).isActive = true
            button.heightAnchor.constraint(equalToConstant: Self.thumbSize.height).isActive = true
            if let cached = ThumbnailCache.shared.thumbnail(for: file.url) {
                button.image = cached
            } else {
                loadThumb(for: file, into: button)
            }
            stack.addArrangedSubview(button)
        }

        scrollView.documentView = stack
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.heightAnchor, constant: -2),
        ])
    }

    private func loadThumb(for file: ImageFile, into button: NSButton) {
        Task { [weak button] in
            let result = await imageService.generateThumbnail(at: file.url, size: Self.thumbSize)
            if case .success(let image) = result {
                ThumbnailCache.shared.store(image, for: file.url)
                await MainActor.run { button?.image = image }
            }
        }
    }

    @objc private func thumbTapped(_ sender: NSButton) {
        guard files.indices.contains(sender.tag) else { return }
        onSelect?(files[sender.tag])
    }
}
