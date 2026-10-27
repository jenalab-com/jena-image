import AppKit

final class AIImageWindowController: NSWindowController, NSWindowDelegate {
    var selectedImages: (() -> [URL])?
    var onSaved: (([URL]) -> Void)?
    private(set) var referenceURLs: [URL] = []
    private(set) var destinationURL: URL?
    private var job: AIImageGenerationService?
    private var savedURLs: [URL] = []
    private let provider = NSPopUpButton()
    private let executable = NSTextField(string: "codex")
    private let prompt = NSTextView()
    private let references = NSTextField(wrappingLabelWithString: "참조 없음 — 설명만으로 생성합니다.")
    private let folder = NSTextField(wrappingLabelWithString: "저장 폴더를 선택하세요.")
    private let status = NSTextField(wrappingLabelWithString: "생성 버튼을 누르면 설명과 참조 이미지가 연결된 AI로 전달됩니다.")
    private let preview = NSImageView()
    private let progress = NSProgressIndicator()
    private var editableButtons: [NSButton] = []
    private var generateButton: NSButton!
    private var cancelButton: NSButton!
    private var revealButton: NSButton!

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "AI 이미지 생성"
        window.minSize = NSSize(width: 600, height: 600)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        setupContent()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(references: [URL], destination: URL?) {
        guard job == nil else { return }
        referenceURLs = references
        if destinationURL == nil { destinationURL = destination }
        updateLabels()
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }

    private func setupContent() {
        guard let content = window?.contentView else { return }
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        let document = AIImageFormView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document
        document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor).isActive = true
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20)
        ])
        func add(_ view: NSView, fullWidth: Bool = true) {
            stack.addArrangedSubview(view)
            if fullWidth { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        }
        add(NSTextField(labelWithString: "연결"))
        provider.addItems(withTitles: AIImageProvider.allCases.map(\.rawValue))
        provider.target = self
        provider.action = #selector(changeProvider)
        add(provider)
        add(NSTextField(labelWithString: "CLI 실행 파일 (이름 또는 절대 경로)"))
        executable.setAccessibilityLabel("CLI 실행 파일")
        add(executable)
        let guidance = NSTextField(wrappingLabelWithString: "Codex: 로그인과 이미지 생성 도구 설정이 필요합니다. 사용자 지정 CLI: request.json 경로를 인자로 받아 output 폴더에 PNG를 저장하는 실행 파일을 연결하세요.")
        guidance.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        guidance.textColor = .secondaryLabelColor
        add(guidance)
        add(NSTextField(labelWithString: "참조 이미지"))
        references.maximumNumberOfLines = 3
        add(references)
        let importButton = button("목록 선택 가져오기", #selector(importSelection))
        let clearButton = button("참조 비우기", #selector(clearReferences))
        add(NSStackView(views: [importButton, clearButton]), fullWidth: false)
        add(NSTextField(labelWithString: "이미지 설명"))
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        prompt.isRichText = false
        prompt.font = .systemFont(ofSize: NSFont.systemFontSize)
        prompt.isVerticallyResizable = true
        prompt.autoresizingMask = [.width]
        prompt.textContainer?.widthTracksTextView = true
        prompt.textContainerInset = NSSize(width: 6, height: 6)
        prompt.setAccessibilityLabel("생성할 이미지 설명")
        scroll.documentView = prompt
        scroll.heightAnchor.constraint(equalToConstant: 110).isActive = true
        add(scroll)
        add(NSTextField(labelWithString: "저장 위치"))
        folder.maximumNumberOfLines = 2
        add(folder)
        let chooseButton = button("저장 폴더 선택…", #selector(chooseFolder))
        add(chooseButton, fullWidth: false)
        generateButton = button("이미지 생성", #selector(generate))
        cancelButton = button("생성 취소", #selector(cancelGeneration))
        cancelButton.isEnabled = false
        revealButton = button("결과 보기", #selector(revealResults))
        revealButton.isEnabled = false
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        add(NSStackView(views: [generateButton, cancelButton, revealButton, progress]), fullWidth: false)
        status.maximumNumberOfLines = 5
        status.setAccessibilityLabel("생성 상태")
        add(status)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.heightAnchor.constraint(equalToConstant: 110).isActive = true
        add(preview)
        editableButtons = [importButton, clearButton, chooseButton]
    }

    private func updateLabels() {
        references.stringValue = referenceURLs.isEmpty ? "참조 없음 — 설명만으로 생성합니다." : "\(referenceURLs.count)장: " + referenceURLs.map(\.lastPathComponent).joined(separator: ", ")
        references.toolTip = referenceURLs.map(\.path).joined(separator: "\n")
        folder.stringValue = destinationURL?.path ?? "저장 폴더를 선택하세요."
        folder.toolTip = destinationURL?.path
    }

    @objc private func changeProvider() {
        executable.stringValue = provider.indexOfSelectedItem == 0 ? "codex" : ""
        executable.placeholderString = "/절대/경로/이미지-생성-cli"
    }

    @objc private func importSelection() {
        referenceURLs = selectedImages?() ?? []
        updateLabels()
    }

    @objc private func clearReferences() {
        referenceURLs = []
        updateLabels()
    }

    @objc private func chooseFolder() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = destinationURL
        panel.prompt = "저장 폴더 선택"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.destinationURL = panel.url
            self?.updateLabels()
        }
    }

    @objc private func generate() {
        guard job == nil else { return }
        guard let destinationURL else { status.stringValue = "저장 폴더를 선택하세요."; return }
        guard !prompt.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status.stringValue = "생성할 이미지의 설명을 입력하세요."
            return
        }
        let request = AIImageRequest(provider: AIImageProvider.allCases[provider.indexOfSelectedItem],
                                     executable: executable.stringValue, prompt: prompt.string,
                                     references: referenceURLs, destination: destinationURL)
        let service = AIImageGenerationService()
        job = service
        setRunning(true)
        status.stringValue = "이미지 생성 중… 완료된 이미지를 선택한 폴더에 저장합니다."
        Task { @MainActor [self] in
            do {
                let urls = try await service.generate(request)
                savedURLs = urls
                preview.image = urls.first.flatMap { NSImage(contentsOf: $0) }
                status.stringValue = "\(urls.count)개 이미지 저장 완료: \(destinationURL.path)"
                onSaved?(urls)
            } catch {
                status.stringValue = error.localizedDescription
            }
            status.toolTip = status.stringValue
            job = nil
            setRunning(false)
        }
    }

    private func setRunning(_ running: Bool) {
        generateButton.isEnabled = !running
        cancelButton.isEnabled = running
        provider.isEnabled = !running
        executable.isEnabled = !running
        prompt.isEditable = !running
        editableButtons.forEach { $0.isEnabled = !running }
        revealButton.isEnabled = !running && !savedURLs.isEmpty
        if running { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
    }

    @objc private func cancelGeneration() {
        job?.cancel()
        cancelButton.isEnabled = false
        status.stringValue = "취소 요청 중… CLI가 종료될 때까지 기다립니다."
    }

    @objc private func revealResults() {
        NSWorkspace.shared.activateFileViewerSelecting(savedURLs)
    }

    @objc func copyFiles(_ sender: Any?) {
        (window?.firstResponder as? NSTextView)?.copy(sender)
    }

    @objc func pasteFiles(_ sender: Any?) {
        (window?.firstResponder as? NSTextView)?.pasteAsPlainText(sender)
    }

    @objc func selectAllItems(_ sender: Any?) {
        (window?.firstResponder as? NSTextView)?.selectAll(sender)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if job != nil {
            status.stringValue = "생성 중입니다. 완료를 기다리거나 ‘생성 취소’를 눌러주세요."
            return false
        }
        return true
    }
}

private final class AIImageFormView: NSView {
    override var isFlipped: Bool { true }
}
