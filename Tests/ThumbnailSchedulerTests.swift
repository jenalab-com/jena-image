import Foundation

func runSchedulerTests() {
    runTest("우선순위 높은 것 먼저, 같은 우선순위는 들어온 순서(FIFO)") {
        let scheduler = ThumbnailScheduler(workerCount: 1)
        let gate = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var order: [String] = []
        func record(_ s: String) { lock.lock(); order.append(s); lock.unlock() }

        // 첫 작업이 워커를 붙잡고 있는 동안 나머지를 쌓는다.
        scheduler.enqueue(priority: .visible) { _ in gate.wait(); record("first") }
        Thread.sleep(forTimeInterval: 0.05)
        scheduler.enqueue(priority: .prefetch) { _ in record("p1") }
        scheduler.enqueue(priority: .visible) { _ in record("v1") }
        scheduler.enqueue(priority: .prefetch) { _ in record("p2") }
        scheduler.enqueue(priority: .visible) { _ in record("v2") }
        gate.signal()

        check(waitUntil { lock.lock(); defer { lock.unlock() }; return order.count == 5 }, "5개 모두 실행")
        lock.lock(); let got = order; lock.unlock()
        checkEqual(got, ["first", "v1", "v2", "p1", "p2"], "실행 순서")
    }

    runTest("이미 끝난 토큰을 취소해도 내부 집합에 남지 않는다") {
        let scheduler = ThumbnailScheduler(workerCount: 1)
        let lock = NSLock()
        var done = false
        let token = scheduler.enqueue(priority: .visible) { _ in lock.lock(); done = true; lock.unlock() }
        check(waitUntil { lock.lock(); defer { lock.unlock() }; return done }, "실행 완료")
        scheduler.cancel(token)
        checkEqual(scheduler.cancelledCount, 0, "완료된 토큰은 취소 표시를 남기지 않음")
    }

    runTest("testCancelledEntryIsSkipped: 취소된 항목은 실행되지 않는다") {
        let scheduler = ThumbnailScheduler(workerCount: 1)
        let gate = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var ran: [String] = []
        func record(_ s: String) { lock.lock(); ran.append(s); lock.unlock() }

        scheduler.enqueue(priority: .visible) { _ in gate.wait(); record("first") }
        Thread.sleep(forTimeInterval: 0.05)
        let a = scheduler.enqueue(priority: .visible) { _ in record("a") }
        scheduler.enqueue(priority: .visible) { _ in record("b") }
        scheduler.cancel(a)
        checkEqual(scheduler.pendingCount, 1, "취소 후 대기 수")
        gate.signal()

        check(waitUntil { lock.lock(); defer { lock.unlock() }; return ran.count == 2 }, "2개 실행")
        lock.lock(); let got = ran; lock.unlock()
        checkEqual(got, ["first", "b"], "a는 건너뜀")
    }

    runTest("reprioritize: 대기 중이면 우선순위를 올려 먼저 꺼내고, 실행 중이면 false") {
        let scheduler = ThumbnailScheduler(workerCount: 1)
        let gate = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var order: [String] = []
        func record(_ s: String) { lock.lock(); order.append(s); lock.unlock() }

        let first = scheduler.enqueue(priority: .visible) { _ in gate.wait(); record("first") }
        Thread.sleep(forTimeInterval: 0.05)
        let p1 = scheduler.enqueue(priority: .prefetch) { _ in record("p1") }
        scheduler.enqueue(priority: .visible) { _ in record("v1") }
        scheduler.enqueue(priority: .prefetch) { _ in record("p2") }

        check(!scheduler.reprioritize(first, to: .visible), "실행 중인 토큰은 false")
        check(scheduler.reprioritize(p1, to: .visible), "대기 중인 토큰은 true")
        checkEqual(scheduler.pendingCount, 3, "대기 수는 그대로")
        gate.signal()

        check(waitUntil { lock.lock(); defer { lock.unlock() }; return order.count == 4 }, "4개 모두 실행")
        lock.lock(); let got = order; lock.unlock()
        checkEqual(got, ["first", "p1", "v1", "p2"], "p1이 visible로 올라 v1보다 먼저(들어온 순서 유지)")
    }

    runTest("cancelAll은 대기 중인 것을 모두 버린다") {
        let scheduler = ThumbnailScheduler(workerCount: 1)
        let gate = DispatchSemaphore(value: 0)
        scheduler.enqueue(priority: .visible) { _ in gate.wait() }
        Thread.sleep(forTimeInterval: 0.05)
        scheduler.enqueue(priority: .prefetch) { _ in }
        scheduler.enqueue(priority: .prefetch) { _ in }
        scheduler.cancelAll()
        checkEqual(scheduler.pendingCount, 0, "cancelAll 후 대기 수")
        gate.signal()
    }

    runTest("워커 수만큼만 동시에 실행된다") {
        let scheduler = ThumbnailScheduler(workerCount: 2)
        let lock = NSLock()
        var concurrent = 0, peak = 0, done = 0
        for _ in 0..<6 {
            scheduler.enqueue(priority: .visible) { _ in
                lock.lock(); concurrent += 1; peak = max(peak, concurrent); lock.unlock()
                Thread.sleep(forTimeInterval: 0.03)
                lock.lock(); concurrent -= 1; done += 1; lock.unlock()
            }
        }
        check(waitUntil { lock.lock(); defer { lock.unlock() }; return done == 6 }, "6개 완료")
        lock.lock(); let p = peak; lock.unlock()
        check(p >= 1 && p <= 2, "최대 동시 실행 수가 워커 수를 넘지 않음 (peak=\(p))")
    }
}
