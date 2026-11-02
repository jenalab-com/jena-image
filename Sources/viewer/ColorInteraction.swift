import AppKit

/// 누른 뒤 거의 움직이지 않고 떼면 클릭, 임계값을 넘으면 드래그(패닝).
struct ClickDragGesture {
    static let threshold: CGFloat = 3

    private let start: CGPoint
    private(set) var hasExceededThreshold = false

    init(start: CGPoint) { self.start = start }

    mutating func update(to point: CGPoint) {
        if hypot(point.x - start.x, point.y - start.y) > Self.threshold { hasExceededThreshold = true }
    }

    var isClick: Bool { !hasExceededThreshold }
}

/// ⌥ 임시 돋보기 판정. ⌘⌥ 같은 조합에선 켜지 않는다.
enum OptionKeyGate {
    static func isOptionAlone(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection([.command, .option, .control, .shift]) == [.option]
    }
}

/// 칩과 정보창은 서로 떨어진 뷰라 칩을 벗어나는 순간 mouseExited가 정보창 진입보다 먼저 온다.
/// 둘 다 벗어난 상태가 `delay` 이상 이어질 때만 닫는다.
final class HoverGrace {
    typealias Scheduler = (_ delay: TimeInterval, _ work: @escaping () -> Void) -> (() -> Void)

    static let mainQueueScheduler: Scheduler = { delay, work in
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return { item.cancel() }
    }

    var onClose: (() -> Void)?
    private let delay: TimeInterval
    private let schedule: Scheduler
    private var insideCount = 0
    private var cancelPending: (() -> Void)?
    private var pendingID: UUID?

    init(delay: TimeInterval = 0.12, schedule: @escaping Scheduler = HoverGrace.mainQueueScheduler) {
        self.delay = delay
        self.schedule = schedule
    }

    deinit { cancelPending?() }

    func enter() {
        insideCount += 1
        pendingID = nil
        cancelPending?()
        cancelPending = nil
    }

    func exit() {
        guard insideCount > 0 else { return }
        insideCount -= 1
        guard insideCount == 0 else { return }
        cancelPending?()
        let id = UUID()
        pendingID = id
        cancelPending = schedule(delay) { [weak self] in
            guard let self, self.insideCount == 0, self.pendingID == id else { return }
            self.pendingID = nil
            self.cancelPending = nil
            self.onClose?()
        }
    }
}

enum MagnifierPlacement {
    /// 좌하단 원점(비뒤집힘) 좌표. 기본은 커서 오른쪽 아래, 가장자리에 닿으면 반대편으로 뒤집는다.
    static func frame(cursor: CGPoint, size: CGSize, bounds: CGRect, offset: CGFloat = 18) -> CGRect {
        var x = cursor.x + offset
        if x + size.width > bounds.maxX { x = cursor.x - offset - size.width }
        var y = cursor.y - offset - size.height
        if y < bounds.minY { y = cursor.y + offset }
        // 뷰보다 확대경이 크면 크기는 유지하고 원점에 고정한다. 넘치는 부분은 뷰에서 잘린다.
        x = max(bounds.minX, min(x, bounds.maxX - size.width))
        y = max(bounds.minY, min(y, bounds.maxY - size.height))
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

enum ChipFlowLayout {
    /// 위-왼쪽 원점(flipped) 좌표. 한 줄에 최소 1개.
    static func frames(count: Int, itemSize: CGSize, spacing: CGFloat, width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        guard count > 0 else { return ([], 0) }
        let perRow = max(1, Int(((width + spacing) / (itemSize.width + spacing)).rounded(.down)))
        var frames: [CGRect] = []
        for i in 0..<count {
            let row = i / perRow, col = i % perRow
            frames.append(CGRect(x: CGFloat(col) * (itemSize.width + spacing),
                                 y: CGFloat(row) * (itemSize.height + spacing),
                                 width: itemSize.width, height: itemSize.height))
        }
        let rows = (count + perRow - 1) / perRow
        return (frames, CGFloat(rows) * itemSize.height + CGFloat(rows - 1) * spacing)
    }
}
