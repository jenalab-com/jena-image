import AppKit

/// 사이드바와 목록 사이의 웹 패널. 머리줄(뒤로·앞으로·새로고침/중지·주소창·옵션·닫기), 탭 줄, 고른 탭의 페이지, 맨 아래 상태 줄.
/// 머리줄과 상태 줄은 고른 탭을 따른다.
final class WebPanelViewController: NSViewController {
    static let defaultWidth: CGFloat = 480
    static let minimumWidth: CGFloat = 360
    static let maximumWidth: CGFloat = 1000
    static let statusDuration: TimeInterval = 6

    let engine: WebPageEngine
    let addressField = NSTextField()
    let statusLabel = NSTextField(labelWithString: "")
    let tabStrip = WebTabStripView()
    private(set) var backButton: NSButton!
    private(set) var forwardButton: NSButton!
    private(set) var reloadButton: NSButton!
    private(set) var optionsButton: NSButton!
    private(set) var closeButton: NSButton!
    var onClose: (() -> Void)?

    private let settings: AppSettings
    private let emptyLabel = NSTextField(labelWithString: "검색어나 주소를 입력하세요")
    private let statusRow = NSStackView()
    private var message: String?
    private var messageGeneration = 0
    private var didLoadInitialPage = false
    /// 주소창이 마지막으로 보여 준 탭. 바뀌면 입력 중이던 글자를 버리고 그 탭의 주소를 보인다.
    private var shownTabID: Int?

    init(engine: WebPageEngine, settings: AppSettings = .shared) {
        self.engine = engine
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = WebPanelView()
        backButton = iconButton("chevron.left", label: "뒤로", action: #selector(goBack))
        forwardButton = iconButton("chevron.right", label: "앞으로", action: #selector(goForward))
        reloadButton = iconButton("arrow.clockwise", label: "새로고침", action: #selector(reloadOrStop))
        optionsButton = iconButton("ellipsis", label: "웹 옵션", action: #selector(showOptions))
        closeButton = iconButton("xmark", label: "웹 패널 닫기", action: #selector(closePanel))

        addressField.placeholderString = "검색어 또는 주소"
        addressField.font = .systemFont(ofSize: 12)
        addressField.bezelStyle = .roundedBezel
        addressField.lineBreakMode = .byTruncatingTail
        addressField.usesSingleLineMode = true
        addressField.cell?.sendsActionOnEndEditing = false
        addressField.target = self
        addressField.action = #selector(addressEntered)
        addressField.setAccessibilityLabel("검색어 또는 주소")
        addressField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addressField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [backButton, forwardButton, reloadButton, addressField, optionsButton, closeButton])
        header.alignment = .centerY
        header.spacing = 4
        header.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)

        tabStrip.heightAnchor.constraint(equalToConstant: WebTabStripView.height).isActive = true
        tabStrip.onSelect = { [weak self] id in self?.engine.selectTab(id) }
        tabStrip.onClose = { [weak self] id in self?.engine.closeTab(id) }
        tabStrip.onNewTab = { [weak self] in self?.newTab() }

        let separator = NSBox()
        separator.boxType = .separator

        let page = NSView()
        let container = engine.containerView
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        for subview in [container, emptyLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            page.addSubview(subview)
        }

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusRow.setViews([statusLabel], in: .leading)
        statusRow.isHidden = true
        statusRow.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 6, right: 10)

        let stack = NSStackView(views: [header, tabStrip, separator, page, statusRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.setCustomSpacing(4, after: header)
        stack.setCustomSpacing(4, after: tabStrip)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.topAnchor.constraint(equalTo: page.topAnchor),
            container.bottomAnchor.constraint(equalTo: page.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: page.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: page.centerYAnchor),
        ])
        for row in [header, tabStrip, separator, page, statusRow] {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        engine.onStateChange = { [weak self] in self?.engineStateChanged() }
        engine.onNotice = { [weak self] text in self?.showStatus(text) }
        engine.onTabsChange = { [weak self] in self?.tabsChanged() }
        engineStateChanged()
        tabsChanged()
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

    // MARK: 주소

    func submitAddress() {
        do {
            let url = try WebAddressResolver.resolve(addressField.stringValue, provider: settings.webSearchProvider,
                                                     mode: settings.webSearchMode)
            addressField.stringValue = url.absoluteString
            // 입력을 마쳐야 이후 페이지 주소가 주소창에 반영된다.
            if addressField.currentEditor() != nil { view.window?.makeFirstResponder(engine.webView) }
            engine.load(url)
        } catch {
            showStatus(error.localizedDescription)
        }
    }

    func focusAddress() {
        guard let window = view.window else { return }
        window.makeFirstResponder(addressField)
        addressField.currentEditor()?.selectAll(nil)
    }

    /// 지난번 탭들을 한 번만 복원한다(고른 탭만 바로 불러온다). 탭 기록이 없고 예전 버전의 마지막 주소가 있으면
    /// 그 주소를 탭 하나로 옮긴다. 복원 자체는 설정을 쓰지 않고(옮긴 경우만 바로 쓴다), 그 뒤의 탭 변화부터 저장한다.
    func loadInitialPage() {
        guard !didLoadInitialPage else { return }
        var addresses = settings.webTabAddresses
        var index = settings.webSelectedTabIndex
        let legacy = settings.takeLegacyWebLastAddress()
        let migrating = addresses.isEmpty && legacy != nil
        if migrating, let legacy {
            addresses = [legacy]
            index = 0
        }
        engine.restoreTabs(addresses: addresses, selectedIndex: index)
        didLoadInitialPage = true
        // 예전 값은 이미 지웠으므로 옮긴 주소는 바로 남긴다.
        if migrating { saveTabs() }
    }

    /// 빈 탭을 열어 고르고 주소창에 포커스를 둔다. 탭이 너무 많으면 엔진이 거절하고 알린다.
    func newTab() {
        guard engine.openTab(url: nil, select: true) != nil else { return }
        focusAddress()
    }

    @objc private func addressEntered() { submitAddress() }
    @objc private func goBack() { engine.goBack() }
    @objc private func goForward() { engine.goForward() }
    @objc private func reloadOrStop() { engine.reloadOrStop() }
    @objc private func closePanel() { onClose?() }

    private func engineStateChanged() {
        guard isViewLoaded else { return }
        backButton.isEnabled = engine.canGoBack
        forwardButton.isEnabled = engine.canGoForward
        let loading = engine.isLoading
        let label = loading ? "중지" : "새로고침"
        reloadButton.image = NSImage(systemSymbolName: loading ? "xmark" : "arrow.clockwise", accessibilityDescription: label)
        reloadButton.toolTip = label
        reloadButton.setAccessibilityLabel(label)
        let url = engine.currentURL
        emptyLabel.isHidden = url != nil
        if engine.selectedTabID != shownTabID {
            // 탭 전환은 편집을 끝낸다. 입력 중이던 글자는 버리고 그 탭의 주소를 보인다.
            shownTabID = engine.selectedTabID
            if addressField.currentEditor() != nil { addressField.abortEditing() }
            addressField.stringValue = engine.tabs.first { $0.id == shownTabID }?.address ?? ""
        } else if let url, addressField.currentEditor() == nil {
            addressField.stringValue = url.absoluteString
        }
        refreshStatus()
    }

    /// 탭 줄을 맞추고, 복원한 뒤라면 열어 둔 탭 주소와 고른 탭 번호를 저장한다.
    private func tabsChanged() {
        guard isViewLoaded else { return }
        tabStrip.update(tabs: engine.tabs, selectedID: engine.selectedTabID)
        saveTabs()
    }

    private func saveTabs() {
        guard didLoadInitialPage else { return }
        let addresses = engine.tabAddresses
        let index = engine.selectedTabIndex
        if settings.webTabAddresses != addresses { settings.webTabAddresses = addresses }
        if settings.webSelectedTabIndex != index { settings.webSelectedTabIndex = index }
    }

    // MARK: 상태 줄

    /// 한 줄 알림. 6초 뒤 지운다. 알림이 없을 때 불러오는 중이면 "불러오는 중…".
    func showStatus(_ text: String) {
        message = text.isEmpty ? nil : text
        messageGeneration += 1
        let generation = messageGeneration
        if message != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.statusDuration) { [weak self] in
                guard let self, self.messageGeneration == generation else { return }
                self.message = nil
                self.refreshStatus()
            }
        }
        refreshStatus()
    }

    private func refreshStatus() {
        let text = message ?? (engine.isLoading ? "불러오는 중…" : "")
        statusLabel.stringValue = text
        statusLabel.toolTip = text.isEmpty ? nil : text
        statusRow.isHidden = text.isEmpty
    }

    // MARK: 옵션

    /// 검색엔진 셋과 검색 종류 둘. 지금 고른 것에 체크.
    func optionsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(.sectionHeader(title: "검색엔진"))
        for provider in WebSearchProvider.allCases {
            let item = NSMenuItem(title: provider.displayName, action: #selector(selectProvider(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = provider.rawValue
            item.state = settings.webSearchProvider == provider ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "검색 종류"))
        for mode in WebSearchMode.allCases {
            let item = NSMenuItem(title: mode == .web ? "웹" : "이미지", action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settings.webSearchMode == mode ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func showOptions() {
        optionsMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: optionsButton.bounds.height + 4), in: optionsButton)
    }

    @objc private func selectProvider(_ sender: NSMenuItem) {
        guard let provider = (sender.representedObject as? String).flatMap(WebSearchProvider.init(rawValue:)) else { return }
        settings.webSearchProvider = provider
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let mode = (sender.representedObject as? String).flatMap(WebSearchMode.init(rawValue:)) else { return }
        settings.webSearchMode = mode
    }
}

/// 패널 바탕. AI 패널과 같은 창 바탕색.
private final class WebPanelView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }
}
