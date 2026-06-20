import AppKit

/// 비교 창의 개별 칸 — 이미지(ImageDisplayView 재사용) + 파일명 라벨.
final class ComparePaneView: NSView {
    let imageDisplayView = ImageDisplayView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let imageService: ImageServiceProtocol

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
