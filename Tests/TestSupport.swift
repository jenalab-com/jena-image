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

import CoreGraphics

/// (x, y)는 위에서 아래로 0. 색은 sRGB 불투명 비트맵.
func makeTestImage(width: Int, height: Int, _ color: (Int, Int) -> RGB8) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let c = color(x, y), i = (y * width + x) * 4
            bytes[i] = c.r; bytes[i + 1] = c.g; bytes[i + 2] = c.b
        }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}
