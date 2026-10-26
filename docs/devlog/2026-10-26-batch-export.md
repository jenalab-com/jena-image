# 2026-10-26 — 일괄 내보내기

## 범위 (작가 확정)

포맷·품질 + 긴 변 기준 리사이즈(축소만) 두 가지. 비율·상자 맞춤은 제외. 리사이즈는 절대 크기가 아니라 규칙이라 장마다 결과 크기가 달라지는 게 정상이고, 공통인 건 규칙 하나뿐이라는 점을 시트 안내문에 적었다.

## 구현

- `services/BatchExportService.swift`
  - `BatchExportOptions`(format, quality, maxLongEdge?, destination), `BatchExportReport`(succeeded, failed(reason), cancelled).
  - `export(_:options:isCancelled:progress:)` — `Task.detached`에서 순서대로 처리, 장마다 `@MainActor` progress 콜백, 취소 플래그 확인.
  - 디코딩은 `CGImageSourceCreateThumbnailAtIndex` + `WithTransform`(EXIF 방향) + `MaxPixelSize`(긴 변 상한 또는 원본 긴 변). 축소가 디코딩 단계에서 일어나 큰 원본을 통째로 올리지 않는다. ImageIO가 못 여는 SVG·AI·EPS는 `NSImage` → `CGContext` 축소 폴백.
  - 출력 파일명 `outputURL(for:format:in:)` — 원본 이름 + 새 확장자, 겹치면 " 2", " 3"…. 같은 폴더에 같은 포맷으로 내보내도 원본을 덮어쓰지 않는다.
- `app/BatchExportWindowController.swift` — 시트. `ExportAccessoryView`(포맷·품질) 재사용(이를 위해 `quality` setter와 `isEnabled` 추가), 리사이즈 체크박스 + px 필드(16~20000), 저장 폴더(기본 첫 파일의 폴더, NSOpenPanel로 변경), 진행률 바·"n/N 파일명"·취소. 시작 시 컨트롤 잠금, 끝나면 `onFinish(report, destination)`.
- `AppSettings.batchExportResize`·`batchExportLongEdge`(기본 꺼짐·2000) + 기존 `defaultExportFormat`·`defaultExportQuality`에 마지막 선택을 저장.
- `MainWindowController.performBatchExport(urls:)` — 비디오 제외, 시트 1개만. 끝나면 저장 폴더 사이드바 카운트 갱신, 현재 폴더(또는 하위 폴더 포함 보기)면 목록 갱신, 실패가 있으면 성공/실패 수와 파일별 사유(최대 8줄) 경고.
- 진입점: 파일 메뉴 "일괄 내보내기…" ⌥⇧⌘S(브라우저 모드·사이드바 포커스 아님·이미지 1장 이상), 브라우저 우클릭(폴더·북마크·카테고리·검색·유사 모드, 이미지 2장 이상). `BrowserDelegate.browser(_:didRequestBatchExport:)`.
- 다국어 키 `batchExport` 4개 언어. 도움말 갱신.

## 결정

- 메뉴는 1장이어도 활성(설정 한 번 정해 두고 여러 번 쓰는 흐름), 우클릭은 2장 이상(1장은 "다른 이름으로 저장"이 있음).
- 리사이즈 기본은 꺼짐. 켜 두면 모르고 줄이는 사고가 나기 쉽다.
- 메타데이터(EXIF)는 옮기지 않는다. 기존 "다른 이름으로 저장"과 같은 동작. 필요해지면 `kCGImageDestinationMetadata`로 보탤 수 있다.

## 검증

- `make build` 경고·에러 0. `make test`·`make test-ui` 통과.
- 수동
  - [ ] 3장 선택 → ⌥⇧⌘S → 시트. 포맷 WebP·품질 80 → 저장 폴더 기본값이 원본 폴더
  - [ ] 리사이즈 끄고 내보내기 → 원본 픽셀 크기 유지, 확장자만 변경
  - [ ] 리사이즈 2000 켜고 가로 4000·세로 3000·작은 800 섞어 내보내기 → 각각 2000×1500, 1500×2000(세로 사진 긴 변), 800 그대로
  - [ ] EXIF 회전된 사진 → 결과가 바로 선 방향
  - [ ] 같은 폴더·같은 포맷으로 내보내기 → "이름 2.jpg"로 생성, 원본 유지
  - [ ] 진행률 바·파일명 갱신, 취소 → 그때까지 저장된 파일만 남음
  - [ ] 저장 폴더가 현재 폴더면 목록에 바로 나타남, 사이드바 카운트 증가
  - [ ] SVG 섞어 내보내기 → 폴백 경로로 PNG 생성
  - [ ] 읽기 전용 폴더로 내보내기 → 실패 경고에 파일별 사유

## 하네스 검증과 발견 — WebP·HEIF는 쓰기 불가

- 앱 소스 전체 + 임시 `main.swift`를 `swiftc`로 묶어 `BatchExportService`를 실제 파일에 돌렸다(1380×1052 JPG, 300×120 PNG, 긴 변 500).
  - 결과: 큰 쪽 500×381, 작은 쪽 300×120 그대로, 리사이즈 없음은 1380×1052 유지, 같은 포맷 재실행은 `a 2.png`. JPEG·PNG·GIF·BMP·TIFF·HEIC·AVIF 전부 성공.
  - **WebP·HEIF는 `CGImageDestinationCreateWithURL`이 nil** — macOS 14 ImageIO는 둘을 읽기만 한다(`CGImageDestinationCopyTypeIdentifiers`에 없음). 기존 "다른 이름으로 저장"도 같은 API라 원래부터 실패하고 있었다.
- 수정: `ImageFormat.writableFormats`(런타임에 `CGImageDestinationCopyTypeIdentifiers`로 거름). `ExportAccessoryView`는 이 목록만 보여 주고, 저장된 기본 포맷이 쓸 수 없는 것이면 JPEG로 바꾼다. 도움말의 내보내기 포맷 문구 갱신. WebP 쓰기가 꼭 필요하면 libwebp 같은 외부 의존성이 들어가야 해 보류(무의존성 원칙).
- 하네스는 임시 파일(`/tmp/jena-batch`)이라 리포에 넣지 않았다.
