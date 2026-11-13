# 공개 저장소와 비공개 저장소 분리

## 변경
- 비공개 저장소 `jenalab-com/jena-image-pro`를 만들고, jena-image 작업 트리 전체(설계 문서·devlog·`scripts/media`·`test/` 기록 포함)를 초기 커밋으로 가져왔다(c58a480).
- 공개 저장소 `jenalab-com/jena-image`에서는 `docs/`와 `scripts/`를 지웠다. README 스크린샷·데모 GIF는 `assets/`로 옮기고(`02-grid.png` 제외), 지운 문서 링크와 소스 주석의 devlog 참조를 정리했다(0d7ff5a). 비교 창 수정은 별도 커밋(c4ce429)으로 두 저장소에 같이 반영된다.
- jena-image의 `.gitignore`에 커밋되지 않은 `.github` 줄이 있어 미디어 경로를 `.github/media` 대신 `assets/`로 정했다. 이 줄은 건드리지 않았다.

## 검증
- 복사본과 원본의 `diff -rq` 차이 없음, pro `make build` 성공.
- jena-image는 정리 후 `make build`·단위·UI 테스트 통과, README가 가리키는 `assets/` 파일 모두 존재 확인 후 푸시했다. 원격에서 pro 비공개 여부와 공개 저장소 파일 목록을 확인했다.

## 참고
- pro 원격은 jenalab 조직 키 별칭 `git@github.com-jenalab:` 를 쓴다(기본 github.com 키는 다른 계정).
- `scripts/media`의 산출물 경로(`docs/media`)는 pro 기준이다. 공개 저장소 README 미디어를 갱신하려면 pro에서 다시 만든 뒤 jena-image의 `assets/`로 복사한다.
