import AppKit
import ImageIO

struct AIChatMessage: Equatable {
    let role: String
    let text: String
    var images: [URL] = []
}

enum AIImageThumbnail {
    static func load(_ url: URL, pixels: Int = 144) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }
}

/// Rows own their wrapping width instead of imposing a text intrinsic width on the split pane.
final class AIChatTranscriptView: NSScrollView {
    var onOpenImages: (([URL]) -> Void)?
    private let canvas = AIChatCanvas()
    private(set) var messageViews: [AIChatMessageView] = []
    private(set) var loadingView: NSView?
    private var lastLayoutWidth: CGFloat = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hasVerticalScroller = true
        autohidesScrollers = true
        hasHorizontalScroller = false
        borderType = .noBorder
        drawsBackground = false
        contentView.drawsBackground = false
        documentView = canvas
        setAccessibilityLabel("AI 대화")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setLoadingView(_ view: NSView) {
        loadingView?.removeFromSuperview()
        loadingView = view
        canvas.addSubview(view)
    }

    func setLoading(_ loading: Bool) {
        loadingView?.isHidden = !loading
        arrangeMessages()
        if loading { scrollToBottom() }
    }

    func setMessages(_ messages: [AIChatMessage]) {
        var retained = 0
        while retained < min(messages.count, messageViews.count),
              messages[retained].role == messageViews[retained].message.role,
              messages[retained] == messageViews[retained].message {
            retained += 1
        }
        for row in messageViews.dropFirst(retained) { row.removeFromSuperview() }
        messageViews.removeSubrange(retained...)
        for message in messages.dropFirst(retained) {
            let row = AIChatMessageView(message: message)
            row.onOpenImages = { [weak self] urls in self?.onOpenImages?(urls) }
            messageViews.append(row)
            canvas.addSubview(row)
        }
        arrangeMessages()
        scrollToBottom()
    }

    override func layout() {
        super.layout()
        guard abs(lastLayoutWidth - contentSize.width) > 0.5 else { return }
        let wasAtBottom = contentView.bounds.maxY >= canvas.bounds.height - 24
        arrangeMessages()
        if wasAtBottom { scrollToBottom() }
    }

    private func arrangeMessages() {
        let width = max(1, contentSize.width)
        lastLayoutWidth = width
        var y: CGFloat = 12
        for row in messageViews {
            let height = row.arrange(width: max(1, width - 16))
            row.frame = NSRect(x: 8, y: y, width: max(1, width - 16), height: height)
            y += height + 20
        }
        if let loadingView = loadingView, !loadingView.isHidden {
            loadingView.frame = NSRect(x: 8, y: y, width: max(1, width - 16), height: 20)
            y += 32
        }
        canvas.setFrameSize(NSSize(width: width, height: max(contentSize.height, y)))
    }

    private func scrollToBottom() {
        contentView.scroll(to: NSPoint(x: 0, y: max(0, canvas.bounds.height - contentSize.height)))
        reflectScrolledClipView(contentView)
    }
}

private final class AIChatCanvas: NSView {
    override var isFlipped: Bool { true }
}

final class AIChatMessageView: NSView {
    var onOpenImages: (([URL]) -> Void)?
    let message: AIChatMessage
    let textView = NSTextView()
    private var images: [NSImageView] = []
    private var revealButton: NSButton?
    private(set) var bubbleFrame = NSRect.zero
    var hasBubble: Bool { message.role == "user" }
    override var isFlipped: Bool { true }

    init(message: AIChatMessage) {
        self.message = message
        super.init(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = message.role == "assistant"
        textView.drawsBackground = false
        textView.allowsUndo = false
        textView.font = .systemFont(ofSize: message.role == "status" ? 11 : 13)
        textView.textColor = message.role == "status" ? .secondaryLabelColor : .labelColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.string = message.text
        let speaker = hasBubble ? "나" : message.role == "assistant" ? "AI" : "상태"
        textView.setAccessibilityLabel(speaker)
        addSubview(textView)
        for url in message.images {
            let image = NSImageView()
            image.image = AIImageThumbnail.load(url, pixels: 320)
            image.imageScaling = .scaleProportionallyUpOrDown
            image.toolTip = url.lastPathComponent
            image.setAccessibilityLabel(url.lastPathComponent)
            images.append(image)
            addSubview(image)
        }
        if message.role == "assistant" && !message.images.isEmpty {
            let button = NSButton(title: "저장된 이미지 보기", target: self, action: #selector(reveal))
            revealButton = button
            addSubview(button)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func reveal() { onOpenImages?(message.images) }

    @discardableResult
    func arrange(width: CGFloat) -> CGFloat {
        let horizontalPadding: CGFloat = hasBubble ? 14 : 0
        let verticalPadding: CGFloat = hasBubble ? 10 : 0
        let naturalWidth = hasBubble ? ceil(textView.attributedString().size().width) + horizontalPadding * 2 : width
        let messageWidth = hasBubble ? min(max(64, naturalWidth), width * 0.86) : width
        let textWidth = max(1, messageWidth - horizontalPadding * 2)
        textView.textContainer?.containerSize = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
        if let container = textView.textContainer { textView.layoutManager?.ensureLayout(for: container) }
        let usedHeight = textView.textContainer.flatMap { textView.layoutManager?.usedRect(for: $0).height } ?? 18
        let textHeight = max(18, ceil(usedHeight))
        var height = textHeight + verticalPadding * 2
        for image in images {
            image.frame = NSRect(x: hasBubble ? width - messageWidth : 0, y: height + 8,
                                 width: messageWidth, height: 140)
            height += 148
        }
        if let button = revealButton {
            button.frame = NSRect(x: 0, y: height + 8, width: min(width, 160), height: 28)
            height += 36
        }
        let x = hasBubble ? width - messageWidth : 0
        bubbleFrame = NSRect(x: x, y: 0, width: messageWidth, height: textHeight + verticalPadding * 2)
        textView.frame = NSRect(x: x + horizontalPadding, y: verticalPadding, width: textWidth, height: textHeight)
        needsDisplay = true
        return height
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard hasBubble else { return }
        let path = NSBezierPath(roundedRect: bubbleFrame.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        path.fill()

    }
}
