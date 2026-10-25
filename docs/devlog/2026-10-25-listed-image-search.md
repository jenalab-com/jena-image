# 현재 목록 안에서만 유사 이미지 검색

전체 등록 폴더의 최초 분석 비용이 크다는 요청에 따라 검색 범위를 현재 브라우저 목록으로 제한했다.
스크롤 밖의 항목도 포함하지만 폴더를 재귀 탐색하지 않는다. 카테고리·북마크는 폴더 등록 없이 검색할 수 있다.
검색 결과에서 다시 검색하면 해당 결과 목록 안에서만 비교한다.

- BrowserViewController가 현재 이미지 URL 스냅샷을 제공한다.
- ImageSimilarityService는 전달받은 URL만 비교하며 기준 이미지·중복 경로·영상을 제외한다.
- 기존 특징 캐시의 디렉터리·파일명·직렬화 형식·모델 버전은 유지한다. 기존 캐시를 삭제하지 않는다.
- 특징을 디스크에서 복원한 후 새 기준 이미지와의 거리를 계산한다. 검색 결과 순위 자체를 저장하는 방식은 아니다.
- 사용 문서에 실제 저장 위치와 재사용 조건을 보완했다.

검증: 실제 Vision 추론과 UI 통합 테스트 32개 통과. 현재 목록 밖의 등록 폴더 이미지 제외,
폴더 등록 없는 카테고리 검색, 재검색 시 캐시 재사용을 확인했다.
`make build BUILD_DIR=/tmp/jena-listed-search-check`와 `git diff --check` 통과.

수정 전 백업:
`/var/folders/jy/d4hl_blj2wgf55g7gg6nnz0m0000gn/T/jena-listed-search-backup-i3jff6iv/before.tar`.
