# 2026-10-16 — 스파이크: iCloud 비워진 파일 + QLThumbnailGenerator (Task 0)

## 질문
비워진(evicted) iCloud Drive 파일에 `QLThumbnailGenerator`(`.thumbnail` 표현)를 요청하면 원본을 내려받지 않고 그림을 주는가. 그리고 스펙의 전제 "`CGImageSourceCreateWithURL`은 다운로드를 유발한다"가 실제로 맞는가.

## 방법
- 대상: `~/Library/Mobile Documents/com~apple~CloudDocs/JenaImage-spike/sample.jpg` (1102×826 JPEG, 212KB). 사용자 원본은 건드리지 않고 `Downloads/IMG_0079.JPG`를 임시 폴더에 복사 → 업로드 완료(`ubiquitousItemIsUploaded=true`) 확인 → `brctl evict`.
- 스크립트 3개(`/tmp/spike-icloud/`, 커밋 안 함): `spike`(QL 요청), `cg`(ImageIO 요청), `status`(상태만 읽음). **상태 확인은 매번 새 프로세스로** — 아래 함정 때문.
- 환경: macOS 26 (Darwin 25.5.0), Swift 6.3.3.

## 결과

| 단계 | 결과 | 상태(새 프로세스) | allocated |
|---|---|---|---|
| evict 직후 | — | NotDownloaded | 0 |
| QuickLook `.thumbnail` 220pt@2x | **440×330, 0.68s**(첫 호출) / 0.01s(반복, QL 캐시) | **NotDownloaded** | **0** |
| `CGImageSourceCreateThumbnailAtIndex` | 440×330, 0.98s | **Current** | 212992 |

- QuickLook은 iCloud 측 썸네일을 받아온다. 원본은 로컬에 내려오지 않는다(`fileAllocatedSize` 0 유지).
- ImageIO는 dataless 파일을 읽는 순간 OS가 원본을 내려받는다. 스펙 §목적 4번 전제 확인.
- 첫 QL 호출 0.7~0.9초는 네트워크 비용. 2초 기준 아래이므로 QL 전용 워커 분리는 하지 않는다. 다만 보이는 셀에서만, 선로드에선 부르지 않는다는 원칙은 유지.

## 결정
**`useQuickLookForEvicted = true`.** Task 2 Step 9를 실행한다(`QuickLookThumbnailing` 프레임워크 추가, `quickLookThumbnail` 본문 채움).

## 발견한 함정 (Task 2·6에 반영)
1. **`URL.resourceValues`는 프로세스 안에서 캐시된다.** 같은 `URL` 인스턴스로 다시 읽으면 옛 값이 돌아온다. 캐시는 런루프 끝에서 비워지는데, 스파이크처럼 런루프가 없는 프로세스와 **앱의 워커 스레드**에서는 비워지지 않는다. 첫 측정에서 CG 실행 뒤에도 `NotDownloaded`로 보였던 이유가 이것. → `isEvictedICloudItem`·`fileStamp`·`sourceStamp`는 읽기 전에 `URL(fileURLWithPath: url.path)`로 새 인스턴스를 만들거나 `removeAllCachedResourceValues()`를 부른다. 안 그러면 뷰어에서 내려받은 뒤에도 그리드가 계속 "미다운로드"로 보이고, Finder에서 파일을 수정해도 mtime이 그대로 보여 디스크 캐시가 갱신되지 않는다.
2. **macOS 26에선 비워진 파일이 `.icloud` 자리표시 파일로 보이지 않는다.** 원래 이름 그대로 dataless 파일이고, `fileSize`는 원본 크기를 그대로 돌려준다(`fileAllocatedSize`만 0). 그래서 (a) 파일명으로 판별하면 안 되고(스펙 §1.4 그대로 메타데이터로), (b) `sourceStamp`(mtime·size)는 비워진 파일에서도 정상이라 디스크 캐시 적중이 된다(스펙 §1.4 "디스크 캐시에 있으면 그걸 쓴다" 성립).

## 정리
- 임시 iCloud 폴더 `JenaImage-spike/`와 `/tmp/spike-icloud/`는 삭제.
