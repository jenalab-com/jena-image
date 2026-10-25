import Foundation

func runCategoryStoreTests() {
    func categoryTest(_ name: String, _ body: (CategoryStore, UserDefaults) throws -> Void) {
        runTest(name) {
            let suite = "jena-category-tests-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            do { try body(CategoryStore(defaults: defaults), defaults) }
            catch { check(false, "예상하지 못한 오류: \(error)") }
        }
    }

    let image = URL(fileURLWithPath: "/images/a.jpg")
    let second = URL(fileURLWithPath: "/other/b.png")

    categoryTest("카테고리 이름과 분류는 저장소 재생성 후에도 유지된다") { store, defaults in
        let category = try store.create(name: "  참고 이미지  ", urls: [image])
        let restored = try CategoryStore(defaults: defaults).categories()
        checkEqual(restored, [category], "재시작 후 순서·ID·경로 보존")
        checkEqual(category.name, "참고 이미지", "이름 앞뒤 공백 제거")
    }

    categoryTest("한 이미지의 여러 카테고리 지정은 서로 독립적이다") { store, _ in
        let first = try store.create(name: "색감", urls: [image])
        let other = try store.create(name: "구도", urls: [image])
        try store.setMembership([image], categoryID: first.id, included: false)
        let result = try store.categories()
        checkEqual(result[0].paths, [], "선택한 카테고리에서만 해제")
        checkEqual(result[1].id, other.id, "다른 카테고리 유지")
        checkEqual(result[1].urls, [image], "다른 분류 보존")
    }

    categoryTest("여러 폴더 이미지를 일괄 지정해도 경로 중복이 생기지 않는다") { store, _ in
        let category = try store.create(name: "모음", urls: [image])
        let alternate = URL(fileURLWithPath: "/images/sub/../a.jpg")
        try store.setMembership([image, alternate, second, second], categoryID: category.id, included: true)
        checkEqual(try store.categories()[0].urls, [image, second], "정규화된 고유 경로")
        try store.setMembership([alternate, second], categoryID: category.id, included: false)
        checkEqual(try store.categories()[0].paths, [], "일괄 해제")
    }

    categoryTest("빈 이름과 중복 이름 거절 시 기존 분류를 보존한다") { store, defaults in
        _ = try store.create(name: "Reference", urls: [image])
        let before = defaults.data(forKey: CategoryStore.storageKey)
        for name in [" \n ", " reference "] {
            do { _ = try store.create(name: name); check(false, "잘못된 이름 거절") }
            catch is CategoryStoreError { }
        }
        checkEqual(defaults.data(forKey: CategoryStore.storageKey), before, "저장 내용 보존")
    }

    categoryTest("없는 원본도 복원 시 분류에서 자동으로 지우지 않는다") { store, defaults in
        let missing = URL(fileURLWithPath: "/unmounted-\(UUID().uuidString)/a.jpg")
        _ = try store.create(name: "외장 디스크", urls: [missing])
        checkEqual(try CategoryStore(defaults: defaults).categories()[0].urls, [missing], "연결 해제된 경로 보존")
    }

    categoryTest("폴더 이동은 하위 분류 경로만 바꾸고 비슷한 접두사는 보존한다") { store, _ in
        let unrelated = URL(fileURLWithPath: "/images-extra/a.jpg")
        _ = try store.create(name: "모음", urls: [image, unrelated, second])
        try store.relocate(from: URL(fileURLWithPath: "/images"), to: URL(fileURLWithPath: "/moved"))
        checkEqual(try store.categories()[0].paths, ["/moved/a.jpg", unrelated.path, second.path], "폴더 경계 인식")
        try store.relocate(from: second, to: URL(fileURLWithPath: "/other/renamed.png"))
        checkEqual(try store.categories()[0].paths.last, "/other/renamed.png", "파일 이름 변경 반영")
    }

    categoryTest("명시적으로 삭제한 원본만 모든 카테고리에서 제거한다") { store, _ in
        _ = try store.create(name: "첫째", urls: [image, second])
        _ = try store.create(name: "둘째", urls: [image])
        try store.removeDeletedFile(at: URL(fileURLWithPath: "/images"))
        let result = try store.categories()
        checkEqual(result[0].urls, [second], "다른 원본은 유지")
        checkEqual(result[1].paths, [], "빈 카테고리도 유지")
        checkEqual(result.count, 2, "카테고리 자동 삭제 금지")
    }

    categoryTest("손상된 분류 데이터를 빈 목록으로 덮어쓰지 않는다") { store, defaults in
        let original = Data("unreadable category data".utf8)
        defaults.set(original, forKey: CategoryStore.storageKey)
        do { _ = try store.create(name: "새 카테고리"); check(false, "손상 시 생성 거절") }
        catch CategoryStoreError.unreadableData { }
        do { try store.relocate(from: image, to: second); check(false, "손상 시 갱신 거절") }
        catch CategoryStoreError.unreadableData { }
        checkEqual(defaults.data(forKey: CategoryStore.storageKey), original, "원래 바이트 보존")
    }

    categoryTest("카테고리 이름 변경 후 ID·이미지·순서와 재실행 복원이 유지된다") { store, defaults in
        let first = try store.create(name: "기존", urls: [image, second])
        let other = try store.create(name: "다른 분류", urls: [image])
        try store.rename(categoryID: first.id, name: "  새 이름  ")
        let restored = try CategoryStore(defaults: defaults).categories()
        checkEqual(restored[0].id, first.id, "동일한 카테고리 유지")
        checkEqual(restored[0].name, "새 이름", "이름 저장")
        checkEqual(restored[0].urls, first.urls, "지정 이미지 유지")
        checkEqual(restored[1], other, "다른 분류 보존")
        try store.rename(categoryID: first.id, name: "새 이름")
        checkEqual(try store.categories(), restored, "자기 이름은 중복 오류 아님")
    }

    categoryTest("잘못된 이름 변경은 기존 이름과 이미지 지정을 보존한다") { store, defaults in
        let first = try store.create(name: "First", urls: [image])
        _ = try store.create(name: "Second", urls: [second])
        let before = defaults.data(forKey: CategoryStore.storageKey)
        for name in [" ", " second "] {
            do { try store.rename(categoryID: first.id, name: name); check(false, "이름 거절") }
            catch is CategoryStoreError { }
        }
        do { try store.rename(categoryID: UUID(), name: "Missing"); check(false, "없는 분류 거절") }
        catch CategoryStoreError.missingCategory { }
        checkEqual(defaults.data(forKey: CategoryStore.storageKey), before, "원래 데이터 보존")
    }

    categoryTest("카테고리 지정은 기존 북마크와 등록 폴더를 변경하지 않는다") { store, defaults in
        defaults.set([image.path], forKey: "imageBookmarks")
        defaults.set(["/images"], forKey: "rootFolderPaths")
        _ = try store.create(name: "새 분류", urls: [second])
        checkEqual(defaults.stringArray(forKey: "imageBookmarks"), [image.path], "북마크 보존")
        checkEqual(defaults.stringArray(forKey: "rootFolderPaths"), ["/images"], "폴더 보존")
    }
}
