# 썸네일 캐시 재설계 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 2만 장 폴더에서 보이는 화면이 2초 안에 채워지고, 앱을 다시 켜도 썸네일이 즉시 뜨며, iCloud 폴더를 훑어도 원본을 내려받지 않는다.

**Architecture:** `ThumbnailProvider`(메모리 캐시 + 디스크 캐시 + 우선순위 워커 큐)를 신설하고, 그리드 셀이 화면에 나타날 때 요청하고 사라질 때 취소하는 "당겨 가기"로 바꾼다. 디스크 캐시는 경로 해시·mtime·크기·px 단계를 키로 써서 무효화가 저절로 되게 한다. iCloud 비워진 파일은 메타데이터로 판별해 생성 경로를 타지 않는다.

**Tech Stack:** Swift 5.9+, AppKit, ImageIO, CryptoKit, QuickLookThumbnailing(스파이크 결과에 따라). 빌드는 `Makefile` + `swiftc` 직결. 테스트 프레임워크 없음(단순 실행 파일).

**Spec:** `docs/thumbnail-cache-design.md`

**검토 반영(2026-10-16):** ① DiskStore 락은 카운터만 보호, 디코드·인코드·GC는 락 밖(GC는 utility 직렬 큐, `limitBytes` setter·`clear()`는 호출자를 막지 않음) ② 같은 우선순위 LIFO → FIFO ③ 스켈레톤 `beginTime = 1`로 위상 동기화 ④ Scheduler `cancel()`이 완료 토큰을 `cancelled`에 남기지 않음 ⑤ `finish`는 대기자 유무와 무관하게 캐시에 먼저 저장 ⑥ 실패·미다운로드 자리표시는 `hasThumbnail = true`(재요청·깜빡임 없음) ⑦ 스파이크에 소요 시간 측정 ⑧ 워커 수 테스트는 상한 검증. 테스트 수: 스케줄러 6 · Provider 7(+2) · DiskStore 10. ⑨(구현 중 발견) 선로드→visible 승격은 `Scheduler.reprioritize`로, 실행 중이면 재디코딩하지 않음.

## Global Constraints

- 최소 macOS 14.0 (`Info.plist` `LSMinimumSystemVersion`). async/await·`AVAssetImageGenerator.image(at:)` 사용 가능.
- 외부 패키지 없음. 빌드는 `make build`(`swiftc -O` 전체 소스 한 번에). 새 파일은 `Sources/` 아래에 두면 자동 포함.
- 디스크 캐시 위치: `~/Library/Caches/com.jenalab.jenaimage/thumbs/`. 저장 포맷 HEIC.
- 디스크 한도 기본 2048MB, 범위 500...8192MB, 500MB 단위. "적용" 없이 즉시 반영.
- 워커 수 `activeProcessorCount - 1`, 최소 2, 최대 8.
- 크기 단계 220/330/440 (`AppSettings.ThumbnailMaxPixel`과 동일 값).
- iCloud 비워진 파일에 `CGImageSourceCreateWithURL`·`NSImage(contentsOf:)`를 절대 부르지 않는다. 선로드는 건너뛴다.
- 기존 동작 유지: 크기 3단계, 메모리 한도 슬라이더와 "적용", 북마크 그리드, 하위 폴더 경로 줄, 승격 규칙(큰 썸네일을 작은 걸로 덮지 않음).
- 코드 주석·devlog는 한국어, 식별자는 영어. 설정 탭 라벨은 기존 탭처럼 한국어 하드코딩(탭 이름만 `L10n`).
- 작업 끝에 `docs/devlog/2026-10-15.md`(또는 실제 작업일)에 섹션 추가.

## Review Focus

1. **스크롤 중 셀 재사용으로 다른 파일 썸네일이 잠깐 보임** — (2026-10-16 추가) 반대 방향도 있다: `didEndDisplaying`이 재사용 뒤에 와서 새 요청을 끊으면 셀이 스켈레톤으로 남는다. 취소는 `representedURL == contents[indexPath].url`일 때만, 선로드 패스에서 비어 있는 보이는 셀을 재요청(자가 치유). — 셀이 재사용되면 이전 요청 결과가 새 파일 자리에 그려지면 안 된다. → Task 3 `BrowserItem` 테스트는 UI라 자동화 불가, Task 4 Step 7 수동 검증 항목으로 고정하고, 코드상 `representedURL` 비교를 완료 콜백에 둔다.
2. **같은 파일을 그리드와 스트립이 동시에 요청** — 생성은 한 번, 두 완료가 모두 와야 한다. → Task 2 `testProviderCoalescesSameKey`.
3. **mtime은 같고 크기만 다른 파일(일부 복사 도구가 mtime 보존)** — 키에 size가 들어 있어 다른 항목으로 취급해야 한다. → Task 6 `testKeyChangesWithSize`.
4. **디스크 한도를 사용량보다 낮게 내렸을 때** — 즉시 GC가 돌아 90%까지 내려가야 한다. → Task 6 `testLoweringLimitTriggersGC`.
5. **취소된 요청이 큐에 쌓여 있을 때** — 워커가 꺼내며 버려야지 실행하면 안 된다(2만 장 휙 넘기기). → Task 1 `testCancelledEntryIsSkipped`.

---

### Task 0: 스파이크 — iCloud 비워진 파일에 QLThumbnailGenerator가 다운로드 없이 그림을 주는가

**Files:**
- Create (throwaway, 커밋 안 함): `/tmp/spike-icloud/spike.swift`
- Modify: `docs/devlog/2026-10-16-spike-icloud.md` (결과 기록 — 2026-10-16 완료, 결정 **true**)

**Interfaces:**
- Produces: 결정 하나 — `useQuickLookForEvicted: Bool`. Task 2 Step 9에서 이 값에 따라 분기 코드를 넣는다.

- [x] **Step 1: 비워진 iCloud 파일 하나 준비**

iCloud Drive 안의 이미지 파일을 골라 비운다. 경로는 실제 파일로 바꾼다.

```bash
brctl evict "$HOME/Library/Mobile Documents/com~apple~CloudDocs/사진/sample.jpg"
sleep 2
xattr -l "$HOME/Library/Mobile Documents/com~apple~CloudDocs/사진/sample.jpg" | head
```
Expected: 비워진 파일은 크기가 0에 가깝고 `.icloud` 자리표시로 보이거나 `brctl` 출력에 evicted 표시.

- [x] **Step 2: 스파이크 스크립트 작성**

```swift
// /tmp/spike-icloud/spike.swift
import Foundation
import QuickLookThumbnailing

let url = URL(fileURLWithPath: CommandLine.arguments[1])

func status() -> String {
    let rv = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
    return "ubiquitous=\(rv?.isUbiquitousItem ?? false) status=\(rv?.ubiquitousItemDownloadingStatus?.rawValue ?? "nil")"
}

print("before:", status())
let req = QLThumbnailGenerator.Request(
    fileAt: url, size: CGSize(width: 220, height: 220), scale: 2, representationTypes: .thumbnail
)
let sem = DispatchSemaphore(value: 0)
let started = Date()
QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, err in
    let elapsed = Date().timeIntervalSince(started)
    if let rep { print("rep: \(rep.cgImage.width)x\(rep.cgImage.height) type=\(rep.type.rawValue) elapsed=\(String(format: "%.2f", elapsed))s") }
    else { print("rep: nil err=\(err?.localizedDescription ?? "nil") elapsed=\(String(format: "%.2f", elapsed))s") }
    sem.signal()
}
sem.wait()
sleep(1)
print("after:", status())
```

소요 시간도 같이 잰다. Provider의 QuickLook 경로는 세마포어로 워커 하나를 묶는 구조라, iCloud 썸네일 fetch가 네트워크를 타서 수 초 걸리면 그 시간만큼 워커가 빠진다. 2초를 넘기면 `true`라도 Task 2 Step 9에서 QuickLook 전용 워커 1개를 따로 두는 쪽으로 조정한다.

- [x] **Step 3: 빌드·실행**

```bash
mkdir -p /tmp/spike-icloud
swiftc -framework QuickLookThumbnailing /tmp/spike-icloud/spike.swift -o /tmp/spike-icloud/spike
/tmp/spike-icloud/spike "$HOME/Library/Mobile Documents/com~apple~CloudDocs/사진/sample.jpg"
```
Expected 둘 중 하나:
- `rep: 440x…` 이고 `after: … status=NSURLUbiquitousItemDownloadingStatusNotDownloaded` → **useQuickLookForEvicted = true**
- `rep: nil` 이거나 `after` 상태가 `Current`로 바뀜(다운로드 유발) → **useQuickLookForEvicted = false**

- [x] **Step 4: devlog에 결과 기록**

`docs/devlog/2026-10-15.md` 끝에 섹션 추가:

```markdown
# 2026-10-15 (추가) — 스파이크: iCloud 비워진 파일 + QLThumbnailGenerator

- 대상: <파일 경로>, 사전 상태 NotDownloaded.
- 결과: rep=<값>, 사후 상태=<값>, 소요=<초>.
- 결정: useQuickLookForEvicted = <true/false>. 썸네일 캐시 재설계 Task 2에 반영.
```

- [ ] **Step 5: 커밋**

```bash
git add docs/devlog/2026-10-15.md
git commit -m "docs: iCloud evicted-file QuickLook thumbnail spike result"
```

---

### Task 1: 테스트 하네스 + ThumbnailScheduler

**Files:**
- Create: `Sources/services/ThumbnailScheduler.swift`
- Create: `Tests/TestSupport.swift`
- Create: `Tests/ThumbnailSchedulerTests.swift`
- Create: `Tests/main.swift`
- Modify: `Makefile` (`test` 타깃 추가)

**Interfaces:**
- Produces:
  ```swift
  enum ThumbnailPriority: Int, Comparable { case background = 0, prefetch = 1, visible = 2 }
  final class ThumbnailScheduler {
      struct Token: Hashable { let id: UInt64 }
      init(workerCount: Int)
      /// work는 워커 스레드에서 실행. isCancelled()로 중간 확인 가능.
      @discardableResult
      func enqueue(priority: ThumbnailPriority, work: @escaping (_ isCancelled: () -> Bool) -> Void) -> Token
      func cancel(_ token: Token)
      func cancelAll()
      /// 대기 중이면 우선순위만 바꾸고 true, 실행 중·완료면 false(호출자는 취소·재등록하지 않는다). 2026-10-16 추가
      @discardableResult func reprioritize(_ token: Token, to priority: ThumbnailPriority) -> Bool
      var pendingCount: Int { get }
      var cancelledCount: Int { get }   // 테스트용. 실행 중 취소 표시가 남아 있는 수
  }
  ```
- 꺼내는 순서: 우선순위 높은 것 → 같은 우선순위는 **들어온 순서(FIFO)**. 스펙 초안의 "최신 먼저(LIFO)"는 쓰지 않는다. `didEndDisplaying`이 화면을 벗어난 셀을 즉시 취소하므로 `visible` 큐에는 지금 보이는 셀만 남고, 선로드도 새 선로드 때 이전 토큰을 전부 취소한다. 그래서 LIFO가 주는 이득이 없고, 첫 화면이 아래에서 위로 채워지는 부작용만 남는다.

- [x] **Step 1: 테스트 지원 파일과 main 작성**

```swift
// Tests/TestSupport.swift
import Foundation

var failureCount = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #file, line: Int = #line) {
    if !condition() {
        failureCount += 1
        print("❌ \(message)  (\((file as NSString).lastPathComponent):\(line))")
    }
}

func checkEqual<T: Equatable>(_ a: T, _ b: T, _ message: String, file: String = #file, line: Int = #line) {
    if a != b {
        failureCount += 1
        print("❌ \(message): \(a) != \(b)  (\((file as NSString).lastPathComponent):\(line))")
    }
}

func runTest(_ name: String, _ body: () -> Void) {
    let before = failureCount
    body()
    print(before == failureCount ? "✅ \(name)" : "💥 \(name)")
}

/// 조건이 참이 될 때까지 최대 timeout초 동안 메인 런루프를 돌린다(메인 큐 콜백 수신용).
func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return condition()
}
```

```swift
// Tests/main.swift
import Foundation

runSchedulerTests()

if failureCount > 0 {
    print("\(failureCount) failure(s)")
    exit(1)
}
print("all tests passed")
```

- [x] **Step 2: Makefile에 test 타깃 추가**

`.PHONY` 줄과 `clean` 아래에 추가:

```makefile
.PHONY: build run clean install pkg dmg test

TEST_SOURCES = Sources/services/ThumbnailScheduler.swift \
               Sources/services/ThumbnailCache.swift \
               $(shell find Tests -name '*.swift')

test:
	@mkdir -p $(BUILD_DIR)
	swiftc -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers $(TEST_SOURCES) -o $(BUILD_DIR)/tests
	@$(BUILD_DIR)/tests
```

- [x] **Step 3: 실패하는 테스트 작성**

```swift
// Tests/ThumbnailSchedulerTests.swift
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
```

- [x] **Step 4: 테스트 실행 → 실패 확인**

Run: `make test`
Expected: 컴파일 에러. (실제로는 `TEST_SOURCES`에 아직 없는 파일이 올라 있어 `error opening input file`로 먼저 멈춘다. `Tests/*.swift`만 `swiftc`로 컴파일하면 `cannot find 'ThumbnailScheduler' in scope`가 난다. 2026-10-16 확인)

- [x] **Step 5: Scheduler 구현**

```swift
// Sources/services/ThumbnailScheduler.swift
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
```

- [x] **Step 6: 테스트 실행 → 통과 확인**

Run: `make test`
Expected: `✅` 5줄, `all tests passed`

- [x] **Step 7: 앱 빌드도 깨지지 않는지 확인**

Run: `make build`
Expected: 에러 없음

- [ ] **Step 8: 커밋**

```bash
git add Makefile Tests Sources/services/ThumbnailScheduler.swift
git commit -m "feat: ThumbnailScheduler priority worker queue + test harness"
```

---

### Task 2: ThumbnailProvider (메모리 계층 + 생성 큐 + 중복 합치기 + iCloud 판별)

**Files:**
- Create: `Sources/services/ThumbnailProvider.swift`
- Create: `Sources/services/ThumbnailProvider+App.swift`
- Modify: `Sources/services/ImageService.swift:98-112` (`generateThumbnailSync` 추가)
- Create: `Tests/ThumbnailProviderTests.swift`
- Modify: `Tests/main.swift`, `Makefile` (`TEST_SOURCES`)

**Interfaces:**
- Consumes: `ThumbnailScheduler`, `ThumbnailPriority` (Task 1), `ThumbnailCache` (기존).
- Produces:
  ```swift
  enum ThumbnailResult { case image(NSImage), failed, notDownloaded }
  struct ThumbnailRequestToken: Hashable
  @MainActor final class ThumbnailProvider {
      static let shared: ThumbnailProvider   // +App.swift
      static let levels = [220, 330, 440]
      init(workerCount: Int, memoryCache: ThumbnailCache, generate: @escaping (URL, CGSize) -> NSImage?)
      func cachedThumbnail(for url: URL, minPixel: Int) -> NSImage?
      /// 메모리 적중이면 completion을 동기 호출하고 nil 반환(취소할 것이 없음).
      func request(_ url: URL, minPixel: Int, priority: ThumbnailPriority,
                   completion: @escaping (ThumbnailResult) -> Void) -> ThumbnailRequestToken?
      func cancel(_ token: ThumbnailRequestToken)
      func cancelAllPending()
      func invalidate(for url: URL)
      func clearMemory()
      func setMemoryLimit(bytes: Int)
      /// 테스트·스파이크 분기용. +App.swift에서 Task 0 결정값으로 설정.
      var useQuickLookForEvicted: Bool
  }
  ```
  `ImageService.generateThumbnailSync(at:size:) -> Result<NSImage, ImageServiceError>` (동기, 워커 스레드용).

- [x] **Step 1: 실패하는 테스트 작성**

```swift
// Tests/ThumbnailProviderTests.swift
import AppKit

private func makeImage(px: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: px, height: px))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    img.addRepresentation(rep)
    return img
}

@MainActor
func runProviderTests() {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("provider-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let fileA = tmp.appendingPathComponent("a.jpg")
    let fileB = tmp.appendingPathComponent("b.jpg")
    FileManager.default.createFile(atPath: fileA.path, contents: Data([1, 2, 3]))
    FileManager.default.createFile(atPath: fileB.path, contents: Data([4, 5, 6]))

    runTest("testProviderCoalescesSameKey: 같은 URL 두 요청 → 생성 1회, 완료 2회") {
        let gate = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var generateCalls = 0
        let provider = ThumbnailProvider(workerCount: 1, memoryCache: ThumbnailCache(memoryLimit: 50_000_000)) { _, _ in
            gate.wait()
            lock.lock(); generateCalls += 1; lock.unlock()
            return makeImage(px: 440)
        }
        var completions = 0
        let t1 = provider.request(fileA, minPixel: 440, priority: .visible) { if case .image = $0 { completions += 1 } }
        let t2 = provider.request(fileA, minPixel: 440, priority: .visible) { if case .image = $0 { completions += 1 } }
        check(t1 != nil && t2 != nil, "둘 다 비동기 토큰")
        gate.signal()
        check(waitUntil { completions == 2 }, "완료 2회")
        lock.lock(); let calls = generateCalls; lock.unlock()
        checkEqual(calls, 1, "생성 호출 수")
    }

    runTest("메모리 적중은 동기 완료 + nil 토큰") {
        let cache = ThumbnailCache(memoryLimit: 50_000_000)
        cache.store(makeImage(px: 440), for: fileA)
        let provider = ThumbnailProvider(workerCount: 1, memoryCache: cache) { _, _ in makeImage(px: 440) }
        var got = false
        let token = provider.request(fileA, minPixel: 440, priority: .visible) { if case .image = $0 { got = true } }
        check(token == nil, "토큰 nil")
        check(got, "동기 완료")
    }

    runTest("작은 썸네일만 있으면 큰 요청은 재생성한다(승격)") {
        let cache = ThumbnailCache(memoryLimit: 50_000_000)
        cache.store(makeImage(px: 220), for: fileA)
        let provider = ThumbnailProvider(workerCount: 1, memoryCache: cache) { _, _ in makeImage(px: 440) }
        var px = 0
        let token = provider.request(fileA, minPixel: 440, priority: .visible) {
            if case .image(let img) = $0 { px = img.representations.first!.pixelsWide }
        }
        check(token != nil, "비동기 토큰")
        check(waitUntil { px == 440 }, "440으로 재생성")
    }

    runTest("취소 후에는 완료가 오지 않는다") {
        let gate = DispatchSemaphore(value: 0)
        let provider = ThumbnailProvider(workerCount: 1, memoryCache: ThumbnailCache(memoryLimit: 50_000_000)) { _, _ in
            gate.wait(); return makeImage(px: 440)
        }
        var completed = false
        provider.request(fileB, minPixel: 440, priority: .visible) { _ in }  // 워커 점유
        Thread.sleep(forTimeInterval: 0.05)
        let token = provider.request(fileA, minPixel: 440, priority: .visible) { _ in completed = true }!
        provider.cancel(token)
        gate.signal(); gate.signal()
        _ = waitUntil(timeout: 0.3) { false }
        check(!completed, "취소된 요청은 완료되지 않음")
    }

    runTest("생성 실패는 .failed, 같은 파일 재요청 시 생성을 다시 부르지 않는다") {
        let lock = NSLock()
        var calls = 0
        let provider = ThumbnailProvider(workerCount: 1, memoryCache: ThumbnailCache(memoryLimit: 50_000_000)) { _, _ in
            lock.lock(); calls += 1; lock.unlock(); return nil
        }
        var results: [ThumbnailResult] = []
        provider.request(fileA, minPixel: 440, priority: .visible) { results.append($0) }
        check(waitUntil { results.count == 1 }, "첫 완료")
        provider.request(fileA, minPixel: 440, priority: .visible) { results.append($0) }
        check(waitUntil { results.count == 2 }, "둘째 완료")
        if case .failed = results[0] {} else { check(false, "첫 결과 failed") }
        if case .failed = results[1] {} else { check(false, "둘째 결과 failed") }
        lock.lock(); let c = calls; lock.unlock()
        checkEqual(c, 1, "생성 호출 수")
    }

    runTest("minPixel을 단계로 올림: 160 → 220, 441 → 440(최대)") {
        checkEqual(ThumbnailProvider.level(forMinPixel: 160), 220, "160")
        checkEqual(ThumbnailProvider.level(forMinPixel: 220), 220, "220")
        checkEqual(ThumbnailProvider.level(forMinPixel: 300), 330, "300")
        checkEqual(ThumbnailProvider.level(forMinPixel: 441), 440, "441")
    }

    try? FileManager.default.removeItem(at: tmp)
}
```

`Tests/main.swift`를 다음으로 교체:

```swift
import Foundation

runSchedulerTests()
MainActor.assumeIsolated { runProviderTests() }

if failureCount > 0 {
    print("\(failureCount) failure(s)")
    exit(1)
}
print("all tests passed")
```

`Makefile`의 `TEST_SOURCES`에 `Sources/services/ThumbnailProvider.swift` 추가(`+App.swift`는 넣지 않는다 — `ImageService`에 의존).

- [x] **Step 2: 테스트 실행 → 실패 확인**

Run: `make test`
Expected: 컴파일 에러(`TEST_SOURCES`에 먼저 올리면 `error opening input file`로 멈춘다 — Task 1과 같음. 2026-10-16 확인)

- [x] **Step 3: Provider 구현**

```swift
// Sources/services/ThumbnailProvider.swift
import AppKit

enum ThumbnailResult {
    case image(NSImage)
    case failed
    case notDownloaded
}

struct ThumbnailRequestToken: Hashable {
    fileprivate let id: UInt64
    fileprivate let key: ThumbnailProvider.Key
}

/// 썸네일 공급자. 메모리 캐시 → (디스크 캐시) → 생성 순으로 찾고, 같은 (url, 크기)의 동시 요청은 생성 한 번으로 합친다.
/// 모든 공개 메서드는 메인 스레드에서 부른다. 워커 완료는 메인으로 돌아와 테이블을 갱신한다.
@MainActor
final class ThumbnailProvider {
    /// 워커 스레드(nonisolated)에서도 읽으므로 격리에서 뺀다.
    nonisolated static let levels = [220, 330, 440]

    struct Key: Hashable {
        let url: URL
        let level: Int
    }

    private struct Waiter {
        let id: UInt64
        let completion: (ThumbnailResult) -> Void
    }

    private final class InFlight {
        var schedulerToken: ThumbnailScheduler.Token?
        var waiters: [Waiter] = []
        var priority: ThumbnailPriority
        init(priority: ThumbnailPriority) { self.priority = priority }
    }

    private let memoryCache: ThumbnailCache
    private let scheduler: ThumbnailScheduler
    private let generate: (URL, CGSize) -> NSImage?
    private var inFlight: [Key: InFlight] = [:]
    private var nextWaiterID: UInt64 = 0
    /// (경로, mtime) 별 실패 기억 — 같은 세션에서 깨진 파일을 다시 디코딩하지 않는다.
    private var failedKeys: Set<String> = []

    /// Task 0 스파이크 결과. true면 iCloud 비워진 파일의 visible 요청에 QuickLook 썸네일을 시도한다.
    var useQuickLookForEvicted = false

    init(workerCount: Int, memoryCache: ThumbnailCache, generate: @escaping (URL, CGSize) -> NSImage?) {
        self.memoryCache = memoryCache
        self.scheduler = ThumbnailScheduler(workerCount: workerCount)
        self.generate = generate
    }

    nonisolated static func level(forMinPixel minPixel: Int) -> Int {
        levels.first { $0 >= minPixel } ?? levels.last!
    }

    // MARK: - Public

    func cachedThumbnail(for url: URL, minPixel: Int) -> NSImage? {
        memoryCache.thumbnail(for: url, minPixelSize: minPixel)
    }

    @discardableResult
    func request(_ url: URL, minPixel: Int, priority: ThumbnailPriority,
                 completion: @escaping (ThumbnailResult) -> Void) -> ThumbnailRequestToken? {
        if let hit = memoryCache.thumbnail(for: url, minPixelSize: minPixel) {
            completion(.image(hit))
            return nil
        }
        let level = Self.level(forMinPixel: minPixel)
        let key = Key(url: url, level: level)
        nextWaiterID += 1
        let waiter = Waiter(id: nextWaiterID, completion: completion)
        let token = ThumbnailRequestToken(id: waiter.id, key: key)

        if let existing = inFlight[key] {
            existing.waiters.append(waiter)
            // 선로드로 들어가 있던 항목이 보이게 되면 우선순위만 올린다. 이미 워커가 디코딩 중이면(reprioritize가 false)
            // 그대로 기다린다 — 취소·재등록은 한 디코딩을 버리고 두 번 하는 셈이다. (2026-10-16 검토에서 수정)
            if priority > existing.priority {
                existing.priority = priority
                if let t = existing.schedulerToken { scheduler.reprioritize(t, to: priority) }
            }
            return token
        }

        let entry = InFlight(priority: priority)
        entry.waiters = [waiter]
        inFlight[key] = entry
        entry.schedulerToken = schedule(key: key, priority: priority)
        return token
    }

    func cancel(_ token: ThumbnailRequestToken) {
        guard let entry = inFlight[token.key] else { return }
        entry.waiters.removeAll { $0.id == token.id }
        if entry.waiters.isEmpty {
            if let t = entry.schedulerToken { scheduler.cancel(t) }
            inFlight.removeValue(forKey: token.key)
        }
    }

    func cancelAllPending() {
        scheduler.cancelAll()
        inFlight.removeAll()
    }

    func invalidate(for url: URL) {
        memoryCache.invalidate(for: url)
        failedKeys = failedKeys.filter { !$0.hasPrefix(url.path + "|") }
    }

    func clearMemory() {
        memoryCache.clearAll()
        failedKeys.removeAll()
    }

    func setMemoryLimit(bytes: Int) {
        memoryCache.setMemoryLimit(bytes: bytes)
    }

    // MARK: - Pipeline

    private func schedule(key: Key, priority: ThumbnailPriority) -> ThumbnailScheduler.Token {
        let generate = self.generate
        let useQL = useQuickLookForEvicted
        let failedSnapshot = failedKeys
        return scheduler.enqueue(priority: priority) { [weak self] isCancelled in
            let outcome = Self.produce(key: key, priority: priority, useQuickLook: useQL,
                                       failedKeys: failedSnapshot, generate: generate)
            if isCancelled() { return }
            Task { @MainActor [weak self] in
                self?.finish(key: key, outcome: outcome)
            }
        }
    }

    private enum Outcome {
        case image(NSImage, store: Bool)
        case failed(fileStamp: String)
        case notDownloaded
    }

    /// 워커 스레드에서 실행. 디스크 조회는 Task 7에서 이 안에 끼운다.
    nonisolated private static func produce(key: Key, priority: ThumbnailPriority, useQuickLook: Bool,
                                            failedKeys: Set<String>,
                                            generate: (URL, CGSize) -> NSImage?) -> Outcome {
        let url = key.url
        let stamp = fileStamp(url)
        if failedKeys.contains(stamp) { return .failed(fileStamp: stamp) }

        if isEvictedICloudItem(url) {
            if priority == .visible, useQuickLook, let img = quickLookThumbnail(url: url, level: key.level) {
                return .image(img, store: false)
            }
            return .notDownloaded
        }

        let pt = CGFloat(key.level) / 2  // 생성 시 레티나 2배
        if let img = generate(url, CGSize(width: pt, height: pt)) {
            return .image(img, store: true)
        }
        return .failed(fileStamp: stamp)
    }

    private func finish(key: Key, outcome: Outcome) {
        // 캐시·실패 기억은 대기자가 남아 있든 없든 반영한다. cancelAllPending()으로 entry가 사라진 뒤 도착한
        // 결과도 이미 디코딩을 마친 것이라, 버리면 폴더를 다시 열 때 같은 비용을 두 번 낸다.
        let result: ThumbnailResult
        switch outcome {
        case .image(let img, let store):
            if store { memoryCache.store(img, for: key.url) }
            result = .image(img)
        case .failed(let stamp):
            failedKeys.insert(stamp)
            result = .failed
        case .notDownloaded:
            result = .notDownloaded
        }
        guard let entry = inFlight.removeValue(forKey: key) else { return }
        for w in entry.waiters { w.completion(result) }
    }

    // MARK: - File helpers (워커 스레드)

    /// `URL.resourceValues`는 같은 인스턴스에 캐시되고, 그 캐시는 런루프 끝에서만 비워진다. 워커 스레드엔 런루프가
    /// 없어 영원히 옛 값이 돌아온다(Task 0 스파이크에서 확인). 그래서 읽을 때마다 새 인스턴스를 만든다.
    nonisolated private static func freshURL(_ url: URL) -> URL {
        URL(fileURLWithPath: url.path)
    }

    nonisolated private static func fileStamp(_ url: URL) -> String {
        let rv = try? freshURL(url).resourceValues(forKeys: [.contentModificationDateKey])
        let mtime = Int(rv?.contentModificationDate?.timeIntervalSince1970 ?? 0)
        return url.path + "|" + String(mtime)
    }

    /// iCloud Drive가 관리하고 아직 로컬에 없는 파일인지. 메타데이터 조회만 하며 다운로드를 유발하지 않는다.
    /// macOS 26에선 비워진 파일도 원래 이름의 dataless 파일로 보이므로(`.icloud` 자리표시 없음) 파일명으로 판별하면 안 된다.
    nonisolated static func isEvictedICloudItem(_ url: URL) -> Bool {
        guard let rv = try? freshURL(url).resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              rv.isUbiquitousItem == true else { return false }
        return rv.ubiquitousItemDownloadingStatus == .notDownloaded
    }

    nonisolated private static func quickLookThumbnail(url: URL, level: Int) -> NSImage? {
        // Task 0 결과가 true일 때만 쓰인다. Task 2 Step 9에서 채운다.
        return nil
    }
}
```

- [x] **Step 4: 테스트 실행 → 통과 확인**

Run: `make test`
Expected: Scheduler 6개 + Provider 7개 `✅`, `all tests passed` (승격 테스트 1개가 2026-10-16 검토에서 추가됨)

- [x] **Step 5: ImageService에 동기 생성 추가**

`Sources/services/ImageService.swift`의 `generateThumbnail(at:size:)` 바로 아래에 추가:

```swift
    /// 워커 스레드용 동기 생성. 이미지는 바로 디코딩하고, 영상은 AVAssetImageGenerator(비동기)를 세마포어로 기다린다.
    /// 메인 스레드에서 부르면 안 된다.
    func generateThumbnailSync(at url: URL, size: CGSize) -> Result<NSImage, ImageServiceError> {
        let ext = url.pathExtension.lowercased()
        if ImageFile.videoExtensions.contains(ext) {
            // 동시 실행 컨텍스트에서 캡처한 var를 바꿀 수 없어 상자로 감싼다.
            final class Box: @unchecked Sendable { var value: Result<NSImage, ImageServiceError> }
            let box = Box(value: .failure(.thumbnailFailed(url)))
            let sem = DispatchSemaphore(value: 0)
            Task.detached { [self] in
                box.value = await generateVideoThumbnail(at: url, size: size)
                sem.signal()
            }
            sem.wait()
            return box.value
        }
        return generateImageThumbnailSync(at: url, size: size)
    }
```

- [x] **Step 6: 앱용 shared 인스턴스**

```swift
// Sources/services/ThumbnailProvider+App.swift
import AppKit

extension ThumbnailProvider {
    /// 워커 수: 코어 - 1, 최소 2, 최대 8.
    static var defaultWorkerCount: Int {
        min(8, max(2, ProcessInfo.processInfo.activeProcessorCount - 1))
    }

    static let shared: ThumbnailProvider = {
        let service = ImageService()
        let provider = ThumbnailProvider(
            workerCount: defaultWorkerCount,
            memoryCache: .shared
        ) { url, size in
            if case .success(let img) = service.generateThumbnailSync(at: url, size: size) { return img }
            return nil
        }
        provider.useQuickLookForEvicted = true  // Task 0 스파이크 결과(docs/devlog/2026-10-16-spike-icloud.md)
        return provider
    }()
}
```

- [x] **Step 7: 빌드 확인**

Run: `make build`
Expected: 에러 없음. (`ThumbnailProvider`는 `@MainActor`라 `static let shared` 접근도 메인에서만 — 호출처는 전부 메인.)

- [ ] **Step 8: 커밋**

```bash
git add Sources/services/ThumbnailProvider.swift Sources/services/ThumbnailProvider+App.swift Sources/services/ImageService.swift Tests Makefile
git commit -m "feat: ThumbnailProvider with memory layer, coalescing, cancel, iCloud eviction check"
```

- [x] **Step 9 (Task 0 결과 = true → 실행한다): QuickLook 경로 채우기**

`Makefile` `FRAMEWORKS`에 `-framework QuickLookThumbnailing` 추가. `ThumbnailProvider.swift` 상단에 `import QuickLookThumbnailing`, `quickLookThumbnail` 본문 교체:

```swift
    nonisolated private static func quickLookThumbnail(url: URL, level: Int) -> NSImage? {
        let pt = CGFloat(level) / 2
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: pt, height: pt),
                                               scale: 2, representationTypes: .thumbnail)
        let sem = DispatchSemaphore(value: 0)
        var image: NSImage?
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            if let cg = rep?.cgImage {
                image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
            sem.signal()
        }
        sem.wait()
        return image
    }
```

`+App.swift`의 `useQuickLookForEvicted = true`. 테스트 빌드(`make test`)에도 `-framework QuickLookThumbnailing` 추가. `make build && make test` 통과 후:

```bash
git commit -am "feat: QuickLook thumbnails for evicted iCloud files (visible cells only)"
```

---

### Task 3: BrowserItem 상태 — 스켈레톤·실패·iCloud 미다운로드

**Files:**
- Modify: `Sources/browser/BrowserItem.swift`

**Interfaces:**
- Consumes: `ThumbnailRequestToken`, `ThumbnailResult` (Task 2).
- Produces:
  ```swift
  extension BrowserItem {
      var representedURL: URL? { get }          // configure에서 설정
      var thumbnailToken: ThumbnailRequestToken? // BrowserViewController가 보관·취소
      var hasThumbnail: Bool { get }             // 이미지·실패·미다운로드·폴더 모두 true(= 더 요청할 것 없음). 스켈레톤만 false
      func showSkeleton()
      func showThumbnail(_ image: NSImage, animated: Bool)
      func showThumbnailResult(_ result: ThumbnailResult)   // .image → showThumbnail(animated: true)
  }
  ```

- [x] **Step 1: 프로퍼티와 스켈레톤 레이어 추가**

`BrowserItem` 클래스 상단 프로퍼티 블록(`private var isHovered = false` 아래)에 추가:

```swift
    /// 현재 셀이 표시 중인 파일. 완료 콜백이 다른 파일 자리에 그려지는 걸 막는 비교 기준.
    private(set) var representedURL: URL?
    /// 진행 중인 썸네일 요청. 셀이 화면에서 사라지거나 재사용될 때 BrowserViewController가 취소한다.
    var thumbnailToken: ThumbnailRequestToken?
    private(set) var hasThumbnail = false
    private var isVideo = false

    private let skeletonLayer = CALayer()
    /// 모든 셀이 같은 위상으로 숨 쉬도록 공유하는 애니메이션.
    private static let skeletonPulse: CABasicAnimation = {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 0.6
        a.toValue = 1.0
        a.duration = 0.8
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        // beginTime이 0이면 CA가 add 시점의 현재 시각으로 바꿔 넣어 셀마다 위상이 어긋난다.
        // 0이 아닌 고정 상수를 주면 모든 레이어가 같은 절대 기준(부팅 후 1초)으로 위상을 계산해 동기화된다.
        a.beginTime = 1
        return a
    }()
```

`setupThumbnailView()` 끝(제약 활성화 뒤)에 추가:

```swift
        skeletonLayer.cornerRadius = 6
        skeletonLayer.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        skeletonLayer.isHidden = true
        thumbnailView.layer?.addSublayer(skeletonLayer)
```

`viewDidLayout()`에 추가:

```swift
        skeletonLayer.frame = thumbnailView.bounds
```

- [x] **Step 2: 상태 메서드 추가**

`updateThumbnail(_:)`을 다음으로 교체:

```swift
    // MARK: - Thumbnail States

    func showSkeleton() {
        hasThumbnail = false
        thumbnailView.image = nil
        thumbnailView.contentTintColor = nil
        thumbnailView.imageScaling = .scaleProportionallyDown
        skeletonLayer.isHidden = false
        skeletonLayer.opacity = 1
        if skeletonLayer.animation(forKey: "pulse") == nil {
            skeletonLayer.add(Self.skeletonPulse, forKey: "pulse")
        }
    }

    func showThumbnail(_ image: NSImage, animated: Bool) {
        hasThumbnail = true
        thumbnailView.imageScaling = .scaleProportionallyDown
        thumbnailView.contentTintColor = nil
        thumbnailView.image = image
        hideSkeleton(animated: animated)
    }

    func showThumbnailResult(_ result: ThumbnailResult) {
        switch result {
        case .image(let img):
            showThumbnail(img, animated: true)
        case .failed:
            showPlaceholder(symbol: isVideo ? "film" : "photo")
        case .notDownloaded:
            showPlaceholder(symbol: "icloud.and.arrow.down")
        }
    }

    private func showPlaceholder(symbol: String) {
        // 실패·미다운로드도 "완성 상태"로 둔다. 세션 내 재시도는 없다는 스펙(§3.3)이므로 셀이 다시 보일 때마다
        // 요청을 보내 스켈레톤 → 심볼로 깜빡일 이유가 없다. 편집 저장 등 invalidate 뒤에는 configure가 다시 돌아 초기화된다.
        hasThumbnail = true
        let config = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        thumbnailView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        thumbnailView.contentTintColor = .tertiaryLabelColor
        thumbnailView.imageScaling = .scaleNone
        hideSkeleton(animated: false)
    }

    private func hideSkeleton(animated: Bool) {
        skeletonLayer.removeAnimation(forKey: "pulse")
        guard animated, !skeletonLayer.isHidden else {
            skeletonLayer.isHidden = true
            return
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        CATransaction.setCompletionBlock { [skeletonLayer] in
            skeletonLayer.isHidden = true
            skeletonLayer.opacity = 1
        }
        skeletonLayer.opacity = 0
        CATransaction.commit()
    }
```

- [x] **Step 3: configure에서 상태 초기화**

`configure(with:thumbnail:isBookmarked:folderPath:)` 첫 줄에 추가:

```swift
        representedURL = content.url
        thumbnailToken = nil
        isVideo = false
```

`.folder` 분기 안 첫 줄에 `hideSkeleton(animated: false); hasThumbnail = true`(폴더는 심볼이 곧 완성 상태).

`.image(let file)` 분기에서:
- 깨진 북마크 분기(`!FileManager.default.fileExists`)의 끝에 `hideSkeleton(animated: false); hasThumbnail = true` (요청하지 않도록).
- `else if file.isVideo { ... }` 를 다음으로 교체:
  ```swift
            } else if file.isVideo {
                isVideo = true
                playBadge.isHidden = false
                if let thumbnail { showThumbnail(thumbnail, animated: false) } else { showSkeleton() }
            } else {
                if let thumbnail { showThumbnail(thumbnail, animated: false) } else { showSkeleton() }
            }
  ```

- [x] **Step 4: prepareForReuse에서 토큰 참조 끊기**

`prepareForReuse()`에 추가:

```swift
        representedURL = nil
        thumbnailToken = nil  // 취소 자체는 didEndDisplaying에서 BrowserViewController가 한다
```

- [x] **Step 5: 빌드 확인** (Task 4와 묶어 진행. 검토에서 추가: `hideSkeleton` 페이드 완료 블록에 세대 번호 가드 — 0.15초 안에 셀이 재사용되면 새 스켈레톤을 숨겨버리는 경쟁 방지. `showSkeleton`에서 배경색 재설정으로 다크·라이트 전환 반영.)

Run: `make build`
Expected: 에러 없음(아직 호출처는 `updateThumbnail`을 쓰므로 `BrowserViewController`에서 컴파일 에러가 나면 Task 4까지 같이 진행 — 그 경우 Step 6 커밋을 Task 4 Step 8과 합친다).

- [ ] **Step 6: 커밋**

```bash
git add Sources/browser/BrowserItem.swift
git commit -m "feat: BrowserItem skeleton/failed/not-downloaded thumbnail states"
```

---

### Task 4: BrowserViewController를 당겨 가기로 전환 + 선로드

**Files:**
- Modify: `Sources/browser/BrowserViewController.swift` (프로퍼티 181-191, `display` 209-229, `displayBookmarks` 231-244, `loadThumbnails`/`updateCellThumbnail` 295-329, `setupScrollView` 522-534, 데이터소스 622-650, delegate extension 668-)

**Interfaces:**
- Consumes: `ThumbnailProvider.shared`, `request/cancel/cancelAllPending/cachedThumbnail`, `BrowserItem.showSkeleton/showThumbnailResult/thumbnailToken/representedURL/hasThumbnail`.
- Produces: `init(imageService:thumbnailProvider:)` 시그니처(기존 `thumbnailCache:` 파라미터 제거).

- [x] **Step 1: 프로퍼티·init 교체**

```swift
    private var thumbnailMinPixelSize: Int { AppSettings.shared.thumbnailMaxPixel.rawValue }
    private var renameWorkItem: DispatchWorkItem?
    private var dropHighlightIndex: Int?
    /// 선로드(앞뒤 2화면) 요청 토큰. 다음 선로드 때 전부 취소하고 다시 건다.
    private var prefetchTokens: [ThumbnailRequestToken] = []
    private var prefetchWorkItem: DispatchWorkItem?

    private let imageService: ImageServiceProtocol
    private let thumbnailProvider: ThumbnailProvider

    /// 기본값을 `.shared`로 두면 기본 인자가 비격리 문맥에서 평가돼 MainActor 경고가 난다. nil을 받아 init 안에서 푼다. (2026-10-16 구현 중 수정)
    init(imageService: ImageServiceProtocol = ImageService(), thumbnailProvider: ThumbnailProvider? = nil) {
        self.imageService = imageService
        self.thumbnailProvider = thumbnailProvider ?? .shared
        super.init(nibName: nil, bundle: nil)
    }
```

`thumbnailRequestSize`, `thumbnailTask` 프로퍼티 삭제.

- [x] **Step 2: display / displayBookmarks에서 루프 제거**

`display(...)`: `thumbnailTask?.cancel()` → `cancelAllThumbnailRequests()`. 끝의 `loadThumbnails(for: imageItems)` 삭제, 대신 `schedulePrefetch()`.
`displayBookmarks(...)`: 같은 교체(`loadThumbnails(for: files)` 삭제 → `schedulePrefetch()`).

- [x] **Step 3: 로딩 블록 교체**

`// MARK: - Thumbnail Loading`부터 `updateCellThumbnail` 끝까지 다음으로 교체:

```swift
    // MARK: - Thumbnail Loading (당겨 가기)

    private func cancelAllThumbnailRequests() {
        prefetchWorkItem?.cancel()
        prefetchTokens.removeAll()
        thumbnailProvider.cancelAllPending()
        for case let item as BrowserItem in collectionView.visibleItems() {
            item.thumbnailToken = nil
        }
    }

    /// 셀이 화면에 들어올 때. 메모리 적중이면 동기 완료라 토큰이 nil로 돌아온다.
    private func requestThumbnail(for item: BrowserItem, url: URL) {
        guard !item.hasThumbnail, item.thumbnailToken == nil else { return }
        let token = thumbnailProvider.request(url, minPixel: thumbnailMinPixelSize, priority: .visible) { [weak item] result in
            guard let item, item.representedURL == url else { return }
            item.thumbnailToken = nil
            item.showThumbnailResult(result)
        }
        item.thumbnailToken = token
    }

    private func cancelThumbnail(for item: BrowserItem) {
        if let token = item.thumbnailToken {
            thumbnailProvider.cancel(token)
            item.thumbnailToken = nil
        }
    }

    /// 스크롤이 멈추고 0.1초 뒤, 보이는 범위 앞뒤 2화면 분량을 선로드한다.
    private func schedulePrefetch() {
        prefetchWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.prefetchAroundVisibleRect() }
        prefetchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func prefetchAroundVisibleRect() {
        for t in prefetchTokens { thumbnailProvider.cancel(t) }
        prefetchTokens.removeAll()

        let visible = collectionView.visibleRect
        guard visible.height > 0, let layout = collectionView.collectionViewLayout else { return }
        let extended = visible.insetBy(dx: 0, dy: -visible.height * 2)
        let visibleIndexes = Set(collectionView.indexPathsForVisibleItems())
        let targets = layout.layoutAttributesForElements(in: extended)
            .compactMap(\.indexPath)  // indexPath는 옵셔널
            .filter { !visibleIndexes.contains($0) }

        let minPixel = thumbnailMinPixelSize
        for indexPath in targets {
            guard let content = contents[safe: indexPath.item], case .image(let file) = content else { continue }
            // 선로드는 메모리 캐시에 채우기만 한다. 셀이 보이게 되면 willDisplay가 적중으로 받아 간다.
            if let token = thumbnailProvider.request(file.url, minPixel: minPixel, priority: .prefetch, completion: { _ in }) {
                prefetchTokens.append(token)
            }
        }
    }
```

- [x] **Step 4: 데이터소스에서 메모리 적중만 넘기기**

`collectionView(_:itemForRepresentedObjectAt:)`의 `thumbnail` 클로저를 교체:

```swift
        let thumbnail: NSImage? = {
            if case .image(let file) = content {
                return thumbnailProvider.cachedThumbnail(for: file.url, minPixel: thumbnailMinPixelSize)
            }
            return nil
        }()
```

- [x] **Step 5: delegate에 willDisplay / didEndDisplaying 추가**

`extension BrowserViewController: NSCollectionViewDelegate` 안, `pasteboardWriterForItemAt` 위에 추가:

```swift
    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem,
                        forRepresentedObjectAt indexPath: IndexPath) {
        guard let cell = item as? BrowserItem,
              let content = contents[safe: indexPath.item],
              case .image(let file) = content
        else { return }
        requestThumbnail(for: cell, url: file.url)
    }

    func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem,
                        forRepresentedObjectAt indexPath: IndexPath) {
        guard let cell = item as? BrowserItem else { return }
        cancelThumbnail(for: cell)
    }
```

- [x] **Step 6: 스크롤 멈춤 감지**

`setupScrollView()` 끝에 추가:

```swift
        // 스크롤이 멈추면 앞뒤 2화면 선로드. 프로그램 스크롤(선택 복원 등)도 bounds 변경으로 잡는다.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrollBoundsChanged), name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
```

클래스 안에 추가:

```swift
    @objc private func scrollBoundsChanged(_ note: Notification) {
        schedulePrefetch()
    }
```

`updateThumbnailScale(_:)` 끝에도 `schedulePrefetch()` (셀 크기가 바뀌면 화면 분량이 바뀐다).

- [x] **Step 7: 빌드·수동 검증** (2026-10-16 사용자 확인, 6항목 전부 정상)

Run: `make build && make run`
확인:
1. 작은 폴더: 셀이 즉시 채워지고, 스켈레톤이 잠깐 보였다 사라진다.
2. 큰 폴더(수천 장 이상): 첫 화면이 2초 안에 채워진다. 끝까지 휙 넘기면 멈춘 자리부터 채워진다.
3. 빠르게 위아래로 흔들어도 다른 파일 썸네일이 셀에 섞여 보이지 않는다(Review Focus 1).
4. 하위 폴더 포함 보기 켜고 끄기 — 경로 줄과 썸네일 모두 정상.
5. 북마크 보기 — 썸네일 정상, 깨진 북마크는 경고 심볼 유지.
6. 슬라이더로 셀 크기 바꿔도 정상.
문제가 있으면 여기서 고치고 다음으로.

- [ ] **Step 8: 커밋**

```bash
git add Sources/browser/BrowserViewController.swift Sources/browser/BrowserItem.swift
git commit -m "feat: pull-based thumbnail loading with visible-first priority and prefetch"
```

---

### Task 5: 스트립·호출처 이관, 설정 적용 연결

**Files:**
- Modify: `Sources/viewer/ThumbnailStripView.swift:12-32, 214-224`
- Modify: `Sources/viewer/CompareCandidateStrip.swift:9-16, 43, 62-70`
- Modify: `Sources/app/MainWindowController.swift:245-250`
- Modify: `Sources/app/MainWindowController+FileOperations.swift:29, 70, 123`
- Modify: `Sources/app/MainWindowController+Actions.swift:129`
- Modify: `Sources/viewer/ViewerViewController.swift:135`
- Modify: `docs/devlog/2026-10-15.md`

**Interfaces:**
- Consumes: `ThumbnailProvider.shared.request/cachedThumbnail/invalidate/clearMemory/setMemoryLimit`.

- [x] **Step 1: ThumbnailStripView** (구현: init은 `thumbnailProvider: ThumbnailProvider? = nil`(MainActor 기본 인자 경고 회피). 검토 추가: `cell.objectValue = file.url`을 두고 완료 콜백에서 비교 — 재사용 셀에 다른 파일 썸네일이 그려지는 것 방지.)

프로퍼티·init:

```swift
    private let thumbnailProvider: ThumbnailProvider
    private let imageService: ImageServiceProtocol
    ...
    init(
        imageService: ImageServiceProtocol = ImageService(),
        thumbnailProvider: ThumbnailProvider = .shared
    ) {
        self.imageService = imageService
        self.thumbnailProvider = thumbnailProvider
        super.init(frame: .zero)
```

파일 안의 `thumbnailCache.thumbnail(for:` 호출은 `thumbnailProvider.cachedThumbnail(for: $0, minPixel: Self.thumbnailMinPixel)`로 바꾼다. 상수 추가:

```swift
    /// 80pt 셀 × 레티나 2배. Provider가 220 단계로 올려 생성하므로 그리드와 공유된다.
    private static let thumbnailMinPixel = 160
```

`loadThumbnail(for:cell:)` 교체:

```swift
    private func loadThumbnail(for file: ImageFile, cell: NSTableCellView) {
        let url = file.url
        thumbnailProvider.request(url, minPixel: Self.thumbnailMinPixel, priority: .visible) { [weak cell] result in
            guard let cell, case .image(let image) = result else { return }
            cell.imageView?.image = image
        }
    }
```

- [x] **Step 2: CompareCandidateStrip** (`imageService` 프로퍼티·파라미터 제거, 호출처 `CompareWindowController.swift:71` 갱신)

```swift
    private static let thumbMinPixel = 144  // 72pt × 2
    ...
            if let cached = ThumbnailProvider.shared.cachedThumbnail(for: file.url, minPixel: Self.thumbMinPixel) {
    ...
    private func loadThumb(for file: ImageFile, into button: NSButton) {
        ThumbnailProvider.shared.request(file.url, minPixel: Self.thumbMinPixel, priority: .visible) { [weak button] result in
            guard case .image(let image) = result else { return }
            button?.image = image
        }
    }
```

`imageService` 프로퍼티·init 파라미터는 다른 용도가 없으면 그대로 둬도 되고, 안 쓰면 제거한다(호출처 `CompareWindowController` 확인).

- [x] **Step 3: invalidate / clearAll / setMemoryLimit 호출처**

전부 치환:

```bash
grep -rl "ThumbnailCache.shared" Sources | xargs sed -i '' \
  -e 's/ThumbnailCache\.shared\.invalidate(for:/ThumbnailProvider.shared.invalidate(for:/g' \
  -e 's/ThumbnailCache\.shared\.clearAll()/ThumbnailProvider.shared.clearMemory()/g' \
  -e 's/ThumbnailCache\.shared\.setMemoryLimit(bytes:/ThumbnailProvider.shared.setMemoryLimit(bytes:/g'
grep -rn "ThumbnailCache.shared" Sources
```
Expected: 마지막 grep에 `ThumbnailProvider+App.swift`의 `memoryCache: .shared`만 남거나 아무것도 없음.

- [x] **Step 4: 빌드·수동 검증** (2026-10-16 사용자 확인, 5항목 정상)

Run: `make build && make run`
확인:
1. 뷰어 스트립 썸네일 정상, 좌우 이동 정상.
2. 비교 창 후보 스트립 정상.
3. 편집기에서 저장 → 뷰어·스트립·그리드 썸네일이 갱신된다.
4. 이름 변경·이동·삭제 후 그리드 정상.
5. 설정 > 썸네일 "적용" → 그리드가 비워졌다 다시 채워진다.

- [x] **Step 5: devlog 1단계 섹션** (`docs/devlog/2026-10-16.md`에 Task별로 기록)

`docs/devlog/2026-10-15.md`에 추가(작업일이 바뀌었으면 그 날짜 파일):

```markdown
# <날짜> — 썸네일 캐시 재설계 1단계: 보이는 셀 우선 · 병렬 · 스켈레톤

## 요청·배경
2만 장 폴더에서 썸네일 생성 수 분, 메모리 한도에 밀려 다 보이지 않음. 설계 `docs/thumbnail-cache-design.md`.

## 원인
전체 순차 생성·직렬·메모리만. iCloud 비워진 파일은 생성 시 원본 다운로드 유발.

## 변경 사항
- `Sources/services/ThumbnailScheduler.swift` 신설: 우선순위 큐 + 워커 N개.
- `Sources/services/ThumbnailProvider.swift` 신설: 메모리 → 생성, 중복 합치기, 취소, 실패 기억, iCloud 판별.
- `Sources/browser/BrowserItem.swift`: 스켈레톤·실패·미다운로드 상태.
- `Sources/browser/BrowserViewController.swift`: willDisplay/didEndDisplaying 당겨 가기, 스크롤 멈춤 선로드.
- 스트립 2곳·invalidate 호출처 Provider로 이관.
- `Makefile` `test` 타깃, `Tests/` 신설.

## 검증
- `make test` 통과(스케줄러 6, Provider 7).
- 수동: <Task 4 Step 7, Task 5 Step 4 항목 결과>

## 트레이드오프
- 선로드는 앞뒤 2화면까지만. 유휴 시 전체 완주는 후속.
- NAS·외장에서 워커 8개가 I/O 병목이 될 수 있음. 측정 후 조정.
```

- [ ] **Step 6: 커밋**

```bash
git add Sources docs/devlog
git commit -m "refactor: route strip thumbnails and cache invalidation through ThumbnailProvider; devlog"
```

---

### Task 6: ThumbnailDiskStore (TDD)

**Files:**
- Create: `Sources/services/ThumbnailDiskStore.swift`
- Create: `Tests/ThumbnailDiskStoreTests.swift`
- Modify: `Tests/main.swift`, `Makefile` (`TEST_SOURCES`)

**Interfaces:**
- Produces:
  ```swift
  final class ThumbnailDiskStore {
      init(directory: URL, limitBytes: Int)   // 디렉터리 없으면 생성. 실패 시 isAvailable = false
      var isAvailable: Bool { get }
      var limitBytes: Int { get set }         // 줄이면 GC를 utility 직렬 큐에 바로 건다(호출자는 기다리지 않음)
      var usedBytes: Int { get }
      static func key(path: String, mtimeSec: Int, fileSize: Int, px: Int) -> String   // "<hash16>_<mtime>_<size>_<px>"
      static func sourceStamp(of url: URL) -> (mtimeSec: Int, fileSize: Int)?
      /// 요청 px 이상인 단계 중 가장 작은 것을 돌려준다. 적중 시 파일 mtime을 지금으로 갱신(LRU).
      func lookup(url: URL, minPx: Int, levels: [Int]) -> CGImage?
      func store(_ image: CGImage, url: URL, px: Int)
      func clear()                            // 디렉터리를 옆으로 옮겨 즉시 0으로, 실제 삭제는 GC 큐에서
      func recount()
  }
  ```
- **락 범위 원칙(2026-10-16 검토 반영):** `NSLock`은 `_usedBytes`·`_limitBytes`·플래그만 보호한다. HEIC 디코드(`lookup`)·인코드(`store`)·디렉터리 열거(GC)는 락 밖에서 한다. 안 그러면 워커 8개가 디스크 계층에서 전부 직렬화되고, `limitBytes`를 메인 스레드에서 내릴 때 GC(3만 파일 열거)가 UI를 1~2초 멈춘다. GC는 전용 `utility` 직렬 큐 하나에서만 돌아 서로 겹치지 않는다(스펙 §2.3).

- [x] **Step 1: 실패하는 테스트 작성**

```swift
// Tests/ThumbnailDiskStoreTests.swift
import Foundation
import CoreGraphics

private func makeCGImage(px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: px, height: px))
    return ctx.makeImage()!
}

private func makeSource(_ dir: URL, _ name: String, bytes: Int, mtime: Date? = nil) -> URL {
    let url = dir.appendingPathComponent(name)
    FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 7, count: bytes))
    if let mtime { try! FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path) }
    return url
}

func runDiskStoreTests() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("diskstore-tests-\(UUID().uuidString)")
    let src = root.appendingPathComponent("src")
    try! FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
    let levels = [220, 330, 440]

    runTest("키는 경로·mtime·size·px를 모두 담는다") {
        let k = ThumbnailDiskStore.key(path: "/a/b.jpg", mtimeSec: 1700000000, fileSize: 1234, px: 440)
        check(k.hasSuffix("_1700000000_1234_440"), "접미사")
        checkEqual(k.count, 16 + "_1700000000_1234_440".count, "해시 16자")
        check(k != ThumbnailDiskStore.key(path: "/a/c.jpg", mtimeSec: 1700000000, fileSize: 1234, px: 440), "경로 다르면 다름")
    }

    runTest("testKeyChangesWithSize: mtime 같고 size만 달라도 다른 키") {
        let a = ThumbnailDiskStore.key(path: "/a.jpg", mtimeSec: 1, fileSize: 100, px: 440)
        let b = ThumbnailDiskStore.key(path: "/a.jpg", mtimeSec: 1, fileSize: 101, px: 440)
        check(a != b, "size 반영")
    }

    runTest("store 후 lookup 적중, usedBytes 증가") {
        let store = ThumbnailDiskStore(directory: root.appendingPathComponent("c1"), limitBytes: 100_000_000)
        check(store.isAvailable, "디렉터리 생성")
        let file = makeSource(src, "a.jpg", bytes: 10)
        check(store.lookup(url: file, minPx: 440, levels: levels) == nil, "비어 있음")
        store.store(makeCGImage(px: 440), url: file, px: 440)
        check(store.usedBytes > 0, "usedBytes 증가")
        let hit = store.lookup(url: file, minPx: 440, levels: levels)
        checkEqual(hit?.width ?? 0, 440, "적중 크기")
    }

    runTest("더 큰 px 항목이 작은 요청을 만족한다, 작은 항목은 큰 요청을 못 만족한다") {
        let store = ThumbnailDiskStore(directory: root.appendingPathComponent("c2"), limitBytes: 100_000_000)
        let file = makeSource(src, "b.jpg", bytes: 10)
        store.store(makeCGImage(px: 330), url: file, px: 330)
        checkEqual(store.lookup(url: file, minPx: 220, levels: levels)?.width ?? 0, 330, "220 요청 → 330 적중")
        check(store.lookup(url: file, minPx: 440, levels: levels) == nil, "440 요청 → 없음")
    }

    runTest("원본 mtime이 바뀌면 적중하지 않는다") {
        let store = ThumbnailDiskStore(directory: root.appendingPathComponent("c3"), limitBytes: 100_000_000)
        let file = makeSource(src, "c.jpg", bytes: 10, mtime: Date(timeIntervalSince1970: 1_000_000))
        store.store(makeCGImage(px: 440), url: file, px: 440)
        try! FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000_000)], ofItemAtPath: file.path)
        check(store.lookup(url: file, minPx: 440, levels: levels) == nil, "mtime 변경 후 미적중")
    }

    runTest("testLoweringLimitTriggersGC: 한도를 내리면 오래된 것부터 지워 90% 이하로") {
        let store = ThumbnailDiskStore(directory: root.appendingPathComponent("c4"), limitBytes: 100_000_000)
        var files: [URL] = []
        for i in 0..<6 {
            let f = makeSource(src, "g\(i).jpg", bytes: 10)
            files.append(f)
            store.store(makeCGImage(px: 440), url: f, px: 440)
            Thread.sleep(forTimeInterval: 0.02)  // 저장 시각 차이
        }
        let perItem = store.usedBytes / 6
        store.limitBytes = perItem * 3  // GC는 비동기(utility 큐)라 기다려야 한다
        let target = Int(Double(perItem * 3) * 0.9) + perItem
        check(waitUntil { store.usedBytes <= target }, "90% 근처까지 감소")
        check(store.lookup(url: files[0], minPx: 440, levels: levels) == nil, "가장 오래된 것 삭제")
        check(store.lookup(url: files[5], minPx: 440, levels: levels) != nil, "가장 최근 것 유지")
    }

    runTest("lookup 적중은 LRU 순서를 갱신한다") {
        let store = ThumbnailDiskStore(directory: root.appendingPathComponent("c5"), limitBytes: 100_000_000)
        var files: [URL] = []
        for i in 0..<3 {
            let f = makeSource(src, "l\(i).jpg", bytes: 10)
            files.append(f)
            store.store(makeCGImage(px: 440), url: f, px: 440)
            Thread.sleep(forTimeInterval: 0.02)
        }
        Thread.sleep(forTimeInterval: 0.02)
        _ = store.lookup(url: files[0], minPx: 440, levels: levels)  // 가장 오래된 것을 방금 씀
        let perItem = store.usedBytes / 3
        store.limitBytes = perItem * 2
        check(waitUntil { store.usedBytes <= Int(Double(perItem * 2) * 0.9) + perItem }, "GC 완료")
        check(store.lookup(url: files[0], minPx: 440, levels: levels) != nil, "최근 사용한 것 유지")
        check(store.lookup(url: files[1], minPx: 440, levels: levels) == nil, "안 쓴 오래된 것 삭제")
    }

    runTest("limitBytes 변경은 호출자를 막지 않는다") {
        let store = ThumbnailDiskStore(directory: root.appendingPathComponent("c8"), limitBytes: 100_000_000)
        for i in 0..<4 {
            store.store(makeCGImage(px: 440), url: makeSource(src, "n\(i).jpg", bytes: 10), px: 440)
        }
        let started = Date()
        store.limitBytes = 1  // 전부 지워야 하는 상황
        check(Date().timeIntervalSince(started) < 0.05, "setter가 GC를 기다리지 않음")
        check(waitUntil { store.usedBytes == 0 }, "비동기 GC로 0까지")
    }

    runTest("clear는 전부 지우고 usedBytes 0") {
        let store = ThumbnailDiskStore(directory: root.appendingPathComponent("c6"), limitBytes: 100_000_000)
        let f = makeSource(src, "z.jpg", bytes: 10)
        store.store(makeCGImage(px: 440), url: f, px: 440)
        store.clear()
        checkEqual(store.usedBytes, 0, "usedBytes")
        check(store.lookup(url: f, minPx: 440, levels: levels) == nil, "비어 있음")
        check(store.isAvailable, "clear 후에도 사용 가능")
    }

    runTest("recount는 디렉터리 실제 크기로 맞춘다") {
        let dir = root.appendingPathComponent("c7")
        let store = ThumbnailDiskStore(directory: dir, limitBytes: 100_000_000)
        let f = makeSource(src, "r.jpg", bytes: 10)
        store.store(makeCGImage(px: 440), url: f, px: 440)
        let before = store.usedBytes
        let store2 = ThumbnailDiskStore(directory: dir, limitBytes: 100_000_000)  // 새 인스턴스는 0부터
        checkEqual(store2.usedBytes, 0, "초기값")
        store2.recount()
        checkEqual(store2.usedBytes, before, "재계산")
    }

    try? FileManager.default.removeItem(at: root)
}
```

`Tests/main.swift`에 `runDiskStoreTests()` 줄을 `runSchedulerTests()` 아래에 추가. `Makefile` `TEST_SOURCES`에 `Sources/services/ThumbnailDiskStore.swift` 추가.

- [x] **Step 2: 테스트 실행 → 실패 확인**

Run: `make test`
Expected: `cannot find 'ThumbnailDiskStore' in scope`

- [x] **Step 3: DiskStore 구현**

```swift
// Sources/services/ThumbnailDiskStore.swift
import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// 썸네일 디스크 캐시. 키에 경로 해시·mtime·크기·px가 들어 있어 원본이 바뀌면 키가 달라지고,
/// 옛 항목은 GC(접근시각 LRU)가 치운다. 어느 스레드에서 불러도 된다.
///
/// 락은 바이트 카운터와 플래그만 지킨다. 디코드·인코드·디렉터리 열거는 락 밖에서 하므로
/// 워커 여러 개가 디스크 계층에서 서로를 기다리지 않는다. GC는 `gcQueue`(utility, 직렬)에서만 돈다.
final class ThumbnailDiskStore {
    private let directory: URL
    private let lock = NSLock()  // _limitBytes·_usedBytes·gcScheduled·loggedWriteFailure 전용
    private let gcQueue = DispatchQueue(label: "com.jenalab.jenaimage.thumbnail-disk-gc", qos: .utility)
    private var _limitBytes: Int
    private var _usedBytes = 0
    private var gcScheduled = false
    private(set) var isAvailable = false
    private var loggedWriteFailure = false

    init(directory: URL, limitBytes: Int) {
        self.directory = directory
        self._limitBytes = limitBytes
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            isAvailable = true
        } catch {
            NSLog("ThumbnailDiskStore: 디렉터리 생성 실패 — 디스크 캐시 비활성: \(error)")
        }
    }

    var limitBytes: Int {
        get { lock.lock(); defer { lock.unlock() }; return _limitBytes }
        set {
            lock.lock(); _limitBytes = newValue; lock.unlock()
            scheduleCollectIfNeeded()  // 메인 스레드(설정 슬라이더)에서 불러도 기다리지 않는다
        }
    }

    var usedBytes: Int {
        lock.lock(); defer { lock.unlock() }
        return _usedBytes
    }

    // MARK: - Key

    static func key(path: String, mtimeSec: Int, fileSize: Int, px: Int) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        let hash16 = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(hash16)_\(mtimeSec)_\(fileSize)_\(px)"
    }

    /// 새 URL 인스턴스로 읽는다 — 리소스 값 캐시가 워커 스레드에서 비워지지 않아 mtime 변경을 놓치기 때문(Task 0 참고).
    /// 비워진 iCloud 파일도 `fileSize`는 원본 크기를 돌려주므로 디스크 캐시 조회가 정상 동작한다.
    static func sourceStamp(of url: URL) -> (mtimeSec: Int, fileSize: Int)? {
        guard let rv = try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let mtime = rv.contentModificationDate, let size = rv.fileSize else { return nil }
        return (Int(mtime.timeIntervalSince1970), size)
    }

    private func fileURL(forKey key: String) -> URL {
        directory.appendingPathComponent(String(key.prefix(2))).appendingPathComponent(key + ".heic")
    }

    // MARK: - Lookup / Store

    /// 락 없이 실행된다. 같은 키를 두 워커가 동시에 조회해도 읽기만 하므로 안전하고,
    /// GC가 그 사이 파일을 지우면 디코드가 실패해 생성 경로로 넘어갈 뿐이다.
    func lookup(url: URL, minPx: Int, levels: [Int]) -> CGImage? {
        guard isAvailable, let stamp = Self.sourceStamp(of: url) else { return nil }
        for px in levels.sorted() where px >= minPx {
            let key = Self.key(path: url.path, mtimeSec: stamp.mtimeSec, fileSize: stamp.fileSize, px: px)
            let file = fileURL(forKey: key)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            guard let src = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                removeFile(file)  // 깨진 항목은 지우고 생성 경로로
                continue
            }
            // 접근시각 = 파일 mtime. 별도 메타 없이 LRU를 만든다(스펙 §2.3).
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return img
        }
        return nil
    }

    /// 인코드는 락 밖. 같은 키의 동시 저장은 Provider가 요청을 합치므로 일어나지 않는다.
    func store(_ image: CGImage, url: URL, px: Int) {
        guard isAvailable, let stamp = Self.sourceStamp(of: url) else { return }
        let key = Self.key(path: url.path, mtimeSec: stamp.mtimeSec, fileSize: stamp.fileSize, px: px)
        let file = fileURL(forKey: key)
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let dest = CGImageDestinationCreateWithURL(file as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            lock.lock(); _usedBytes += size; lock.unlock()
            scheduleCollectIfNeeded()
        } catch {
            lock.lock()
            let firstTime = !loggedWriteFailure
            loggedWriteFailure = true
            lock.unlock()
            if firstTime { NSLog("ThumbnailDiskStore: 쓰기 실패 — 메모리 캐시만으로 계속: \(error)") }
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// 디렉터리를 옆 이름으로 옮기고(즉시) 빈 디렉터리를 새로 만든다. 수만 개 파일의 실제 삭제는 GC 큐에서.
    /// 호출자(설정 창)는 바로 usedBytes == 0을 본다.
    func clear() {
        guard isAvailable else { return }
        let trash = directory.deletingLastPathComponent()
            .appendingPathComponent("thumbs-trash-\(UUID().uuidString)", isDirectory: true)
        lock.lock()
        let moved = (try? FileManager.default.moveItem(at: directory, to: trash)) != nil
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _usedBytes = 0
        lock.unlock()
        if moved {
            gcQueue.async { try? FileManager.default.removeItem(at: trash) }
        }
    }

    /// 디렉터리를 훑어 usedBytes를 실제 값으로 맞춘다(비정상 종료 보정). 느리므로 백그라운드에서 부른다.
    func recount() {
        let total = allEntries().reduce(0) { $0 + $1.size }
        lock.lock(); _usedBytes = total; lock.unlock()
        scheduleCollectIfNeeded()
    }

    // MARK: - GC (gcQueue에서만 실행)

    private struct Entry { let url: URL; let size: Int; let date: Date }

    private func allEntries() -> [Entry] {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                                                     options: [.skipsHiddenFiles]) else { return [] }
        var out: [Entry] = []
        for case let u as URL in e where u.pathExtension == "heic" {
            let rv = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            out.append(Entry(url: u, size: rv?.fileSize ?? 0, date: rv?.contentModificationDate ?? .distantPast))
        }
        return out
    }

    /// 한도를 넘었고 GC가 걸려 있지 않으면 한 번만 건다. 저장마다 호출돼도 디렉터리 열거는 GC 1회당 한 번이다.
    private func scheduleCollectIfNeeded() {
        lock.lock()
        let needed = _usedBytes > _limitBytes && !gcScheduled
        if needed { gcScheduled = true }
        lock.unlock()
        guard needed else { return }
        gcQueue.async { [weak self] in self?.collect() }
    }

    private func collect() {
        lock.lock()
        let limit = _limitBytes
        let over = _usedBytes > limit
        lock.unlock()
        if over {
            let target = Int(Double(limit) * 0.9)
            for entry in allEntries().sorted(by: { $0.date < $1.date }) {
                if usedBytes <= target { break }
                removeFile(entry.url, size: entry.size)
            }
        }
        lock.lock(); gcScheduled = false; lock.unlock()
        // 도는 동안 한도가 더 내려갔거나 저장이 이어졌으면 한 번 더 건다(그 사이 요청은 gcScheduled 때문에 무시됐다).
        scheduleCollectIfNeeded()
    }

    private func removeFile(_ url: URL, size: Int? = nil) {
        let s = size ?? ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        if (try? FileManager.default.removeItem(at: url)) != nil {
            lock.lock(); _usedBytes = max(0, _usedBytes - s); lock.unlock()
        }
    }
}
```

- [x] **Step 4: 테스트 실행 → 통과 확인** (2026-10-16: 23/23, HEIC 인코딩 정상. 검토 추가: `collect()` 끝에서 `gcScheduled`를 내린 뒤 `scheduleCollectIfNeeded()`를 한 번 더 — GC 도는 동안 내려간 한도가 다음 저장까지 미적용되던 구멍)

Run: `make test`
Expected: DiskStore 10개 포함 전부 `✅`. GC 테스트 두 개는 `waitUntil`로 비동기 GC를 기다린다. HEIC 인코딩이 이 Mac에서 안 되면 `store 후 lookup` 테스트가 실패한다 — 그 경우 `UTType.heic`를 `UTType.jpeg`로, 확장자를 `.jpg`로 바꾸고 스펙 §핵심 결정 표의 "저장 포맷"을 갱신한다.

- [ ] **Step 5: 커밋**

```bash
git add Sources/services/ThumbnailDiskStore.swift Tests Makefile
git commit -m "feat: ThumbnailDiskStore with content-stamped keys and LRU GC"
```

---

### Task 7: Provider에 디스크 계층 연결 + 설정 키 + 시작 시 재계산

**Files:**
- Modify: `Sources/services/ThumbnailProvider.swift` (init, `produce`, `finish`, 새 메서드)
- Modify: `Sources/services/ThumbnailProvider+App.swift`
- Modify: `Sources/services/AppSettings.swift:17-24, 165-176`
- Modify: `Tests/ThumbnailProviderTests.swift` (디스크 적중 테스트 추가)

**Interfaces:**
- Consumes: `ThumbnailDiskStore` (Task 6).
- Produces:
  ```swift
  ThumbnailProvider.init(workerCount:memoryCache:diskStore:generate:)   // diskStore: ThumbnailDiskStore?
  func setDiskLimit(bytes: Int)
  var diskUsedBytes: Int { get }
  func clearDisk()
  AppSettings.thumbnailDiskCacheMB: Int   // 기본 2048, 500...8192
  AppSettings.thumbnailDiskCacheMBDefault / thumbnailDiskCacheMBRange
  ```

- [x] **Step 1: 실패하는 테스트 추가**

`Tests/ThumbnailProviderTests.swift`의 `runProviderTests()` 안, 마지막 `runTest` 뒤에 추가:

```swift
    runTest("디스크에 있으면 생성을 부르지 않고 메모리에도 채운다") {
        let diskDir = tmp.appendingPathComponent("disk")
        let disk = ThumbnailDiskStore(directory: diskDir, limitBytes: 100_000_000)
        let cg = makeImage(px: 440).cgImage(forProposedRect: nil, context: nil, hints: nil)!
        disk.store(cg, url: fileA, px: 440)

        let lock = NSLock()
        var calls = 0
        let cache = ThumbnailCache(memoryLimit: 50_000_000)
        let provider = ThumbnailProvider(workerCount: 1, memoryCache: cache, diskStore: disk) { _, _ in
            lock.lock(); calls += 1; lock.unlock(); return makeImage(px: 440)
        }
        var got = false
        provider.request(fileA, minPixel: 440, priority: .visible) { if case .image = $0 { got = true } }
        check(waitUntil { got }, "디스크 적중 완료")
        lock.lock(); let c = calls; lock.unlock()
        checkEqual(c, 0, "생성 호출 없음")
        check(cache.thumbnail(for: fileA, minPixelSize: 440) != nil, "메모리에 채워짐")
    }

    runTest("생성 결과는 디스크에 저장된다") {
        let diskDir = tmp.appendingPathComponent("disk2")
        let disk = ThumbnailDiskStore(directory: diskDir, limitBytes: 100_000_000)
        let provider = ThumbnailProvider(workerCount: 1, memoryCache: ThumbnailCache(memoryLimit: 50_000_000), diskStore: disk) { _, _ in
            makeImage(px: 440)
        }
        var got = false
        provider.request(fileB, minPixel: 440, priority: .visible) { if case .image = $0 { got = true } }
        check(waitUntil { got }, "완료")
        check(waitUntil { disk.usedBytes > 0 }, "디스크 저장")
        check(disk.lookup(url: fileB, minPx: 440, levels: ThumbnailProvider.levels) != nil, "디스크 적중")
    }
```

기존 테스트의 `ThumbnailProvider(workerCount:memoryCache:)` 호출은 그대로 둔다(아래에서 `diskStore` 기본값 nil).

- [x] **Step 2: 테스트 실행 → 실패 확인**

Run: `make test`
Expected: `extra argument 'diskStore' in call`

- [x] **Step 3: Provider 수정**

init 교체:

```swift
    private let diskStore: ThumbnailDiskStore?

    init(workerCount: Int, memoryCache: ThumbnailCache, diskStore: ThumbnailDiskStore? = nil,
         generate: @escaping (URL, CGSize) -> NSImage?) {
        self.memoryCache = memoryCache
        self.diskStore = diskStore
        self.scheduler = ThumbnailScheduler(workerCount: workerCount)
        self.generate = generate
    }
```

공개 메서드 추가(`setMemoryLimit` 아래):

```swift
    func setDiskLimit(bytes: Int) { diskStore?.limitBytes = bytes }
    var diskUsedBytes: Int { diskStore?.usedBytes ?? 0 }
    func clearDisk() { diskStore?.clear() }

    /// 앱 시작 30초 뒤 디렉터리를 훑어 누적 바이트를 보정한다.
    func scheduleDiskRecount() {
        guard let diskStore else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30) { diskStore.recount() }
    }
```

`schedule(key:priority:)`에서 `produce` 호출에 `diskStore: diskStore` 전달. `produce` 시그니처와 본문 교체:

```swift
    nonisolated private static func produce(key: Key, priority: ThumbnailPriority, useQuickLook: Bool,
                                            failedKeys: Set<String>, diskStore: ThumbnailDiskStore?,
                                            generate: (URL, CGSize) -> NSImage?) -> Outcome {
        let url = key.url
        let stamp = fileStamp(url)
        if failedKeys.contains(stamp) { return .failed(fileStamp: stamp) }

        // 디스크 캐시는 iCloud 비워진 파일에도 유효하다(원본 메타데이터만 읽는다).
        if let cg = diskStore?.lookup(url: url, minPx: key.level, levels: levels) {
            return .image(NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)), store: false)
        }

        if isEvictedICloudItem(url) {
            if priority == .visible, useQuickLook, let img = quickLookThumbnail(url: url, level: key.level) {
                return .image(img, store: false)
            }
            return .notDownloaded
        }

        let pt = CGFloat(key.level) / 2
        if let img = generate(url, CGSize(width: pt, height: pt)) {
            if let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                diskStore?.store(cg, url: url, px: key.level)
            }
            return .image(img, store: true)
        }
        return .failed(fileStamp: stamp)
    }
```

디스크 저장 분기가 `produce` 안으로 들어갔으므로 `Outcome.image`의 `store` 라벨은 역할이 없다. 제거한다:

```swift
    private enum Outcome {
        case image(NSImage)
        case failed(fileStamp: String)
        case notDownloaded
    }
```

위 `produce` 본문의 `.image(…, store: false)` / `.image(img, store: true)` 세 곳을 모두 `.image(…)`로 바꾸고, `finish`는 어떤 경로든 메모리에 채운다(디스크 적중도 메모리에 올려야 다음 스크롤이 즉시). 대기자 유무와 무관하게 캐시에 먼저 넣는 순서는 Task 2와 같다:

```swift
        case .image(let img):
            memoryCache.store(img, for: key.url)
            result = .image(img)
```

- [x] **Step 4: AppSettings 키 추가**

`Key` enum에 `case thumbnailDiskCacheMB = "thumbnailDiskCacheMB"`. `thumbnailCacheMB` 아래에:

```swift
    static let thumbnailDiskCacheMBDefault = 2048
    static let thumbnailDiskCacheMBRange = 500...8192

    /// 썸네일 디스크 캐시 한도(MB). 기본 2048, 500~8192. "적용" 없이 즉시 반영.
    var thumbnailDiskCacheMB: Int {
        get {
            if defaults.object(forKey: Key.thumbnailDiskCacheMB.rawValue) == nil { return Self.thumbnailDiskCacheMBDefault }
            let v = defaults.integer(forKey: Key.thumbnailDiskCacheMB.rawValue)
            return min(max(v, Self.thumbnailDiskCacheMBRange.lowerBound), Self.thumbnailDiskCacheMBRange.upperBound)
        }
        set { defaults.set(newValue, forKey: Key.thumbnailDiskCacheMB.rawValue) }
    }
```

- [x] **Step 5: +App.swift에 디스크 연결**

```swift
    static let shared: ThumbnailProvider = {
        let service = ImageService()
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.jenalab.jenaimage/thumbs", isDirectory: true)
        let disk = ThumbnailDiskStore(directory: cachesDir,
                                      limitBytes: AppSettings.shared.thumbnailDiskCacheMB * 1024 * 1024)
        let provider = ThumbnailProvider(
            workerCount: defaultWorkerCount,
            memoryCache: .shared,
            diskStore: disk.isAvailable ? disk : nil
        ) { url, size in
            if case .success(let img) = service.generateThumbnailSync(at: url, size: size) { return img }
            return nil
        }
        provider.useQuickLookForEvicted = true  // Task 0 결과
        provider.scheduleDiskRecount()
        return provider
    }()
```

- [x] **Step 6: 테스트·빌드** (2026-10-16: 25/25, 빌드 0. 검토 반영: `ThumbnailDiskStore`를 `@unchecked Sendable`로 선언(워커 @Sendable 클로저 캡처 경고), QuickLook으로 받은 iCloud 썸네일도 디스크에 저장 — 안 하면 비워진 파일은 세션마다 네트워크 왕복)

Run: `make test && make build`
Expected: 전부 통과, 빌드 성공. (`produce`의 QuickLook 분기에서도 `diskStore?.store`를 호출한다.)

- [x] **Step 7: 수동 검증** (2026-10-16 사용자 확인)

`make run` 후 큰 폴더를 끝까지 한 번 훑고 앱 종료 → 재실행 → 같은 폴더. 스켈레톤 거의 없이 즉시 채워진다. `du -sh ~/Library/Caches/com.jenalab.jenaimage/thumbs` 로 크기 확인.

- [ ] **Step 8: 커밋**

```bash
git add Sources/services Tests
git commit -m "feat: disk thumbnail cache wired into ThumbnailProvider; disk limit setting"
```

---

### Task 8: 설정 탭 — 디스크 슬라이더·사용량·비우기

**Files:**
- Modify: `Sources/app/PreferencesWindowController.swift:165-286`

**Interfaces:**
- Consumes: `AppSettings.thumbnailDiskCacheMB/Default/Range`, `ThumbnailProvider.shared.setDiskLimit/diskUsedBytes/clearDisk`.

- [x] **Step 1: 컨트롤 프로퍼티 추가**

`applyButton` 아래:

```swift
    private let diskSlider = NSSlider()
    private let diskValueLabel = NSTextField(labelWithString: "")
    private let diskUsageLabel = NSTextField(labelWithString: "")
    private let diskClearButton = NSButton(title: "비우기", target: nil, action: nil)
```

- [x] **Step 2: 뷰 구성**

`createThumbnailView()`에서 `container.addSubview(applyButton)` 앞에 추가:

```swift
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
```

제약 배열에서 `applyButton.topAnchor.constraint(equalTo: cacheHintLabel.bottomAnchor, constant: 20)`를 다음으로 교체하고 디스크 제약 추가:

```swift
            diskLabel.topAnchor.constraint(equalTo: cacheHintLabel.bottomAnchor, constant: 20),
            diskLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            diskSlider.centerYAnchor.constraint(equalTo: diskLabel.centerYAnchor),
            diskSlider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 130),
            diskSlider.widthAnchor.constraint(equalToConstant: 190),

            diskValueLabel.centerYAnchor.constraint(equalTo: diskLabel.centerYAnchor),
            diskValueLabel.leadingAnchor.constraint(equalTo: diskSlider.trailingAnchor, constant: 8),

            diskUsageLabel.topAnchor.constraint(equalTo: diskLabel.bottomAnchor, constant: 8),
            diskUsageLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 130),

            diskClearButton.centerYAnchor.constraint(equalTo: diskUsageLabel.centerYAnchor),
            diskClearButton.leadingAnchor.constraint(equalTo: diskUsageLabel.trailingAnchor, constant: 12),

            applyButton.topAnchor.constraint(equalTo: diskUsageLabel.bottomAnchor, constant: 20),
```

`updateThumbnailHint()` 호출 뒤에 `updateDiskLabels()`.

- [x] **Step 3: 동작 메서드** (구현 차이: 드래그 중(`leftMouseDragged`)엔 값 라벨만 바꾸고 한도 저장·`setDiskLimit`은 손을 뗄 때 — 중간 값마다 적용하면 GC가 파일을 지워 되돌릴 수 없다. 사용량 문구는 "사용 중 X"로 줄임(창 폭 480 안에 비우기 버튼과 함께 두기 위해).)

`applyThumbnailSettings(_:)` 아래에 추가:

```swift
    /// 디스크 한도는 500MB 단위, 즉시 반영(비용이 없으므로 "적용" 불필요).
    private var pendingDiskMB: Int {
        let stepped = Int((Double(diskSlider.integerValue) / 500).rounded()) * 500
        return min(max(stepped, AppSettings.thumbnailDiskCacheMBRange.lowerBound), AppSettings.thumbnailDiskCacheMBRange.upperBound)
    }

    private func updateDiskLabels() {
        let mb = pendingDiskMB
        diskValueLabel.stringValue = mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
        let used = ThumbnailProvider.shared.diskUsedBytes
        let usedText = ByteCountFormatter.string(fromByteCount: Int64(used), countStyle: .file)
        diskUsageLabel.stringValue = "사용 중 \(usedText). 앱을 다시 켜도 썸네일이 바로 뜨도록 디스크에 둬요."
        diskClearButton.isEnabled = used > 0
    }

    @objc private func diskLimitChanged(_ sender: Any?) {
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
```

- [x] **Step 4: 빌드·수동 검증** (2026-10-16 사용자 확인; "사용 중" 라벨 미갱신 버그 → 창 열 때·2초 주기 갱신으로 수정)

Run: `make build && make run`
확인:
1. 설정 > 썸네일: "디스크 한도" 슬라이더 기본 2.0 GB, 사용 중 표시, 비우기 버튼.
2. 슬라이더를 사용량보다 아래로 내리면 UI가 멈추지 않고, 1초 안에 사용 중 수치가 줄어든다.
3. 비우기 → 사용 중 0, 버튼 비활성. 그리드로 돌아가면 다시 채워진다.
4. 메모리 "적용"은 이전과 동일.

- [ ] **Step 5: 커밋**

```bash
git add Sources/app/PreferencesWindowController.swift
git commit -m "feat: disk thumbnail cache controls in Preferences > Thumbnails"
```

---

### Task 9: 마무리 — 수동 검증 8항목, devlog 2단계, README, 현황판

**Files:**
- Modify: `docs/devlog/<작업일>.md`
- Modify: `README.md` (기능 목록에 디스크 캐시 한 줄, 있으면)
- Modify: `~/Documents/project/source/skills/global/projects.md` jena-image 줄, `projects/jena-image.md`

- [ ] **Step 1: 스펙 §5.2 수동 검증 8항목 실행**

`make run` 후:
1. 2만 장 폴더: 첫 화면 2초 안에 채워짐.
2. 끝까지 휙 넘기면 멈춘 자리부터 채워짐.
3. 스켈레톤이 보이고, 다른 파일 썸네일이 섞이지 않음.
4. 앱 재시작 후 즉시 뜸.
5. Finder에서 파일 수정·삭제가 반영됨(수정은 mtime 변경 → 새 썸네일).
6. 설정에서 디스크 비우기 후 다시 채워짐.
7. iCloud 비워진 파일(`brctl evict`)을 훑어도 상태가 `NotDownloaded` 유지. 뷰어로 열면 내려받음.
8. 메모리 한도 "적용"이 이전처럼 동작.
결과를 항목별로 기록. 실패 항목은 고치고 재확인.

- [ ] **Step 2: devlog 2단계 섹션**

```markdown
# <날짜> (추가) — 썸네일 캐시 재설계 2단계: 디스크 캐시 · 설정 탭

## 변경 사항
- `Sources/services/ThumbnailDiskStore.swift` 신설: 키 `<hash16>_<mtime>_<size>_<px>.heic`, LRU GC(90%, utility 직렬 큐·비동기), recount, 비우기는 디렉터리 이동 후 백그라운드 삭제.
- `ThumbnailProvider`: 메모리 → 디스크 → 생성. 시작 30초 뒤 recount.
- `AppSettings.thumbnailDiskCacheMB`(기본 2048, 500~8192).
- 설정 > 썸네일: 디스크 한도 슬라이더(즉시 반영)·사용 중·비우기.

## 검증
- `make test`: 스케줄러 6 · Provider 9 · DiskStore 10 통과.
- 수동 8항목: <결과>

## 트레이드오프
- 디스크 키에 경로 해시를 쓰므로 파일을 옮기면 재생성(옛 항목은 GC). inode 추적은 외부 볼륨에서 불안정해 채택 안 함.
- HEIC 인코딩 비용이 생성에 더해진다(장당 수 ms). 디코딩 대비 작아 체감 없음.
```

- [ ] **Step 3: 현황판 갱신**

`projects.md` jena-image 줄의 '현 단계'를 "썸네일 캐시 재설계 완료(1·2단계) · 다음: 릴리스 v1.7.0 또는 plan.md v1.3"으로, 갱신일을 작업일로. `projects/jena-image.md`에 날짜 섹션 추가(커밋 해시, 남은 후속: NAS 워커 조정·유휴 완주).

- [ ] **Step 4: 커밋**

```bash
git add docs README.md
git commit -m "docs: thumbnail cache redesign devlog and verification results"
```
