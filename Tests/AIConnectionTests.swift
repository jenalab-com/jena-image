import Foundation

func runAIConnectionTests() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("jena-connection-test-\(UUID().uuidString)")
    do {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = root.appendingPathComponent("codex fixture")
        func script(_ body: String) throws {
            try ("#!/bin/sh\n" + body).write(to: fixture, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
        }
        func checkConnection(path: String, timeout: TimeInterval = 2) -> AIConnectionStatus? {
            var result: AIConnectionStatus?
            Task { @MainActor in result = await AIConnectionService().check(path: path, timeout: timeout) }
            check(waitUntil(timeout: timeout + 3) { result != nil }, "계정 조회가 제한 시간 안에 끝난다")
            return result
        }
        runTest("CLI 미설치와 실행 파일이 아닌 디렉터리를 구분한다") {
            checkEqual(checkConnection(path: root.appendingPathComponent("missing").path)?.state, .missing, "미설치")
            check(AIExecutableLocator.resolve(root.path) == nil, "실행 권한 있는 폴더를 CLI로 인정하지 않는다")
        }
        func accountScript(_ result: String) throws {
            try script("""
            [ "$1" = app-server ] || exit 9
            IFS= read -r init
            echo '{"id":1,"result":{}}'
            IFS= read -r initialized
            IFS= read -r account
            case "$account" in *refreshToken*) ;; *) exit 8;; esac
            echo '{"id":2,"result":\(result)}'
            """)
        }
        try accountScript("{\"account\":{\"type\":\"chatgpt\",\"email\":\"fixture@example.test\",\"planType\":\"plus\"},\"requiresOpenaiAuth\":true}")
        runTest("재확인은 CLI 계정 프로토콜로 로그인 계정을 읽는다") {
            let result = checkConnection(path: fixture.path)
            checkEqual(result?.state, .connected, "로그인 연결: \(result?.detail ?? "없음")")
            checkEqual(result?.account, "ChatGPT · fixture@example.test · plus", "이메일과 요금제")
        }
        try accountScript("{\"account\":null,\"requiresOpenaiAuth\":true}")
        runTest("로그아웃 후 재확인하면 이전 계정을 유지하지 않는다") {
            let result = checkConnection(path: fixture.path)
            checkEqual(result?.state, .signedOut, "로그인 필요")
            check(result?.account == nil, "계정 제거")
        }
        runTest("API 키 계정에 이메일을 만들어 표시하지 않는다") {
            let result = AIConnectionService.accountStatus(result: ["account": ["type": "apiKey"]], executable: fixture)
            checkEqual(result.state, .connected, "API 키 연결")
            checkEqual(result.account, "API 키 연결 · 계정 이메일 미제공", "키 값을 표시하지 않는다")
        }
        try script("""
        IFS= read -r init
        echo '{"id":1,"result":{}}'
        IFS= read -r initialized
        IFS= read -r request
        case "$request" in *model*list*) ;; *) exit 8;; esac
        case "$request" in
          *page2*) echo '{"id":2,"result":{"data":[{"model":"second","displayName":"Second"},{"model":"first"}],"nextCursor":null}}';;
          *) echo '{"id":2,"result":{"data":[{"model":"first","displayName":"First","inputModalities":["text","image"]},{"model":"hidden","hidden":true},{"model":"text-only","inputModalities":["text"]}],"nextCursor":"page2"}}';;
        esac
        """)
        runTest("모델 목록은 페이지를 합치고 숨김과 이미지 미지원 모델을 제외한다") {
            var result: [AIModelOption]?
            var failure: Error?
            Task { @MainActor in
                do { result = try await AIConnectionService().models(path: fixture.path, timeout: 2) }
                catch { failure = error }
            }
            check(waitUntil { result != nil || failure != nil }, "모델 조회 완료")
            check(failure == nil, "모델 조회 오류: \(failure?.localizedDescription ?? "없음")")
            checkEqual(result, [.init(id: "first", title: "First"), .init(id: "second", title: "Second")], "페이지, 필터, 중복 제거 및 구형 목록 호환")
        }
        try script("""
        IFS= read -r init
        echo '{"id":1,"result":{}}'
        IFS= read -r initialized
        IFS= read -r request
        case "$request" in *account*rateLimits*read*) ;; *) exit 8;; esac
        echo '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":2000000000},"secondary":null}}}'
        """)
        runTest("사용 현황은 CLI 사용량 프로토콜에서 읽는다") {
            var result: [AIUsageWindow]?
            var failure: Error?
            Task { @MainActor in
                do { result = try await AIConnectionService().usage(path: fixture.path, timeout: 2) }
                catch { failure = error }
            }
            check(waitUntil { result != nil || failure != nil }, "사용량 조회 종료")
            checkEqual(result?.first?.usedPercent, 25, "사용 비율")
            checkEqual(result?.first?.resetsAt, Date(timeIntervalSince1970: 2000000000), "초 단위 리셋 시각")
        }
        runTest("사용량 기간과 리셋 남은 시간의 일 시 분 경계를 표시한다") {
            let now = Date(timeIntervalSince1970: 2000000000)
            func summary(_ seconds: TimeInterval) -> String {
                AIUsageWindow(title: "주간", usedPercent: 35, resetsAt: now.addingTimeInterval(seconds)).summary(now: now)
            }
            checkEqual(summary(183600), "주간 · 사용 35% · 리셋 2d 3h", "일 시간")
            checkEqual(summary(12000), "주간 · 사용 35% · 리셋 3h 20m", "시간 분")
            checkEqual(summary(86400), "주간 · 사용 35% · 리셋 1d 0h", "하루 경계")
            checkEqual(summary(-1), "주간 · 사용 35% · 리셋 0h 0m", "지난 시각 음수 방지")
            let parsed = AIUsageWindow.parse(["rateLimitsByLimitId": ["codex": ["primary": ["usedPercent": 0, "windowDurationMins": 300], "secondary": ["usedPercent": 70, "windowDurationMins": 10080]]]])
            checkEqual(parsed.map(\.title), ["5시간", "주간"], "두 한도 분리")
            check(parsed[0].summary(now: now).contains("리셋 정보 없음"), "없는 리셋 시각을 꾸미지 않는다")
            check(AIUsageWindow.parse([:]).isEmpty, "사용량 미제공")
        }
        try script("exit 7")
        runTest("CLI 오류를 미설치 또는 로그인 완료로 오인하지 않는다") {
            checkEqual(checkConnection(path: fixture.path)?.state, .failed, "프로토콜 실패")
        }
        try script("trap '' TERM\nexec /bin/sleep 30")
        runTest("응답 없는 CLI의 연결 확인은 시간 제한으로 끝난다") {
            checkEqual(checkConnection(path: fixture.path, timeout: 0.2)?.state, .failed, "타임아웃")
        }
    } catch { check(false, "계정 테스트 준비: \(error)") }
}
