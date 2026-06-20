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

        self.panes = files.map { ComparePaneView(file: $0, imageService: imageService) }
        setupGrid()
        panes.forEach { $0.load() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupGrid() {
        guard let window else { return }
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        gridView.translatesAutoresizingMaskIntoConstraints = false
        gridView.rowSpacing = 2
        gridView.columnSpacing = 2
        rebuildGrid()
        container.addSubview(gridView)
        window.contentView = container

        NSLayoutConstraint.activate([
            gridView.topAnchor.constraint(equalTo: container.topAnchor),
            gridView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            gridView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
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
        // 모든 칸이 균등하게 늘어나도록
        for col in 0..<shape.cols {
            gridView.column(at: col).xPlacement = .fill
        }
        for row in 0..<shape.rows {
            gridView.row(at: row).yPlacement = .fill
        }
        for pane in panes {
            pane.setContentHuggingPriority(.defaultLow, for: .horizontal)
            pane.setContentHuggingPriority(.defaultLow, for: .vertical)
        }
    }
}
