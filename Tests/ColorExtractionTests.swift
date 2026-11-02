import Foundation
import CoreGraphics

/// 색·개수 목록을 RGBA(불투명) 배열로 펼친다.
private func pixels(_ runs: [(RGB8, Int)], alpha: UInt8 = 255) -> [UInt8] {
    var out: [UInt8] = []
    for (c, n) in runs { for _ in 0..<n { out += [c.r, c.g, c.b, alpha] } }
    return out
}

func runColorExtractionTests() {
    runTest("칸마다 가장 많이 나온 실제 색을 기록한다") {
        // 5bit 양자화에서 (200,100,50)과 (201,101,51)은 같은 칸이다.
        let h = ColorExtractionService.buildHistogram(
            rgba: pixels([(RGB8(200, 100, 50), 5), (RGB8(201, 101, 51), 2)]), isCancelled: { false })!
        checkEqual(h.bins.count, 1, "한 칸")
        checkEqual(h.bins[0].count, 7, "칸 개수")
        checkEqual(h.bins[0].topColor, RGB8(200, 100, 50), "대표는 더 많이 나온 실제 색")
        checkEqual(h.bins[0].topCount, 5, "대표 색 개수")
        checkEqual(h.totalPixels, 7, "총 픽셀")
    }

    runTest("투명 픽셀은 히스토그램과 비율 분모에서 제외한다") {
        let data = pixels([(RGB8(255, 0, 0), 4)]) + pixels([(RGB8(0, 0, 0), 100)], alpha: 0)
        let h = ColorExtractionService.buildHistogram(rgba: data, isCancelled: { false })!
        checkEqual(h.totalPixels, 4, "불투명 픽셀만")
        let swatches = ColorExtractionService.group(h, tolerance: 10, minRatio: 0, formula: .cie76)
        checkEqual(swatches.map { $0.color }, [RGB8(255, 0, 0)], "검정이 끼지 않음")
        check(abs(swatches[0].ratio - 1.0) < 1e-9, "비율 100%")
    }

    runTest("축소는 긴 변을 맞추고 종횡비를 유지한다") {
        let big = makeTestImage(width: 1000, height: 500) { _, _ in RGB8(10, 20, 30) }
        let r = ColorExtractionService.downscaledRGBA(from: big, longSide: 256)!
        checkEqual(r.width, 256, "가로(긴 변)")
        checkEqual(r.height, 128, "세로")
        checkEqual(r.pixels.count, 256 * 128 * 4, "버퍼 크기")
        let small = makeTestImage(width: 40, height: 20) { _, _ in RGB8(1, 2, 3) }
        let s = ColorExtractionService.downscaledRGBA(from: small, longSide: 256)!
        checkEqual(s.width, 40, "작은 이미지는 키우지 않음")
    }

    // 서로 먼 색 5개: 빨강 3단계 + 파랑 + 초록. 개수는 모두 달라 동률이 없다.
    let palette: [(RGB8, Int)] = [(RGB8(255, 0, 0), 500), (RGB8(225, 0, 0), 400), (RGB8(195, 0, 0), 300),
                                  (RGB8(0, 0, 255), 200), (RGB8(0, 255, 0), 100)]
    let histogram = ColorExtractionService.buildHistogram(rgba: pixels(palette), isCancelled: { false })!

    runTest("허용 범위를 키우면 칩이 줄어든다") {
        let counts = [0.0, 5, 10, 20, 50, 100, 300].map {
            ColorExtractionService.group(histogram, tolerance: $0, minRatio: 0, formula: .cie76).count
        }
        checkEqual(counts.first!, 5, "허용 0이면 5칸 그대로")
        checkEqual(counts.last!, 1, "아주 크면 하나로")
        check(zip(counts, counts.dropFirst()).allSatisfy { $0 >= $1 }, "단조 감소: \(counts)")
        check(counts.contains(3), "빨강 3단계가 합쳐지는 구간 존재: \(counts)")
    }

    runTest("칩 색은 평균이 아니라 이미지에 실제 있는 색이다") {
        let actual = Set(palette.map { $0.0 })
        for tol in [0.0, 10, 30, 100, 300] {
            let swatches = ColorExtractionService.group(histogram, tolerance: tol, minRatio: 0, formula: .cie76)
            check(swatches.allSatisfy { actual.contains($0.color) }, "허용 \(tol): 모든 칩이 실제 색")
        }
        let merged = ColorExtractionService.group(histogram, tolerance: 100, minRatio: 0, formula: .cie76)
        checkEqual(merged[0].color, RGB8(255, 0, 0), "합쳐진 빨강 묶음의 칩은 가장 많이 나온 255,0,0")
    }

    runTest("비율은 큰 순서로 정렬되고, 최소 비율 0이면 합이 100%다") {
        for tol in [0.0, 30, 300] {
            let s = ColorExtractionService.group(histogram, tolerance: tol, minRatio: 0, formula: .cie76)
            check(abs(s.map { $0.ratio }.reduce(0, +) - 1.0) < 1e-9, "허용 \(tol): 합 100%")
            check(zip(s, s.dropFirst()).allSatisfy { $0.ratio >= $1.ratio }, "허용 \(tol): 내림차순")
        }
        let filtered = ColorExtractionService.group(histogram, tolerance: 0, minRatio: 0.2, formula: .cie76)
        check(filtered.map { $0.ratio }.reduce(0, +) <= 1.0 + 1e-9, "필터 후 합은 100% 이하")
    }

    runTest("최소 비율보다 작은 묶음은 칩에서 빠진다") {
        let h = ColorExtractionService.buildHistogram(
            rgba: pixels([(RGB8(30, 60, 200), 999), (RGB8(250, 250, 0), 1)]), isCancelled: { false })!
        checkEqual(ColorExtractionService.group(h, tolerance: 5, minRatio: 0.002, formula: .cie76).count, 1, "0.1% 짜리 제외")
        checkEqual(ColorExtractionService.group(h, tolerance: 5, minRatio: 0, formula: .cie76).count, 2, "필터 끄면 둘 다")
        // 작은 칸이 큰 묶음의 허용 범위 안이면 필터와 무관하게 큰 묶음에 합쳐진다.
        let near = ColorExtractionService.buildHistogram(
            rgba: pixels([(RGB8(30, 60, 200), 999), (RGB8(46, 60, 200), 1)]), isCancelled: { false })!
        let merged = ColorExtractionService.group(near, tolerance: 20, minRatio: 0.002, formula: .cie76)
        checkEqual(merged.count, 1, "가까운 작은 칸은 합류")
        check(abs(merged[0].ratio - 1.0) < 1e-9, "합류한 비율까지 반영")
    }

    runTest("히스토그램을 다시 만들지 않고 허용 범위만 바꿔도 처음부터 계산한 것과 같다") {
        let first = ColorExtractionService.group(histogram, tolerance: 10, minRatio: 0, formula: .cie76)
        _ = ColorExtractionService.group(histogram, tolerance: 100, minRatio: 0, formula: .cie76)
        _ = ColorExtractionService.group(histogram, tolerance: 0, minRatio: 0, formula: .cie76)
        let again = ColorExtractionService.group(histogram, tolerance: 10, minRatio: 0, formula: .cie76)
        checkEqual(first, again, "슬라이더를 오간 뒤에도 같은 결과(히스토그램 불변)")
        let fresh = ColorExtractionService.buildHistogram(rgba: pixels(palette), isCancelled: { false })!
        checkEqual(first, ColorExtractionService.group(fresh, tolerance: 10, minRatio: 0, formula: .cie76), "새로 만든 것과 동일")
    }

    runTest("취소 신호가 오면 히스토그램을 만들지 않는다") {
        let data = pixels([(RGB8(1, 2, 3), 40_000)])
        check(ColorExtractionService.buildHistogram(rgba: data, isCancelled: { true }) == nil, "취소되면 nil")
        let job = ColorJob()
        check(!job.isCancelled, "새 작업은 취소 아님")
        job.cancel()
        check(job.isCancelled, "cancel 후")
    }
}
