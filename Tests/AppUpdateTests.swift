import Foundation

func runAppUpdateTests() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("jena-update-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    runTest("버전은 숫자 단위로 비교하고 v 접두어·꼬리표를 무시한다") {
        check(AppVersion.isNewer("2.0.10", than: "2.0.9"), "2.0.10 > 2.0.9")
        check(AppVersion.isNewer("v2.1", than: "2.0.9"), "v2.1 > 2.0.9")
        check(AppVersion.isNewer("3", than: "2.9.9"), "3 > 2.9.9")
        check(!AppVersion.isNewer("2.0.1", than: "2.0.1"), "같은 버전은 새 버전이 아님")
        check(!AppVersion.isNewer("2.0", than: "2.0.0"), "2.0 == 2.0.0")
        check(!AppVersion.isNewer("2.0.0", than: "2.0.1"), "낮은 버전")
        check(!AppVersion.isNewer("2.1.0-beta", than: "2.1.0"), "꼬리표는 무시")
    }

    let digest = String(repeating: "a", count: 64)
    func releaseJSON(assets: String) -> Data {
        """
        {"tag_name":"v2.1.0","name":"v2.1.0","html_url":"https://github.com/jenalab-com/jena-image/releases/tag/v2.1.0",
         "body":"## 변경\\n- 업데이트","assets":[\(assets)]}
        """.data(using: .utf8)!
    }
    let dmgAsset = """
    {"name":"JenaImage.dmg","size":1234,"digest":"sha256:\(digest)",
     "browser_download_url":"https://github.com/jenalab-com/jena-image/releases/download/v2.1.0/JenaImage.dmg"}
    """

    runTest("최신 릴리스 응답에서 버전·노트·DMG·해시를 읽는다") {
        do {
            let release = try AppUpdateService.parseRelease(releaseJSON(assets: #"{"name":"notes.txt","size":1,"browser_download_url":"https://x/notes.txt"}, "# + dmgAsset))
            checkEqual(release.version, "2.1.0", "버전")
            checkEqual(release.notes, "## 변경\n- 업데이트", "노트")
            checkEqual(release.assetURL.lastPathComponent, "JenaImage.dmg", "DMG 선택")
            checkEqual(release.assetSize, 1234, "크기")
            checkEqual(release.sha256, digest, "해시")
            checkEqual(release.pageURL.absoluteString, "https://github.com/jenalab-com/jena-image/releases/tag/v2.1.0", "릴리스 페이지")
        } catch { check(false, "파싱 실패: \(error)") }
    }

    runTest("DMG가 없거나 응답이 깨지면 명확한 오류를 낸다") {
        do {
            _ = try AppUpdateService.parseRelease(releaseJSON(assets: ""))
            check(false, "DMG 없음은 실패해야 함")
        } catch { checkEqual(error as? AppUpdateError, .missingAsset, "DMG 없음") }
        do {
            _ = try AppUpdateService.parseRelease(Data("not json".utf8))
            check(false, "깨진 응답은 실패해야 함")
        } catch { checkEqual(error as? AppUpdateError, .badResponse, "깨진 응답") }
    }

    let payload = root.appendingPathComponent("payload.dmg")
    try? Data("jena update payload".utf8).write(to: payload)
    let payloadDigest = (try? AppUpdateService.sha256Hex(of: payload)) ?? ""
    func localRelease(sha: String?, size: Int? = nil) -> AppRelease {
        AppRelease(version: "2.1.0", notes: "", pageURL: URL(string: "https://example.com")!,
                   assetURL: payload, assetSize: size ?? 19, sha256: sha)
    }

    runTest("내려받은 파일은 해시와 크기가 모두 맞아야 통과한다") {
        checkEqual(payloadDigest.count, 64, "SHA-256 16진수 길이")
        do { try AppUpdateService.verify(file: payload, release: localRelease(sha: payloadDigest)) }
        catch { check(false, "정상 파일 검증 실패: \(error)") }
        do { try AppUpdateService.verify(file: payload, release: localRelease(sha: digest)); check(false, "해시 불일치 통과") }
        catch { checkEqual(error as? AppUpdateError, .digestMismatch, "해시 불일치") }
        do { try AppUpdateService.verify(file: payload, release: localRelease(sha: payloadDigest, size: 20)); check(false, "크기 불일치 통과") }
        catch { checkEqual(error as? AppUpdateError, .sizeMismatch, "크기 불일치") }
        do { try AppUpdateService.verify(file: payload, release: localRelease(sha: nil)); check(false, "해시 없는 릴리스 통과") }
        catch { checkEqual(error as? AppUpdateError, .missingDigest, "해시 없음") }
    }

    runTest("확인 주소에서 릴리스를 읽고 진행률과 함께 내려받아 검증한다") {
        let feed = root.appendingPathComponent("latest.json")
        let json = """
        {"tag_name":"v2.1.0","html_url":"https://example.com/r","body":"",
         "assets":[{"name":"JenaImage.dmg","size":19,"digest":"sha256:\(payloadDigest)","browser_download_url":"\(payload.absoluteString)"}]}
        """
        try? json.write(to: feed, atomically: true, encoding: .utf8)
        let service = AppUpdateService(feedURL: feed)
        var outcome: Result<URL, Error>?
        let fractions = UpdateTestBox<[Double]>([])
        Task {
            do {
                let release = try await service.latestRelease()
                outcome = .success(try await service.download(release) { fractions.append($0) })
            } catch { outcome = .failure(error) }
        }
        check(waitUntil(timeout: 10) { outcome != nil }, "내려받기 완료")
        guard case .success(let file)? = outcome else { return check(false, "내려받기 실패: \(String(describing: outcome))") }
        checkEqual(try? Data(contentsOf: file), try? Data(contentsOf: payload), "같은 내용")
        check(fractions.value.last == 1, "진행률 끝은 1: \(fractions.value)")
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    runTest("번역된 위치·읽기 전용 볼륨·쓰기 불가 폴더에서는 직접 설치하지 않는다") {
        let writable = root.appendingPathComponent("Apps/JenaImage.app")
        try? FileManager.default.createDirectory(at: writable, withIntermediateDirectories: true)
        checkEqual(AppUpdateInstaller.installability(of: writable), .ready, "쓰기 가능한 위치")
        let translocated = URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/JenaImage.app")
        checkEqual(AppUpdateInstaller.installability(of: translocated), .translocated, "App Translocation")
        let locked = root.appendingPathComponent("Locked/JenaImage.app")
        try? FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.deletingLastPathComponent().path)
        checkEqual(AppUpdateInstaller.installability(of: locked), .notWritable, "상위 폴더 쓰기 불가")
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.deletingLastPathComponent().path)
    }

    // 테스트용 앱 번들과 DMG
    func makeBundle(at url: URL, id: String, version: String, marker: String) {
        let contents = url.appendingPathComponent("Contents")
        try? FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleShortVersionString": version,
                                    "CFBundleExecutable": "JenaImage", "CFBundlePackageType": "APPL"]
        (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
        try? marker.write(to: contents.appendingPathComponent("MacOS/JenaImage"), atomically: true, encoding: .utf8)
    }
    func makeDMG(id: String, version: String, name: String) -> URL {
        let src = root.appendingPathComponent("src-\(name)")
        makeBundle(at: src.appendingPathComponent("JenaImage.app"), id: id, version: version, marker: "new")
        try? FileManager.default.createSymbolicLink(at: src.appendingPathComponent("Applications"),
                                                    withDestinationURL: URL(fileURLWithPath: "/Applications"))
        let dmg = root.appendingPathComponent("\(name).dmg")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = ["create", "-quiet", "-volname", "JenaImage", "-srcfolder", src.path, "-format", "UDZO", "-ov", dmg.path]
        try? p.run(); p.waitUntilExit()
        return dmg
    }

    runTest("DMG 같은 읽기 전용 볼륨에서 실행 중이면 직접 설치하지 않는다") {
        let dmg = makeDMG(id: "com.jenalab.jenaimage", version: "2.1.0", name: "readonly")
        let mount = root.appendingPathComponent("ro-mount")
        try? FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        func hdiutil(_ args: [String]) { let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil"); p.arguments = args; try? p.run(); p.waitUntilExit() }
        hdiutil(["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path])
        checkEqual(AppUpdateInstaller.installability(of: mount.appendingPathComponent("JenaImage.app")), .readOnlyVolume, "읽기 전용 볼륨")
        hdiutil(["detach", "-quiet", "-force", mount.path])
    }

    let target = root.appendingPathComponent("Install/JenaImage.app")
    makeBundle(at: target, id: "com.jenalab.jenaimage", version: "2.0.1", marker: "old")
    let installer = AppUpdateInstaller()

    runTest("DMG 안 앱의 번들 ID와 버전이 맞으면 같은 폴더 옆에 준비하고 마운트를 해제한다") {
        let dmg = makeDMG(id: "com.jenalab.jenaimage", version: "2.1.0", name: "good")
        do {
            let staged = try installer.stage(dmg: dmg, expectedVersion: "2.1.0",
                                             bundleIdentifier: "com.jenalab.jenaimage", target: target)
            checkEqual(staged.deletingLastPathComponent().deletingLastPathComponent(), target.deletingLastPathComponent(),
                       "대상과 같은 폴더 안 임시 폴더")
            checkEqual(try? String(contentsOf: staged.appendingPathComponent("Contents/MacOS/JenaImage"), encoding: .utf8),
                       "new", "새 번들 복사")
            let info = Process()
            let pipe = Pipe()
            info.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            info.arguments = ["info"]
            info.standardOutput = pipe
            try? info.run(); info.waitUntilExit()
            let attached = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            check(!attached.contains(dmg.path), "DMG 마운트 해제")
            try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
        } catch { check(false, "준비 실패: \(error)") }
    }

    runTest("번들 ID나 버전이 다르면 준비하지 않고 흔적을 남기지 않는다") {
        for (id, version, name) in [("com.other.app", "2.1.0", "wrong-id"), ("com.jenalab.jenaimage", "2.0.9", "wrong-version")] {
            let dmg = makeDMG(id: id, version: version, name: name)
            do {
                _ = try installer.stage(dmg: dmg, expectedVersion: "2.1.0", bundleIdentifier: "com.jenalab.jenaimage", target: target)
                check(false, "\(name)는 거부해야 함")
            } catch {
                if case .invalidBundle? = error as? AppUpdateError {} else { check(false, "\(name) 오류 종류: \(error)") }
            }
        }
        let leftovers = ((try? FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path)) ?? [])
            .filter { $0.hasPrefix(".JenaImage-update") }
        checkEqual(leftovers, [], "임시 폴더 정리")
    }

    runTest("교체 스크립트는 앱 종료를 기다렸다 교체하고 다시 실행한다") {
        let staging = target.deletingLastPathComponent().appendingPathComponent(".JenaImage-update-test")
        let staged = staging.appendingPathComponent("JenaImage.app")
        makeBundle(at: staged, id: "com.jenalab.jenaimage", version: "2.1.0", marker: "new")
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sleep")
        waiter.arguments = ["0.5"]
        try? waiter.run()
        let relaunched = root.appendingPathComponent("relaunched")
        do {
            let script = try installer.launchReplacement(staged: staged, target: target, waitingFor: waiter.processIdentifier,
                                                        relaunch: ["/usr/bin/touch", relaunched.path])
            check(waitUntil(timeout: 10) { !script.isRunning }, "스크립트 종료")
            checkEqual(script.terminationStatus, 0, "성공 종료")
        } catch { check(false, "스크립트 실행 실패: \(error)") }
        checkEqual(try? String(contentsOf: target.appendingPathComponent("Contents/MacOS/JenaImage"), encoding: .utf8), "new", "교체됨")
        check(!FileManager.default.fileExists(atPath: staging.path), "임시 폴더 제거")
        check(FileManager.default.fileExists(atPath: relaunched.path), "재실행 명령 수행")
    }

    runTest("새 앱을 옮기지 못하면 기존 앱을 되돌리고 그 앱을 다시 실행한다") {
        let staging = target.deletingLastPathComponent().appendingPathComponent(".JenaImage-update-missing")
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let relaunched = root.appendingPathComponent("relaunched-old")
        let before = try? String(contentsOf: target.appendingPathComponent("Contents/MacOS/JenaImage"), encoding: .utf8)
        do {
            let script = try installer.launchReplacement(staged: staging.appendingPathComponent("JenaImage.app"), target: target,
                                                        waitingFor: 999_999, relaunch: ["/usr/bin/touch", relaunched.path])
            check(waitUntil(timeout: 10) { !script.isRunning }, "스크립트 종료")
            check(script.terminationStatus != 0, "실패 종료 코드")
        } catch { check(false, "스크립트 실행 실패: \(error)") }
        checkEqual(try? String(contentsOf: target.appendingPathComponent("Contents/MacOS/JenaImage"), encoding: .utf8), before, "기존 앱 보존")
        check(FileManager.default.fileExists(atPath: relaunched.path), "기존 앱 재실행")
        try? FileManager.default.removeItem(at: staging)
    }
}

/// 비동기 콜백에서 값을 모으는 테스트 도우미.
final class UpdateTestBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func append<E>(_ element: E) where T == [E] { lock.lock(); stored.append(element); lock.unlock() }
}
