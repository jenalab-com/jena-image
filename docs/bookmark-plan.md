# 이미지 북마크 기능 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 폴더 구조와 무관하게 이미지를 북마크(위치만 저장)해, 사이드바의 "★ 북마크" 항목에서 썸네일로 모아 보고 관리한다.

**Architecture:** 새 `BookmarkStore`가 파일 경로 목록을 UserDefaults에 영속하고 변경 알림을 발행한다. 사이드바 최상단에 고정 "★ 북마크" 행을 두고, 클릭하면 `MainWindowController`가 메인 영역을 북마크 그리드로 전환한다. 북마크 그리드는 기존 `BrowserViewController`에 "북마크 모드"를 더해 임의 이미지 배열을 표시한다. 추가/제거는 브라우저·뷰어 양쪽에서 토글한다.

**Tech Stack:** Swift, AppKit (NSOutlineView, NSCollectionView, NSWindowController). 외부 의존성 없음. 빌드는 `make build`(swiftc 통짜 컴파일).

## Global Constraints

- 테스트 러너 없음. 각 태스크 검증 = `make build`(경고·에러 0) + 명시된 수동 GUI 절차.
- 코드 주석·UI 문자열은 한국어(기존 관습). 식별자는 영어.
- 비샌드박스 앱이라 북마크는 **파일 경로 문자열**만 저장(보안 스코프 북마크 불필요).
- 북마크 정렬: 최근 추가가 위(index 0). 드래그 재정렬은 범위 밖(2차).
- "삭제"·"이름변경"은 실제 파일 대상(기존 `performDelete`/`performRename` 재사용),
  성공 시 `BookmarkStore`를 반드시 동기화한다.
- 커밋은 비교 기능처럼 한 태스크당 해당 파일만 `git add`. 절대 `git add -A` 금지
  (작업 트리에 무관한 변경이 있을 수 있음).
- 기존 패턴을 따른다: 영속은 `AppSettings`(UserDefaults) 스타일, 단일 서비스
  인스턴스를 `MainWindowController`가 소유·주입(`securityService` 패턴).

---

## 파일 구조

생성:
- `Sources/services/BookmarkStore.swift` — 북마크 경로 목록 영속 + CRUD + 변경 알림.

수정:
- `Sources/sidebar/SidebarViewController.swift` — 최상단 "★ 북마크" 고정 행 + delegate 콜백.
- `Sources/browser/BrowserViewController.swift` — 북마크 모드(`displayBookmarks`, 빈 상태, 우클릭 "빼기", 토글 메뉴 항목).
- `Sources/app/MainWindowController.swift` — `BookmarkStore` 소유, 북마크 보기 전환, 토글 액션.
- `Sources/app/MainWindowController+Delegates.swift` — 사이드바/브라우저 북마크 delegate 구현.
- `Sources/app/MainWindowController+FileOperations.swift` — rename/delete 후 `BookmarkStore` 동기화.
- `Sources/app/MainWindowController+Actions.swift` — 토글 액션 + `validateMenuItem`.
- `Sources/app/MainMenu.swift` — 북마크 토글 메뉴 항목 + 단축키.
- `Sources/viewer/ViewerViewController.swift` — 뷰어 ★ 토글 버튼 + 상태 갱신.

---

## Task 1: `BookmarkStore` — 영속 + CRUD + 알림

북마크 경로 목록을 UserDefaults에 저장하고 변경을 알린다. 순수 데이터 레이어.

**Files:**
- Create: `Sources/services/BookmarkStore.swift`

**Interfaces:**
- Consumes: 없음(표준 라이브러리만).
- Produces:
  - `final class BookmarkStore` (단일 인스턴스로 주입; 기존 `securityService`처럼 `MainWindowController`가 소유)
    - `var bookmarks: [URL]` (읽기 — 최근 추가가 index 0)
    - `func add(_ url: URL)` — 이미 있으면 무시, 새 항목을 맨 앞에 삽입.
    - `func remove(_ url: URL)` — 목록에서 제거(파일 불변).
    - `func contains(_ url: URL) -> Bool`
    - `func rename(from oldURL: URL, to newURL: URL)` — 경로 교체(없으면 무시), 순서 유지.
  - `extension Notification.Name { static let bookmarksChanged }` — 변경 시 발행.

- [ ] **Step 1: `BookmarkStore` 작성**

`Sources/services/BookmarkStore.swift` 생성:

```swift
import Foundation

extension Notification.Name {
    /// 북마크 목록이 바뀌면 발행(사이드바·그리드·뷰어 버튼 갱신용).
    static let bookmarksChanged = Notification.Name("bookmarksChanged")
}

/// 이미지 북마크(즐겨찾기) 영속 저장소. 파일 경로만 저장(비샌드박스).
/// 최근 추가가 앞(index 0).
final class BookmarkStore {
    private let defaults = UserDefaults.standard
    private let key = "imageBookmarks"

    private(set) var bookmarks: [URL] {
        get {
            let paths = defaults.stringArray(forKey: key) ?? []
            return paths.map { URL(fileURLWithPath: $0) }
        }
        set {
            defaults.set(newValue.map { $0.path }, forKey: key)
        }
    }

    /// 같은 파일이 이미 있으면 무시. 새 항목을 맨 앞에 추가.
    func add(_ url: URL) {
        let std = url.standardizedFileURL
        guard !contains(std) else { return }
        bookmarks = [std] + bookmarks
        NotificationCenter.default.post(name: .bookmarksChanged, object: nil)
    }

    /// 목록에서만 제거(파일은 그대로).
    func remove(_ url: URL) {
        let std = url.standardizedFileURL
        let next = bookmarks.filter { $0.standardizedFileURL != std }
        guard next.count != bookmarks.count else { return }
        bookmarks = next
        NotificationCenter.default.post(name: .bookmarksChanged, object: nil)
    }

    func contains(_ url: URL) -> Bool {
        let std = url.standardizedFileURL
        return bookmarks.contains { $0.standardizedFileURL == std }
    }

    /// 이름변경/이동 시 경로 교체(순서 유지). 없으면 무시.
    func rename(from oldURL: URL, to newURL: URL) {
        let oldStd = oldURL.standardizedFileURL
        guard let idx = bookmarks.firstIndex(where: { $0.standardizedFileURL == oldStd }) else { return }
        var next = bookmarks
        next[idx] = newURL.standardizedFileURL
        bookmarks = next
        NotificationCenter.default.post(name: .bookmarksChanged, object: nil)
    }
}
```

- [ ] **Step 2: 빌드 검증**

Run: `make build`
Expected: 컴파일 성공, 경고·에러 0. (SourceKit의 cross-file "Cannot find type"은 통짜 빌드 특성상 무시 — `make build`가 기준.)

- [ ] **Step 3: 커밋**

```bash
git add Sources/services/BookmarkStore.swift
git commit -m "feat: 북마크 영속 저장소(BookmarkStore) 추가"
```

---

## Task 2: 사이드바 "★ 북마크" 항목 + 북마크 그리드 전환

사이드바 최상단에 고정 "★ 북마크" 행을 두고, 클릭하면 메인이 북마크 그리드로 전환된다(처음엔 빈 상태라도). 폴더를 다시 선택하면 일반 폴더 보기로 복귀.

**Files:**
- Modify: `Sources/sidebar/SidebarViewController.swift` (고정 행 + delegate, `loadView`/레이아웃)
- Modify: `Sources/browser/BrowserViewController.swift` (`displayBookmarks` + 빈 상태 + `isBookmarkMode`)
- Modify: `Sources/app/MainWindowController.swift` (`bookmarkStore` 소유, 북마크 보기 전환 메서드)
- Modify: `Sources/app/MainWindowController+Delegates.swift` (사이드바 delegate 구현)

**Interfaces:**
- Consumes: Task 1의 `BookmarkStore.bookmarks`, `.bookmarksChanged`.
- Produces:
  - `SidebarDelegate.sidebarDidSelectBookmarks(_ sidebar: SidebarViewController)`
  - `BrowserViewController.displayBookmarks(_ files: [ImageFile])`, `var isBookmarkMode: Bool` (읽기)
  - `MainWindowController.showBookmarks()` — 메인을 북마크 그리드로 전환.
  - `MainWindowController.bookmarkStore: BookmarkStore` (프로퍼티)

- [ ] **Step 1: 사이드바에 고정 "★ 북마크" 행 추가**

`SidebarViewController`의 `loadView`/레이아웃에서, outline의 `scrollView` 위에 고정
버튼 행을 둔다(outline 트리 데이터에 끼우지 않는다 — 트리 로직과 분리).

`SidebarDelegate` 프로토콜에 추가:

```swift
    func sidebarDidSelectBookmarks(_ sidebar: SidebarViewController)
```

`SidebarViewController`에 프로퍼티와 버튼 추가:

```swift
    private let bookmarksButton = NSButton()
```

`loadView`에서 `setupScrollView()` 호출 전후로 북마크 버튼을 구성하고, `scrollView`의
top을 이 버튼 아래로 잇는다(버튼은 view.top, scrollView.top = 버튼.bottom):

```swift
    private func setupBookmarksRow() {
        bookmarksButton.translatesAutoresizingMaskIntoConstraints = false
        bookmarksButton.title = " 북마크"
        bookmarksButton.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "북마크")
        bookmarksButton.imagePosition = .imageLeading
        bookmarksButton.bezelStyle = .inline
        bookmarksButton.isBordered = false
        bookmarksButton.alignment = .left
        bookmarksButton.contentTintColor = .controlAccentColor
        bookmarksButton.target = self
        bookmarksButton.action = #selector(bookmarksTapped)
        view.addSubview(bookmarksButton)
        // 제약: bookmarksButton.top = view.top(+여백), leading/trailing = view, height ~28
        //       scrollView.top = bookmarksButton.bottom 으로 잇는다(기존 scrollView.top 제약 교체).
    }

    @objc private func bookmarksTapped() {
        // 폴더 선택 해제 후 delegate 호출(폴더 보기와 상호배타).
        outlineView.deselectAll(nil)
        delegate?.sidebarDidSelectBookmarks(self)
    }
```

> 주의: 기존 `setupScrollView()`가 `scrollView.topAnchor.constraint(equalTo: ...)`를
> 어디에 잡는지 확인하고, 그 top 제약만 `bookmarksButton.bottomAnchor`로 바꾼다.
> 나머지(leading/trailing/bottom)는 그대로.

- [ ] **Step 2: `BrowserViewController` 북마크 모드**

`BrowserViewController`에 추가:

```swift
    private(set) var isBookmarkMode = false

    /// 북마크(임의 위치 이미지) 평면 목록을 표시한다.
    func displayBookmarks(_ files: [ImageFile]) {
        isBookmarkMode = true
        contents = files.map { BrowserContent.image($0) }
        collectionView.reloadData()
        loadThumbnails(for: files)
        updateEmptyState()
    }
```

기존 `display(folders:images:)` 시작부에 `isBookmarkMode = false`를 추가해, 폴더
보기로 돌아오면 모드가 해제되게 한다.

빈 상태 안내(컬렉션이 비고 북마크 모드일 때):

```swift
    private let emptyLabel = NSTextField(labelWithString: "북마크가 비어 있어요")

    private func updateEmptyState() {
        // emptyLabel을 collectionView 중앙에 한 번 배치(없으면 추가).
        emptyLabel.isHidden = !(isBookmarkMode && contents.isEmpty)
    }
```

> `emptyLabel`은 `loadView`에서 한 번 추가하고 가운데 정렬 제약을 건다. 폴더 모드에선 항상 숨김.

- [ ] **Step 3: `MainWindowController` 북마크 보기 전환**

`MainWindowController`에 프로퍼티 추가(다른 서비스들 근처):

```swift
    let bookmarkStore = BookmarkStore()
```

북마크 보기 전환 메서드:

```swift
    /// 사이드바 북마크 항목 → 메인을 북마크 그리드로 전환.
    func showBookmarks() {
        switchToMode(.browser)
        let files = bookmarkStore.bookmarks.compactMap { ImageFile(url: $0) }
        browserVC.displayBookmarks(files)
        window?.title = "북마크"
        statusBar.update(folderCount: 0, imageCount: files.count, selectionCount: 0)
    }
```

> `ImageFile(url:)`은 failable이며 존재하지 않는 파일도 생성될 수 있다(깨진 북마크는
> Task 4에서 플레이스홀더 처리). 여기서는 단순 변환만.

- [ ] **Step 4: 사이드바 delegate 구현**

`Sources/app/MainWindowController+Delegates.swift`의 `SidebarDelegate` extension에 추가:

```swift
    func sidebarDidSelectBookmarks(_ sidebar: SidebarViewController) {
        activePanel = .sidebar
        showBookmarks()
    }
```

- [ ] **Step 5: 빌드 검증**

Run: `make build`
Expected: 성공, 경고·에러 0.

- [ ] **Step 6: 수동 GUI 검증**

`make run` 후:
1. 사이드바 최상단에 "★ 북마크" 행이 보이는지.
2. 클릭 → 메인이 "북마크가 비어 있어요" 빈 그리드로 전환되고 창 제목이 "북마크"인지.
3. 폴더를 선택 → 일반 폴더 그리드로 정상 복귀하는지.

- [ ] **Step 7: 커밋**

```bash
git add Sources/sidebar/SidebarViewController.swift Sources/browser/BrowserViewController.swift Sources/app/MainWindowController.swift Sources/app/MainWindowController+Delegates.swift
git commit -m "feat: 사이드바 북마크 항목 + 북마크 그리드 전환"
```

---

## Task 3: 추가/제거 토글 (브라우저 + 뷰어)

브라우저 선택 항목과 뷰어 현재 이미지를 북마크에 토글한다. 변경은 `.bookmarksChanged`로
북마크 그리드·★ 상태에 반영된다.

**Files:**
- Modify: `Sources/browser/BrowserViewController.swift` (우클릭 토글 항목)
- Modify: `Sources/app/MainWindowController.swift` (토글 액션, `.bookmarksChanged` 관찰)
- Modify: `Sources/app/MainWindowController+Delegates.swift` (브라우저 토글 delegate)
- Modify: `Sources/app/MainWindowController+Actions.swift` (토글 액션 + validateMenuItem)
- Modify: `Sources/app/MainMenu.swift` (북마크 토글 메뉴 + 단축키)
- Modify: `Sources/viewer/ViewerViewController.swift` (★ 버튼 + 상태)

**Interfaces:**
- Consumes: Task 1 `BookmarkStore.add/remove/contains`, `.bookmarksChanged`; Task 2 `showBookmarks`, `isBookmarkMode`.
- Produces:
  - `BrowserDelegate.browserDidToggleBookmark(_ browser: BrowserViewController, urls: [URL])`
  - `MainWindowController.toggleBookmark(_ urls: [URL])` (internal), `@objc func toggleBookmarkSelected(_:)`
  - `ViewerViewController.onToggleBookmark: ((URL) -> Void)?`, `func updateBookmarkButton(isBookmarked: Bool)`

- [ ] **Step 1: 브라우저 우클릭 토글 항목**

`BrowserViewController`의 `BrowserDelegate`에 추가:

```swift
    func browserDidToggleBookmark(_ browser: BrowserViewController, urls: [URL])
```

`buildContextMenu(for urls:)`에서 이미지가 포함된 경우 토글 항목을 넣는다(라벨은
모두 북마크돼 있으면 "북마크에서 빼기", 아니면 "북마크에 추가"). 북마크 상태 판정은
delegate가 알 수 없으므로, 컨트롤러가 채워준 `bookmarkedURLs: Set<URL>`(주입)로 라벨 결정:

```swift
    var isBookmarkedProvider: ((URL) -> Bool)?   // MainWindowController가 주입

    // buildContextMenu 내, 이미지 url들에 대해:
    let imageURLs = urls.filter { ImageFile(url: $0)?.isVideo == false }
    if !imageURLs.isEmpty {
        let allBookmarked = imageURLs.allSatisfy { isBookmarkedProvider?($0) ?? false }
        let title = allBookmarked ? "북마크에서 빼기" : "북마크에 추가"
        menu.addItem(withTitle: title, action: #selector(contextToggleBookmark(_:)), keyEquivalent: "")
    }
```

핸들러:

```swift
    @objc private func contextToggleBookmark(_ sender: NSMenuItem) {
        let urls = selectedURLs()
        guard !urls.isEmpty else { return }
        delegate?.browserDidToggleBookmark(self, urls: urls)
    }
```

북마크 모드일 때 우클릭 메뉴에 "빼기"도 추가(Task 4에서 동작 강화; 여기선 토글이 곧 빼기 역할).

- [ ] **Step 2: 컨트롤러 토글 액션 + 상태 주입**

`MainWindowController`에 추가:

```swift
    /// 주어진 URL들을 북마크 토글. 모두 북마크돼 있으면 일괄 제거, 아니면 일괄 추가.
    func toggleBookmark(_ urls: [URL]) {
        let images = urls.compactMap { ImageFile(url: $0) }.filter { !$0.isVideo }.map { $0.url }
        guard !images.isEmpty else { return }
        let allBookmarked = images.allSatisfy { bookmarkStore.contains($0) }
        for url in images {
            if allBookmarked { bookmarkStore.remove(url) } else { bookmarkStore.add(url) }
        }
    }

    @objc func toggleBookmarkSelected(_ sender: Any?) {
        toggleBookmark(browserVC.selectedURLs())
    }
```

`browserVC` 구성 시 상태 provider 주입(예: `viewDidLoad`나 브라우저 생성부):

```swift
    browserVC.isBookmarkedProvider = { [weak self] url in self?.bookmarkStore.contains(url) ?? false }
```

`.bookmarksChanged` 관찰 → 북마크 보기 중이면 그리드 갱신, 뷰어 ★ 갱신:

```swift
    // init/viewDidLoad에서
    NotificationCenter.default.addObserver(
        forName: .bookmarksChanged, object: nil, queue: .main
    ) { [weak self] _ in
        guard let self else { return }
        if self.browserVC.isBookmarkMode { self.showBookmarks() }
        self.refreshViewerBookmarkButton()
    }
```

- [ ] **Step 3: 브라우저 토글 delegate**

`MainWindowController+Delegates.swift`의 `BrowserDelegate` extension:

```swift
    func browserDidToggleBookmark(_ browser: BrowserViewController, urls: [URL]) {
        toggleBookmark(urls)
    }
```

- [ ] **Step 4: 메뉴 + 단축키**

`MainMenu.swift`의 `createViewMenu()`에서 비교 항목 근처에 추가:

```swift
        let bookmark = NSMenuItem(title: "북마크 토글", action: #selector(MainWindowController.toggleBookmarkSelected(_:)), keyEquivalent: "b")
        viewMenu.addItem(bookmark)
```

> 단축키 `⌘B`. 기존 단축키(o,r,d,S,p,c,v,a,s,[,9,0,+,-,f,m,?,e,\)와 무충돌 확인.

`MainWindowController+Actions.swift`의 `validateMenuItem`에 활성 조건(이미지 1장 이상 선택, 비디오 제외):

```swift
        if menuItem.action == #selector(toggleBookmarkSelected(_:)) {
            return browserVC.selectedURLs().compactMap { ImageFile(url: $0) }.filter { !$0.isVideo }.count >= 1
        }
```

- [ ] **Step 5: 뷰어 ★ 토글 버튼**

`ViewerViewController`에 추가(하단 버튼들 옆 — 기존 `editButton`/`thumbnailToggleButton` 패턴):

```swift
    var onToggleBookmark: ((URL) -> Void)?
    private let bookmarkButton = NSButton(title: "", target: nil, action: nil)

    func updateBookmarkButton(isBookmarked: Bool) {
        let name = isBookmarked ? "star.fill" : "star"
        bookmarkButton.image = NSImage(systemSymbolName: name, accessibilityDescription: "북마크")
    }

    @objc private func bookmarkButtonTapped() {
        guard let url = currentImageURL else { return }
        onToggleBookmark?(url)
    }
```

`setupEditButton`(하단 버튼 구성부)에서 `bookmarkButton`을 구성·배치하고
`bookmarkButtonTapped`를 연결한다. `showImage`/`showMedia`에서 현재 파일이 바뀔 때
상태를 갱신하도록, `ViewerDelegate`에 조회 훅을 둔다:

```swift
    // ViewerDelegate에 추가
    func viewerIsBookmarked(_ viewer: ViewerViewController, url: URL) -> Bool
```

`showMedia(at:)` 끝에서:

```swift
    if let url = currentImageURL {
        updateBookmarkButton(isBookmarked: delegate?.viewerIsBookmarked(self, url: url) ?? false)
    }
```

`MainWindowController`에서 뷰어 콜백 배선:

```swift
    // 뷰어 구성부
    viewerVC.onToggleBookmark = { [weak self] url in self?.toggleBookmark([url]) }

    // ViewerDelegate 구현
    func viewerIsBookmarked(_ viewer: ViewerViewController, url: URL) -> Bool {
        bookmarkStore.contains(url)
    }

    // .bookmarksChanged 관찰에서 호출되는 헬퍼
    func refreshViewerBookmarkButton() {
        guard let url = viewerVC.currentImageURL else { return }
        viewerVC.updateBookmarkButton(isBookmarked: bookmarkStore.contains(url))
    }
```

- [ ] **Step 6: 빌드 검증**

Run: `make build`
Expected: 성공, 경고·에러 0.

- [ ] **Step 7: 수동 GUI 검증**

`make run` 후:
1. 브라우저에서 이미지 선택 → 우클릭 "북마크에 추가" → 사이드바 북마크 그리드에 나타나는지.
2. 같은 이미지 우클릭 → 라벨이 "북마크에서 빼기"로 바뀌고, 누르면 빠지는지.
3. `⌘B`로도 토글되는지.
4. 뷰어로 열어 ★ 버튼이 북마크 상태(채워짐/빈 별)를 정확히 표시하고, 눌러 토글되는지.
5. 토글 직후 북마크 그리드/★ 버튼이 즉시 갱신되는지(`.bookmarksChanged`).

- [ ] **Step 8: 커밋**

```bash
git add Sources/browser/BrowserViewController.swift Sources/app/MainWindowController.swift Sources/app/MainWindowController+Delegates.swift Sources/app/MainWindowController+Actions.swift Sources/app/MainMenu.swift Sources/viewer/ViewerViewController.swift
git commit -m "feat: 북마크 추가/제거 토글(브라우저·뷰어)"
```

---

## Task 4: 북마크 뷰 동작(빼기·삭제·이름변경) + 파일조작 동기화 + 깨진 북마크

북마크 그리드의 우클릭 동작을 완성하고, 실제 파일 삭제·이름변경 시 `BookmarkStore`를
동기화한다. 원본이 사라진 북마크는 플레이스홀더로 표시한다.

**Files:**
- Modify: `Sources/browser/BrowserViewController.swift` (북마크 모드 우클릭 메뉴: 빼기/삭제/이름변경, 깨진 항목 표시)
- Modify: `Sources/app/MainWindowController+FileOperations.swift` (rename/delete 후 Store 동기화)
- Modify: `Sources/app/MainWindowController.swift` (북마크 뷰 더블클릭 → 뷰어, imageList = 북마크 전체)

**Interfaces:**
- Consumes: Task 1 `BookmarkStore.remove/rename`; Task 2 `displayBookmarks`/`isBookmarkMode`; Task 3 `browserDidToggleBookmark`.
- Produces:
  - `BrowserDelegate.browserDidRequestRemoveBookmark(_ browser: BrowserViewController, urls: [URL])`

- [ ] **Step 1: 북마크 모드 우클릭 메뉴**

`buildContextMenu(for urls:)`에서 `isBookmarkMode`일 때 메뉴를 구성한다(열기·빼기·삭제·이름변경):

```swift
        if isBookmarkMode {
            menu.addItem(withTitle: "열기", action: #selector(contextOpen(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "빼기", action: #selector(contextRemoveBookmark(_:)), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            if urls.count == 1 {
                menu.addItem(withTitle: "이름 변경", action: #selector(contextRename(_:)), keyEquivalent: "")
            }
            menu.addItem(withTitle: "삭제", action: #selector(contextDelete(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Finder에서 보기", action: #selector(contextRevealInFinder(_:)), keyEquivalent: "")
            return menu
        }
```

> `contextOpen`/`contextRename`/`contextDelete`/`contextRevealInFinder`는 기존 핸들러를
> 재사용(이미 존재). 없으면 가장 가까운 기존 핸들러명에 맞춘다(구현 시 확인).

"빼기" 핸들러 + delegate:

```swift
    @objc private func contextRemoveBookmark(_ sender: NSMenuItem) {
        let urls = selectedURLs()
        guard !urls.isEmpty else { return }
        delegate?.browserDidRequestRemoveBookmark(self, urls: urls)
    }
```

`BrowserDelegate`에 추가 + 구현(`MainWindowController+Delegates.swift`):

```swift
    func browserDidRequestRemoveBookmark(_ browser: BrowserViewController, urls: [URL]) {
        urls.forEach { bookmarkStore.remove($0) }
    }
```

- [ ] **Step 2: 파일조작 후 Store 동기화**

`MainWindowController+FileOperations.swift`:
- `performDelete(urls:)` 성공 경로에서 삭제된 각 url을 `bookmarkStore.remove($0)`.
- `performRename(url:newName:)` 성공 경로에서 새 URL을 계산해 `bookmarkStore.rename(from: oldURL, to: newURL)`.

> 정확한 삽입 위치: 각 함수에서 실제 파일 시스템 작업이 성공한 직후(기존 갱신 로직
> 옆). 새 URL은 기존 rename이 계산하는 값(같은 디렉토리 + newName)을 재사용한다.

- [ ] **Step 3: 북마크 뷰 더블클릭 → 뷰어(북마크 목록으로 네비)**

북마크 그리드에서 이미지 더블클릭(또는 Enter) 시, 뷰어의 imageList가 **북마크 전체**가
되도록 한다. 기존 브라우저는 `didRequestViewImage(url:inList:)`로 폴더 목록을 넘긴다.
북마크 모드에선 inList를 북마크 목록으로 채운다:

`BrowserViewController`의 뷰어 진입 지점(더블클릭 핸들러)에서 `isBookmarkMode`이면
`contents`(현재 북마크 이미지들)를 inList로 전달하도록 분기. 기존 코드가 폴더 기준
목록을 만들고 있으면, 북마크 모드에서는 `contents.compactMap { if case .image(let f) = $0 { return f } else { return nil } }`를 쓴다.

- [ ] **Step 4: 깨진 북마크 플레이스홀더**

북마크 그리드 셀 구성 시 파일이 존재하지 않으면(또는 썸네일 생성 실패) 흐릿한
플레이스홀더 + "원본을 찾을 수 없음" 느낌으로 표시한다. 자동 제거하지 않는다.

`displayBookmarks`/썸네일 로드 경로에서 `FileManager.default.fileExists(atPath: url.path)`가
false인 항목은 시스템 심볼(예: `exclamationmark.triangle`)로 대체하고 이름을 회색으로.
"빼기"만 가능(삭제/이름변경/열기는 비활성 또는 무동작).

> 구현 메모: 셀 렌더링이 `BrowserContent.image`만 처리하므로, 존재하지 않는 파일도
> `ImageFile`로 들어온다. 셀에서 `fileExists`로 분기해 플레이스홀더 이미지를 세팅하고,
> 컨텍스트 메뉴는 깨진 항목이 하나라도 포함되면 삭제/이름변경을 비활성화한다.

- [ ] **Step 5: 빌드 검증**

Run: `make build`
Expected: 성공, 경고·에러 0.

- [ ] **Step 6: 수동 GUI 검증**

`make run` 후:
1. 북마크 그리드에서 우클릭 → 열기/빼기/이름 변경/삭제/Finder에서 보기가 보이는지.
2. **빼기** → 북마크에서만 빠지고 파일은 그대로(Finder 확인).
3. **이름 변경** → 실제 파일명이 바뀌고, 북마크 그리드에도 새 이름으로 유지되는지(경로 동기화).
4. **삭제** → 확인 다이얼로그 후 휴지통으로 가고, 북마크에서도 사라지는지.
5. 북마크 이미지 더블클릭 → 뷰어에서 ↑/↓로 **북마크 목록 안에서** 이동하는지.
6. 북마크된 파일을 Finder에서 다른 곳으로 옮긴 뒤 북마크 그리드 → 플레이스홀더로
   표시되고 "빼기"만 가능한지(자동 삭제 안 됨).

- [ ] **Step 7: devlog 작성 + 커밋**

`docs/devlog/<오늘 날짜>.md`에 북마크 기능 요약을 추가(배경·변경 사항·검증). 그 후:

```bash
git add Sources/browser/BrowserViewController.swift Sources/app/MainWindowController+FileOperations.swift Sources/app/MainWindowController.swift docs/devlog/
git commit -m "feat: 북마크 뷰 동작(빼기·삭제·이름변경) + 파일조작 동기화 + 깨진 북마크"
```

---

## Self-Review 기록

- **Spec 커버리지:** `BookmarkStore`(Task 1) / 사이드바 항목·그리드 전환(Task 2) /
  브라우저·뷰어 토글(Task 3) / 빼기·삭제·이름변경·동기화·깨진 북마크(Task 4) /
  정렬 최근 추가 위(Task 1 `add`가 맨 앞 삽입) / 깨진 북마크 자동삭제 안 함(Task 4).
  설계의 2차 항목(드래그 재정렬, 그룹, 별칭)은 의도적으로 제외 — 범위 일치.
- **타입 일관성:** `BookmarkStore.add/remove/contains/rename`(Task 1) →
  `displayBookmarks`/`isBookmarkMode`(Task 2) → `toggleBookmark`/`isBookmarkedProvider`/
  `onToggleBookmark`/`viewerIsBookmarked`(Task 3) → `browserDidRequestRemoveBookmark`/
  파일조작 동기화(Task 4) 시그니처가 태스크 간 일치.
- **열린 사항(구현 단계 확정):**
  - Task 2 Step 1에서 기존 `scrollView.topAnchor` 제약의 실제 위치를 확인해 북마크 행
    아래로 교체.
  - Task 4 Step 1의 컨텍스트 핸들러명(`contextOpen`/`contextRename`/`contextDelete`/
    `contextRevealInFinder`)이 실제와 일치하는지 확인 후 사용.
  - `⌘B` 단축키 무충돌 확인(계획 가정: 미사용).
