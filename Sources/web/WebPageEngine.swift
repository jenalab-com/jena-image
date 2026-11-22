import AppKit
import WebKit

/// 웹 패널의 탭 엔진. jena-web `WebKitBrowserRuntime`에서 설정·탐색·새 창·대화창·내려받기를 옮기고
/// 파비콘·방문 기록·사이트 설정·개인정보·앱 생명주기·링크 정책 스크립트는 뺐다.
/// 공유 설정(데이터 저장소·이미지 알림 스크립트·메시지 처리기)은 엔진 하나가 갖고, 탭(`WebTab`)은 웹 뷰와 탭별 상태를 갖는다.
/// 페이지가 연 새 창은 WebKit이 준 설정으로 만든 새 탭이다.
/// 한 페이지용 API(`currentURL`·`isLoading`·`load`·`webView` 등)는 고른 탭에 대한 것이다.
@MainActor
final class WebPageEngine: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    /// 고른 탭의 웹 뷰 하나만 담는다. 뒤에 있는 탭의 웹 뷰는 떼어 두어 클릭·드래그를 받지 않는다.
    let containerView = NSView()
    /// 고른 탭의 웹 뷰.
    var webView: WKWebView { selected.view }

    /// 고른 탭의 주소·불러오기·뒤로/앞으로 변화, 그리고 고른 탭이 바뀔 때.
    var onStateChange: (() -> Void)?
    /// 탭 목록·제목·주소·불러오기·고른 탭 변화.
    var onTabsChange: (() -> Void)?
    /// 실패·안내 한 줄.
    var onNotice: ((String) -> Void)?
    /// 우클릭 저장 대상 폴더. 실제 폴더가 없는 화면이면 nil.
    var saveFolderProvider: (() -> URL?)?
    var onSaveImage: ((WebImageReport, URL) -> Void)?

    /// 사용자가 이 패널을 보고 있는지. 창 컨트롤러가 패널을 펼치고 접을 때 맞춘다.
    /// 보이는 것은 펼친 패널의 고른 탭뿐이다. 보이지 않는 탭은 주 창에 시트(대화창·파일 선택·저장 창)를 띄우지 않고 소리를 내지 않는다.
    /// 패널 밖의 엔진은 보이지 않는 쪽으로 시작한다.
    var isPresented = false {
        didSet {
            guard isPresented != oldValue else { return }
            applyMediaSuspension()
        }
    }
    /// 페이지 대화창을 띄운다. 테스트는 실제 시트 대신 바로 답하는 것으로 바꾼다.
    var dialogPresenter: @MainActor (NSAlert, WKWebView) async -> NSApplication.ModalResponse = { alert, view in
        guard let window = view.window else { return alert.runModal() }
        return await alert.beginSheetModal(for: window)
    }

    var currentURL: URL? { selected.view.url }
    var isLoading: Bool { selected.view.isLoading }
    var canGoBack: Bool { selected.view.canGoBack }
    var canGoForward: Bool { selected.view.canGoForward }

    var tabs: [WebTabInfo] { tabList.map(\.info) }
    var selectedTabID: Int? { selected?.id }
    /// 다시 켤 때 열 탭 주소(빈 탭은 빈 문자열)와 고른 탭 번호.
    var tabAddresses: [String] { tabList.map(\.savedAddress) }
    var selectedTabIndex: Int { tabList.firstIndex { $0 === selected } ?? 0 }

    /// 페이지 스크립트가 마지막 `contextmenu`에서 알린 이미지(어느 탭이든). 이미지가 아닌 곳이면 nil.
    private(set) var lastContextImage: WebImageReport?
    private var draggedImage: (report: WebImageReport, time: Date)?

    /// WebKit이 이미지 위 우클릭 메뉴에 넣는 항목 식별자(2026-11-21 로그로 확인).
    private static let imageMenuIdentifiers: Set<String> = [
        "WKMenuItemIdentifierCopyImage", "WKMenuItemIdentifierDownloadImage", "WKMenuItemIdentifierOpenImageInNewWindow",
    ]
    private static let captureWorld = WKContentWorld.world(name: "jena.image-capture")
    private static let messageName = "jenaImage"

    private let configuration: WKWebViewConfiguration
    private var tabList: [WebTab] = []
    private var selected: WebTab!
    private var nextTabID = 0
    private var downloads: [ObjectIdentifier: WKDownload] = [:]
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]
    private static let dialogFloodLimit = 3
    private static let dialogFloodWindow: TimeInterval = 10
    /// 탭 수 상한과, 한 탭의 페이지가 1초 안에 열 수 있는 새 탭 수(한 번의 클릭이 창을 여럿 여는 페이지 막기).
    static let maximumTabs = 30
    private static let openBurstLimit = 2
    private static let openBurstWindow: TimeInterval = 1
    /// WebKit이 가운데 버튼 클릭에 주는 `WKNavigationAction.buttonNumber`. 버튼 비트(왼쪽 1, 오른쪽 2, 가운데 4)다
    /// (2026-11-22 합성 클릭으로 확인: 왼쪽 1, 가운데 4).
    private static let middleButtonNumber = 4

    /// 기본 저장소(로그인 유지). 기본 인자로 두면 `.default()`가 메인 액터 밖에서 평가돼 따로 둔다.
    convenience override init() { self.init(dataStore: .default()) }

    init(dataStore: WKWebsiteDataStore) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        // 사이트가 로그인·영상을 알려진 브라우저에만 열어 주므로 설치된 Safari에 맞춘다.
        configuration.applicationNameForUserAgent = "Version/\(Self.safariVersion()) Safari/605.1.15"
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Safari처럼 클릭으로 연 창만 앱에 온다. 스크립트가 저절로 연 창은 엔진이 버린다.
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isElementFullscreenEnabled = true
        self.configuration = configuration
        super.init()
        let controller = configuration.userContentController
        controller.addUserScript(WKUserScript(source: Self.captureScript, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false, in: Self.captureWorld))
        controller.add(WebScriptMessageProxy(engine: self), contentWorld: Self.captureWorld, name: Self.messageName)
        activate(makeTab(configuration: configuration, at: 0, openerID: nil, pendingURL: nil))
    }

    private static func safariVersion() -> String {
        let info = NSDictionary(contentsOfFile: "/Applications/Safari.app/Contents/Info.plist")
        let parts = ((info?["CFBundleShortVersionString"] as? String) ?? "26.0").split(separator: ".").prefix(2)
        return parts.joined(separator: ".")
    }

    private static func isWeb(_ url: URL) -> Bool {
        isHTTP(url) || url.absoluteString == "about:blank"
    }
    private static func isHTTP(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    // MARK: 탭

    /// 새 탭을 끝에 연다. `url`이 nil이면 빈 탭. `select`면 그 탭을 고른다.
    /// 탭이 이미 `maximumTabs`개면 열지 않고 알린 뒤 nil.
    @discardableResult
    func openTab(url: URL?, select: Bool) -> Int? {
        guard hasRoomForTab() else { return nil }
        let tab = makeTab(configuration: configuration, at: tabList.count, openerID: nil, pendingURL: nil)
        if let url { load(url, in: tab) }
        if select { activate(tab) } else { onTabsChange?() }
        return tab.id
    }

    func selectTab(_ id: Int) {
        guard let tab = tab(id), tab !== selected else { return }
        activate(tab)
    }

    /// 탭을 닫는다. 고른 탭이면 그 자리의 다음 탭(없으면 앞 탭)을 고른다. 마지막 탭을 닫으면 빈 탭 하나가 남는다.
    func closeTab(_ id: Int) { close(id, returningToOpener: false) }

    /// `returningToOpener`는 페이지가 스스로 닫을 때(`window.close()`)만 참이다 — 로그인 창이 닫히면 연 탭으로 돌아간다.
    private func close(_ id: Int, returningToOpener: Bool) {
        guard let index = tabList.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabList.remove(at: index)
        discard(tab)
        guard tab === selected else { onTabsChange?(); return }
        if tabList.isEmpty {
            activate(makeTab(configuration: configuration, at: 0, openerID: nil, pendingURL: nil))
        } else if returningToOpener, let opener = tab.openerID.flatMap(self.tab) {
            activate(opener)
        } else {
            activate(tabList[min(index, tabList.count - 1)])
        }
    }

    /// 지금 탭을 모두 닫고 주어진 주소의 탭들로 바꾼다(`maximumTabs`개까지). http/https가 아닌 주소는 빈 탭이 된다.
    /// 고른 탭만 바로 불러오고 나머지는 처음 고를 때 불러온다. 번호가 범위 밖이면 가까운 끝 탭.
    func restoreTabs(addresses: [String], selectedIndex: Int) {
        let old = tabList
        tabList = []
        for address in addresses.prefix(Self.maximumTabs) {
            let url = URL(string: address).flatMap { Self.isHTTP($0) ? $0 : nil }
            makeTab(configuration: configuration, at: tabList.count, openerID: nil, pendingURL: url)
        }
        if tabList.isEmpty { makeTab(configuration: configuration, at: 0, openerID: nil, pendingURL: nil) }
        for tab in old { discard(tab) }
        activate(tabList[max(0, min(selectedIndex, tabList.count - 1))])
    }

    func webView(forTab id: Int) -> WKWebView? { tab(id)?.view }

    private func tab(_ id: Int) -> WebTab? { tabList.first { $0.id == id } }
    private func tab(for view: WKWebView) -> WebTab? { tabList.first { $0.view === view } }

    private func hasRoomForTab() -> Bool {
        guard tabList.count < Self.maximumTabs else {
            onNotice?("탭이 너무 많아 새 탭을 열지 않습니다.")
            return false
        }
        return true
    }
    /// 페이지가 새 탭을 열어도 되는지. 한 탭은 1초 안에 둘까지 — 넘는 요청은 막고 그 묶음에 한 번만 알린다.
    private func mayOpenTab(from opener: WebTab?) -> Bool {
        guard hasRoomForTab() else { return false }
        guard let opener else { return true }
        let now = Date()
        opener.openTimes = opener.openTimes.filter { now.timeIntervalSince($0) < Self.openBurstWindow }
        if opener.openTimes.isEmpty { opener.openLimitNoticed = false }
        guard opener.openTimes.count < Self.openBurstLimit else {
            if !opener.openLimitNoticed {
                opener.openLimitNoticed = true
                onNotice?("이 페이지가 여는 새 탭을 더 열지 않습니다.")
            }
            return false
        }
        opener.openTimes.append(now)
        return true
    }
    /// 연 탭 바로 뒤, 그 탭이 먼저 연 탭들 뒤의 자리. 연 탭이 없으면 끝.
    private func insertionIndex(after opener: WebTab?) -> Int {
        guard let opener, var position = tabList.firstIndex(where: { $0 === opener }) else { return tabList.count }
        position += 1
        while position < tabList.count, tabList[position].openerID == opener.id { position += 1 }
        return position
    }
    /// 페이지에서 온 알림은 그 탭이 고른 탭일 때만 상태 줄에 낸다(뒤 탭의 실패가 앞 탭의 것처럼 보이지 않게).
    private func notice(_ text: String, from webView: WKWebView) {
        if tab(for: webView) === selected { onNotice?(text) }
    }

    @discardableResult
    private func makeTab(configuration: WKWebViewConfiguration, at index: Int, openerID: Int?, pendingURL: URL?) -> WebTab {
        nextTabID += 1
        let view = WebPageView(frame: NSRect(x: 0, y: 0, width: 480, height: 640), configuration: configuration)
        view.engine = self
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        view.autoresizingMask = [.width, .height]
        let tab = WebTab(id: nextTabID, view: view, openerID: openerID, pendingURL: pendingURL)
        let id = tab.id
        let changed: @Sendable (WKWebView, Any) -> Void = { [weak self] _, _ in
            Task { @MainActor in self?.tabChanged(id) }
        }
        tab.observations = [
            view.observe(\.url) { view, change in changed(view, change) },
            view.observe(\.title) { view, change in changed(view, change) },
            view.observe(\.isLoading) { view, change in changed(view, change) },
            view.observe(\.canGoBack) { view, change in changed(view, change) },
            view.observe(\.canGoForward) { view, change in changed(view, change) },
        ]
        tabList.insert(tab, at: index)
        return tab
    }

    /// 탭을 고른다: 그 웹 뷰만 보이게 하고, 미뤄 둔 주소를 불러오고, 소리를 맞추고 알린다.
    private func activate(_ tab: WebTab) {
        selected = tab
        for view in containerView.subviews where view !== tab.view { view.removeFromSuperview() }
        if tab.view.superview !== containerView {
            tab.view.frame = containerView.bounds
            containerView.addSubview(tab.view)
        }
        if let url = tab.pendingURL {
            tab.pendingURL = nil
            tab.view.load(URLRequest(url: url))
        } else if tab.needsReload {
            tab.needsReload = false
            tab.view.reload()
        }
        applyMediaSuspension()
        onStateChange?()
        onTabsChange?()
    }

    /// 닫힌 탭의 대리자·관찰을 끊고 떼어 낸다. 대화창 기록·미디어 상태는 탭과 함께 사라진다.
    private func discard(_ tab: WebTab) {
        tab.observations.forEach { $0.invalidate() }
        tab.observations = []
        tab.view.engine = nil
        tab.view.navigationDelegate = nil
        tab.view.uiDelegate = nil
        tab.view.stopLoading()
        tab.view.removeFromSuperview()
    }

    private func tabChanged(_ id: Int) {
        guard let tab = tab(id) else { return }
        if !tab.view.isLoading, let url = tab.view.url, Self.isHTTP(url) { tab.savedAddress = url.absoluteString }
        if tab === selected { onStateChange?() }
        onTabsChange?()
    }

    // MARK: 탐색

    func load(_ url: URL) { load(url, in: selected) }
    func goBack() { selected.view.goBack() }
    func goForward() { selected.view.goForward() }
    func reloadOrStop() { if selected.view.isLoading { selected.view.stopLoading() } else { selected.view.reload() } }

    private func load(_ url: URL, in tab: WebTab) {
        guard Self.isWeb(url) else { onNotice?("HTTP 또는 HTTPS 주소만 열 수 있습니다."); return }
        tab.pendingURL = nil
        tab.view.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.shouldPerformDownload { return .download }
        guard navigationAction.targetFrame?.isMainFrame ?? true, let url = navigationAction.request.url else { return .allow }
        // 보통 링크도 ⌘클릭·가운데 클릭이면 Safari처럼 뒤의 새 탭으로 연다(새 창 링크는 `createWebViewWith`로 온다).
        if navigationAction.navigationType == .linkActivated, navigationAction.targetFrame?.isMainFrame == true, Self.isHTTP(url),
           navigationAction.modifierFlags.contains(.command) || navigationAction.buttonNumber == Self.middleButtonNumber {
            let opener = tab(for: webView)
            // 사용자가 직접 누른 것이라 "1초에 둘" 제한은 걸지 않는다(그 제한은 페이지가 여는 창용). 전체 탭 수만 본다.
            if hasRoomForTab() {
                let tab = makeTab(configuration: configuration, at: insertionIndex(after: opener), openerID: opener?.id, pendingURL: nil)
                tab.view.load(navigationAction.request)
                onTabsChange?()
            }
            return .cancel
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if ["http", "https", "about", "blob", "data"].contains(scheme) { return .allow }
        notice("이 링크 유형은 앱에서 지원하지 않습니다.", from: webView)
        return .cancel
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?
            .split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return navigationResponse.canShowMIMEType && disposition != "attachment" ? .allow : .download
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error, from: webView) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report(error, from: webView)
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard let tab = tab(for: webView) else { return }
        // 새 페이지는 대화창 폭주 기록과 새 탭 열기 기록을 새로 시작한다.
        tab.dialogTimes = []
        tab.dialogsSilenced = false
        tab.openTimes = []
        // 새 페이지가 들어섰으니 다시 불러올 필요가 없다(직접 새로고침한 뒤 탭을 오갈 때 또 불러오지 않게).
        tab.needsReload = false
        // 페이지가 처음 들어선 웹 뷰(새 탭, 미뤄 둔 탭)는 여기서 보임 상태에 맞춘다.
        applyMediaSuspension(to: tab)
    }
    /// 페이지 프로세스가 끝난 탭은 다음에 고를 때 다시 불러온다. 고른 탭이면 지금 알린다.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        tab(for: webView)?.needsReload = true
        notice("페이지 프로세스가 종료됐습니다. 새로고침해주세요.", from: webView)
    }
    private func report(_ error: Error, from webView: WKWebView) {
        let detail = error as NSError
        // 취소된 불러오기와 정책으로 끊긴 프레임은 페이지 실패가 아니다.
        if detail.code == NSURLErrorCancelled || (detail.domain == "WebKitErrorDomain" && detail.code == 102) { return }
        notice(error.localizedDescription, from: webView)
    }

    // MARK: 새 창 → 새 탭

    /// `target=_blank` 링크·"새 창에서 링크 열기"·`window.open` 모두 새 탭이다. WebKit이 준 설정으로 만들어야
    /// `window.opener`·POST 본문·로그인 맥락이 이어진다. ⌘를 누른 채 연 것은 뒤에서, 그 밖은 앞에서 연다.
    /// 새 탭은 연 탭 바로 뒤(그 탭이 먼저 연 탭들 뒤)에 둔다. 한 번의 클릭으로 창을 여럿 여는 페이지는
    /// 1초에 둘까지만 열고, 탭이 `maximumTabs`개면 열지 않는다.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, !url.absoluteString.isEmpty, !Self.isWeb(url) {
            notice("지원하지 않는 주소의 팝업을 차단했습니다.", from: webView)
            return nil
        }
        let opener = tab(for: webView)
        guard mayOpenTab(from: opener) else { return nil }
        let tab = makeTab(configuration: configuration, at: insertionIndex(after: opener), openerID: opener?.id, pendingURL: nil)
        if navigationAction.modifierFlags.contains(.command) { onTabsChange?() } else { activate(tab) }
        return tab.view
    }
    /// 페이지가 `window.close()`를 부르면 그 탭을 닫고, 고른 탭이었으면 연 탭(아직 있으면)으로 돌아간다.
    func webViewDidClose(_ webView: WKWebView) {
        if let tab = tab(for: webView) { close(tab.id, returningToOpener: true) }
    }

    // MARK: 대화창·파일 선택·권한

    /// 보이지 않는 탭과 대화창을 쏟아내는 페이지는 시트 없이 바로 답한다(alert는 통과, confirm은 false, prompt는 nil).
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        guard mayShowDialog(in: webView) else { return }
        _ = await dialogPresenter(dialog(from: frame, text: message), webView)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        guard mayShowDialog(in: webView) else { return false }
        let alert = dialog(from: frame, text: message)
        alert.addButton(withTitle: "확인"); alert.addButton(withTitle: "취소")
        return await dialogPresenter(alert, webView) == .alertFirstButtonReturn
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo) async -> String? {
        guard mayShowDialog(in: webView) else { return nil }
        let alert = dialog(from: frame, text: prompt)
        let input = NSTextField(string: defaultText ?? "")
        input.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = input
        alert.addButton(withTitle: "확인"); alert.addButton(withTitle: "취소")
        return await dialogPresenter(alert, webView) == .alertFirstButtonReturn ? input.stringValue : nil
    }
    /// 페이지가 보낸 글은 항상 보낸 사이트 이름 아래에 보인다.
    private func dialog(from frame: WKFrameInfo, text: String) -> NSAlert {
        let host = frame.securityOrigin.host
        let alert = NSAlert()
        alert.messageText = host.isEmpty ? "이 페이지의 메시지" : "\(host)의 메시지"
        alert.informativeText = text
        return alert
    }
    /// 펼친 패널의 고른 탭인지. 그런 탭만 시트를 띄우고 소리를 낸다.
    private func isVisible(_ tab: WebTab?) -> Bool {
        isPresented && tab != nil && tab === selected
    }
    /// 보일 때만, 그리고 한 탭의 페이지가 10초 안에 셋을 넘기기 전까지만 띄운다(탭마다 따로 센다).
    /// 넘기면 그 탭에 다음 페이지가 열릴 때까지 자동으로 답하고 한 번 알린다.
    private func mayShowDialog(in webView: WKWebView) -> Bool {
        guard let tab = tab(for: webView), isVisible(tab), !tab.dialogsSilenced else { return false }
        let now = Date()
        tab.dialogTimes = tab.dialogTimes.filter { now.timeIntervalSince($0) < Self.dialogFloodWindow } + [now]
        guard tab.dialogTimes.count > Self.dialogFloodLimit else { return true }
        tab.dialogsSilenced = true
        onNotice?("이 페이지의 알림창을 더 표시하지 않습니다.")
        return false
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        guard isVisible(tab(for: webView)) else { return nil }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        let response: NSApplication.ModalResponse
        if let window = webView.window { response = await panel.beginSheetModal(for: window) } else { response = panel.runModal() }
        return response == .OK ? panel.urls : nil
    }
    func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin, initiatedBy frame: WKFrameInfo,
                 type: WKMediaCaptureType) async -> WKPermissionDecision {
        notice("카메라·마이크 요청을 거절했습니다.", from: webView)
        return .deny
    }

    // MARK: 일반 내려받기(저장 창)

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        retainDownload(download)
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        retainDownload(download)
    }
    private func retainDownload(_ download: WKDownload) {
        downloads[ObjectIdentifier(download)] = download
        download.delegate = self
    }
    /// 저장 창은 그 내려받기를 시작한 탭이 보일 때만 띄운다. 접힌 패널·뒤에 있는 탭·닫힌 탭의 것은 거절하고 알린다.
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        let id = ObjectIdentifier(download)
        let source = download.webView.flatMap { tab(for: $0) }
        guard isVisible(source) else {
            downloads.removeValue(forKey: id)
            onNotice?(isPresented ? "뒤에 있는 탭의 내려받기를 취소했습니다." : "패널이 접혀 있어 내려받기를 취소했습니다.")
            return nil
        }
        let panel = NSSavePanel()
        panel.title = "다운로드 저장"
        panel.nameFieldStringValue = (suggestedFilename as NSString).lastPathComponent
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.canCreateDirectories = true
        let result: NSApplication.ModalResponse
        if let window = source?.view.window { result = await panel.beginSheetModal(for: window) } else { result = await panel.begin() }
        guard result == .OK, let destination = panel.url else {
            downloads.removeValue(forKey: id)
            return nil
        }
        // WKDownload는 없는 경로만 받는다. 기존 파일은 지우지 않는다.
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            downloads.removeValue(forKey: id)
            onNotice?("저장하지 않았습니다: 같은 이름의 파일이 있습니다. 다시 받아 다른 이름을 골라주세요.")
            return nil
        }
        downloadDestinations[id] = destination
        return destination
    }
    func downloadDidFinish(_ download: WKDownload) {
        let id = ObjectIdentifier(download)
        downloads.removeValue(forKey: id)
        guard let destination = downloadDestinations.removeValue(forKey: id) else { return }
        onNotice?("내려받았습니다: \(destination.lastPathComponent)")
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let id = ObjectIdentifier(download)
        downloads.removeValue(forKey: id)
        downloadDestinations.removeValue(forKey: id)
        if (error as NSError).code != NSURLErrorCancelled {
            onNotice?("내려받지 못했습니다: \(error.localizedDescription)")
        }
    }

    // MARK: 이미지 알림 스크립트

    /// `contextmenu`·`dragstart`를 window의 캡처 단계에서 듣고 대상 `<img>`를 알린다.
    /// 문서 시작에 등록하므로 페이지가 window에 단 캡처 처리기보다 먼저 불려 전파를 끊어도 놓치지 않는다.
    ///
    /// 이미지를 찾는 순서: 이벤트 경로의 `<img>` → 대상 요소 안의 첫 `<img>`(링크로 감싼 이미지) →
    /// 포인터 아래에 깔린 요소들 중 `<img>`(덮개에 가린 이미지). 없으면 image 없이 보낸다.
    ///
    /// 이 패널은 이미지를 모으는 자리라 **이미지 끌기는 페이지가 막지 못하게 한다**(2026-11-22 · civitai·Pinterest):
    /// - 넘겨 보는 이미지(회전목마) 등은 `dragstart`를 취소해 끌기 자체가 시작되지 않는다 → 이미지 끌기면
    ///   페이지 처리기에 닿기 전에 전파를 끊는다. 그 이미지를 끌어서 넘기는 동작은 이 패널에서 되지 않는다(화살표로 넘긴다).
    /// - `draggable=false`·`-webkit-user-drag: none`인 이미지와 덮개에 가린 이미지는 누르고 있는 동안만 끌 수 있게 바꿨다가 되돌린다.
    private static let captureScript = """
        (() => {
          const imageFor = event => {
            for (const node of event.composedPath()) {
              if (node && node.tagName === 'IMG') return node;
            }
            const target = event.target;
            if (target && target.querySelector) {
              const inside = target.querySelector('img');
              if (inside) return inside;
            }
            if (typeof event.clientX === 'number' && document.elementsFromPoint) {
              // 좌표가 정말 그 대상을 가리킬 때만 그 아래를 본다(좌표 없는 이벤트가 엉뚱한 이미지를 집지 않게).
              const stack = document.elementsFromPoint(event.clientX, event.clientY);
              if (stack.includes(target)) {
                for (const node of stack) {
                  if (node.tagName === 'IMG') return node;
                }
              }
            }
            return null;
          };
          const send = (kind, event) => {
            const image = imageFor(event);
            const body = { kind, pageURL: location.href };
            if (image) body.image = { currentSrc: image.currentSrc || '', src: image.src || '', srcset: image.getAttribute('srcset') || '' };
            window.webkit.messageHandlers.\(messageName).postMessage(body);
            return image;
          };
          window.addEventListener('contextmenu', event => { send('contextmenu', event); }, true);
          window.addEventListener('dragstart', event => {
            if (send('dragstart', event)) event.stopImmediatePropagation();
          }, true);

          let restore = null;
          const undo = () => { if (restore) { const run = restore; restore = null; run(); } };
          const makeDraggable = element => {
            const attribute = element.getAttribute('draggable');
            const style = element.style.getPropertyValue('-webkit-user-drag');
            const priority = element.style.getPropertyPriority('-webkit-user-drag');
            element.setAttribute('draggable', 'true');
            element.style.setProperty('-webkit-user-drag', 'element', 'important');
            return () => {
              if (attribute === null) element.removeAttribute('draggable'); else element.setAttribute('draggable', attribute);
              if (style) element.style.setProperty('-webkit-user-drag', style, priority); else element.style.removeProperty('-webkit-user-drag');
            };
          };
          window.addEventListener('mousedown', event => {
            undo();
            if (event.button !== 0 || !(event.target instanceof Element)) return;
            const image = imageFor(event);
            if (!image) return;
            const target = event.target;
            if (target === image) {
              if (!image.draggable || getComputedStyle(image).webkitUserDrag === 'none') restore = makeDraggable(image);
            } else if (!target.closest('a[href], [draggable="true"]')) {
              restore = makeDraggable(target);
            }
          }, true);
          window.addEventListener('mouseup', undo, true);
          window.addEventListener('dragend', undo, true);
        })();
        """

    /// 고른 탭의 알림만 받는다. 뒤 탭은 보이지 않아 손으로 누르거나 끌 수 없으므로, 그 탭 스크립트의 알림이
    /// 앞 탭에서 방금 누른·끈 이미지를 덮지 않게 한다.
    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.name == Self.messageName, message.webView === selected.view,
              let body = message.body as? [String: Any] else { return }
        let report = WebImageReport(message: body)
        switch body["kind"] as? String {
        case "contextmenu": lastContextImage = report
        case "dragstart": draggedImage = report.map { ($0, Date()) }
        default: break
        }
    }

    // MARK: 끌어다 놓기

    /// dragstart 후 30초 안의 값. 읽어도 지우지 않는다(끌어 지나가는 동안 여러 번 읽는다).
    func takeDraggedImage() -> WebImageReport? {
        guard let draggedImage, Date().timeIntervalSince(draggedImage.time) < 30 else { return nil }
        return draggedImage.report
    }

    /// 놓기가 끝난 드래그를 지운다. 새 dragstart 없는 다음 드래그가 같은 이미지를 다시 저장하지 않게 한다.
    func clearDraggedImage() { draggedImage = nil }

    // MARK: 보이기

    /// 펼친 패널의 고른 탭만 소리·영상을 내고, 뒤에 있는 탭과 접힌 패널의 탭은 멈춘다.
    private func applyMediaSuspension() {
        for tab in tabList { applyMediaSuspension(to: tab) }
    }
    /// WebKit은 멈춤 요청을 겹쳐 세어 되살리기 한 번이 멈춤 여러 번을 풀지 못한다(2026-11-22 확인).
    /// 그래서 탭마다 지금 상태를 기억해 바뀔 때만 부른다. 멈춤은 다음 페이지로 이어진다.
    /// 아직 페이지가 없는 웹 뷰는 건너뛰고 첫 페이지가 들어설 때(`didCommit`) 맞춘다.
    private func applyMediaSuspension(to tab: WebTab) {
        guard tab.view.url != nil else { return }
        let suspend = !isVisible(tab)
        guard suspend != tab.mediaSuspended else { return }
        tab.mediaSuspended = suspend
        tab.view.setAllMediaPlaybackSuspended(suspend)
    }

    /// 어느 탭의 웹 뷰 또는 그 하위 뷰. 실제 드래그의 출발지는 웹 뷰 자신이다(2026-11-21 확인).
    func isDragSource(_ source: Any?) -> Bool {
        guard let view = source as? NSView else { return false }
        return tabList.contains { view === $0.view || view.isDescendant(of: $0.view) }
    }

    /// 놓을 자리가 추가로 등록할 종류. 이미지 드래그 보드에서 확인한 값(2026-11-21) — 파일 약속·주소·PNG·TIFF.
    static var imageDragTypes: [NSPasteboard.PasteboardType] {
        [.URL, .png, .tiff] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    }

    // MARK: 우클릭

    /// 이미지 우클릭 메뉴 맨 위에 붙일 항목. 저장할 수 없는 이미지면 빈 배열.
    func contextMenuItems(for image: WebImageReport?) -> [NSMenuItem] {
        guard let image, WebImageCandidate.bestURL(for: image) != nil else { return [] }
        guard let folder = saveFolderProvider?() else {
            let item = NSMenuItem(title: "저장할 폴더를 먼저 선택하세요", action: nil, keyEquivalent: "")
            item.isEnabled = false
            return [item]
        }
        let item = NSMenuItem(title: "'\(folder.lastPathComponent)'에 저장", action: #selector(saveContextImage(_:)), keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        return [item]
    }

    /// 스크립트 알림이 메뉴가 열린 뒤 도착할 수 있어 이미지와 폴더는 누르는 순간에 읽는다.
    @objc private func saveContextImage(_ sender: Any?) {
        guard let image = lastContextImage else { return }
        guard let folder = saveFolderProvider?() else { onNotice?("저장할 폴더를 먼저 선택하세요"); return }
        onSaveImage?(image, folder)
    }

    func decorate(_ menu: NSMenu) {
        guard menu.items.contains(where: { Self.imageMenuIdentifiers.contains($0.identifier?.rawValue ?? "") }) else { return }
        let items = contextMenuItems(for: lastContextImage)
        guard !items.isEmpty else { return }
        menu.insertItem(.separator(), at: 0)
        for item in items.reversed() { menu.insertItem(item, at: 0) }
    }
}

/// 사용자 콘텐츠 컨트롤러가 처리기를 붙잡아 생기는 순환을 끊는다.
private final class WebScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var engine: WebPageEngine?
    init(engine: WebPageEngine) { self.engine = engine }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        engine?.receive(message)
    }
}
