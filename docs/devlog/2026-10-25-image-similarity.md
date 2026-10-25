# 로컬 이미지 유사 검색

기준 이미지의 우클릭 메뉴에서 등록 폴더 전체를 검색하고 유사도순 최대 100장을 보여준다.
결과에서 기존 카테고리 수집 기능을 재사용한다.

- 모델: Apple Vision Image Feature Print revision 2, macOS 14 이상.
- 원본을 ImageIO로 축소하고 EXIF 방향을 반영한다. 투명 원본은 분석용 회색 바탕에 합성한다.
- 전용 actor에서 한 장씩 처리하며 특징 캐시를 로컬에 저장한다.
- 취소·화면 이동·창 닫기 시 진행 작업을 취소하고 세션 식별자로 늦은 결과를 무시한다.
- 검색 결과는 별도 브라우저 모드로 유지해 카테고리 변경·상세 복귀·자동 갱신이 검색 순위를 덮지 않는다.
- 모델/운영 방법: [사용 문서](../image-similarity.md).
- 선택 근거와 한계: [구조 결정 기록](../architecture-log/2026-10-25-image-similarity.md).

## 검증 결과

- 단위 테스트 45개와 UI/실제 Vision 통합 테스트 31개, 총 76개 통과.
- 실제 Vision 추론: 동일 이미지 최상위, 아카이브 재사용, 변경 파일 재분석, 손상 캐시 재생성,
  취소, 접근 불가 루트·손상 파일 처리.
- UI: 우클릭 검색 실행, 결과 카테고리 수집, 상세 복귀, 자동 갱신 시 결과 유지,
  뒤로 가기 및 검색 중 이동 후 늦은 결과 차단.
- `make build BUILD_DIR=/tmp/jena-similarity-check` 성공, `git diff --check` 통과.
- 테스트는 격리된 UserDefaults와 임시 원본·특징 캐시를 사용했다.
- 기존 설치 앱과 프로젝트 `.build`는 교체하지 않았다.

## 수정 전 보존

기존 미커밋 작업을 포함한 백업:
`/var/folders/jy/d4hl_blj2wgf55g7gg6nnz0m0000gn/T/jena-similarity-backup-ks9s342n/before.tar`.
