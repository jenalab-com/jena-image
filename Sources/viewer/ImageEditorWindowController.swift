import AppKit

/// 이미지 편집 전용 윈도우 — 좌측 이미지 미리보기 + 우측 편집 도구
final class ImageEditorWindowController: NSWindowController {

    private let originalImage: NSImage
    private let originalURL: URL
    private let imageService: ImageServiceProtocol

    private let editingService = ImageEditingService()
    private var editedImage: NSImage

    // Undo/Redo 히스토리 (최대 10개)
    private var undoStack: [NSImage] = []
    private var redoStack: [NSImage] = []
    private let maxHistory = 10

    // 좌측: 이미지 표시
    private let imageScrollView = NSScrollView()
    private let imageView = NSImageView()

    // 우측: 편집 도구 패널
    private let controlsView = NSView()
    private let imageSizeLabel = NSTextField(labelWithString: "")

    // 도구 선택
    private enum Tool { case none, crop, resize, canvas, adjust }
    private var activeTool: Tool = .none

    private let cropButton = NSButton(title: "자르기", target: nil, action: nil)
    private let resizeButton = NSButton(title: "이미지 크기", target: nil, action: nil)
    private let canvasButton = NSButton(title: "캔버스 크기", target: nil, action: nil)
    private let adjustButton = NSButton(title: "색상 보정", target: nil, action: nil)

    // 색상 보정 슬라이더
    private let brightnessSlider = NSSlider()
    private let contrastSlider = NSSlider()
    private let saturationSlider = NSSlider()
    private let highlightsSlider = NSSlider()
    private let shadowsSlider = NSSlider()
    private let brightnessLabel = NSTextField(labelWithString: "0")
    private let contrastLabel = NSTextField(labelWithString: "1.00")
    private let saturationLabel = NSTextField(labelWithString: "1.00")
    private let highlightsLabel = NSTextField(labelWithString: "0")
    private let shadowsLabel = NSTextField(labelWithString: "0")

    private let undoButton = NSButton(title: "", target: nil, action: nil)
    private let redoButton = NSButton(title: "", target: nil, action: nil)

    private let toolOptionsContainer = NSScrollView()
    private let toolOptionsContent = NSView()

    // Resize
    private let resizeWidthField = NSTextField()
    private let resizeHeightField = NSTextField()
    private let resizeLockAspect = NSButton(checkboxWithTitle: "비율 유지", target: nil, action: nil)
    private var resizeAspectRatio: CGFloat = 1.0
    private var isResizeUpdating = false

    // Canvas
    private let canvasModeSegment = NSSegmentedControl(labels: ["상대", "절대"], trackingMode: .selectOne, target: nil, action: nil)
    private let canvasWidthField = NSTextField()
    private let canvasHeightField = NSTextField()
    private let canvasAlignPopup = NSPopUpButton()
    private let canvasColorWell = NSColorWell()
    private let canvasTransparentCheck = NSButton(checkboxWithTitle: "투명", target: nil, action: nil)
    private let canvasPreviewLabel = NSTextField(labelWithString: "")

    // Crop overlay
    private var cropOverlay: CropOverlayView?

    // 콜백
    var onComplete: (() -> Void)?
    /// 저장 완료 시 — 저장된 파일의 부모 폴더 URL 전달
    var onSaved: ((URL) -> Void)?

    init(image: NSImage, url: URL, imageService: ImageServiceProtocol) {
        self.originalImage = image
        self.editedImage = image
        self.originalURL = url
        self.imageService = imageService

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "이미지 편집 — \(url.lastPathComponent)"
        win.minSize = NSSize(width: 700, height: 450)
        win.center()

        super.init(window: win)
        win.delegate = self

        setupUI()
        displayImage(image)
        updateSizeLabel()
        observeScrollViewResize()
    }

    private var frameObserver: NSObjectProtocol?

    private func observeScrollViewResize() {
        imageScrollView.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: imageScrollView,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.fitImageToView()
            if let overlay = self.cropOverlay {
                DispatchQueue.main.async {
                    // 오버레이 프레임을 스크롤뷰에 맞춤 (autoresizingMask 대체)
                    overlay.frame = self.imageScrollView.bounds
                    overlay.updateImageRect(self.computeImageRect())
                }
            }
        }
    }

    deinit {
        if let obs = frameObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupUI() {
        guard let window else { return }

        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false

        // --- 좌측: 이미지 미리보기 ---
        let imageContainer = NSView()
        imageContainer.translatesAutoresizingMaskIntoConstraints = false

        imageScrollView.translatesAutoresizingMaskIntoConstraints = false
        imageScrollView.hasVerticalScroller = true
        imageScrollView.hasHorizontalScroller = true
        imageScrollView.allowsMagnification = true
        imageScrollView.minMagnification = 0.1
        imageScrollView.maxMagnification = 5.0
        imageScrollView.backgroundColor = .controlBackgroundColor
        imageScrollView.wantsLayer = true
        imageScrollView.layer?.cornerRadius = 6

        imageView.imageScaling = .scaleNone
        imageView.translatesAutoresizingMaskIntoConstraints = false

        // CenteringClipView로 이미지를 항상 중앙 배치
        let centeringClip = CenteringClipView()
        centeringClip.documentView = imageView
        imageScrollView.contentView = centeringClip

        // 이미지 영역에 패딩 — 창 가장자리 리사이즈와 crop 드래그가 겹치지 않게
        imageContainer.addSubview(imageScrollView)
        let pad: CGFloat = 12
        NSLayoutConstraint.activate([
            imageScrollView.topAnchor.constraint(equalTo: imageContainer.topAnchor, constant: pad),
            imageScrollView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor, constant: -pad),
            imageScrollView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor, constant: pad),
            imageScrollView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor, constant: -pad),
        ])

        // --- 우측: 편집 도구 ---
        controlsView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "편집 도구")
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        controlsView.addSubview(titleLabel)

        imageSizeLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        imageSizeLabel.textColor = .secondaryLabelColor
        imageSizeLabel.translatesAutoresizingMaskIntoConstraints = false
        controlsView.addSubview(imageSizeLabel)

        // Undo/Redo 버튼
        undoButton.translatesAutoresizingMaskIntoConstraints = false
        undoButton.bezelStyle = .rounded
        undoButton.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "실행 취소")
        undoButton.toolTip = "실행 취소 (⌘Z)"
        undoButton.target = self
        undoButton.action = #selector(undoTapped)
        undoButton.isEnabled = false

        redoButton.translatesAutoresizingMaskIntoConstraints = false
        redoButton.bezelStyle = .rounded
        redoButton.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: "다시 실행")
        redoButton.toolTip = "다시 실행 (⌘⇧Z)"
        redoButton.target = self
        redoButton.action = #selector(redoTapped)
        redoButton.isEnabled = false

        let undoRedoStack = NSStackView(views: [undoButton, redoButton])
        undoRedoStack.translatesAutoresizingMaskIntoConstraints = false
        undoRedoStack.spacing = 4
        controlsView.addSubview(undoRedoStack)

        // 도구 버튼
        for (button, action) in [
            (cropButton, #selector(cropTapped)),
            (resizeButton, #selector(resizeTapped)),
            (canvasButton, #selector(canvasTapped)),
            (adjustButton, #selector(adjustTapped)),
        ] as [(NSButton, Selector)] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.bezelStyle = .rounded
            button.setButtonType(.toggle)
            button.target = self
            button.action = action
        }

        let toolStack = NSStackView(views: [cropButton, resizeButton, canvasButton, adjustButton])
        toolStack.translatesAutoresizingMaskIntoConstraints = false
        toolStack.distribution = .fillEqually
        toolStack.spacing = 6
        controlsView.addSubview(toolStack)

        // 변형 버튼 (좌우 반전, 상하 반전, 왼쪽 회전, 오른쪽 회전)
        let transformStack = NSStackView()
        transformStack.translatesAutoresizingMaskIntoConstraints = false
        transformStack.spacing = 4
        for (symbolName, tooltip, action) in [
            ("arrow.left.and.right.righttriangle.left.righttriangle.right", "좌우 반전", #selector(editorFlipH)),
            ("arrow.up.and.down.righttriangle.up.righttriangle.down", "상하 반전", #selector(editorFlipV)),
            ("rotate.left", "왼쪽으로 회전", #selector(editorRotateLeft)),
            ("rotate.right", "오른쪽으로 회전", #selector(editorRotateRight)),
        ] as [(String, String, Selector)] {
            let btn = NSButton()
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.bezelStyle = .rounded
            btn.isBordered = true
            btn.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)
            btn.toolTip = tooltip
            btn.target = self
            btn.action = action
            NSLayoutConstraint.activate([
                btn.widthAnchor.constraint(equalToConstant: 32),
                btn.heightAnchor.constraint(equalToConstant: 28),
            ])
            transformStack.addArrangedSubview(btn)
        }
        controlsView.addSubview(transformStack)

        // 도구 옵션 스크롤 영역
        toolOptionsContainer.translatesAutoresizingMaskIntoConstraints = false
        toolOptionsContainer.hasVerticalScroller = true
        toolOptionsContainer.hasHorizontalScroller = false
        toolOptionsContainer.drawsBackground = false
        toolOptionsContent.translatesAutoresizingMaskIntoConstraints = false
        toolOptionsContainer.documentView = toolOptionsContent
        controlsView.addSubview(toolOptionsContainer)

        // 하단 버튼
        let saveButton = NSButton(title: "다른 이름으로 저장", target: self, action: #selector(saveTapped))
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = .command
        controlsView.addSubview(saveButton)

        let cancelButton = NSButton(title: "닫기", target: self, action: #selector(cancelTapped))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        controlsView.addSubview(cancelButton)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        controlsView.addSubview(separator)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: controlsView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: 16),

            imageSizeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            imageSizeLabel.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: 16),

            undoRedoStack.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            undoRedoStack.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -16),

            toolStack.topAnchor.constraint(equalTo: imageSizeLabel.bottomAnchor, constant: 16),
            toolStack.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: 16),
            toolStack.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -16),
            toolStack.heightAnchor.constraint(equalToConstant: 28),

            transformStack.topAnchor.constraint(equalTo: toolStack.bottomAnchor, constant: 8),
            transformStack.centerXAnchor.constraint(equalTo: controlsView.centerXAnchor),

            separator.topAnchor.constraint(equalTo: transformStack.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -16),

            toolOptionsContainer.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 12),
            toolOptionsContainer.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor),
            toolOptionsContainer.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor),
            toolOptionsContainer.bottomAnchor.constraint(equalTo: cancelButton.topAnchor, constant: -12),

            // toolOptionsContent fills width
            toolOptionsContent.leadingAnchor.constraint(equalTo: toolOptionsContainer.leadingAnchor),
            toolOptionsContent.trailingAnchor.constraint(equalTo: toolOptionsContainer.trailingAnchor),
            toolOptionsContent.topAnchor.constraint(equalTo: toolOptionsContainer.topAnchor),
            toolOptionsContent.widthAnchor.constraint(equalTo: toolOptionsContainer.widthAnchor),

            cancelButton.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -16),
            cancelButton.bottomAnchor.constraint(equalTo: controlsView.bottomAnchor, constant: -16),

            saveButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -8),
            saveButton.bottomAnchor.constraint(equalTo: controlsView.bottomAnchor, constant: -16),
        ])

        // Split View에 추가
        splitView.addSubview(imageContainer)
        splitView.addSubview(controlsView)

        window.contentView = splitView

        // 우측 패널 폭 제약
        NSLayoutConstraint.activate([
            controlsView.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            controlsView.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            imageContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 400),
        ])

        // 초기 비율
        splitView.setPosition(600, ofDividerAt: 0)
    }

    // MARK: - Image Display

    private func displayImage(_ image: NSImage) {
        imageView.image = image
        imageView.frame = NSRect(origin: .zero, size: image.size)
        fitImageToView()
    }

    private func fitImageToView() {
        guard let image = imageView.image else { return }
        let viewSize = imageScrollView.contentSize
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let scaleX = viewSize.width / imageSize.width
        let scaleY = viewSize.height / imageSize.height
        let scale = min(scaleX, scaleY, 1.0)
        imageScrollView.magnification = scale
    }

    private func updateSizeLabel() {
        let size = editedImage.size
        imageSizeLabel.stringValue = "\(Int(size.width)) × \(Int(size.height)) px"
    }

    // MARK: - Tool Selection

    @objc private func cropTapped() {
        selectTool(activeTool == .crop ? .none : .crop)
    }

    @objc private func resizeTapped() {
        selectTool(activeTool == .resize ? .none : .resize)
    }

    @objc private func canvasTapped() {
        selectTool(activeTool == .canvas ? .none : .canvas)
    }

    @objc private func adjustTapped() {
        selectTool(activeTool == .adjust ? .none : .adjust)
    }

    private func selectTool(_ tool: Tool) {
        // 이전 crop 해제
        if activeTool == .crop && tool != .crop {
            removeCropOverlay()
        }

        activeTool = tool
        cropButton.state = tool == .crop ? .on : .off
        resizeButton.state = tool == .resize ? .on : .off
        canvasButton.state = tool == .canvas ? .on : .off
        adjustButton.state = tool == .adjust ? .on : .off

        // 옵션 영역 초기화
        toolOptionsContent.subviews.forEach { $0.removeFromSuperview() }

        switch tool {
        case .none:
            break
        case .crop:
            showCropOptions()
            addCropOverlay()
        case .resize:
            showResizeOptions()
        case .canvas:
            showCanvasOptions()
        case .adjust:
            showAdjustOptions()
        }
    }

    // MARK: - Crop

    private func showCropOptions() {
        let label = NSTextField(wrappingLabelWithString: "이미지 위에서 드래그하여 자르기 영역을 선택하세요.\n\nEnter: 적용  /  ESC: 취소")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        toolOptionsContent.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: toolOptionsContent.topAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: toolOptionsContent.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: toolOptionsContent.trailingAnchor, constant: -16),
            label.bottomAnchor.constraint(lessThanOrEqualTo: toolOptionsContent.bottomAnchor, constant: -8),
        ])
    }

    /// 이미지가 스크롤뷰 내에서 실제 표시되는 영역 (중앙 배치·magnification 반영)
    private func computeImageRect() -> CGRect {
        let target: NSView = cropOverlay ?? imageScrollView
        let imgBounds = NSRect(origin: .zero, size: imageView.frame.size)
        return imageView.convert(imgBounds, to: target)
    }

    private func addCropOverlay() {
        removeCropOverlay()

        let overlay = CropOverlayView(frame: imageScrollView.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.imageSize = editedImage.size
        overlay.imageRect = computeImageRect()

        overlay.onCropConfirmed = { [weak self] cropRect in
            self?.applyCrop(cropRect)
        }
        overlay.onCropCancelled = { [weak self] in
            self?.selectTool(.none)
        }

        imageScrollView.addSubview(overlay)
        overlay.resetSelection()
        window?.makeFirstResponder(overlay)
        cropOverlay = overlay

        imageScrollView.allowsMagnification = false
    }

    private func removeCropOverlay() {
        cropOverlay?.removeFromSuperview()
        cropOverlay = nil
        imageScrollView.allowsMagnification = true
    }

    private func applyCrop(_ cropRect: CGRect) {
        guard let cropped = editingService.cropImage(editedImage, to: cropRect) else { return }
        applyEdit(cropped)
        removeCropOverlay()
        selectTool(.none)
    }

    // MARK: - Resize Options

    private func showResizeOptions() {
        resizeAspectRatio = editedImage.size.width / editedImage.size.height

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        toolOptionsContent.addSubview(stack)

        let wRow = makeFieldRow(label: "너비:", field: resizeWidthField, unit: "px")
        resizeWidthField.integerValue = Int(editedImage.size.width)
        resizeWidthField.delegate = self
        stack.addArrangedSubview(wRow)

        let hRow = makeFieldRow(label: "높이:", field: resizeHeightField, unit: "px")
        resizeHeightField.integerValue = Int(editedImage.size.height)
        resizeHeightField.delegate = self
        stack.addArrangedSubview(hRow)

        resizeLockAspect.state = .on
        resizeLockAspect.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(resizeLockAspect)

        let applyBtn = NSButton(title: "크기 적용", target: self, action: #selector(applyResize))
        applyBtn.translatesAutoresizingMaskIntoConstraints = false
        applyBtn.bezelStyle = .rounded
        stack.addArrangedSubview(applyBtn)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: toolOptionsContent.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: toolOptionsContent.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: toolOptionsContent.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: toolOptionsContent.bottomAnchor, constant: -8),
        ])
    }

    @objc private func applyResize() {
        let w = max(1, resizeWidthField.integerValue)
        let h = max(1, resizeHeightField.integerValue)
        guard let resized = editingService.resizeImage(editedImage, to: CGSize(width: w, height: h)) else { return }
        applyEdit(resized)
        selectTool(.none)
    }

    // MARK: - Canvas Options

    private func showCanvasOptions() {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        toolOptionsContent.addSubview(stack)

        // 모드
        canvasModeSegment.selectedSegment = 0
        canvasModeSegment.translatesAutoresizingMaskIntoConstraints = false
        canvasModeSegment.target = self
        canvasModeSegment.action = #selector(canvasModeChanged)
        stack.addArrangedSubview(canvasModeSegment)

        // 너비/높이
        let wRow = makeFieldRow(label: "너비:", field: canvasWidthField, unit: "px")
        canvasWidthField.integerValue = 0
        canvasWidthField.delegate = self
        configureNumberField(canvasWidthField, min: -99999)
        stack.addArrangedSubview(wRow)

        let hRow = makeFieldRow(label: "높이:", field: canvasHeightField, unit: "px")
        canvasHeightField.integerValue = 0
        canvasHeightField.delegate = self
        configureNumberField(canvasHeightField, min: -99999)
        stack.addArrangedSubview(hRow)

        // 정렬
        let alignRow = NSStackView()
        alignRow.translatesAutoresizingMaskIntoConstraints = false
        let alignLabel = NSTextField(labelWithString: "정렬:")
        alignLabel.translatesAutoresizingMaskIntoConstraints = false
        canvasAlignPopup.removeAllItems()
        canvasAlignPopup.translatesAutoresizingMaskIntoConstraints = false
        for a in CanvasAlignment.allCases {
            canvasAlignPopup.addItem(withTitle: a.displayName)
        }
        canvasAlignPopup.selectItem(at: CanvasAlignment.center.rawValue)
        alignRow.addArrangedSubview(alignLabel)
        alignRow.addArrangedSubview(canvasAlignPopup)
        stack.addArrangedSubview(alignRow)

        // 배경색
        let colorRow = NSStackView()
        colorRow.translatesAutoresizingMaskIntoConstraints = false
        let colorLabel = NSTextField(labelWithString: "배경:")
        colorLabel.translatesAutoresizingMaskIntoConstraints = false
        canvasColorWell.translatesAutoresizingMaskIntoConstraints = false
        canvasColorWell.color = .white
        if #available(macOS 13.0, *) {
            canvasColorWell.colorWellStyle = .minimal
        }
        canvasTransparentCheck.translatesAutoresizingMaskIntoConstraints = false
        canvasTransparentCheck.state = .off
        canvasTransparentCheck.target = self
        canvasTransparentCheck.action = #selector(canvasTransparentChanged)
        colorRow.addArrangedSubview(colorLabel)
        colorRow.addArrangedSubview(canvasColorWell)
        colorRow.addArrangedSubview(canvasTransparentCheck)
        NSLayoutConstraint.activate([
            canvasColorWell.widthAnchor.constraint(equalToConstant: 36),
            canvasColorWell.heightAnchor.constraint(equalToConstant: 22),
        ])
        stack.addArrangedSubview(colorRow)

        // 결과 미리보기
        canvasPreviewLabel.translatesAutoresizingMaskIntoConstraints = false
        canvasPreviewLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        canvasPreviewLabel.textColor = .controlAccentColor
        updateCanvasPreview()
        stack.addArrangedSubview(canvasPreviewLabel)

        // 적용
        let applyBtn = NSButton(title: "캔버스 적용", target: self, action: #selector(applyCanvas))
        applyBtn.translatesAutoresizingMaskIntoConstraints = false
        applyBtn.bezelStyle = .rounded
        stack.addArrangedSubview(applyBtn)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: toolOptionsContent.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: toolOptionsContent.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: toolOptionsContent.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: toolOptionsContent.bottomAnchor, constant: -8),
        ])
    }

    @objc private func canvasModeChanged() {
        if canvasModeSegment.selectedSegment == 0 {
            canvasWidthField.integerValue = 0
            canvasHeightField.integerValue = 0
            configureNumberField(canvasWidthField, min: -99999)
            configureNumberField(canvasHeightField, min: -99999)
        } else {
            canvasWidthField.integerValue = Int(editedImage.size.width)
            canvasHeightField.integerValue = Int(editedImage.size.height)
            configureNumberField(canvasWidthField, min: 1)
            configureNumberField(canvasHeightField, min: 1)
        }
        updateCanvasPreview()
    }

    private func canvasResultSize() -> CGSize {
        if canvasModeSegment.selectedSegment == 0 {
            return CGSize(
                width: max(1, editedImage.size.width + CGFloat(canvasWidthField.integerValue)),
                height: max(1, editedImage.size.height + CGFloat(canvasHeightField.integerValue))
            )
        } else {
            return CGSize(
                width: max(1, CGFloat(canvasWidthField.integerValue)),
                height: max(1, CGFloat(canvasHeightField.integerValue))
            )
        }
    }

    private func updateCanvasPreview() {
        let size = canvasResultSize()
        canvasPreviewLabel.stringValue = "결과: \(Int(size.width)) × \(Int(size.height)) px"
    }

    @objc private func canvasTransparentChanged() {
        canvasColorWell.isEnabled = canvasTransparentCheck.state == .off
    }

    @objc private func applyCanvas() {
        let resultSize = canvasResultSize()
        let alignment = CanvasAlignment(rawValue: canvasAlignPopup.indexOfSelectedItem) ?? .center

        if resultSize.width < editedImage.size.width || resultSize.height < editedImage.size.height {
            let alert = NSAlert()
            alert.messageText = "캔버스가 현재 이미지보다 작습니다"
            alert.informativeText = "이미지의 일부가 잘릴 수 있습니다. 계속하시겠습니까?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "계속")
            alert.addButton(withTitle: "취소")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        let fillColor = canvasTransparentCheck.state == .on ? NSColor.clear : canvasColorWell.color
        guard let resized = editingService.resizeCanvas(editedImage, to: resultSize, fillColor: fillColor, alignment: alignment) else { return }
        applyEdit(resized)
        selectTool(.none)
    }

    // MARK: - Adjust Options

    private func showAdjustOptions() {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        toolOptionsContent.addSubview(stack)

        func makeSliderRow(label: String, slider: NSSlider, valueLabel: NSTextField,
                           min: Double, max: Double, value: Double) -> NSView {
            let titleLabel = NSTextField(labelWithString: label)
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.font = .systemFont(ofSize: 11)

            slider.translatesAutoresizingMaskIntoConstraints = false
            slider.minValue = min
            slider.maxValue = max
            slider.doubleValue = value
            slider.controlSize = .small
            slider.isContinuous = true
            slider.target = self
            slider.action = #selector(adjustSliderChanged(_:))

            valueLabel.translatesAutoresizingMaskIntoConstraints = false
            valueLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            valueLabel.textColor = .secondaryLabelColor
            valueLabel.alignment = .right

            let row = NSStackView(views: [titleLabel, slider, valueLabel])
            row.translatesAutoresizingMaskIntoConstraints = false
            row.spacing = 6
            NSLayoutConstraint.activate([
                titleLabel.widthAnchor.constraint(equalToConstant: 55),
                valueLabel.widthAnchor.constraint(equalToConstant: 38),
            ])
            return row
        }

        stack.addArrangedSubview(makeSliderRow(
            label: "밝기", slider: brightnessSlider, valueLabel: brightnessLabel,
            min: -0.5, max: 0.5, value: 0))
        stack.addArrangedSubview(makeSliderRow(
            label: "대비", slider: contrastSlider, valueLabel: contrastLabel,
            min: 0.5, max: 2.0, value: 1.0))
        stack.addArrangedSubview(makeSliderRow(
            label: "채도", slider: saturationSlider, valueLabel: saturationLabel,
            min: 0.0, max: 2.0, value: 1.0))
        stack.addArrangedSubview(makeSliderRow(
            label: "하이라이트", slider: highlightsSlider, valueLabel: highlightsLabel,
            min: -1.0, max: 1.0, value: 0))
        stack.addArrangedSubview(makeSliderRow(
            label: "섀도우", slider: shadowsSlider, valueLabel: shadowsLabel,
            min: -1.0, max: 1.0, value: 0))

        let buttonStack = NSStackView()
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.spacing = 8

        let resetBtn = NSButton(title: "초기화", target: self, action: #selector(resetAdjust))
        resetBtn.translatesAutoresizingMaskIntoConstraints = false
        resetBtn.bezelStyle = .rounded

        let applyBtn = NSButton(title: "적용", target: self, action: #selector(applyAdjust))
        applyBtn.translatesAutoresizingMaskIntoConstraints = false
        applyBtn.bezelStyle = .rounded

        buttonStack.addArrangedSubview(resetBtn)
        buttonStack.addArrangedSubview(applyBtn)
        stack.addArrangedSubview(buttonStack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: toolOptionsContent.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: toolOptionsContent.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: toolOptionsContent.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: toolOptionsContent.bottomAnchor, constant: -8),
        ])
    }

    @objc private func adjustSliderChanged(_ sender: NSSlider) {
        brightnessLabel.stringValue = String(format: "%.2f", brightnessSlider.doubleValue)
        contrastLabel.stringValue = String(format: "%.2f", contrastSlider.doubleValue)
        saturationLabel.stringValue = String(format: "%.2f", saturationSlider.doubleValue)
        highlightsLabel.stringValue = String(format: "%.2f", highlightsSlider.doubleValue)
        shadowsLabel.stringValue = String(format: "%.2f", shadowsSlider.doubleValue)

        // 실시간 미리보기
        guard let preview = editingService.adjustImage(
            editedImage,
            brightness: Float(brightnessSlider.doubleValue),
            contrast: Float(contrastSlider.doubleValue),
            saturation: Float(saturationSlider.doubleValue),
            highlights: Float(highlightsSlider.doubleValue),
            shadows: Float(shadowsSlider.doubleValue)
        ) else { return }
        imageView.image = preview
        imageView.frame = NSRect(origin: .zero, size: preview.size)
    }

    @objc private func resetAdjust() {
        brightnessSlider.doubleValue = 0
        contrastSlider.doubleValue = 1.0
        saturationSlider.doubleValue = 1.0
        highlightsSlider.doubleValue = 0
        shadowsSlider.doubleValue = 0
        brightnessLabel.stringValue = "0.00"
        contrastLabel.stringValue = "1.00"
        saturationLabel.stringValue = "1.00"
        highlightsLabel.stringValue = "0.00"
        shadowsLabel.stringValue = "0.00"
        // 원본으로 복원
        displayImage(editedImage)
    }

    @objc private func applyAdjust() {
        guard let adjusted = editingService.adjustImage(
            editedImage,
            brightness: Float(brightnessSlider.doubleValue),
            contrast: Float(contrastSlider.doubleValue),
            saturation: Float(saturationSlider.doubleValue),
            highlights: Float(highlightsSlider.doubleValue),
            shadows: Float(shadowsSlider.doubleValue)
        ) else { return }
        applyEdit(adjusted)
        selectTool(.none)
    }

    // MARK: - Undo / Redo

    private func pushUndo() {
        undoStack.append(editedImage)
        if undoStack.count > maxHistory {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        updateUndoRedoButtons()
    }

    /// 편집 적용 공통: undo 저장 → 이미지 교체 → 표시 갱신
    private func applyEdit(_ newImage: NSImage) {
        pushUndo()
        editedImage = newImage
        displayImage(newImage)
        updateSizeLabel()
    }

    @objc private func undoTapped() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(editedImage)
        editedImage = prev
        displayImage(prev)
        updateSizeLabel()
        updateUndoRedoButtons()
    }

    @objc private func redoTapped() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(editedImage)
        editedImage = next
        displayImage(next)
        updateSizeLabel()
        updateUndoRedoButtons()
    }

    private func updateUndoRedoButtons() {
        undoButton.isEnabled = !undoStack.isEmpty
        redoButton.isEnabled = !redoStack.isEmpty
    }

    // MARK: - Flip & Rotate

    @objc private func editorFlipH() {
        applyEdit(editingService.flipHorizontal(editedImage))
    }

    @objc private func editorFlipV() {
        applyEdit(editingService.flipVertical(editedImage))
    }

    @objc private func editorRotateLeft() {
        applyEdit(editingService.rotate(editedImage, degrees: 90))
    }

    @objc private func editorRotateRight() {
        applyEdit(editingService.rotate(editedImage, degrees: -90))
    }

    // MARK: - Save / Cancel

    @objc private func saveTapped() {
        let panel = NSSavePanel()
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let ext = originalURL.pathExtension
        panel.nameFieldStringValue = "\(baseName)_edited.\(ext)"

        let accessory = ExportAccessoryView()
        if let currentFormat = ImageFormat.from(extension: ext) {
            accessory.selectedFormat = currentFormat
        }
        panel.accessoryView = accessory

        guard panel.runModal() == .OK, let saveURL = panel.url else { return }

        let format = accessory.selectedFormat
        let quality = accessory.quality
        let result = imageService.exportImage(editedImage, to: saveURL, format: format, quality: quality)

        if case .failure(let error) = result {
            let alert = NSAlert(error: error as NSError)
            alert.runModal()
        } else {
            // 저장 성공 — 저장된 폴더 갱신 요청
            let savedFolder = saveURL.deletingLastPathComponent()
            onSaved?(savedFolder)
            close()
        }
    }

    @objc private func cancelTapped() {
        close()
    }

    // MARK: - Helpers

    private func makeFieldRow(label: String, field: NSTextField, unit: String) -> NSStackView {
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.spacing = 6

        let lbl = NSTextField(labelWithString: label)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 12)

        field.translatesAutoresizingMaskIntoConstraints = false
        configureNumberField(field, min: 1)

        let unitLbl = NSTextField(labelWithString: unit)
        unitLbl.translatesAutoresizingMaskIntoConstraints = false
        unitLbl.font = .systemFont(ofSize: 12)

        row.addArrangedSubview(lbl)
        row.addArrangedSubview(field)
        row.addArrangedSubview(unitLbl)

        NSLayoutConstraint.activate([
            lbl.widthAnchor.constraint(equalToConstant: 40),
            field.widthAnchor.constraint(equalToConstant: 70),
        ])

        return row
    }

    private func configureNumberField(_ field: NSTextField, min: Int) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = min as NSNumber
        formatter.maximum = 99999
        field.formatter = formatter
    }
}

// MARK: - NSWindowDelegate

extension ImageEditorWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        onComplete?()
    }

    func windowDidResize(_ notification: Notification) {
        // frameDidChangeNotification에서 처리
    }
}

// MARK: - NSTextFieldDelegate

extension ImageEditorWindowController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }

        if activeTool == .resize && resizeLockAspect.state == .on && !isResizeUpdating {
            isResizeUpdating = true
            if field === resizeWidthField {
                let w = max(1, resizeWidthField.integerValue)
                resizeHeightField.integerValue = max(1, Int(round(CGFloat(w) / resizeAspectRatio)))
            } else if field === resizeHeightField {
                let h = max(1, resizeHeightField.integerValue)
                resizeWidthField.integerValue = max(1, Int(round(CGFloat(h) * resizeAspectRatio)))
            }
            isResizeUpdating = false
        }

        if activeTool == .canvas {
            updateCanvasPreview()
        }
    }
}
