import AppKit

/// 비교 창의 개별 칸 — 이미지(ImageDisplayView 재사용) + 파일명 라벨.
final class ComparePaneView: NSView {
    let imageDisplayView = ImageDisplayView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let imageService: ImageServiceProtocol

    var onRequestClose: ((ComparePaneView) -> Void)?
    private let closeButton = NSButton()

    private(set) var file: ImageFile

    init(file: ImageFile, imageService: ImageServiceProtocol) {
        self.file = file
        self.imageService = imageService
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// 이미지를 비동기 로드해 표시한다.
    func load() {
        nameLabel.stringValue = file.name
        Task { [weak self] in
            guard let self else { return }
            let result = await self.imageService.loadImage(at: self.file.url)
            await MainActor.run {
                switch result {
                case .success(let image): self.imageDisplayView.display(image)
                case .failure: self.imageDisplayView.displayError()
                }
            }
        }
    }

    @objc private func closeTapped() { onRequestClose?(self) }

    func setCloseEnabled(_ enabled: Bool) {
        closeButton.isHidden = !enabled
        closeButton.isEnabled = enabled
    }

    private func setupViews() {
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        imageDisplayView.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.textColor = .secondaryLabelColor

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .circular
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "닫기")
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])

        addSubview(imageDisplayView)
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            imageDisplayView.topAnchor.constraint(equalTo: topAnchor),
            imageDisplayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageDisplayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageDisplayView.bottomAnchor.constraint(equalTo: nameLabel.topAnchor, constant: -2),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }
}
