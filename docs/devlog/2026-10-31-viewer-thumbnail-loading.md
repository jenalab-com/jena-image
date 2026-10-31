# 상세 로딩을 확대된 썸네일 미리보기로 변경

## 요청

로딩 문구만 표시하는 대신 어떤 이미지를 열고 있는지 인지할 수 있도록, 작은 썸네일을 크게 늘리고 흐리게 표시한다.

## 변경

- 상세 뷰와 썸네일 목록이 같은 ThumbnailProvider를 공유한다. 미리보기는 작은 메모리 캐시도 즉시 사용하며, 캐시에 없으면 기존 파이프라인에서 비동기로 요청한다.
- 로딩 썸네일은 원본 표시 영역에 종횡비를 유지하며 확대한다. 별도 NSImageView에 Gaussian blur를 적용하고 원본과 분리한다. 썸네일이 표시되면 중앙 로딩 패널을 숨긴다.
- 원본이 도착하면 미리보기를 제거하고 선명한 원본으로 교체한다. 원본이 먼저 도착했거나 파일을 전환한 뒤에는 늦은 썸네일을 표시하지 않는다.
- 요청 세대와 원본 로딩 상태를 함께 확인한다. 화면 이탈·영상 전환·원본 완료 때 미리보기 요청을 취소한다.
- 공유 캐시의 이미지 크기나 원본 참조를 변경하지 않는다. 미리보기는 편집·내보내기용 원본으로 취급하지 않는다.
- 썸네일도 없는 동안에만 기존 로딩 표시를 사용한다.

## 검증

- `make build` 성공.
- `make test-ui` 58개 통과. 작은 캐시의 즉시 확대·블러 설정, 문구 숨김, 다음 파일의 썸네일 교체, 늦은 원본·썸네일 차단을 검증했다.
- `git diff --check` 통과.
- `test/상세_썸네일_로딩_2026-10-31/`에 빌드·UI 테스트 로그와 확대 미리보기 캡처를 보존했다. 뷰 캐시 캡처는 확대 영역과 문구 제거를 확인하는 용도이며, 합성 단계의 블러 강도를 측정한 결과는 아니다.

## 구현 근거와 보존

블러는 [NSView.contentFilters](https://developer.apple.com/documentation/appkit/nsview/contentfilters)를 사용한다. layer-backed 뷰에 필터를 설정하면 AppKit이 필요한 Core Image 합성을 구성한다([layerUsesCoreImageFilters](https://developer.apple.com/documentation/appkit/nsview/layerusescoreimagefilters)). 원본 크기의 CPU 중간 비트맵을 새로 만들지 않는다.

기존 성능 개선과 로딩 처리를 보존하고 이번 요청 범위만 변경했다. 수정 전 관련 파일은 `/var/folders/jy/d4hl_blj2wgf55g7gg6nnz0m0000gn/T/jena-viewer-preview-original-ny3xmryy/original.tar.gz`에 보존했다. 설치·커밋·푸시는 수행하지 않았다.

## 커밋·푸시 요청

사용자의 후속 요청으로 이번 성능 개선, 재귀 탐색 진행 표시, 상세 썸네일 미리보기, 테스트와 검증 기록을 함께 커밋해 origin/main에 푸시한다. 원격과 로컬 main의 기존 HEAD가 같음을 확인했고, 최종 빌드·UI 58개 통과 기록과 diff 검사를 확인했다.
