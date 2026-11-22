import AppKit

@MainActor
func runUpdateWindowTests() {
    let release = AppRelease(version: "2.1.0", notes: "## 주요 변경\n- 업데이트를 앱에서 설치",
                             pageURL: URL(string: "https://example.com/releases/v2.1.0")!,
                             assetURL: URL(string: "https://example.com/JenaImage.dmg")!, assetSize: 10, sha256: "ab")
    let writable = FileManager.default.temporaryDirectory.appendingPathComponent("jena-update-ui-\(UUID().uuidString)/JenaImage.app")
    try? FileManager.default.createDirectory(at: writable, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: writable.deletingLastPathComponent()) }

    func make(current: String = "2.0.1", bundle: URL = writable) -> UpdateWindowController {
        let controller = UpdateWindowController(currentVersion: current, bundleURL: bundle, bundleIdentifier: "com.jenalab.jenaimage")
        controller.window?.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        controller.fetchLatest = { release }
        return controller
    }

    runTest("최신 버전이면 그렇게 알리고 설치 버튼을 두지 않는다") {
        let controller = make(current: "2.1.0")
        controller.showAndCheck()
        check(waitUntil { controller.state == .upToDate }, "최신 상태: \(controller.state)")
        check(controller.titleLabel.stringValue.contains("최신"), "안내 문구: \(controller.titleLabel.stringValue)")
        checkEqual(controller.primaryButton.title, "확인", "닫기 버튼")
        checkEqual(controller.primaryButton.keyEquivalent, "\r", "확인은 Enter로 닫힘")
        controller.close()
    }

    runTest("새 버전이면 변경 내용을 보이고 설치하면 교체를 맡긴 뒤 앱을 종료한다") {
        let controller = make()
        var calls: [String] = []
        controller.download = { _, progress in calls.append("download"); progress(0.5); progress(1); return URL(fileURLWithPath: "/tmp/x.dmg") }
        controller.stage = { dmg, rel in calls.append("stage \(dmg.lastPathComponent) \(rel.version)"); return URL(fileURLWithPath: "/tmp/staged.app") }
        controller.launchReplacement = { staged in calls.append("replace \(staged.lastPathComponent)") }
        controller.terminate = { calls.append("terminate") }
        controller.showAndCheck()
        check(waitUntil { controller.state == .available(release) }, "새 버전 상태: \(controller.state)")
        check(controller.titleLabel.stringValue.contains("2.1.0"), "새 버전 표시")
        check(controller.notesView.string.contains("업데이트를 앱에서 설치"), "변경 내용 표시")
        check(!controller.notesView.string.contains("##"), "제목 기호는 숨김")
        checkEqual(controller.primaryButton.title, "설치", "설치 버튼")
        checkEqual(controller.primaryButton.keyEquivalent, "", "설치는 Enter로 시작하지 않음")
        controller.primaryButton.performClick(nil)
        check(waitUntil { calls.last == "terminate" }, "종료까지 진행: \(calls)")
        checkEqual(calls, ["download", "stage x.dmg 2.1.0", "replace staged.app", "terminate"], "설치 순서")
        checkEqual(controller.state, .restarting, "재시작 상태")
        controller.close()
    }

    runTest("직접 교체할 수 없는 위치면 다운로드 페이지로 안내한다") {
        let controller = make(bundle: URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/A/d/JenaImage.app"))
        var opened: URL?
        controller.openURL = { opened = $0 }
        controller.showAndCheck()
        check(waitUntil { controller.state == .available(release) }, "새 버전 상태")
        checkEqual(controller.primaryButton.title, "다운로드 페이지 열기", "대체 버튼")
        check(controller.detailLabel.stringValue.contains("격리"), "이유 안내: \(controller.detailLabel.stringValue)")
        controller.primaryButton.performClick(nil)
        checkEqual(opened, release.pageURL, "릴리스 페이지 열기")
        controller.close()
    }

    runTest("조회나 검증에 실패하면 이유를 보이고 앱을 종료하지 않는다") {
        let failing = make()
        failing.fetchLatest = { throw AppUpdateError.rateLimited }
        failing.showAndCheck()
        check(waitUntil { if case .failed = failing.state { return true }; return false }, "조회 실패 상태")
        check(failing.detailLabel.stringValue.contains("한도"), "조회 실패 이유: \(failing.detailLabel.stringValue)")
        checkEqual(failing.primaryButton.title, "다시 시도", "재시도 버튼")
        failing.close()

        let mismatch = make()
        var terminated = false
        mismatch.download = { _, _ in throw AppUpdateError.digestMismatch }
        mismatch.terminate = { terminated = true }
        mismatch.showAndCheck()
        check(waitUntil { mismatch.state == .available(release) }, "새 버전 상태")
        mismatch.primaryButton.performClick(nil)
        check(waitUntil { if case .failed = mismatch.state { return true }; return false }, "검증 실패 상태")
        check(mismatch.detailLabel.stringValue.contains("일치하지 않아요"), "검증 실패 이유")
        check(!terminated, "실패 시 종료하지 않음")
        mismatch.close()
    }
}
