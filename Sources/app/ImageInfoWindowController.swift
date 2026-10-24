import AppKit

/// 이미지 정보(⌘I) 패널 — 파일 기본 정보 + 이미지/EXIF 메타데이터를 보여준다.
final class ImageInfoWindowController: NSWindowController {

    private let textView = NSTextView()
    /// 비동기 로드 결과가 늦게 도착해도 최신 요청만 반영하기 위한 토큰.
    private var loadToken = UUID()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "이미지 정보"
        window.center()
        window.minSize = NSSize(width: 360, height: 260)
        window.isReleasedWhenClosed = false

        super.init(window: window)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 22, height: 18)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        window.contentView = scrollView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Public

    func show(for url: URL) {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        reload(for: url)
    }

    /// 패널이 열려 있을 때만 새 파일 정보로 갱신한다.
    func updateIfVisible(for url: URL) {
        guard window?.isVisible == true else { return }
        reload(for: url)
    }

    // MARK: - Content

    private func reload(for url: URL) {
        let token = UUID()
        loadToken = token
        window?.title = url.lastPathComponent
        textView.string = "불러오는 중…"

        // iCloud에서 내려받는 파일이면 헤더 읽기가 느릴 수 있어 백그라운드에서 조회한다.
        Task {
            let metadata = await Task.detached(priority: .userInitiated) {
                ImageMetadataService.load(for: url)
            }.value

            await MainActor.run { [weak self] in
                guard let self, self.loadToken == token else { return }
                self.window?.title = metadata.fileName
                self.textView.textStorage?.setAttributedString(self.buildContent(metadata))
            }
        }
    }

    private func buildContent(_ metadata: ImageMetadata) -> NSAttributedString {
        let result = NSMutableAttributedString()

        result.append(title(metadata.fileName))

        // 일반
        result.append(section("일반"))
        result.append(row("종류", metadata.kind))
        result.append(row("포맷", metadata.format))
        if let size = metadata.fileSize {
            result.append(row("크기", ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))
        } else {
            result.append(row("크기", "알 수 없음"))
        }
        result.append(row("위치", abbreviatedPath(metadata.fileURL.deletingLastPathComponent().path)))
        result.append(row("생성일", formattedDate(metadata.createdAt)))
        result.append(row("수정일", formattedDate(metadata.modifiedAt)))

        // 이미지
        let hasImageSection = metadata.dimension != nil
            || metadata.dpi != nil
            || metadata.colorModel != nil
            || metadata.colorProfile != nil
        if hasImageSection {
            result.append(section("이미지"))
            if let dimension = metadata.dimension {
                result.append(row("해상도", dimension))
            }
            if let dpi = metadata.dpi {
                result.append(row("DPI", dpi))
            }
            if let colorModel = metadata.colorModel {
                result.append(row("색 공간", colorModel))
            }
            if let colorProfile = metadata.colorProfile {
                result.append(row("색 프로파일", colorProfile))
            }
        }

        // 카메라(EXIF)
        if !metadata.exif.isEmpty {
            result.append(section("카메라"))
            for field in metadata.exif {
                result.append(row(field.label, field.value))
            }
        } else if metadata.kind == "이미지" {
            result.append(note("촬영 정보(EXIF)가 없습니다."))
        }

        // 위치(GPS)
        if !metadata.gps.isEmpty {
            result.append(section("위치"))
            for field in metadata.gps {
                result.append(row(field.label, field.value))
            }
        }

        if metadata.kind == "동영상" {
            result.append(note("동영상 파일입니다. 해상도·재생 정보는 뷰어에서 확인하세요."))
        }

        return result
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard !home.isEmpty, path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "알 수 없음" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Style

    private func title(_ text: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = 10
        return NSAttributedString(string: text + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: para,
        ])
    }

    private func section(_ text: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.paragraphSpacingBefore = 12
        para.paragraphSpacing = 4
        return NSAttributedString(string: text + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: para,
        ])
    }

    private func row(_ label: String, _ value: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let valueFont = NSFont.systemFont(ofSize: 12)
        let para = NSMutableParagraphStyle()
        para.headIndent = 96
        para.firstLineHeadIndent = 0
        para.tabStops = [NSTextTab(type: .leftTabStopType, location: 96)]
        para.paragraphSpacing = 4
        para.lineSpacing = 2

        result.append(NSAttributedString(string: label + "\t", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: para,
        ]))
        result.append(NSAttributedString(string: value + "\n", attributes: [
            .font: valueFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: para,
        ]))
        return result
    }

    private func note(_ text: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.paragraphSpacingBefore = 12
        para.paragraphSpacing = 2
        return NSAttributedString(string: text + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: para,
        ])
    }
}
