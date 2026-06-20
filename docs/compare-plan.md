# 이미지 비교 기능 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 브라우저에서 선택한 2~4장의 이미지를 별도 창에 나란히 띄우고, 줌·팬을 동기화해 베스트를 고를 수 있게 한다.

**Architecture:** 별도 `CompareWindowController`(NSWindowController)가 N개의 `ComparePaneView`를 그리드로 배치한다. 각 칸은 기존 `ImageDisplayView`를 재사용하고, 줌·팬 변경을 콜백으로 노출한다. `SyncCoordinator`가 그 신호를 받아 나머지 칸에 같은 변환을 브로드캐스트한다. 진입은 브라우저 다중 선택 + (메뉴/단축키/우클릭/툴바) 4경로.

**Tech Stack:** Swift, AppKit (NSWindowController, NSGridView, NSScrollView). 외부 의존성 없음. 빌드는 `make build`(swiftc 통짜 컴파일).

## Global Constraints

- 테스트 러너 없음. 각 태스크 검증 = `make build`(경고·에러 0) + 명시된 수동 GUI 절차.
- 코드 주석·UI 문자열은 한국어(기존 코드 관습). 식별자는 영어.
- 비교 대상은 정지 이미지 전용. 비디오(`ImageFile.isVideo`)는 진입 시 제외.
- 한 세션 내 모델 토글 금지(캐시). 커밋은 사용자가 요청할 때만 — 단 본 계획은 태스크별 커밋 단위를 명시하되 실제 커밋 실행 여부는 실행자가 사용자 지침에 따른다.
- 기존 파일 패턴을 따른다: 윈도우 컨트롤러는 `ImageEditorWindowController` 스타일, 진입 액션은 `MainWindowController`의 `@objc` 메서드 + delegate 콜백.

---

## 파일 구조

생성:
- `Sources/viewer/CompareWindowController.swift` — 비교 창. 그리드 배치, 후보 strip, 동기화 토글, 칸 추가/제거.
- `Sources/viewer/ComparePaneView.swift` — 개별 칸(이미지 + 파일명 + 닫기 + 활성 테두리). `ImageDisplayView` 래핑.
- `Sources/viewer/CompareSyncCoordinator.swift` — 줌·팬 동기화 브로드캐스트 + 좌표 정규화 순수 함수.

수정:
- `Sources/viewer/ImageDisplayView.swift` — 줌·팬 변경 콜백(`onTransformChanged`)과 외부 적용 메서드(`applyTransform`) 추가.
- `Sources/app/MainWindowController.swift` — `ToolbarID.compare` 추가, 비교 창 보관 프로퍼티, `compareSelected(_:)` 액션, 툴바 등록.
- `Sources/app/MainWindowController+Delegates.swift` — 툴바 default/allowed/itemForItemIdentifier에 compare 등록, `BrowserDelegate.browserDidRequestCompare` 구현.
- `Sources/app/MainWindowController+Actions.swift` — `validateMenuItem`/`validateToolbarItem`에서 비교 활성화 조건.
- `Sources/app/MainMenu.swift` — View 메뉴에 "비교" 항목 + 단축키.
- `Sources/browser/BrowserViewController.swift` — `buildContextMenu`에 "비교" 항목, `BrowserDelegate`에 compare 콜백.

---

## Task 1: 진입점 배선 + 비교 창 골격(정적 N장 그리드)

브라우저에서 2~4장(비디오 제외) 선택 후 4경로 중 하나로 비교 창을 열면, 선택분이 2/3/4칸 그리드로 뜬다. 줌·팬은 각 칸 독립(동기화는 Task 2), 교체·닫기 없음.

**Files:**
- Create: `Sources/viewer/ComparePaneView.swift`
- Create: `Sources/viewer/CompareWindowController.swift`
- Modify: `Sources/app/MainWindowController.swift` (ToolbarID enum ~L24-31, 툴바 itemForItemIdentifier, 새 프로퍼티/액션)
- Modify: `Sources/app/MainWindowController+Delegates.swift` (툴바 식별자 목록·itemForItemIdentifier, BrowserDelegate)
- Modify: `Sources/app/MainWindowController+Actions.swift` (`validateMenuItem` ~L268)
- Modify: `Sources/app/MainMenu.swift` (View 메뉴)
- Modify: `Sources/browser/BrowserViewController.swift` (`BrowserDelegate` 프로토콜, `buildContextMenu`)

**Interfaces:**
- Consumes: `BrowserViewController.selectedURLs() -> [URL]`, `ImageFile(url:)`, `ImageFile.isVideo`, `ImageServiceProtocol`.
- Produces:
  - `final class ComparePaneView: NSView` — `init(file: ImageFile, imageService: ImageServiceProtocol)`, `let imageDisplayView: ImageDisplayView`, `var file: ImageFile`(읽기), `func load()`(이미지 로드 시작).
  - `final class CompareWindowController: NSWindowController` — `init(files: [ImageFile], imageService: ImageServiceProtocol)`, `var onClose: (() -> Void)?`.
  - `BrowserDelegate.browserDidRequestCompare(_ browser: BrowserViewController, urls: [URL])`.
  - `MainWindowController.compareFiles(_ urls: [URL])` (internal helper), `@objc func compareSelected(_ sender: Any?)`.
  - `MainWindowController.ToolbarID.compare = NSToolbarItem.Identifier("compare")`.

- [ ] **Step 1: `ComparePaneView` 작성**

`Sources/viewer/ComparePaneView.swift` 생성. 이미지 표시는 기존 `ImageDisplayView` 재사용, 그 위에 파일명 라벨을 얹는다. (닫기 버튼·활성 테두리는 Task 3/4에서 추가하므로 지금은 골격만.)

```swift
import AppKit

/// 비교 창의 개별 칸 — 이미지(ImageDisplayView 재사용) + 파일명 라벨.
final class ComparePaneView: NSView {
    let imageDisplayView = ImageDisplayView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let imageService: ImageServiceProtocol

    private(set) var file: ImageFile

    init(file: ImageFile, imageService: ImageServiceProtocol) {
        self.file = file
        self.imageService = imageService
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// 이미지를 비동기 로드해 표시한다.
    func load() {
        nameLabel.stringValue = file.name
        Task { [weak self] in
            guard let self else { return }
            let result = await self.imageService.loadImage(at: self.file.url)
            await MainActor.run {
                switch result {
                case .success(let image): self.imageDisplayView.display(image)
                case .failure: self.imageDisplayView.displayError()
                }
            }
        }
    }

    private func setupViews() {
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        imageDisplayView.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.textColor = .secondaryLabelColor

        addSubview(imageDisplayView)
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            imageDisplayView.topAnchor.constraint(equalTo: topAnchor),
            imageDisplayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageDisplayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageDisplayView.bottomAnchor.constraint(equalTo: nameLabel.topAnchor, constant: -2),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }
}
```

- [ ] **Step 2: `CompareWindowController` 작성(그리드 배치)**

`Sources/viewer/CompareWindowController.swift` 생성. `NSGridView`로 칸 수에 맞춰 배치한다. 그리드 배치 규칙은 순수 함수 `compareGridShape(count:)`로 분리해 추론을 쉽게 한다.

```swift
import AppKit

/// 칸 수 → (행, 열) 그리드 형태. 2=1x2, 3=1x3, 4=2x2.
func compareGridShape(count: Int) -> (rows: Int, cols: Int) {
    switch count {
    case ...2: return (1, 2)
    case 3:    return (1, 3)
    default:   return (2, 2)   // 4
    }
}

/// 여러 이미지를 나란히 비교하는 별도 창.
final class CompareWindowController: NSWindowController {
    var onClose: (() -> Void)?

    private let imageService: ImageServiceProtocol
    private var panes: [ComparePaneView] = []
    private let gridView = NSGridView()

    init(files: [ImageFile], imageService: ImageServiceProtocol) {
        self.imageService = imageService

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "비교"
        window.center()
        super.init(window: window)

        self.panes = files.map { ComparePaneView(file: $0, imageService: imageService) }
        setupGrid()
        panes.forEach { $0.load() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupGrid() {
        guard let window else { return }
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        gridView.translatesAutoresizingMaskIntoConstraints = false
        gridView.rowSpacing = 2
        gridView.columnSpacing = 2
        rebuildGrid()
        container.addSubview(gridView)
        window.contentView = container

        NSLayoutConstraint.activate([
            gridView.topAnchor.constraint(equalTo: container.topAnchor),
            gridView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            gridView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    /// 현재 panes로 그리드를 다시 구성한다(칸 추가/제거 시 재호출 — Task 3에서 사용).
    private func rebuildGrid() {
        while gridView.numberOfRows > 0 { gridView.removeRow(at: 0) }

        let shape = compareGridShape(count: panes.count)
        var index = 0
        for _ in 0..<shape.rows {
            var rowViews: [NSView] = []
            for _ in 0..<shape.cols {
                rowViews.append(index < panes.count ? panes[index] : NSView())
                index += 1
            }
            gridView.addRow(with: rowViews)
        }
        // 모든 칸이 균등하게 늘어나도록
        for col in 0..<shape.cols {
            gridView.column(at: col).xPlacement = .fill
        }
        for row in 0..<shape.rows {
            gridView.row(at: row).yPlacement = .fill
        }
        for pane in panes {
            pane.setContentHuggingPriority(.defaultLow, for: .horizontal)
            pane.setContentHuggingPriority(.defaultLow, for: .vertical)
        }
    }
}
```

- [ ] **Step 3: 진입 배선 — ToolbarID·프로퍼티·액션**

`Sources/app/MainWindowController.swift`의 `ToolbarID` enum(약 L31, `sort` 다음 줄)에 추가:

```swift
        static let compare = NSToolbarItem.Identifier("compare")
```

같은 파일에 비교 창 보관 프로퍼티와 액션을 추가(다른 `@objc` 액션들 근처):

```swift
    private var compareWindowController: CompareWindowController?

    /// 선택된 URL들로 비교 창을 연다(2장 이상, 비디오 제외).
    func compareFiles(_ urls: [URL]) {
        let files = urls.compactMap { ImageFile(url: $0) }.filter { !$0.isVideo }
        guard files.count >= 2 else { return }
        let controller = CompareWindowController(files: Array(files.prefix(4)), imageService: ImageService())
        controller.onClose = { [weak self] in self?.compareWindowController = nil }
        controller.showWindow(nil)
        compareWindowController = controller
    }

    @objc func compareSelected(_ sender: Any?) {
        compareFiles(browserVC.selectedURLs())
    }
```

> 참고: `compareFiles`는 `prefix(4)`로 4장 상한을 강제한다(설계: 2~4장).

- [ ] **Step 4: 툴바 아이템 등록**

`Sources/app/MainWindowController+Delegates.swift`의 `toolbarDefaultItemIdentifiers`에서 `ToolbarID.addFolder` 뒤에 추가:

```swift
            ToolbarID.addFolder,
            ToolbarID.compare,
```

같은 파일 `itemForItemIdentifier`의 switch에 case 추가(`addFolder` case 뒤):

```swift
        case ToolbarID.compare:
            item.label = "비교"
            item.toolTip = "선택한 이미지 비교"
            item.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "비교")
            item.action = #selector(compareSelected(_:))
            item.target = self
```

- [ ] **Step 5: 메뉴 + 단축키**

`Sources/app/MainMenu.swift`의 `createViewMenu()`에서 슬라이드쇼 항목 뒤(L130 근처)에 추가:

```swift
        viewMenu.addItem(NSMenuItem.separator())
        let compare = NSMenuItem(title: "비교", action: #selector(MainWindowController.compareSelected(_:)), keyEquivalent: "\\")
        viewMenu.addItem(compare)
```

> 단축키 `Cmd+\`. 기존 단축키와 충돌 없음(확인: o,r,d,S,p,c,v,a,s,[,9,0,+,-,f,m,?,e와 무충돌).

- [ ] **Step 6: 우클릭 컨텍스트 메뉴 + BrowserDelegate**

`Sources/browser/BrowserViewController.swift`의 `BrowserDelegate` 프로토콜 정의에 메서드 추가:

```swift
    func browserDidRequestCompare(_ browser: BrowserViewController, urls: [URL])
```

같은 파일 `buildContextMenu(for urls:)`에서 "복사" 항목 앞(L331 근처)에, 2장 이상일 때만 "비교"를 넣는다:

```swift
        if urls.count >= 2 {
            menu.addItem(withTitle: "비교", action: #selector(contextCompare(_:)), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
        }
```

그리고 `@objc` 핸들러를 다른 context 핸들러 근처에 추가:

```swift
    @objc private func contextCompare(_ sender: NSMenuItem) {
        let urls = selectedURLs()
        guard urls.count >= 2 else { return }
        delegate?.browserDidRequestCompare(self, urls: urls)
    }
```

`Sources/app/MainWindowController+Delegates.swift`의 `BrowserDelegate` extension에 구현 추가:

```swift
    func browserDidRequestCompare(_ browser: BrowserViewController, urls: [URL]) {
        compareFiles(urls)
    }
```

- [ ] **Step 7: 메뉴/툴바 활성화 조건**

`Sources/app/MainWindowController+Actions.swift`의 `validateMenuItem(_:)`(L268)에 비교 액션 분기 추가. 2장 이상 선택 + 비디오 제외 후에도 2장 이상일 때만 활성:

```swift
        if menuItem.action == #selector(compareSelected(_:)) {
            let imageCount = browserVC.selectedURLs()
                .compactMap { ImageFile(url: $0) }.filter { !$0.isVideo }.count
            return imageCount >= 2
        }
```

툴바 아이템 활성화를 위해 같은 파일(또는 MainWindowController)에 `validateToolbarItem` 추가:

```swift
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        if item.itemIdentifier == ToolbarID.compare {
            let imageCount = browserVC.selectedURLs()
                .compactMap { ImageFile(url: $0) }.filter { !$0.isVideo }.count
            return imageCount >= 2
        }
        return true
    }
```

- [ ] **Step 8: 빌드 검증**

Run: `make build`
Expected: 컴파일 성공, 경고·에러 0. (SourceKit의 "Cannot find type" 류는 통짜 빌드 특성상 무시 — `make build` 결과가 기준.)

- [ ] **Step 9: 수동 GUI 검증**

`make run`으로 실행 후:
1. 브라우저에서 이미지 1장만 선택 → View 메뉴 "비교" 비활성, 툴바 비교 아이콘 비활성 확인.
2. 2장 선택 → 4경로 각각 확인: (a) View 메뉴 "비교", (b) `Cmd+\`, (c) 우클릭 "비교", (d) 툴바 아이콘. 각각 비교 창이 좌우 2칸으로 뜨고 두 이미지가 표시되는지.
3. 3장 → 가로 3칸, 4장 → 2x2, 5장 이상 선택 → 앞 4장만.
4. 각 칸에서 스크롤 휠/제스처로 줌이 (독립적으로) 되는지.
5. 창 닫기(빨간 버튼)로 정상 종료.

- [ ] **Step 10: 커밋**

```bash
git add Sources/viewer/ComparePaneView.swift Sources/viewer/CompareWindowController.swift Sources/app/MainWindowController.swift Sources/app/MainWindowController+Delegates.swift Sources/app/MainWindowController+Actions.swift Sources/app/MainMenu.swift Sources/browser/BrowserViewController.swift
git commit -m "feat: 이미지 비교 창 골격 + 진입점(메뉴·단축키·우클릭·툴바)"
```

---

## Task 2: 줌·팬 동기화

한 칸에서 확대/이동하면 모든 칸이 같은 배율·같은 (정규화된) 위치로 따라간다. 상단에 동기화 on/off 토글을 둔다.

**Files:**
- Modify: `Sources/viewer/ImageDisplayView.swift` (변환 콜백·적용 메서드 추가)
- Create: `Sources/viewer/CompareSyncCoordinator.swift`
- Modify: `Sources/viewer/CompareWindowController.swift` (코디네이터 연결 + 토글 UI)

**Interfaces:**
- Consumes: Task 1의 `ComparePaneView.imageDisplayView`, `CompareWindowController.panes`.
- Produces:
  - `ImageDisplayView.onTransformChanged: ((_ magnification: CGFloat, _ centerInImage: CGPoint) -> Void)?` — 줌·팬이 바뀔 때 호출. `centerInImage`는 0~1 정규화된 이미지 내 가시 중심.
  - `ImageDisplayView.applyTransform(magnification: CGFloat, centerInImage: CGPoint)` — 외부에서 변환 적용(콜백을 다시 트리거하지 않음).
  - `ImageDisplayView.normalizedVisibleCenter: CGPoint` (읽기 전용 계산 프로퍼티).
  - `final class CompareSyncCoordinator` — `init(panes: [ComparePaneView])`, `var isEnabled: Bool`.

- [ ] **Step 1: `ImageDisplayView`에 정규화 중심 계산 + 적용 메서드 추가**

`Sources/viewer/ImageDisplayView.swift`에 추가. `imageView`/`scrollView`/`clipView`는 같은 클래스 내부라 접근 가능.

```swift
    // MARK: - 동기화용 변환 노출

    /// 줌·팬이 바뀔 때 호출(외부 동기화용). (배율, 0~1 정규화된 이미지 내 가시 중심)
    var onTransformChanged: ((_ magnification: CGFloat, _ centerInImage: CGPoint) -> Void)?

    /// 동기화 적용 중에는 콜백을 되쏘지 않기 위한 플래그.
    private var isApplyingExternalTransform = false

    /// 현재 가시 영역의 중심을 이미지 좌표 기준 0~1로 정규화한 값.
    var normalizedVisibleCenter: CGPoint {
        let w = imageView.frame.width, h = imageView.frame.height
        guard w > 0, h > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        let center = CGPoint(x: clipView.bounds.midX, y: clipView.bounds.midY)
        return CGPoint(x: center.x / w, y: center.y / h)
    }

    /// 외부(다른 칸)에서 전달된 배율·중심을 적용한다. 콜백은 발생시키지 않는다.
    func applyTransform(magnification: CGFloat, centerInImage: CGPoint) {
        isApplyingExternalTransform = true
        defer { isApplyingExternalTransform = false }

        isFitMode = false
        scrollView.magnification = magnification

        let w = imageView.frame.width, h = imageView.frame.height
        guard w > 0, h > 0 else { return }
        let target = CGPoint(x: centerInImage.x * w, y: centerInImage.y * h)
        let origin = CGPoint(x: target.x - clipView.bounds.width / 2,
                             y: target.y - clipView.bounds.height / 2)
        clipView.setBoundsOrigin(origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    /// 줌·팬 변경을 외부에 알린다.
    private func notifyTransformChanged() {
        guard !isApplyingExternalTransform else { return }
        onTransformChanged?(scrollView.magnification, normalizedVisibleCenter)
    }
```

- [ ] **Step 2: 변경 지점에서 `notifyTransformChanged()` 호출**

`ImageDisplayView`의 줌·팬 변경 경로에 호출을 추가한다.
- `zoomIn()`, `zoomOut()`, `zoomToActualSize()` 끝에 `notifyTransformChanged()` 추가.
- `mouseDragged(with:)`의 `clipView.setBoundsOrigin(origin)` 다음 줄에 `notifyTransformChanged()` 추가.
- `ZoomScrollView`는 private 서브클래스라 콜백 경로가 없다. clipView bounds 변경을 관찰해 처리한다. `observeFrameChanges()`에 이어 `clipView`의 bounds 변경 관찰을 추가:

```swift
    private var clipBoundsObserver: NSObjectProtocol?
```

`setupViews()` 끝(또는 `init`의 `observeFrameChanges()` 뒤)에:

```swift
        clipView.postsBoundsChangedNotifications = true
        clipBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main
        ) { [weak self] _ in
            self?.notifyTransformChanged()
        }
```

`deinit`에서 해제:

```swift
        if let observer = clipBoundsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
```

> bounds 변경 관찰이 휠 줌(magnification 변경 시 clip bounds도 바뀜)과 패닝을 모두 포괄하므로, 명시적 `notifyTransformChanged()` 호출과 중복될 수 있으나 `isApplyingExternalTransform` 가드와 동일 값 재방송은 무해하다.

- [ ] **Step 3: `CompareSyncCoordinator` 작성**

`Sources/viewer/CompareSyncCoordinator.swift` 생성:

```swift
import AppKit

/// 비교 칸들의 줌·팬을 동기화한다. 한 칸의 변환을 나머지 칸에 브로드캐스트.
final class CompareSyncCoordinator {
    var isEnabled = true

    private let panes: [ComparePaneView]
    private var isBroadcasting = false

    init(panes: [ComparePaneView]) {
        self.panes = panes
        for pane in panes {
            pane.imageDisplayView.onTransformChanged = { [weak self, weak pane] mag, center in
                guard let self, let pane else { return }
                self.broadcast(from: pane, magnification: mag, centerInImage: center)
            }
        }
    }

    private func broadcast(from source: ComparePaneView, magnification: CGFloat, centerInImage: CGPoint) {
        guard isEnabled, !isBroadcasting else { return }
        isBroadcasting = true
        defer { isBroadcasting = false }
        for pane in panes where pane !== source {
            pane.imageDisplayView.applyTransform(magnification: magnification, centerInImage: centerInImage)
        }
    }
}
```

- [ ] **Step 4: 비교 창에 코디네이터 + 토글 연결**

`CompareWindowController`에 코디네이터 프로퍼티와 상단 동기화 토글을 추가한다.

프로퍼티:

```swift
    private var syncCoordinator: CompareSyncCoordinator?
    private let syncToggle = NSButton(checkboxWithTitle: "줌·팬 동기화", target: nil, action: nil)
```

`init`에서 panes 구성·load 사이에 코디네이터 생성:

```swift
        self.syncCoordinator = CompareSyncCoordinator(panes: panes)
```

`setupGrid()`를 상단 바(토글) + 그리드 세로 스택으로 바꾼다. container에 toolbar 영역을 추가:

```swift
        syncToggle.translatesAutoresizingMaskIntoConstraints = false
        syncToggle.state = .on
        syncToggle.target = self
        syncToggle.action = #selector(toggleSync(_:))
        container.addSubview(syncToggle)
        // gridView top을 syncToggle.bottom으로 연결, syncToggle은 container.top+8/leading+8 고정
```

토글 액션:

```swift
    @objc private func toggleSync(_ sender: NSButton) {
        syncCoordinator?.isEnabled = (sender.state == .on)
    }
```

> 레이아웃 상세: `syncToggle.top = container.top + 8`, `syncToggle.leading = container.leading + 8`; `gridView.top = syncToggle.bottom + 8`, gridView의 bottom/leading/trailing은 기존대로 container에 고정.

- [ ] **Step 5: 빌드 검증**

Run: `make build`
Expected: 성공, 경고·에러 0.

- [ ] **Step 6: 수동 GUI 검증**

`make run` 후 2장 비교 창을 띄우고:
1. 한 칸에서 휠로 확대 → 다른 칸도 같은 배율로 확대되는지.
2. 한 칸을 드래그(패닝) → 다른 칸도 같은 위치로 이동하는지.
3. 동기화 토글 끄기 → 한 칸만 조작되고 나머지는 그대로인지. 다시 켜기 → 동기화 복귀.
4. 해상도가 크게 다른 두 이미지로 반복 → 중심이 대략 맞는지(완벽 일치는 아님, 설계상 허용).
5. 3장·4장에서도 한 칸 조작이 나머지 전부에 반영되는지.

- [ ] **Step 7: 커밋**

```bash
git add Sources/viewer/ImageDisplayView.swift Sources/viewer/CompareSyncCoordinator.swift Sources/viewer/CompareWindowController.swift
git commit -m "feat: 비교 창 줌·팬 동기화 + on/off 토글"
```

---

## Task 3: 칸 닫기/제거 + 그리드 재배치

각 칸의 닫기(×) 버튼으로 칸을 제거하고 그리드를 다시 배치한다(4→3→2). 2칸이 최소 — 2칸일 때 닫기는 비활성.

**Files:**
- Modify: `Sources/viewer/ComparePaneView.swift` (닫기 버튼 + 콜백)
- Modify: `Sources/viewer/CompareWindowController.swift` (칸 제거 + 재배치, 코디네이터 재구성)

**Interfaces:**
- Consumes: Task 1의 `rebuildGrid()`, `panes`; Task 2의 `CompareSyncCoordinator(panes:)`.
- Produces:
  - `ComparePaneView.onRequestClose: ((ComparePaneView) -> Void)?`
  - `ComparePaneView.setCloseEnabled(_ enabled: Bool)`

- [ ] **Step 1: `ComparePaneView`에 닫기 버튼 추가**

`Sources/viewer/ComparePaneView.swift`에 추가:

```swift
    var onRequestClose: ((ComparePaneView) -> Void)?
    private let closeButton = NSButton()
```

`setupViews()`에서 우상단에 닫기 버튼 배치:

```swift
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .circular
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "닫기")
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])
```

핸들러와 활성 토글:

```swift
    @objc private func closeTapped() { onRequestClose?(self) }

    func setCloseEnabled(_ enabled: Bool) {
        closeButton.isHidden = !enabled
        closeButton.isEnabled = enabled
    }
```

- [ ] **Step 2: 비교 창에서 칸 제거 처리**

`CompareWindowController`의 panes 생성 직후(각 pane에 close 콜백 연결)와 제거 메서드를 추가한다. `init`에서 panes를 만든 뒤:

```swift
        for pane in panes { pane.onRequestClose = { [weak self] p in self?.removePane(p) } }
```

제거 메서드:

```swift
    private func removePane(_ pane: ComparePaneView) {
        guard panes.count > 2, let idx = panes.firstIndex(where: { $0 === pane }) else { return }
        panes.remove(at: idx)
        rebuildGrid()
        syncCoordinator = CompareSyncCoordinator(panes: panes)  // 콜백 재배선
        syncCoordinator?.isEnabled = (syncToggle.state == .on)
        updateCloseButtons()
    }

    /// 2칸이면 닫기 비활성(최소 2칸 유지).
    private func updateCloseButtons() {
        let enabled = panes.count > 2
        panes.forEach { $0.setCloseEnabled(enabled) }
    }
```

`rebuildGrid()` 호출 직후(`setupGrid`와 `init` 양쪽 흐름에서) `updateCloseButtons()`가 한 번 불리도록, `init` 끝에 `updateCloseButtons()` 추가.

> 코디네이터를 통째로 재생성하는 이유: 기존 코디네이터가 제거된 pane을 약참조로 들고 있어 재배선이 가장 단순·안전(YAGNI). pane 수가 최대 4라 비용 무시 가능.

- [ ] **Step 3: 빌드 검증**

Run: `make build`
Expected: 성공, 경고·에러 0.

- [ ] **Step 4: 수동 GUI 검증**

`make run` 후:
1. 4장 비교 → 각 칸 우상단 닫기 버튼 표시. 한 칸 닫기 → 3칸(가로 3)으로 재배치.
2. 또 닫기 → 2칸(좌우)으로. 이 시점에서 닫기 버튼이 사라지는지(2칸 최소).
3. 칸 제거 후에도 남은 칸들의 줌·팬 동기화가 계속 동작하는지(코디네이터 재배선 확인).

- [ ] **Step 5: 커밋**

```bash
git add Sources/viewer/ComparePaneView.swift Sources/viewer/CompareWindowController.swift
git commit -m "feat: 비교 창 칸 닫기 + 그리드 재배치"
```

---

## Task 4: 하단 공용 strip + 활성 칸 교체

비교 창 하단에 후보 썸네일 strip(처음 선택분 + 같은 폴더의 나머지 이미지)을 둔다. 칸을 클릭해 활성화한 뒤 strip 항목을 클릭하면 활성 칸이 그 이미지로 교체된다.

**Files:**
- Create: `Sources/viewer/CompareCandidateStrip.swift` — 가로 후보 썸네일 목록.
- Modify: `Sources/viewer/ComparePaneView.swift` (활성 상태 표시 + 클릭 감지 + 파일 교체)
- Modify: `Sources/viewer/CompareWindowController.swift` (strip 배치, 활성 칸 관리, 후보 풀 구성)

**Interfaces:**
- Consumes: `FileService.contentsOfFolder`(또는 기존 폴더 열거 경로), `ThumbnailCache.shared`, `ImageServiceProtocol.generateThumbnail`, `ImageFile`.
- Produces:
  - `ComparePaneView.onActivated: ((ComparePaneView) -> Void)?`
  - `ComparePaneView.setActive(_ active: Bool)`
  - `ComparePaneView.setFile(_ file: ImageFile)` — 표시 이미지 교체.
  - `final class CompareCandidateStrip: NSView` — `init(files: [ImageFile], imageService:)`, `var onSelect: ((ImageFile) -> Void)?`.

- [ ] **Step 1: 폴더 후보 열거 경로 확인**

구현 전 `Sources/services/FileService.swift`에서 폴더 내 이미지 열거 메서드 시그니처를 확인한다(예: `contentsOfFolder(at:) -> [ImageFile]` 또는 유사). 후보 풀 = (처음 선택분 ∪ 첫 파일의 부모 폴더 이미지), 중복 URL 제거, 비디오 제외.

Run: `grep -n "func contentsOfFolder\|func images\|func enumerate" Sources/services/FileService.swift`
Expected: 폴더 이미지 목록을 반환하는 메서드 1개 이상 확인. 그 시그니처를 Step 4에서 사용.

- [ ] **Step 2: `ComparePaneView` 활성 상태 + 클릭 + 교체**

`Sources/viewer/ComparePaneView.swift`에 추가:

```swift
    var onActivated: ((ComparePaneView) -> Void)?

    func setActive(_ active: Bool) {
        layer?.borderColor = (active ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.borderWidth = active ? 3 : 1
    }

    /// 표시 이미지를 다른 파일로 교체한다.
    func setFile(_ file: ImageFile) {
        self.file = file
        load()
    }

    override func mouseDown(with event: NSEvent) {
        onActivated?(self)
        super.mouseDown(with: event)
    }
```

> 주의: `ImageDisplayView`가 자체 `mouseDown`(패닝/더블클릭)을 갖는다. `ComparePaneView.mouseDown`은 이미지 영역 밖(라벨/여백) 클릭에서만 들어온다. 칸 어디를 클릭해도 활성화되게 하려면, `ComparePaneView`에 클릭 감지용 투명 오버레이 대신 `ImageDisplayView`에 활성화 콜백을 전달하는 편이 확실하다. 따라서 `ImageDisplayView.mouseDown`(L249)의 더블클릭 분기 이전에 `onSingleClick?()` 훅을 추가하고, `ComparePaneView`가 `imageDisplayView.onSingleClick = { [weak self] in self.map { $0.onActivated?($0) } }`로 연결한다.

`ImageDisplayView`에 추가:

```swift
    var onSingleClick: (() -> Void)?
```

`mouseDown(with:)`에서 `clickCount == 2` 처리 뒤, 패닝 시작 직전에:

```swift
        onSingleClick?()
```

- [ ] **Step 3: `CompareCandidateStrip` 작성**

`Sources/viewer/CompareCandidateStrip.swift` 생성. 가로 `NSCollectionView` 또는 간단히 가로 `NSScrollView`+`NSStackView`에 썸네일 버튼을 채운다(YAGNI: 스택 + 버튼).

```swift
import AppKit

/// 비교 후보 이미지를 가로로 나열하는 strip. 항목 클릭 → onSelect.
final class CompareCandidateStrip: NSView {
    var onSelect: ((ImageFile) -> Void)?

    private let scrollView = NSScrollView()
    private let stack = NSStackView()
    private let imageService: ImageServiceProtocol
    private let files: [ImageFile]
    private static let thumbSize = CGSize(width: 72, height: 54)

    init(files: [ImageFile], imageService: ImageServiceProtocol) {
        self.files = files
        self.imageService = imageService
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (i, file) in files.enumerated() {
            let button = NSButton()
            button.bezelStyle = .smallSquare
            button.imageScaling = .scaleProportionallyUpOrDown
            button.title = ""
            button.tag = i
            button.target = self
            button.action = #selector(thumbTapped(_:))
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: Self.thumbSize.width).isActive = true
            button.heightAnchor.constraint(equalToConstant: Self.thumbSize.height).isActive = true
            if let cached = ThumbnailCache.shared.thumbnail(for: file.url) {
                button.image = cached
            } else {
                loadThumb(for: file, into: button)
            }
            stack.addArrangedSubview(button)
        }

        scrollView.documentView = stack
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.heightAnchor, constant: -2),
        ])
    }

    private func loadThumb(for file: ImageFile, into button: NSButton) {
        Task { [weak button] in
            let result = await imageService.generateThumbnail(at: file.url, size: Self.thumbSize)
            if case .success(let image) = result {
                ThumbnailCache.shared.store(image, for: file.url)
                await MainActor.run { button?.image = image }
            }
        }
    }

    @objc private func thumbTapped(_ sender: NSButton) {
        guard files.indices.contains(sender.tag) else { return }
        onSelect?(files[sender.tag])
    }
}
```

- [ ] **Step 4: 비교 창에 strip + 활성 칸 관리**

`CompareWindowController`에 추가:

```swift
    private weak var activePane: ComparePaneView?
    private var candidateStrip: CompareCandidateStrip?
```

후보 풀 구성 헬퍼(첫 파일의 부모 폴더 이미지 ∪ 선택분, 중복 URL 제거, 비디오 제외). Step 1에서 확인한 FileService 메서드를 사용:

```swift
    private func buildCandidates(from files: [ImageFile]) -> [ImageFile] {
        var seen = Set<URL>()
        var result: [ImageFile] = []
        let folderImages: [ImageFile]
        if let parent = files.first?.url.deletingLastPathComponent() {
            folderImages = FileService().contentsOfFolder(at: parent)   // ← Step 1에서 확인한 실제 시그니처로
                .filter { !$0.isVideo }
        } else {
            folderImages = []
        }
        for f in files + folderImages where !seen.contains(f.url) {
            seen.insert(f.url); result.append(f)
        }
        return result
    }
```

`init`에서 각 pane의 활성화 콜백 연결:

```swift
        for pane in panes { pane.onActivated = { [weak self] p in self?.setActivePane(p) } }
```

활성 칸 관리 + strip 선택 처리:

```swift
    private func setActivePane(_ pane: ComparePaneView) {
        activePane?.setActive(false)
        activePane = pane
        pane.setActive(true)
    }

    private func handleCandidateSelected(_ file: ImageFile) {
        let target = activePane ?? panes.first
        target?.setFile(file)
        if let target { setActivePane(target) }
    }
```

`setupGrid()`의 세로 스택을 [토글] → [그리드] → [strip] 3단으로 확장한다. strip 생성·배치:

```swift
        let strip = CompareCandidateStrip(files: buildCandidates(from: panes.map { $0.file }), imageService: imageService)
        strip.onSelect = { [weak self] file in self?.handleCandidateSelected(file) }
        strip.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(strip)
        self.candidateStrip = strip
        // 레이아웃: gridView.bottom = strip.top - 8; strip.leading/trailing = container ±0;
        //          strip.bottom = container.bottom; strip.height = 70 고정.
```

> `gridView.bottom`을 기존 `container.bottom` 고정에서 `strip.top` 기준으로 바꾼다. 초기 활성 칸은 첫 칸으로 두기 위해 `init` 끝에 `panes.first.map { setActivePane($0) }` 추가.

- [ ] **Step 5: 빌드 검증**

Run: `make build`
Expected: 성공, 경고·에러 0. (Step 1에서 확인한 `contentsOfFolder` 시그니처가 다르면 그 자리에서 맞춰 수정.)

- [ ] **Step 6: 수동 GUI 검증**

`make run` 후:
1. 같은 폴더 이미지가 여럿인 상태에서 2장 비교 → 하단 strip에 폴더의 이미지들이 깔리는지.
2. 칸을 클릭 → 그 칸에 강조 테두리(활성)가 생기는지. 다른 칸 클릭 시 활성이 이동하는지.
3. 활성 칸이 있는 상태에서 strip의 다른 이미지 클릭 → 활성 칸이 그 이미지로 교체되는지.
4. 교체 후 그 칸도 줌·팬 동기화에 정상 참여하는지.
5. 칸을 닫아 2칸이 된 뒤에도 교체가 동작하는지.

- [ ] **Step 7: devlog 작성 + 커밋**

`docs/devlog/<오늘 날짜>.md`에 비교 기능 구현 요약을 추가(기존 devlog 형식: 배경·변경 사항·검증). 그 후:

```bash
git add Sources/viewer/CompareCandidateStrip.swift Sources/viewer/ComparePaneView.swift Sources/viewer/CompareWindowController.swift docs/devlog/
git commit -m "feat: 비교 창 후보 strip + 활성 칸 교체"
```

---

## Self-Review 기록

- **Spec 커버리지:** 진입 4경로(Task 1) / 별도 창·2~4 그리드(Task 1) / `ImageDisplayView` 재사용·변환 콜백(Task 2) / 줌·팬 동기화 + 토글(Task 2) / 칸 닫기·재배치(Task 3) / 하단 공용 strip·활성 칸 교체(Task 4). 설계의 2차 항목(드래그&드롭, diff/overlay)은 의도적으로 제외 — 범위 일치.
- **타입 일관성:** `onTransformChanged`/`applyTransform`/`normalizedVisibleCenter`(Task 2) → `CompareSyncCoordinator`(Task 2,3 재생성) → `setFile`/`setActive`/`onActivated`/`onRequestClose`(Task 3,4) 시그니처가 태스크 간 일치.
- **열린 사항:** Task 4 Step 1에서 `FileService`의 폴더 열거 실제 시그니처를 확인 후 `buildCandidates`에 반영(계획에 확인 단계 명시). 동기화 좌표 정밀도는 해상도 차가 클 때 근사 — 설계상 허용, Task 2 검증 4항에서 눈으로 확인.
