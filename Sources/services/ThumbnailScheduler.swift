import Foundation

/// 썸네일 요청 우선순위. 값이 클수록 먼저 처리한다.
enum ThumbnailPriority: Int, Comparable {
    case background = 0
    case prefetch = 1
    case visible = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// 우선순위 큐 + 고정 수 워커 스레드.
/// 꺼내는 규칙: 우선순위 높은 것 → 같은 우선순위면 먼저 들어온 것(FIFO).
/// 화면을 벗어난 셀은 호출자가 즉시 취소하므로 큐에는 지금 필요한 것만 남는다. 그래서 FIFO로 충분하고,
/// 첫 화면이 위에서 아래로 자연스럽게 채워진다.
/// 대기 중 취소는 큐에서 바로 빼고, 실행 중 취소는 표시만 남겨 work가 isCancelled()로 확인한다.
final class ThumbnailScheduler {
    struct Token: Hashable { let id: UInt64 }

    private struct Entry {
        let token: Token
        let priority: ThumbnailPriority
        let work: (_ isCancelled: () -> Bool) -> Void
    }

    private let condition = NSCondition()
    private var pending: [Entry] = []        // 삽입 순서 유지(앞이 오래된 것)
    private var running: Set<Token> = []     // 워커가 실행 중인 토큰
    private var cancelled: Set<Token> = []   // 실행 중 취소 표시. 완료 시 제거되므로 running의 부분집합
    private var nextID: UInt64 = 0
    private var workers: [Thread] = []

    init(workerCount: Int) {
        for i in 0..<max(1, workerCount) {
            let t = Thread { [weak self] in self?.workerLoop() }
            t.name = "com.jenalab.jenaimage.thumbnail-worker-\(i)"
            t.qualityOfService = .userInitiated
            workers.append(t)
            t.start()
        }
    }

    var pendingCount: Int {
        condition.lock(); defer { condition.unlock() }
        return pending.count
    }

    var cancelledCount: Int {
        condition.lock(); defer { condition.unlock() }
        return cancelled.count
    }

    @discardableResult
    func enqueue(priority: ThumbnailPriority, work: @escaping (_ isCancelled: () -> Bool) -> Void) -> Token {
        condition.lock()
        nextID += 1
        let token = Token(id: nextID)
        pending.append(Entry(token: token, priority: priority, work: work))
        condition.signal()
        condition.unlock()
        return token
    }

    func cancel(_ token: Token) {
        condition.lock()
        if let idx = pending.firstIndex(where: { $0.token == token }) {
            pending.remove(at: idx)
        } else if running.contains(token) {
            cancelled.insert(token)  // work가 isCancelled()로 확인. 완료 시 workerLoop가 지운다
        }
        // 이미 끝난 토큰은 아무것도 남기지 않는다 — 안 그러면 cancelled가 세션 내내 자란다.
        condition.unlock()
    }

    func cancelAll() {
        condition.lock()
        pending.removeAll()
        condition.unlock()
    }

    /// 대기 중인 항목의 우선순위를 바꾼다(선로드 → 보이는 셀 승격용). 큐 안 위치는 그대로라 같은 우선순위 안에선
    /// 원래 들어온 순서를 유지한다. 이미 실행 중이거나 끝난 토큰이면 false — 그 경우 호출자는 취소·재등록하지 말고
    /// 그대로 결과를 기다려야 한다(취소하면 이미 한 디코딩을 버리고 다시 하게 된다).
    @discardableResult
    func reprioritize(_ token: Token, to priority: ThumbnailPriority) -> Bool {
        condition.lock(); defer { condition.unlock() }
        guard let idx = pending.firstIndex(where: { $0.token == token }) else { return false }
        let old = pending[idx]
        pending[idx] = Entry(token: old.token, priority: priority, work: old.work)
        return true
    }

    private func dequeue() -> Entry {
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let idx = bestIndex() {
                let entry = pending.remove(at: idx)
                running.insert(entry.token)
                return entry
            }
            condition.wait()
        }
    }

    /// 우선순위 최대, 그중 가장 앞(먼저 들어온) 인덱스.
    private func bestIndex() -> Int? {
        var best: Int?
        for (i, e) in pending.enumerated() {
            if let b = best {
                if e.priority > pending[b].priority { best = i }
            } else {
                best = i
            }
        }
        return best
    }

    private func workerLoop() {
        while true {
            let entry = dequeue()
            let token = entry.token
            entry.work { [weak self] in
                guard let self else { return true }
                self.condition.lock(); defer { self.condition.unlock() }
                return self.cancelled.contains(token)
            }
            condition.lock()
            running.remove(token)
            cancelled.remove(token)
            condition.unlock()
        }
    }
}
