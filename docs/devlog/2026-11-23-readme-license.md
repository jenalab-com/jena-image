# README 라이선스 표기·clone 주소 정정

## 배경
- `LICENSE` 파일과 README 상단 배지는 MIT인데, README 맨 아래 License 섹션만 "Proprietary — All rights reserved"로 남아 서로 어긋나 있었다.
- Build 섹션의 clone 주소가 `jenalab/jena-image`로 적혀 있었다. 실제 저장소는 `jenalab-com/jena-image`다.

## 변경
- README License 섹션: `MIT — Copyright (c) 2026 JenaLab. See LICENSE.`로 수정.
- README Build 섹션: clone 주소를 `https://github.com/jenalab-com/jena-image.git`로 수정.
- `LICENSE`는 이미 표준 MIT 전문이라 손대지 않았다.

## 검증
- 저장소 전체에서 `Proprietary`·`All rights reserved`·`jenalab/jena-image` 검색 결과 없음.
- 문서만 바뀌어 빌드 영향 없음.
