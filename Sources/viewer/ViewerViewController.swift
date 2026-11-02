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
    func viewerIsBookmarked(_ viewer: ViewerViewController, url: URL) -> Bool
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
    private let categoryButton = NSButton(title: "카테고리", target: nil, action: nil)
    var categoryMenuProvider: (([URL]) -> NSMenu)?
    private let bookmarkButton = NSButton(title: "", target: nil, action: nil)

    /// MainWindowController가 주입하는 북마크 토글 클로저
    var onToggleBookmark: ((URL) -> Void)?

    private var imageFiles: [ImageFile] = []
    private var currentIndex: Int = 0
    private var loadTask: Task<Void, Never>?
    private var loadingThumbnailToken: ThumbnailRequestToken?
    private var loadGeneration = 0
    private var isShowingVideo = false
    private var slideshowTimer: Timer?
    private let colorButton = NSButton(title: "", target: nil, action: nil)
    private let colorPanel = ColorPalettePanel()
    private var imageBottomToContainer: NSLayoutConstraint!
    private var imageBottomToPanel: NSLayoutConstraint!
    /// 사용자가 연 상태. 동영상으로 넘어가 잠시 숨겨져도 유지된다.
    private var isColorPanelOpen = false
    private var isMagnifierToggleOn = false
    private var isOptionHeld = false
    private var isOriginalReady = false


    private let imageService: ImageServiceProtocol
    private let thumbnailProvider: ThumbnailProvider

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

    init(imageService: ImageServiceProtocol = ImageService(), thumbnailProvider: ThumbnailProvider? = nil) {
        self.imageService = imageService
        let provider = thumbnailProvider ?? .shared
        self.thumbnailProvider = provider
        self.thumbnailStrip = ThumbnailStripView(imageService: imageService, thumbnailProvider: provider)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit { loadTask?.cancel() }

    override var acceptsFirstResponder: Bool { true }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        // 뷰어를 벗어나면(브라우저 복귀·창 닫기 등) 슬라이드쇼 타이머를 반드시 정지
        stopSlideshow()
        cancelImageLoading()
        imageDisplayView.clearImage()
        closeColorPanel()
        isOptionHeld = false
        setOriginalReady(false)
    }

    override func loadView() {
        view = NSView()
        setupSplitView()
        setupEditButton()
        imageDisplayView.contextMenuProvider = { [weak self] in self?.makeContextMenu() }
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

        colorPanel.onMagnifierToggled = { [weak self] on in
            self?.isMagnifierToggleOn = on
            self?.updateMagnifierActive()
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

    func makeContextMenu() -> NSMenu? {
        guard currentImageURL != nil else { return nil }
        let menu = NSMenu()
        let rename = NSMenuItem(title: "이름 변경…", action: #selector(beginRenamingCurrentImage), keyEquivalent: "")
        rename.target = self
        menu.addItem(rename)
        return menu
    }

    @objc func beginRenamingCurrentImage() {
        guard let url = currentImageURL, let window = view.window else { return }
        stopSlideshow()
        let alert = NSAlert()
        alert.messageText = "파일 이름 변경"
        alert.informativeText = "확장자는 그대로 유지해요."
        alert.addButton(withTitle: "변경")
        alert.addButton(withTitle: "취소")
        let field = NSTextField(string: url.deletingPathExtension().lastPathComponent)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let stem = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !stem.isEmpty else { return }
            let name = stem + (url.pathExtension.isEmpty ? "" : "." + url.pathExtension)
            self.delegate?.viewer(self, didRequestRename: url, newName: name)
        }
    }

    func updateCurrentImage(oldURL: URL, newURL: URL) {
        guard let index = imageFiles.firstIndex(where: { $0.url == oldURL }),
              let newFile = ImageFile(url: newURL) else { return }
        imageFiles[index] = newFile
        thumbnailStrip.display(images: imageFiles, selectedIndex: currentIndex)
        if index == currentIndex {
            view.window?.title = newFile.name
            if imageDisplayView.isLoading { showImage(newFile) }
        }
    }

    /// 외부에서 현재 이미지 파일이 변경된 경우 디스크에서 다시 읽어 갱신
    func reloadCurrentImage() {
        guard let file = currentFile, !file.isVideo else { return }
        thumbnailProvider.invalidate(for: file.url)
        thumbnailStrip.reloadThumbnail(at: currentIndex)
        showImage(file)
    }

    // MARK: - Zoom

    func zoomIn() { imageDisplayView.zoomIn() }
    func zoomOut() { imageDisplayView.zoomOut() }
    func zoomActualSize() { imageDisplayView.zoomToActualSize() }
    func zoomFit() { imageDisplayView.fitToView() }
    func applyFitMode(_ mode: AppSettings.ViewerFitMode) { imageDisplayView.applyFit(mode) }

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

    // MARK: - Slideshow

    var isSlideshowRunning: Bool { slideshowTimer != nil }

    func toggleSlideshow() {
        if isSlideshowRunning { stopSlideshow() } else { startSlideshow() }
    }

    func startSlideshow() {
        guard imageFiles.count > 1, slideshowTimer == nil else { return }
        let interval = AppSettings.shared.slideshowInterval
        slideshowTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.advanceSlideshow()
        }
    }

    func stopSlideshow() {
        slideshowTimer?.invalidate()
        slideshowTimer = nil
    }

    /// 다음 이미지로 넘기되, 마지막이면 처음으로 순환한다.
    private func advanceSlideshow() {
        guard !imageFiles.isEmpty else { stopSlideshow(); return }
        showMedia(at: (currentIndex + 1) % imageFiles.count)
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

        if let url = currentImageURL {
            updateBookmarkButton(isBookmarked: delegate?.viewerIsBookmarked(self, url: url) ?? false)
        }
    }

    private func showVideo(_ file: ImageFile) {
        cancelImageLoading()
        imageDisplayView.clearImage()
        setOriginalReady(false)
        switchContentView(toVideo: true)
        videoPlayerView.play(url: file.url)
        view.window?.title = file.name
    }

    private func showImage(_ file: ImageFile) {
        switchContentView(toVideo: false)
        videoPlayerView.stop()

        cancelImageLoading()
        let generation = loadGeneration
        imageDisplayView.displayLoading()
        setOriginalReady(false)
        view.window?.title = file.name
        // 작은 캐시도 즉시 활용하고, 없으면 기존 썸네일 파이프라인에서 비동기로 받는다.
        loadingThumbnailToken = thumbnailProvider.request(file.url, minPixel: 1, priority: .visible) { [weak self] result in
            guard let self, self.loadGeneration == generation, self.imageDisplayView.isLoading else { return }
            self.loadingThumbnailToken = nil
            if case .image(let thumbnail) = result {
                self.imageDisplayView.displayLoadingPreview(thumbnail)
            }
        }
        let service = imageService
        loadTask = Task { @MainActor [weak self] in
            let result = await service.loadImage(at: file.url)
            guard !Task.isCancelled, let self, self.loadGeneration == generation else { return }
            self.cancelLoadingThumbnail()
            switch result {
            case .success(let image):
                self.imageDisplayView.display(image)
                self.setOriginalReady(true)
            case .failure:
                self.imageDisplayView.displayError()
                self.colorPanel.setState(.empty)
            }
        }
    }

    private func cancelLoadingThumbnail() {
        if let token = loadingThumbnailToken { thumbnailProvider.cancel(token) }
        loadingThumbnailToken = nil
    }

    private func cancelImageLoading() {
        loadGeneration += 1
        loadTask?.cancel()
        cancelLoadingThumbnail()
    }

    private func switchContentView(toVideo: Bool) {
        let changed = toVideo != isShowingVideo
        isShowingVideo = toVideo

        imageDisplayView.isHidden = toVideo
        videoPlayerView.isHidden = !toVideo
        editButton.isHidden = toVideo
        colorButton.isHidden = toVideo
        applyColorPanelVisibility()
        updateMagnifierActive()

        bookmarkButton.isHidden = toVideo
        categoryButton.isHidden = toVideo

        if changed {
            delegate?.viewer(self, didSwitchToVideo: toVideo)
        }
    }

    // MARK: - Key Handling

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:  // ESC
            if isSlideshowRunning {
                stopSlideshow()  // 슬라이드쇼 중이면 닫지 않고 정지만
            } else {
                videoPlayerView.stop()
                delegate?.viewerDidRequestClose(self)
            }
        case 126, 123: // ↑, ←
            stopSlideshow()  // 수동 조작 시 슬라이드쇼 정지
            if let newIndex = thumbnailStrip.selectPrevious() {
                showMedia(at: newIndex)
            }
        case 125, 124: // ↓, →
            stopSlideshow()
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

    // MARK: - Color Panel

    /// 원본 로딩이 끝났을 때만 색상 기능을 켠다(썸네일 미리보기로 뽑으면 저해상도 값이 나온다). 편집 버튼과 같은 규칙.
    private func setOriginalReady(_ ready: Bool) {
        isOriginalReady = ready
        editButton.isEnabled = ready
        colorButton.isEnabled = ready
        if !ready { imageDisplayView.pixelSource = nil }
        if isColorPanelOpen && !ready { colorPanel.setState(.loading) }
        updateMagnifierActive()
    }

    @objc private func colorButtonTapped() {
        if isColorPanelOpen { closeColorPanel() } else { openColorPanel() }
    }

    private func openColorPanel() {
        guard isOriginalReady, !isShowingVideo else { colorButton.state = .off; return }
        isColorPanelOpen = true
        colorButton.state = .on
        colorPanel.setTolerance(AppSettings.shared.colorTolerance)
        colorPanel.setMagnifierOn(false)             // 패널을 연다고 돋보기가 켜지지 않는다
        isMagnifierToggleOn = false
        colorPanel.setState(.loading)
        applyColorPanelVisibility()
        updateMagnifierActive()
    }

    private func closeColorPanel() {
        isColorPanelOpen = false
        isMagnifierToggleOn = false
        colorButton.state = .off
        colorPanel.setMagnifierOn(false)
        applyColorPanelVisibility()
        updateMagnifierActive()
    }

    private func applyColorPanelVisibility() {
        let visible = isColorPanelOpen && !isShowingVideo
        colorPanel.isHidden = !visible
        // 둘을 동시에 켜지 않도록 끄는 쪽을 먼저 처리한다.
        if visible { imageBottomToContainer.isActive = false; imageBottomToPanel.isActive = true }
        else { imageBottomToPanel.isActive = false; imageBottomToContainer.isActive = true }
    }

    /// 돋보기 = (패널이 열려 있고 토글이 켜짐) 또는 ⌥ 단독. 원본 로딩이 끝난 이미지에서만.
    private func updateMagnifierActive() {
        let toggled = isColorPanelOpen && isMagnifierToggleOn
        imageDisplayView.isMagnifierActive = isOriginalReady && !isShowingVideo && (toggled || isOptionHeld)
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

        bookmarkButton.translatesAutoresizingMaskIntoConstraints = false
        bookmarkButton.bezelStyle = .rounded
        bookmarkButton.controlSize = .small
        bookmarkButton.image = NSImage(systemSymbolName: "star", accessibilityDescription: "북마크")
        bookmarkButton.target = self
        bookmarkButton.action = #selector(bookmarkButtonTapped)

        categoryButton.translatesAutoresizingMaskIntoConstraints = false
        categoryButton.bezelStyle = .rounded
        categoryButton.controlSize = .small
        categoryButton.font = .systemFont(ofSize: 12)
        categoryButton.image = NSImage(systemSymbolName: "tag", accessibilityDescription: "카테고리 지정")
        categoryButton.imagePosition = .imageLeading
        categoryButton.toolTip = "이 이미지의 카테고리 지정/해제"
        categoryButton.target = self
        categoryButton.action = #selector(categoryButtonTapped)
        contentContainer.addSubview(categoryButton)
        contentContainer.addSubview(editButton)
        contentContainer.addSubview(thumbnailToggleButton)
        contentContainer.addSubview(bookmarkButton)
        colorButton.translatesAutoresizingMaskIntoConstraints = false
        colorButton.bezelStyle = .rounded
        colorButton.controlSize = .small
        colorButton.image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: L10n.string(.colorButton))
        colorButton.toolTip = L10n.string(.colorButton)
        colorButton.setButtonType(.pushOnPushOff)
        colorButton.refusesFirstResponder = true
        colorButton.isEnabled = false
        colorButton.target = self
        colorButton.action = #selector(colorButtonTapped)
        contentContainer.addSubview(colorButton)


        NSLayoutConstraint.activate([
            thumbnailToggleButton.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -8),
            thumbnailToggleButton.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -8),

            editButton.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -8),
            editButton.trailingAnchor.constraint(equalTo: thumbnailToggleButton.leadingAnchor, constant: -6),

            categoryButton.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -8),
            categoryButton.trailingAnchor.constraint(equalTo: bookmarkButton.leadingAnchor, constant: -6),
            bookmarkButton.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -8),
            bookmarkButton.trailingAnchor.constraint(equalTo: colorButton.leadingAnchor, constant: -6),
            colorButton.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -8),
            colorButton.trailingAnchor.constraint(equalTo: editButton.leadingAnchor, constant: -6),
        ])
    }

    func updateBookmarkButton(isBookmarked: Bool) {
        let name = isBookmarked ? "star.fill" : "star"
        bookmarkButton.image = NSImage(systemSymbolName: name, accessibilityDescription: "북마크")
    }

    @objc private func categoryButtonTapped() {
        guard let url = currentImageURL, let menu = categoryMenuProvider?([url]) else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: categoryButton.bounds.height), in: categoryButton)
    }

    @objc private func bookmarkButtonTapped() {
        guard let url = currentImageURL else { return }
        onToggleBookmark?(url)
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
            imageDisplayView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            imageDisplayView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            videoPlayerView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            videoPlayerView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            videoPlayerView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            videoPlayerView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
        ])

        imageBottomToContainer = imageDisplayView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        imageBottomToPanel = imageDisplayView.bottomAnchor.constraint(equalTo: colorPanel.topAnchor)
        imageBottomToContainer.isActive = true

        // 색상 패널: 이미지 아래, 하단 버튼 줄(약 40pt) 위. 열리면 이미지 영역이 그만큼 줄어든다.
        colorPanel.translatesAutoresizingMaskIntoConstraints = false
        colorPanel.isHidden = true
        contentContainer.addSubview(colorPanel)
        NSLayoutConstraint.activate([
            colorPanel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            colorPanel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            colorPanel.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -40),
        ])

        splitView.addSubview(contentContainer)
        splitView.addSubview(thumbnailStrip)

        view.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: view.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            thumbnailStrip.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
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
