import AppKit

/// 원본·캐시를 변경하지 않고 썸네일의 투명 영역과 여백에 체크무늬를 표시한다.
final class ThumbnailImageView: NSImageView {
    var showsCheckerboard = true { didSet { needsDisplay = true } }

    private static let checkerboard: NSColor = {
        let tile = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor(white: 0.82, alpha: 1).setFill()
            rect.fill()
            NSColor(white: 0.66, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 8, height: 8).fill()
            NSRect(x: 8, y: 8, width: 8, height: 8).fill()
            return true
        }
        return NSColor(patternImage: tile)
    }()

    override func draw(_ dirtyRect: NSRect) {
        if showsCheckerboard {
            Self.drawCheckerboard(in: dirtyRect.intersection(bounds))
        }
        super.draw(dirtyRect)
    }

    static func drawCheckerboard(in rect: NSRect) {
        checkerboard.setFill()
        rect.fill()
    }
}

final class ThumbnailButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        ThumbnailImageView.drawCheckerboard(in: dirtyRect.intersection(bounds))
        super.draw(dirtyRect)
    }
}
