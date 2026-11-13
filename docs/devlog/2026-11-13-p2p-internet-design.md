# 2026-11-13 — 인터넷 P2P 공유: 가능성 검증과 설계 v2

## 배경
"서버 링크 공유"는 차후로 미루고, 지금은 토렌트처럼 중앙 서버 없이 인터넷 너머에서 열린 공유를 찾아 공유자 Mac에 직접 붙는 1:N P2P를 하기로 했다. 가능한지 먼저 확인한 뒤 설계를 다시 썼다.

## 한 일
- 스파이크 3종(앱 밖, 리포 미포함): Bonjour 1:N(Swift, Network.framework), UPnP 포트 개방 + 외부 도달(Python), Mainline DHT ping/get_peers(Python). 셋 다 성공. 결과는 design-log에 기록.
- `docs/p2p-internet-sharing-design.md`(v2) 작성. v1은 대체됨 표시. `plan.md` 31번 갱신, 다음 후보 1순위로.

## 결정
- 비공개 채널 기본 · 공개 옵션(이름 필수) · IP 미표시 · 폴더 밖 접근 구조적 차단 · 블록체인 미채택.

## 다음
- Phase 0: Swift `DHTClient`·`PortMapper` 스파이크를 두 Mac(서로 다른 망)에서 실측. 그 전에 미결 14절(포트 번호·동시 접속·초대 코드 형식·1차 TLS) 확정.
