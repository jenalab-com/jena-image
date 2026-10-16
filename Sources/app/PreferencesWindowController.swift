import AppKit

/// 설정 윈도우
final class PreferencesWindowController: NSWindowController {

    static let shared = PreferencesWindowController()

    private let settings = AppSettings.shared

    private init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = L10n.string(.preferences).replacingOccurrences(of: "…", with: "")
        win.center()
        win.isReleasedWhenClosed = false

        super.init(window: win)

        setupUI()
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: win, queue: .main
        ) { [weak self] _ in self?.stopDiskUsageRefresh() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startDiskUsageRefresh()
    }

    // MARK: - 디스크 사용량 주기 갱신

    /// 탭 뷰는 한 번 만들어 재사용하므로 "사용 중" 라벨은 창을 열 때와 열려 있는 동안 주기적으로 맞춘다.
    /// (뒤에서 그리드가 스크롤되면 캐시가 계속 쌓인다.)
    private var diskUsageTimer: Timer?

    private func startDiskUsageRefresh() {
        updateDiskLabels()
        diskUsageTimer?.invalidate()
        diskUsageTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.updateDiskLabels()
        }
    }

    private func stopDiskUsageRefresh() {
        diskUsageTimer?.invalidate()
        diskUsageTimer = nil
    }

    // MARK: - UI

    private func setupUI() {
        guard let window else { return }

        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false

        // 일반 탭
        let generalTab = NSTabViewItem(identifier: "general")
        generalTab.label = L10n.string(.general)
        generalTab.view = createGeneralView()
        tabView.addTabViewItem(generalTab)

        // 뷰어 탭
        let viewerTab = NSTabViewItem(identifier: "viewer")
        viewerTab.label = L10n.string(.viewer)
        viewerTab.view = createViewerView()
        tabView.addTabViewItem(viewerTab)

        // 썸네일 탭
        let thumbTab = NSTabViewItem(identifier: "thumbnails")
        thumbTab.label = L10n.string(.thumbnails)
        thumbTab.view = createThumbnailView()
        tabView.addTabViewItem(thumbTab)

        // 내보내기 탭
        let exportTab = NSTabViewItem(identifier: "export")
        exportTab.label = L10n.string(.saveAsFile)
        exportTab.view = createExportView()
        tabView.addTabViewItem(exportTab)

        window.contentView = tabView
    }

    // MARK: - General Tab

    private func createGeneralView() -> NSView {
        let container = NSView()

        // 언어 선택
        let langLabel = makeLabel(L10n.string(.language))
        let langPopup = NSPopUpButton()
        langPopup.translatesAutoresizingMaskIntoConstraints = false
        for lang in Language.allCases {
            langPopup.addItem(withTitle: lang.displayName)
        }
        if let idx = Language.allCases.firstIndex(of: settings.language) {
            langPopup.selectItem(at: idx)
        }
        langPopup.target = self
        langPopup.action = #selector(languageChanged(_:))

        let restartLabel = NSTextField(wrappingLabelWithString: L10n.string(.restartRequired))
        restartLabel.translatesAutoresizingMaskIntoConstraints = false
        restartLabel.font = .systemFont(ofSize: 11)
        restartLabel.textColor = .secondaryLabelColor

        container.addSubview(langLabel)
        container.addSubview(langPopup)
        container.addSubview(restartLabel)

        NSLayoutConstraint.activate([
            langLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            langLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            langPopup.centerYAnchor.constraint(equalTo: langLabel.centerYAnchor),
            langPopup.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 130),
            langPopup.widthAnchor.constraint(equalToConstant: 160),

            restartLabel.topAnchor.constraint(equalTo: langLabel.bottomAnchor, constant: 8),
            restartLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 130),
            restartLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
        ])

        return container
    }

    // MARK: - Viewer Tab

    private func createViewerView() -> NSView {
        let container = NSView()

        // 배경색
        let bgLabel = makeLabel(L10n.string(.bgColor))
        let bgPopup = NSPopUpButton()
        bgPopup.translatesAutoresizingMaskIntoConstraints = false
        for bg in AppSettings.ViewerBackground.allCases {
            bgPopup.addItem(withTitle: bg.displayName())
        }
        if let idx = AppSettings.ViewerBackground.allCases.firstIndex(of: settings.viewerBackground) {
            bgPopup.selectItem(at: idx)
        }
        bgPopup.target = self
        bgPopup.action = #selector(bgChanged(_:))

        // 스크롤 줌
        let zoomCheck = NSButton(checkboxWithTitle: "스크롤 휠로 확대/축소", target: self, action: #selector(scrollZoomChanged(_:)))
        zoomCheck.translatesAutoresizingMaskIntoConstraints = false
        zoomCheck.state = settings.scrollWheelZoom ? .on : .off

        // 썸네일 스트립
        let thumbCheck = NSButton(checkboxWithTitle: "이미지 뷰어에서 썸네일 목록 표시", target: self, action: #selector(thumbStripChanged(_:)))
        thumbCheck.translatesAutoresizingMaskIntoConstraints = false
        thumbCheck.state = settings.showThumbnailStrip ? .on : .off

        container.addSubview(bgLabel)
        container.addSubview(bgPopup)
        container.addSubview(zoomCheck)
        container.addSubview(thumbCheck)

        NSLayoutConstraint.activate([
            bgLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            bgLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            bgPopup.centerYAnchor.constraint(equalTo: bgLabel.centerYAnchor),
            bgPopup.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 130),
            bgPopup.widthAnchor.constraint(equalToConstant: 160),

            zoomCheck.topAnchor.constraint(equalTo: bgLabel.bottomAnchor, constant: 20),
            zoomCheck.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            thumbCheck.topAnchor.constraint(equalTo: zoomCheck.bottomAnchor, constant: 12),
            thumbCheck.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
        ])

        return container
    }

    // MARK: - Thumbnail Tab

    private let thumbSizePopup = NSPopUpButton()
    private let cacheSlider = NSSlider()
    private let cacheValueLabel = NSTextField(labelWithString: "")
    private let cacheHintLabel = NSTextField(wrappingLabelWithString: "")
    private let applyButton = NSButton(title: "적용", target: nil, action: nil)
    private let diskSlider = NSSlider()
    private let diskValueLabel = NSTextField(labelWithString: "")
    private let diskUsageLabel = NSTextField(labelWithString: "")
    private let diskClearButton = NSButton(title: "비우기", target: nil, action: nil)

    /// 썸네일 크기·캐시 한도. 컨트롤을 움직여도 안내만 바뀌고, "적용"을 눌러야 저장·반영된다
    /// (캐시 비움 + 재생성이 무거운 작업이라 실시간 적용은 피한다).
    private func createThumbnailView() -> NSView {
        let container = NSView()

        let sizeLabel = makeLabel("최대 크기")
        thumbSizePopup.translatesAutoresizingMaskIntoConstraints = false
        for option in AppSettings.ThumbnailMaxPixel.allCases {
            thumbSizePopup.addItem(withTitle: option.displayName)
        }
        if let idx = AppSettings.ThumbnailMaxPixel.allCases.firstIndex(of: settings.thumbnailMaxPixel) {
            thumbSizePopup.selectItem(at: idx)
        }
        thumbSizePopup.target = self
        thumbSizePopup.action = #selector(thumbnailControlsChanged(_:))

        let cacheLabel = makeLabel("메모리 한도")
        cacheSlider.translatesAutoresizingMaskIntoConstraints = false
        cacheSlider.minValue = Double(AppSettings.thumbnailCacheMBRange.lowerBound)
        cacheSlider.maxValue = Double(AppSettings.thumbnailCacheMBRange.upperBound)
        cacheSlider.integerValue = settings.thumbnailCacheMB
        cacheSlider.target = self
        cacheSlider.action = #selector(thumbnailControlsChanged(_:))

        cacheValueLabel.translatesAutoresizingMaskIntoConstraints = false
        cacheValueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        cacheHintLabel.translatesAutoresizingMaskIntoConstraints = false
        cacheHintLabel.font = .systemFont(ofSize: 11)
        cacheHintLabel.textColor = .secondaryLabelColor

        applyButton.translatesAutoresizingMaskIntoConstraints = false
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"
        applyButton.target = self
        applyButton.action = #selector(applyThumbnailSettings(_:))

        container.addSubview(sizeLabel)
        container.addSubview(thumbSizePopup)
        container.addSubview(cacheLabel)
        container.addSubview(cacheSlider)
        container.addSubview(cacheValueLabel)
        container.addSubview(cacheHintLabel)

        let diskLabel = makeLabel("디스크 한도")
        diskSlider.translatesAutoresizingMaskIntoConstraints = false
        diskSlider.minValue = Double(AppSettings.thumbnailDiskCacheMBRange.lowerBound)
        diskSlider.maxValue = Double(AppSettings.thumbnailDiskCacheMBRange.upperBound)
        diskSlider.integerValue = settings.thumbnailDiskCacheMB
        diskSlider.target = self
        diskSlider.action = #selector(diskLimitChanged(_:))

        diskValueLabel.translatesAutoresizingMaskIntoConstraints = false
        diskValueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        diskUsageLabel.translatesAutoresizingMaskIntoConstraints = false
        diskUsageLabel.font = .systemFont(ofSize: 11)
        diskUsageLabel.textColor = .secondaryLabelColor

        diskClearButton.translatesAutoresizingMaskIntoConstraints = false
        diskClearButton.bezelStyle = .rounded
        diskClearButton.target = self
        diskClearButton.action = #selector(clearDiskCache(_:))

        container.addSubview(diskLabel)
        container.addSubview(diskSlider)
        container.addSubview(diskValueLabel)
        container.addSubview(diskUsageLabel)
        container.addSubview(diskClearButton)
        container.addSubview(applyButton)

        NSLayoutConstraint.activate([
            sizeLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            sizeLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            thumbSizePopup.centerYAnchor.constraint(equalTo: sizeLabel.centerYAnchor),
            thumbSizePopup.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 130),
            thumbSizePopup.widthAnchor.constraint(equalToConstant: 260),

            cacheLabel.topAnchor.constraint(equalTo: sizeLabel.bottomAnchor, constant: 20),
            cacheLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            cacheSlider.centerYAnchor.constraint(equalTo: cacheLabel.centerYAnchor),
            cacheSlider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 130),
            cacheSlider.widthAnchor.constraint(equalToConstant: 190),

            cacheValueLabel.centerYAnchor.constraint(equalTo: cacheLabel.centerYAnchor),
            cacheValueLabel.leadingAnchor.constraint(equalTo: cacheSlider.trailingAnchor, constant: 8),

            cacheHintLabel.topAnchor.constraint(equalTo: cacheLabel.bottomAnchor, constant: 8),
            cacheHintLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 130),
            cacheHintLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            diskLabel.topAnchor.constraint(equalTo: cacheHintLabel.bottomAnchor, constant: 20),
            diskLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            diskSlider.centerYAnchor.constraint(equalTo: diskLabel.centerYAnchor),
            diskSlider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 130),
            diskSlider.widthAnchor.constraint(equalToConstant: 190),

            diskValueLabel.centerYAnchor.constraint(equalTo: diskLabel.centerYAnchor),
            diskValueLabel.leadingAnchor.constraint(equalTo: diskSlider.trailingAnchor, constant: 8),

            diskUsageLabel.topAnchor.constraint(equalTo: diskLabel.bottomAnchor, constant: 12),
            diskUsageLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 130),

            diskClearButton.centerYAnchor.constraint(equalTo: diskUsageLabel.centerYAnchor),
            diskClearButton.leadingAnchor.constraint(equalTo: diskUsageLabel.trailingAnchor, constant: 12),

            applyButton.topAnchor.constraint(equalTo: diskUsageLabel.bottomAnchor, constant: 20),
            applyButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
        ])

        updateThumbnailHint()
        updateDiskLabels()
        return container
    }

    /// 슬라이더 값은 50MB 단위로 맞춰 읽는다.
    private var pendingCacheMB: Int {
        let raw = cacheSlider.integerValue
        let stepped = Int((Double(raw) / 50).rounded()) * 50
        return min(max(stepped, AppSettings.thumbnailCacheMBRange.lowerBound), AppSettings.thumbnailCacheMBRange.upperBound)
    }

    private var pendingThumbnailSize: AppSettings.ThumbnailMaxPixel {
        AppSettings.ThumbnailMaxPixel.allCases[max(0, thumbSizePopup.indexOfSelectedItem)]
    }

    private func updateThumbnailHint() {
        let mb = pendingCacheMB
        let size = pendingThumbnailSize
        let perImageKB = size.approxBytesPerImage / 1024
        let count = (mb * 1024 * 1024) / size.approxBytesPerImage
        cacheValueLabel.stringValue = mb >= 1024
            ? String(format: "%.1f GB", Double(mb) / 1024)
            : "\(mb) MB"
        cacheHintLabel.stringValue =
            "썸네일 한 장 약 \(perImageKB)KB 기준으로 약 \(count.formatted())장을 메모리에 둘 수 있어요. " +
            "넘치면 오래된 썸네일부터 비우고 필요할 때 다시 만들어요."

        let changed = mb != settings.thumbnailCacheMB || size != settings.thumbnailMaxPixel
        applyButton.isEnabled = changed
    }

    @objc private func thumbnailControlsChanged(_ sender: Any?) {
        updateThumbnailHint()
    }

    @objc private func applyThumbnailSettings(_ sender: Any?) {
        settings.thumbnailCacheMB = pendingCacheMB
        settings.thumbnailMaxPixel = pendingThumbnailSize
        cacheSlider.integerValue = pendingCacheMB
        updateThumbnailHint()
        NotificationCenter.default.post(name: .thumbnailSettingsApplied, object: nil)
    }

    /// 디스크 한도는 500MB 단위, 즉시 반영(비용이 없으므로 "적용" 불필요).
    private var pendingDiskMB: Int {
        let stepped = Int((Double(diskSlider.integerValue) / 500).rounded()) * 500
        return min(max(stepped, AppSettings.thumbnailDiskCacheMBRange.lowerBound), AppSettings.thumbnailDiskCacheMBRange.upperBound)
    }

    private func updateDiskValueLabel() {
        let mb = pendingDiskMB
        diskValueLabel.stringValue = mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
    }

    private func updateDiskLabels() {
        updateDiskValueLabel()
        let used = ThumbnailProvider.shared.diskUsedBytes
        let usedText = ByteCountFormatter.string(fromByteCount: Int64(used), countStyle: .file)
        diskUsageLabel.stringValue = "사용 중 \(usedText)"
        diskClearButton.isEnabled = used > 0
    }

    @objc private func diskLimitChanged(_ sender: Any?) {
        // 드래그 중에는 라벨만 갱신한다. 중간 값마다 한도를 적용하면 GC가 파일을 지워 버리므로 손을 뗄 때 반영.
        if NSApp.currentEvent?.type == .leftMouseDragged {
            updateDiskValueLabel()
            return
        }
        let mb = pendingDiskMB
        settings.thumbnailDiskCacheMB = mb
        diskSlider.integerValue = mb
        ThumbnailProvider.shared.setDiskLimit(bytes: mb * 1024 * 1024)
        updateDiskLabels()
        // GC는 utility 큐에서 비동기로 돌아 사용량이 뒤늦게 줄어든다. 잠시 뒤 라벨을 한 번 더 맞춘다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.updateDiskLabels() }
    }

    @objc private func clearDiskCache(_ sender: Any?) {
        ThumbnailProvider.shared.clearDisk()
        updateDiskLabels()
    }

    // MARK: - Export Tab

    private func createExportView() -> NSView {
        let container = NSView()

        // 기본 포맷
        let fmtLabel = makeLabel(L10n.string(.defaultFormat))
        let fmtPopup = NSPopUpButton()
        fmtPopup.translatesAutoresizingMaskIntoConstraints = false
        for format in ImageFormat.allCases {
            fmtPopup.addItem(withTitle: format.displayName)
        }
        if let idx = ImageFormat.allCases.firstIndex(where: { $0.rawValue == settings.defaultExportFormat }) {
            fmtPopup.selectItem(at: idx)
        }
        fmtPopup.target = self
        fmtPopup.action = #selector(formatChanged(_:))

        // 기본 품질
        let qualLabel = makeLabel(L10n.string(.defaultQuality))

        let qualSlider = NSSlider()
        qualSlider.translatesAutoresizingMaskIntoConstraints = false
        qualSlider.minValue = 1
        qualSlider.maxValue = 100
        qualSlider.integerValue = settings.defaultExportQuality
        qualSlider.target = self
        qualSlider.action = #selector(qualityChanged(_:))

        let qualValue = NSTextField(labelWithString: "\(settings.defaultExportQuality)")
        qualValue.translatesAutoresizingMaskIntoConstraints = false
        qualValue.tag = 100

        container.addSubview(fmtLabel)
        container.addSubview(fmtPopup)
        container.addSubview(qualLabel)
        container.addSubview(qualSlider)
        container.addSubview(qualValue)

        NSLayoutConstraint.activate([
            fmtLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            fmtLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            fmtPopup.centerYAnchor.constraint(equalTo: fmtLabel.centerYAnchor),
            fmtPopup.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 130),
            fmtPopup.widthAnchor.constraint(equalToConstant: 160),

            qualLabel.topAnchor.constraint(equalTo: fmtLabel.bottomAnchor, constant: 20),
            qualLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            qualSlider.centerYAnchor.constraint(equalTo: qualLabel.centerYAnchor),
            qualSlider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 130),
            qualSlider.widthAnchor.constraint(equalToConstant: 180),

            qualValue.centerYAnchor.constraint(equalTo: qualLabel.centerYAnchor),
            qualValue.leadingAnchor.constraint(equalTo: qualSlider.trailingAnchor, constant: 8),
        ])

        return container
    }

    // MARK: - Actions

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let lang = Language.allCases[sender.indexOfSelectedItem]
        settings.language = lang
        // 메뉴바 즉시 재구성
        NSApp.mainMenu = MainMenu.create()
    }

    @objc private func bgChanged(_ sender: NSPopUpButton) {
        let bg = AppSettings.ViewerBackground.allCases[sender.indexOfSelectedItem]
        settings.viewerBackground = bg
    }

    @objc private func scrollZoomChanged(_ sender: NSButton) {
        settings.scrollWheelZoom = sender.state == .on
    }

    @objc private func thumbStripChanged(_ sender: NSButton) {
        settings.showThumbnailStrip = sender.state == .on
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        let format = ImageFormat.allCases[sender.indexOfSelectedItem]
        settings.defaultExportFormat = format.rawValue
    }

    @objc private func qualityChanged(_ sender: NSSlider) {
        settings.defaultExportQuality = sender.integerValue
        // 품질 값 라벨 갱신
        if let container = sender.superview,
           let label = container.viewWithTag(100) as? NSTextField {
            label.stringValue = "\(sender.integerValue)"
        }
    }

    // MARK: - Helpers

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .right
        label.font = .systemFont(ofSize: 13)
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: 100),
        ])
        return label
    }
}
