# 2026-10-26 — 최근 폴더 · 클립보드 이미지 저장 · 공유

## 배경

`docs/plan.md`의 "다음 후보 1번"이던 v1.4 저비용 세 항목(30·28·25)을 한 번에 구현했다.
세 기능 모두 기존 흐름(파일 메뉴·⌘V·툴바/우클릭)에 한 자리씩 끼워 넣는 성격이라 새 창이나 서비스 계층은 두지 않았다.

## 변경

### 최근 폴더 (30)
- `AppSettings.recentFolders` — 경로 문자열 배열(`recentFolderPaths`), 최신이 앞, 10개 상한. `addRecentFolder`/`removeRecentFolder`/`clearRecentFolders`.
- `MainWindowController.navigateToFolder`가 들어올 때마다 기록한다(새로고침으로 같은 폴더를 다시 열어도 자리만 앞으로 옮겨져 무해).
- `app/RecentFoldersMenu.swift` — 파일 메뉴 "최근 폴더" 하위 메뉴의 `NSMenuDelegate`. 열릴 때마다 재구성하고, 항목 action은 target 없이 responder chain으로 `MainWindowController.openRecentFolder(_:)`에 닿는다. 폴더 아이콘 16pt, 전체 경로는 툴팁, 맨 아래 "목록 지우기".
- `openRecentFolder`: 폴더가 없어졌으면 경고 뒤 목록에서 제거. 사이드바 루트 아래면 `SidebarViewController.revealFolder(at:)`로 트리를 펼쳐 선택(델리게이트 억제)한 뒤 `navigateToFolder`. 어느 루트에도 없으면 "폴더 추가"와 같이 루트로 등록한다.
- 다국어 키 `recentFolders`·`noRecentFolders`·`clearRecentFolders` 4개 언어 추가.

### 클립보드 이미지 저장 (28)
- `pasteFiles`: 파일 URL이 하나도 없을 때만 `NSImage(pasteboard:)`를 시도. 파일 URL이 있으면 기존 복사/잘라내기 분기가 그대로 우선한다(이 앱의 ⌘C는 URL과 이미지를 함께 쓰므로 순서가 중요).
- `saveClipboardImage(_:to:)` (`+FileOperations`): `ImageService.exportImage(.png)`로 저장. 이름은 "클립보드 이미지 YYYY-MM-DD HH.mm.ss.png", 겹치면 `generateUniqueName`(private → internal)으로 번호. 저장 뒤 `pendingSelectionURLs`에 넣고 `refreshCurrentFolder`, 사이드바 폴더 카운트 갱신.
- `navigateToFolder` 완료 시 `pendingSelectionURLs`가 있으면 그 항목을 선택하고 비운다.
- 메뉴 검증: 붙여넣기는 파일 URL 또는 `NSImage` 읽기 가능 시 활성.
- 포맷은 PNG 고정 — 스크린샷이 주 용도라 무손실이 맞고, 설정의 기본 내보내기 포맷(jpeg)을 따르면 스크린샷 글자가 뭉개진다.

### 공유 (25)
- `app/MainWindowController+Share.swift` — `shareableURLs()`(선택 중 존재하는 미디어 파일만), `share(urls:)`, `NSSharingServicePickerToolbarItemDelegate.items(for:)`, 피커 delegate(표시 중 `sharingPicker` 참조 유지, 선택 후 해제).
- 진입점 3곳: 툴바 `ToolbarID.share`(`NSSharingServicePickerToolbarItem`, 브라우저·뷰어 모두 맨 오른쪽), 파일 메뉴 "공유…"(`validateMenuItem`으로 대상 없으면 비활성), 브라우저 우클릭 "공유…"(폴더 모드·북마크/카테고리/유사 모드 공통, 선택이 모두 미디어 파일일 때. 깨진 북마크 포함 시 숨김).
- 피커 위치: 브라우저는 `BrowserViewController.anchorForSelection()`(첫 선택 셀 프레임), 뷰어는 뷰 전체. 메뉴로 열어도 선택 항목 근처에 뜬다.
- `BrowserDelegate.browser(_:didRequestShare:)` 추가.
- 다국어 키 `share` 4개 언어 추가.

### 문서·도움말
- 도움말 창: 최근 폴더·공유·클립보드 이미지 저장(⌘V) 설명과 단축키 표 갱신.
- `docs/plan.md`: 25·28·30 ✅ + 구현 요약, 다음 후보를 배치 내보내기·검색부터로 정리.

## 결정

- 최근 폴더를 사이드바 루트 밖에서 골랐을 때 **루트로 등록**한다. 등록 없이 열면 사이드바와 브라우저가 따로 놀고, 파일시스템 감시(`syncWatchedFolders`)도 루트 기준이라 반쪽이 된다. 루트였다가 제거한 폴더를 최근에서 고르면 다시 돌아오는 셈인데, 이건 의도된 복귀로 본다.
- 공유 단축키는 두지 않았다. macOS 표준에 없고 ⌘S 계열은 이미 차 있다.
- 버전은 올리지 않았다(릴리스 요청 없음). 릴리스 시 `Makefile`·`Info.plist` 함께.

## 검증

- `make build`: 경고·에러 0. `make test`·`make test-ui`: 전부 통과.
- 수동 GUI 확인 체크리스트
  - [ ] 파일 → 최근 폴더: 폴더 이동 뒤 목록 맨 앞에 뜨는지, 아이콘·툴팁, "목록 지우기"
  - [ ] 최근 폴더에서 하위 폴더 선택 → 사이드바 트리가 펼쳐져 선택되는지 (중복 로드 없이 한 번)
  - [ ] 사이드바에서 제거한 폴더를 최근에서 선택 → 루트로 재등록
  - [ ] 최근 폴더를 Finder에서 지운 뒤 선택 → 경고, 목록에서 사라짐
  - [ ] ⌃⇧⌘4 스크린샷 → 브라우저에서 ⌘V → PNG 생성·선택됨, 사이드바 카운트 +1
  - [ ] Finder에서 파일 ⌘C → ⌘V → 기존처럼 파일 복사(이미지 저장으로 빠지지 않음)
  - [ ] 카테고리·유사 검색 모드에서 ⌘V 비활성
  - [ ] 툴바 공유 버튼: 선택 없으면 비활성, 이미지 선택 시 AirDrop/Mail 등 시트, 뷰어 모드에서도 동작
  - [ ] 우클릭 "공유…": 폴더가 섞이면 숨김, 북마크 모드에서 깨진 북마크 포함 시 숨김
  - [ ] 영어/일본어/중국어 전환 시 메뉴 문자열

## 추가 수정 — 뷰어에서 돌아올 때 사이드바 선택 복귀

- 증상: 하위 폴더 포함 보기에서 이미지를 열면 뷰어가 파일을 넘길 때마다 사이드바가 그 파일을 선택하는데(`didNavigateToFile` → `selectFile`), 더블클릭으로 목록에 돌아와도 그 파일이 선택된 채 남았다.
- 수정: `viewerDidRequestClose`의 폴더 모드 분기에서 `sidebarVC.revealFolder(at: currentFolderURL)`로 선택을 현재 폴더로 되돌린다. 델리게이트를 억제하므로 폴더가 다시 로드되지는 않는다. 북마크·카테고리·유사 검색 모드는 기존 분기 그대로.
- 검증: `make build` 0 경고. 수동 — [ ] 하위 폴더 포함 켜고 이미지 열기 → 더블클릭 복귀 → 사이드바 선택이 폴더로 돌아오는지, 목록 스크롤·선택이 유지되는지.
