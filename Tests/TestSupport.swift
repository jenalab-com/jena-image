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
