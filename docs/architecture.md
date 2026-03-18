# JenaImage — 아키텍처 설계

## 1. 개요

JenaImage는 macOS 네이티브 이미지 뷰어로, Swift + AppKit 기반의 단일 윈도우 애플리케이션이다. 서버/DB 없이 로컬 파일 시스템만을 데이터 소스로 사용한다.

**핵심 설계 원칙:**
- Feature-first 구조 (기능 단위 모듈 분리)
- 의존성은 안쪽으로만 흐른다 (UI → Service → Model)
- 비동기 이미지 로딩 + 캐시로 UI 블로킹 방지
- AppKit 네이티브 컴포넌트 최대 활용

---

## 2. 시스템 구성

```
┌─────────────────────────────────────────────┐
│                  JenaImage                   │
│                                             │
│  ┌─────────┐  ┌──────────┐  ┌───────────┐  │
│  │ Sidebar │  │ Browser  │  │  Viewer   │  │
│  │ Feature │  │ Feature  │  │  Feature  │  │
│  └────┬────┘  └────┬─────┘  └─────┬─────┘  │
│       │            │              │         │
│  ┌────┴────────────┴──────────────┴─────┐   │
│  │          Services Layer              │   │
│  │  FileService  ImageService  Cache    │   │
│  └──────────────────┬───────────────────┘   │
│                     │                       │
│  ┌──────────────────┴───────────────────┐   │
│  │          Models Layer                │   │
│  │  FolderNode  ImageFile  ImageFormat  │   │
│  └──────────────────────────────────────┘   │
│                     │                       │
├─────────────────────┼───────────────────────┤
│  macOS Frameworks   │                       │
│  AppKit · Foundation · ImageIO · UTType     │
└─────────────────────────────────────────────┘
```

---

## 3. 레이어 구조

### 3.1 레이어별 역할

| 레이어 | 역할 | 의존 가능 대상 |
|--------|------|---------------|
| **App** | 앱 생명주기, 윈도우 구성, 메뉴 바인딩 | Feature, Service |
| **Feature (UI)** | ViewController + View. 사용자 입력 처리, 상태 렌더링 | Service, Model |
| **Service** | 비즈니스 로직. 파일 I/O, 이미지 변환, 캐시 관리 | Model, macOS Frameworks |
| **Model** | 데이터 구조체. 순수 값 타입, 프레임워크 의존 없음 | 없음 |

### 3.2 금지 규칙

- Model → Service/Feature 의존 금지
- Service → Feature(UI) 의존 금지
- Feature 간 직접 참조 금지 (이벤트/delegate를 통해 간접 통신)
- ViewController에서 FileManager/ImageIO 직접 호출 금지

---

## 4. 폴더 구조

```
Sources/
  app/
    main.swift                   # NSApplication 엔트리 포인트
    AppDelegate.swift            # 앱 생명주기, 윈도우 생성
    MainWindowController.swift   # NSSplitViewController 구성
    MainMenu.swift               # 메뉴바 구성 및 액션 바인딩

  sidebar/
    SidebarViewController.swift  # NSOutlineView 기반 폴더 트리
    SidebarDelegate.swift        # 폴더 선택/드래그 타겟 처리

  browser/
    BrowserViewController.swift  # NSCollectionView 기반 그리드
    BrowserItem.swift            # 컬렉션 뷰 아이템 (폴더/이미지)
    BrowserDelegate.swift        # 선택, 더블클릭, 컨텍스트 메뉴, 드래그 소스

  viewer/
    ViewerViewController.swift   # 뷰어 모드 컨테이너 (썸네일 스트립 + 이미지 뷰)
    ImageDisplayView.swift       # 확대/축소/패닝 가능한 이미지 뷰
    ThumbnailStripView.swift     # 세로 썸네일 목록

  services/
    FileService.swift            # 폴더 열거, 이동, 복사, 삭제, 이름 변경
    ImageService.swift           # 이미지 로드, 썸네일 생성, 포맷 변환
    ThumbnailCache.swift         # LRU 기반 썸네일 메모리 캐시
    SecurityScopeService.swift   # 앱 샌드박스 보안 스코프 북마크 관리

  models/
    FolderNode.swift             # 폴더 트리 노드 (URL, children, isExpanded)
    ImageFile.swift              # 이미지 파일 (URL, name, fileSize, imageFormat)
    ImageFormat.swift            # 지원 포맷 enum (jpeg, png, webp, heic, ...)
    BrowserContent.swift         # 브라우저 표시 항목 (folder | image) enum
```

---

## 5. 핵심 컴포넌트 설계

### 5.1 MainWindowController — 화면 구성 허브

```
NSSplitViewController
  ├── SidebarViewController      (좌측, 고정 너비 200–300pt)
  └── ContentViewController     (우측, 가변)
        ├── BrowserViewController  (브라우저 모드)
        └── ViewerViewController   (뷰어 모드, 전환)
```

- `NSSplitViewController`로 사이드바/콘텐츠 영역 분할
- 콘텐츠 영역은 브라우저 모드 ↔ 뷰어 모드 전환 (ViewController 교체)
- 모드 전환 시 애니메이션 없이 즉시 교체 (반응성 우선)

### 5.2 SidebarViewController — 폴더 트리

- **뷰**: `NSOutlineView`
- **데이터 소스**: `FolderNode` 트리 구조
- **지연 로딩**: 폴더 펼침 시점에 하위 폴더 로드 (전체 트리 미리 로드하지 않음)
- **드래그 타겟**: `NSOutlineView`의 드래그 앤 드롭 프로토콜 구현
- **이벤트 전달**: delegate 패턴으로 폴더 선택 이벤트를 `MainWindowController`에 전달

### 5.3 BrowserViewController — 이미지/폴더 그리드

- **뷰**: `NSCollectionView` (Flow Layout)
- **데이터 소스**: `[BrowserContent]` — 폴더 먼저, 이미지 다음
- **썸네일 로딩**: `ImageService`로 비동기 로드 → 완료 시 해당 셀만 업데이트
- **다중 선택**: `NSCollectionView` 기본 다중 선택 지원 활용
- **컨텍스트 메뉴**: `NSMenu` 동적 구성 (선택 항목에 따라 메뉴 항목 변경)
- **드래그 소스**: 선택 이미지를 파일 URL로 드래그 제공

### 5.4 ViewerViewController — 이미지 뷰어

- **레이아웃**: `NSSplitView` (좌: `ThumbnailStripView`, 우: `ImageDisplayView`)
- **ImageDisplayView**: `NSScrollView` + `NSImageView`
  - 확대/축소: `magnification` 속성 제어 (10%–500%)
  - 핀치 제스처: `NSMagnificationGestureRecognizer`
  - 패닝: 스크롤 뷰 기본 동작
  - 초기 표시: aspect fit 계산 후 적용
- **ThumbnailStripView**: `NSTableView` (단일 컬럼, 세로 스크롤)
  - 현재 이미지 하이라이트
  - 클릭 또는 ↑↓ 키로 이미지 전환

### 5.5 FileService — 파일 시스템 오퍼레이션

```swift
protocol FileServiceProtocol {
    func contentsOfFolder(at url: URL) -> Result<([URL], [URL]), FileServiceError>  // (folders, images)
    func moveFile(from: URL, to: URL) -> Result<URL, FileServiceError>
    func copyFile(from: URL, to: URL) -> Result<URL, FileServiceError>
    func trashFile(at url: URL) -> Result<Void, FileServiceError>
    func renameFile(at url: URL, newName: String) -> Result<URL, FileServiceError>
}
```

- 모든 파일 오퍼레이션은 `Result` 타입으로 성공/실패 반환
- 파일 충돌 감지는 호출자(Feature)가 사전 확인 후 사용자에게 선택권 제공
- `NSWorkspace.shared.recycle`로 휴지통 이동 (영구 삭제 방지)

### 5.6 ImageService — 이미지 처리

```swift
protocol ImageServiceProtocol {
    func loadImage(at url: URL) async -> Result<NSImage, ImageServiceError>
    func generateThumbnail(at url: URL, size: CGSize) async -> Result<NSImage, ImageServiceError>
    func exportImage(_ image: NSImage, to url: URL, format: ImageFormat, quality: Float) -> Result<Void, ImageServiceError>
    func supportedFormats() -> [ImageFormat]
}
```

- 이미지 로드/썸네일 생성은 `async`로 백그라운드 처리
- `CGImageSource` (ImageIO) 기반 — 모든 지원 포맷 통합 처리
- 썸네일 생성: `CGImageSourceCreateThumbnailAtIndex` 활용 (전체 이미지 디코딩 없이 빠른 썸네일)
- 포맷 변환: `CGImageDestination`으로 대상 UTType 지정하여 저장

### 5.7 ThumbnailCache — 메모리 캐시

```swift
class ThumbnailCache {
    private let cache: NSCache<NSURL, NSImage>
    init(memoryLimit: Int)          // 바이트 단위 상한 (기본 500MB)
    func thumbnail(for url: URL) -> NSImage?
    func store(_ image: NSImage, for url: URL)
    func invalidate(for url: URL)   // 파일 이름 변경/삭제 시
    func clearAll()
}
```

- `NSCache` 기반 — 메모리 압박 시 자동 해제, LRU 정책
- 캐시 키: 파일 URL (파일 이동/삭제 시 해당 키 무효화)
- `countLimit` + `totalCostLimit` 동시 설정

---

## 6. 데이터 흐름

### 6.1 폴더 선택 → 브라우저 표시

```
SidebarViewController
  │ [사용자가 폴더 클릭]
  │ delegate.didSelectFolder(url)
  ▼
MainWindowController
  │ fileService.contentsOfFolder(at: url)
  ▼
FileService
  │ FileManager.contentsOfDirectory → 필터링 → (folders, images) 반환
  ▼
MainWindowController
  │ browserVC.display(folders, images)
  ▼
BrowserViewController
  │ NSCollectionView reloadData
  │ 각 셀에서 imageService.generateThumbnail(url) async 호출
  ▼
ImageService → ThumbnailCache (히트 시 즉시 반환 / 미스 시 생성 후 캐시)
  ▼
BrowserViewController
  │ 셀 업데이트 (썸네일 이미지 설정)
```

### 6.2 이미지 더블 클릭 → 뷰어 모드

```
BrowserViewController
  │ [사용자가 이미지 더블 클릭]
  │ delegate.didRequestViewImage(url, allImages)
  ▼
MainWindowController
  │ 콘텐츠 영역을 ViewerViewController로 전환
  │ viewerVC.display(imageURL, imageList)
  ▼
ViewerViewController
  │ imageService.loadImage(at: url) async → ImageDisplayView에 표시
  │ ThumbnailStripView에 imageList 전달
```

### 6.3 드래그 앤 드롭 이동

```
BrowserViewController (드래그 소스)
  │ [사용자가 이미지 드래그]
  │ NSPasteboardItem에 파일 URL 기록
  ▼
SidebarViewController (드래그 타겟)
  │ [사용자가 폴더에 드롭]
  │ delegate.didDropImages(urls, toFolder)
  ▼
MainWindowController
  │ fileService.moveFile(from:to:) 각 파일에 대해 실행
  │ 충돌 시 → DLG-04 표시
  │ 성공 시 → browserVC에서 해당 항목 제거
  │         → thumbnailCache.invalidate(원본 URL)
```

---

## 7. 상태 관리

### 7.1 상태 분류

| 상태 | 범위 | 소유자 | 수명 |
|------|------|--------|------|
| 현재 선택 폴더 URL | 앱 전역 | MainWindowController | 앱 실행 중 |
| 콘텐츠 모드 (browser/viewer) | 앱 전역 | MainWindowController | 앱 실행 중 |
| 폴더 트리 펼침/접기 상태 | 사이드바 | SidebarViewController | 앱 실행 중 |
| 브라우저 선택 항목 | 브라우저 화면 | BrowserViewController | 폴더 전환 시 리셋 |
| 브라우저 스크롤 위치 | 브라우저 화면 | NSCollectionView | 폴더 전환 시 리셋 |
| 현재 뷰어 이미지 URL | 뷰어 화면 | ViewerViewController | 뷰어 종료 시 소멸 |
| 뷰어 확대/축소 비율 | 뷰어 화면 | ImageDisplayView | 이미지 전환 시 fit으로 리셋 |
| 뷰어 패닝 오프셋 | 뷰어 화면 | NSScrollView | 이미지 전환 시 리셋 |
| 썸네일 캐시 | 앱 전역 | ThumbnailCache (싱글턴) | 앱 실행 중 (LRU 해제) |
| 인라인 편집 상태 | 브라우저 셀 | BrowserItem | 편집 종료 시 소멸 |
| 루트 폴더 경로 | 앱 영속 | UserDefaults + Security Scope Bookmark | 앱 재시작 후에도 유지 |

### 7.2 상태 원칙

- **단일 소유자**: 각 상태는 정확히 하나의 소유자가 관리한다
- **파생 금지**: 동일 데이터를 두 곳에 저장하지 않는다 (예: 선택 폴더의 이미지 수는 저장하지 않고 매번 계산)
- **이벤트 기반 전파**: 상태 변경 시 delegate/notification으로 관심 있는 뷰에만 전파
- **비동기 작업 취소**: 폴더 전환 시 이전 폴더의 진행 중인 썸네일 로딩 작업 취소

---

## 8. 동시성 모델

### 8.1 스레드 정책

| 작업 | 실행 위치 | 이유 |
|------|----------|------|
| UI 업데이트 | Main Thread | AppKit 필수 |
| 폴더 내용 열거 | Background (async) | 대용량 폴더 시 블로킹 방지 |
| 썸네일 생성 | Background (async) | 이미지 디코딩은 CPU 집약적 |
| 이미지 로드 | Background (async) | 대용량 이미지 디코딩 |
| 파일 이동/복사/삭제 | Background (async) | 파일 I/O |
| 포맷 변환 저장 | Background (async) | 인코딩은 CPU 집약적 |

### 8.2 Swift Concurrency 활용

```swift
// 썸네일 로딩 — Task 기반 취소 가능 비동기
func loadThumbnails(for urls: [URL]) {
    currentTask?.cancel()  // 이전 폴더 작업 취소
    currentTask = Task {
        for url in urls {
            guard !Task.isCancelled else { return }
            let thumbnail = await imageService.generateThumbnail(at: url, size: thumbnailSize)
            await MainActor.run {
                updateCell(for: url, with: thumbnail)
            }
        }
    }
}
```

- `Task` + `async/await`로 비동기 처리
- `Task.isCancelled` 체크로 불필요한 작업 조기 종료
- `@MainActor`로 UI 업데이트 보장
- 폴더 전환 시 이전 `Task` 취소 → 스레드/메모리 낭비 방지

---

## 9. Feature 간 통신

Feature(ViewController) 간 직접 참조를 금지하고, `MainWindowController`가 중재자 역할을 한다.

### 9.1 통신 패턴: Delegate

```swift
// Sidebar → MainWindowController
protocol SidebarDelegate: AnyObject {
    func sidebar(_ sidebar: SidebarViewController, didSelectFolder url: URL)
    func sidebar(_ sidebar: SidebarViewController, didReceiveDrop imageURLs: [URL], toFolder: URL)
}

// Browser → MainWindowController
protocol BrowserDelegate: AnyObject {
    func browser(_ browser: BrowserViewController, didRequestViewImage url: URL, inList: [URL])
    func browser(_ browser: BrowserViewController, didRequestDelete urls: [URL])
    func browser(_ browser: BrowserViewController, didRequestMove urls: [URL])
    func browser(_ browser: BrowserViewController, didRequestCopy urls: [URL])
    func browser(_ browser: BrowserViewController, didRequestRename url: URL, newName: String)
    func browser(_ browser: BrowserViewController, didRequestExport url: URL)
}

// Viewer → MainWindowController
protocol ViewerDelegate: AnyObject {
    func viewerDidRequestClose(_ viewer: ViewerViewController)
    func viewer(_ viewer: ViewerViewController, didRequestDelete url: URL)
    func viewer(_ viewer: ViewerViewController, didRequestExport url: URL)
    func viewer(_ viewer: ViewerViewController, didRequestRename url: URL, newName: String)
}
```

### 9.2 통신 흐름

```
SidebarVC ──delegate──▶ MainWindowController ◀──delegate── BrowserVC
                              │
                              │ delegate
                              ▼
                        ViewerVC
```

- `MainWindowController`가 모든 Feature의 delegate를 구현
- Feature 간 직접 참조 없음 → 각 Feature를 독립적으로 테스트 가능

---

## 10. 보안 — 앱 샌드박스

### 10.1 파일 접근 전략

```
최초 실행 → NSOpenPanel으로 루트 폴더 선택
         → Security-Scoped Bookmark 저장 (UserDefaults)
이후 실행 → 저장된 Bookmark으로 접근 권한 복원
         → startAccessingSecurityScopedResource()
앱 종료  → stopAccessingSecurityScopedResource()
```

### 10.2 SecurityScopeService

```swift
class SecurityScopeService {
    func requestFolderAccess() -> URL?           // NSOpenPanel 표시
    func saveBookmark(for url: URL)              // Bookmark 저장
    func restoreBookmark() -> URL?               // 저장된 Bookmark 복원
    func startAccessing(_ url: URL) -> Bool      // 접근 시작
    func stopAccessing(_ url: URL)               // 접근 종료
}
```

- 사용자가 명시적으로 선택한 폴더와 그 하위 폴더만 접근 가능
- Bookmark은 앱 재시작 후에도 유효 (앱 업데이트 시 갱신 필요)

---

## 11. 빌드 시스템

### 11.1 Makefile 기반 빌드

Xcode 프로젝트 없이 `swiftc` 직접 컴파일:

```makefile
APP_NAME     = JenaImage
BUNDLE_ID    = com.jenalab.jenaimage
VERSION      = 1.0.0
BUILD_DIR    = .build
SOURCES      = $(shell find Sources -name '*.swift')
FRAMEWORKS   = -framework AppKit -framework UniformTypeIdentifiers

build:
    @mkdir -p $(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS
    @mkdir -p $(BUILD_DIR)/$(APP_NAME).app/Contents/Resources
    swiftc $(FRAMEWORKS) -O $(SOURCES) -o $(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)
    @cp Info.plist $(BUILD_DIR)/$(APP_NAME).app/Contents/

run: build
    @open $(BUILD_DIR)/$(APP_NAME).app

clean:
    @rm -rf $(BUILD_DIR)

install: build
    @cp -R $(BUILD_DIR)/$(APP_NAME).app ~/Applications/

pkg: build
    pkgbuild --root $(BUILD_DIR) --identifier $(BUNDLE_ID) --version $(VERSION) $(BUILD_DIR)/$(APP_NAME).pkg
```

### 11.2 필수 프레임워크

| 프레임워크 | 용도 |
|-----------|------|
| AppKit | NSWindow, NSViewController, NSOutlineView, NSCollectionView, NSImageView |
| Foundation | FileManager, URL, Data, UserDefaults |
| ImageIO | CGImageSource (이미지 로드/썸네일), CGImageDestination (포맷 변환) |
| UniformTypeIdentifiers | UTType — 이미지 포맷 식별, 드래그 앤 드롭 타입 선언 |
| CoreGraphics | CGImage 처리, 이미지 리사이징 |

---

## 12. ADR (Architecture Decision Records)

### ADR-001: AppKit 선택 (SwiftUI 제외)

**Status:** Accepted

**Context:** macOS 이미지 뷰어는 NSOutlineView (폴더 트리), NSCollectionView (이미지 그리드), NSScrollView (확대/축소 패닝) 등 고급 AppKit 컨트롤에 의존한다.

**Decision:** AppKit을 사용한다. SwiftUI는 사용하지 않는다.

**Rationale:**
- `NSOutlineView`의 트리 구조, 지연 로딩, 드래그 앤 드롭은 SwiftUI `List`/`OutlineGroup`보다 성숙함
- `NSCollectionView`의 대량 셀 재사용, 드래그 소스 기능이 SwiftUI `LazyVGrid`보다 안정적
- `NSScrollView`의 `magnification` 기반 확대/축소가 SwiftUI `ScrollView`보다 정밀 제어 가능
- macOS 14+ 타겟이지만 SwiftUI의 macOS 지원은 여전히 갭이 있음

**Consequences:**
- 선언적 UI의 편의성은 포기
- UIKit/SwiftUI 경험만 있는 개발자의 진입 장벽 존재

---

### ADR-002: Xcode 없이 Makefile + swiftc 빌드

**Status:** Accepted

**Context:** 빠른 반복 개발과 CI 통합을 위해 빌드 시스템을 결정해야 한다.

**Decision:** Xcode 프로젝트 없이 `Makefile` + `swiftc` 직접 빌드를 사용한다.

**Rationale:**
- `.xcodeproj` 파일 관리 불필요 — 소스 파일 추가/삭제가 자유로움
- CLI에서 `make run` 한 줄로 빌드 + 실행
- CI에서 Xcode GUI 없이 빌드 가능
- JenaLab 생태계의 다른 프로젝트(jena-note 등)와 동일한 빌드 패턴

**Consequences:**
- Xcode 디버거, Interface Builder, Instruments 연동이 번거로움 (필요 시 별도 Xcode workspace 구성 가능)
- 코드 서명/Notarization은 별도 스크립트 필요

---

### ADR-003: NSCache 기반 썸네일 캐시 (디스크 캐시 제외)

**Status:** Accepted

**Context:** 1,000개 이상 이미지 폴더에서 스크롤 끊김 없이 썸네일을 표시해야 한다.

**Decision:** `NSCache` 기반 메모리 전용 캐시를 사용한다. 디스크 캐시는 구현하지 않는다.

**Rationale:**
- `NSCache`는 메모리 압박 시 자동 해제 — 별도 LRU 구현 불필요
- `CGImageSourceCreateThumbnailAtIndex`로 썸네일 생성이 충분히 빠름 (전체 디코딩 불필요)
- 디스크 캐시는 캐시 무효화(파일 변경/삭제) 관리 복잡도 대비 이득이 적음
- macOS 앱은 메모리가 상대적으로 여유로움 (500MB 상한이면 충분)

**Consequences:**
- 앱 재시작 시 캐시 콜드 스타트 — 사용자 체감 영향 미미 (빠른 재생성)

---

### ADR-004: Feature 간 통신은 Delegate 패턴

**Status:** Accepted

**Context:** Sidebar, Browser, Viewer 간 이벤트를 전달하는 방법이 필요하다.

**Decision:** Delegate 패턴을 사용하며, `MainWindowController`가 모든 delegate를 구현하는 중재자(Mediator) 역할을 한다.

**Rationale:**
- NotificationCenter보다 타입 안전 — 컴파일 타임에 프로토콜 준수 검증
- Combine/RxSwift 같은 외부 의존성 불필요
- Feature가 3개뿐이므로 Mediator 패턴의 복잡도가 적절
- 각 Feature를 독립적으로 테스트 가능 (mock delegate 주입)

**Consequences:**
- Feature 수가 크게 늘어나면 `MainWindowController`가 비대해질 수 있음 — 현재 범위에서는 문제 없음

---

### ADR-005: Swift Concurrency (async/await) 채택

**Status:** Accepted

**Context:** 이미지 로딩, 파일 I/O를 비동기로 처리해야 한다.

**Decision:** Swift Concurrency (`async/await`, `Task`, `@MainActor`)를 사용한다. GCD는 사용하지 않는다.

**Rationale:**
- macOS 14+ 타겟이므로 Swift Concurrency 완전 지원
- `Task` 취소가 내장되어 있어 폴더 전환 시 불필요한 작업 종료가 간단
- `@MainActor`로 UI 업데이트 스레드 안전성 보장
- 콜백 지옥이나 Combine 체이닝보다 코드 가독성 우수

**Consequences:**
- Actor isolation 관련 컴파일 경고에 주의 필요
