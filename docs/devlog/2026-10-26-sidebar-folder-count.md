# 2026-10-26 — 사이드바 폴더 숫자를 하위 폴더 포함 총계로

## 증상과 원인

사이드바 폴더 옆 숫자가 "맞지 않는다"는 보고. 확인해 보니 숫자는 `FolderNode.mediaFileCount`, 즉 **그 폴더 바로 아래** 미디어 파일 수였고 그 기준으로는 정확했다(render_image 직속 2개, chroma는 직속 0개라 공란). 하위 폴더 포함 보기에서 3330개가 보이는데 옆 숫자가 2이니 기준이 어긋난 것. 하위 폴더만 있는 폴더는 아예 숫자가 없어 더 어색했다.

## 변경

- `services/FolderMediaCountService.swift` — 폴더와 모든 하위 폴더의 미디어 파일 총계. `Task.detached`로 한 번 재귀하면서 하위 폴더 각각의 총계도 함께 캐시(키는 경로 문자열)하므로, 펼쳐서 드러난 하위 폴더는 보통 캐시에서 바로 나온다. `invalidate(url)`은 그 폴더 아래 전부와 **조상**(총계가 바뀌므로)을 지우고 세대를 올려 진행 중인 계산 결과를 버린다. 규칙은 `FolderNode.loadChildren`과 동일(숨김 제외·패키지 안 내려감·`allSupportedExtensions`).
- `SidebarViewController` — 폴더 셀은 캐시 값을 보여 주고, 없으면 비워 둔 채 계산을 예약. 계산이 끝나면 `onUpdate` → `refreshVisibleCounts()`가 보이는 행의 레이블만 갱신(행 재생성 없음). `reload(node:)`는 그 노드를 무효화, `reloadAll`은 전부 무효화. 셀 바인딩의 `node.loadChildren()`은 펼침 삼각형 판단용으로 유지.
- 도움말 "미디어 개수" 문구 갱신.

## 검증

- `make build` 경고·에러 0, `make test`·`make test-ui` 통과.
- 단독 하네스(서비스 + ImageFile + ImageFormat만 컴파일)로 실제 폴더 계산: root 3330(브라우저 하위 포함 보기와 일치), chroma 556, ayase_hina 60. 잎 폴더 무효화 뒤 root·chroma 캐시가 비고 재계산 예약됨.
- 수동: [ ] 앱 시작 직후 큰 루트 숫자가 잠시 뒤 채워지는지(UI 멈춤 없음) · [ ] 폴더 펼치면 하위 숫자가 즉시 보이는지 · [ ] 파일 삭제/붙여넣기/일괄 내보내기 뒤 그 폴더와 상위 폴더 숫자가 같이 바뀌는지 · [ ] ⇧⌘R 새로고침 뒤 전체 재계산.
