import AppKit

func runColorInteractionTests() {
    runTest("클릭: 3pt 이내로만 움직이고 떼면 클릭") {
        var g = ClickDragGesture(start: CGPoint(x: 100, y: 100))
        check(g.isClick, "움직이지 않고 떼어도 클릭")
        g.update(to: CGPoint(x: 102, y: 102))          // 거리 2.83
        check(g.isClick && !g.hasExceededThreshold, "2.83pt는 클릭")
        g.update(to: CGPoint(x: 103, y: 100))          // 정확히 3.0
        check(g.isClick, "정확히 3pt도 클릭(넘지 않음)")
    }

    runTest("드래그: 3pt를 넘으면 되돌아와도 드래그로 남는다") {
        var g = ClickDragGesture(start: .zero)
        g.update(to: CGPoint(x: 2, y: 0))
        g.update(to: CGPoint(x: 3.1, y: 0))
        check(g.hasExceededThreshold && !g.isClick, "3.1pt는 드래그")
        g.update(to: CGPoint(x: 0, y: 0))              // 제자리로 돌아와 떼도
        check(!g.isClick, "한번 패닝한 제스처는 클릭이 아니다 — 패닝 후 의도치 않은 복사 방지")
        var diagonal = ClickDragGesture(start: CGPoint(x: 100, y: 100))
        diagonal.update(to: CGPoint(x: 97.8, y: 97.8))
        check(!diagonal.isClick, "음의 대각선 3.11pt도 드래그 — 축별 3pt 판정 금지")
    }

    runTest("OptionKeyGate: ⌥ 단독만 true") {
        check(OptionKeyGate.isOptionAlone([.option]), "⌥")
        check(!OptionKeyGate.isOptionAlone([]), "아무것도 안 누름")
        check(!OptionKeyGate.isOptionAlone([.command]), "⌘만")
    }

    runTest("OptionKeyGate: ⌘⌥·⇧⌥·⌃⌥ 같은 조합 키는 false") {
        check(!OptionKeyGate.isOptionAlone([.command, .option]), "⌘⌥")
        check(!OptionKeyGate.isOptionAlone([.shift, .option]), "⇧⌥")
        check(!OptionKeyGate.isOptionAlone([.control, .option]), "⌃⌥")
        check(!OptionKeyGate.isOptionAlone([.command, .shift, .option]), "⌘⇧⌥")
    }

    runTest("OptionKeyGate: CapsLock·fn 같은 상태 플래그는 무시한다") {
        check(OptionKeyGate.isOptionAlone([.option, .capsLock]), "⌥+CapsLock")
        check(OptionKeyGate.isOptionAlone([.option, .function]), "⌥+fn(방향키 등에서 붙음)")
        check(OptionKeyGate.isOptionAlone([.option, .numericPad]), "⌥+숫자패드 플래그")
    }
}

/// 시계를 손으로 돌리는 가짜 스케줄러.
private final class FakeClock {
    private(set) var pending: [(id: Int, deadline: TimeInterval, work: () -> Void, cancelled: Bool)] = []
    private var now: TimeInterval = 0
    private var nextID = 0
    lazy var scheduler: HoverGrace.Scheduler = { [unowned self] delay, work in
        let id = self.nextID; self.nextID += 1
        self.pending.append((id, self.now + delay, work, false))
        return { if let i = self.pending.firstIndex(where: { $0.id == id }) { self.pending[i].cancelled = true } }
    }
    func advance(by interval: TimeInterval = 0.12) {
        now += interval
        let due = pending.filter { $0.deadline <= now }
        pending.removeAll { $0.deadline <= now }
        for entry in due where !entry.cancelled { entry.work() }
    }
}

func runColorLayoutTests() {
    runTest("HoverGrace: 칩에서 정보창으로 옮겨가도 닫히지 않는다") {
        let clock = FakeClock(); let grace = HoverGrace(delay: 0.12, schedule: clock.scheduler)
        var closed = 0; grace.onClose = { closed += 1 }
        grace.enter()        // 칩 위
        grace.exit()         // 칩을 벗어남 — 정보창에 닿기 전 틈
        grace.enter()        // 정보창 진입 (유예 안)
        clock.advance()
        checkEqual(closed, 0, "정보창으로 건너갔으니 닫히지 않음")
        grace.exit()         // 정보창을 벗어남
        clock.advance()
        checkEqual(closed, 1, "둘 다 벗어나면 유예 후 닫힘")
    }

    runTest("HoverGrace: 둘 다 벗어나면 유예 뒤 정확히 한 번 닫힌다") {
        let clock = FakeClock(); let grace = HoverGrace(delay: 0.12, schedule: clock.scheduler)
        var closed = 0; grace.onClose = { closed += 1 }
        grace.enter(); grace.exit()
        check(closed == 0, "유예 시간이 지나기 전엔 닫히지 않음")
        clock.advance()
        checkEqual(closed, 1, "유예 후 닫힘")
        clock.advance()
        checkEqual(closed, 1, "중복 닫힘 없음")
    }

    runTest("HoverGrace: 옆 칩으로 바로 이동(exit 직후 enter)하면 닫히지 않는다") {
        let clock = FakeClock(); let grace = HoverGrace(delay: 0.12, schedule: clock.scheduler)
        var closed = 0; grace.onClose = { closed += 1 }
        grace.enter(); grace.exit(); grace.enter(); grace.exit(); grace.enter()
        clock.advance()
        checkEqual(closed, 0, "취소된 예약은 실행되지 않음")
    }

    runTest("MagnifierPlacement: 기본은 커서 오른쪽 아래, 가장자리에서 뒤집힌다") {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let size = CGSize(width: 110, height: 134)
        let normal = MagnifierPlacement.frame(cursor: CGPoint(x: 300, y: 400), size: size, bounds: bounds)
        checkEqual(normal, CGRect(x: 318, y: 400 - 18 - 134, width: 110, height: 134), "오른쪽 아래")

        let nearRight = MagnifierPlacement.frame(cursor: CGPoint(x: 780, y: 400), size: size, bounds: bounds)
        check(nearRight.maxX <= 780 - 18 + 0.001, "오른쪽 끝 근처: 커서 왼쪽으로 뒤집힘 \(nearRight)")
        let nearBottom = MagnifierPlacement.frame(cursor: CGPoint(x: 300, y: 30), size: size, bounds: bounds)
        check(nearBottom.minY >= 30 + 18 - 0.001, "아래 끝 근처: 커서 위쪽으로 뒤집힘 \(nearBottom)")
        let corner = MagnifierPlacement.frame(cursor: CGPoint(x: 790, y: 5), size: size, bounds: bounds)
        check(bounds.contains(corner), "모서리: 양쪽 다 뒤집혀도 bounds 안 \(corner)")
    }

    runTest("ChipFlowLayout: 폭을 넘으면 줄바꿈한다") {
        // 폭 300, 칩 40×60, 간격 8 → 한 줄 6개
        let r = ChipFlowLayout.frames(count: 13, itemSize: CGSize(width: 40, height: 60), spacing: 8, width: 300)
        checkEqual(r.frames.count, 13, "개수")
        checkEqual(r.frames[5], CGRect(x: 5 * 48, y: 0, width: 40, height: 60), "첫 줄 마지막")
        checkEqual(r.frames[6], CGRect(x: 0, y: 68, width: 40, height: 60), "둘째 줄 처음")
        checkEqual(r.height, 3 * 60 + 2 * 8, "세 줄 높이")
        checkEqual(ChipFlowLayout.frames(count: 0, itemSize: CGSize(width: 40, height: 60), spacing: 8, width: 300).height, 0, "빈 목록")
        let narrow = ChipFlowLayout.frames(count: 3, itemSize: CGSize(width: 40, height: 60), spacing: 8, width: 10)
        checkEqual(narrow.frames[2].minX, 0, "너무 좁아도 한 줄에 최소 1개")
    }

    runTest("HoverGrace: 두 영역이 겹쳐 진입해도 마지막 이탈부터 120ms를 센다") {
        let clock = FakeClock()
        let grace = HoverGrace(schedule: clock.scheduler)
        var closed = 0
        grace.onClose = { closed += 1 }
        grace.enter(); grace.enter(); grace.exit()
        clock.advance(by: 1)
        checkEqual(closed, 0, "정보창에 먼저 들어가고 칩을 나와도 열린 상태")
        grace.exit()
        clock.advance(by: 0.10)
        checkEqual(closed, 0, "100ms에는 유지")
        grace.exit()
        clock.advance(by: 0.03)
        checkEqual(closed, 1, "중복 이탈이 유예를 연장하지 않음")
    }

    runTest("HoverGrace: 취소된 콜백이 늦게 실행돼도 새 유예를 닫지 않는다") {
        let clock = FakeClock()
        let grace = HoverGrace(schedule: clock.scheduler)
        var closed = 0
        grace.onClose = { closed += 1 }
        grace.enter(); grace.exit()
        let stale = clock.pending[0].work
        grace.enter(); grace.exit()
        stale()
        checkEqual(closed, 0, "옛 예약이 새 예약의 닫기를 앞당기지 않음")
        clock.advance()
        checkEqual(closed, 1, "현재 예약만 닫음")
        stale()
        checkEqual(closed, 1, "늦은 중복 실행도 무시")
    }

    runTest("HoverGrace: 해제되면 예약을 취소하고 정보창을 닫지 않는다") {
        let clock = FakeClock()
        var grace: HoverGrace? = HoverGrace(schedule: clock.scheduler)
        let isReleased = { [weak grace] in grace == nil }
        var closed = 0
        grace?.onClose = { closed += 1 }
        grace?.enter(); grace?.exit()
        grace = nil
        check(isReleased(), "예약이 정보창 수명을 늘리지 않음")
        check(clock.pending[0].cancelled, "해제 시 예약 취소")
        clock.advance()
        checkEqual(closed, 0, "해제 후 콜백 없음")
    }

    runTest("MagnifierPlacement: 이동한 bounds와 확대경보다 작은 뷰") {
        let bounds = CGRect(x: 50, y: 80, width: 300, height: 250)
        let size = CGSize(width: 110, height: 134)
        for cursor in [CGPoint(x: 50, y: 80), CGPoint(x: 350, y: 330), CGPoint(x: 350, y: 80)] {
            check(bounds.contains(MagnifierPlacement.frame(cursor: cursor, size: size, bounds: bounds)),
                  "0이 아닌 원점에서도 가장자리 안에 배치")
        }
        let tiny = CGRect(x: 50, y: 80, width: 70, height: 90)
        checkEqual(MagnifierPlacement.frame(cursor: CGPoint(x: 60, y: 90), size: size, bounds: tiny),
                   CGRect(origin: tiny.origin, size: size), "들어갈 수 없는 크기는 원점 고정·크기 유지")
    }

    runTest("ChipFlowLayout: 정확히 맞는 폭과 한 칸 모자란 폭, 마지막 간격 제외") {
        let item = CGSize(width: 40, height: 60)
        let exact = ChipFlowLayout.frames(count: 3, itemSize: item, spacing: 8, width: 136)
        checkEqual(exact.frames.last?.maxX, 136, "3칩+사이 간격 2개가 정확히 맞음")
        checkEqual(exact.height, 60, "한 줄 아래 불필요한 간격 없음")
        let smaller = ChipFlowLayout.frames(count: 3, itemSize: item, spacing: 8, width: 135)
        checkEqual(smaller.frames[2].origin, CGPoint(x: 0, y: 68), "1pt 부족하면 다음 줄")
        checkEqual(smaller.height, 128, "두 줄 높이+사이 간격 1개")
        let zero = ChipFlowLayout.frames(count: 2, itemSize: item, spacing: 8, width: 0)
        checkEqual(zero.frames[1].origin, CGPoint(x: 0, y: 68), "배치 전 폭 0이어도 한 줄 한 칩")
    }

}
