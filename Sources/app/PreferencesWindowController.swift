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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
