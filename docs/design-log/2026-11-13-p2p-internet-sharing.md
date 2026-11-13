# P2P 공유 설계 v2 로그 — 인터넷 너머

- 날짜: 2026-11-13
- 상태: 설계 v2 작성, 구현 없음. v1(로컬 네트워크) 대체
- 대상 문서: [p2p-internet-sharing-design.md](../p2p-internet-sharing-design.md)

## 작가 결정
- 범위는 인터넷 너머 1:N. 중앙 서버 없음. 찾기(DHT)와 가져오기(HTTP)는 다른 방식이어도 됨.
- 기본 비공개 채널(초대 코드), 공개 채널 옵션. 공개는 표시 이름 필수.
- 화면에 IP 미표시(시스템 수준 노출은 한계로 명시).
- 공유 폴더 밖 접근을 구조적으로 차단.
- 블록체인 미채택(장부가 아니라 분산 탐색이 필요 → DHT).

## 검토한 대안과 트레이드오프
- 블록체인: 합의·비용·지연이 붙고 전송에 무관 → 제외.
- 자체 DHT 네트워크 vs Mainline 합승: 초기 피어가 없으면 자체망은 비어 있으므로 Mainline에 채널 키로 합승. 부트스트랩이 외부 노드라는 의존은 수용.
- 서버 경로 기반 vs 불투명 ID: ID 기반이면 디렉터리 순회가 설계상 불가 → 채택.
- 1차 TLS: 넣으면 Phase 1이 길어짐. 미결(14-4)로 남김.
- 중계 없는 NAT 실패 처리: 명확한 안내로 끝내고, 유료 중계는 서버 링크 공유와 합류(Phase 3).

## 기술 검증 기록
- 이 집 회선: 공인 IPv4(112.161.x), 공유기 UPnP IGD 지원, NAT-PMP 미응답, IPv6 없음.
- UPnP AddPortMapping 성공 → 읽기 전용 HTTP → portchecker.io "open" → DeletePortMapping.
- Mainline DHT: dht.transmissionbt.com 응답, get_peers 3홉에서 노드 10개·token 수신(announce 가능 상태). router.bittorrent.com·utorrent는 타임아웃.
- Bonjour(NWListener/NWBrowser) 1:N 발견·TXT·연결 성공(v1용, 참고).
