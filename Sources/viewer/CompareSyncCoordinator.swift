import AppKit

/// 비교 칸들의 줌·팬을 동기화한다. 한 칸의 변환을 나머지 칸에 브로드캐스트.
final class CompareSyncCoordinator {
    var isEnabled = true

    private let panes: [ComparePaneView]
    private var isBroadcasting = false

    init(panes: [ComparePaneView]) {
        self.panes = panes
        for pane in panes {
            pane.imageDisplayView.onTransformChanged = { [weak self, weak pane] mag, center in
                guard let self, let pane else { return }
                self.broadcast(from: pane, magnification: mag, centerInImage: center)
            }
        }
    }

    private func broadcast(from source: ComparePaneView, magnification: CGFloat, centerInImage: CGPoint) {
        guard isEnabled, !isBroadcasting else { return }
        isBroadcasting = true
        defer { isBroadcasting = false }
        for pane in panes where pane !== source {
            pane.imageDisplayView.applyTransform(magnification: magnification, centerInImage: centerInImage)
        }
    }
}
