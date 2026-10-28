import AppKit

func runAIImageGenerationTests() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("jena-ai-test-\(UUID().uuidString)")
    do {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent("저장 폴더")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("참조 ' $(echo unsafe).png")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let originalBytes = bitmap.representation(using: .png, properties: [:])!
        try originalBytes.write(to: original)
        let fixture = root.appendingPathComponent("fixture cli")
        func script(_ contents: String) throws {
            try ("#!/bin/sh\n" + contents).write(to: fixture, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
        }
        func request(_ references: [URL] = []) -> AIImageRequest {
            AIImageRequest(provider: .custom, executable: fixture.path, prompt: "한글 ' $(touch unsafe)", references: references, destination: destination)
        }
        func execute(_ request: AIImageRequest, service: AIImageGenerationService = AIImageGenerationService()) -> Result<[URL], Error>? {
            var result: Result<[URL], Error>?
            Task { @MainActor in
                do { result = .success(try await service.generate(request)) }
                catch { result = .failure(error) }
            }
            check(waitUntil(timeout: 10) { result != nil }, "CLI 작업이 완료된다")
            return result
        }
        try script("test -f \"$1\" || exit 9\ncp reference-1.png output/result.png\n")
        runTest("AI 참조 복사본을 전달하고 선택 폴더에 충돌 없이 저장한다") {
            let first = execute(request([original]))
            let second = execute(request([original]))
            guard case .success(let firstURLs) = first, case .success(let secondURLs) = second else {
                check(false, "생성 성공 필요: \(String(describing: first))")
                return
            }
            checkEqual(firstURLs.count, 1, "결과 수")
            let sourceName = original.deletingPathExtension().lastPathComponent
            checkEqual(firstURLs[0].lastPathComponent, "\(sourceName)_AI.png", "참조 원본 이름 뒤에 AI 표시")
            checkEqual(secondURLs[0].lastPathComponent, "\(sourceName)_AI_2.png", "이름 충돌 시 번호 추가")
            checkEqual(firstURLs[0].deletingLastPathComponent().path, destination.path, "선택한 폴더로 저장")
            check(firstURLs[0] != secondURLs[0], "반복 생성 시 덮어쓰기 방지")
            checkEqual(try? Data(contentsOf: original), originalBytes, "원본 보존")
            check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("unsafe").path), "문자열을 셸로 실행하지 않는다")
        }
        let otherReference = root.appendingPathComponent("다른.원본.jpg")
        try originalBytes.write(to: otherReference)
        let existing = destination.appendingPathComponent("다른.원본_AI.png")
        let preservedBytes = Data("existing file".utf8)
        try preservedBytes.write(to: existing)
        try script("cp reference-1.png output/first.png\ncp reference-1.png output/second.png\n")
        runTest("여러 참조와 결과는 첫 원본 이름을 따르고 기존 파일을 보존한다") {
            guard case .success(let urls) = execute(request([otherReference, original])) else {
                check(false, "여러 이미지 생성 성공"); return
            }
            checkEqual(urls.map(\.lastPathComponent), ["다른.원본_AI_2.png", "다른.원본_AI_3.png"], "원본 확장자만 제거하고 각 결과를 구별")
            checkEqual(try? Data(contentsOf: existing), preservedBytes, "같은 이름의 기존 파일 보존")
        }
        try script("printf '%s' '\(originalBytes.base64EncodedString())' | /usr/bin/base64 -D > output/result.png\n")
        runTest("참조 없이 생성한 이미지는 기존 UUID 파일명을 유지한다") {
            guard case .success(let urls) = execute(request()) else { check(false, "참조 없는 생성 성공"); return }
            checkEqual(urls.count, 1, "결과 수")
            let name = urls[0].deletingPathExtension().lastPathComponent
            check(name.hasPrefix("AI-"), "기존 AI 접두어 유지")
            check(UUID(uuidString: String(name.dropFirst(3))) != nil, "UUID 파일명 유지")
            checkEqual(urls[0].pathExtension, "png", "PNG 출력 유지")
        }
        try script("echo 'not an image' > output/fake.png\n")
        runTest("AI 잘못된 이미지와 빈 출력을 성공으로 표시하지 않는다") {
            guard case .failure = execute(request()) else { check(false, "잘못된 이미지 거부"); return }
        }
        try script("exit 0\n")
        runTest("AI CLI가 텍스트만 반환하면 생성 실패로 처리한다") {
            guard case .failure = execute(request()) else { check(false, "빈 출력 거부"); return }
        }
        try script("echo login-required\nexit 7\n")
        runTest("AI CLI 실패 시 진단 가능한 오류를 제공한다") {
            guard case .failure(let error) = execute(request()) else { check(false, "종료 코드 확인"); return }
            check(error.localizedDescription.contains("7"), "종료 코드 표시")
            check(error.localizedDescription.contains("작업 기록"), "진단 경로 표시")
        }
        try script("ln -s ../reference-1.png output/linked.png\n")
        runTest("AI 출력의 심볼릭 링크를 저장하지 않는다") {
            guard case .failure = execute(request([original])) else { check(false, "심볼릭 링크 거부"); return }
        }
        let marker = root.appendingPathComponent("started")
        try script("echo started > '\(marker.path)'\nexec /bin/sleep 30\n")
        runTest("AI 실행 중 사용자 취소로 CLI가 종료된다") {
            let service = AIImageGenerationService()
            var result: Result<[URL], Error>?
            Task { @MainActor in
                do { result = .success(try await service.generate(request())) }
                catch { result = .failure(error) }
            }
            check(waitUntil(timeout: 5) { FileManager.default.fileExists(atPath: marker.path) }, "CLI 실행 확인")
            service.cancel()
            check(waitUntil(timeout: 5) { result != nil }, "취소 후 종료")
            guard case .failure(let error) = result else { check(false, "취소된 결과 저장 방지"); return }
            check(error.localizedDescription.contains("취소"), "취소 이유 표시")
        }
        try script("trap '' TERM\necho started > '\(marker.path)'\nexec /bin/sleep 30\n")
        try? FileManager.default.removeItem(at: marker)
        runTest("종료 신호를 무시하는 CLI도 취소 후 작업을 풀어준다") {
            let service = AIImageGenerationService()
            var result: Result<[URL], Error>?
            Task { @MainActor in
                do { result = .success(try await service.generate(request())) }
                catch { result = .failure(error) }
            }
            check(waitUntil(timeout: 5) { FileManager.default.fileExists(atPath: marker.path) }, "무응답 CLI 시작")
            service.cancel()
            check(waitUntil(timeout: 5) { result != nil }, "강제 종료 후 완료")
            guard case .failure = result else { check(false, "취소를 성공으로 표시하지 않는다"); return }
        }
        runTest("AI 취소된 작업은 실행하지 않는다") {
            let service = AIImageGenerationService()
            service.cancel()
            guard case .failure(let error) = execute(request(), service: service) else { check(false, "취소 반영"); return }
            check(error.localizedDescription.contains("취소"), "취소 이유 표시")
        }
        runTest("Codex 모델 선택은 독립 인자이며 기본 모델은 CLI 설정을 따른다") {
            var request = AIImageRequest(provider: .codex, executable: "codex", prompt: "test", references: [], destination: root)
            check(!AIImageGenerationService.arguments(for: request, workspace: root, references: []).contains("--model"), "기본 모델 인자 생략")
            request.model = "fixture-model"
            let args = AIImageGenerationService.arguments(for: request, workspace: root, references: [])
            check(args.firstIndex(of: "--model").map { args[$0 + 1] == "fixture-model" } == true, "선택 모델 전달")
        }
        runTest("Codex 참조 경로와 프롬프트를 독립된 인자로 전달한다") {
            let codex = AIImageRequest(provider: .codex, executable: "codex", prompt: "$(touch unsafe)", references: [original], destination: destination)
            let arguments = AIImageGenerationService.arguments(for: codex, workspace: root, references: [original])
            check(arguments.contains(original.path), "특수문자 경로 보존")
            check(arguments.contains("workspace-write"), "작업 디렉터리 쓰기 권한")
            check(arguments.last?.contains(codex.prompt) == true, "프롬프트 보존")
            check(!arguments.contains("--dangerously-bypass-approvals-and-sandbox"), "샌드박스 유지")
        }
    } catch { check(false, "AI 테스트 준비 실패: \(error)") }
}
