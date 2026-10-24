# jena-image 기능 계획

> 최종 갱신: 2026-10-24 (v1.8.0 기준). ✅ 완료 · 🔶 부분 구현 · ❌ 미착수.

## v1.0 — 핵심 이미지 뷰어 ✅

1. mac 어플리케이션 이미지 뷰어
2. 이미지 목록에서 이미지 선택시 이미지 뷰어에 이미지 표시
3. 좌측 사이드바에 폴더 트리 구조로 폴더 목록 표시
4. 우측 화면 해당 폴더내 이미지 및 폴더 목록
5. 좌측 사이드에서 폴더 선택시 우측에는 child 폴더와 이미지 목록 표시
6. 이미지 더블 클릭시 이미지 뷰어
7. 이미지 뷰어는 별도의 창이 아닌 우측 화면에 노출되며, 우측 화면에서 우측에는 이미지 보기, 좌측에는 이미지 목록 썸네일 스크롤바
8. 이미지 뷰어에서 확대, 축소 가능
9. 이미지 다른이름으로 저장시 파일 포맷 변환 지원
   - jpg, png, webp, heic, heif, avif, tiff, bmp, gif
10. 이미지 삭제, 이동, 복사 가능
11. 이미지 이동은 드래그로 폴더 지정해서 이동 가능

## v1.1 — 편집 및 비디오 ✅

12. 이미지 편집 (자르기, 리사이즈, 캔버스 조절, 실행취소/재실행)
13. 비디오 재생 지원 (mp4, mov, m4v, avi, mkv)
14. 이미지 뒤집기 (좌우, 상하)

## v1.2 — 전문 포맷 미리보기 ✅

15. PSD, AI, SVG, EPS 파일 미리보기 지원
16. 폴더 아이콘 컬러 커스터마이징
17. 다국어 메뉴 지원

## v1.3 — 외부 연동 및 정보 ✅

### 18. 인쇄 ✅
- 현재 보고 있는 이미지를 ⌘P로 바로 인쇄
- 용지 크기, 방향, 맞춤(Fit to Page) 설정
- NSPrintOperation 활용
- 구현: `MainWindowController.printImage(_:)` — 뷰어는 현재 이미지, 브라우저는 선택 첫 이미지를 `NSPrintOperation`으로 출력. `NSPrintInfo`는 fit 페이지네이션·가운데 정렬, 용지·방향은 인쇄 패널에서 선택.

### 19. 외부 앱으로 열기 (Open With) ✅
- 우클릭 컨텍스트 메뉴 → "다른 앱으로 열기" 하위 메뉴
- 시스템에 등록된 호환 앱 목록 자동 표시
  - 예: PSD → Photoshop, Pixelmator / AI → Illustrator / JPG → 모든 이미지 편집 앱
- NSWorkspace.shared.open(_:withApplicationAt:) 활용
- 기본 앱으로 열기 (더블클릭 시 시스템 기본 앱) 옵션 포함
- 구현: `OpenWithService`가 `NSWorkspace.urlsForApplications(toOpen:)`로 호환 앱을 조회하고(이 앱 제외·중복 제거·이름순), `NSWorkspace.open(_:withApplicationAt:configuration:)`로 연다. 하위 메뉴 맨 위 "기본 앱으로 열기"는 `NSWorkspace.open(_:)`.

### 20. 이미지 정보 패널 (Metadata) ✅
- ⌘I 단축키로 정보 패널 표시
- 기본 정보: 파일명, 파일 크기, 해상도(px), DPI, 색공간, 포맷, 생성일, 수정일
- EXIF 정보 (사진인 경우): 카메라, 렌즈, ISO, 셔터 속도, 조리개, GPS
- CGImageSource / ImageIO 프레임워크 활용
- 구현: `ImageInfoWindowController`(패널) + `ImageMetadataService`(ImageIO 조회). 파일 메뉴 ⌘I, 브라우저 우클릭 "정보 보기", 뷰어에서 다음/이전 이미지로 이동하면 패널이 열려 있을 때 자동 갱신된다. 동영상은 파일 정보만 표시.

## v1.4 — 생산성 향상 (일부 완료)

### 21. 배치 내보내기 ❌
- 브라우저에서 다중 선택 → 일괄 포맷 변환/리사이즈/내보내기
- 진행률 표시
- 현재는 `exportCurrentImage`가 선택 첫 항목 1장만 처리한다.

### 22. 이미지 비교 ✅
- 2장 선택 → 좌우 분할 비교 뷰
- 동기화 줌/팬
- 구현: `CompareWindowController`·`ComparePaneView`·`CompareSyncCoordinator`·`CompareCandidateStrip`. 2~4장 그리드, 후보 strip으로 칸 교체. 상세는 [compare-plan.md](compare-plan.md).

### 23. Quick Look 미리보기 ✅
- 브라우저에서 Space 키로 선택 이미지 빠른 미리보기
- Finder Quick Look과 동일한 UX 패턴

### 24. 슬라이드쇼 ✅
- 전체화면 자동 재생 (간격 조절: 3/5/10초)
- 일시정지, 이전/다음 컨트롤

### 25. 공유 (Share Sheet) ❌
- macOS Share Sheet 연동 (AirDrop, Mail, Messages 등)
- NSSharingServicePicker 활용

### 26. 즐겨찾기 / 태그 🔶
- macOS Finder 태그 연동 또는 자체 즐겨찾기 시스템 — **북마크로 구현 완료**
- 태그별 필터링/검색 — ❌ 미착수
- 상세는 [bookmark-plan.md](bookmark-plan.md).

### 27. 검색 ❌
- 파일명 기반 검색 (현재 폴더 / 전체 폴더)
- 검색 필드는 툴바에 배치

### 28. 클립보드 이미지 저장 ❌
- ⌘V로 클립보드의 이미지를 현재 폴더에 파일로 저장
- 스크린샷 워크플로우에 유용
- 현재 ⌘V(`pasteFiles`)는 클립보드의 **파일 URL** 붙여넣기/잘라내기만 처리한다.

### 29. 이미지 회전 🔶
- 90° 단위 회전 후 저장 지원
- 기존 flip 기능의 자연스러운 확장
- 뷰어 회전(`ImageDisplayView.rotationAngle`)은 **보기 변환만** 하고 저장하지 않는다.
- 에디터의 회전(`ImageEditorWindowController`)은 "다른 이름으로 저장"으로 결과를 저장할 수 있다.

### 30. 최근 폴더 ❌
- 앱 실행 시 최근 열었던 폴더 목록 빠른 접근
- File 메뉴 → "최근 폴더" 하위 메뉴

## 다음 후보 (우선순위 제안)

1. v1.4 저비용 항목 — 최근 폴더(30) · 클립보드 이미지 저장(28) · 공유(25)
2. 규모 있는 항목 — 배치 내보내기(21) · 검색(27)
3. 장기 과제 — [editor-roadmap.md](editor-roadmap.md) Phase 1(비파괴 편집 기반)부터

