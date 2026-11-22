import AppKit
import WebKit

@MainActor
func runWebPanelEngineTests() {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let png = bitmap.representation(using: .png, properties: [:])!
    let page = """
        <!doctype html><body style="margin:0">
        <img id=a src="/a.png" srcset="/a.png 100w, /big.png 800w" style="display:block;width:200px;height:200px">
        <p id=plain>글</p></body>
        """
    // 위쪽 100pt는 새 창 링크, 그 아래 100pt는 window.open 버튼, 그 아래 100pt는 http가 아닌 주소의 window.open 버튼.
    let links = """
        <!doctype html><body style="margin:0">
        <a href="/page.html" target="_blank" style="display:block;height:100px;background:#ccc">새 창 링크</a>
        <button onclick="window.open('/popup.html')" style="display:block;width:100%;height:100px;margin:0">팝업</button>
        <button onclick="window.open('ftp://example.com/x')" style="display:block;width:100%;height:100px;margin:0">ftp 팝업</button>
        <a href="/page.html" style="display:block;height:100px;background:#eee">같은 탭 링크</a></body>
        """
    // 한 번 누르면 창 다섯을 연다.
    let burst = """
        <!doctype html><body style="margin:0">
        <button onclick="for (let i = 0; i < 5; i++) window.open('/blank.html?' + i)" style="display:block;width:100%;height:100px;margin:0">다섯</button></body>
        """
    let mediaLink = """
        <!doctype html><body style="margin:0">
        <a href="/media.html" target="_blank" style="display:block;height:100px;background:#ccc">영상 새 창</a></body>
        """
    // 파일 선택 칸이 위쪽 100pt를 채운다. 선택 창이 아무것도 고르지 않고 끝나면 cancel이 온다.
    let upload = """
        <!doctype html><body style="margin:0">
        <input id=f type=file style="display:block;width:300px;height:100px">
        <script>document.getElementById('f').addEventListener('cancel', () => { window.pickerCancelled = true; });</script></body>
        """
    // 페이지가 window 캡처 단계에서 우클릭·드래그 전파를 끊는다.
    let stopper = """
        <!doctype html><body style="margin:0">
        <script>for (const type of ['contextmenu', 'dragstart']) window.addEventListener(type, e => e.stopImmediatePropagation(), true);</script>
        <img id=a src="/a.png?stop" style="display:block;width:100px;height:100px"></body>
        """
    // 페이지가 끌기를 막는 세 가지 방식: dragstart 취소(회전목마), 끌 수 없게 표시한 이미지, 덮개에 가린 이미지.
    let blocked = """
        <!doctype html><body style="margin:0">
        <script>document.addEventListener('dragstart', e => { window.pageSawDragstart = true; e.preventDefault(); }, true);</script>
        <img id=carousel src="/a.png?carousel" style="display:block;width:100px;height:100px">
        <img id=locked src="/a.png?locked" draggable="false" style="display:block;width:100px;height:100px;-webkit-user-drag:none">
        <div style="position:relative;width:100px;height:100px">
          <img id=covered src="/a.png?covered" style="position:absolute;inset:0;width:100px;height:100px">
          <div id=cover style="position:absolute;inset:0"></div>
        </div>
        <p id=text style="margin:0;height:50px">글</p></body>
        """
    let server: WebTestServer
    do {
        server = try WebTestServer(routes: [
            "/page.html": (200, ["Content-Type": "text/html; charset=utf-8"], Data(page.utf8)),
            "/a.png": (200, ["Content-Type": "image/png"], png),
            "/big.png": (200, ["Content-Type": "image/png"], png),
            "/html.png": (200, ["Content-Type": "text/html"], Data("<html>오류</html>".utf8)),
            "/missing.png": (404, ["Content-Type": "text/html"], Data("not found".utf8)),
            "/fake.png": (200, ["Content-Type": "image/png"], Data("<html>가짜 이미지</html>".utf8)),
            "/case/Photo.PNG": (200, ["Content-Type": "image/png"], png),
            "/case/photo.png": (200, ["Content-Type": "image/png"], png),
            "/links.html": (200, ["Content-Type": "text/html; charset=utf-8"], Data(links.utf8)),
            "/popup.html": (200, ["Content-Type": "text/html; charset=utf-8"], Data(links.utf8)),
            "/blank.html": (200, ["Content-Type": "text/html; charset=utf-8"], Data("<!doctype html><p>빈 페이지</p>".utf8)),
            "/file.bin": (200, ["Content-Type": "application/octet-stream", "Content-Disposition": "attachment; filename=\"file.bin\""],
                          Data("내려받을 파일".utf8)),
            "/upload.html": (200, ["Content-Type": "text/html; charset=utf-8"], Data(upload.utf8)),
            "/stopper.html": (200, ["Content-Type": "text/html; charset=utf-8"], Data(stopper.utf8)),
            "/blocked.html": (200, ["Content-Type": "text/html; charset=utf-8"], Data(blocked.utf8)),
            "/media.html": (200, ["Content-Type": "text/html; charset=utf-8"],
                            Data("<!doctype html><audio id=m src=\"/silence.wav\" autoplay loop muted></audio>".utf8)),
            "/silence.wav": (200, ["Content-Type": "audio/wav"], silentWAV()),
            "/slowsave.png": (200, ["Content-Type": "image/png"], Data(repeating: 7, count: 256 * 1024)),
            "/slowtab.png": (200, ["Content-Type": "image/png"], png),
            "/burst.html": (200, ["Content-Type": "text/html; charset=utf-8"], Data(burst.utf8)),
            "/medialink.html": (200, ["Content-Type": "text/html; charset=utf-8"], Data(mediaLink.utf8)),
        ])
    } catch {
        check(false, "테스트 서버 시작: \(error)")
        return
    }
    defer { server.stop() }

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("jena-web-engine-\(UUID().uuidString)")
    let folder = root.appendingPathComponent("저장 폴더")
    let empty = root.appendingPathComponent("빈 폴더")
    let dataFolder = root.appendingPathComponent("data 폴더")
    for url in [folder, empty, dataFolder] { try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    defer { try? FileManager.default.removeItem(at: root) }

    let engine = WebPageEngine(dataStore: .nonPersistent())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    engine.containerView.frame = window.contentView!.bounds
    engine.containerView.autoresizingMask = [.width, .height]
    window.contentView!.addSubview(engine.containerView)
    defer { window.close() }

    let pageURL = server.baseURL.appendingPathComponent("page.html")
    func report(src: String) -> WebImageReport {
        WebImageReport(currentSrc: "", src: src, srcset: "", pageURL: pageURL.absoluteString)
    }
    let saver = WebImageSaver(engine: engine)
    var results: [Result<URL, WebImageSaveError>] = []
    var failures: [WebImageSaveError] = []
    var lastResult: Result<URL, WebImageSaveError>? { results.last }
    saver.onFinish = { result, _ in
        results.append(result)
        if case .failure(let error) = result { failures.append(error) }
    }

    runTest("페이지를 불러오면 상태가 바뀐다") {
        var changes = 0
        engine.onStateChange = { changes += 1 }
        engine.load(pageURL)
        check(waitUntil(timeout: 10) { !engine.isLoading && engine.currentURL?.lastPathComponent == "page.html" }, "불러오기 완료")
        check(!engine.canGoBack, "첫 페이지는 뒤로 없음")
        check(!engine.canGoForward, "앞으로 없음")
        check(changes > 0, "상태 변화 알림")
        checkEqual(engine.tabs.count, 1, "탭 하나")
        engine.onStateChange = nil
    }

    runTest("http·https가 아닌 주소는 열지 않고 알린다") {
        var notices: [String] = []
        engine.onNotice = { notices.append($0) }
        engine.load(URL(string: "file:///etc/hosts")!)
        checkEqual(notices.count, 1, "안내 한 줄")
        _ = waitUntil(timeout: 0.3) { false }
        checkEqual(engine.currentURL?.lastPathComponent, "page.html", "페이지 유지")
        engine.onNotice = nil
    }

    runTest("스크립트가 우클릭·드래그 대상 이미지를 알린다") {
        engine.webView.evaluateJavaScript("document.getElementById('a').dispatchEvent(new MouseEvent('contextmenu', {bubbles: true}))")
        check(waitUntil(timeout: 5) { engine.lastContextImage != nil }, "우클릭 알림")
        checkEqual(engine.lastContextImage.flatMap { WebImageCandidate.bestURL(for: $0) }?.lastPathComponent, "big.png", "srcset의 큰 후보")
        checkEqual(engine.lastContextImage?.pageURL, pageURL.absoluteString, "페이지 주소")
        engine.webView.evaluateJavaScript("document.getElementById('a').dispatchEvent(new DragEvent('dragstart', {bubbles: true}))")
        check(waitUntil(timeout: 5) { engine.takeDraggedImage() != nil }, "드래그 알림")
        check(engine.takeDraggedImage() != nil, "읽어도 지우지 않는다")
        engine.webView.evaluateJavaScript("document.getElementById('plain').dispatchEvent(new MouseEvent('contextmenu', {bubbles: true}))")
        check(waitUntil(timeout: 5) { engine.lastContextImage == nil }, "이미지 아닌 곳 우클릭은 이전 값을 지운다")
    }

    runTest("드래그 출발지는 엔진의 웹 뷰와 그 하위 뷰다") {
        check(engine.isDragSource(engine.webView), "웹 뷰")
        let child = NSView()
        engine.webView.addSubview(child)
        check(engine.isDragSource(child), "하위 뷰")
        child.removeFromSuperview()
        check(!engine.isDragSource(NSView()), "다른 뷰")
        check(!engine.isDragSource(nil), "출발지 없음")
        check(WebPageEngine.imageDragTypes.contains(.URL), "주소 종류 등록")
        check(WebPageEngine.imageDragTypes.contains(.tiff), "TIFF 종류 등록")
    }

    let menuReport = report(src: "/a.png")
    runTest("우클릭 메뉴에 폴더 저장 항목이 붙는다") {
        engine.saveFolderProvider = { folder }
        let items = engine.contextMenuItems(for: menuReport)
        checkEqual(items.first?.title, "'\(folder.lastPathComponent)'에 저장", "폴더 이름")
        check(items.first?.isEnabled == true, "활성")
        engine.saveFolderProvider = { nil }
        checkEqual(engine.contextMenuItems(for: menuReport).first?.title, "저장할 폴더를 먼저 선택하세요", "폴더 없음 안내")
        check(engine.contextMenuItems(for: menuReport).first?.isEnabled == false, "비활성")
        check(engine.contextMenuItems(for: nil).isEmpty, "이미지가 아니면 항목 없음")
    }

    runTest("저장 항목은 누르는 순간의 이미지와 폴더로 저장을 요청한다") {
        var requested: [(WebImageReport, URL)] = []
        engine.onSaveImage = { requested.append(($0, $1)) }
        engine.saveFolderProvider = { folder }
        engine.webView.evaluateJavaScript("document.getElementById('a').dispatchEvent(new MouseEvent('contextmenu', {bubbles: true}))")
        _ = waitUntil(timeout: 5) { engine.lastContextImage != nil }
        guard let item = engine.contextMenuItems(for: engine.lastContextImage).first, let action = item.action else {
            check(false, "저장 항목"); return
        }
        engine.saveFolderProvider = { empty }
        app.sendAction(action, to: item.target, from: item)
        checkEqual(requested.count, 1, "한 번 요청")
        checkEqual(requested.first?.1, empty, "누른 순간의 폴더")
        checkEqual(requested.first?.0, engine.lastContextImage, "누른 순간의 이미지")
        engine.onSaveImage = nil
    }

    runTest("실제 우클릭 메뉴 맨 위에 저장 항목과 구분선이 들어간다") {
        engine.saveFolderProvider = { folder }
        var titles: [String]?
        var separatorSecond = false
        let observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
            guard let object = note.object as? NSMenu else { return }
            nonisolated(unsafe) let menu = object
            // 알림은 willOpenMenu보다 먼저 온다. 메뉴 고리가 돈 뒤에 읽고 닫는다.
            RunLoop.main.perform(inModes: [.eventTracking, .default]) {
                MainActor.assumeIsolated {
                    titles = menu.items.map(\.title)
                    separatorSecond = menu.items.count > 1 && menu.items[1].isSeparatorItem
                    menu.cancelTrackingWithoutAnimation()
                }
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let location = engine.webView.convert(NSPoint(x: 100, y: engine.webView.isFlipped ? 100 : engine.webView.bounds.height - 100), to: nil)
        for type in [NSEvent.EventType.rightMouseDown, .rightMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            if type == .rightMouseDown { engine.webView.rightMouseDown(with: event) } else { engine.webView.rightMouseUp(with: event) }
            _ = waitUntil(timeout: 0.3) { titles != nil }
        }
        check(waitUntil(timeout: 5) { titles != nil }, "메뉴 열림")
        checkEqual(titles?.first, "'\(folder.lastPathComponent)'에 저장", "맨 위 저장 항목")
        check(separatorSecond, "구분선")
    }

    runTest("앱에서는 페이지가 만든 가짜 우클릭·끌기를 받지 않고, 실제 우클릭은 받는다") {
        WebPageEngine.requiresTrustedEvents = true
        defer { WebPageEngine.requiresTrustedEvents = false }
        let strict = WebPageEngine(dataStore: .nonPersistent())
        let strictWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        strict.containerView.frame = strictWindow.contentView!.bounds
        strictWindow.contentView!.addSubview(strict.containerView)
        defer { strictWindow.close() }
        strict.isPresented = true
        strict.load(server.baseURL.appendingPathComponent("page.html"))
        check(waitUntil(timeout: 10) { !strict.isLoading && strict.currentURL?.lastPathComponent == "page.html" }, "불러옴")
        // 페이지 스크립트가 만든 이벤트: 받지 않는다.
        var done = false
        strict.webView.evaluateJavaScript("""
            (() => { const i = document.getElementById('a');
                     i.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, clientX: 50, clientY: 50 }));
                     const d = new DragEvent('dragstart', { bubbles: true, cancelable: true, clientX: 50, clientY: 50 });
                     i.dispatchEvent(d); return true; })()
            """) { _, _ in done = true }
        check(waitUntil(timeout: 5) { done }, "가짜 이벤트 보냄")
        _ = waitUntil(timeout: 0.6) { strict.lastContextImage != nil || strict.takeDraggedImage() != nil }
        check(strict.lastContextImage == nil, "가짜 우클릭은 받지 않음")
        check(strict.takeDraggedImage() == nil, "가짜 끌기는 받지 않음")
        // 실제 우클릭(마우스 이벤트): 받는다. 메뉴는 열리자마자 닫는다.
        let observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
            guard let object = note.object as? NSMenu else { return }
            nonisolated(unsafe) let menu = object
            RunLoop.main.perform(inModes: [.eventTracking, .default]) { MainActor.assumeIsolated { menu.cancelTrackingWithoutAnimation() } }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let view = strict.webView
        let location = view.convert(NSPoint(x: 100, y: view.isFlipped ? 100 : view.bounds.height - 100), to: nil)
        for type in [NSEvent.EventType.rightMouseDown, .rightMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: strictWindow.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            if type == .rightMouseDown { view.rightMouseDown(with: event) } else { view.rightMouseUp(with: event) }
            _ = waitUntil(timeout: 0.3) { strict.lastContextImage != nil }
        }
        check(waitUntil(timeout: 5) { strict.lastContextImage != nil }, "실제 우클릭은 받음")
    }

    runTest("이미지를 폴더에 저장하고 Referer와 이름을 지킨다") {
        results.removeAll(); failures.removeAll()
        saver.save(report(src: "/a.png"), to: folder)
        check(waitUntil(timeout: 10) { results.count == 1 }, "완료")
        if case .success(let url)? = lastResult {
            checkEqual(url.lastPathComponent, "a.png", "결과 주소")
        } else { check(false, "성공 결과: \(String(describing: lastResult))") }
        check(FileManager.default.fileExists(atPath: folder.appendingPathComponent("a.png").path), "파일 생성")
        checkEqual(server.headers(forPath: "/a.png")?["Referer"], pageURL.absoluteString, "Referer")
        saver.save(report(src: "/a.png"), to: folder); saver.save(report(src: "/a.png"), to: folder)
        check(waitUntil(timeout: 10) { results.count == 3 }, "연달아 두 번")
        checkEqual(Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []), ["a.png", "a 2.png", "a 3.png"], "서로 다른 이름")
        check(failures.isEmpty, "실패 없음: \(failures)")
    }

    runTest("이미지가 아닌 응답은 파일을 남기지 않는다") {
        results.removeAll(); failures.removeAll()
        for path in ["/html.png", "/missing.png"] { saver.save(report(src: path), to: empty) }
        check(waitUntil(timeout: 10) { failures.count == 2 }, "둘 다 실패로 알림")
        _ = waitUntil(timeout: 1) { false }
        checkEqual(results.count, 2, "저장 한 번에 결과 한 번")
        check(((try? FileManager.default.contentsOfDirectory(atPath: empty.path)) ?? ["?"]).isEmpty, "남은 파일 없음")
    }

    runTest("폴더가 사라졌으면 실패로 알린다") {
        results.removeAll(); failures.removeAll()
        saver.save(report(src: "/a.png"), to: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        check(waitUntil(timeout: 10) { if case .failure(.folderMissing)? = lastResult { return true }; return false }, "folderMissing")
    }

    runTest("저장할 수 없는 주소는 거절한다") {
        results.removeAll(); failures.removeAll()
        saver.save(WebImageReport(currentSrc: "", src: "blob:https://example.com/1", srcset: "", pageURL: "https://example.com/"), to: folder)
        check(waitUntil(timeout: 2) { if case .failure(.unsupportedAddress)? = lastResult { return true }; return false }, "unsupportedAddress")
    }

    runTest("data 주소 이미지를 저장한다") {
        results.removeAll(); failures.removeAll()
        saver.save(report(src: "data:image/png;base64,\(png.base64EncodedString())"), to: dataFolder)
        check(waitUntil(timeout: 5) { results.count == 1 }, "완료")
        guard case .success(let url)? = lastResult else { check(false, "성공 결과: \(String(describing: lastResult))"); return }
        checkEqual(url.deletingLastPathComponent().standardizedFileURL, dataFolder.standardizedFileURL, "고른 폴더")
        checkEqual(url.pathExtension, "png", "MIME 확장자")
        check(NSImage(contentsOf: url) != nil, "이미지로 읽힘")
        saver.save(report(src: "data:,hello"), to: dataFolder)
        check(waitUntil(timeout: 5) { if case .failure(.notAnImage)? = lastResult { return true }; return false }, "MIME 없는 data는 거절")
        checkEqual((try? FileManager.default.contentsOfDirectory(atPath: dataFolder.path))?.count, 1, "거절한 data는 파일 없음")
    }

    runTest("내려받은 것이 이미지가 아니면 이번 저장이 만든 파일만 지운다") {
        results.removeAll(); failures.removeAll()
        let fakeFolder = root.appendingPathComponent("가짜 폴더")
        try! FileManager.default.createDirectory(at: fakeFolder, withIntermediateDirectories: true)
        let existing = Data("원래 파일".utf8)
        try! existing.write(to: fakeFolder.appendingPathComponent("fake.png"))
        saver.save(report(src: "/fake.png"), to: fakeFolder)
        check(waitUntil(timeout: 10) { results.count == 1 }, "완료")
        check({ if case .failure(.notAnImage)? = lastResult { return true }; return false }(), "notAnImage: \(String(describing: lastResult))")
        checkEqual((try? FileManager.default.contentsOfDirectory(atPath: fakeFolder.path)) ?? [], ["fake.png"], "이번 저장의 파일은 남지 않음")
        checkEqual(try? Data(contentsOf: fakeFolder.appendingPathComponent("fake.png")), existing, "원래 파일 그대로")
    }

    runTest("대소문자만 다른 이름을 동시에 받으면 서로 다른 파일로 남는다") {
        // 두 본문이 함께 도착하면 둘 다 이름을 정한 뒤에 파일이 생긴다. APFS는 대소문자를 가리지 않아
        // 예약이 대소문자를 구분하면 같은 파일을 고르고, 진 쪽은 WebKit이 취소한다. 경합이라 여러 번 돌린다.
        server.delayBody(forPath: "/case/Photo.PNG", by: 0.3)
        server.delayBody(forPath: "/case/photo.png", by: 0.3)
        for round in 1...6 {
            results.removeAll(); failures.removeAll()
            let caseFolder = root.appendingPathComponent("동시 폴더 \(round)")
            try! FileManager.default.createDirectory(at: caseFolder, withIntermediateDirectories: true)
            saver.save(report(src: "/case/Photo.PNG"), to: caseFolder)
            saver.save(report(src: "/case/photo.png"), to: caseFolder)
            check(waitUntil(timeout: 10) { results.count == 2 }, "\(round)회: 둘 다 완료")
            _ = waitUntil(timeout: 0.3) { false }
            let saved = results.compactMap { try? $0.get() }
            checkEqual(saved.count, 2, "\(round)회: 둘 다 저장 \(failures)")
            for url in saved { check(NSImage(contentsOf: url) != nil, "\(round)회: 성공한 파일은 남는다 \(url.lastPathComponent)") }
            checkEqual((try? FileManager.default.contentsOfDirectory(atPath: caseFolder.path))?.count, 2, "\(round)회: 파일 두 개")
        }
    }

    /// 웹 뷰의 (왼쪽 위 기준) 점을 실제 마우스 클릭으로 누른다. WebKit은 이것을 사용자 동작으로 본다.
    func click(_ view: WKWebView, x: CGFloat, y: CGFloat, modifiers: NSEvent.ModifierFlags = [], middle: Bool = false) {
        let location = view.convert(NSPoint(x: x, y: view.isFlipped ? y : view.bounds.height - y), to: nil)
        let types: [NSEvent.EventType] = middle ? [.otherMouseDown, .otherMouseUp] : [.leftMouseDown, .leftMouseUp]
        for type in types {
            var event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            // `mouseEvent(with:)`는 버튼 번호를 정하지 못한다. 가운데 버튼(2)은 CGEvent 필드로 넣는다.
            if middle, let cgEvent = event.cgEvent {
                cgEvent.setIntegerValueField(.mouseEventButtonNumber, value: 2)
                event = NSEvent(cgEvent: cgEvent) ?? event
            }
            switch type {
            case .leftMouseDown: view.mouseDown(with: event)
            case .leftMouseUp: view.mouseUp(with: event)
            case .otherMouseDown: view.otherMouseDown(with: event)
            default: view.otherMouseUp(with: event)
            }
        }
    }

    /// 페이지 스크립트를 돌려 끝났는지와 값을 돌려준다. 대화창이 떠서 멈추면 finished가 false다.
    func evaluate(_ script: String, in view: WKWebView? = nil, timeout: TimeInterval = 3) -> (finished: Bool, value: Any?) {
        var finished = false
        var value: Any?
        (view ?? engine.webView).evaluateJavaScript(script) { result, _ in value = result; finished = true }
        _ = waitUntil(timeout: timeout) { finished }
        return (finished, value)
    }
    /// 실패한 시험이 남긴 시트를 걷어 다음 시험이 멈추지 않게 한다.
    func dismissSheets() {
        while let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .cancel) }
        // 창 없이 뜬 저장·열기 창도 걷는다.
        for panel in app.windows.compactMap({ $0 as? NSSavePanel }) where panel.isVisible { panel.cancel(nil) }
    }
    func loadPage(_ path: String) -> Bool {
        let url = server.baseURL.appendingPathComponent(path)
        engine.load(url)
        return waitUntil(timeout: 10) { !engine.isLoading && engine.currentURL == url }
    }

    runTest("보이지 않는 엔진의 페이지 대화창은 띄우지 않고 조용히 답한다") {
        engine.isPresented = false
        check(loadPage("blank.html"), "페이지")
        let confirmed = evaluate("confirm('확인?')")
        check(confirmed.finished && (confirmed.value as? Bool) == false, "confirm은 false: \(confirmed)")
        dismissSheets()
        let prompted = evaluate("prompt('이름?', '기본') === null")
        check(prompted.finished && (prompted.value as? Bool) == true, "prompt는 null: \(prompted)")
        dismissSheets()
        let alerted = evaluate("alert('알림'), 'done'")
        check(alerted.finished && (alerted.value as? String) == "done", "alert는 그냥 돌아온다: \(alerted)")
        dismissSheets()
        check(window.attachedSheet == nil && window.sheets.isEmpty, "시트 없음")
    }

    runTest("보이지 않는 엔진은 파일 선택 창을 띄우지 않는다") {
        engine.isPresented = false
        check(loadPage("upload.html"), "페이지")
        _ = waitUntil(timeout: 0.3) { false }
        click(engine.webView, x: 50, y: 50)
        let cancelled = waitUntil(timeout: 5) { (evaluate("window.pickerCancelled === true").value as? Bool) == true }
        check(window.attachedSheet == nil && window.sheets.isEmpty, "시트 없음")
        dismissSheets()
        check(cancelled, "선택 없이 끝남")
    }

    runTest("보이지 않는 엔진의 일반 내려받기는 저장 창 없이 거절하고 알린다") {
        engine.isPresented = false
        check(loadPage("blank.html"), "페이지")
        var notices: [String] = []
        engine.onNotice = { notices.append($0) }
        engine.load(server.baseURL.appendingPathComponent("file.bin"))
        check(waitUntil(timeout: 10) { !notices.isEmpty }, "알림")
        _ = waitUntil(timeout: 0.5) { false }
        check(window.attachedSheet == nil && window.sheets.isEmpty, "저장 창 없음")
        dismissSheets()
        checkEqual(notices, ["패널이 접혀 있어 내려받기를 취소했습니다."], "한 번 알림")
        engine.onNotice = nil
    }

    runTest("한 페이지가 10초 안에 대화창을 넷 이상 띄우면 나머지는 자동으로 답한다") {
        var shown = 0
        var notices: [String] = []
        engine.dialogPresenter = { _, _ in shown += 1; return .alertFirstButtonReturn }
        engine.onNotice = { notices.append($0) }
        engine.isPresented = true
        defer { engine.isPresented = false; engine.onNotice = nil }
        check(loadPage("blank.html"), "페이지")
        let answers = evaluate("[0, 1, 2, 3, 4].map(i => confirm('질문 ' + i))").value as? [Bool]
        checkEqual(answers, [true, true, true, false, false], "넷째부터 false")
        checkEqual(shown, 3, "세 번만 표시")
        check((evaluate("prompt('또?') === null").value as? Bool) == true, "prompt도 자동 답")
        _ = evaluate("alert('또'), 1")
        checkEqual(shown, 3, "여전히 세 번")
        checkEqual(notices, ["이 페이지의 알림창을 더 표시하지 않습니다."], "한 번 알림")
        check(loadPage("page.html"), "다음 페이지")
        checkEqual(evaluate("confirm('새 페이지')").value as? Bool, true, "새 페이지는 다시 표시")
        checkEqual(shown, 4, "표시 횟수")
        check(window.attachedSheet == nil, "실제 시트 없음")
    }

    /// 재생 상태가 `expected`가 될 때까지 묻는다. 답이 늦게 오는 때가 있어 한 번에 하나씩, 넉넉히 기다린다.
    func mediaState(becomes expected: WKMediaPlaybackState, in view: WKWebView? = nil, timeout: TimeInterval = 8) -> (Bool, String) {
        let deadline = Date().addingTimeInterval(timeout)
        var last: WKMediaPlaybackState?
        while Date() < deadline {
            var answer: WKMediaPlaybackState?
            (view ?? engine.webView).requestMediaPlaybackState { answer = $0 }
            _ = waitUntil(timeout: max(0, deadline.timeIntervalSinceNow)) { answer != nil }
            last = answer ?? last
            if answer == expected { return (true, "") }
            _ = waitUntil(timeout: 0.2) { false }
        }
        return (false, "마지막 상태 \(String(describing: last?.rawValue))")
    }
    runTest("패널이 접히면 소리를 멈추고 펼치면 다시 낸다") {
        engine.isPresented = true
        check(loadPage("media.html"), "페이지")
        var result = mediaState(becomes: .playing)
        check(result.0, "보이면 재생: \(result.1)")
        engine.isPresented = false
        result = mediaState(becomes: .suspended)
        check(result.0, "접히면 멈춤: \(result.1)")
        engine.isPresented = true
        result = mediaState(becomes: .playing)
        check(result.0, "펼치면 다시: \(result.1)")
        engine.isPresented = false
        let blank = server.baseURL.appendingPathComponent("blank.html")
        engine.load(blank)
        check(waitUntil(timeout: 10) { !engine.isLoading && engine.currentURL == blank },
              "소리 없는 페이지로: \(engine.isLoading) \(String(describing: engine.currentURL))")
    }

    runTest("페이지가 window 캡처 단계에서 전파를 끊어도 이미지를 알린다") {
        check(loadPage("stopper.html"), "페이지")
        engine.webView.evaluateJavaScript("document.getElementById('a').dispatchEvent(new MouseEvent('contextmenu', {bubbles: true}))")
        check(waitUntil(timeout: 3) { engine.lastContextImage?.src.hasSuffix("?stop") == true }, "우클릭 알림")
        engine.webView.evaluateJavaScript("document.getElementById('a').dispatchEvent(new DragEvent('dragstart', {bubbles: true}))")
        check(waitUntil(timeout: 3) { engine.takeDraggedImage()?.src.hasSuffix("?stop") == true }, "드래그 알림")
    }

    runTest("페이지가 이미지 끌기를 막아도 끌기가 시작되고 이미지를 알린다") {
        engine.clearDraggedImage()
        engine.load(server.baseURL.appendingPathComponent("blocked.html"))
        check(waitUntil(timeout: 10) { !engine.isLoading && engine.currentURL?.lastPathComponent == "blocked.html" }, "불러옴")
        // 회전목마처럼 dragstart를 취소하는 페이지: 처리기에 닿기 전에 끊어 취소되지 않는다.
        let carousel = evaluate("""
            (() => { const e = new DragEvent('dragstart', { bubbles: true, cancelable: true, clientX: 50, clientY: 50 });
                     document.getElementById('carousel').dispatchEvent(e);
                     return [e.defaultPrevented, window.pageSawDragstart === true]; })()
            """)
        checkEqual(carousel.value as? [Bool], [false, false], "취소되지 않고 페이지 처리기도 불리지 않음")
        check(waitUntil(timeout: 5) { engine.takeDraggedImage()?.src.hasSuffix("?carousel") == true }, "이미지를 알림")
        // 이미지가 아닌 것을 끌 때는 페이지에 맡긴다(글 끌기를 막는 페이지는 그대로 막는다).
        let text = evaluate("""
            (() => { window.pageSawDragstart = false;
                     const e = new DragEvent('dragstart', { bubbles: true, cancelable: true, clientX: 10, clientY: 320 });
                     document.getElementById('text').dispatchEvent(e);
                     return [e.defaultPrevented, window.pageSawDragstart === true]; })()
            """)
        checkEqual(text.value as? [Bool], [true, true], "이미지가 아니면 페이지 처리기가 그대로 동작")
        check(waitUntil(timeout: 5) { engine.takeDraggedImage() == nil }, "이미지가 아니면 알린 이미지를 지움")
    }

    runTest("끌 수 없게 해 둔 이미지는 누르는 동안만 끌 수 있게 바꿨다가 되돌린다") {
        let state = "(() => { const i = document.getElementById('locked'); return [i.getAttribute('draggable'), getComputedStyle(i).webkitUserDrag]; })()"
        checkEqual(evaluate(state).value as? [String], ["false", "none"], "처음엔 끌 수 없음")
        _ = evaluate("document.getElementById('locked').dispatchEvent(new MouseEvent('mousedown', { bubbles: true, button: 0, clientX: 50, clientY: 150 }))")
        checkEqual(evaluate(state).value as? [String], ["true", "element"], "누르는 동안 끌 수 있음")
        _ = evaluate("document.getElementById('locked').dispatchEvent(new MouseEvent('mouseup', { bubbles: true, button: 0 }))")
        checkEqual(evaluate(state).value as? [String], ["false", "none"], "떼면 원래대로")
        _ = evaluate("document.getElementById('locked').dispatchEvent(new MouseEvent('mousedown', { bubbles: true, button: 2, clientX: 50, clientY: 150 }))")
        checkEqual(evaluate(state).value as? [String], ["false", "none"], "오른쪽 버튼에는 바꾸지 않음")
    }

    runTest("덮개에 가린 이미지도 찾아서 알리고 끌 수 있게 한다") {
        engine.clearDraggedImage()
        // 덮개(#cover)가 이미지 위를 덮고 있다 — 이벤트 대상은 덮개이고 이미지는 그 아래 형제다.
        _ = evaluate("document.getElementById('cover').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, clientX: 50, clientY: 250 }))")
        check(waitUntil(timeout: 5) { engine.lastContextImage?.src.hasSuffix("?covered") == true }, "우클릭: 아래 깔린 이미지")
        _ = evaluate("document.getElementById('cover').dispatchEvent(new MouseEvent('mousedown', { bubbles: true, button: 0, clientX: 50, clientY: 250 }))")
        checkEqual(evaluate("document.getElementById('cover').getAttribute('draggable')").value as? String, "true", "누르는 동안 덮개를 끌 수 있음")
        _ = evaluate("document.getElementById('cover').dispatchEvent(new DragEvent('dragstart', { bubbles: true, cancelable: true, clientX: 50, clientY: 250 }))")
        check(waitUntil(timeout: 5) { engine.takeDraggedImage()?.src.hasSuffix("?covered") == true }, "끌기: 아래 깔린 이미지")
        _ = evaluate("document.getElementById('cover').dispatchEvent(new DragEvent('dragend', { bubbles: true }))")
        check((evaluate("document.getElementById('cover').getAttribute('draggable')").value as? String) == nil, "끝나면 덮개를 원래대로")
    }

    runTest("cancelAll은 진행 중 저장을 멈추고 이번 저장이 만든 파일만 지운다") {
        results.removeAll(); failures.removeAll()
        let cancelFolder = root.appendingPathComponent("취소 폴더")
        try! FileManager.default.createDirectory(at: cancelFolder, withIntermediateDirectories: true)
        let existing = Data("원래 파일".utf8)
        try! existing.write(to: cancelFolder.appendingPathComponent("slowsave.png"))
        // 앞쪽 절반은 바로, 나머지는 3초 뒤에 온다. 그 사이에 파일이 쓰이는 중이다.
        server.delayBody(forPath: "/slowsave.png", by: 3, leadingBytes: 128 * 1024)
        saver.save(report(src: "/slowsave.png"), to: cancelFolder)
        let partial = cancelFolder.appendingPathComponent("slowsave 2.png")
        check(waitUntil(timeout: 5) { ((try? FileManager.default.attributesOfItem(atPath: partial.path)[.size]) as? Int ?? 0) > 0 },
              "쓰는 중인 파일")
        saver.cancelAll()
        _ = waitUntil(timeout: 4) { false }
        checkEqual((try? FileManager.default.contentsOfDirectory(atPath: cancelFolder.path)) ?? [], ["slowsave.png"], "남은 파일은 원래 것뿐")
        checkEqual(try? Data(contentsOf: cancelFolder.appendingPathComponent("slowsave.png")), existing, "원래 파일 그대로")
        checkEqual(results.count, 1, "결과 한 번")
    }

    // MARK: 탭

    let blankURL = server.baseURL.appendingPathComponent("blank.html")
    func tabView(_ id: Int) -> WKWebView? { engine.webView(forTab: id) }
    func tabInfo(_ id: Int) -> WebTabInfo? { engine.tabs.first { $0.id == id } }
    func loaded(_ id: Int, _ name: String) -> Bool {
        waitUntil(timeout: 10) { tabView(id).map { !$0.isLoading && $0.url?.lastPathComponent == name } ?? false }
    }
    /// 다른 탭을 모두 닫고 고른 탭 하나만 남긴다.
    func closeOtherTabs() {
        for tab in engine.tabs where tab.id != engine.selectedTabID { engine.closeTab(tab.id) }
    }

    runTest("탭을 열고 고르고 닫는다") {
        closeOtherTabs()
        guard let first = engine.selectedTabID else { check(false, "고른 탭"); return }
        checkEqual(engine.tabs.count, 1, "탭 하나")
        var tabChanges = 0
        engine.onTabsChange = { tabChanges += 1 }
        defer { engine.onTabsChange = nil }
        let second = engine.openTab(url: blankURL, select: true)!
        checkEqual(engine.tabs.map(\.id), [first, second], "끝에 더함")
        checkEqual(engine.selectedTabID, second, "앞에서 열면 고름")
        check(waitUntil(timeout: 10) { !engine.isLoading && engine.currentURL == blankURL }, "고른 탭의 주소")
        let third = engine.openTab(url: nil, select: false)!
        checkEqual(engine.selectedTabID, second, "뒤에서 열면 고른 탭 유지")
        checkEqual(tabInfo(third)?.title, "새 탭", "빈 탭 제목")
        checkEqual(tabInfo(third)?.address, "", "빈 탭 주소")
        check(tabChanges > 0, "탭 변화 알림")
        let shown = descendants(engine.containerView, of: WKWebView.self)
        check(shown.count == 1 && shown.first === engine.webView, "고른 탭의 웹 뷰만 보인다: \(shown.count)")
        engine.selectTab(first)
        checkEqual(engine.selectedTabID, first, "고르기")
        check(descendants(engine.containerView, of: WKWebView.self).first === tabView(first), "고른 탭으로 바뀜")
        engine.selectTab(second)
        engine.closeTab(second)
        checkEqual(engine.selectedTabID, third, "고른 탭을 닫으면 그 자리의 다음 탭")
        engine.closeTab(third)
        checkEqual(engine.selectedTabID, first, "다음이 없으면 앞 탭")
        engine.closeTab(first)
        checkEqual(engine.tabs.count, 1, "마지막 탭을 닫으면 빈 탭 하나")
        check(engine.selectedTabID != nil && engine.selectedTabID != first, "새 빈 탭을 고름")
        check(engine.currentURL == nil, "빈 탭")
        checkEqual(engine.tabs.first?.title, "새 탭", "빈 탭 제목")
    }

    runTest("탭마다 주소와 뒤로 기록이 따로다") {
        guard let a = engine.selectedTabID else { check(false, "고른 탭"); return }
        check(loadPage("blank.html") && loadPage("page.html"), "두 페이지")
        check(engine.canGoBack, "A는 뒤로 있음")
        let b = engine.openTab(url: blankURL, select: true)!
        check(loaded(b, "blank.html"), "B 불러옴")
        check(!engine.canGoBack, "B는 뒤로 없음")
        engine.selectTab(a)
        check(engine.canGoBack, "A로 돌아와도 뒤로 있음")
        checkEqual(engine.currentURL?.lastPathComponent, "page.html", "A 주소 그대로")
        checkEqual(tabInfo(b)?.address, blankURL.absoluteString, "B 주소")
        checkEqual(tabInfo(a)?.title, server.baseURL.host, "제목 없는 페이지는 호스트")
        engine.closeTab(b)
    }

    runTest("새 창 링크는 앞의 새 탭으로, ⌘클릭은 뒤의 새 탭으로 연다") {
        closeOtherTabs()
        check(loadPage("links.html"), "링크 페이지")
        _ = waitUntil(timeout: 0.3) { false }
        guard let opener = engine.selectedTabID else { check(false, "고른 탭"); return }
        let extra = engine.openTab(url: nil, select: false)!
        click(engine.webView, x: 50, y: 50)
        check(waitUntil(timeout: 5) { engine.tabs.count == 3 }, "새 탭")
        guard let front = engine.selectedTabID, front != opener else { check(false, "새 탭을 고름"); return }
        checkEqual(engine.tabs.map(\.id), [opener, front, extra], "연 탭 바로 뒤")
        check(waitUntil(timeout: 10) { !engine.isLoading && engine.currentURL?.lastPathComponent == "page.html" }, "새 탭에서 불러옴")
        checkEqual(tabView(opener)?.url?.lastPathComponent, "links.html", "연 탭은 그대로")
        engine.selectTab(opener)
        _ = waitUntil(timeout: 0.3) { false }
        click(engine.webView, x: 50, y: 50, modifiers: .command)
        check(waitUntil(timeout: 5) { engine.tabs.count == 4 }, "⌘클릭도 새 탭")
        checkEqual(engine.selectedTabID, opener, "⌘클릭은 뒤에서")
        guard let back = engine.tabs.map(\.id).first(where: { ![opener, front, extra].contains($0) }) else { check(false, "뒤 탭"); return }
        check(loaded(back, "page.html"), "뒤 탭도 불러옴")
        engine.closeTab(front); engine.closeTab(back); engine.closeTab(extra)
    }

    runTest("window.open 창은 새 탭이고 opener가 살아 있으며 window.close로 닫힌다") {
        closeOtherTabs()
        check(loadPage("links.html"), "링크 페이지")
        _ = waitUntil(timeout: 0.3) { false }
        guard let opener = engine.selectedTabID else { check(false, "고른 탭"); return }
        let extra = engine.openTab(url: nil, select: false)!
        click(engine.webView, x: 50, y: 150)
        check(waitUntil(timeout: 5) { engine.tabs.count == 3 }, "새 탭")
        guard let popup = engine.selectedTabID, popup != opener else { check(false, "새 탭을 고름"); return }
        check(loaded(popup, "popup.html"), "팝업 불러옴")
        checkEqual(evaluate("window.opener !== null && window.opener.location.pathname").value as? String, "/links.html", "opener 유지")
        check(engine.isDragSource(engine.webView), "새 탭도 드래그 출발지")
        _ = evaluate("window.close()")
        check(waitUntil(timeout: 5) { tabInfo(popup) == nil }, "window.close로 탭 닫힘")
        checkEqual(engine.selectedTabID, opener, "연 탭으로 돌아온다")
        engine.closeTab(extra)
    }

    runTest("http·https가 아닌 주소의 새 창은 거절하고 알린다") {
        closeOtherTabs()
        check(loadPage("links.html"), "링크 페이지")
        _ = waitUntil(timeout: 0.3) { false }
        var notices: [String] = []
        engine.onNotice = { notices.append($0) }
        defer { engine.onNotice = nil }
        click(engine.webView, x: 50, y: 250)
        check(waitUntil(timeout: 5) { !notices.isEmpty }, "알림")
        _ = waitUntil(timeout: 0.5) { false }
        checkEqual(notices, ["지원하지 않는 주소의 팝업을 차단했습니다."], "한 번 알림")
        checkEqual(engine.tabs.count, 1, "탭 수 그대로")
    }

    runTest("뒤에 있는 탭의 대화창은 띄우지 않고, 홍수 계수는 탭마다 따로다") {
        closeOtherTabs()
        var shown = 0
        engine.dialogPresenter = { _, _ in shown += 1; return .alertFirstButtonReturn }
        engine.isPresented = true
        defer { engine.isPresented = false }
        check(loadPage("blank.html"), "페이지")
        let back = engine.openTab(url: blankURL, select: false)!
        check(loaded(back, "blank.html"), "뒤 탭")
        guard let backView = tabView(back) else { check(false, "뒤 탭 웹 뷰"); return }
        let answer = evaluate("confirm('뒤')", in: backView)
        check(answer.finished && (answer.value as? Bool) == false, "뒤 탭의 confirm은 false: \(answer)")
        checkEqual(shown, 0, "뒤 탭은 띄우지 않음")
        checkEqual(evaluate("[0, 1, 2].map(i => confirm('앞 ' + i))").value as? [Bool], [true, true, true], "고른 탭은 띄움")
        checkEqual(shown, 3, "세 번 표시")
        engine.selectTab(back)
        checkEqual(evaluate("[0, 1, 2].map(i => confirm('뒤였던 ' + i))").value as? [Bool], [true, true, true], "다른 탭은 따로 센다")
        checkEqual(shown, 6, "여섯 번 표시")
        check(window.attachedSheet == nil, "실제 시트 없음")
        closeOtherTabs()
    }

    runTest("뒤에 있는 탭의 일반 내려받기는 저장 창 없이 거절하고 알린다") {
        closeOtherTabs()
        engine.isPresented = true
        var notices: [String] = []
        engine.onNotice = { notices.append($0) }
        defer { engine.isPresented = false; engine.onNotice = nil }
        let back = engine.openTab(url: blankURL, select: false)!
        check(loaded(back, "blank.html"), "뒤 탭")
        tabView(back)?.evaluateJavaScript("location.href = '/file.bin'")
        check(waitUntil(timeout: 10) { !notices.isEmpty }, "알림")
        _ = waitUntil(timeout: 0.5) { false }
        check(window.attachedSheet == nil && window.sheets.isEmpty, "저장 창 없음")
        dismissSheets()
        checkEqual(notices, ["뒤에 있는 탭의 내려받기를 취소했습니다."], "한 번 알림")
        engine.closeTab(back)
    }

    runTest("뒤에 있는 탭은 소리를 멈추고 고르면 다시 낸다") {
        closeOtherTabs()
        engine.isPresented = true
        check(loadPage("media.html"), "페이지")
        guard let a = engine.selectedTabID, let view = tabView(a) else { check(false, "고른 탭"); return }
        var result = mediaState(becomes: .playing, in: view)
        check(result.0, "고른 탭은 재생: \(result.1)")
        let b = engine.openTab(url: blankURL, select: true)!
        result = mediaState(becomes: .suspended, in: view)
        check(result.0, "뒤로 가면 멈춤: \(result.1)")
        engine.selectTab(a)
        result = mediaState(becomes: .playing, in: view)
        check(result.0, "다시 고르면 재생: \(result.1)")
        engine.isPresented = false
        result = mediaState(becomes: .suspended, in: view)
        check(result.0, "접힌 패널의 고른 탭도 멈춤: \(result.1)")
        engine.closeTab(b)
        check(loadPage("blank.html"), "소리 없는 페이지로")
    }

    runTest("이미지 알림은 고른 탭의 것만 받고, 드래그 출발지는 모든 탭의 웹 뷰다") {
        closeOtherTabs()
        engine.clearDraggedImage()
        check(loadPage("page.html"), "페이지")
        guard let a = engine.selectedTabID, let view = tabView(a) else { check(false, "고른 탭"); return }
        view.evaluateJavaScript("document.getElementById('plain').dispatchEvent(new MouseEvent('contextmenu', {bubbles: true}))")
        check(waitUntil(timeout: 5) { engine.lastContextImage == nil }, "고른 탭의 이미지 아닌 우클릭")
        let b = engine.openTab(url: blankURL, select: true)!
        check(loaded(b, "blank.html"), "앞 탭")
        check(view.window == nil, "뒤 탭의 웹 뷰는 창에서 떼어 둔다")
        // 뒤 탭은 보이지 않아 손으로 누르거나 끌 수 없다. 스크립트가 보낸 알림이 앞 탭의 값을 덮지 않는다.
        view.evaluateJavaScript("document.getElementById('a').dispatchEvent(new MouseEvent('contextmenu', {bubbles: true}))")
        view.evaluateJavaScript("document.getElementById('a').dispatchEvent(new DragEvent('dragstart', {bubbles: true}))")
        check(!waitUntil(timeout: 1) { engine.lastContextImage != nil || engine.takeDraggedImage() != nil }, "뒤 탭의 알림은 무시")
        check(engine.isDragSource(view), "뒤 탭의 웹 뷰도 출발지")
        engine.selectTab(a)
        view.evaluateJavaScript("document.getElementById('a').dispatchEvent(new DragEvent('dragstart', {bubbles: true}))")
        check(waitUntil(timeout: 5) { engine.takeDraggedImage() != nil }, "고른 탭의 드래그 알림")
        engine.closeTab(b)
    }

    runTest("이미지 저장을 시작하고 그 탭을 닫아도 파일이 생긴다") {
        closeOtherTabs()
        results.removeAll(); failures.removeAll()
        let closeFolder = root.appendingPathComponent("탭 닫기 폴더")
        try! FileManager.default.createDirectory(at: closeFolder, withIntermediateDirectories: true)
        // 테스트 실행기는 앱의 이벤트 고리처럼 자동 해제 풀을 비우지 않으므로 탭의 수명을 풀 안에 가둔다.
        weak var closedView: WKWebView?
        var tab = 0
        autoreleasepool {
            tab = engine.openTab(url: pageURL, select: true)!
            check(loaded(tab, "page.html"), "저장할 탭")
            server.delayBody(forPath: "/slowtab.png", by: 1.5)
            saver.save(report(src: "/slowtab.png"), to: closeFolder)
            _ = waitUntil(timeout: 0.5) { false }
            closedView = tabView(tab)
            engine.closeTab(tab)
        }
        check(tabInfo(tab) == nil, "탭 닫힘")
        check(waitUntil(timeout: 1) { closedView == nil }, "닫힌 탭의 웹 뷰가 풀림")
        checkEqual(results.count, 0, "웹 뷰가 풀린 때는 아직 받는 중")
        check(waitUntil(timeout: 10) { results.count == 1 }, "완료")
        if case .success(let url)? = lastResult {
            check(NSImage(contentsOf: url) != nil, "이미지 파일")
        } else { check(false, "성공 결과: \(String(describing: lastResult))") }
        checkEqual(server.headers(forPath: "/slowtab.png")?["Referer"], pageURL.absoluteString, "Referer")
    }

    runTest("한 번 눌러 창을 여럿 열어도 1초에 새 탭 둘까지만 열고 한 번 알린다") {
        closeOtherTabs()
        check(loadPage("burst.html"), "페이지")
        _ = waitUntil(timeout: 0.3) { false }
        guard let opener = engine.selectedTabID else { check(false, "고른 탭"); return }
        var notices: [String] = []
        engine.onNotice = { notices.append($0) }
        defer { engine.onNotice = nil }
        click(engine.webView, x: 50, y: 50)
        _ = waitUntil(timeout: 1) { false }
        checkEqual(engine.tabs.count, 3, "새 탭은 둘")
        checkEqual(notices, ["이 페이지가 여는 새 탭을 더 열지 않습니다."], "한 번 알림")
        _ = waitUntil(timeout: 1.1) { false }
        engine.selectTab(opener)
        _ = waitUntil(timeout: 0.3) { false }
        click(engine.webView, x: 50, y: 50)
        check(waitUntil(timeout: 3) { engine.tabs.count == 5 }, "1초 뒤에는 다시 연다: \(engine.tabs.count)")
        engine.selectTab(opener)
        closeOtherTabs()
    }

    runTest("탭은 서른 개까지만 연다") {
        closeOtherTabs()
        check(loadPage("links.html"), "링크 페이지")
        _ = waitUntil(timeout: 0.3) { false }
        var notices: [String] = []
        engine.onNotice = { notices.append($0) }
        defer { engine.onNotice = nil }
        for _ in 0..<29 { check(engine.openTab(url: nil, select: false) != nil, "서른까지") }
        checkEqual(engine.tabs.count, 30, "서른 탭")
        check(engine.openTab(url: nil, select: false) == nil, "서른하나째는 거절")
        checkEqual(notices, ["탭이 너무 많아 새 탭을 열지 않습니다."], "알림")
        click(engine.webView, x: 50, y: 50)
        _ = waitUntil(timeout: 1) { false }
        checkEqual(engine.tabs.count, 30, "새 창도 거절")
        checkEqual(notices.count, 2, "새 창도 알림")
        closeOtherTabs()
    }

    runTest("✕로 닫은 탭은 연 탭이 아니라 그 자리의 다음 탭으로 간다") {
        closeOtherTabs()
        check(loadPage("links.html"), "링크 페이지")
        _ = waitUntil(timeout: 0.3) { false }
        guard let opener = engine.selectedTabID else { check(false, "고른 탭"); return }
        let extra = engine.openTab(url: nil, select: false)!
        click(engine.webView, x: 50, y: 50)
        check(waitUntil(timeout: 5) { engine.tabs.count == 3 }, "새 탭")
        guard let front = engine.selectedTabID, front != opener else { check(false, "새 탭을 고름"); return }
        checkEqual(engine.tabs.map(\.id), [opener, front, extra], "순서")
        engine.closeTab(front)
        checkEqual(engine.selectedTabID, extra, "다음 탭")
        closeOtherTabs()
    }

    runTest("보통 링크를 ⌘클릭·가운데 클릭하면 뒤의 새 탭으로 연다") {
        closeOtherTabs()
        check(loadPage("links.html"), "링크 페이지")
        _ = waitUntil(timeout: 0.3) { false }
        guard let opener = engine.selectedTabID else { check(false, "고른 탭"); return }
        click(engine.webView, x: 50, y: 350, modifiers: .command)
        check(waitUntil(timeout: 5) { engine.tabs.count == 2 }, "⌘클릭은 새 탭")
        checkEqual(engine.selectedTabID, opener, "뒤에서")
        if let back = engine.tabs.last?.id { check(loaded(back, "page.html"), "새 탭에서 불러옴") }
        _ = waitUntil(timeout: 0.5) { false }
        checkEqual(engine.currentURL?.lastPathComponent, "links.html", "누른 탭은 그대로")
        _ = waitUntil(timeout: 1.1) { false }
        click(engine.webView, x: 50, y: 350, middle: true)
        check(waitUntil(timeout: 5) { engine.tabs.count == 3 }, "가운데 클릭도 새 탭")
        checkEqual(engine.selectedTabID, opener, "가운데 클릭도 뒤에서")
        checkEqual(engine.currentURL?.lastPathComponent, "links.html", "누른 탭은 그대로")
        click(engine.webView, x: 50, y: 350)
        check(waitUntil(timeout: 10) { !engine.isLoading && engine.currentURL?.lastPathComponent == "page.html" }, "그냥 누르면 그 탭에서")
        checkEqual(engine.tabs.count, 3, "새 탭 없음")
        closeOtherTabs()
    }

    runTest("⌘로 뒤에 연 영상 탭은 고를 때까지 소리를 내지 않는다") {
        closeOtherTabs()
        engine.isPresented = true
        defer { engine.isPresented = false }
        check(loadPage("medialink.html"), "페이지")
        _ = waitUntil(timeout: 0.3) { false }
        click(engine.webView, x: 50, y: 50, modifiers: .command)
        check(waitUntil(timeout: 5) { engine.tabs.count == 2 }, "뒤 탭")
        guard let back = engine.tabs.last?.id, let view = tabView(back) else { check(false, "뒤 탭 웹 뷰"); return }
        check(loaded(back, "media.html"), "영상 불러옴")
        var result = mediaState(becomes: .suspended, in: view)
        check(result.0, "뒤에 있는 동안 멈춤: \(result.1)")
        engine.selectTab(back)
        result = mediaState(becomes: .playing, in: view)
        check(result.0, "고르면 재생: \(result.1)")
        closeOtherTabs()
        check(loadPage("blank.html"), "소리 없는 페이지로")
    }

    runTest("뒤에 있는 탭의 실패 알림은 상태 줄에 내지 않는다") {
        closeOtherTabs()
        check(loadPage("blank.html"), "페이지")
        var notices: [String] = []
        engine.onNotice = { notices.append($0) }
        defer { engine.onNotice = nil }
        let refused = URL(string: "http://127.0.0.1:9/")!
        let back = engine.openTab(url: refused, select: false)!
        check(waitUntil(timeout: 10) { tabView(back)?.isLoading == false && tabInfo(back) != nil }, "뒤 탭 끝남")
        _ = waitUntil(timeout: 1) { false }
        checkEqual(notices, [], "뒤 탭 실패는 알리지 않음")
        engine.selectTab(back)
        engine.load(refused)
        check(waitUntil(timeout: 10) { !notices.isEmpty }, "고른 탭 실패는 알림")
        closeOtherTabs()
    }

    runTest("이상한 주소·번호로 복원해도 탭이 맞게 선다") {
        engine.restoreTabs(addresses: ["아무 글", "ftp://example.com/x", "", pageURL.absoluteString], selectedIndex: -3)
        checkEqual(engine.tabs.count, 4, "탭 넷")
        checkEqual(engine.selectedTabIndex, 0, "음수는 첫 탭")
        checkEqual(engine.tabAddresses, ["", "", "", pageURL.absoluteString], "http가 아니면 빈 탭")
        checkEqual(engine.tabs.map(\.title), ["새 탭", "새 탭", "새 탭", server.baseURL.host ?? "?"], "제목")
        engine.restoreTabs(addresses: [blankURL.absoluteString, pageURL.absoluteString], selectedIndex: 99)
        checkEqual(engine.selectedTabIndex, 1, "넘치면 끝 탭")
        check(waitUntil(timeout: 10) { !engine.isLoading && engine.currentURL == pageURL }, "고른 탭 불러옴")
        engine.restoreTabs(addresses: [], selectedIndex: 0)
        checkEqual(engine.tabs.count, 1, "없으면 빈 탭 하나")
    }

    runTest("닫힌 탭의 웹 뷰가 풀린다") {
        weak var released: WKWebView?
        autoreleasepool {
            let tab = engine.openTab(url: blankURL, select: true)!
            _ = loaded(tab, "blank.html")
            released = tabView(tab)
            engine.closeTab(tab)
        }
        check(waitUntil(timeout: 5) { released == nil }, "웹 뷰 해제")
    }
}

/// 1초짜리 무음 WAV(8kHz, 8비트 모노).
private func silentWAV() -> Data {
    let samples = 8000
    var data = Data()
    func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + samples))
    data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
    append(UInt32(8000)); append(UInt32(8000)); append(UInt16(1)); append(UInt16(8))
    data.append(contentsOf: Array("data".utf8)); append(UInt32(samples))
    data.append(Data(repeating: 0x80, count: samples))
    return data
}
