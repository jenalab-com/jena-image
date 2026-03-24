import AppKit

// MARK: - Delegate

protocol ViewerDelegate: AnyObject {
    func viewerDidRequestClose(_ viewer: ViewerViewController)
    func viewer(_ viewer: ViewerViewController, didRequestDelete url: URL)
    func viewer(_ viewer: ViewerViewController, didRequestExport url: URL)
    func viewer(_ viewer: ViewerViewController, didRequestRename url: URL, newName: String)
    func viewer(_ viewer: ViewerViewController, didSwitchToVideo isVideo: Bool)
    func viewer(_ viewer: ViewerViewController, didNavigateToFile url: URL)
    func viewerDidEndEditing(_ viewer: ViewerViewController)
    func viewer(_ viewer: ViewerViewController, didSaveEditedImageToFolder folderURL: URL)
}

// MARK: - ViewController

final class ViewerViewController: NSViewController {
    weak var delegate: ViewerDelegate?

    private let thumbnailStrip: ThumbnailStripView
    private let imageDisplayView = ImageDisplayView()
    private let videoPlayerView = VideoPlayerView()
    private let contentContainer = NSView()
    private let splitView = NSSplitView()

    // 하단 버튼
    private let editButton = NSButton(title: "편집", target: nil, action: nil)
    private let thumbnailToggleButton = NSButton(title: "", target: nil, action: nil)

    private var imageFiles: [ImageFile] = []
    private var currentIndex: Int = 0
    private var loadTask: Task<Void, Never>?
    private var isShowingVideo = false

    private let imageService: ImageServiceProtocol

    // 편집 윈도우
    private var editorWindowController: ImageEditorWindowController?

    var currentImageURL: URL? {
        imageFiles[safe: currentIndex]?.url
    }

    var currentImage: NSImage? {
        imageDisplayView.currentImage
    }

    var currentFile: ImageFile? {
        imageFiles[safe: currentIndex]
    }

    var isShowingImage: Bool {
        !isShowingVideo && imageDisplayView.currentImage != nil
    }

    var isEditing: Bool {
        editorWindowController != nil
    }

    init(imageService: ImageServiceProtocol = ImageService()) {
        self.imageService = imageService
        self.thumbnailStrip = ThumbnailStripView(imageService: imageService)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func loadView() {
        view = NSView()
        setupSplitView()
        setupEditButton()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        thumbnailStrip.onImageSelected = { [weak self] index in
            self?.showMedia(at: index)
        }

        imageDisplayView.onDoubleClick = { [weak self] in
            guard let self else { return }
            self.delegate?.viewerDidRequestClose(self)
        }

        videoPlayerView.onDoubleClick = { [weak self] in
            guard let self else { return }
            self.delegate?.viewerDidRequestClose(self)
        }
    }

    // MARK: - Public

    func display(imageURL: URL, imageList: [ImageFile]) {
        imageFiles = imageList
        currentIndex = imageList.firstIndex(where: { $0.url == imageURL }) ?? 0
        thumbnailStrip.display(images: imageList, selectedIndex: currentIndex)
        showMedia(at: currentIndex)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.window?.makeFirstResponder(self)
        }
    }

    func updateCurrentImage(oldURL: URL, newURL: URL) {
        guard let index = imageFiles.firstIndex(where: { $0.url == oldURL }),
              let newFile = ImageFile(url: newURL) else { return }
        imageFiles[index] = newFile
        thumbnailStrip.display(images: imageFiles, selectedIndex: currentIndex)
        if index == currentIndex {
            view.window?.title = newFile.name
        }
    }

    // MARK: - Zoom

    func zoomIn() { imageDisplayView.zoomIn() }
    func zoomOut() { imageDisplayView.zoomOut() }
    func zoomActualSize() { imageDisplayView.zoomToActualSize() }
    func zoomFit() { imageDisplayView.fitToView() }

    // MARK: - Flip

    func flipHorizontal() { imageDisplayView.flipHorizontal() }
    func flipVertical() { imageDisplayView.flipVertical() }
    func rotateLeft() { imageDisplayView.rotateLeft() }
    func rotateRight() { imageDisplayView.rotateRight() }
    func resetFlip() { imageDisplayView.resetFlip() }

    // MARK: - Image Editing

    func openEditor() {
        guard let image = imageDisplayView.currentImage,
              let url = currentImageURL,
              editorWindowController == nil else { return }

        let controller = ImageEditorWindowController(image: image, url: url, imageService: imageService)
        controller.onComplete = { [weak self] in
            guard let self else { return }
            self.editorWindowController = nil
            self.delegate?.viewerDidEndEditing(self)
        }
        controller.onSaved = { [weak self] folderURL in
            guard let self else { return }
            self.delegate?.viewer(self, didSaveEditedImageToFolder: folderURL)
        }
        controller.showWindow(nil)
        editorWindowController = controller
    }

    func closeEditor() {
        editorWindowController?.close()
        editorWindowController = nil
    }

    // MARK: - Navigation

    func showPrevious() {
        if let newIndex = thumbnailStrip.selectPrevious() {
            showMedia(at: newIndex)
        }
    }

    func showNext() {
        if let newIndex = thumbnailStrip.selectNext() {
            showMedia(at: newIndex)
        }
    }

    // MARK: - Media Display

    private func showMedia(at index: Int) {
        guard let file = imageFiles[safe: index] else { return }
        currentIndex = index
        thumbnailStrip.selectImage(at: index)

        if file.isVideo {
            showVideo(file)
        } else {
            showImage(file)
        }

        delegate?.viewer(self, didNavigateToFile: file.url)
    }

    private func showVideo(_ file: ImageFile) {
        loadTask?.cancel()
        switchContentView(toVideo: true)
        videoPlayerView.play(url: file.url)
        view.window?.title = file.name
    }

    private func showImage(_ file: ImageFile) {
        switchContentView(toVideo: false)
        videoPlayerView.stop()

        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.imageService.loadImage(at: file.url)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                switch result {
                case .success(let image):
                    self.imageDisplayView.display(image)
                    self.view.window?.title = file.name
                case .failure:
                    self.imageDisplayView.displayError()
                }
            }
        }
    }

    private func switchContentView(toVideo: Bool) {
        let changed = toVideo != isShowingVideo
        isShowingVideo = toVideo

        imageDisplayView.isHidden = toVideo
        videoPlayerView.isHidden = !toVideo
        editButton.isHidden = toVideo

        if changed {
            delegate?.viewer(self, didSwitchToVideo: toVideo)
        }
    }

    // MARK: - Key Handling

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:  // ESC
            videoPlayerView.stop()
            delegate?.viewerDidRequestClose(self)
        case 126, 123: // ↑, ←
            if let newIndex = thumbnailStrip.selectPrevious() {
                showMedia(at: newIndex)
            }
        case 125, 124: // ↓, →
            if let newIndex = thumbnailStrip.selectNext() {
                showMedia(at: newIndex)
            }
        case 24 where event.modifierFlags.contains(.command):
            imageDisplayView.zoomIn()
        case 27 where event.modifierFlags.contains(.command):
            imageDisplayView.zoomOut()
        case 29 where event.modifierFlags.contains(.command):
            imageDisplayView.zoomToActualSize()
        case 25 where event.modifierFlags.contains(.command):
            imageDisplayView.fitToView()
        case 51:  // Delete
            if let url = currentImageURL {
                delegate?.viewer(self, didRequestDelete: url)
            }
        default:
            super.keyDown(with: event)
        }
    }

    func removeCurrentImage() {
        guard imageFiles.indices.contains(currentIndex) else { return }
        imageFiles.remove(at: currentIndex)

        if imageFiles.isEmpty {
            videoPlayerView.stop()
            delegate?.viewerDidRequestClose(self)
            return
        }

        let newIndex = min(currentIndex, imageFiles.count - 1)
        thumbnailStrip.display(images: imageFiles, selectedIndex: newIndex)
        showMedia(at: newIndex)
    }

    // MARK: - Bottom Buttons

    private var isThumbnailVisible = true

    private func setupEditButton() {
        editButton.translatesAutoresizingMaskIntoConstraints = false
        editButton.bezelStyle = .rounded
        editButton.controlSize = .small
        editButton.font = .systemFont(ofSize: 12)
        editButton.target = self
        editButton.action = #selector(editButtonTapped)

        thumbnailToggleButton.translatesAutoresizingMaskIntoConstraints = false
        thumbnailToggleButton.bezelStyle = .rounded
        thumbnailToggleButton.controlSize = .small
        thumbnailToggleButton.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "썸네일 목록")
        thumbnailToggleButton.setButtonType(.toggle)
        thumbnailToggleButton.state = .on
        thumbnailToggleButton.target = self
        thumbnailToggleButton.action = #selector(toggleThumbnailStrip)

        contentContainer.addSubview(editButton)
        contentContainer.addSubview(thumbnailToggleButton)

        NSLayoutConstraint.activate([
            thumbnailToggleButton.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -8),
            thumbnailToggleButton.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -8),

            editButton.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -8),
            editButton.trailingAnchor.constraint(equalTo: thumbnailToggleButton.leadingAnchor, constant: -6),
        ])
    }

    @objc private func editButtonTapped() {
        openEditor()
    }

    @objc private func toggleThumbnailStrip() {
        isThumbnailVisible.toggle()
        thumbnailToggleButton.state = isThumbnailVisible ? .on : .off

        if isThumbnailVisible {
            thumbnailStrip.isHidden = false
        } else {
            thumbnailStrip.isHidden = true
        }
        splitView.adjustSubviews()
    }

    // MARK: - Setup

    private func setupSplitView() {
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        imageDisplayView.translatesAutoresizingMaskIntoConstraints = false
        videoPlayerView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailStrip.translatesAutoresizingMaskIntoConstraints = false

        contentContainer.addSubview(imageDisplayView)
        contentContainer.addSubview(videoPlayerView)
        videoPlayerView.isHidden = true

        NSLayoutConstraint.activate([
            imageDisplayView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            imageDisplayView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            imageDisplayView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            imageDisplayView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            videoPlayerView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            videoPlayerView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            videoPlayerView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            videoPlayerView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
        ])

        splitView.addSubview(contentContainer)
        splitView.addSubview(thumbnailStrip)

        view.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: view.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            thumbnailStrip.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            thumbnailStrip.widthAnchor.constraint(lessThanOrEqualToConstant: 180),
        ])
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
