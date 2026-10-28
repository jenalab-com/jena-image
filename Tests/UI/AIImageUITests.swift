import AppKit

@MainActor
func runAIImageUITests(controller: MainWindowController, directory: URL) {
    let image = directory.appendingPathComponent("ai-reference.png")
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    for y in 0..<32 {
        for x in 0..<32 {
            bitmap.setColor(NSColor(calibratedRed: CGFloat(x) / 40 + 0.15,
                                   green: CGFloat(y) / 40 + 0.15, blue: 0.65, alpha: 1), atX: x, y: y)
        }
    }
    try! bitmap.representation(using: .png, properties: [:])!.write(to: image)
    controller.currentFolderURL = directory
    controller.currentCategoryID = nil
    controller.switchToMode(.browser)
    controller.browserVC.display(folders: [], images: [image])
    controller.browserVC.restoreSelection(urls: [image])
    runTest("AI는 우측 패널에서 열리고 선택 이미지가 제거 가능한 썸네일로 첨부된다") {
        controller.showAIMode(nil)
        guard let ai = controller.aiChatVC else { check(false, "패널 생성"); return }
        checkEqual(controller.splitViewController.splitViewItems.count, 3, "세 번째 패널")
        check(controller.splitViewController.splitViewItems.last?.viewController === ai, "오른쪽 AI")
        checkEqual(ai.referenceURLs, [image], "최초 선택 첨부")
        check(!descendants(ai.attachments, of: NSImageView.self).isEmpty, "첨부 썸네일")
        let remove = descendants(ai.attachments, of: NSButton.self).first
        remove?.performClick(nil)
        check(ai.referenceURLs.isEmpty, "첨부 제거")
        ai.selectionChanged([image])
        check(ai.referenceURLs.isEmpty, "같은 선택 재통지가 제거를 취소하지 않는다")
        controller.browserVC.display(folders: [], images: [image])
        controller.browserVC.restoreSelection(urls: [image])
        check(ai.referenceURLs.isEmpty, "목록 자동 새로고침이 제거한 첨부를 복구하지 않는다")
        let collection = descendants(controller.browserVC.view, of: NSCollectionView.self).first!
        collection.deselectAll(nil)
        collection.delegate?.collectionView?(collection, didDeselectItemsAt: [IndexPath(item: 0, section: 0)])
        collection.selectItems(at: [IndexPath(item: 0, section: 0)], scrollPosition: [])
        collection.delegate?.collectionView?(collection, didSelectItemsAt: [IndexPath(item: 0, section: 0)])
        checkEqual(ai.referenceURLs, [image], "목록 선택 변경이 실제 첨부로 연결된다")
        ai.input.string = "프롬프트 보존"
        controller.showAIMode(nil)
        check(controller.aiSplitItem?.isCollapsed == true, "닫기")
        controller.showAIMode(nil)
        checkEqual(ai.input.string, "프롬프트 보존", "재개방 입력 유지")
        controller.switchToMode(.viewer)
        check(controller.splitViewController.splitViewItems[1].viewController === controller.viewerVC, "중앙만 뷰어로 교체")
        check(controller.splitViewController.splitViewItems.last?.viewController === ai, "뷰어에서도 우측 AI 유지")
        controller.switchToMode(.browser)
        ai.view.layoutSubtreeIfNeeded()
        check(ai.input.frame.width > 100, "입력창 너비")
        check(!descendants(ai.view, of: NSButton.self).contains { $0.title.contains("폴더 선택") }, "별도 저장 폴더 선택 없음")
        check(!descendants(ai.view, of: NSButton.self).contains { $0.title == "전송" }, "전송 버튼 제거")
        check(!ai.input.drawsBackground, "입력 텍스트 배경 투명")
        check(descendants(ai.view, of: AIChatTranscriptView.self).allSatisfy { !$0.drawsBackground && !$0.contentView.drawsBackground }, "대화 영역은 패널 바탕 사용")
        let tools = descendants(ai.composer, of: NSButton.self)
        check(!tools.contains { $0.toolTip == "참조 이미지 추가" }, "이미지 추가 버튼 제거")
        check(tools.contains { $0.accessibilityLabel() == "AI 옵션" }, "입력창 안의 설정 옵션")
        check(ai.cancelButton.isHidden, "평상시 중지 숨김")
        controller.window?.makeFirstResponder(ai.input)
        let copyItem = NSMenuItem(title: "복사", action: #selector(MainWindowController.copyFiles(_:)), keyEquivalent: "")
        check(controller.validateMenuItem(copyItem), "채팅 입력의 복사 메뉴 활성화")
        controller.selectAllItems(nil)
        checkEqual(ai.input.selectedRange().length, ai.input.string.utf16.count, "전체 선택은 채팅 텍스트에 적용")
        controller.browserVC.displayBookmarks([ImageFile(url: image)!])
        check(controller.aiDestinationURL == nil, "가상 목록은 이전 폴더로 저장하지 않는다")
        controller.browserVC.display(folders: [], images: [image])
        controller.window?.makeFirstResponder(nil)
    }
    runTest("AI 제목과 닫기는 헤더 아래에서 창 크기와 모드 변경을 따른다") {
        guard let window = controller.window, let ai = controller.aiChatVC else { check(false, "창과 패널"); return }
        let originalFrame = window.frame
        defer {
            window.setFrame(originalFrame, display: false)
            controller.switchToMode(.browser)
        }
        for mode in [MainWindowController.ContentMode.browser, .viewer] {
            controller.switchToMode(mode)
            for size in [NSSize(width: 940, height: 500), NSSize(width: 1200, height: 800)] {
                var frame = window.frame
                frame.size = size
                window.setFrame(frame, display: false)
                window.contentView?.layoutSubtreeIfNeeded()
                let title = descendants(ai.view, of: NSTextField.self).first { $0.stringValue == "AI 이미지" }!
                let close = descendants(ai.view, of: NSButton.self).first { $0.toolTip == "AI 사이드바 닫기" }!
                for element in [title as NSView, close as NSView] {
                    let rect = element.convert(element.bounds, to: nil)
                    check(rect.maxY <= window.contentLayoutRect.maxY, "제목/닫기가 툴바 아래 안전 영역에 배치된다: top=\(rect.maxY), content=\(window.contentLayoutRect.maxY), safe=\(ai.view.safeAreaInsets.top), size=\(size)")
                    check(rect.minY >= window.contentLayoutRect.minY, "제목/닫기가 화면 안에 있다")
                }
            }
        }
    }
    runTest("AI 저장 대상은 전송 시점 폴더이며 생성 중 이동해도 바뀌지 않는다") {
        let suite = "ai-ui-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.aiExecutable = "/usr/bin/true"
        let ai = AIChatViewController(settings: settings)
        ai.loadUsage = { _ in [.init(title: "주간", usedPercent: 35, resetsAt: Date().addingTimeInterval(183600))] }
        var folder: URL? = directory
        ai.currentDestination = { folder }
        _ = ai.view
        ai.loadModels = { _ in [.init(id: "fixture-model", title: "Fixture Model")] }
        var refreshed = false
        Task { @MainActor in refreshed = await ai.refreshModels() }
        check(waitUntil { refreshed }, "모델 목록 로드")
        ai.selectModel("fixture-model")
        checkEqual(AppSettings(defaults: defaults).aiModel, "fixture-model", "모델 선택 영속화")
        checkEqual(ai.modelButton.title, "Fixture Model ▾", "모델 표시명")
        var usageLoaded = false
        Task { @MainActor in await ai.refreshUsage(); usageLoaded = true }
        check(waitUntil { usageLoaded }, "사용 현황 갱신")
        check(ai.usageLabel.stringValue.contains("사용 35% · 리셋 2d 3h"), "사용량과 남은 시간 표시")
        check(!ai.usageLabel.isDescendant(of: ai.composer), "입력창 아래 별도 사용 현황")
        var usageCalls = 0
        var releaseUsage = false
        ai.loadUsage = { _ in
            usageCalls += 1
            while !releaseUsage { try await Task.sleep(nanoseconds: 10_000_000) }
            return [.init(title: "주간", usedPercent: 42, resetsAt: Date().addingTimeInterval(12000))]
        }
        ai.usageRefreshButton.performClick(nil)
        check(waitUntil { usageCalls == 1 }, "재조회 버튼이 조회를 호출한다")
        check(!ai.usageRefreshButton.isEnabled, "조회 중 중복 클릭 방지")
        releaseUsage = true
        check(waitUntil { ai.usageRefreshButton.isEnabled }, "조회 완료 후 버튼 복구")
        check(ai.usageLabel.stringValue.contains("사용 42%"), "재조회한 사용량 반영")
        var captured: AIImageRequest?
        var release = false
        let fixture = directory.appendingPathComponent("ai-ui-fixture")
        try! "#!/bin/sh\ncp reference-1.png output/result.png\n".write(to: fixture, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
        ai.generateImages = { request, service in
            captured = request
            while !release { try await Task.sleep(nanoseconds: 10_000_000) }
            let fixtureRequest = AIImageRequest(provider: .custom, executable: fixture.path,
                prompt: request.prompt, references: request.references, destination: request.destination)
            return try await service.generate(fixtureRequest)
        }
        ai.selectionChanged([image])
        ai.input.string = "푸른 하늘"
        let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        ai.input.keyDown(with: enter)
        check(waitUntil { captured != nil }, "요청 전달")
        folder = directory.appendingPathComponent("other")
        ai.refreshDestination()
        checkEqual(captured?.destination, directory, "전송 시점 폴더 고정")
        checkEqual(captured?.references, [image], "참조 전달")
        checkEqual(captured?.model, "fixture-model", "선택 모델을 생성 요청에 전달")
        check(!ai.modelButton.isEnabled, "생성 중 모델 변경 방지")
        let transcript = descendants(ai.view, of: AIChatTranscriptView.self).first!
        check(transcript.loadingView?.isHidden == false, "대화 영역에 생성 대기 표시")
        check(descendants(transcript, of: NSTextField.self).contains { $0.stringValue == "이미지를 만들고 있어요.." }, "생성 대기 문구")
        check(descendants(transcript, of: NSProgressIndicator.self).contains { !$0.isHidden }, "대화 영역 로딩 아이콘")
        check(descendants(ai.composer, of: NSProgressIndicator.self).isEmpty, "입력창에 중복 로딩 없음")
        release = true
        check(waitUntil { !ai.isRunning }, "완료")
        check(transcript.loadingView?.isHidden == true, "완료 시 로딩 제거")
        let saved = ai.messages.last?.images ?? []
        checkEqual(saved.count, 1, "채팅 결과 이미지")
        checkEqual(saved.first?.deletingLastPathComponent().path, directory.path, "원래 폴더에 실제 파일 저장")
        check(saved.first.map { FileManager.default.fileExists(atPath: $0.path) } == true, "저장 결과 실재")
        checkEqual(ai.referenceURLs, saved, "결과를 다음 요청에 첨부")
        check(ai.messages.last?.text.contains(saved[0].lastPathComponent) == true, "결과 메시지에 파일명 표시")
        check(ai.messages.last?.text.contains(directory.path) == false, "결과 메시지에 폴더 경로 대신 파일명 표시")
        ai.onOpenImages = controller.aiChatVC?.onOpenImages
        let openButton = descendants(ai.view, of: NSButton.self).first { $0.title == "저장된 이미지 보기" }
        check(openButton != nil, "결과 열기 버튼")
        openButton?.performClick(nil)
        check(controller.contentMode == .viewer, "결과 버튼은 앱 상세로 전환")
        checkEqual(controller.viewerVC.currentImageURL, saved.first, "상세에서 생성 파일 열기")
        check(controller.aiSplitItem?.isCollapsed == false, "상세를 열어도 AI 패널 유지")
        controller.switchToMode(.browser)
        ai.generateImages = { _, _ in throw AIImageGenerationError(message: "테스트 실패") }
        ai.input.string = "조금 더 밝게"
        ai.send()
        check(waitUntil { !ai.isRunning }, "실패 종료")
        check(transcript.loadingView?.isHidden == true, "실패 시 로딩 제거")
        checkEqual(ai.messages.last?.role, "status", "새 요청 실패는 이전 성공과 다른 메시지")
        check(ai.messages.last?.images.isEmpty == true, "실패를 이전 이미지로 표시하지 않는다")
        checkEqual(ai.input.string, "조금 더 밝게", "실패 시 입력 복구")
        ai.selectModel("")
        checkEqual(settings.aiModel, "", "CLI 기본 모델로 복귀")
        ai.loadModels = { _ in throw AIImageGenerationError(message: "fixture") }
        var failedRefresh: Bool?
        Task { @MainActor in failedRefresh = await ai.refreshModels() }
        check(waitUntil { failedRefresh != nil }, "모델 조회 실패 종료")
        checkEqual(failedRefresh, false, "실패 상태 전달")
        check(ai.modelOptions.isEmpty && ai.modelButton.isEnabled, "오래된 목록 제거와 재시도 활성화")
        ai.loadUsage = { _ in throw AIImageGenerationError(message: "fixture") }
        var usageFailed = false
        Task { @MainActor in await ai.refreshUsage(); usageFailed = true }
        check(waitUntil { usageFailed }, "사용 현황 오류 종료")
        check(ai.usageRefreshButton.isEnabled, "실패 후 재조회 버튼 복구")
        checkEqual(ai.usageLabel.stringValue, "사용 현황을 확인할 수 없어요", "실패 시 오래된 비율을 표시하지 않는다")
        folder = nil
        ai.refreshDestination()
        check(!ai.canSend, "선택된 실제 폴더 없으면 전송 불가")
    }
    runTest("채팅 Enter는 전송하고 Shift Enter와 한글 조합 확정은 전송하지 않는다") {
        let input = AIChatInputView(frame: NSRect(x: 0, y: 0, width: 260, height: 80))
        input.isRichText = false
        input.string = "이미지 요청"
        input.setSelectedRange(NSRange(location: input.string.utf16.count, length: 0))
        var submissions = 0
        input.onSubmit = { submissions += 1 }
        func enter(_ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                            windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                            isARepeat: false, keyCode: 36)!
        }
        input.keyDown(with: enter())
        checkEqual(submissions, 1, "Enter 전송")
        input.keyDown(with: enter(.shift))
        checkEqual(submissions, 1, "Shift Enter는 전송 안 함")
        check(input.string.contains("\n"), "Shift Enter 개행")
        input.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0),
                            replacementRange: NSRange(location: NSNotFound, length: 0))
        check(input.hasMarkedText(), "한글 조합 상태")
        input.keyDown(with: enter())
        checkEqual(submissions, 1, "조합 확정 Enter는 전송 안 함")
        input.unmarkText()
        input.keyDown(with: enter())
        checkEqual(submissions, 2, "조합 완료 후 Enter 전송")
        input.isEditable = false
        input.keyDown(with: enter())
        checkEqual(submissions, 2, "생성 중 입력 잠금")
    }
    runTest("AI 설정은 미설치·미로그인·계정 연결 상태별 액션을 표시한다") {
        let suite = "ai-settings-ui-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vc = AIConnectionViewController(settings: AppSettings(defaults: defaults))
        _ = vc.view
        vc.apply(.missing)
        var terminalCalls: [Bool] = []
        vc.openTerminal = { installing, _, completion in terminalCalls.append(installing); completion(nil) }
        vc.installButton.performClick(nil)
        checkEqual(terminalCalls, [true], "설치 버튼 연결")
        check(!vc.installButton.isHidden && vc.loginButton.isHidden, "미설치에는 설치")
        vc.apply(.init(state: .signedOut, executable: URL(fileURLWithPath: "/usr/bin/true"), detail: "로그인 필요", account: nil))
        check(vc.installButton.isHidden && !vc.loginButton.isHidden, "설치 후에는 로그인")
        vc.loginButton.performClick(nil)
        checkEqual(terminalCalls, [true, false], "로그인 버튼 연결")
        vc.apply(.init(state: .connected, executable: URL(fileURLWithPath: "/usr/bin/true"), detail: "연결 완료", account: "fixture@example.test"))
        checkEqual(vc.accountLabel.stringValue, "fixture@example.test", "연결 계정 표시")
        check(vc.installButton.isHidden && vc.loginButton.isHidden, "연결 후 설치 로그인 숨김")
        var calls = 0
        vc.checkConnection = { _ in calls += 1; return .missing }
        vc.recheck()
        check(waitUntil { calls == 1 && vc.checkButton.isEnabled }, "재확인 실제 실행")
        checkEqual(vc.accountLabel.stringValue, "", "재확인은 이전 계정을 지운다")
        let command = try! AICLITerminal.script(install: false, executable: URL(fileURLWithPath: "/tmp/cli ' test"))
        check(command.contains("'\\''"), "로그인 경로 셸 인용")
    }
    if let ai = controller.aiChatVC {
        ai.input.string = "따뜻한 오후 햇살이 비치는 정원을 그려 주세요."
        let sample = ai.input.string
        ai.input.string = String(repeating: "긴 문장으로 이미지를 자세히 설명합니다. ", count: 80)
        ai.view.layoutSubtreeIfNeeded()
        check(ai.composer.frame.height <= 200, "긴 입력은 제한 높이 이후 스크롤")
        ai.input.string = sample
        for (appearance, filename) in [(NSAppearance.Name.aqua, "ai-sidebar-preview.png"),
                                       (.darkAqua, "ai-sidebar-dark-preview.png")] {
            ai.view.appearance = NSAppearance(named: appearance)
            ai.view.layoutSubtreeIfNeeded()
            if let bitmap = ai.view.bitmapImageRepForCachingDisplay(in: ai.view.bounds) {
                ai.view.cacheDisplay(in: ai.view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: ".build/" + filename))
            }
        }
        ai.view.appearance = nil
    }
    if controller.aiSplitItem?.isCollapsed == false { controller.showAIMode(nil) }
}
