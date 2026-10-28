import AppKit

/// 한글 조합을 확정하는 Enter와 요청을 보내는 Enter를 구분한다.
final class AIChatInputView: NSTextView {
    var onSubmit: (() -> Void)?
    var onTextChange: (() -> Void)?
    var placeholder = "이미지를 설명해 주세요" { didSet { needsDisplay = true } }

    override var string: String {
        didSet { needsDisplay = true; onTextChange?() }
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
        onTextChange?()
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        guard isReturn, !hasMarkedText() else {
            super.keyDown(with: event)
            return
        }
        guard isEditable else { return }
        if event.modifierFlags.contains(.shift) {
            insertNewlineIgnoringFieldEditor(nil)
        } else {
            onSubmit?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText() else { return }
        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
                             y: textContainerInset.height)
        (placeholder as NSString).draw(at: origin, withAttributes: [
            .font: font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.placeholderTextColor
        ])
    }
}

/// 입력부만 은은하게 구분하고 대화 영역은 패널 바탕을 그대로 쓴다.
final class AIChatComposerView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 22, yRadius: 22).fill()
    }
}
