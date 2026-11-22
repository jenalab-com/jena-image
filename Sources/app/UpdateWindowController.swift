import AppKit

enum UpdateState: Equatable {
    case idle, checking, upToDate, available(AppRelease), downloading(Double), preparing, restarting, failed(String)
}

/// 메뉴 "업데이트 확인…"에서 여는 창. 확인 → 변경 내용 → 내려받기·검증 → 교체 스크립트 실행 → 종료.
/// 네트워크·설치 단계는 주입할 수 있어 테스트에서 실제 다운로드 없이 흐름을 검증한다.
@MainActor
final class UpdateWindowController: NSWindowController, NSWindowDelegate {
    static let shared = UpdateWindowController()
    static let releasesPageURL = URL(string: "https://github.com/jenalab-com/jena-image/releases/latest")!

    let currentVersion: String
    let bundleURL: URL
    let bundleIdentifier: String

    var fetchLatest: () async throws -> AppRelease
    var download: (AppRelease, @escaping @Sendable (Double) -> Void) async throws -> URL
    var stage: (URL, AppRelease) async throws -> URL
    var launchReplacement: (URL) throws -> Void
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var terminate: () -> Void = { NSApp.terminate(nil) }

    private(set) var state: UpdateState = .idle
    private var release: AppRelease?
    private var work: Task<Void, Never>?

    let titleLabel = NSTextField(labelWithString: "")
    let detailLabel = NSTextField(wrappingLabelWithString: "")
    let notesView = NSTextView()
    private let notesScroll = NSScrollView()
    private let progress = NSProgressIndicator()
    let primaryButton = NSButton(title: "", target: nil, action: nil)
    let secondaryButton = NSButton(title: "", target: nil, action: nil)

    init(currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
         bundleURL: URL = Bundle.main.bundleURL,
         bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.jenalab.jenaimage") {
        self.currentVersion = currentVersion
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
        let service = AppUpdateService()
        let installer = AppUpdateInstaller()
        fetchLatest = { try await service.latestRelease() }
        download = { release, progress in try await service.download(release, progress: progress) }
        stage = { dmg, release in
            // hdiutil·ditto는 수 초 걸릴 수 있어 메인 스레드 밖에서 돌린다.
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result {
                        try installer.stage(dmg: dmg, expectedVersion: release.version,
                                            bundleIdentifier: bundleIdentifier, target: bundleURL)
                    })
                }
            }
        }
        launchReplacement = { staged in
            try installer.launchReplacement(staged: staged, target: bundleURL, waitingFor: ProcessInfo.processInfo.processIdentifier)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "업데이트"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func showAndCheck() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        check()
    }

    func windowWillClose(_ notification: Notification) {
        // 창을 닫으면 진행 중인 확인·설치를 멈춘다. 교체 스크립트를 띄운 뒤(재시작 중)에는 되돌릴 수 없다.
        if state != .restarting { work?.cancel(); work = nil; state = .idle }
    }

    // MARK: - 흐름

    private func check() {
        work?.cancel()
        release = nil
        set(.checking)
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let latest = try await fetchLatest()
                guard !Task.isCancelled else { return }
                release = latest
                set(AppVersion.isNewer(latest.version, than: currentVersion) ? .available(latest) : .upToDate)
            } catch {
                guard !Task.isCancelled else { return }
                set(.failed(Self.message(for: error)))
            }
        }
    }

    private func install(_ release: AppRelease) {
        guard AppUpdateInstaller.installability(of: bundleURL) == .ready else {
            openURL(release.pageURL)
            close()
            return
        }
        set(.downloading(0))
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let dmg = try await download(release) { [weak self] fraction in
                    Task { @MainActor in
                        guard let self, case .downloading = self.state else { return }
                        self.set(.downloading(fraction))
                    }
                }
                try Task.checkCancellation()
                set(.preparing)
                let staged = try await stage(dmg, release)
                Self.removeDownloadFolder(of: dmg)
                try Task.checkCancellation()
                try launchReplacement(staged)
                set(.restarting)
                terminate()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                set(.failed(Self.message(for: error)))
            }
        }
    }

    @objc private func primaryClicked() {
        switch state {
        case .available(let release):
            if AppUpdateInstaller.installability(of: bundleURL) == .ready { install(release) }
            else { openURL(release.pageURL); close() }
        case .failed: check()
        default: close()
        }
    }

    @objc private func secondaryClicked() {
        if case .failed = state { openURL(release?.pageURL ?? Self.releasesPageURL) }
        close()
    }

    // MARK: - 화면

    private func set(_ newState: UpdateState) {
        state = newState
        render()
    }

    private func render() {
        let installability = AppUpdateInstaller.installability(of: bundleURL)
        var title = "", detail = "", notes: String?, primary: String?, secondary: String?
        var progressValue: Double?   // nil이면 진행 표시 숨김, -1이면 막대 대신 회전
        switch state {
        case .idle, .checking:
            title = "업데이트를 확인하는 중…"; progressValue = -1; secondary = "취소"
        case .upToDate:
            title = "최신 버전을 사용하고 있어요"; detail = "JenaImage \(currentVersion)"; primary = "확인"
        case .available(let release):
            title = "새 버전 \(release.version)이 나왔어요"
            detail = "지금 버전은 \(currentVersion)이에요."
            if installability != .ready { detail += "\n" + installability.guidance }
            notes = release.notes
            primary = installability == .ready ? "설치" : "다운로드 페이지 열기"
            secondary = "나중에"
        case .downloading(let fraction):
            title = "내려받는 중…"; detail = "\(Int(fraction * 100))%"; progressValue = fraction
        case .preparing:
            title = "설치 파일을 확인하는 중…"; detail = "검증이 끝나면 앱을 닫고 새 버전으로 다시 열어요."; progressValue = -1
        case .restarting:
            title = "새 버전으로 다시 시작합니다…"; progressValue = -1
        case .failed(let message):
            title = "업데이트하지 못했어요"; detail = message; primary = "다시 시도"; secondary = "다운로드 페이지"
        }
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        detailLabel.isHidden = detail.isEmpty
        notesScroll.isHidden = notes == nil
        if let notes { notesView.textStorage?.setAttributedString(Self.render(notes: notes)) }
        progress.isHidden = progressValue == nil
        if let value = progressValue {
            progress.isIndeterminate = value < 0
            if value < 0 { progress.startAnimation(nil) } else { progress.stopAnimation(nil); progress.doubleValue = value }
        }
        primaryButton.isHidden = primary == nil
        primaryButton.title = primary ?? ""
        // 설치는 앱을 종료하므로 실수로 누른 Enter가 시작하지 않게 한다. 되돌릴 수 있는 버튼만 기본 버튼으로 둔다.
        if case .available = state, installability == .ready { primaryButton.keyEquivalent = "" }
        else { primaryButton.keyEquivalent = "\r" }
        secondaryButton.isHidden = secondary == nil
        secondaryButton.title = secondary ?? ""
        fitWindowToContent()
    }

    /// 상태마다 보이는 요소가 달라 창 높이를 내용에 맞춘다. 위쪽 모서리는 그대로 둔다.
    private func fitWindowToContent() {
        guard let window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let height = content.fittingSize.height
        guard height > 0 else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: NSSize(width: 480, height: height)))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true)
    }

    private func buildContent(in window: NSWindow) {
        titleLabel.font = .boldSystemFont(ofSize: 15)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        notesView.isEditable = false
        notesView.drawsBackground = false
        notesView.textContainerInset = NSSize(width: 6, height: 6)
        notesScroll.documentView = notesView
        notesScroll.hasVerticalScroller = true
        notesScroll.borderType = .bezelBorder
        notesView.autoresizingMask = [.width]
        progress.style = .bar
        progress.minValue = 0
        progress.maxValue = 1
        primaryButton.target = self
        primaryButton.action = #selector(primaryClicked)
        primaryButton.bezelStyle = .rounded
        secondaryButton.target = self
        secondaryButton.action = #selector(secondaryClicked)
        secondaryButton.bezelStyle = .rounded
        // macOS 관례대로 버튼은 오른쪽, 기본 동작(primary)이 가장 오른쪽.
        let buttons = NSStackView()
        buttons.setViews([secondaryButton, primaryButton], in: .trailing)
        buttons.spacing = 8
        let stack = NSStackView(views: [titleLabel, detailLabel, notesScroll, progress, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        window.contentView = content
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            notesScroll.heightAnchor.constraint(equalToConstant: 200),
        ])
        for view in [detailLabel, notesScroll, progress, buttons] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        render()
    }

    // MARK: - 도우미

    /// 릴리스 노트(Markdown)를 읽기 쉬운 글로. 제목 기호는 떼고 굵게, 목록은 점으로 보인다.
    static func render(notes: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
        for raw in notes.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            var attributes = body
            if line.hasPrefix("#") {
                line = String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                attributes[.font] = NSFont.boldSystemFont(ofSize: 13)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = "• " + line.dropFirst(2)
            }
            let inline = (try? NSAttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                .map { NSMutableAttributedString(attributedString: $0) } ?? NSMutableAttributedString(string: line)
            inline.addAttributes(attributes, range: NSRange(location: 0, length: inline.length))
            result.append(inline)
            result.append(NSAttributedString(string: "\n", attributes: body))
        }
        return result
    }

    static func message(for error: Error) -> String {
        (error as? AppUpdateError)?.errorDescription
            ?? "업데이트 정보를 받지 못했어요. 네트워크를 확인한 뒤 다시 시도해 주세요."
    }

    /// 내려받기 서비스가 만든 임시 폴더만 지운다(다른 위치의 파일은 건드리지 않는다).
    private static func removeDownloadFolder(of dmg: URL) {
        let folder = dmg.deletingLastPathComponent()
        guard folder.lastPathComponent.hasPrefix("JenaImage-update-"),
              folder.path.hasPrefix(FileManager.default.temporaryDirectory.path) else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}
