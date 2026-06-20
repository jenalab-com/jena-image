import AppKit

/// 칸 수 → (행, 열) 그리드 형태. 2=1x2, 3=1x3, 4=2x2.
func compareGridShape(count: Int) -> (rows: Int, cols: Int) {
    switch count {
    case ...2: return (1, 2)
    case 3:    return (1, 3)
    default:   return (2, 2)   // 4
    }
}

/// 여러 이미지를 나란히 비교하는 별도 창.
final class CompareWindowController: NSWindowController {
    var onClose: (() -> Void)?

    private let imageService: ImageServiceProtocol
    private var panes: [ComparePaneView] = []
    private let gridView = NSGridView()
    private var syncCoordinator: CompareSyncCoordinator?
    private let syncToggle = NSButton(checkboxWithTitle: "줌·팬 동기화", target: nil, action: nil)
    private weak var activePane: ComparePaneView?
    private var candidateStrip: CompareCandidateStrip?
    /// 모든 칸을 동일 크기로 묶는 제약(그리드 재구성마다 갱신).
    private var equalSizeConstraints: [NSLayoutConstraint] = []

    init(files: [ImageFile], imageService: ImageServiceProtocol) {
        self.imageService = imageService

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "비교"
        window.center()
        super.init(window: window)
        window.delegate = self

        self.panes = files.map { ComparePaneView(file: $0, imageService: imageService) }
        self.syncCoordinator = CompareSyncCoordinator(panes: panes)
        for pane in panes {
            pane.onRequestClose = { [weak self] p in self?.removePane(p) }
            pane.onActivated = { [weak self] p in self?.setActivePane(p) }
        }
        setupGrid()
        panes.forEach { $0.load() }
        updateCloseButtons()
        panes.first.map { setActivePane($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupGrid() {
        guard let window else { return }
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        syncToggle.translatesAutoresizingMaskIntoConstraints = false
        syncToggle.state = .on
        syncToggle.target = self
        syncToggle.action = #selector(toggleSync(_:))
        container.addSubview(syncToggle)

        gridView.translatesAutoresizingMaskIntoConstraints = false
        gridView.rowSpacing = 2
        gridView.columnSpacing = 2
        rebuildGrid()
        container.addSubview(gridView)

        let strip = CompareCandidateStrip(
            files: buildCandidates(from: panes.map { $0.file }),
            imageService: imageService
        )
        strip.onSelect = { [weak self] file in self?.handleCandidateSelected(file) }
        strip.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(strip)
        self.candidateStrip = strip

        window.contentView = container

        NSLayoutConstraint.activate([
            syncToggle.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            syncToggle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),

            gridView.topAnchor.constraint(equalTo: syncToggle.bottomAnchor, constant: 8),
            gridView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            gridView.bottomAnchor.constraint(equalTo: strip.topAnchor, constant: -8),

            strip.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            strip.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            strip.heightAnchor.constraint(equalToConstant: 70),
        ])
    }

    @objc private func toggleSync(_ sender: NSButton) {
        syncCoordinator?.isEnabled = (sender.state == .on)
    }

    private func removePane(_ pane: ComparePaneView) {
        guard panes.count > 2, let idx = panes.firstIndex(where: { $0 === pane }) else { return }
        panes.remove(at: idx)
        rebuildGrid()
        syncCoordinator = CompareSyncCoordinator(panes: panes)  // 콜백 재배선
        syncCoordinator?.isEnabled = (syncToggle.state == .on)
        updateCloseButtons()
        // 닫힌 칸이 활성이었다면 첫 칸으로 활성 이동.
        if activePane === pane || activePane == nil {
            panes.first.map { setActivePane($0) }
        }
    }

    private func setActivePane(_ pane: ComparePaneView) {
        activePane?.setActive(false)
        activePane = pane
        pane.setActive(true)
    }

    private func handleCandidateSelected(_ file: ImageFile) {
        let target = activePane ?? panes.first
        target?.setFile(file)
        if let target { setActivePane(target) }
    }

    private func buildCandidates(from files: [ImageFile]) -> [ImageFile] {
        var seen = Set<URL>()
        var result: [ImageFile] = []
        let folderImages: [ImageFile]
        if let parent = files.first?.url.deletingLastPathComponent() {
            let serviceResult = FileService().contentsOfFolder(
                at: parent,
                sortKey: AppSettings.shared.sortKey,
                ascending: AppSettings.shared.sortAscending
            )
            if case .success(let (_, imageURLs)) = serviceResult {
                folderImages = imageURLs.compactMap { ImageFile(url: $0) }.filter { !$0.isVideo }
            } else {
                folderImages = []
            }
        } else {
            folderImages = []
        }
        for f in files + folderImages where !seen.contains(f.url) {
            seen.insert(f.url); result.append(f)
        }
        return result
    }

    /// 2칸이면 닫기 비활성(최소 2칸 유지).
    private func updateCloseButtons() {
        let enabled = panes.count > 2
        panes.forEach { $0.setCloseEnabled(enabled) }
    }

    /// 현재 panes로 그리드를 다시 구성한다(칸 추가/제거 시 재호출 — Task 3에서 사용).
    private func rebuildGrid() {
        while gridView.numberOfRows > 0 { gridView.removeRow(at: 0) }

        let shape = compareGridShape(count: panes.count)
        var index = 0
        for _ in 0..<shape.rows {
            var rowViews: [NSView] = []
            for _ in 0..<shape.cols {
                rowViews.append(index < panes.count ? panes[index] : NSView())
                index += 1
            }
            gridView.addRow(with: rowViews)
        }
        // 각 칸이 셀을 가득 채우도록
        for col in 0..<shape.cols {
            gridView.column(at: col).xPlacement = .fill
        }
        for row in 0..<shape.rows {
            gridView.row(at: row).yPlacement = .fill
        }
        for pane in panes {
            pane.setContentHuggingPriority(.defaultLow, for: .horizontal)
            pane.setContentHuggingPriority(.defaultLow, for: .vertical)
            // 이미지 크기가 칸 너비를 끌어당기지 않도록 압축 저항도 낮춘다.
            pane.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            pane.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        }

        // 칸 너비/높이를 서로 동일하게 묶어 균등 분할(.fill만으론 컬럼 폭이
        // 콘텐츠 크기를 따라가 한쪽이 더 넓어지는 문제를 막는다).
        NSLayoutConstraint.deactivate(equalSizeConstraints)
        equalSizeConstraints.removeAll()
        if let first = panes.first {
            for pane in panes.dropFirst() {
                equalSizeConstraints.append(pane.widthAnchor.constraint(equalTo: first.widthAnchor))
                equalSizeConstraints.append(pane.heightAnchor.constraint(equalTo: first.heightAnchor))
            }
        }
        NSLayoutConstraint.activate(equalSizeConstraints)
    }
}

// MARK: - NSWindowDelegate

extension CompareWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
