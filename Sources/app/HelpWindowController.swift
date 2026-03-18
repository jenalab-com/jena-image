import AppKit

final class HelpWindowController: NSWindowController {

    static let shared = HelpWindowController()

    private var textView: NSTextView!

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "JenaImage 도움말"
        window.center()
        window.minSize = NSSize(width: 480, height: 400)

        super.init(window: window)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 32, height: 24)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        window.contentView = scrollView

        textView.textStorage?.setAttributedString(buildHelp())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Content

    private func buildHelp() -> NSAttributedString {
        let result = NSMutableAttributedString()

        result.append(h1("JenaImage 도움말"))
        result.append(body("JenaImage는 macOS용 이미지·영상 뷰어입니다. 폴더를 등록하고, 파일을 탐색·확대·내보내기할 수 있습니다."))
        result.append(spacer())

        // 시작하기
        result.append(h2("시작하기"))
        result.append(item("폴더 추가", detail: "사이드바 하단의 + 버튼, 툴바의 폴더 추가 버튼, 또는 ⌘O로 폴더를 사이드바에 등록합니다."))
        result.append(item("폴더 제거", detail: "사이드바에서 등록된 폴더를 우클릭하여 '사이드바에서 제거'를 선택합니다."))
        result.append(item("폴더 탐색", detail: "사이드바에서 폴더를 클릭하면 우측 브라우저에 내용이 표시됩니다. 다시 클릭하면 펼침/접기가 토글됩니다."))
        result.append(item("미디어 개수", detail: "사이드바 폴더 이름 우측에 해당 폴더 안의 이미지·영상 파일 수가 표시됩니다."))
        result.append(spacer())

        // 브라우저
        result.append(h2("브라우저"))
        result.append(item("썸네일 크기", detail: "하단 상태바의 슬라이더로 썸네일 크기를 조절합니다."))
        result.append(item("이미지/영상 열기", detail: "파일을 더블클릭하면 뷰어 모드로 전환됩니다. 영상 파일은 재생 배지가 표시됩니다."))
        result.append(item("폴더 열기", detail: "폴더를 더블클릭하면 해당 폴더로 이동합니다."))
        result.append(item("모두 선택", detail: "⌘A로 현재 폴더의 모든 항목을 선택합니다."))
        result.append(spacer())

        // 뷰어
        result.append(h2("뷰어"))
        result.append(shortcut("확대", key: "⌘+"))
        result.append(shortcut("축소", key: "⌘-"))
        result.append(shortcut("원본 크기", key: "⌘0"))
        result.append(shortcut("화면에 맞춤", key: "⌘9"))
        result.append(item("뒤로가기", detail: "툴바의 뒤로 버튼, ⌘[ 또는 ESC 키로 브라우저로 돌아갑니다."))
        result.append(item("이미지 이동", detail: "우측 썸네일 패널에서 다른 파일을 선택하거나 상하 방향키를 사용합니다. 뷰어 진입 시 키보드 포커스가 자동으로 이동합니다."))
        result.append(item("사이드바 동기화", detail: "뷰어에서 파일을 탐색하면 좌측 사이드바에도 해당 파일이 자동으로 포커스됩니다."))
        result.append(item("뒤집기", detail: "하단 상태바에서 좌우/상하 뒤집기, 원래대로 되돌리기를 사용할 수 있습니다. (이미지 전용)"))
        result.append(item("영상 재생", detail: "영상 파일을 열면 자동으로 재생됩니다. 더블클릭하면 브라우저로 돌아갑니다."))
        result.append(spacer())

        // 사이드바 컨텍스트 메뉴
        result.append(h2("사이드바 우클릭 메뉴"))
        result.append(item("Finder에서 보기", detail: "선택한 파일 또는 폴더를 Finder에서 열어 위치를 확인합니다."))
        result.append(item("이름 변경", detail: "폴더 또는 파일 이름을 인라인으로 변경합니다. 루트 폴더는 변경 불가."))
        result.append(item("다른 이름으로 저장", detail: "이미지 파일을 다른 포맷으로 변환하여 저장합니다. (이미지 파일 전용)"))
        result.append(item("사이드바에서 제거", detail: "등록된 루트 폴더를 사이드바 목록에서 제거합니다."))
        result.append(item("삭제", detail: "파일 또는 하위 폴더를 휴지통으로 이동합니다."))
        result.append(spacer())

        // 파일 관리
        result.append(h2("파일 관리"))
        result.append(shortcut("다른 이름으로 저장", key: "⇧⌘S"))
        result.append(shortcut("삭제", key: "⌫"))
        result.append(shortcut("Finder에서 보기", key: "⌘R"))
        result.append(item("이름 변경", detail: "사이드바 또는 브라우저에서 파일을 선택 후 다시 클릭하거나, 우클릭 메뉴 또는 파일 메뉴에서 '이름 변경'을 선택합니다."))
        result.append(item("이동/복사", detail: "우클릭 후 이동 또는 복사를 선택하거나, 파일 메뉴에서 접근합니다."))
        result.append(item("드래그 앤 드롭", detail: "브라우저나 사이드바에서 이미지를 폴더로 드래그하여 이동할 수 있습니다."))
        result.append(spacer())

        // 편집
        result.append(h2("편집"))
        result.append(shortcut("복사 (클립보드)", key: "⌘C"))
        result.append(shortcut("모두 선택", key: "⌘A"))
        result.append(spacer())

        // 내보내기
        result.append(h2("이미지 내보내기"))
        result.append(body("다른 이름으로 저장(⇧⌘S) 시 포맷을 변환하여 내보낼 수 있습니다."))
        result.append(body("지원 포맷: JPEG, PNG, WebP, HEIC, HEIF, AVIF, TIFF, BMP, GIF"))
        result.append(spacer())

        // 지원 파일 형식
        result.append(h2("지원 파일 형식"))
        result.append(body("이미지: JPEG, PNG, WebP, HEIC, HEIF, AVIF, TIFF, BMP, GIF"))
        result.append(body("영상: MP4, MOV, M4V, AVI, MKV"))
        result.append(spacer())

        // 단축키 요약
        result.append(h2("단축키 요약"))
        result.append(shortcut("폴더 추가", key: "⌘O"))
        result.append(shortcut("다른 이름으로 저장", key: "⇧⌘S"))
        result.append(shortcut("삭제", key: "⌫"))
        result.append(shortcut("Finder에서 보기", key: "⌘R"))
        result.append(shortcut("복사 (클립보드)", key: "⌘C"))
        result.append(shortcut("모두 선택", key: "⌘A"))
        result.append(shortcut("사이드바 토글", key: "⌥⌘S"))
        result.append(shortcut("뒤로", key: "⌘["))
        result.append(shortcut("이전 파일", key: "↑"))
        result.append(shortcut("다음 파일", key: "↓"))
        result.append(shortcut("확대", key: "⌘+"))
        result.append(shortcut("축소", key: "⌘-"))
        result.append(shortcut("원본 크기", key: "⌘0"))
        result.append(shortcut("화면에 맞춤", key: "⌘9"))
        result.append(shortcut("전체 화면", key: "⌃⌘F"))
        result.append(spacer())

        return result
    }

    // MARK: - Style Helpers

    private func h1(_ text: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = 6
        return NSAttributedString(string: text + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: para,
        ])
    }

    private func h2(_ text: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.paragraphSpacingBefore = 8
        para.paragraphSpacing = 4
        return NSAttributedString(string: text + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: para,
        ])
    }

    private func body(_ text: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = 2
        para.lineSpacing = 3
        return NSAttributedString(string: text + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: para,
        ])
    }

    private func item(_ title: String, detail: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let para = NSMutableParagraphStyle()
        para.headIndent = 16
        para.firstLineHeadIndent = 0
        para.paragraphSpacing = 3
        para.lineSpacing = 2
        result.append(NSAttributedString(string: "• ", attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: para,
        ]))
        result.append(NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: para,
        ]))
        result.append(NSAttributedString(string: " — " + detail + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: para,
        ]))
        return result
    }

    private func shortcut(_ label: String, key: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let para = NSMutableParagraphStyle()
        para.headIndent = 120
        para.firstLineHeadIndent = 16
        para.tabStops = [NSTextTab(type: .leftTabStopType, location: 120)]
        para.paragraphSpacing = 3

        result.append(NSAttributedString(string: "  " + label + "\t", attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: para,
        ]))
        result.append(NSAttributedString(string: key + "\n", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: para,
        ]))
        return result
    }

    private func spacer(height: CGFloat = 12) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.minimumLineHeight = height
        para.maximumLineHeight = height
        return NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 1),
            .paragraphStyle: para,
        ])
    }
}
