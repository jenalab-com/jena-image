# 웹 패널 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 툴바의 웹 버튼으로 오른쪽 분할 칸에 한 페이지 브라우저를 열고, 웹 이미지를 우클릭·끌어다 놓기로 폴더에 저장한다.

**Architecture:** jena-web의 `WebKitBrowserRuntime`에서 탐색·대화창·내려받기·팝업 처리를 가져와 `WKWebView` 하나를 감싸는 `WebPageEngine`으로 줄인다. 순수 로직(주소 해석·저장할 주소 고르기·파일 이름)은 UI 없는 파일로 떼어 `make test`로 검증하고, 패널·저장·드롭은 `MainWindowController+Web.swift`가 AI 패널과 같은 분할 칸 방식으로 잇는다.

**Tech Stack:** Swift · AppKit · WebKit(`WKWebView`, `WKDownload`) · `swiftc` 단일 모듈 빌드(`Makefile`) · 자체 테스트 틀(`runTest`·`check`·`checkEqual`·`waitUntil`, `Tests/TestSupport.swift`)

**Spec:** `docs/web-panel-design.md` — 실행자는 이 계획과 함께 읽는다.

## Global Constraints

- macOS 14 이상(`Info.plist`의 `LSMinimumSystemVersion`). 추가 의존성은 `-framework WebKit`뿐.
- 모든 소스가 한 모듈로 컴파일된다. 새 타입은 `Web` 접두를 붙인다(`AppSettings`·`BrowserViewController`·북마크 이름이 이미 있다).
- jena-web 저장소(`../jena-web`)는 읽기만 한다. 고치지 않는다.
- 화면 문자열은 한국어 고정(이웃 화면과 같음). 코드 식별자·주석 관례는 기존 파일을 따른다.
- 폭: 패널 최소 360 / 기본 480 / 최대 1000. 창 최소 폭: 패널 없음 700 / AI 940 / 웹 980.
- AI 패널과 웹 패널은 한 번에 하나만 펼친다. 접힌 쪽 상태는 유지한다.
- 저장은 `http`·`https`·`data:`만. 기존 파일을 덮어쓰지 않는다. 이미지가 아닌 결과는 방금 만든 그 파일만 지운다.
- 저장 폴더는 사용자가 고른 시점(메뉴 클릭·드롭)에 고정한다.
- **커밋하지 않는다.** 작업 트리에 11-17 앱 업데이트 작업이 미커밋으로 있다. 커밋은 작성자가 요청할 때만 한다.
- 각 Task 끝에 `make build`, `make test`, `make test-ui`가 모두 통과해야 한다.

## Review Focus

테스트로 고정할 실패 양상(각 줄 끝이 맡는 Task).

1. 서버가 제안한 파일 이름에 경로가 들어 있다(`../../x.png`, `a/b.png`) → 폴더 밖에 쓰지 않고 마지막 조각만 쓴다. (Task 1)
2. 이미지 주소가 HTML·404를 돌려준다 → 폴더에 파일이 남지 않고 실패로 알린다. (Task 2)
3. 같은 주소를 연달아 두 번 저장한다 → 두 파일이 서로 다른 이름으로 남는다. (Task 2)
4. 저장 도중 대상 폴더가 사라졌다 → 실패로 알리고 죽지 않는다. (Task 2)
5. 내려받는 동안 패널을 접거나 다른 폴더로 옮긴다 → 처음 고른 폴더에 끝까지 저장된다. (Task 4)

---

### Task 1: 순수 로직 — 주소 해석, 저장할 주소, 파일 이름

**Files:**
- Create: `Sources/web/WebAddressResolver.swift`, `Sources/web/WebImageCandidate.swift`, `Sources/services/UniqueFileName.swift`
- Modify: `Sources/app/MainWindowController+FileOperations.swift:258-269`(`generateUniqueName`이 `UniqueFileName.make`를 부르게), `Makefile`(`TEST_SOURCES`에 위 세 파일), `Tests/main.swift`(`runWebPanelLogicTests()` 호출)
- Test: `Tests/WebPanelLogicTests.swift`

**Interfaces — Produces:**

```swift
enum WebSearchProvider: String, CaseIterable { case google, bing, naver
    var displayName: String }            // "Google" · "Bing" · "네이버"
enum WebSearchMode: String, CaseIterable { case web, images }
enum WebAddressError: LocalizedError, Equatable { case emptyInput, invalidAddress, unsupportedScheme }
enum WebAddressResolver {
    static func resolve(_ input: String, provider: WebSearchProvider, mode: WebSearchMode) throws -> URL
}
struct WebImageReport: Equatable {
    let currentSrc: String, src: String, srcset: String, pageURL: String
    init(currentSrc: String, src: String, srcset: String, pageURL: String)
    init?(message: Any)                  // 스크립트가 보낸 [String: Any]. "image" 키가 없으면 nil
}
enum WebImageCandidate {
    static let imageExtensions: Set<String>   // ImageFormat.allCases의 fileExtensions 합
    static func bestURL(for report: WebImageReport) -> URL?
    static func fileName(suggested: String?, url: URL, mimeType: String?, now: Date) -> String
    static func decodeDataURL(_ url: URL) -> (data: Data, mimeType: String)?
}
enum UniqueFileName {
    /// 이름이 비어 있으면 그대로, 겹치면 "이름 2.ext", "이름 3.ext"…
    static func make(for name: String, in folder: URL, exists: (URL) -> Bool) -> String
}
```

검색 주소(jena-web `Resources/search-providers.json`과 같은 값): Google `https://www.google.com/search` · 이미지 `?udm=2`, Bing `https://www.bing.com/search` · `https://www.bing.com/images/search`, 네이버 `https://search.naver.com/search.naver` · 이미지 `?where=image`. 검색어 키는 네이버만 `query`, 나머지는 `q`.

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `Tests/WebPanelLogicTests.swift`의 `func runWebPanelLogicTests()`

```swift
runTest("주소창 입력을 주소와 검색으로 가른다") {
    let r = { try? WebAddressResolver.resolve($0, provider: .google, mode: .images) }
    checkEqual(r("https://a.com/x")?.absoluteString, "https://a.com/x", "완전한 주소")
    checkEqual(r("pinterest.com")?.absoluteString, "https://pinterest.com", "점이 있으면 https")
    checkEqual(r("  노을 사진 ")?.absoluteString, "https://www.google.com/search?udm=2&q=%EB%85%B8%EC%9D%84%20%EC%82%AC%EC%A7%84", "검색")
    checkEqual(try? WebAddressResolver.resolve("고양이", provider: .naver, mode: .web).query, "query=%EA%B3%A0%EC%96%91%EC%9D%B4", "네이버 키")
    for bad in ["javascript:alert(1)", "file:///etc/passwd", "ftp://a.com", "data:text/html,x"] {
        check((try? WebAddressResolver.resolve(bad, provider: .google, mode: .web)) == nil, "거부: \(bad)")
    }
    check((try? WebAddressResolver.resolve("https://user:pw@a.com", provider: .google, mode: .web)) == nil, "계정 정보가 든 주소 거부")
    check((try? WebAddressResolver.resolve("   ", provider: .google, mode: .web)) == nil, "빈 입력")
}
runTest("저장할 이미지 주소를 고른다") {
    let page = "https://site.com/board/1"
    func best(_ c: String, _ s: String, _ set: String) -> String? {
        WebImageCandidate.bestURL(for: WebImageReport(currentSrc: c, src: s, srcset: set, pageURL: page))?.absoluteString
    }
    checkEqual(best("https://i.com/236.jpg", "https://i.com/236.jpg", "https://i.com/236.jpg 236w, /orig.jpg 1200w, https://i.com/564.jpg 564w"), "https://site.com/orig.jpg", "srcset의 가장 큰 너비, 상대 주소 풀기")
    checkEqual(best("https://i.com/a.jpg", "", "https://i.com/a.jpg 1x, https://i.com/b.jpg 2x"), "https://i.com/a.jpg", "너비 후보가 없으면 currentSrc")
    checkEqual(best("", "img/a.png", ""), "https://site.com/board/img/a.png", "src만 있을 때")
    checkEqual(best("", "", "깨진, , 값"), nil, "쓸 주소가 없으면 nil")
    checkEqual(best("blob:https://site.com/1", "", ""), nil, "blob은 저장하지 않는다")
    check(best("data:image/png;base64,AAAA", "", "") != nil, "data는 허용")
}
runTest("파일 이름을 정한다") {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let u = URL(string: "https://i.com/p/sunset.jpg?w=1")!
    checkEqual(WebImageCandidate.fileName(suggested: "photo.png", url: u, mimeType: "image/png", now: now), "photo.png", "서버 제안")
    checkEqual(WebImageCandidate.fileName(suggested: nil, url: u, mimeType: "image/jpeg", now: now), "sunset.jpg", "주소의 마지막 조각")
    checkEqual(WebImageCandidate.fileName(suggested: "../../evil.png", url: u, mimeType: nil, now: now), "evil.png", "경로 제거")
    checkEqual(WebImageCandidate.fileName(suggested: "a/b.png", url: u, mimeType: nil, now: now), "b.png", "경로 제거")
    checkEqual(WebImageCandidate.fileName(suggested: nil, url: URL(string: "https://i.com/img?id=7")!, mimeType: "image/webp", now: now), "img.webp", "확장자를 MIME으로")
    checkEqual(WebImageCandidate.fileName(suggested: "view.php", url: u, mimeType: "image/jpeg", now: now), "view.jpg", "이미지 확장자가 아니면 MIME으로 바꿈")
    check(WebImageCandidate.fileName(suggested: nil, url: URL(string: "https://i.com/")!, mimeType: "image/png", now: now).hasPrefix("웹 이미지 "), "이름이 없으면 날짜 이름")
    let data = WebImageCandidate.decodeDataURL(URL(string: "data:image/png;base64,iVBORw0KGgo=")!)
    checkEqual(data?.mimeType, "image/png", "data 주소 MIME"); checkEqual(data?.data.count, 8, "data 주소 본문")
}
runTest("겹치는 이름에 번호를 붙인다") {
    let folder = URL(fileURLWithPath: "/tmp/x")
    let taken: Set<String> = ["a.png", "a 2.png"]
    checkEqual(UniqueFileName.make(for: "a.png", in: folder) { taken.contains($0.lastPathComponent) }, "a 3.png", "다음 번호")
    checkEqual(UniqueFileName.make(for: "b.png", in: folder) { _ in false }, "b.png", "안 겹치면 그대로")
}
```

- [ ] **Step 2: `make test`가 컴파일 오류(타입 없음)로 실패하는지 확인한다**
- [ ] **Step 3: 세 파일을 구현한다.** `WebAddressResolver`는 `../jena-web/Sources/navigation/NavigationService.swift`·`search/SearchService.swift`의 규칙을 그대로 옮긴다. 날짜 이름 형식은 `saveClipboardImage`와 같은 `yyyy-MM-dd HH.mm.ss`(en_US_POSIX). MIME→확장자: jpeg→jpg, png, gif, webp, avif, bmp, tiff, heic, heif. `UniqueFileName.make`는 **안 겹치면 원래 이름**을 돌려준다(기존 `generateUniqueName`은 겹칠 때만 불렸다 — 겹칠 때의 결과는 같아야 한다).
- [ ] **Step 4: `generateUniqueName`을 `UniqueFileName.make(for:in:exists:)` 호출로 바꾼다**(`exists`는 `fileService.fileExists(at:)`).
- [ ] **Step 5: `make test`, `make build`, `make test-ui` 통과를 확인한다**

---

### Task 2: 엔진과 저장기

**Files:**
- Create: `Sources/web/WebPageEngine.swift`, `Sources/web/WebImageSaver.swift`, `Tests/UI/WebTestServer.swift`, `Tests/UI/WebPanelEngineTests.swift`
- Modify: `Makefile`(`FRAMEWORKS`에 `-framework WebKit`), `Info.plist`(`NSAppTransportSecurity` → `NSAllowsArbitraryLoadsInWebContent` = true), `Tests/UI/main.swift`(`runWebPanelEngineTests()` 호출)

**Interfaces — Consumes:** Task 1의 `WebImageReport`, `WebImageCandidate`, `UniqueFileName`.

**Interfaces — Produces:**

```swift
@MainActor final class WebPageEngine: NSObject {
    init(dataStore: WKWebsiteDataStore = .default())
    let containerView: NSView                 // 페이지 + 겹친 팝업(닫기 줄 포함)을 담는다
    var webView: WKWebView { get }            // 주 페이지
    var onStateChange: (() -> Void)?          // 주소·불러오기·뒤로/앞으로·팝업 변화
    var onNotice: ((String) -> Void)?         // 실패·안내 한 줄
    var saveFolderProvider: (() -> URL?)?     // 우클릭 저장 대상 폴더
    var onSaveImage: ((WebImageReport, URL) -> Void)?
    var currentURL: URL? { get }
    var isLoading: Bool { get }
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
    var hasPopup: Bool { get }
    func load(_ url: URL)
    func goBack(); func goForward(); func reloadOrStop(); func closePopup()
    private(set) var lastContextImage: WebImageReport?
    func takeDraggedImage() -> WebImageReport?        // dragstart 후 30초 안의 값. 읽어도 지우지 않는다
    func isDragSource(_ source: Any?) -> Bool         // 주 페이지·팝업의 웹 뷰 또는 그 하위 뷰
    static var imageDragTypes: [NSPasteboard.PasteboardType] { get }
    func contextMenuItems(for image: WebImageReport?) -> [NSMenuItem]   // 테스트용으로 분리
}
enum WebImageSaveError: LocalizedError { case unsupportedAddress, notAnImage, folderMissing, download(String) }
@MainActor final class WebImageSaver: NSObject {
    init(engine: WebPageEngine)
    var onFinish: ((Result<URL, WebImageSaveError>, _ folder: URL) -> Void)?
    func save(_ report: WebImageReport, to folder: URL)
}
/// 테스트 전용. 127.0.0.1의 빈 포트에서 경로별 응답을 주고 받은 요청 헤더를 기록한다.
final class WebTestServer {
    init(routes: [String: (status: Int, headers: [String: String], body: Data)]) throws
    var baseURL: URL { get }
    func headers(forPath path: String) -> [String: String]?
    func stop()
}
```

`../jena-web/Sources/browser/webkit/WebKitBrowserRuntime.swift`에서 **가져오는 것**: 설정(Safari 버전 UA, `mediaTypesRequiringUserActionForPlayback = []`, `javaScriptCanOpenWindowsAutomatically = false`, 전체 화면), `decidePolicyFor` 두 개, 실패 보고(`report`), 일반 내려받기(저장 창·같은 이름 거부), alert/confirm/prompt/열기 창. **빼는 것**: 탭(`Page` 사전)·파비콘·방문 기록·사이트 설정·개인정보·`NSApplicationDelegate`·링크 정책 스크립트. 카메라·마이크는 항상 `.deny`.

- [ ] **Step 1: 실제 값 확인(문서화되지 않은 부분).** 임시 로그를 넣은 채 `make run`으로 띄워 ① 이미지 위 우클릭 메뉴의 `NSMenuItem.identifier` 값들 ② 이미지 드래그 중 `NSPasteboard(name: .drag).types` ③ 그때의 `draggingSource` 클래스를 확인하고, 결과를 `docs/devlog/2026-11-21-web-panel.md`에 적는다. 손으로 끄는 동작을 자동화할 수 없으면 ②③은 Task 4의 드롭 대상에서 로그로 확인하도록 넘기고, `imageDragTypes`는 `[.URL, .tiff, .fileURL] + NSFilePromiseReceiver.readableDraggedTypes`로 둔다.
- [ ] **Step 2: 실패하는 테스트를 쓴다** — `Tests/UI/WebPanelEngineTests.swift`의 `@MainActor func runWebPanelEngineTests()`. 엔진은 `WKWebsiteDataStore.nonPersistent()`로 만든다. 서버 경로: `/page.html`(`<img id=a src="/a.png" srcset="/a.png 100w, /big.png 800w">` 포함), `/a.png`·`/big.png`(유효한 PNG), `/html.png`(본문 HTML, `Content-Type: text/html`), `/missing.png`(404).

```swift
runTest("페이지를 불러오면 상태가 바뀐다") {
    engine.load(server.baseURL.appendingPathComponent("page.html"))
    check(waitUntil(timeout: 10) { !engine.isLoading && engine.currentURL?.lastPathComponent == "page.html" }, "불러오기 완료")
    check(!engine.canGoBack, "첫 페이지는 뒤로 없음")
}
runTest("스크립트가 우클릭·드래그 대상 이미지를 알린다") {
    engine.webView.evaluateJavaScript("document.getElementById('a').dispatchEvent(new MouseEvent('contextmenu', {bubbles: true}))")
    check(waitUntil(timeout: 5) { engine.lastContextImage != nil }, "우클릭 알림")
    checkEqual(WebImageCandidate.bestURL(for: engine.lastContextImage!)?.lastPathComponent, "big.png", "srcset의 큰 후보")
    engine.webView.evaluateJavaScript("document.getElementById('a').dispatchEvent(new DragEvent('dragstart', {bubbles: true}))")
    check(waitUntil(timeout: 5) { engine.takeDraggedImage() != nil }, "드래그 알림")
}
runTest("우클릭 메뉴에 폴더 저장 항목이 붙는다") {
    engine.saveFolderProvider = { folder }
    let items = engine.contextMenuItems(for: report)
    checkEqual(items.first?.title, "'\(folder.lastPathComponent)'에 저장", "폴더 이름")
    check(items.first?.isEnabled == true, "활성")
    engine.saveFolderProvider = { nil }
    checkEqual(engine.contextMenuItems(for: report).first?.title, "저장할 폴더를 먼저 선택하세요", "폴더 없음 안내")
    check(engine.contextMenuItems(for: report).first?.isEnabled == false, "비활성")
    check(engine.contextMenuItems(for: nil).isEmpty, "이미지가 아니면 항목 없음")
}
runTest("이미지를 폴더에 저장하고 Referer와 이름을 지킨다") {
    saver.save(report(src: "/a.png"), to: folder)          // 결과는 onFinish로 results에 쌓는다
    check(waitUntil(timeout: 10) { results.count == 1 }, "완료")
    check(FileManager.default.fileExists(atPath: folder.appendingPathComponent("a.png").path), "파일 생성")
    checkEqual(server.headers(forPath: "/a.png")?["Referer"], server.baseURL.appendingPathComponent("page.html").absoluteString, "Referer")
    saver.save(report(src: "/a.png"), to: folder); saver.save(report(src: "/a.png"), to: folder)
    check(waitUntil(timeout: 10) { results.count == 3 }, "연달아 두 번")
    checkEqual(Set(try! FileManager.default.contentsOfDirectory(atPath: folder.path)), ["a.png", "a 2.png", "a 3.png"], "서로 다른 이름")
}
runTest("이미지가 아닌 응답은 파일을 남기지 않는다") {
    for path in ["/html.png", "/missing.png"] { saver.save(report(src: path), to: empty) }
    check(waitUntil(timeout: 10) { failures.count == 2 }, "둘 다 실패로 알림")
    check(try! FileManager.default.contentsOfDirectory(atPath: empty.path).isEmpty, "남은 파일 없음")
}
runTest("폴더가 사라졌으면 실패로 알린다") {
    saver.save(report(src: "/a.png"), to: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
    check(waitUntil(timeout: 10) { if case .failure(.folderMissing)? = lastResult { return true }; return false }, "folderMissing")
}
runTest("data 주소 이미지를 저장한다") { /* 유효한 PNG의 data: 주소 → 파일 생성, 이미지로 읽힘 */ }
```

- [ ] **Step 3: `make test-ui`가 컴파일 오류로 실패하는지 확인한다**
- [ ] **Step 4: `WebTestServer`를 구현한다**(`Network`의 `NWListener`, 요청 한 건당 연결 종료).
- [ ] **Step 5: `WebPageEngine`을 구현한다.**
  - 이미지 알림 스크립트는 전용 `WKContentWorld.world(name: "jena.image-capture")`에 `atDocumentStart`·모든 프레임으로 넣고, `add(_:contentWorld:name:)`의 핸들러 이름은 `jenaImage`. `contextmenu`·`dragstart`를 캡처 단계에서 듣고 `event.composedPath()`에서 `<img>`(없으면 대상 요소의 첫 `img`)를 찾아 `{kind, image: {currentSrc, src, srcset}, pageURL}`을 보낸다. 이미지가 없으면 `image` 없이 보내 이전 값을 지운다.
  - 우클릭: `WKWebView` 하위 클래스에서 `willOpenMenu(_:with:)`를 재정의해 `super` 호출 뒤, 메뉴가 이미지용(Step 1에서 확인한 식별자 존재)이면 `contextMenuItems(for:)`의 결과를 맨 위에 넣고 구분선을 붙인다. 항목을 누를 때 `lastContextImage`와 `saveFolderProvider`를 **그 시점에** 읽어 `onSaveImage`를 부른다.
  - 새 창: `createWebViewWith`에서 `navigationType == .linkActivated`면 주 페이지에서 그 주소를 불러오고 `nil`을 돌려준다. 그 밖이면 받은 `configuration`으로 웹 뷰를 만들어 `containerView` 위에 겹치고(위쪽 닫기 줄: "새 창" 라벨 + 닫기 버튼) 돌려준다. `webViewDidClose`·`closePopup()`으로 걷는다. http/https가 아닌 주소의 창은 거절한다.
- [ ] **Step 6: `WebImageSaver`를 구현한다.** `bestURL` → 폴더 존재 확인 → `data:`면 직접 쓰기, 아니면 `engine.webView.startDownload(using:)`(요청에 `Referer` = `report.pageURL`). `decideDestinationUsing`에서 `WebImageCandidate.fileName`과 `UniqueFileName.make`로 정한다. **동시 저장이 같은 이름을 고르지 않도록 진행 중인 대상 경로를 집합으로 들고 `exists`에 포함한다.** 완료 후 `ImageFile(url:)?.isImage == true`이고 `NSImage(contentsOf:)`가 읽히는지 확인하고, 아니면 그 파일을 지우고 `.notAnImage`. HTTP 상태가 200대가 아니면 내려받지 않는다.
- [ ] **Step 7: Referer 테스트가 실패하면** `URLSession` + `WKHTTPCookieStore.allCookies()` 방식으로 바꾼다(`save`·`onFinish` 모양은 그대로). 어느 쪽을 썼는지 devlog에 적는다.
- [ ] **Step 8: `make build`, `make test`, `make test-ui` 통과를 확인한다**

---

### Task 3: 패널 화면과 창 연결

**Files:**
- Create: `Sources/web/WebPanelViewController.swift`, `Sources/app/MainWindowController+Web.swift`, `Tests/UI/WebPanelUITests.swift`
- Modify: `Sources/app/MainWindowController.swift`(`ToolbarID.web = "webBrowser"`, 상태 변수), `Sources/app/MainWindowController+Delegates.swift`(툴바 기본·허용 목록의 `ToolbarID.ai` 바로 뒤에 `ToolbarID.web`, 항목 생성), `Sources/app/MainWindowController+AI.swift`(오른쪽 패널 공통 처리 사용), `Sources/app/MainMenu.swift`(보기 메뉴 "웹 브라우저", `showWebMode(_:)`), `Sources/services/AppSettings.swift`, `Tests/UI/main.swift`

**Interfaces — Consumes:** `WebPageEngine`, `WebAddressResolver`, `WebSearchProvider`, `WebSearchMode`.

**Interfaces — Produces:**

```swift
// AppSettings
var webSearchProvider: WebSearchProvider   // 키 "webSearchProvider", 기본 .google
var webSearchMode: WebSearchMode           // 키 "webSearchMode", 기본 .images
var webLastAddress: String                 // 키 "webLastAddress", 기본 ""

final class WebPanelViewController: NSViewController {
    static let defaultWidth: CGFloat = 480, minimumWidth: CGFloat = 360, maximumWidth: CGFloat = 1000
    init(engine: WebPageEngine, settings: AppSettings = .shared)
    let engine: WebPageEngine
    let addressField: NSTextField
    let statusLabel: NSTextField
    private(set) var backButton: NSButton!, forwardButton: NSButton!, reloadButton: NSButton!
    private(set) var optionsButton: NSButton!, closeButton: NSButton!
    var onClose: (() -> Void)?
    func submitAddress()            // addressField 해석 → engine.load, 실패는 상태 줄
    func showStatus(_ text: String) // 6초 뒤 지움. 불러오는 중이면 "불러오는 중…"
    func focusAddress()
    func loadInitialPage()          // settings.webLastAddress가 있으면 한 번만 불러온다
}

// MainWindowController
var webPanelVC: WebPanelViewController?
var webSplitItem: NSSplitViewItem?
var makeWebEngine: () -> WebPageEngine     // 기본 { WebPageEngine() } — 테스트가 비영구 저장소로 바꾼다
@objc func showWebMode(_ sender: Any?)
/// 오른쪽 패널(AI·웹) 공통: 다른 쪽을 접고, 창 최소 폭을 맞추고, 처음 열 때 나눔선 위치를 잡는다.
func setRightPanel(_ item: NSSplitViewItem, visible: Bool, minimumWindowWidth: CGFloat, defaultWidth: CGFloat, firstOpen: Bool)
```

머리줄: `‹` `›` `⟳/✕` `[주소창: placeholder "검색어 또는 주소"]` `⋯` `✕`. `AIChatViewController`의 `iconButton` 모양을 따른다. ⋯ 메뉴는 검색엔진 3개와 검색 종류 2개(선택된 것에 체크). 빈 화면 문구 "검색어나 주소를 입력하세요". 주소창은 페이지가 바뀌면 현재 주소를 보이되 편집 중(`currentEditor() != nil`)이면 덮어쓰지 않는다. 주 프레임 탐색이 끝날 때마다 http/https 주소를 `webLastAddress`에 저장한다.

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `@MainActor func runWebPanelUITests(controller: MainWindowController, server: WebTestServer)`. 시작 전에 `controller.makeWebEngine = { WebPageEngine(dataStore: .nonPersistent()) }`.

```swift
runTest("웹 버튼은 오른쪽 칸을 열고 접는다") {
    check(controller.toolbarDefaultItemIdentifiers(controller.window!.toolbar!).contains(MainWindowController.ToolbarID.web), "툴바 항목")
    controller.showWebMode(nil)
    guard let web = controller.webPanelVC else { check(false, "패널 생성"); return }
    check(controller.splitViewController.splitViewItems.last?.viewController === web, "맨 오른쪽")
    check(controller.webSplitItem?.isCollapsed == false, "펼침")
    checkEqual(controller.window?.minSize.width, 980, "창 최소 폭")
    check((controller.window?.frame.width ?? 0) >= 980, "좁으면 창을 넓힌다")
    controller.showWebMode(nil)
    check(controller.webSplitItem?.isCollapsed == true, "접힘")
    checkEqual(controller.window?.minSize.width, 700, "최소 폭 복귀")
}
runTest("AI와 웹은 한 번에 하나만 펼친다") {
    controller.showWebMode(nil); controller.showAIMode(nil)
    check(controller.webSplitItem?.isCollapsed == true && controller.aiSplitItem?.isCollapsed == false, "AI를 열면 웹이 접힘")
    checkEqual(controller.window?.minSize.width, 940, "AI 최소 폭")
    controller.showWebMode(nil)
    check(controller.aiSplitItem?.isCollapsed == true && controller.webSplitItem?.isCollapsed == false, "웹을 열면 AI가 접힘")
    check(controller.splitViewController.splitViewItems[1].viewController === controller.browserVC, "가운데 칸은 그대로")
}
runTest("뷰어로 바꿔도 웹 패널이 남는다") {
    controller.switchToMode(.viewer)
    check(controller.webSplitItem?.isCollapsed == false, "유지")
    check(controller.splitViewController.splitViewItems[1].viewController === controller.viewerVC, "가운데만 교체")
    controller.switchToMode(.browser)
}
runTest("주소창 입력으로 페이지를 열고 마지막 주소를 기억한다") {
    let web = controller.webPanelVC!
    web.addressField.stringValue = server.baseURL.appendingPathComponent("page.html").absoluteString
    web.submitAddress()
    check(waitUntil(timeout: 10) { !web.engine.isLoading && web.engine.currentURL?.lastPathComponent == "page.html" }, "불러옴")
    checkEqual(settings.webLastAddress, web.engine.currentURL?.absoluteString ?? "", "마지막 주소 저장")
    web.addressField.stringValue = "javascript:alert(1)"; web.submitAddress()
    check(!web.statusLabel.stringValue.isEmpty, "거부 사유를 상태 줄에")
    check(web.engine.currentURL?.lastPathComponent == "page.html", "페이지는 그대로")
}
runTest("닫기 버튼은 패널을 접는다") {
    controller.webPanelVC?.closeButton.performClick(nil)
    check(controller.webSplitItem?.isCollapsed == true, "접힘")
}
```

- [ ] **Step 2: `make test-ui`가 컴파일 오류로 실패하는지 확인한다**
- [ ] **Step 3: `AppSettings` 세 속성과 `WebPanelViewController`를 구현한다**
- [ ] **Step 4: `setRightPanel`과 `showWebMode`를 구현하고 `showAIMode`를 `setRightPanel`을 쓰게 고친다.** 나눔선 번호는 `splitViewItems.firstIndex(of: item)! - 1`로 구한다(지금은 `1`로 고정돼 있어 칸이 넷이면 틀린다). 처음 열 때 위치는 `splitView.bounds.width - defaultWidth`. 기존 `Tests/UI/AIImageUITests.swift`가 그대로 통과해야 한다(그 테스트의 `splitViewItems.count == 3` 검사는 AI만 열린 상태에서 돈다 — `main.swift`에서 웹 테스트를 AI 테스트 **뒤에** 부른다).
- [ ] **Step 5: 툴바 항목(`headerItem(..., label: "웹 브라우저", tip: "웹 브라우저", symbol: "globe", toggle: true, action: #selector(showWebMode(_:)))`)과 메뉴 항목을 넣는다.** 패널 상태가 바뀔 때 버튼의 `state`를 맞춘다.
- [ ] **Step 6: `make build`, `make test`, `make test-ui` 통과를 확인한다**

---

### Task 4: 저장 연결과 끌어다 놓기

**Files:**
- Modify: `Sources/app/MainWindowController+Web.swift`, `Sources/browser/BrowserViewController.swift`(파일 맨 위 컬렉션 뷰 하위 클래스의 `itemIndexPath(at:)`·드래그 처리 ~104-172, 연결부 ~1002-1008, `registerForDraggedTypes` 989), `Sources/sidebar/SidebarViewController.swift`(846, 1008-1034), `Tests/UI/WebPanelUITests.swift`

**Interfaces — Consumes:** `WebImageSaver`, `WebPageEngine.takeDraggedImage()`·`isDragSource(_:)`·`imageDragTypes`·`onSaveImage`·`saveFolderProvider`.

**Interfaces — Produces:**

```swift
// MainWindowController
var webImageSaver: WebImageSaver?
var webSaveFolderURL: URL? { get }                         // aiDestinationURL과 같은 규칙
func saveWebImage(_ report: WebImageReport, to folder: URL)
func handleWebImageDrop(from info: NSDraggingInfo, to folder: URL?) -> Bool   // folder nil = 지금 폴더

// BrowserViewController
var isWebImageDrag: ((NSDraggingInfo) -> Bool)?
var onWebImageDrop: ((NSDraggingInfo, _ folder: URL?) -> Bool)?   // 폴더 타일 위면 그 폴더, 빈 곳이면 nil
// SidebarViewController
var isWebImageDrag: ((NSDraggingInfo) -> Bool)?
var onWebImageDrop: ((NSDraggingInfo, _ folder: URL) -> Bool)?
```

- [ ] **Step 1: 실패하는 테스트를 쓴다.** 드래그는 `NSDraggingInfo`를 흉내 낸 테스트용 객체(`draggingSource`, `draggingPasteboard`, `draggingLocation`만 채움)로 넣는다.

```swift
runTest("목록의 위치 판정이 메이슨리 레이아웃에서 폴더 타일을 찾는다") {
    controller.browserVC.display(folders: [subfolder], images: [image])
    let collection = descendants(controller.browserVC.view, of: NSCollectionView.self).first!
    collection.layoutSubtreeIfNeeded()
    let frame = collection.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame
    let point = collection.convert(NSPoint(x: frame.midX, y: frame.midY), to: nil)
    check(collection.performDragOperation(FakeDrag(fileURLs: [image], location: point)), "파일을 폴더 타일에 놓으면 받는다")
    check(waitUntil { FileManager.default.fileExists(atPath: subfolder.appendingPathComponent(image.lastPathComponent).path) }, "옮겨졌다")
}
runTest("웹 이미지를 목록의 빈 곳에 놓으면 지금 폴더에 저장된다") {
    // 엔진에 dragstart 알림을 만든 뒤, 출처가 웹 뷰인 FakeDrag를 빈 곳에 놓는다
    check(waitUntil(timeout: 10) { FileManager.default.fileExists(atPath: directory.appendingPathComponent("big.png").path) }, "저장")
    check(waitUntil { controller.browserVC.selectedURLs() == [directory.appendingPathComponent("big.png")] }, "새 파일 선택")
    check(controller.webPanelVC?.statusLabel.stringValue.hasPrefix("저장했습니다: ") == true, "상태 줄")
}
runTest("웹 이미지를 폴더 타일·사이드바 폴더에 놓으면 그 폴더에 저장된다") { /* 두 경로 각각 파일 생성 확인 */ }
runTest("웹 패널이 아닌 곳에서 온 비파일 드래그는 받지 않는다") {
    checkEqual(collection.draggingEntered(FakeDrag(urlOnly: URL(string: "https://x.com/a.png")!, source: nil, location: emptyPoint)), [], "목록 거부")
    // 사이드바 validateDrop도 [] 를 돌려준다
}
runTest("실제 폴더가 없는 화면에서는 저장하지 않는다") {
    controller.showBookmarks()
    check(controller.webSaveFolderURL == nil, "저장 폴더 없음")
    check(!controller.handleWebImageDrop(from: webDrag(at: emptyPoint), to: nil), "빈 곳 드롭 거부")
    checkEqual(controller.webPanelVC?.engine.contextMenuItems(for: report).first?.isEnabled, false, "우클릭 항목 비활성")
}
runTest("내려받는 동안 폴더를 옮기거나 패널을 접어도 처음 폴더에 저장된다") {
    controller.saveWebImage(report, to: directory)   // 서버의 /slow.png는 0.5초 뒤 응답
    controller.navigateToFolder(other); controller.showWebMode(nil)
    check(waitUntil(timeout: 10) { FileManager.default.fileExists(atPath: directory.appendingPathComponent("slow.png").path) }, "처음 폴더")
    check(!FileManager.default.fileExists(atPath: other.appendingPathComponent("slow.png").path), "옮긴 폴더에는 없음")
}
runTest("뷰어로 보는 중에 저장돼도 보던 이미지가 바뀌지 않는다") { /* viewerVC.currentImageURL 불변, 상태 줄만 갱신 */ }
```

- [ ] **Step 2: `make test-ui` 실패를 확인한다**(첫 테스트는 기존 결함 때문에, 나머지는 미구현으로).
- [ ] **Step 3: `itemIndexPath(at:)`를 `indexPathForItem(at: convert(windowPoint, from: nil))`로 바꾼다.** 첫 테스트만 통과하는지 확인한다.
- [ ] **Step 4: 목록 드롭을 구현한다.** `registerForDraggedTypes([.fileURL] + WebPageEngine.imageDragTypes)`. 컬렉션 뷰의 `draggingEntered`·`draggingUpdated`·`performDragOperation`에서 웹 이미지 드래그(`isWebImageDrag`)를 먼저 가른다: 폴더 타일 위면 강조하고 `.copy`, 빈 곳이면 `.copy`, 받을 수 없으면 `[]`. 웹 드래그가 아니고 보드에 파일 주소도 없으면 `[]`. 파일 드래그의 기존 흐름은 건드리지 않는다.
- [ ] **Step 5: 사이드바 드롭을 구현한다.** `validateDrop`이 **파일 드래그이거나 웹 이미지 드래그일 때만** `FolderNode`를 받는다(웹은 `.copy`). `acceptDrop`은 웹 드래그면 `onWebImageDrop`으로 넘긴다.
- [ ] **Step 6: `MainWindowController+Web.swift`를 잇는다.** `showWebMode`의 첫 생성에서 `engine.saveFolderProvider = { webSaveFolderURL }`, `engine.onSaveImage = saveWebImage`, 저장기 `onFinish` → 상태 줄("저장했습니다: 이름" / "저장하지 못했습니다: 사유"), 사이드바 `reloadFolder(at:)`, 그리고 **목록 화면(`contentMode == .browser`, 컬렉션 화면 아님)에서 `currentFolderURL == folder`일 때만** `pendingSelectionURLs = [url]` + `refreshCurrentFolder()`. `handleWebImageDrop`은 `isDragSource(info.draggingSource)`와 `takeDraggedImage()`가 둘 다 있을 때만 `true`. `isWebImageDrag`·`onWebImageDrop`은 `setupDelegates()`에서 한 번 잇는다(패널이 아직 없으면 `false`).
- [ ] **Step 7: `make build`, `make test`, `make test-ui` 통과를 확인한다**

---

### Task 5: 실제 사이트 확인과 기록

**Files:**
- Create: `docs/devlog/2026-11-21-web-panel.md`
- Modify: `README.md`(기능 목록에 웹 패널 한 단락 — 기존 문단의 언어·형식을 따른다), `docs/web-panel-design.md`(구현 중 바뀐 결정이 있으면 반영), `~/Documents/project/source/skills/global/projects.md`의 jena-image 줄

- [ ] **Step 1: `make run`으로 띄워 직접 확인한다.** ① 웹 버튼으로 열림·접힘 ② `pinterest.com`·Google 이미지 검색이 열리고 스크롤·영상(mp4)이 된다 ③ 이미지 우클릭 → "'폴더'에 저장" → 목록에 나타나고 선택된다 ④ 이미지를 목록 빈 곳·폴더 타일·사이드바 폴더로 끌어다 놓는다 ⑤ Pinterest의 Google 로그인 팝업이 패널 안에 겹쳐 뜨고 로그인 뒤 닫힌다 ⑥ 앱을 다시 켜면 마지막 주소와 로그인이 남아 있다 ⑦ `http://` 페이지가 열린다(`NSAllowsArbitraryLoadsInWebContent`가 필요했는지 기록) ⑧ AI 패널·뷰어·파일 끌어다 옮기기가 전과 같다.
- [ ] **Step 2: 손으로만 확인할 수 있는데 하지 못한 항목은 devlog에 "작성자 확인 필요"로 남긴다.** 통과로 적지 않는다.
- [ ] **Step 3: devlog를 쓴다**(기존 `docs/devlog/*.md` 형식: 변경과 이유 · 결정과 절충 · 검증 및 발견 · 최종 결과). Task 2 Step 1의 실제 값, Referer 방식, 되살린 폴더 타일 드롭을 포함한다.
- [ ] **Step 4: 임시 로그가 남아 있지 않은지 확인하고 `make build`, `make test`, `make test-ui`를 마지막으로 돌린다**
