import AppKit

/// 원본·캐시를 변경하지 않고 썸네일의 투명 영역과 여백에 바탕을 깐다.
/// 설정 "투명 체크무늬"가 켜져 있으면 체크무늬, 꺼져 있으면 흰색(기본). 폴더 셀 등은 `showsCheckerboard = false`로 바탕을 끈다.
final class ThumbnailImageView: NSImageView {
    var showsCheckerboard = true { didSet { needsDisplay = true } }
    private var observer: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        observeSetting()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        observeSetting()
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    private func observeSetting() {
        observer = NotificationCenter.default.addObserver(
            forName: .settingsChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.needsDisplay = true }
    }

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
            Self.drawBackdrop(in: dirtyRect.intersection(bounds))
        }
        super.draw(dirtyRect)
    }

    /// 투명 영역 바탕 — 설정에 따라 체크무늬 또는 흰색.
    static func drawBackdrop(in rect: NSRect) {
        if AppSettings.shared.showsTransparencyCheckerboard {
            checkerboard.setFill()
        } else {
            NSColor.white.setFill()
        }
        rect.fill()
    }
}

final class ThumbnailButton: NSButton {
    private var observer: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        observer = NotificationCenter.default.addObserver(
            forName: .settingsChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.needsDisplay = true }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    override func draw(_ dirtyRect: NSRect) {
        ThumbnailImageView.drawBackdrop(in: dirtyRect.intersection(bounds))
        super.draw(dirtyRect)
    }
}
