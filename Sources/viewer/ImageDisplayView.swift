import AppKit

/// 확대/축소/패닝 가능한 이미지 뷰
final class ImageDisplayView: NSView {
    var onDoubleClick: (() -> Void)?

    private let scrollView = NSScrollView()
    private let clipView = CenteringClipView()
    private let imageView = NSImageView()

    private var isFitMode = true
    private var frameObserver: NSObjectProtocol?

    private static let minMagnification: CGFloat = 0.1
    private static let maxMagnification: CGFloat = 5.0

    var currentMagnification: CGFloat {
        scrollView.magnification
    }

    /// 현재 표시 중인 이미지 (flip 적용 전 원본)
    var currentImage: NSImage? {
        originalImage
    }

    /// 이미지가 화면에 표시되는 영역 (오버레이 좌표 계산용)
    var imageDisplayRect: CGRect {
        let mag = scrollView.magnification
        let imgFrame = imageView.frame
        let clipBounds = clipView.bounds
        let visibleOrigin = CGPoint(
            x: (imgFrame.origin.x - clipBounds.origin.x) * mag,
            y: (imgFrame.origin.y - clipBounds.origin.y) * mag
        )
        return CGRect(
            origin: CGPoint(x: max(0, visibleOrigin.x), y: max(0, visibleOrigin.y)),
            size: CGSize(width: imgFrame.width * mag, height: imgFrame.height * mag)
        )
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
        observeFrameChanges()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let observer = frameObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private var isFlippedHorizontally = false
    private var isFlippedVertically = false
    private var originalImage: NSImage?

    // MARK: - Public

    func display(_ image: NSImage) {
        originalImage = image
        imageView.image = image
        imageView.frame = NSRect(origin: .zero, size: image.size)
        isFlippedHorizontally = false
        isFlippedVertically = false
        isFitMode = true
        fitToView()
    }

    func displayError() {
        imageView.image = NSImage(
            systemSymbolName: "exclamationmark.triangle",
            accessibilityDescription: "이미지를 표시할 수 없습니다"
        )
        imageView.frame = NSRect(origin: .zero, size: NSSize(width: 64, height: 64))
        scrollView.magnification = 1.0
    }

    func zoomIn() {
        isFitMode = false
        let newMag = min(scrollView.magnification * 1.25, Self.maxMagnification)
        scrollView.animator().magnification = newMag
    }

    func zoomOut() {
        isFitMode = false
        let newMag = max(scrollView.magnification / 1.25, Self.minMagnification)
        scrollView.animator().magnification = newMag
    }

    func zoomToActualSize() {
        isFitMode = false
        scrollView.animator().magnification = 1.0
    }

    func fitToView() {
        isFitMode = true
        guard let image = imageView.image else { return }
        let viewSize = scrollView.contentSize
        let imageSize = image.size

        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let scaleX = viewSize.width / imageSize.width
        let scaleY = viewSize.height / imageSize.height
        let scale = min(scaleX, scaleY, 1.0)

        scrollView.magnification = scale
    }

    // MARK: - Flip

    func flipHorizontal() {
        isFlippedHorizontally.toggle()
        applyFlippedImage()
    }

    func flipVertical() {
        isFlippedVertically.toggle()
        applyFlippedImage()
    }

    func resetFlip() {
        isFlippedHorizontally = false
        isFlippedVertically = false
        applyFlippedImage()
    }

    private func applyFlippedImage() {
        guard let original = originalImage else { return }

        if !isFlippedHorizontally && !isFlippedVertically {
            imageView.image = original
            return
        }

        let size = original.size
        let flipped = NSImage(size: size)
        flipped.lockFocus()

        let transform = NSAffineTransform()
        transform.translateX(by: isFlippedHorizontally ? size.width : 0,
                             yBy: isFlippedVertically ? size.height : 0)
        transform.scaleX(by: isFlippedHorizontally ? -1 : 1,
                         yBy: isFlippedVertically ? -1 : 1)
        transform.concat()

        original.draw(in: NSRect(origin: .zero, size: size),
                      from: .zero, operation: .sourceOver, fraction: 1.0)
        flipped.unlockFocus()

        imageView.image = flipped
    }

    // MARK: - Frame Change Observer

    private func observeFrameChanges() {
        scrollView.postsBoundsChangedNotifications = true
        scrollView.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isFitMode else { return }
            self.fitToView()
        }
    }

    // MARK: - Crop Overlay

    private var cropOverlay: CropOverlayView?

    func showCropOverlay(onConfirm: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        guard let image = originalImage else { return }
        removeCropOverlay()

        let overlay = CropOverlayView(frame: scrollView.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.imageSize = image.size
        overlay.imageRect = imageDisplayRect
        overlay.onCropConfirmed = { [weak self] rect in
            self?.removeCropOverlay()
            onConfirm(rect)
        }
        overlay.onCropCancelled = { [weak self] in
            self?.removeCropOverlay()
            onCancel()
        }
        scrollView.addSubview(overlay)
        overlay.resetSelection()
        overlay.window?.makeFirstResponder(overlay)
        cropOverlay = overlay

        // 줌/스크롤 비활성화
        scrollView.allowsMagnification = false
    }

    func removeCropOverlay() {
        cropOverlay?.removeFromSuperview()
        cropOverlay = nil
        scrollView.allowsMagnification = true
    }

    var isCropping: Bool {
        cropOverlay != nil
    }

    // MARK: - Double Click

    override func mouseDown(with event: NSEvent) {
        guard cropOverlay == nil else { return }
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            onDoubleClick?()
        }
    }

    // MARK: - Setup

    private func setupViews() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = Self.minMagnification
        scrollView.maxMagnification = Self.maxMagnification
        scrollView.backgroundColor = .controlBackgroundColor
        scrollView.scrollerStyle = .overlay

        // CenteringClipView로 교체하여 이미지를 항상 중앙에 배치
        clipView.documentView = imageView
        scrollView.contentView = clipView
        addSubview(scrollView)

        imageView.imageScaling = .scaleNone
        imageView.setAccessibilityRole(.image)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
}

// MARK: - Centering Clip View

/// document가 clip view보다 작을 때 자동으로 중앙 정렬하는 NSClipView 서브클래스
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView = documentView else { return rect }

        let docFrame = documentView.frame

        // 가로 중앙
        if docFrame.width < rect.width {
            rect.origin.x = (docFrame.width - rect.width) / 2
        }

        // 세로 중앙
        if docFrame.height < rect.height {
            rect.origin.y = (docFrame.height - rect.height) / 2
        }

        return rect
    }
}
