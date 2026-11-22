import AppKit

/// 삭제만 바꿔 끼운 파일 서비스. 나머지는 실제 구현에 맡긴다.
private final class TrashStubService: FileServiceProtocol {
    enum TrashBehavior { case succeeds, unavailable, fails }
    private let real = FileService()
    /// 휴지통 이동의 결과. `unavailable`은 클라우드 폴더에서 macOS가 거절하는 경우다.
    var trash: TrashBehavior = .unavailable
    /// 이 이름의 파일은 휴지통 이동이 된다(여럿을 섞어 시험할 때).
    var trashableNames: Set<String> = []
    var permanentDeleteSucceeds = true
    private(set) var permanentlyDeleted: [URL] = []

    func contentsOfFolder(at url: URL, sortKey: SortKey, ascending: Bool) -> Result<(folders: [URL], images: [URL]), FileServiceError> {
        real.contentsOfFolder(at: url, sortKey: sortKey, ascending: ascending)
    }
    func recursiveImages(at url: URL, sortKey: SortKey, ascending: Bool) -> Result<[URL], FileServiceError> {
        real.recursiveImages(at: url, sortKey: sortKey, ascending: ascending)
    }
    func moveFile(from source: URL, to destinationFolder: URL) -> Result<URL, FileServiceError> { real.moveFile(from: source, to: destinationFolder) }
    func copyFile(from source: URL, to destinationFolder: URL) -> Result<URL, FileServiceError> { real.copyFile(from: source, to: destinationFolder) }
    func duplicateFile(at url: URL) -> Result<URL, FileServiceError> { real.duplicateFile(at: url) }
    func renameFile(at url: URL, newName: String) -> Result<URL, FileServiceError> { real.renameFile(at: url, newName: newName) }
    func createFolder(in parentURL: URL, name: String) -> Result<URL, FileServiceError> { real.createFolder(in: parentURL, name: name) }
    func fileExists(at url: URL) -> Bool { real.fileExists(at: url) }

    func trashFile(at url: URL) -> Result<Void, FileServiceError> {
        let behavior = trashableNames.contains(url.lastPathComponent) ? .succeeds : trash
        switch behavior {
        case .succeeds:
            try? FileManager.default.removeItem(at: url)   // 실제 휴지통을 건드리지 않는다
            return .success(())
        case .unavailable:
            return .failure(.trashUnavailable(url, .noPermission, "휴지통으로 옮길 권한이 없습니다"))
        case .fails:
            return .failure(.operationFailed("파일을 삭제할 수 없습니다: 다른 오류"))
        }
    }
    func deleteFilePermanently(at url: URL) -> Result<Void, FileServiceError> {
        guard permanentDeleteSucceeds else { return .failure(.operationFailed("파일을 삭제할 수 없습니다: 바로 삭제 실패")) }
        permanentlyDeleted.append(url)
        try? FileManager.default.removeItem(at: url)
        return .success(())
    }
    func resetLog() { permanentlyDeleted = [] }
}

/// 휴지통으로 옮길 수 없는 폴더(Google Drive 등)에서의 삭제 — 확인을 받은 뒤에만 바로 삭제한다.
@MainActor
func runDeleteFallbackTests(directory: URL) {
    let root = directory.appendingPathComponent("delete-fallback-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let suite = "jena-delete-fallback-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let service = TrashStubService()
    let controller = MainWindowController(categoryStore: CategoryStore(defaults: defaults),
                                          settings: AppSettings(defaults: defaults), fileService: service)
    defer {
        controller.folderLoadGeneration += 1
        for url in controller.folderWatcher.watchedURLs { controller.folderWatcher.unwatch(url) }
        controller.window?.close()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    func makeImage(_ name: String) -> URL {
        let url = root.appendingPathComponent(name)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }
    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    /// 목록의 파일 이름. 주소 표기(`/var`·`/private/var`)가 달라도 비교되게 이름으로 본다.
    func listedNames() -> [String] { controller.browserVC.listedImageURLs.map(\.lastPathComponent).sorted() }
    func settled() -> Bool { !controller.browserVC.isFolderLoading }
    func show() {
        controller.navigateToFolder(root)
        _ = waitUntil(timeout: 5) { settled() }
    }
    func clear() {
        for name in (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
        }
    }

    // 확인 창과 오류 창을 바꿔 끼운다 — 테스트가 모달을 띄우지 않는다.
    var asked: [[URL]] = []
    var answer = true
    controller.askPermanentDelete = { urls in asked.append(urls); return answer }
    var reported: [[(url: URL, reason: String)]] = []
    controller.onDeleteFailure = { reported.append($0) }
    func reset(trash: TrashStubService.TrashBehavior, answer newAnswer: Bool = true, permanentWorks: Bool = true, trashable: Set<String> = []) {
        clear(); asked = []; reported = []; answer = newAnswer
        service.trash = trash; service.permanentDeleteSucceeds = permanentWorks; service.trashableNames = trashable; service.resetLog()
    }

    runTest("휴지통에 넣을 수 없으면 묻고, 확인하면 바로 삭제한다") {
        reset(trash: .unavailable, answer: true)
        let a = makeImage("a.png"), b = makeImage("b.png"); _ = makeImage("keep.png")
        show()
        var deleted: [URL]?
        controller.trashConfirmed(urls: [a, b]) { deleted = $0 }
        checkEqual(asked.map { Set($0) }, [Set([a, b])], "한 번에 물음")
        check(!exists(a) && !exists(b), "두 파일 삭제")
        checkEqual(Set(service.permanentlyDeleted), Set([a, b]), "고른 항목만 바로 삭제")
        checkEqual(Set(deleted ?? []), Set([a, b]), "지워진 항목을 돌려줌")
        check(reported.isEmpty, "오류 알림 없음")
        check(waitUntil(timeout: 5) { settled() && listedNames() == ["keep.png"] }, "목록에서 사라지고 나머지는 그대로")
    }

    runTest("바로 삭제를 그만두면 아무것도 지우지 않고 오류도 알리지 않는다") {
        reset(trash: .unavailable, answer: false)
        let a = makeImage("a.png")
        show()
        var deleted: [URL]?
        controller.trashConfirmed(urls: [a]) { deleted = $0 }
        checkEqual(asked.count, 1, "물어봄")
        check(exists(a), "파일은 그대로")
        check(service.permanentlyDeleted.isEmpty, "바로 삭제 안 함")
        checkEqual(deleted, [], "지워진 항목 없음 — 뷰어는 보던 이미지를 빼지 않는다")
        check(reported.isEmpty, "그만둔 것은 오류가 아니다")
        check(waitUntil(timeout: 5) { settled() && listedNames() == ["a.png"] }, "목록에 그대로")
    }

    runTest("휴지통 이동이 되면 묻지 않는다") {
        reset(trash: .succeeds)
        let a = makeImage("a.png")
        show()
        var deleted: [URL]?
        controller.trashConfirmed(urls: [a]) { deleted = $0 }
        check(!exists(a), "지워짐")
        check(asked.isEmpty && service.permanentlyDeleted.isEmpty, "묻지도 바로 지우지도 않음")
        checkEqual(deleted, [a], "지워진 항목")
        check(waitUntil(timeout: 5) { settled() && listedNames().isEmpty }, "목록 갱신")
    }

    runTest("섞여 있으면 휴지통에 못 넣는 것만 묻는다") {
        reset(trash: .unavailable, answer: false, trashable: ["local.png"])
        let local = makeImage("local.png"), cloud = makeImage("cloud.png")
        show()
        var deleted: [URL]?
        controller.trashConfirmed(urls: [local, cloud]) { deleted = $0 }
        checkEqual(asked, [[cloud]], "거절된 것만 물음")
        check(!exists(local) && exists(cloud), "되는 것은 휴지통으로, 그만둔 것은 그대로")
        checkEqual(deleted, [local], "실제로 지워진 것만")
        check(reported.isEmpty, "오류 알림 없음")
    }

    runTest("바로 삭제도 실패하면 무엇이 왜 안 지워졌는지 알린다") {
        reset(trash: .unavailable, answer: true, permanentWorks: false)
        let a = makeImage("stuck.png")
        show()
        var deleted: [URL]?
        controller.trashConfirmed(urls: [a]) { deleted = $0 }
        check(exists(a), "파일은 그대로")
        checkEqual(deleted, [], "지워진 항목 없음")
        checkEqual(reported.count, 1, "한 번 알림")
        checkEqual(reported.first?.map(\.url) ?? [], [a], "실패한 파일")
        let message = MainWindowController.deleteFailureMessage(reported.first ?? [], total: 1)
        check(message.contains("1개 항목을 삭제하지 못했습니다.") && message.contains("stuck.png") && message.contains("바로 삭제 실패"), "이름과 이유가 든 안내")
        check(waitUntil(timeout: 5) { settled() && listedNames() == ["stuck.png"] }, "목록에 그대로")
    }

    runTest("권한 문제가 아닌 실패에는 바로 삭제를 권하지 않는다") {
        reset(trash: .fails)
        let a = makeImage("a.png")
        show()
        controller.trashConfirmed(urls: [a])
        check(asked.isEmpty, "묻지 않음")
        check(exists(a) && service.permanentlyDeleted.isEmpty, "지우지 않음")
        checkEqual(reported.first?.first?.reason, "파일을 삭제할 수 없습니다: 다른 오류", "원래 이유를 알림")
    }

    runTest("안내 문구") {
        let one = [URL(fileURLWithPath: "/x/사진 1.jpeg")]
        checkEqual(MainWindowController.permanentDeleteQuestion(one), "'사진 1.jpeg'을(를) 휴지통에 넣을 수 없습니다. 바로 삭제할까요?", "하나")
        checkEqual(MainWindowController.permanentDeleteQuestion(one + one + one), "3개 항목을 휴지통에 넣을 수 없습니다. 바로 삭제할까요?", "여럿")
        let failures = (1...5).map { (url: URL(fileURLWithPath: "/x/f\($0).png"), reason: "이유 \($0)") }
        let message = MainWindowController.deleteFailureMessage(failures, total: 8)
        check(message.hasPrefix("8개 중 5개 항목을 삭제하지 못했습니다."), "개수")
        check(message.contains("f1.png") && message.contains("f3.png") && !message.contains("f4.png"), "앞의 셋만")
        check(message.contains("… 외 2개"), "나머지 개수")
    }

    runTest("폴더는 바로 삭제하지 않고, 왜 안 지웠는지 알린다") {
        reset(trash: .unavailable, answer: true)
        let folder = root.appendingPathComponent("모음")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try! Data("x".utf8).write(to: folder.appendingPathComponent("안의 파일.txt"))
        let a = makeImage("a.png")
        show()
        var deleted: [URL]?
        controller.trashConfirmed(urls: [folder, a]) { deleted = $0 }
        checkEqual(asked, [[a]], "파일만 물음")
        check(exists(folder) && exists(folder.appendingPathComponent("안의 파일.txt")), "폴더와 그 안은 그대로")
        check(!service.permanentlyDeleted.contains(folder), "폴더는 바로 삭제에 넘기지 않음")
        checkEqual(deleted, [a], "파일만 지워짐")
        checkEqual(reported.first?.map(\.url) ?? [], [folder], "폴더를 알림")
        check(reported.first?.first?.reason.contains("폴더는 바로 삭제하지 않습니다") == true, "까닭")
    }

    runTest("그만둔 항목의 북마크는 남고, 지운 항목의 북마크는 정리된다") {
        reset(trash: .unavailable, answer: false)
        let a = makeImage("a.png")
        show()
        controller.bookmarkStore.add(a)
        controller.trashConfirmed(urls: [a])
        check(controller.bookmarkStore.contains(a), "그만두면 북마크 유지")
        answer = true
        controller.trashConfirmed(urls: [a])
        check(!exists(a) && !controller.bookmarkStore.contains(a), "지우면 북마크 정리")
    }

    runTest("확인 창은 취소가 기본이고, 권한으로 풀 수 있을 때만 설정 버튼이 있다") {
        let url = [URL(fileURLWithPath: "/x/a.png")]
        let cloud = MainWindowController.makePermanentDeleteAlert(url, refusals: [.noPermission], trashedCount: 0)
        checkEqual(cloud.buttons.map(\.title), ["취소", "바로 삭제", "권한 설정 열기…"], "버튼 순서")
        checkEqual(cloud.buttons[0].keyEquivalent, "\r", "Enter는 취소")
        check(cloud.buttons[1].hasDestructiveAction && cloud.buttons[1].keyEquivalent != "\r", "바로 삭제는 파괴적 동작이고 Enter가 아니다")
        check(cloud.informativeText.contains("전체 디스크 접근 권한") && cloud.informativeText.contains("남을 수도 있습니다"), "클라우드 안내")
        let share = MainWindowController.makePermanentDeleteAlert(url, refusals: [.noTrashOnVolume], trashedCount: 0)
        checkEqual(share.buttons.map(\.title), ["취소", "바로 삭제"], "휴지통 없는 볼륨에는 설정 버튼 없음")
        check(share.informativeText.contains("이 볼륨에는 휴지통이 없습니다") && !share.informativeText.contains("클라우드"), "볼륨 안내")
        let mixed = MainWindowController.makePermanentDeleteAlert(url, refusals: [.noPermission], trashedCount: 2)
        check(mixed.informativeText.hasPrefix("고른 항목 중 2개는 휴지통으로 옮겼습니다."), "이미 옮긴 것을 알림")
    }

    runTest("휴지통 이동 오류를 종류별로 가른다") {
        func refusal(_ domain: String, _ code: Int) -> TrashRefusal? { FileService.trashRefusal(for: NSError(domain: domain, code: code)) }
        checkEqual(refusal(NSCocoaErrorDomain, NSFileWriteNoPermissionError), .noPermission, "513")
        checkEqual(refusal(NSCocoaErrorDomain, NSFeatureUnsupportedError), .noTrashOnVolume, "3328")
        checkEqual(refusal(NSCocoaErrorDomain, NSFileNoSuchFileError), nil, "파일 없음은 해당 없음")
        checkEqual(refusal(NSPOSIXErrorDomain, 1), nil, "다른 영역의 오류는 해당 없음")
    }

    runTest("실제 파일 서비스는 권한 없음과 다른 오류를 구분한다") {
        let real = FileService()
        let missing = root.appendingPathComponent("없는 파일.png")
        if case .failure(.trashUnavailable) = real.trashFile(at: missing) { check(false, "없는 파일은 휴지통 불가로 분류하지 않는다") }
        check((try? real.trashFile(at: missing).get()) == nil, "없는 파일은 실패")
        let victim = makeImage("permanent.png")
        check((try? real.deleteFilePermanently(at: victim).get()) != nil && !exists(victim), "바로 삭제는 파일을 지운다")
        check((try? real.deleteFilePermanently(at: victim).get()) == nil, "없는 파일의 바로 삭제는 실패")
    }
}
