import AppKit

// 프로덕션 캐시 디렉터리에 접근하지 않는 테스트 전용 공급자.
extension ThumbnailProvider {
    static let defaultWorkerCount = 2
    static let shared = ThumbnailProvider(workerCount: 2, memoryCache: ThumbnailCache()) { url, _ in NSImage(contentsOf: url) }
}

func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
    ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0, of: type) }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let suite = "jena-category-ui-tests-\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
let store = CategoryStore(defaults: defaults)
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
let firstURL = temporary.appendingPathComponent("a.png")
let secondURL = temporary.appendingPathComponent("b.png")
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
try bitmap.representation(using: .png, properties: [:])!.write(to: firstURL)
try bitmap.representation(using: .png, properties: [:])!.write(to: secondURL)
let first = try store.create(name: "색감", urls: [firstURL])
let second = try store.create(name: "구도", urls: [secondURL])
let controller = MainWindowController(categoryStore: store, settings: AppSettings(defaults: defaults))
controller.sidebarVC.setFolders([temporary])

runTest("사이드바 아이콘 전환과 카테고리 선택이 이미지 목록에 연결된다") {
    let sidebar = controller.sidebarVC
    let buttons = descendants(sidebar.view, of: NSButton.self)
    let categoryButton = buttons.first { $0.toolTip == "카테고리 보기" }!
    categoryButton.performClick(nil)
    check(sidebar.isCategoryView, "카테고리 보기 활성")
    check(controller.browserVC.isCategoryMode, "카테고리 그리드 활성")
    checkEqual(controller.currentCategoryID, first.id, "첫 카테고리 선택")
    let outline = descendants(sidebar.view, of: NSOutlineView.self).first!
    checkEqual(outline.numberOfRows, 5, "즐겨찾기 2행 + 카테고리 그룹과 2행")
    outline.selectRowIndexes(IndexSet(integer: 4), byExtendingSelection: false)
    checkEqual(controller.currentCategoryID, second.id, "다른 카테고리 행 선택")
    checkEqual(controller.window?.title, "구도", "카테고리 이름 표시")
    let folderButton = buttons.first { $0.toolTip == "폴더로 보기" }!
    folderButton.performClick(nil)
    check(!sidebar.isCategoryView, "폴더 보기 복귀")
}

runTest("목록 메뉴의 부분 선택을 누르면 선택 이미지 모두 지정된다") {
    let menu = controller.browserVC.categoryMenuProvider!([firstURL, secondURL])
    let item = menu.items.first { $0.title == "색감" }!
    checkEqual(item.state, .mixed, "일부만 지정된 상태")
    app.sendAction(item.action!, to: item.target, from: item)
    checkEqual(try! store.categories()[0].urls, [firstURL, secondURL], "일괄 추가")
    let updated = controller.browserVC.categoryMenuProvider!([firstURL, secondURL])
    checkEqual(updated.items.first { $0.title == "색감" }?.state, .on, "모두 지정됨 표시")
}

runTest("카테고리 그리드 우클릭에 지정과 분류 해제가 모두 노출된다") {
    controller.showCategory(first.id)
    controller.browserVC.restoreSelection(urls: [firstURL])
    let menu = NSMenu()
    controller.browserVC.menuNeedsUpdate(menu)
    check(menu.items.contains { $0.title == "카테고리 지정" && $0.submenu != nil }, "카테고리 지정 서브메뉴")
    check(menu.items.contains { $0.title == "카테고리에서 빼기" }, "원본 삭제와 별개의 해제 메뉴")
    check(!menu.items.contains { $0.title == "새 폴더" }, "가상 분류에는 폴더 생성 없음")
}

runTest("상세에서 분류 해제해도 상세를 유지하고 돌아오면 목록에 반영된다") {
    controller.showCategory(first.id)
    controller.browser(controller.browserVC, didRequestViewImage: firstURL,
                       inList: [ImageFile(url: firstURL)!, ImageFile(url: secondURL)!])
    let buttons = descendants(controller.viewerVC.view, of: NSButton.self)
    check(buttons.contains { $0.title == "카테고리" }, "상세의 카테고리 버튼")
    let menu = controller.viewerVC.categoryMenuProvider!([firstURL])
    let item = menu.items.first { $0.title == "색감" }!
    app.sendAction(item.action!, to: item.target, from: item)
    checkEqual(controller.contentMode, .viewer, "분류 변경 후에도 상세 유지")
    checkEqual(controller.viewerVC.currentImageURL, firstURL, "현재 이미지 유지")
    controller.viewerDidRequestClose(controller.viewerVC)
    check(controller.browserVC.isCategoryMode, "원래 카테고리로 복귀")
    checkEqual(controller.window?.title, "색감", "원래 제목 복원")
    controller.browserVC.selectAllItems()
    checkEqual(controller.browserVC.selectedURLs(), [secondURL], "해제한 이미지 제외")
    check(FileManager.default.fileExists(atPath: firstURL.path), "원본 파일 보존")
}

runTest("느린 폴더 열거 결과가 이후 선택한 카테고리를 덮지 않는다") {
    controller.navigateToFolder(temporary)
    controller.showCategory(second.id)
    _ = waitUntil(timeout: 0.3) { false }
    check(controller.browserVC.isCategoryMode, "늦은 폴더 결과 무시")
    checkEqual(controller.currentCategoryID, second.id, "카테고리 선택 유지")
    controller.refreshAfterExternalChange()
    check(controller.browserVC.isCategoryMode, "외부 변경 새로고침에도 유지")
}

runTest("카테고리 안에서 이름 변경 시 분류와 그리드가 함께 갱신된다") {
    controller.showCategory(second.id)
    controller.performRename(url: secondURL, newName: "renamed.png")
    let renamed = temporary.appendingPathComponent("renamed.png")
    checkEqual(try! store.categories()[1].urls, [renamed], "저장된 분류 경로 갱신")
    check(controller.browserVC.isCategoryMode, "폴더로 튕기지 않음")
    controller.browserVC.selectAllItems()
    checkEqual(controller.browserVC.selectedURLs(), [renamed], "갱신된 파일 표시")
}

runTest("카테고리 보기에는 이전 폴더로의 파일 붙여넣기를 허용하지 않는다") {
    let item = NSMenuItem(title: "붙여넣기", action: #selector(MainWindowController.pasteFiles(_:)), keyEquivalent: "")
    check(!controller.validateMenuItem(item), "가상 분류에 실제 파일 복사 방지")
}

runTest("북마크와 폴더 이미지 목록에서도 카테고리 지정 메뉴를 제공한다") {
    let browser = controller.browserVC
    browser.displayBookmarks([ImageFile(url: firstURL)!])
    browser.restoreSelection(urls: [firstURL])
    let bookmarkMenu = NSMenu()
    browser.menuNeedsUpdate(bookmarkMenu)
    check(bookmarkMenu.items.contains { $0.title == "카테고리 지정" }, "북마크에서 분류")
    browser.display(folders: [], images: [firstURL])
    browser.restoreSelection(urls: [firstURL])
    let folderMenu = NSMenu()
    browser.menuNeedsUpdate(folderMenu)
    check(folderMenu.items.contains { $0.title == "카테고리 지정" }, "폴더에서 분류")
    check(!browser.isCollectionMode, "폴더 모드 복귀")
}

runTest("카테고리 이미지 이동 후에도 분류와 목록을 유지한다") {
    let destination = temporary.appendingPathComponent("destination")
    try! FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let renamed = temporary.appendingPathComponent("renamed.png")
    controller.showCategory(second.id)
    controller.performMoveToFolder(urls: [renamed], target: destination)
    let moved = destination.appendingPathComponent("renamed.png")
    checkEqual(try! store.categories()[1].urls, [moved], "이동 경로 반영")
    check(controller.browserVC.isCategoryMode, "이동 후에도 카테고리 유지")
    controller.browserVC.selectAllItems()
    checkEqual(controller.browserVC.selectedURLs(), [moved], "새 경로로 목록 조회")
}

runTest("카테고리 이름 변경은 현재 선택과 이미지 목록을 보존하며 메뉴에 반영된다") {
    controller.sidebarVC.setCategoryView(true)
    controller.showCategory(second.id)
    controller.browserVC.selectAllItems()
    let selected = controller.browserVC.selectedURLs()
    try! store.rename(categoryID: second.id, name: "새 구도")
    checkEqual(controller.currentCategoryID, second.id, "분류 선택 유지")
    checkEqual(controller.window?.title, "새 구도", "창 제목 갱신")
    checkEqual(controller.browserVC.selectedURLs(), selected, "이미지 선택 유지")
    let menu = controller.viewerVC.categoryMenuProvider!(selected)
    check(menu.items.contains { $0.title == "새 구도" && $0.state == .on }, "지정 메뉴 이름과 체크 유지")
}

runTest("카테고리 더블클릭은 해당 행의 이름 변경을 요청한다") {
    let sidebar = controller.sidebarVC
    let original = sidebar.onRenameCategory
    var requested: UUID?
    sidebar.onRenameCategory = { requested = $0 }
    defer { sidebar.onRenameCategory = original }
    let outline = descendants(sidebar.view, of: NSOutlineView.self).first!
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    let rect = outline.rect(ofRow: 4)
    let location = outline.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
    let event = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [],
                                  timestamp: 0, windowNumber: controller.window!.windowNumber,
                                  context: nil, eventNumber: 1, clickCount: 2, pressure: 1)!
    outline.mouseDown(with: event)
    checkEqual(requested, second.id, "더블클릭한 카테고리 ID 전달")
}

runTest("우클릭 이름 변경은 선택된 행 대신 우클릭한 카테고리를 대상으로 한다") {
    let sidebar = controller.sidebarVC
    let original = sidebar.onRenameCategory
    var requested: UUID?
    sidebar.onRenameCategory = { requested = $0 }
    defer { sidebar.onRenameCategory = original }
    let outline = descendants(sidebar.view, of: NSOutlineView.self).first!
    let rect = outline.rect(ofRow: 3)
    let location = outline.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
    let event = NSEvent.mouseEvent(with: .rightMouseDown, location: location, modifierFlags: [],
                                  timestamp: 0, windowNumber: controller.window!.windowNumber,
                                  context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
    guard let menu = outline.menu(for: event) else { check(false, "우클릭 메뉴 존재"); return }
    sidebar.menuNeedsUpdate(menu)
    let visible = menu.items.filter { !$0.isHidden }
    checkEqual(visible.map { $0.title }, ["이름 변경"], "카테고리 전용 메뉴")
    guard let item = visible.first, let action = item.action else { return }
    app.sendAction(action, to: item.target, from: item)
    checkEqual(requested, first.id, "우클릭한 카테고리 이름 변경")
}

MainActor.assumeIsolated { runMasonryUITests(directory: temporary) }
MainActor.assumeIsolated { runLibraryDesignTests(directory: temporary) }
MainActor.assumeIsolated { runSimilarityTests(directory: temporary) }

for url in controller.folderWatcher.watchedURLs { controller.folderWatcher.unwatch(url) }
controller.window?.close()
defaults.removePersistentDomain(forName: suite)
try FileManager.default.removeItem(at: temporary)
if failureCount > 0 { exit(1) }
print("all category UI tests passed")
