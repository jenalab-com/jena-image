# 상세 화면 이미지 로딩 표시

## 요청과 원인

상세 화면에서 다음 파일로 이동해도 원본 로딩이 끝날 때까지 이전 이미지가 남아 같은 파일처럼 보였다. `showImage`가 비동기 결과를 기다리는 동안 화면과 `currentImage`를 갱신하지 않았기 때문이다.

## 변경

- 요청 시작 시 이전 이미지 픽셀과 원본 참조를 즉시 비우고 중앙에 회전 표시와 ‘이미지를 불러오는 중…’ 문구를 표시한다.
- 제목은 새 파일명으로 즉시 바꾸고 원본이 도착할 때까지 편집 버튼을 비활성화한다.
- 성공·실패 시 로딩 표시를 종료한다. 실패 상태에 이전 원본을 남기지 않는다.
- 연속 이동 시 취소된 요청이 최신 화면을 덮어쓰지 않도록 MainActor에서 취소 확인과 결과 적용을 함께 수행한다.
- 영상 전환·상세 화면 이탈 시 로딩 상태를 정리한다. 새 원본 표시 시 회전 상태도 초기화한다.

## 디자인 결정

이미지를 빠르게 확인하며 넘기는 사용자가 현재 파일의 로딩 여부를 바로 알 수 있게 하는 것이 목적이다. 기존 LibraryCardView의 중립색 배경과 시스템 글꼴을 재사용해 사용자가 선택한 밝은·어두운 이미지 배경에서도 문구가 구분되게 했다. 별도 썸네일 조회 없이 즉시 이전 이미지를 지우고 로딩 상태를 표시하는 방식으로 구현했다.

참조: [Apple Loading](https://developer.apple.com/design/human-interface-guidelines/loading), [Progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators), [NSProgressIndicator](https://developer.apple.com/documentation/appkit/nsprogressindicator).

## 보존

앞선 성능 개선의 미커밋 변경을 유지했다. 이번 수정 전 ImageDisplayView.swift, ViewerViewController.swift, Tests/UI/main.swift는 `/var/folders/jy/d4hl_blj2wgf55g7gg6nnz0m0000gn/T/jena-viewer-loading-original-huv95u1a/original.tar.gz`에 보존했다.

## 검증

늦은 결과를 수동으로 반환하는 테스트 로더로 최초 로딩, 다음 이미지 전환, 연속 이동, 실패, 화면 이탈을 검증한다. 로그와 밝은·어두운 배경 캡처는 `test/상세_로딩_2026-10-31/`에 기록한다.

## 최종 결과

- `make build` 성공.
- `make test-ui` 55개 통과(상세 로딩 회귀 테스트 5개 포함).
- `git diff --check` 통과.
- 밝은 UI/어두운 배경과 어두운 UI/밝은 배경의 캡처에서 중앙 로딩 문구와 이전 이미지 제거를 확인했다.
- 초기 캡처 테스트의 창 콘텐츠 크기가 0으로 잡혀 캡처 생성이 실패했다. 테스트 창 크기를 명시하고 실제 레이아웃 완료를 기다리도록 수정한 후 캡처와 테스트가 통과했다.
- 앞선 성능 개선 변경을 유지했으며 설치·커밋·푸시는 수행하지 않았다.
