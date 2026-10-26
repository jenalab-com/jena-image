import AppKit

/// 일괄 내보내기 시트. 포맷·품질, 긴 변 기준 축소, 저장 폴더를 정하고 진행률을 보여준다.
final class BatchExportWindowController: NSWindowController {

    /// 끝났을 때(취소 포함) 호출. 저장된 폴더를 넘겨 호출자가 목록을 갱신할 수 있게 한다.
    var onFinish: ((BatchExportReport, URL) -> Void)?

    private let sources: [URL]
    private let service = BatchExportService()
    private var isCancelled = false
    private var isRunning = false

    private let accessory = ExportAccessoryView()
    private let resizeCheckbox = NSButton(checkboxWithTitle: "긴 변이 다음보다 크면 줄이기:", target: nil, action: nil)
    private let longEdgeField = NSTextField(string: "2000")
    private let destinationLabel = NSTextField(labelWithString: "")
    private let chooseButton = NSButton(title: "선택…", target: nil, action: nil)
    private let progressBar = NSProgressIndicator()
    private let progressLabel = NSTextField(labelWithString: "")
    private let exportButton = NSButton(title: "내보내기", target: nil, action: nil)
    private let cancelButton = NSButton(title: "취소", target: nil, action: nil)

    private var destination: URL {
        didSet { updateDestinationLabel() }
    }

    private func updateDestinationLabel() {
        destinationLabel.stringValue = destination.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    init(sources: [URL]) {
        self.sources = sources
        self.destination = sources.first?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "일괄 내보내기"
        super.init(window: window)
        setupViews()
        applyDefaults()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 표시

    func beginSheet(for parent: NSWindow) {
        guard let window else { return }
        parent.beginSheet(window) { _ in }
    }

    private func setupViews() {
        guard let content = window?.contentView else { return }
        let count = sources.count
        let title = NSTextField(labelWithString: "선택한 이미지 \(count)개를 같은 설정으로 내보냅니다.")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        let note = NSTextField(wrappingLabelWithString: "리사이즈는 비율을 유지한 채 긴 변만 맞추며, 그보다 작은 이미지는 원본 크기 그대로입니다. 파일명은 원본 이름에 새 확장자를 붙이고 겹치면 번호를 더합니다.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor

        resizeCheckbox.target = self
        resizeCheckbox.action = #selector(resizeToggled(_:))
        longEdgeField.alignment = .right
        let formatter = NumberFormatter()
        formatter.minimum = 16
        formatter.maximum = 20000
        formatter.allowsFloats = false
        longEdgeField.formatter = formatter
        let pxLabel = NSTextField(labelWithString: "px")

        let destTitle = NSTextField(labelWithString: "저장 폴더:")
        destinationLabel.lineBreakMode = .byTruncatingMiddle
        destinationLabel.textColor = .secondaryLabelColor
        chooseButton.target = self
        chooseButton.action = #selector(chooseDestination(_:))

        progressBar.style = .bar
        progressBar.minValue = 0
        progressBar.maxValue = Double(count)
        progressBar.isIndeterminate = false
        progressBar.isHidden = true
        progressLabel.font = .systemFont(ofSize: 11)
        progressLabel.textColor = .secondaryLabelColor
        progressLabel.lineBreakMode = .byTruncatingMiddle
        progressLabel.isHidden = true

        exportButton.target = self
        exportButton.action = #selector(startExport(_:))
        exportButton.keyEquivalent = "\r"
        cancelButton.target = self
        cancelButton.action = #selector(cancel(_:))
        cancelButton.keyEquivalent = "\u{1b}"

        let resizeRow = NSStackView(views: [resizeCheckbox, longEdgeField, pxLabel])
        resizeRow.orientation = .horizontal
        resizeRow.spacing = 6
        let destRow = NSStackView(views: [destTitle, destinationLabel, chooseButton])
        destRow.orientation = .horizontal
        destRow.spacing = 8
        let buttons = NSStackView(views: [cancelButton, exportButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [title, accessory, resizeRow, destRow, note, progressBar, progressLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            accessory.heightAnchor.constraint(equalToConstant: 64),
            accessory.widthAnchor.constraint(equalTo: stack.widthAnchor),
            longEdgeField.widthAnchor.constraint(equalToConstant: 70),
            destRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            destinationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            note.widthAnchor.constraint(equalTo: stack.widthAnchor),
            progressBar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            progressLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
    }

    private func applyDefaults() {
        let settings = AppSettings.shared
        if let format = ImageFormat(rawValue: settings.defaultExportFormat) { accessory.selectedFormat = format }
        accessory.quality = Float(settings.defaultExportQuality)
        resizeCheckbox.state = settings.batchExportResize ? .on : .off
        longEdgeField.integerValue = settings.batchExportLongEdge
        longEdgeField.isEnabled = settings.batchExportResize
        updateDestinationLabel()
    }

    // MARK: - 액션

    @objc private func resizeToggled(_ sender: NSButton) {
        longEdgeField.isEnabled = sender.state == .on
    }

    @objc private func chooseDestination(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = destination
        panel.prompt = "선택"
        panel.message = "내보낸 파일을 저장할 폴더를 선택하세요"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.destination = url
        }
    }

    @objc private func cancel(_ sender: Any?) {
        if isRunning {
            isCancelled = true
            cancelButton.isEnabled = false
            progressLabel.stringValue = "취소하는 중…"
        } else {
            finish(report: BatchExportReport(cancelled: true))
        }
    }

    @objc private func startExport(_ sender: Any?) {
        guard !isRunning else { return }
        let resize = resizeCheckbox.state == .on
        let longEdge = longEdgeField.integerValue
        if resize, longEdge < 16 {
            NSSound.beep()
            window?.makeFirstResponder(longEdgeField)
            return
        }
        let options = BatchExportOptions(
            format: accessory.selectedFormat,
            quality: accessory.quality,
            maxLongEdge: resize ? longEdge : nil,
            destination: destination
        )
        let settings = AppSettings.shared
        settings.defaultExportFormat = options.format.rawValue
        settings.defaultExportQuality = Int(options.quality)
        settings.batchExportResize = resize
        settings.batchExportLongEdge = longEdge

        isRunning = true
        for control in [accessory, resizeCheckbox, longEdgeField, chooseButton, exportButton] as [NSView] {
            (control as? NSControl)?.isEnabled = false
        }
        accessory.isEnabled = false
        progressBar.isHidden = false
        progressLabel.isHidden = false
        progressBar.doubleValue = 0

        let total = sources.count
        Task { @MainActor [weak self] in
            guard let self else { return }
            let report = await self.service.export(self.sources, options: options,
                                                   isCancelled: { [weak self] in self?.isCancelled ?? true },
                                                   progress: { [weak self] done, url in
                guard let self else { return }
                self.progressBar.doubleValue = Double(done)
                self.progressLabel.stringValue = "\(done + 1)/\(total) · \(url.lastPathComponent)"
            })
            self.progressBar.doubleValue = Double(total)
            self.finish(report: report)
        }
    }

    private func finish(report: BatchExportReport) {
        guard let window else { return }
        let destination = self.destination
        window.sheetParent?.endSheet(window)
        onFinish?(report, destination)
    }
}
