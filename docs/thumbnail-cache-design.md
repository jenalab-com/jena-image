# 썸네일 캐시 재설계 — 보이는 셀 우선 · 병렬 · 디스크 캐시

작성일: 2026-10-15

## 목적

하위 폴더 포함 보기에서 2만 장 이상을 열면 썸네일 생성에 수 분이 걸리고, 메모리 한도에
밀려 다 보이지도 않는다. 원인은 세 가지다.

1. **전체 순차 생성** — 목록 앞에서부터 한 장씩 돈다. 화면 밖 셀도 같은 순서로 기다린다.
2. **직렬** — 한 번에 한 장만 디코딩한다.
3. **메모리만** — 500MB 한도(440px 기준 약 660장)를 넘으면 LRU로 밀려 재생성한다.
   앱을 다시 켜면 전부 처음부터다.
4. (발견) **iCloud 비워진 파일** — `CGImageSourceCreateWithURL`이 원본 다운로드를
   유발한다. iCloud Drive 폴더에서는 사실상 폴더 전체를 내려받는 셈이다.

목표: 스크롤 중인 화면이 2초 안에 채워지고, 앱을 다시 켜도 썸네일이 즉시 뜬다.
iCloud 폴더를 훑어도 원본을 몰래 내려받지 않는다.

## 핵심 결정 (확정)

| 항목 | 결정 |
|---|---|
| 구조 | `ThumbnailProvider` 신설. 메모리·디스크·생성 큐를 한곳에 품고, 셀이 "당겨 가는" 방식 |
| 우선순위 | 보이는 셀 → 앞뒤 2화면 선로드 → 그 밖은 요청 시에만 (유휴 시 전체 완주는 안 함) |
| 병렬 | 워커 `activeProcessorCount - 1`, 최소 2 · 최대 8 |
| 디스크 캐시 위치 | 로컬 한곳 `~/Library/Caches/com.jenalab.jenaimage/thumbs/`. 외부 볼륨·iCloud 파일도 여기 |
| 디스크 한도 | 기본 2GB, 설정 탭 슬라이더 500MB~8GB (500MB 단위). "적용" 없이 즉시 반영 |
| 저장 포맷 | HEIC (440px 약 40~80KB) |
| 생성 중 표시 | 스켈레톤 (연한 회색 둥근 사각, 숨 쉬듯 밝기 반복) |
| iCloud 비워진 파일 | 자동 다운로드 안 함. iCloud 썸네일(스파이크로 확인) 또는 자리표시. 뷰어로 열 때만 내려받음 |
| 생성 백엔드 | 기존 `ImageService.generateImageThumbnailSync` 유지. `QLThumbnailGenerator`는 iCloud 비워진 파일 전용 후보 |

## 1. 구조

```
BrowserViewController / ThumbnailStripView / CompareCandidateStrip
        │ request(url, minPixel, priority) → token
        │ cancel(token)
        ▼
ThumbnailProvider (shared)
  ├─ 메모리 계층: ThumbnailCache (기존, 승격 규칙 유지)
  ├─ 디스크 계층: ThumbnailDiskStore (2단계)
  └─ 생성 큐:     ThumbnailScheduler (우선순위 큐 + 워커 풀)
                      └─ ImageService.generateImageThumbnailSync
```

### 1.1 ThumbnailProvider

- `Sources/services/ThumbnailProvider.swift`. 앱에 하나(`shared`).
- API:
  ```swift
  enum Priority { case visible, prefetch, background }
  struct RequestToken: Hashable { let id: UInt64 }

  func request(_ url: URL, minPixel: Int, priority: Priority,
               completion: @escaping @MainActor (ThumbnailResult) -> Void) -> RequestToken
  func cancel(_ token: RequestToken)
  func invalidate(for url: URL)      // 메모리 계층만
  func clearMemory()                 // 설정 "적용" 때
  func clearDisk()                   // 설정 "비우기" 버튼
  ```
- `ThumbnailResult`: `.image(NSImage)` / `.failed` / `.notDownloaded`.
- 조회 순서: 메모리 → 디스크 → 생성. 어느 단계에서 찾든 위 계층에 채운다.
- 같은 `(url, minPixel)`을 여러 곳이 요청하면 생성은 한 번, 완료는 전부에게.
- 생성 실패는 `(url, mtime)`별로 기억해 같은 세션에서 재시도하지 않는다. mtime이 바뀌면 다시 시도한다.

### 1.2 ThumbnailScheduler

- 우선순위 큐. `visible` > `prefetch` > `background`. 같은 우선순위 안에서는 늦게 들어온
  요청이 먼저다(스크롤이 멈춘 자리가 가장 최근 요청이므로).
- 워커 풀은 `DispatchQueue(attributes: .concurrent)` + 세마포어가 아니라 명시적 워커 수
  N개의 루프로 둔다. 취소된 요청은 꺼낼 때 버린다.
- 요청 하나의 수명: 큐 대기 → 워커가 꺼냄 → 디스크 조회 → (없으면) 생성 → 메모리·디스크 저장 → 완료 콜백(메인).

### 1.3 셀 쪽 흐름 (당겨 가기)

- `BrowserViewController`
  - `collectionView(_:willDisplay:forRepresentedObjectAt:)`에서 `.visible`로 요청하고 토큰을 `BrowserItem`에 보관.
  - `collectionView(_:didEndDisplaying:forRepresentedObjectAt:)`에서 취소.
  - `NSScrollView.didEndLiveScrollNotification` + 0.1초 디바운스 → 보이는 범위 앞뒤 2화면 분량을 `.prefetch`로 요청. 다음 선로드 때 이전 선로드 토큰은 모두 취소.
  - 기존 `loadThumbnails` 루프, `thumbnailTask`, `updateCellThumbnail`은 제거.
  - `display(...)` / `displayBookmarks(...)` 진입 시 보류 중인 모든 토큰 취소.
- `ThumbnailStripView`, `CompareCandidateStrip`: `imageService.generateThumbnail` 호출을 Provider 요청으로 교체. 스켈레톤은 넣지 않는다(80×60이라 즉시 뜸).

### 1.4 iCloud 처리

- 요청마다 `URL.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])`를 읽는다. 다운로드를 유발하지 않는 메타데이터 조회다. 폴더 경로로 판별하지 않는다(데스크톱·문서 동기화 시 `~/Desktop`도 iCloud).
- `isUbiquitousItem == false` 또는 상태 `.current`/`.downloaded`: 일반 경로.
- `.notDownloaded`:
  - 디스크 캐시에 있으면 그걸 쓴다(가장 흔한 좋은 경우).
  - `visible` 요청: iCloud 측 썸네일 경로(스파이크 결과에 따라 `QLThumbnailGenerator`)를 시도. 없으면 `.notDownloaded` 반환.
  - `prefetch` 요청: 건너뛴다. 큐에 넣지 않는다.
  - 어느 경우에도 `CGImageSourceCreateWithURL`·`NSImage(contentsOf:)`를 부르지 않는다.
- **스파이크(1단계 착수 전, 30분)**: 비워진 iCloud 파일에 `QLThumbnailGenerator`(`.thumbnail` 표현)가 원본 다운로드 없이 그림을 주는지 확인. 확인 방법: 비워둔 파일로 요청 뒤 `ubiquitousItemDownloadingStatus`가 그대로 `.notDownloaded`인지, 결과 이미지가 왔는지. 결과는 devlog에 기록. 안 되면 자리표시만.

## 2. 디스크 캐시 키와 무효화 (2단계)

### 2.1 키

- 파일명: `<pathHash16>_<mtimeSec>_<fileSize>_<px>.heic`
  - `pathHash16`: 경로 문자열 SHA-256의 앞 16 hex
  - `mtimeSec`: 수정시각 정수 초
  - `fileSize`: 바이트
  - `px`: 요청 크기 단계 220/330/440
- 하위 폴더: `pathHash16` 앞 2자. 한 디렉터리에 수만 개 쌓이는 걸 피한다.
- 조회: 요청 시 파일 `mtime`·`size`를 읽어 키를 만들고 존재 여부만 본다. 디스크 캐시에 있는 큰 크기(440)가 작은 요청(220)도 만족하므로, 요청 px 이상의 항목이 있으면 그걸 쓴다.

### 2.2 무효화 표

| 상황 | 처리 |
|---|---|
| 파일 수정 | mtime 변경 → 키가 달라짐. 옛 항목은 GC |
| 파일 삭제 | 아무것도 안 함. 옛 항목은 GC |
| 파일 추가 | 새 요청이 생성 → 저장 |
| 앱 내 이름 변경·이동 | 경로 변경 → 재생성. 옛 항목은 GC |
| 설정 "적용"(크기 변경) | px가 키에 있어 공존. 디스크는 비우지 않음. 메모리만 `clearMemory()` |
| 편집기 저장 후 `reloadCurrentImage` | 메모리 `invalidate(for:)` 유지. 디스크는 mtime으로 분리 |
| 설정 "비우기" | 디렉터리 전체 삭제 + 누적 바이트 0 |

기존 5곳의 `ThumbnailCache.shared.invalidate(for:)` 호출은 `ThumbnailProvider.shared.invalidate(for:)`로 이름만 바꾸고 의미(메모리만)는 유지한다.

### 2.3 GC

- 누적 바이트를 메모리 변수로 추적. 저장 시 더하고, 삭제 시 뺀다.
- 한도 초과 시: 접근시각 오래된 순으로 한도의 90%까지 삭제. 접근시각은 디스크 조회 적중 시 파일 `modificationDate`를 현재로 갱신해 기록한다(별도 메타 파일 없음).
- 앱 시작 30초 뒤 백그라운드로 디렉터리를 한 번 훑어 누적 바이트를 다시 센다. 비정상 종료로 어긋난 수치 보정.
- 삭제 작업은 utility QoS 큐에서, 요청 처리와 겹치지 않게 직렬로.

### 2.4 설정 탭

- 기존 메모리 슬라이더 아래에 추가: "디스크 캐시" 슬라이더(500MB~8GB, 500MB 단위, 1024 이상 GB 표기), "사용 중 n" 라벨, "비우기" 버튼.
- `AppSettings.thumbnailDiskCacheMB` (기본 2048, 범위 500...8192).
- 디스크 한도 변경은 즉시 반영. 줄이면 GC가 바로 돈다.
- 다국어 라벨 4종(기존 탭과 동일 체계).

## 3. 셀 상태와 스켈레톤, 오류 처리

### 3.1 BrowserItem 상태

| 상태 | 표시 |
|---|---|
| 로딩 중 | `thumbnailView` 위 `CALayer`. 배경 `quaternaryLabelColor`, 모서리 6pt, 불투명도 0.6→1.0→0.6을 1.6초 주기 반복. 이름·경로 줄·배지는 그대로 |
| 완료 | 스켈레톤 0.15초 페이드아웃 후 이미지. 메모리 적중은 페이드 없이 즉시 |
| 실패 | 스켈레톤 걷고 `photo` 심볼, `tertiaryLabelColor` |
| iCloud 미다운로드 | 스켈레톤 걷고 `icloud.and.arrow.down` 심볼, `tertiaryLabelColor` |
| 깨진 북마크(기존) | `exclamationmark.triangle` 유지 |

- 스켈레톤 애니메이션은 공유 `CABasicAnimation` 객체 하나를 재사용해 셀 간 동기화. GPU 부담과 산만함을 같이 줄인다.
- 폴더 셀, 비디오 셀(`film` 심볼 기본)은 지금과 동일.

### 3.2 셀 재사용 안전

- `prepareForReuse`: 보관 토큰 취소, 스켈레톤으로 복귀.
- 완료 콜백: 셀의 현재 URL이 요청 URL과 같을 때만 그린다.

### 3.3 오류 처리

- 생성 실패: 실패 상태 표시. `(url, mtime)`별 기억으로 세션 내 재시도 없음.
- 디스크 쓰기 실패(가득 참·권한): 메모리 계층만으로 계속. 세션당 한 번 `NSLog`. 경고창 없음.
- 디스크 읽기에서 깨진 HEIC: 항목 삭제 후 생성 경로로.
- 디스크 캐시 디렉터리 생성 실패: 디스크 계층 비활성, 이후 동작은 1단계와 동일.

## 4. 단계와 작업 순서

**0. 스파이크** — iCloud 비워진 파일 + `QLThumbnailGenerator` 확인(§1.4). 결과를 devlog에.

**1단계: Provider + 보이는 셀 우선 + 병렬 + 스켈레톤**
1. `ThumbnailProvider`, `ThumbnailScheduler` 신설. 메모리 계층은 기존 `ThumbnailCache`.
2. `BrowserItem` 스켈레톤·실패·미다운로드 상태.
3. `BrowserViewController` 당겨 가기 전환. iCloud 상태 판별 포함.
4. 뷰어 스트립·비교 스트립 호출 교체. 기존 `invalidate` 호출처 이름 교체.

**2단계: 디스크 캐시**
5. `ThumbnailDiskStore` 신설(키·GC·누적 바이트).
6. Provider 조회 순서에 디스크 삽입.
7. 설정 탭 슬라이더·사용량·비우기. `AppSettings` 키.

각 단계 끝은 빌드되고 쓸 수 있는 상태여야 한다.

## 5. 테스트

### 5.1 자동 (UI 없는 순수 로직)

- `Makefile`에 `test` 타깃 추가. `Tests/` 아래 파일 + 필요한 `Sources/services` 파일을 `swiftc`로 빌드해 실행하는 단순 실행 파일(XCTest 없음, 실패 시 비정상 종료).
- 대상:
  - Scheduler: 우선순위 순서, 같은 우선순위 내 최신 우선, 취소된 요청 폐기, 같은 URL 중복 요청 합치기, 워커 수 상한.
  - DiskStore: 키 생성(경로·mtime·size·px), 더 큰 px 적중, GC 삭제 순서와 90% 목표, 누적 바이트 추적, 재계산.
  - 임시 디렉터리에 가짜 파일 생성. 이미지는 작은 `CGImage`를 코드로 만들어 사용.

### 5.2 수동 GUI (devlog에 그대로 기록)

1. 2만 장 폴더: 첫 화면이 2초 안에 채워진다.
2. 끝까지 휙 넘기면 멈춘 자리부터 채워진다.
3. 스켈레톤이 보이고, 다른 파일 썸네일이 섞여 보이지 않는다.
4. 앱 재시작 후 즉시 뜬다(2단계).
5. Finder에서 파일 수정·삭제가 반영된다.
6. 설정에서 디스크 비우기 후 다시 채워진다(2단계).
7. iCloud 비워진 파일을 훑어도 다운로드 상태가 바뀌지 않는다. 뷰어로 열면 내려받는다.
8. 메모리 한도 "적용"이 지금처럼 동작한다.

## 6. 건드리지 않는 것

썸네일 크기 3단계, 메모리 한도 슬라이더와 "적용" 동작, 북마크 그리드, 하위 폴더 포함 보기의 경로 줄, `ImageService`의 생성 로직 자체.

## 7. 열린 후속 (이번 범위 밖)

- 외장 디스크·NAS에서 I/O 병목 시 볼륨별 워커 수 조정. 측정 후 판단.
- 유휴 시 전체 완주(`.background` 우선순위는 API에만 두고 이번엔 쓰지 않음).
- iCloud 비워진 파일의 "보이는 셀만 자동 다운로드" 옵션.
