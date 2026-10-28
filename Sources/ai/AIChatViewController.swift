import AppKit

final class AIChatViewController: NSViewController {
    static let defaultWidth: CGFloat = 300
    static let minimumWidth: CGFloat = 280
    static let maximumWidth: CGFloat = 600
    var currentDestination: (() -> URL?)?
    var onSaved: (([URL]) -> Void)?
    var onOpenImages: (([URL]) -> Void)?
    var onClose: (() -> Void)?
    var generateImages: (AIImageRequest, AIImageGenerationService) async throws -> [URL] = { request, service in
        try await service.generate(request)
    }
    var loadModels: (String) async throws -> [AIModelOption] = { path in
        try await AIConnectionService().models(path: path)
    }
    var loadUsage: (String) async throws -> [AIUsageWindow] = { path in
        try await AIConnectionService().usage(path: path)
    }
    let usageLabel = NSTextField(wrappingLabelWithString: "사용 현황 확인 중…")
    private(set) var usageRefreshButton: NSButton!
    private var usageTimer: Timer?
    private var usageWindows: [AIUsageWindow] = []
    private var loadingUsage = false

    private(set) var modelButton: NSButton!
    private(set) var modelOptions: [AIModelOption] = []
    private var loadingModels = false
    private let settings: AppSettings
    private let transcript = AIChatTranscriptView()
    let input = AIChatInputView()
    let composer = AIChatComposerView()
    private let inputScroll = NSScrollView()
    private var inputHeight: NSLayoutConstraint!
    private var optionsButton: NSButton!
    let statusLabel = NSTextField(wrappingLabelWithString: "")
    let attachments = NSStackView()
    private let attachmentScroll = NSScrollView()
    private let progress = NSProgressIndicator()
    var canSend: Bool { !isRunning && currentDestination?() != nil }
    private(set) var cancelButton: NSButton!
    private(set) var referenceURLs: [URL] = []
    private(set) var messages: [AIChatMessage] = []
    private var lastSelection = Set<URL>()
    private var job: AIImageGenerationService?
    var isRunning: Bool { job != nil }

    init(settings: AppSettings = .shared) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { job?.cancel(); usageTimer?.invalidate() }

    override func loadView() {
        view = AIChatPanelView()
        transcript.onOpenImages = { [weak self] urls in self?.onOpenImages?(urls) }
        let title = NSTextField(labelWithString: "AI 이미지")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        let close = iconButton("xmark", label: "AI 사이드바 닫기", action: #selector(closePanel))
        let top = NSStackView(views: [title, NSView(), close])
        top.spacing = 8

        attachments.orientation = .horizontal
        attachments.alignment = .top
        attachments.spacing = 8
        attachmentScroll.documentView = attachments
        attachmentScroll.hasHorizontalScroller = true
        attachmentScroll.autohidesScrollers = true
        attachmentScroll.drawsBackground = false
        attachmentScroll.contentView.drawsBackground = false
        attachmentScroll.heightAnchor.constraint(equalToConstant: 84).isActive = true
        attachmentScroll.isHidden = true

        input.isRichText = false
        input.drawsBackground = false
        input.font = .systemFont(ofSize: 13)
        input.isVerticallyResizable = true
        input.autoresizingMask = [.width]
        input.textContainer?.widthTracksTextView = true
        input.textContainerInset = NSSize(width: 0, height: 7)
        input.allowsUndo = true
        input.setAccessibilityLabel("이미지 생성 요청")
        input.setAccessibilityHelp("Enter로 전송하고 Shift+Enter로 줄바꿈합니다.")
        input.toolTip = "Enter 전송 · Shift+Enter 줄바꿈"
        input.onSubmit = { [weak self] in self?.send() }
        input.onTextChange = { [weak self] in self?.updateInputHeight() }
        inputScroll.documentView = input
        inputScroll.hasVerticalScroller = true
        inputScroll.autohidesScrollers = true
        inputScroll.drawsBackground = false
        inputScroll.contentView.drawsBackground = false
        inputScroll.borderType = .noBorder
        inputHeight = inputScroll.heightAnchor.constraint(equalToConstant: 32)
        inputHeight.isActive = true
        inputScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true

        optionsButton = iconButton("ellipsis", label: "AI 옵션", action: #selector(showOptions))
        cancelButton = iconButton("stop.fill", label: "생성 중지", action: #selector(cancelGeneration))
        cancelButton.isEnabled = false
        cancelButton.isHidden = true
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        progress.isHidden = true
        progress.widthAnchor.constraint(equalToConstant: 16).isActive = true
        progress.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let loadingLabel = NSTextField(labelWithString: "이미지를 만들고 있어요..")
        loadingLabel.font = .systemFont(ofSize: 13)
        loadingLabel.textColor = .secondaryLabelColor
        let loadingRow = NSStackView(views: [progress, loadingLabel, NSView()])
        loadingRow.spacing = 8
        loadingRow.alignment = .centerY
        loadingRow.isHidden = true
        transcript.setLoadingView(loadingRow)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2
        statusLabel.isHidden = true

        modelButton = NSButton(title: modelTitle, target: self, action: #selector(showModels))
        modelButton.isBordered = false
        modelButton.font = .systemFont(ofSize: 11)
        modelButton.contentTintColor = .secondaryLabelColor
        modelButton.setAccessibilityLabel("Codex 모델 선택")
        modelButton.toolTip = "요청을 처리할 Codex 모델 선택"
        modelButton.cell?.lineBreakMode = .byTruncatingTail
        modelButton.widthAnchor.constraint(lessThanOrEqualToConstant: 140).isActive = true
        let inputRow = NSStackView(views: [NSView(), modelButton, cancelButton, optionsButton])
        inputRow.alignment = .centerY
        inputRow.spacing = 6
        let composerStack = NSStackView(views: [inputScroll, inputRow, statusLabel])
        composerStack.orientation = .vertical
        composerStack.alignment = .leading
        composerStack.spacing = 4
        composerStack.translatesAutoresizingMaskIntoConstraints = false
        composer.addSubview(composerStack)
        NSLayoutConstraint.activate([
            composerStack.topAnchor.constraint(equalTo: composer.topAnchor, constant: 8),
            composerStack.bottomAnchor.constraint(equalTo: composer.bottomAnchor, constant: -8),
            composerStack.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 10),
            composerStack.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -10),
            inputScroll.widthAnchor.constraint(equalTo: composerStack.widthAnchor),
            inputRow.widthAnchor.constraint(equalTo: composerStack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: composerStack.widthAnchor)
        ])
        usageLabel.font = .systemFont(ofSize: 10)
        usageLabel.textColor = .secondaryLabelColor
        usageLabel.setAccessibilityLabel("AI 사용 현황과 리셋까지 남은 시간")
        usageRefreshButton = iconButton("arrow.clockwise", label: "사용 현황 재조회", action: #selector(reloadUsage))
        let usageRow = NSStackView(views: [usageLabel, usageRefreshButton])
        usageRow.alignment = .centerY
        usageRow.spacing = 6
        usageLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [top, transcript, attachmentScroll, composer, usageRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            transcript.heightAnchor.constraint(greaterThanOrEqualToConstant: 60)
        ])
        for row in [top, transcript, attachmentScroll, composer, usageRow] {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        messages = [.init(role: "status", text: "어떤 이미지를 만들어 볼까요?")]
        transcript.setMessages(messages)
        refreshDestination()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        usageTimer?.invalidate()
        Task { @MainActor [weak self] in await self?.refreshUsage() }
        usageTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshUsage() }
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        usageTimer?.invalidate()
        usageTimer = nil
    }

    @objc private func reloadUsage() {
        Task { @MainActor [weak self] in await self?.refreshUsage() }
    }

    func refreshUsage() async {
        guard !loadingUsage else { return }
        loadingUsage = true
        usageRefreshButton?.isEnabled = false
        usageRefreshButton?.toolTip = "사용 현황 조회 중…"
        defer {
            loadingUsage = false
            usageRefreshButton?.isEnabled = true
            usageRefreshButton?.toolTip = "사용 현황 재조회"
        }
        let path = settings.aiExecutable
        if !usageWindows.isEmpty { renderUsage() }
        do {
            let windows = try await loadUsage(path)
            guard path == settings.aiExecutable else { return }
            usageWindows = windows
            renderUsage()
        } catch {
            usageWindows = []
            usageLabel.stringValue = "사용 현황을 확인할 수 없어요"
            usageLabel.toolTip = "CLI 연결을 확인해 주세요. 1분마다 다시 확인합니다."
        }
    }

    private func renderUsage() {
        usageLabel.stringValue = usageWindows.isEmpty ? "사용 현황 정보 없음"
            : usageWindows.map { $0.summary() }.joined(separator: "\n")
        usageLabel.toolTip = "CLI 계정의 사용 비율과 다음 리셋까지 남은 시간 · 1분마다 갱신"
    }

    private func iconButton(_ symbol: String, label: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!,
                              target: self, action: action)
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateInputHeight()
    }

    private func updateInputHeight() {
        guard inputHeight != nil, let container = input.textContainer, let manager = input.layoutManager else { return }
        manager.ensureLayout(for: container)
        let height = min(128, max(32, ceil(manager.usedRect(for: container).height + input.textContainerInset.height * 2)))
        if abs(inputHeight.constant - height) > 0.5 { inputHeight.constant = height }
    }

    private func showStatus(_ message: String) {
        statusLabel.stringValue = message
        statusLabel.isHidden = message.isEmpty
    }

    func refreshDestination() {
        guard isViewLoaded else { return }
        let destination = currentDestination?()
        optionsButton.toolTip = destination.map { "AI 옵션 · 자동 저장: " + $0.lastPathComponent } ?? "AI 옵션 · 저장 폴더를 선택하세요"
        if !isRunning {
            if destination == nil { showStatus("저장할 폴더를 왼쪽에서 선택하세요.") }
            else if statusLabel.stringValue == "저장할 폴더를 왼쪽에서 선택하세요." { showStatus("") }
        }
    }

    @objc private func showOptions() {
        let menu = NSMenu()
        let folder = NSMenuItem(title: (currentDestination?()).map { "자동 저장 · " + $0.lastPathComponent } ?? "저장 폴더를 선택하세요",
                                action: nil, keyEquivalent: "")
        menu.addItem(folder)
        let settings = NSMenuItem(title: "AI 연결 설정…", action: #selector(showSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: optionsButton.bounds.height), in: optionsButton)
    }

    private var modelTitle: String {
        let title = modelOptions.first { $0.id == settings.aiModel }?.title
            ?? (settings.aiModel.isEmpty ? "기본 모델" : settings.aiModel)
        return title + " ▾"
    }

    func selectModel(_ id: String) {
        settings.aiModel = id
        modelButton.title = modelTitle
    }

    @objc private func chooseModel(_ sender: NSMenuItem) {
        guard !isRunning, let id = sender.representedObject as? String else { return }
        selectModel(id)
    }

    /// Refresh on each opening so account or CLI changes cannot leave a stale catalog.
    func refreshModels() async -> Bool {
        guard !loadingModels else { return false }
        loadingModels = true
        modelButton.isEnabled = false
        modelButton.title = "모델 불러오는 중…"
        defer {
            loadingModels = false
            modelButton.isEnabled = !isRunning
            modelButton.title = modelTitle
        }
        do {
            modelOptions = try await loadModels(settings.aiExecutable)
            if statusLabel.stringValue.hasPrefix("모델 목록을 가져오지 못했어요.") { showStatus("") }
            return true
        } catch {
            modelOptions = []
            showStatus("모델 목록을 가져오지 못했어요. 모델 버튼을 눌러 재시도하거나 연결 설정을 확인해 주세요.")
            return false
        }
    }

    @objc private func showModels() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let loaded = await self.refreshModels()
            guard !self.isRunning, self.view.window?.isVisible == true else { return }
            let menu = NSMenu()
            let options = [AIModelOption(id: "", title: "기본 모델 · CLI 설정 사용")] + self.modelOptions
            for option in options {
                let item = NSMenuItem(title: option.title, action: #selector(self.chooseModel(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = option.id
                item.state = self.settings.aiModel == option.id ? .on : .off
                menu.addItem(item)
            }
            if !loaded || self.modelOptions.isEmpty {
                menu.addItem(.separator())
                menu.addItem(NSMenuItem(title: loaded ? "선택 가능한 이미지 입력 모델이 없어요" : "목록 조회 실패 · 다시 눌러 재시도", action: nil, keyEquivalent: ""))
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: self.modelButton.bounds.height), in: self.modelButton)
        }
    }

    func addReferences(_ urls: [URL]) {
        for url in urls where ImageFile(url: url)?.isImage == true && !referenceURLs.contains(url) {
            referenceURLs.append(url)
        }
        renderAttachments()
    }

    /// 선택 변화의 새 항목만 추가한다. 첨부 제거 후 같은 선택의 재통지로 되살아나지 않는다.
    func selectionChanged(_ urls: [URL]) {
        _ = view
        let images = urls.filter { ImageFile(url: $0)?.isImage == true }
        let incoming = Set(images)
        let additions = images.filter { !lastSelection.contains($0) }
        lastSelection = incoming
        addReferences(additions)
    }

    func removeReference(_ url: URL) {
        referenceURLs.removeAll { $0 == url }
        renderAttachments()
    }

    private func renderAttachments() {
        for view in attachments.arrangedSubviews { attachments.removeArrangedSubview(view); view.removeFromSuperview() }
        for url in referenceURLs {
            let tile = AIReferenceTile(url: url) { [weak self] in self?.removeReference(url) }
            attachments.addArrangedSubview(tile)
        }
        attachments.frame = NSRect(x: 0, y: 0, width: CGFloat(referenceURLs.count) * 80, height: 76)
        attachmentScroll.isHidden = referenceURLs.isEmpty
    }

    @objc func send() {
        guard job == nil else { return }
        let prompt = input.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { showStatus("이미지 설명을 입력해 주세요."); return }
        guard let destination = currentDestination?() else { refreshDestination(); return }
        guard AIExecutableLocator.resolve(settings.aiExecutable) != nil else {
            showStatus("설정에서 CLI를 설치하고 연결해 주세요.")
            return
        }
        let references = referenceURLs
        let history = messages.filter { $0.role == "user" || $0.role == "assistant" }
            .suffix(12).map { "\($0.role): \($0.text)" }.joined(separator: "\n")
        var request = AIImageRequest(provider: .codex, executable: settings.aiExecutable,
                                     prompt: prompt, references: references, destination: destination)
        request.history = history
        request.model = settings.aiModel
        let service = AIImageGenerationService()
        job = service
        messages.append(.init(role: "user", text: prompt, images: references))
        transcript.setMessages(messages)
        input.string = ""
        referenceURLs = []
        renderAttachments()
        showStatus("")
        setRunning(true)
        let generate = generateImages
        Task { @MainActor [weak self] in
            do {
                let urls = try await generate(request, service)
                guard let self else { return }
                let filenames = urls.map(\.lastPathComponent).joined(separator: "\n")
                self.messages.append(.init(role: "assistant", text: "\(urls.count)개 이미지를 저장했어요.\n\(filenames)", images: urls))
                self.showStatus("")
                for url in urls where !self.referenceURLs.contains(url) { self.referenceURLs.append(url) }
                self.renderAttachments()
                self.onSaved?(urls)
            } catch {
                guard let self else { return }
                self.messages.append(.init(role: "status", text: error.localizedDescription))
                self.showStatus("완료하지 못했어요. 대화의 오류를 확인해 주세요.")
                if self.input.string.isEmpty { self.input.string = prompt }
                for url in references where !self.referenceURLs.contains(url) { self.referenceURLs.append(url) }
                self.renderAttachments()
            }
            guard let self else { return }
            self.job = nil
            self.setRunning(false)
            self.transcript.setMessages(self.messages)
            await self.refreshUsage()
        }
    }

    private func setRunning(_ running: Bool) {
        input.isEditable = !running
        modelButton.isEnabled = !running && !loadingModels
        cancelButton.isEnabled = running
        cancelButton.isHidden = !running
        transcript.setLoading(running)
        progress.isHidden = !running
        if running { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        refreshDestination()
    }

    @objc func cancelGeneration() {
        job?.cancel()
        cancelButton.isEnabled = false
        showStatus("생성을 중지하고 있어요…")
    }
    @objc private func showSettings() { PreferencesWindowController.shared.showAI() }
    @objc private func closePanel() { onClose?() }
}

private final class AIReferenceTile: NSView {
    private let remove: () -> Void
    init(url: URL, remove: @escaping () -> Void) {
        self.remove = remove
        super.init(frame: NSRect(x: 0, y: 0, width: 72, height: 76))
        let image = NSImageView(frame: NSRect(x: 0, y: 18, width: 64, height: 54))
        image.image = AIImageThumbnail.load(url)
        image.imageScaling = .scaleProportionallyUpOrDown
        image.setAccessibilityLabel(url.lastPathComponent)
        let name = NSTextField(labelWithString: url.lastPathComponent)
        name.frame = NSRect(x: 0, y: 0, width: 72, height: 16)
        name.font = .systemFont(ofSize: 10)
        name.lineBreakMode = .byTruncatingMiddle
        let button = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "첨부 제거: " + url.lastPathComponent)!,
                              target: self, action: #selector(removeImage))
        button.frame = NSRect(x: 50, y: 54, width: 22, height: 22)
        button.isBordered = false
        button.setAccessibilityLabel("첨부 제거: " + url.lastPathComponent)
        toolTip = url.path
        addSubview(image); addSubview(name); addSubview(button)
        widthAnchor.constraint(equalToConstant: 72).isActive = true
        heightAnchor.constraint(equalToConstant: 76).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func removeImage() { remove() }
}


private final class AIChatPanelView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }
}
