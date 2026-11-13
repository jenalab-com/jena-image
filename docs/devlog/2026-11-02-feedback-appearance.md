# 2026-11-02 — 사용자 피드백 3건: 기본 격자 · 투명 체크무늬 토글 · 앱 배경

> 문서는 비공개 리포 `jena-image-pro/docs`에 둔다(2026-11-01 공개/비공개 분리). 소스 변경은 두 리포에 같은 패치로 적용했다.

## 피드백과 대응

1. **처음 목록이 Masonry라 순서를 알기 어렵다** → `AppSettings.browserLayoutMode` 기본값을 `.grid`(같은 크기·행 우선 순서)로. 이미 Masonry를 직접 고른 사용자는 저장값이 있어 그대로 유지. 툴바 세그먼트로 언제든 전환.
2. **체크무늬가 눈이 아프다** → `AppSettings.showsTransparencyCheckerboard`(기본 꺼짐). 툴바에 "투명 체크무늬" 체크박스(`ToolbarID.checkerboard`, 브라우저·뷰어 모드 모두). 꺼지면 `ThumbnailImageView`·`ThumbnailButton`이 투명 영역을 흰색으로 채운다(`drawBackdrop`). 변경은 `.settingsChanged`로 모든 썸네일 뷰가 즉시 다시 그린다.
3. **앱 배경에 색이 섞인다** → 원인은 `LibrarySurfaceView(.canvas)`의 `NSVisualEffectView(.underWindowBackground, behindWindow)` — 데스크톱 배경이 비쳐 색이 들어왔다. 기본을 **옅은 회색 불투명**(라이트 0.955 / 다크 0.17)으로 바꾸고, 설정 → 일반에 "앱 배경" 색(`NSColorWell`)·불투명도 슬라이더(0~100%)·"기본값" 버튼 추가. 불투명도 100%면 블러를 아예 꺼서 비용도 없애고, 낮추면 블러가 다시 비친다. 목록·뷰어(`.system` 배경)·상태바가 같은 표면을 쓰므로 한꺼번에 반영.

## 구현 메모

- `AppSettings`: `thumbnailCheckerboard`·`canvasBackgroundColor`(NSColor 아카이브)·`canvasBackgroundOpacity` 키, `defaultCanvasColor(dark:)`.
- `LibrarySurfaceView`: 캔버스에 `tint` 레이어 추가, `.settingsChanged`·모양 변경 시 재적용.
- 테스트: Masonry UI 스위트는 `browserLayout=masonry`를 명시. 디자인 테스트에 "기본은 흰색" 케이스 추가, 체크무늬 케이스는 설정을 켜고 검증.
- 도움말: 보기 방식·투명 체크무늬·앱 배경 항목 추가.

## 검증

- `make build` 경고·에러 0, `make test`·`make test-ui` 통과.
- UI 테스트 미리보기(`.build/library-grid.png`): 회색 바탕, 흰 썸네일 여백, 격자 배치, 툴바 체크박스 확인.
- 수동: [ ] 설정 → 일반에서 색·불투명도 즉시 반영 · [ ] 불투명도 0%에서 데스크톱 비침 · [ ] 다크 모드 기본 회색 · [ ] 체크박스 토글 시 목록·뷰어 스트립·비교 strip 모두 바뀜 · [ ] 첫 실행 사용자 격자 기본.
