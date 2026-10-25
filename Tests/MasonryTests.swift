import AppKit
import ImageIO
import UniformTypeIdentifiers

func runMasonryTests() {
    runTest("일반 격자는 이미지 비율과 무관하게 같은 크기의 행과 열을 만든다") {
        let layout = MasonryGeometry(width: 600, preferredColumnWidth: 180,
                                     aspectRatios: [0.5, 2, 1, 3, 0.2, 1], captionHeight: 36, mode: .grid)
        checkEqual(Set(layout.frames.map(\.height)).count, 1, "같은 셀 높이")
        checkEqual(Set(layout.frames.prefix(3).map(\.minY)).count, 1, "첫 행 정렬")
        checkEqual(layout.frames[3].minX, layout.frames[0].minX, "다음 행 시작")
        checkEqual(layout.frames[3].minY, layout.frames[0].maxY + 12, "행 간격")
    }
    runTest("masonry는 같은 폭·다른 높이로 원본 비율을 유지한다") {
        let layout = MasonryGeometry(width: 600, preferredColumnWidth: 180, aspectRatios: [0.5, 2, 1], captionHeight: 36)
        checkEqual(layout.columns.count, 3, "3열")
        checkEqual(Set(layout.frames.map(\.width)).count, 1, "동일한 열 너비")
        check(layout.frames[0].height > layout.frames[2].height, "세로 이미지가 더 높음")
        check(layout.frames[2].height > layout.frames[1].height, "가로 이미지가 더 낮음")
        for (frame, ratio) in zip(layout.frames, [0.5, 2.0, 1.0]) {
            check(abs((frame.height - 36) - (frame.width - 4) / ratio) < 1, "잘라내지 않는 이미지 높이")
        }
    }
    runTest("다음 이미지는 가장 짧은 열 아래에 배치되어 행 사이 빈 공간이 없다") {
        let layout = MasonryGeometry(width: 600, preferredColumnWidth: 180, aspectRatios: [0.5, 2, 1, 1], captionHeight: 36)
        checkEqual(layout.frames[3].minX, layout.frames[1].minX, "짧은 가로 이미지 아래")
        checkEqual(layout.frames[3].minY, layout.frames[1].maxY + 12, "일정한 간격")
        check(layout.frames[3].minY < layout.frames[0].maxY, "이전 행 최대 높이를 기다리지 않음")
    }
    runTest("masonry 항목은 서로 겹치지 않고 콘텐츠 경계 안에 들어간다") {
        let ratios = (0..<100).map { CGFloat($0 % 9 + 1) / 3 }
        let layout = MasonryGeometry(width: 850, preferredColumnWidth: 180, aspectRatios: ratios, captionHeight: 50)
        for i in layout.frames.indices {
            let frame = layout.frames[i]
            check(frame.minX >= 0 && frame.maxX <= layout.contentSize.width, "가로 경계")
            check(frame.maxY <= layout.contentSize.height, "세로 경계")
            for j in (i + 1)..<layout.frames.count {
                check(!frame.intersects(layout.frames[j]), "셀 겹침 없음")
            }
        }
    }
    runTest("좁은 창과 크기 조절 슬라이더에 맞춰 열 수가 변한다") {
        let ratios = Array(repeating: CGFloat(1), count: 8)
        let narrow = MasonryGeometry(width: 140, preferredColumnWidth: 180, aspectRatios: ratios, captionHeight: 36)
        let wide = MasonryGeometry(width: 800, preferredColumnWidth: 180, aspectRatios: ratios, captionHeight: 36)
        let large = MasonryGeometry(width: 800, preferredColumnWidth: 360, aspectRatios: ratios, captionHeight: 36)
        checkEqual(narrow.columns.count, 1, "좁으면 한 열")
        check(wide.columns.count > large.columns.count, "썸네일 확대 시 열 수 감소")
        check(narrow.frames.allSatisfy { $0.maxX <= 140 }, "가로 스크롤 불필요")
    }
    runTest("화면 검색은 위에서 시작한 긴 이미지와 새로 보이는 이미지를 모두 찾는다") {
        let layout = MasonryGeometry(width: 600, preferredColumnWidth: 180,
                                     aspectRatios: [0.05] + Array(repeating: 2, count: 100), captionHeight: 36)
        let rect = CGRect(x: 0, y: 500, width: 600, height: 300)
        let expected = layout.frames.indices.filter { layout.frames[$0].intersects(rect) }
        checkEqual(layout.indexes(in: rect), expected, "열 이진 검색 결과와 전체 검사 일치")
        check(layout.indexes(in: rect).contains(0), "긴 이미지가 스크롤 도중 사라지지 않음")
    }
    runTest("빈 목록과 잘못된 비율도 유효한 레이아웃을 만든다") {
        let empty = MasonryGeometry(width: 600, preferredColumnWidth: 180, aspectRatios: [], captionHeight: 36)
        check(empty.frames.isEmpty, "빈 목록")
        check(empty.indexes(in: CGRect(x: 0, y: 0, width: 600, height: 400)).isEmpty, "빈 화면 검색")
        let invalid = MasonryGeometry(width: 600, preferredColumnWidth: 180,
                                      aspectRatios: [0, -.infinity, .nan], captionHeight: 36)
        check(invalid.frames.allSatisfy { $0.height.isFinite && $0.height > 36 }, "알 수 없는 비율은 정사각형")
    }
    runTest("원본 메타데이터에서 EXIF 회전을 반영한 비율을 읽는다") {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("masonry-metadata-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let context = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = context.makeImage()!
        for orientation in [1, 6, 8] {
            let url = folder.appendingPathComponent("orientation-\(orientation).tiff")
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
            check(CGImageDestinationFinalize(destination), "테스트 이미지 저장")
            checkEqual(ImageAspectRatioReader.aspectRatio(at: url), orientation == 1 ? 2 : 0.5, "회전된 가로·세로")
        }
        check(ImageAspectRatioReader.aspectRatio(at: folder.appendingPathComponent("missing.png")) == nil,
              "없는 원본은 대체 비율 사용")
    }
}
