import AppKit
import WebKit

@MainActor
func runWebPanelUITests(controller: MainWindowController, settings: AppSettings) {
    let page = "<!doctype html><title>웹 패널</title><body><p>글</p></body>"
    let imagePage = """
        <!doctype html><body style="margin:0">
        <img id=a src="/big.png" style="display:block;width:100px;height:100px">
        <img id=slow src="/slow.png" style="display:block;width:100px;height:100px">
        <p id=plain>글</p></body>
        """
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let png = bitmap.representation(using: .png, properties: [:])!
    let server: WebTestServer
    do {
        server = try WebTestServer(routes: [
            "/page.html": (200, ["Content-Type": "text/html; charset=utf-8"], Data(page.utf8)),
            "/images.html": (200, ["Content-Type": "text/html; charset=utf-8"], Data(imagePage.utf8)),
            "/big.png": (200, ["Content-Type": "image/png"], png),
            "/slow.png": (200, ["Content-Type": "image/png"], png),
        ])
    } catch {
        check(false, "테스트 서버 시작: \(error)")
        return
    }
    defer { server.stop() }
    controller.makeWebEngine = { WebPageEngine(dataStore: .nonPersistent()) }
    let previousFolder = controller.currentFolderURL
    let previousTabs = (settings.webTabAddresses, settings.webSelectedTabIndex)
    // 뒤에 오는 스위트가 같은 창을 쓰므로 패널을 접고, 최소 폭과 보던 폴더와 열어 둔 탭 기록을 되돌린다.
    defer {
        if controller.webSplitItem?.isCollapsed == false { controller.showWebMode(nil) }
        controller.webPanelVC?.engine.load(URL(string: "about:blank")!)
        _ = waitUntil(timeout: 5) { controller.webPanelVC?.engine.isLoading == false }
        settings.webTabAddresses = previousTabs.0
        settings.webSelectedTabIndex = previousTabs.1
        if let previousFolder {
            controller.navigateToFolder(previousFolder)
            check(waitUntil(timeout: 5) { !controller.browserVC.isFolderLoading }, "보던 폴더로 복귀")
        }
        checkEqual(controller.window?.minSize.width, 700, "최소 폭 복귀")
        check(controller.webSplitItem?.isCollapsed == true, "패널 접힘으로 복귀")
    }
    let webButton = { controller.window?.toolbar?.items.first { $0.itemIdentifier == MainWindowController.ToolbarID.web }?.view as? NSButton }

    runTest("웹 버튼은 사이드바와 목록 사이 칸을 열고 접는다") {
        check(controller.toolbarDefaultItemIdentifiers(controller.window!.toolbar!).contains(MainWindowController.ToolbarID.web), "툴바 항목")
        // 웹 버튼은 사이드바 토글 바로 오른쪽이다 — 목록 화면과 뷰어 화면 모두, 실제 툴바에서도.
        let ids = MainWindowController.ToolbarID.self
        checkEqual(Array(controller.toolbarDefaultItemIdentifiers(controller.window!.toolbar!).prefix(2)), [ids.sidebar, ids.web], "목록 화면의 순서")
        controller.switchToMode(.viewer)
        checkEqual(Array(controller.toolbarDefaultItemIdentifiers(controller.window!.toolbar!).prefix(3)), [ids.sidebar, ids.web, ids.back], "뷰어 화면의 순서")
        checkEqual(Array(controller.window!.toolbar!.items.map(\.itemIdentifier).prefix(2)), [ids.sidebar, ids.web], "실제 툴바의 순서")
        // 제목보다 앞에 놓이려면 내비게이션 항목이어야 한다(사이드바 토글 · 웹 · 뒤로).
        let navigational = controller.window!.toolbar!.items.filter(\.isNavigational).map(\.itemIdentifier)
        checkEqual(navigational, [ids.sidebar, ids.web, ids.back], "제목 앞에 놓이는 항목")
        controller.switchToMode(.browser)
        controller.showWebMode(nil)
        guard let web = controller.webPanelVC else { check(false, "패널 생성"); return }
        let items = controller.splitViewController.splitViewItems
        check(items.first?.viewController === controller.sidebarVC, "맨 왼쪽은 사이드바")
        check(items.count > 1 && items[1].viewController === web, "사이드바 바로 오른쪽")
        check(items.count > 2 && items[2].viewController === controller.browserVC, "목록은 웹 오른쪽(2번)")
        if let ai = controller.aiChatVC { check(items.last?.viewController === ai, "AI는 맨 오른쪽 그대로") }
        check(controller.webSplitItem?.isCollapsed == false, "펼침")
        checkEqual(controller.window?.minSize.width, 980, "창 최소 폭")
        check((controller.window?.frame.width ?? 0) >= 980, "좁으면 창을 넓힌다")
        checkEqual(webButton()?.state, .on, "열리면 버튼 켜짐")
        controller.showWebMode(nil)
        check(controller.webSplitItem?.isCollapsed == true, "접힘")
        checkEqual(controller.window?.minSize.width, 700, "최소 폭 복귀")
        checkEqual(webButton()?.state, .off, "접히면 버튼 꺼짐")
    }
    runTest("AI와 웹은 한 번에 하나만 펼친다") {
        controller.showWebMode(nil); controller.showAIMode(nil)
        check(controller.webSplitItem?.isCollapsed == true && controller.aiSplitItem?.isCollapsed == false, "AI를 열면 웹이 접힘")
        checkEqual(controller.window?.minSize.width, 940, "AI 최소 폭")
        checkEqual(webButton()?.state, .off, "AI를 열면 웹 버튼 꺼짐")
        controller.showWebMode(nil)
        check(controller.aiSplitItem?.isCollapsed == true && controller.webSplitItem?.isCollapsed == false, "웹을 열면 AI가 접힘")
        check(controller.splitViewController.splitViewItems[2].viewController === controller.browserVC, "목록 칸은 그대로(2번)")
        check(controller.splitViewController.splitViewItems[1] === controller.webSplitItem, "웹은 1번 그대로")
        checkEqual(webButton()?.state, .on, "웹 버튼 다시 켜짐")
    }
    runTest("뷰어로 바꿔도 웹 패널이 남는다") {
        controller.switchToMode(.viewer)
        check(controller.webSplitItem?.isCollapsed == false, "유지")
        check(controller.splitViewController.splitViewItems[2].viewController === controller.viewerVC, "목록 칸만 교체")
        check(controller.splitViewController.splitViewItems[1] === controller.webSplitItem, "웹은 1번 그대로")
        checkEqual(webButton()?.state, .on, "툴바를 다시 짜도 버튼 상태 유지")
        controller.switchToMode(.browser)
        check(controller.splitViewController.splitViewItems[2].viewController === controller.browserVC, "목록으로 되돌림")
        check(controller.splitViewController.splitViewItems[1] === controller.webSplitItem, "되돌려도 웹은 1번")
    }
    runTest("주소창 입력으로 페이지를 열고 탭 주소를 기억한다") {
        let web = controller.webPanelVC!
        web.addressField.stringValue = server.baseURL.appendingPathComponent("page.html").absoluteString
        web.submitAddress()
        check(waitUntil(timeout: 10) { !web.engine.isLoading && web.engine.currentURL?.lastPathComponent == "page.html" }, "불러옴")
        check(waitUntil { settings.webTabAddresses == [web.engine.currentURL?.absoluteString ?? "?"] }, "탭 주소 저장")
        checkEqual(settings.webSelectedTabIndex, 0, "고른 탭 번호 저장")
        checkEqual(web.addressField.stringValue, web.engine.currentURL?.absoluteString ?? "", "주소창에 현재 주소")
        web.addressField.stringValue = "javascript:alert(1)"; web.submitAddress()
        check(!web.statusLabel.stringValue.isEmpty, "거부 사유를 상태 줄에")
        check(web.engine.currentURL?.lastPathComponent == "page.html", "페이지는 그대로")
    }
    runTest("닫기 버튼은 패널을 접는다") {
        controller.webPanelVC?.closeButton.performClick(nil)
        check(controller.webSplitItem?.isCollapsed == true, "접힘")
        checkEqual(webButton()?.state, .off, "닫기 버튼으로 접어도 버튼 꺼짐")
        checkEqual(controller.window?.minSize.width, 700, "최소 폭 복귀")
    }
    runTest("접힌 패널의 페이지는 대화창을 띄우지 않고 조용히 답한다") {
        guard let web = controller.webPanelVC, let window = controller.window else { check(false, "패널"); return }
        check(controller.webSplitItem?.isCollapsed == true, "접힌 상태")
        check(!web.engine.isPresented, "엔진은 보이지 않음으로 표시")
        var results: [Any?] = []
        for script in ["confirm('확인?')", "prompt('이름?') === null", "alert('알림'), 'done'"] {
            var finished = false
            web.engine.webView.evaluateJavaScript(script) { value, _ in results.append(value); finished = true }
            if !waitUntil(timeout: 3, { finished }) { results.append("멈춤") }
            while let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .cancel) }
        }
        checkEqual(results.map { "\($0 ?? "nil")" }, ["0", "1", "done"], "confirm false·prompt null·alert 통과")
        check(window.attachedSheet == nil && window.sheets.isEmpty, "주 창에 시트 없음")
    }
    runTest("나눔선으로 접고 펼쳐도 버튼·최소 폭·엔진 표시가 따라간다") {
        controller.showWebMode(nil)
        guard let item = controller.webSplitItem, let engine = controller.webPanelVC?.engine else { check(false, "패널"); return }
        check(engine.isPresented, "펼치면 보임")
        item.isCollapsed = true
        checkEqual(webButton()?.state, .off, "버튼 꺼짐")
        checkEqual(controller.window?.minSize.width, 700, "최소 폭 700")
        check(!engine.isPresented, "엔진 보이지 않음")
        item.isCollapsed = false
        checkEqual(webButton()?.state, .on, "버튼 켜짐")
        checkEqual(controller.window?.minSize.width, 980, "최소 폭 980")
        check(engine.isPresented, "엔진 보임")
        controller.showWebMode(nil)
        check(item.isCollapsed && !engine.isPresented, "버튼 길로 다시 접힘")
    }
    runTest("화면 오른쪽 끝의 창을 넓혀도 화면 안에 둔다") {
        let suite = "web-panel-edge-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let other = MainWindowController(categoryStore: CategoryStore(defaults: defaults), settings: AppSettings(defaults: defaults))
        defer { other.window?.close() }
        other.makeWebEngine = { WebPageEngine(dataStore: .nonPersistent()) }
        guard let window = other.window, let screen = window.screen ?? NSScreen.main else { check(false, "창과 화면"); return }
        let visible = screen.visibleFrame
        window.setFrame(NSRect(x: visible.maxX - 800, y: visible.minY + 20, width: 800, height: 600), display: false)
        other.showWebMode(nil)
        let frame = window.frame
        checkEqual(frame.width, min(980, visible.width), "최소 폭까지 넓힘")
        check(frame.maxX <= visible.maxX + 0.5 && frame.minX >= visible.minX - 0.5, "화면 안: \(frame) / \(visible)")
    }
    runTest("보기 메뉴에 웹 브라우저 항목이 있다") {
        let items = MainMenu.create().items.compactMap(\.submenu).flatMap(\.items)
        let item = items.first { $0.action == #selector(MainWindowController.showWebMode(_:)) }
        checkEqual(item?.title, "웹 브라우저", "메뉴 제목")
        if let item, !item.keyEquivalent.isEmpty {
            let clash = items.contains { $0 !== item && $0.keyEquivalent == item.keyEquivalent
                && $0.keyEquivalentModifierMask == item.keyEquivalentModifierMask }
            check(!clash, "단축키 충돌 없음")
        }
    }
    runTest("⋯ 메뉴는 검색엔진과 검색 종류를 고르고 저장한다") {
        let suite = "web-panel-options-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let local = AppSettings(defaults: defaults)
        checkEqual(local.webSearchProvider, .google, "기본 검색엔진")
        checkEqual(local.webSearchMode, .images, "기본 검색 종류")
        checkEqual(local.webTabAddresses, [], "기본 탭 주소")
        checkEqual(local.webSelectedTabIndex, 0, "기본 고른 탭")
        let web = WebPanelViewController(engine: WebPageEngine(dataStore: .nonPersistent()), settings: local)
        _ = web.view
        let menu = web.optionsMenu()
        let checked = menu.items.filter { $0.state == .on }.map(\.title)
        checkEqual(checked, ["Google", "이미지"], "선택된 항목에 체크")
        guard let naver = menu.items.first(where: { $0.title == "네이버" }),
              let webMode = menu.items.first(where: { $0.title == "웹" }) else { check(false, "메뉴 항목"); return }
        app.sendAction(naver.action!, to: naver.target, from: naver)
        app.sendAction(webMode.action!, to: webMode.target, from: webMode)
        checkEqual(local.webSearchProvider, .naver, "검색엔진 저장")
        checkEqual(local.webSearchMode, .web, "검색 종류 저장")
        checkEqual(web.optionsMenu().items.filter { $0.state == .on }.map(\.title), ["네이버", "웹"], "바뀐 체크")
        check(descendants(web.view, of: NSTextField.self).contains { $0.stringValue == "검색어나 주소를 입력하세요" && !$0.isHidden }, "빈 화면 문구")
        checkEqual(web.addressField.placeholderString, "검색어 또는 주소", "주소창 안내")
    }
    runTest("지난 탭은 처음 한 번만 복원한다") {
        let suite = "web-panel-initial-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let local = AppSettings(defaults: defaults)
        let pageURL = server.baseURL.appendingPathComponent("page.html")
        local.webTabAddresses = [pageURL.absoluteString]
        let web = WebPanelViewController(engine: WebPageEngine(dataStore: .nonPersistent()), settings: local)
        _ = web.view
        web.loadInitialPage()
        check(waitUntil(timeout: 10) { !web.engine.isLoading && web.engine.currentURL == pageURL }, "지난 주소 열기")
        // 열 수 있는 다른 주소로 바꿔 두고, 다시 열었다면 충분히 드러날 만큼 기다린다.
        local.webTabAddresses = [server.baseURL.appendingPathComponent("images.html").absoluteString]
        web.loadInitialPage()
        check(!waitUntil(timeout: 1.5) { web.engine.isLoading || web.engine.currentURL != pageURL }, "두 번째 호출은 무시")
    }
    /// 따로 쓰는 설정과 패널. 패널은 창에 넣어 주소창 편집·포커스를 실제처럼 본다.
    func makeLocalPanel(_ name: String, width: CGFloat = 480, prepare: (AppSettings, UserDefaults) -> Void = { _, _ in },
                        _ body: (WebPanelViewController, AppSettings, UserDefaults, NSWindow) -> Void) {
        let suite = "web-panel-\(name)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let local = AppSettings(defaults: defaults)
        prepare(local, defaults)
        let web = WebPanelViewController(engine: WebPageEngine(dataStore: .nonPersistent()), settings: local)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        web.view.frame = window.contentView!.bounds
        web.view.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(web.view)
        web.view.layoutSubtreeIfNeeded()
        body(web, local, defaults, window)
    }
    let tabPageURL = server.baseURL.appendingPathComponent("page.html")
    let tabImagesURL = server.baseURL.appendingPathComponent("images.html")

    runTest("탭 줄은 탭마다 항목을 두고 +·클릭·✕로 열고 고르고 닫는다") {
        makeLocalPanel("strip") { web, local, _, window in
            web.loadInitialPage()
            let strip = web.tabStrip
            checkEqual(strip.items.count, 1, "처음엔 항목 하나")
            checkEqual(strip.items.first?.titleButton.title, "새 탭", "빈 탭 제목")
            checkEqual(strip.newTabButton.toolTip, "새 탭", "+ 툴팁")
            checkEqual(strip.newTabButton.accessibilityLabel(), "새 탭", "+ 접근성 이름")
            web.addressField.stringValue = tabPageURL.absoluteString
            web.submitAddress()
            check(waitUntil(timeout: 10) { !web.engine.isLoading && web.engine.currentURL == tabPageURL }, "첫 탭 불러옴")
            check(waitUntil { strip.items.first?.titleButton.title == "웹 패널" }, "항목 제목은 페이지 제목")
            checkEqual(strip.items.first?.closeButton.accessibilityLabel(), "탭 닫기: 웹 패널", "닫기 접근성 이름")
            let first = web.engine.selectedTabID

            strip.newTabButton.performClick(nil)
            checkEqual(strip.items.count, 2, "+로 새 탭")
            guard strip.items.count == 2 else { return }
            check(web.engine.selectedTabID != first, "새 탭을 고름")
            checkEqual(strip.items.map(\.isSelected), [false, true], "고른 탭 표시")
            checkEqual(web.addressField.stringValue, "", "새 탭의 빈 주소")
            check(web.addressField.currentEditor() != nil && window.firstResponder === web.addressField.currentEditor(), "주소창에 포커스")

            // 입력하던 글자는 탭을 바꾸면 그 탭의 주소로 바뀐다.
            web.addressField.currentEditor()?.string = "입력 중"
            strip.items[0].titleButton.performClick(nil)
            checkEqual(web.engine.selectedTabID, first, "항목 클릭으로 전환")
            checkEqual(strip.items.map(\.isSelected), [true, false], "고른 탭 표시 바뀜")
            check(web.addressField.currentEditor() == nil, "탭 전환은 편집을 끝낸다")
            checkEqual(web.addressField.stringValue, tabPageURL.absoluteString, "주소창이 고른 탭을 따른다")
            check(web.backButton.isEnabled == web.engine.canGoBack, "뒤로 버튼도 고른 탭")
            check(waitUntil { local.webTabAddresses == [tabPageURL.absoluteString, ""] && local.webSelectedTabIndex == 0 }, "탭을 열고 옮기면 저장")

            strip.items[1].closeButton.performClick(nil)
            checkEqual(strip.items.count, 1, "✕로 닫기")
            guard strip.items.count == 1 else { return }
            checkEqual(web.engine.selectedTabID, first, "고른 탭 그대로")
            check(waitUntil { local.webTabAddresses == [tabPageURL.absoluteString] }, "닫으면 저장")
            strip.items[0].closeButton.performClick(nil)
            checkEqual(strip.items.count, 1, "마지막 탭을 닫으면 빈 탭 하나")
            checkEqual(strip.items.first?.titleButton.title, "새 탭", "빈 탭")
            checkEqual(web.addressField.stringValue, "", "빈 주소창")
            check(waitUntil { local.webTabAddresses == [""] && local.webSelectedTabIndex == 0 }, "빈 탭은 빈 문자열로 저장")
        }
    }
    runTest("탭이 많으면 항목 폭을 줄이고 넘치면 옆으로 스크롤해 새 탭을 보인다") {
        makeLocalPanel("overflow") { web, _, _, _ in
            web.loadInitialPage()
            let strip = web.tabStrip
            web.view.layoutSubtreeIfNeeded()
            check(strip.items.allSatisfy { $0.frame.width <= 180.5 && $0.frame.width >= 89.5 }, "한 탭 폭: \(strip.items.map(\.frame.width))")
            for _ in 0..<11 { strip.newTabButton.performClick(nil) }
            web.view.layoutSubtreeIfNeeded()
            checkEqual(strip.items.count, 12, "열두 탭")
            check(strip.items.allSatisfy { abs($0.frame.width - 90) < 0.5 }, "넘치면 최소 폭: \(strip.items.map(\.frame.width))")
            guard strip.items.count == 12, let last = strip.items.last else { return }
            check(strip.visibleItemsRect.insetBy(dx: -0.5, dy: -0.5).contains(last.frame), "새로 연 탭이 보인다: \(strip.visibleItemsRect)")
            check(!strip.visibleItemsRect.contains(strip.items[0].frame), "첫 탭은 가려진다")
            strip.items[0].titleButton.performClick(nil)
            web.view.layoutSubtreeIfNeeded()
            check(strip.visibleItemsRect.insetBy(dx: -0.5, dy: -0.5).contains(strip.items[0].frame), "고른 탭이 보인다: \(strip.visibleItemsRect)")
        }
    }
    runTest("좁은 패널에 탭 여덟을 복원하면 고른 탭이 보이고, 항목 어디를 눌러도 고른다") {
        // 끝 주소는 http가 아니다. 복원이 설정을 다시 쓰면 빈 문자열로 바뀐다.
        let addresses = (0..<7).map { tabPageURL.absoluteString + "?\($0)" } + ["ftp://example.com/x"]
        makeLocalPanel("reveal", width: WebPanelViewController.minimumWidth, prepare: { local, _ in
            local.webTabAddresses = addresses
            local.webSelectedTabIndex = 1
        }) { web, local, _, _ in
            web.loadInitialPage()
            checkEqual(local.webTabAddresses, addresses, "복원만으로는 쓰지 않는다")
            web.view.layoutSubtreeIfNeeded()
            let strip = web.tabStrip
            guard strip.items.count == 8 else { check(false, "항목 여덟: \(strip.items.count)"); return }
            check(strip.items[1].isSelected, "고른 탭 표시")
            check(strip.visibleItemsRect.insetBy(dx: -0.5, dy: -0.5).contains(strip.items[1].frame), "고른 탭이 보인다: \(strip.visibleItemsRect)")
            check(!strip.visibleItemsRect.contains(strip.items[7].frame), "넘친 끝 탭은 가려져 있다")
            // 제목·닫기 버튼이 아닌 항목의 가장자리를 눌러도 고른다.
            let item = strip.items[0]
            let point = item.convert(NSPoint(x: 2, y: item.bounds.midY), to: nil)
            let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: web.view.window?.windowNumber ?? 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            check(item.hitTest(NSPoint(x: item.frame.minX + 2, y: item.frame.midY)) === item, "가장자리는 항목 자신이 받는다")
            item.mouseDown(with: event)
            checkEqual(web.engine.selectedTabID, item.tabID, "가장자리 클릭으로 고름")
        }
    }
    runTest("다시 켜면 탭을 복원하고 고른 탭만 바로 불러온다") {
        makeLocalPanel("restore", prepare: { local, _ in
            local.webTabAddresses = [tabPageURL.absoluteString, "", tabImagesURL.absoluteString]
            local.webSelectedTabIndex = 2
        }) { web, local, _, _ in
            web.loadInitialPage()
            let tabs = web.engine.tabs
            checkEqual(tabs.count, 3, "탭 셋")
            guard tabs.count == 3 else { return }
            checkEqual(web.engine.selectedTabID, tabs[2].id, "고른 탭 번호")
            check(waitUntil(timeout: 10) { !web.engine.isLoading && web.engine.currentURL == tabImagesURL }, "고른 탭은 바로 불러옴")
            checkEqual(web.addressField.stringValue, tabImagesURL.absoluteString, "주소창")
            check(web.engine.webView(forTab: tabs[0].id)?.url == nil, "나머지는 아직 불러오지 않음")
            checkEqual(web.engine.tabs[0].title, server.baseURL.host, "불러오기 전 제목은 호스트")
            checkEqual(web.engine.tabs[0].address, tabPageURL.absoluteString, "불러오기 전 주소")
            checkEqual(web.engine.tabs[1].title, "새 탭", "빈 탭")
            checkEqual(web.tabStrip.items.first?.titleButton.title, server.baseURL.host, "탭 줄에도 호스트")
            guard web.tabStrip.items.count == 3 else { return }
            web.tabStrip.items[0].titleButton.performClick(nil)
            check(waitUntil(timeout: 10) { !web.engine.isLoading && web.engine.currentURL == tabPageURL }, "처음 고를 때 불러옴")
            check(waitUntil { local.webSelectedTabIndex == 0 }, "고른 탭 저장")
            checkEqual(local.webTabAddresses, [tabPageURL.absoluteString, "", tabImagesURL.absoluteString], "주소 저장")
        }
    }
    runTest("예전 마지막 주소만 있으면 탭 하나로 옮기고 지운다") {
        makeLocalPanel("migrate", prepare: { _, defaults in
            defaults.set(tabPageURL.absoluteString, forKey: "webLastAddress")
        }) { web, local, defaults, _ in
            web.loadInitialPage()
            checkEqual(web.engine.tabs.count, 1, "탭 하나")
            check(waitUntil(timeout: 10) { !web.engine.isLoading && web.engine.currentURL == tabPageURL }, "그 주소를 연다")
            check(defaults.object(forKey: "webLastAddress") == nil, "예전 값은 지움")
            check(waitUntil { local.webTabAddresses == [tabPageURL.absoluteString] }, "새 값으로 저장")
        }
    }
    runTest("보기 메뉴의 새 탭은 웹 패널이 펼쳐져 있을 때만 켜진다") {
        let items = MainMenu.create().items.compactMap(\.submenu).flatMap(\.items)
        guard let item = items.first(where: { $0.action == #selector(MainWindowController.newWebTab(_:)) }) else {
            check(false, "메뉴 항목"); return
        }
        checkEqual(item.title, "새 탭", "메뉴 제목")
        checkEqual(item.keyEquivalent, "", "단축키 없음")
        if controller.webSplitItem?.isCollapsed == false { controller.showWebMode(nil) }
        check(!controller.validateMenuItem(item), "접혀 있으면 꺼짐")
        controller.showWebMode(nil)
        check(controller.validateMenuItem(item), "펼쳐져 있으면 켜짐")
        guard let engine = controller.webPanelVC?.engine else { check(false, "패널"); return }
        let count = engine.tabs.count
        app.sendAction(item.action!, to: controller, from: item)
        checkEqual(engine.tabs.count, count + 1, "누르면 새 탭")
        checkEqual(engine.selectedTabID, engine.tabs.last?.id, "새 탭을 고름")
        if let id = engine.selectedTabID { engine.closeTab(id) }
        controller.showWebMode(nil)
    }
    runTest("상태 줄은 불러오는 중을 보이고 메시지는 남겨 둔다") {
        let web = WebPanelViewController(engine: WebPageEngine(dataStore: .nonPersistent()), settings: settings)
        _ = web.view
        server.delayBody(forPath: "/page.html", by: 1)
        web.engine.load(server.baseURL.appendingPathComponent("page.html"))
        check(waitUntil { web.statusLabel.stringValue == "불러오는 중…" }, "불러오는 중 표시")
        checkEqual(web.reloadButton.accessibilityLabel(), "중지", "불러오는 동안 중지 버튼")
        web.showStatus("알림")
        checkEqual(web.statusLabel.stringValue, "알림", "메시지가 우선")
        check(waitUntil(timeout: 10) { !web.engine.isLoading }, "불러오기 끝")
        checkEqual(web.statusLabel.stringValue, "알림", "6초 전에는 메시지 유지")
        checkEqual(web.reloadButton.accessibilityLabel(), "새로고침", "끝나면 새로고침 버튼")
        web.engine.onNotice?("엔진 알림")
        checkEqual(web.statusLabel.stringValue, "엔진 알림", "엔진 알림은 상태 줄로")
    }
    /// 새 창(1300 폭)을 만든다. 공용 창의 상태를 건드리지 않고 칸 배치를 처음부터 본다.
    func makeWideController(_ name: String, _ body: (MainWindowController) -> Void) {
        let suite = "web-panel-\(name)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let other = MainWindowController(categoryStore: CategoryStore(defaults: defaults), settings: AppSettings(defaults: defaults))
        defer { other.window?.close() }
        other.makeWebEngine = { WebPageEngine(dataStore: .nonPersistent()) }
        if let window = other.window {
            var frame = window.frame
            frame.size.width = 1300
            window.setFrame(frame, display: false)
        }
        other.splitViewController.view.layoutSubtreeIfNeeded()
        body(other)
    }
    /// 칸 배치: [사이드바 | 웹 | 목록·뷰어 | AI]. 웹은 1번, 목록·뷰어는 2번, AI는 맨 끝.
    func checkLayout(_ other: MainWindowController, content: NSViewController, _ label: String) {
        let items = other.splitViewController.splitViewItems
        checkEqual(items.count, 4, "\(label): 칸 넷")
        guard items.count == 4 else { return }
        check(items[0].viewController === other.sidebarVC, "\(label): 0번 사이드바")
        check(items[1] === other.webSplitItem, "\(label): 1번 웹")
        check(items[2].viewController === content, "\(label): 2번 목록·뷰어")
        check(items[3] === other.aiSplitItem, "\(label): 맨 끝 AI")
    }
    /// 칸의 뷰는 분할 뷰 안의 감싸개에 들어 있으므로 분할 뷰 좌표로 바꿔 본다.
    func splitFrame(_ other: MainWindowController, _ view: NSView) -> NSRect {
        view.convert(view.bounds, to: other.splitViewController.splitView)
    }
    /// 웹은 사이드바 바로 오른쪽, 목록은 웹 바로 오른쪽에 붙는다.
    func checkWebBetween(_ other: MainWindowController, _ label: String) {
        other.splitViewController.view.layoutSubtreeIfNeeded()
        guard let web = other.webPanelVC else { check(false, "\(label): 웹 패널"); return }
        let sidebarItem = other.splitViewController.splitViewItems[0]
        let sidebarEdge = sidebarItem.isCollapsed ? 0 : splitFrame(other, other.sidebarVC.view).maxX
        let webFrame = splitFrame(other, web.view)
        let content = splitFrame(other, other.contentMode == .browser ? other.browserVC.view : other.viewerVC.view)
        check(webFrame.minX >= sidebarEdge - 0.5 && webFrame.minX <= sidebarEdge + 2,
              "\(label): 웹 왼쪽 끝은 사이드바 끝(\(sidebarEdge)) 바로 옆: \(webFrame.minX)")
        check(content.minX >= webFrame.maxX - 0.5 && content.minX <= webFrame.maxX + 2,
              "\(label): 목록은 웹 바로 오른쪽: \(content.minX) / \(webFrame.maxX)")
    }
    runTest("웹을 먼저 연 뒤 AI를 처음 열어도 칸 순서와 폭이 맞다") {
        makeWideController("order-web-first") { other in
            other.showWebMode(nil)
            other.splitViewController.view.layoutSubtreeIfNeeded()
            guard let web = other.webPanelVC else { check(false, "웹 패널 생성"); return }
            checkEqual(other.splitViewController.splitViewItems.count, 3, "칸 셋")
            check(other.splitViewController.splitViewItems[1].viewController === web, "웹은 1번")
            check(other.splitViewController.splitViewItems[2].viewController === other.browserVC, "목록은 2번")
            check(abs(web.view.frame.width - WebPanelViewController.defaultWidth) < 2, "웹 기본 폭으로 열림: \(web.view.frame.width)")
            check(web.engine.containerView.frame.height > web.view.frame.height - 120, "페이지가 패널 높이를 채운다")
            checkWebBetween(other, "웹 먼저")
            other.showAIMode(nil)
            guard let ai = other.aiChatVC, let aiItem = other.aiSplitItem else { check(false, "AI 패널 생성"); return }
            check(other.webSplitItem?.isCollapsed == true && !aiItem.isCollapsed, "AI만 펼침")
            checkLayout(other, content: other.browserVC, "AI 연 뒤")
            other.splitViewController.view.layoutSubtreeIfNeeded()
            let width = ai.view.frame.width
            check(width >= AIChatViewController.minimumWidth - 1 && width <= AIChatViewController.maximumWidth + 1, "AI 폭 \(width)")
            check(abs(width - AIChatViewController.defaultWidth) < 2, "AI 기본 폭으로 열림: \(width)")
            check(other.webSplitItem?.isCollapsed == true, "나눔선을 옮겨도 웹은 접힌 채")
            checkEqual(other.window?.minSize.width, 940, "AI 최소 폭")
            other.switchToMode(.viewer)
            checkLayout(other, content: other.viewerVC, "뷰어")
            check(!aiItem.isCollapsed && other.webSplitItem?.isCollapsed == true, "AI 유지, 웹 접힌 채")
            other.switchToMode(.browser)
            checkLayout(other, content: other.browserVC, "목록")
            // 다시 웹을 열면 AI가 접히고 웹은 처음 폭 그대로다.
            other.showWebMode(nil)
            other.splitViewController.view.layoutSubtreeIfNeeded()
            check(aiItem.isCollapsed && other.webSplitItem?.isCollapsed == false, "웹만 펼침")
            check(abs(web.view.frame.width - WebPanelViewController.defaultWidth) < 2, "웹 폭 그대로: \(web.view.frame.width)")
            checkWebBetween(other, "웹 다시")
        }
    }
    runTest("AI를 먼저 연 뒤 웹을 처음 열어도 칸 순서와 폭이 맞다") {
        makeWideController("order-ai-first") { other in
            other.showAIMode(nil)
            other.splitViewController.view.layoutSubtreeIfNeeded()
            guard let ai = other.aiChatVC, let aiItem = other.aiSplitItem else { check(false, "AI 패널 생성"); return }
            checkEqual(other.splitViewController.splitViewItems.count, 3, "칸 셋")
            check(other.splitViewController.splitViewItems[1].viewController === other.browserVC, "웹이 없을 때 목록은 1번")
            check(abs(ai.view.frame.width - AIChatViewController.defaultWidth) < 2, "AI 기본 폭으로 열림: \(ai.view.frame.width)")
            other.showWebMode(nil)
            other.splitViewController.view.layoutSubtreeIfNeeded()
            guard let web = other.webPanelVC else { check(false, "웹 패널 생성"); return }
            check(aiItem.isCollapsed && other.webSplitItem?.isCollapsed == false, "웹만 펼침")
            checkLayout(other, content: other.browserVC, "웹 연 뒤")
            check(abs(web.view.frame.width - WebPanelViewController.defaultWidth) < 2, "웹 기본 폭으로 열림: \(web.view.frame.width)")
            checkWebBetween(other, "AI 먼저")
            checkEqual(other.window?.minSize.width, 980, "웹 최소 폭")
            other.switchToMode(.viewer)
            checkLayout(other, content: other.viewerVC, "뷰어")
            check(other.webSplitItem?.isCollapsed == false && aiItem.isCollapsed, "웹 유지, AI 접힌 채")
            checkWebBetween(other, "뷰어")
            other.switchToMode(.browser)
            checkLayout(other, content: other.browserVC, "목록")
            other.showAIMode(nil)
            other.splitViewController.view.layoutSubtreeIfNeeded()
            check(!aiItem.isCollapsed && other.webSplitItem?.isCollapsed == true, "AI 다시 펼침")
            check(abs(ai.view.frame.width - AIChatViewController.defaultWidth) < 2, "AI 폭 그대로: \(ai.view.frame.width)")
        }
    }
    runTest("사이드바를 접은 채 웹을 처음 열어도 왼쪽 끝에서 기본 폭으로 열린다") {
        makeWideController("sidebar-collapsed") { other in
            other.splitViewController.splitViewItems[0].isCollapsed = true
            other.showWebMode(nil)
            other.splitViewController.view.layoutSubtreeIfNeeded()
            guard let web = other.webPanelVC else { check(false, "웹 패널 생성"); return }
            check(abs(web.view.frame.width - WebPanelViewController.defaultWidth) < 2, "웹 기본 폭으로 열림: \(web.view.frame.width)")
            checkWebBetween(other, "사이드바 접힘")
            // 사이드바 토글은 사이드바만 펼치고 웹은 그대로 둔다.
            other.toggleSidebar(nil)
            check(waitUntil { other.splitViewController.splitViewItems[0].isCollapsed == false }, "사이드바 펼침")
            check(other.webSplitItem?.isCollapsed == false, "웹은 그대로 펼침")
            check(other.splitViewController.splitViewItems[0].viewController === other.sidebarVC, "토글 대상은 사이드바")
            other.toggleSidebar(nil)
            check(waitUntil { other.splitViewController.splitViewItems[0].isCollapsed }, "사이드바 다시 접힘")
            check(other.webSplitItem?.isCollapsed == false, "웹은 여전히 펼침")
        }
    }
    runTest("웹 폭은 다시 열어도 남겨 둔 폭이고 창을 넓히면 목록이 늘어난다") {
        makeWideController("width") { other in
            other.showWebMode(nil)
            other.splitViewController.view.layoutSubtreeIfNeeded()
            guard let web = other.webPanelVC, let window = other.window else { check(false, "웹 패널 생성"); return }
            let splitView = other.splitViewController.splitView
            splitView.setPosition(splitFrame(other, web.view).minX + 600, ofDividerAt: 1)
            other.splitViewController.view.layoutSubtreeIfNeeded()
            check(abs(web.view.frame.width - 600) < 2, "끌어서 넓힌 폭: \(web.view.frame.width)")
            other.showWebMode(nil)
            check(other.webSplitItem?.isCollapsed == true, "접힘")
            other.showWebMode(nil)
            other.splitViewController.view.layoutSubtreeIfNeeded()
            check(abs(web.view.frame.width - 600) < 2, "다시 열어도 남긴 폭: \(web.view.frame.width)")
            let sidebarWidth = other.sidebarVC.view.frame.width
            let contentWidth = other.browserVC.view.frame.width
            var frame = window.frame
            frame.size.width += 200
            window.setFrame(frame, display: false)
            other.splitViewController.view.layoutSubtreeIfNeeded()
            check(abs(web.view.frame.width - 600) < 2, "창을 넓혀도 웹 폭 그대로: \(web.view.frame.width)")
            check(abs(other.sidebarVC.view.frame.width - sidebarWidth) < 2, "사이드바 폭 그대로")
            check(abs(other.browserVC.view.frame.width - (contentWidth + 200)) < 2, "목록이 늘어난다: \(other.browserVC.view.frame.width)")
            // 목록 최소 폭(400)보다 넓게 남도록 처음보다 50만 좁힌다.
            frame.size.width -= 250
            window.setFrame(frame, display: false)
            other.splitViewController.view.layoutSubtreeIfNeeded()
            check(abs(web.view.frame.width - 600) < 2, "창을 좁혀도 웹 폭 그대로: \(web.view.frame.width)")
            check(abs(other.browserVC.view.frame.width - (contentWidth - 50)) < 2, "목록이 줄어든다: \(other.browserVC.view.frame.width)")
        }
    }
    runWebImageSaveUITests(controller: controller, server: server, png: png)
}

/// 저장 연결과 끌어다 놓기. 목록·사이드바·우클릭 저장이 고른 폴더로 가는지 본다.
@MainActor
private func runWebImageSaveUITests(controller: MainWindowController, server: WebTestServer, png: Data) {
    let fileManager = FileManager.default
    // 목록은 심볼릭 링크를 푼 실제 경로(/private/var…)로 읽으므로 처음부터 그 경로를 쓴다.
    let temporary = realpath(fileManager.temporaryDirectory.path, nil).map { pointer in
        defer { free(pointer) }
        return URL(fileURLWithPath: String(cString: pointer), isDirectory: true)
    } ?? fileManager.temporaryDirectory
    let root = temporary.appendingPathComponent("jena-web-save-\(UUID().uuidString)")
    let directory = root.appendingPathComponent("목록")
    let subfolder = directory.appendingPathComponent("하위")
    let other = root.appendingPathComponent("다른 폴더")
    for url in [subfolder, other] { try! fileManager.createDirectory(at: url, withIntermediateDirectories: true) }
    let previousFolder = controller.currentFolderURL
    defer {
        controller.switchToMode(.browser)
        controller.currentFolderURL = previousFolder
        for url in controller.folderWatcher.watchedURLs where url.path.hasPrefix(root.path) { controller.folderWatcher.unwatch(url) }
        try? fileManager.removeItem(at: root)
    }
    func makeImage(_ name: String) -> URL {
        let url = directory.appendingPathComponent(name)
        try! png.write(to: url)
        return url
    }
    func exists(_ url: URL) -> Bool { fileManager.fileExists(atPath: url.path) }

    let collection = descendants(controller.browserVC.view, of: NSCollectionView.self).first!
    let outline = descendants(controller.sidebarVC.view, of: NSOutlineView.self).first!
    /// 목록에 폴더를 띄우고 다 읽을 때까지 기다린다. 항목 순서는 폴더(0) 다음 이미지(1).
    func showFolder(_ url: URL) {
        controller.navigateToFolder(url)
        check(waitUntil(timeout: 5) { !controller.browserVC.isFolderLoading }, "폴더 읽기: \(url.lastPathComponent)")
        collection.layoutSubtreeIfNeeded()
    }
    func itemPoint(_ index: Int) -> NSPoint {
        let frame = collection.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame ?? .zero
        return collection.convert(NSPoint(x: frame.midX, y: frame.midY), to: nil)
    }
    /// 어느 타일에도 닿지 않는 자리(내용 아래).
    func emptyPoint() -> NSPoint {
        let height = collection.collectionViewLayout?.collectionViewContentSize.height ?? 0
        return collection.convert(NSPoint(x: 4, y: height + 40), to: nil)
    }
    func highlighted(_ index: Int) -> Bool {
        (collection.item(at: IndexPath(item: index, section: 0))?.view as? LibraryCardView)?.isDropTarget == true
    }

    // 웹 패널을 펼치고 이미지 페이지를 연다.
    if controller.webSplitItem?.isCollapsed != false { controller.showWebMode(nil) }
    guard let web = controller.webPanelVC else { check(false, "웹 패널"); return }
    let pageURL = server.baseURL.appendingPathComponent("images.html")
    web.engine.load(pageURL)
    check(waitUntil(timeout: 10) { !web.engine.isLoading && web.engine.currentURL == pageURL }, "이미지 페이지 열기")
    /// 페이지에서 dragstart를 일으켜 엔진이 끄는 이미지를 알게 한다.
    func startWebDrag(_ id: String = "a") -> Bool {
        web.engine.webView.evaluateJavaScript("document.getElementById('\(id)').dispatchEvent(new DragEvent('dragstart', {bubbles: true}))")
        return waitUntil(timeout: 5) { (web.engine.takeDraggedImage() != nil) == (id != "plain") }
    }
    /// 웹 뷰에서 출발한 드래그. 보드의 주소는 일부러 다른 주소다 — 저장은 스크립트가 알린 값으로 한다.
    func webDrag(at location: NSPoint) -> FakeDrag {
        FakeDrag(urlOnly: URL(string: "https://example.invalid/link.html")!, source: web.engine.webView, location: location)
    }
    func report(_ path: String) -> WebImageReport {
        WebImageReport(currentSrc: "", src: server.baseURL.appendingPathComponent(path).absoluteString,
                       srcset: "", pageURL: pageURL.absoluteString)
    }

    runTest("목록의 위치 판정이 메이슨리 레이아웃에서 폴더 타일을 찾는다") {
        let image = makeImage("옮길.png")
        showFolder(directory)
        check(collection.performDragOperation(FakeDrag(fileURLs: [image], location: itemPoint(0))), "파일을 폴더 타일에 놓으면 받는다")
        check(waitUntil { exists(subfolder.appendingPathComponent(image.lastPathComponent)) }, "옮겨졌다")
        check(!exists(image), "원래 자리에는 없다")
    }
    runTest("파일 드래그는 폴더 타일에만 놓이고 폴더를 자기 안으로 옮기지 않는다") {
        let image = makeImage("남을.png")
        showFolder(directory)
        checkEqual(collection.draggingUpdated(FakeDrag(fileURLs: [image], location: itemPoint(0))), .move, "폴더 타일 위는 옮기기")
        check(highlighted(0), "폴더 타일 강조")
        collection.draggingExited(nil)
        check(!highlighted(0), "벗어나면 강조 해제")
        check(!collection.draggingUpdated(FakeDrag(fileURLs: [image], location: itemPoint(1))).contains(.move), "이미지 타일 위는 옮기기 아님")
        check(!highlighted(1), "이미지 타일은 강조하지 않음")
        check(!collection.performDragOperation(FakeDrag(fileURLs: [image], location: itemPoint(1))), "이미지 타일에 놓으면 받지 않는다")
        check(!collection.performDragOperation(FakeDrag(fileURLs: [image], location: emptyPoint())), "빈 곳에 놓으면 받지 않는다")
        checkEqual(collection.draggingUpdated(FakeDrag(fileURLs: [subfolder], location: itemPoint(0))), [], "폴더를 자기 위에")
        check(!collection.performDragOperation(FakeDrag(fileURLs: [subfolder], location: itemPoint(0))), "폴더를 자기 안으로 옮기지 않는다")
        checkEqual(collection.draggingUpdated(FakeDrag(fileURLs: [directory], location: itemPoint(0))), [], "부모 폴더를 자식 위에")
        check(exists(image) && exists(subfolder), "그대로")
    }
    /// 이미 그 폴더에 있는 항목을 폴더 타일에 놓으면 거부한다. 받으면 겹침 대화창이 떠 테스트가 멈추므로
    /// 동작이 `[]`일 때만 놓기까지 해 본다.
    func checkRefusedOnFolderTile(_ urls: [URL], _ label: String) {
        let operation = collection.draggingUpdated(FakeDrag(fileURLs: urls, location: itemPoint(0)))
        checkEqual(operation, [], "\(label): 동작")
        guard operation == [] else { return }
        check(!highlighted(0), "\(label): 강조 없음")
        check(!collection.performDragOperation(FakeDrag(fileURLs: urls, location: itemPoint(0))), "\(label): 놓기 거부")
    }
    runTest("이미 그 폴더에 있는 항목은 폴더 타일에 놓아도 옮기지 않는다") {
        showFolder(directory)
        let inside = subfolder.appendingPathComponent("안.png")
        try! png.write(to: inside)
        let inner = subfolder.appendingPathComponent("안쪽 폴더")
        try! fileManager.createDirectory(at: inner, withIntermediateDirectories: true)
        try! png.write(to: inner.appendingPathComponent("깊은.png"))
        let outside = makeImage("섞인.png")

        checkRefusedOnFolderTile([inside], "제 폴더의 파일")
        checkEqual(try? Data(contentsOf: inside), png, "파일 그대로")
        checkRefusedOnFolderTile([inner], "제 폴더의 하위 폴더")
        check(exists(inner.appendingPathComponent("깊은.png")), "폴더 트리 그대로")
        // 대소문자만 다른 경로도 같은 폴더다(기본 APFS).
        let upper = URL(fileURLWithPath: subfolder.deletingLastPathComponent().path)
            .appendingPathComponent("하위", isDirectory: true).appendingPathComponent("안.PNG")
        checkRefusedOnFolderTile([upper], "대소문자만 다른 경로")
        checkRefusedOnFolderTile([outside, inside], "섞인 드래그")
        check(exists(outside) && exists(inside), "하나도 옮기지 않음")
    }
    runTest("옮기기 경로는 원본과 대상이 같은 파일이면 대화창 없이 건너뛴다") {
        // 사이드바 드롭 경로. 같은 파일을 겹침으로 보거나 오류를 띄우면 대화창(runModal)에서 멈추므로,
        // 다음 줄에 닿은 것 자체가 대화창이 없었다는 뜻이다.
        let inside = subfolder.appendingPathComponent("사이드바.png")
        try! png.write(to: inside)
        controller.sidebar(controller.sidebarVC, didReceiveDrop: [inside], toFolder: subfolder)
        checkEqual(try? Data(contentsOf: inside), png, "파일 그대로")
        check(!exists(subfolder.appendingPathComponent("사이드바 2.png")), "이름을 바꾸지 않음")
    }
    runTest("웹 이미지를 목록의 빈 곳에 놓으면 지금 폴더에 저장된다") {
        showFolder(directory)
        collection.deselectAll(nil)
        check(startWebDrag(), "드래그 알림")
        checkEqual(collection.draggingEntered(webDrag(at: emptyPoint())), .copy, "빈 곳 들어옴")
        checkEqual(collection.draggingUpdated(webDrag(at: emptyPoint())), .copy, "빈 곳 위")
        check(collection.performDragOperation(webDrag(at: emptyPoint())), "놓기")
        let saved = directory.appendingPathComponent("big.png")
        check(waitUntil(timeout: 10) { exists(saved) }, "저장")
        check(waitUntil(timeout: 5) { controller.browserVC.selectedURLs() == [saved] }, "새 파일 선택")
        check(web.statusLabel.stringValue.hasPrefix("저장했습니다: "), "상태 줄: \(web.statusLabel.stringValue)")
        check(!exists(directory.appendingPathComponent("link.html")), "보드의 주소로 받지 않는다")
    }
    runTest("웹 이미지를 폴더 타일·사이드바 폴더에 놓으면 그 폴더에 저장된다") {
        showFolder(directory)
        check(startWebDrag(), "드래그 알림")
        checkEqual(collection.draggingUpdated(webDrag(at: itemPoint(0))), .copy, "폴더 타일 위")
        check(highlighted(0), "폴더 타일 강조")
        checkEqual(collection.draggingUpdated(webDrag(at: itemPoint(1))), .copy, "이미지 타일 위는 지금 폴더")
        check(!highlighted(0) && !highlighted(1), "이미지 타일 위에서는 강조 없음")
        check(collection.performDragOperation(webDrag(at: itemPoint(0))), "폴더 타일에 놓기")
        check(waitUntil(timeout: 10) { exists(subfolder.appendingPathComponent("big.png")) }, "폴더 타일의 폴더에 저장")
        check(!highlighted(0), "놓은 뒤 강조 해제")
        // 놓은 드래그는 다 쓴 것이다. 새 dragstart 없는 다음 드래그로 다시 저장하지 않는다.
        check(!collection.performDragOperation(webDrag(at: itemPoint(0))), "새 드래그 없이 다시 놓으면 받지 않는다")
        check(!controller.handleWebImageDrop(from: webDrag(at: .zero), to: other), "직접 불러도 받지 않는다")
        _ = waitUntil(timeout: 1) { false }
        check(!exists(subfolder.appendingPathComponent("big 2.png")) && !exists(other.appendingPathComponent("big.png")), "두 번째 파일 없음")

        check(startWebDrag(), "새 드래그 알림")
        let node = FolderNode(url: other)
        checkEqual(controller.sidebarVC.outlineView(outline, validateDrop: webDrag(at: .zero), proposedItem: node, proposedChildIndex: -1),
                   .copy, "사이드바 폴더 위")
        check(controller.sidebarVC.outlineView(outline, acceptDrop: webDrag(at: .zero), item: node, childIndex: -1), "사이드바에 놓기")
        check(waitUntil(timeout: 10) { exists(other.appendingPathComponent("big.png")) }, "사이드바 폴더에 저장")
    }
    runTest("웹 패널이 아닌 곳에서 온 비파일 드래그는 받지 않는다") {
        showFolder(directory)
        let foreign = { (location: NSPoint) in FakeDrag(urlOnly: URL(string: "https://x.com/a.png")!, source: nil, location: location) }
        checkEqual(collection.draggingEntered(foreign(emptyPoint())), [], "목록 거부")
        checkEqual(collection.draggingUpdated(foreign(itemPoint(0))), [], "폴더 타일 위도 거부")
        check(!highlighted(0), "강조 없음")
        check(!collection.performDragOperation(foreign(itemPoint(0))), "놓아도 받지 않는다")
        let node = FolderNode(url: other)
        checkEqual(controller.sidebarVC.outlineView(outline, validateDrop: foreign(.zero), proposedItem: node, proposedChildIndex: -1),
                   [], "사이드바 거부")
        check(!controller.sidebarVC.outlineView(outline, acceptDrop: foreign(.zero), item: node, childIndex: -1), "사이드바에 놓아도 받지 않는다")
        let file = FakeDrag(fileURLs: [makeImage("파일.png")], location: .zero)
        checkEqual(controller.sidebarVC.outlineView(outline, validateDrop: file, proposedItem: node, proposedChildIndex: -1),
                   .move, "사이드바의 파일 드래그는 그대로")
        // 출발지가 웹 뷰여도 끄는 것이 이미지가 아니면 받지 않는다.
        check(startWebDrag("plain"), "이미지 아닌 드래그 알림")
        checkEqual(collection.draggingUpdated(webDrag(at: emptyPoint())), [], "이미지 아닌 웹 드래그 거부")
        checkEqual(controller.sidebarVC.outlineView(outline, validateDrop: webDrag(at: .zero), proposedItem: node, proposedChildIndex: -1),
                   [], "사이드바도 거부")
    }
    runTest("실제 폴더가 없는 화면에서는 저장하지 않는다") {
        controller.showBookmarks()
        check(controller.webSaveFolderURL == nil, "저장 폴더 없음")
        check(startWebDrag(), "드래그 알림")
        checkEqual(collection.draggingUpdated(webDrag(at: emptyPoint())), [], "빈 곳 위 거부")
        check(!controller.handleWebImageDrop(from: webDrag(at: emptyPoint()), to: nil), "빈 곳 드롭 거부")
        checkEqual(web.engine.contextMenuItems(for: report("big.png")).first?.isEnabled, false, "우클릭 항목 비활성")
        showFolder(directory)
        checkEqual(controller.webSaveFolderURL, directory, "실제 폴더면 그 폴더")
        checkEqual(web.engine.contextMenuItems(for: report("big.png")).first?.title, "'목록'에 저장", "우클릭 항목")
    }
    runTest("우클릭 저장 항목은 누른 순간의 폴더에 저장한다") {
        showFolder(directory)
        server.delayBody(forPath: "/slow.png", by: 0.5)
        web.engine.webView.evaluateJavaScript("document.getElementById('slow').dispatchEvent(new MouseEvent('contextmenu', {bubbles: true}))")
        check(waitUntil(timeout: 5) { web.engine.lastContextImage?.src.hasSuffix("/slow.png") == true }, "우클릭 알림")
        guard let item = web.engine.contextMenuItems(for: web.engine.lastContextImage).first, let action = item.action else {
            check(false, "저장 항목"); return
        }
        app.sendAction(action, to: item.target, from: item)
        showFolder(other)
        let saved = directory.appendingPathComponent("slow.png")
        check(waitUntil(timeout: 10) { exists(saved) }, "누른 순간의 폴더")
        check(!exists(other.appendingPathComponent("slow.png")), "옮긴 폴더에는 없음")
        // 파일은 내려받는 도중에 생기므로 끝난 뒤에 지운다.
        check(waitUntil(timeout: 10) { web.statusLabel.stringValue == "저장했습니다: slow.png" }, "저장 완료")
        try? fileManager.removeItem(at: saved)
    }
    runTest("내려받는 동안 폴더를 옮기거나 패널을 접어도 처음 폴더에 저장된다") {
        showFolder(directory)
        server.delayBody(forPath: "/slow.png", by: 0.5)
        controller.saveWebImage(report("slow.png"), to: directory)   // 서버의 /slow.png는 0.5초 뒤 응답
        controller.navigateToFolder(other); controller.showWebMode(nil)
        check(controller.webSplitItem?.isCollapsed == true, "패널 접힘")
        check(waitUntil(timeout: 10) { exists(directory.appendingPathComponent("slow.png")) }, "처음 폴더")
        check(!exists(other.appendingPathComponent("slow.png")), "옮긴 폴더에는 없음")
        check(waitUntil(timeout: 10) { web.statusLabel.stringValue == "저장했습니다: slow.png" }, "저장 완료")
        controller.showWebMode(nil)
    }
    runTest("뷰어로 보는 중에 저장돼도 보던 이미지가 바뀌지 않는다") {
        let viewed = makeImage("보는 중.png")
        showFolder(directory)
        controller.browser(controller.browserVC, didRequestViewImage: viewed, inList: [ImageFile(url: viewed)!])
        check(waitUntil { controller.viewerVC.currentImageURL == viewed }, "뷰어로 보기")
        web.showStatus("")
        controller.saveWebImage(report("big.png"), to: directory)
        check(waitUntil(timeout: 10) { web.statusLabel.stringValue.hasPrefix("저장했습니다: ") }, "상태 줄만 갱신")
        check(exists(directory.appendingPathComponent("big 2.png")), "겹치지 않는 이름으로 저장")
        _ = waitUntil(timeout: 0.5) { false }
        checkEqual(controller.viewerVC.currentImageURL, viewed, "보던 이미지 그대로")
        checkEqual(controller.contentMode, .viewer, "뷰어 유지")
    }
}

/// 테스트용 드래그. 시험 대상이 읽는 출발지·보드·위치만 채운다.
private final class FakeDrag: NSObject, NSDraggingInfo {
    let draggingSource: Any?
    let draggingPasteboard: NSPasteboard
    let draggingLocation: NSPoint

    private init(source: Any?, location: NSPoint, write: (NSPasteboard) -> Void) {
        draggingSource = source
        draggingLocation = location
        draggingPasteboard = NSPasteboard(name: NSPasteboard.Name("jena-fake-drag-\(UUID().uuidString)"))
        draggingPasteboard.clearContents()
        write(draggingPasteboard)
    }
    /// 목록·Finder에서 온 파일 드래그.
    convenience init(fileURLs: [URL], location: NSPoint) {
        self.init(source: nil, location: location) { $0.writeObjects(fileURLs as [NSURL]) }
    }
    /// 주소 한 줄만 실린 드래그.
    convenience init(urlOnly url: URL, source: Any?, location: NSPoint) {
        self.init(source: source, location: location) { $0.setString(url.absoluteString, forType: .URL) }
    }
    deinit { draggingPasteboard.releaseGlobally() }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .every }
    var draggedImageLocation: NSPoint { draggingLocation }
    var draggedImage: NSImage? { nil }
    var draggingSequenceNumber: Int { 0 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
