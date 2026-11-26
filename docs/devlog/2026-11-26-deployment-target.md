# 빌드 최소 macOS 버전 고정

## 배경
- macOS 27.2.1에서 앱을 열면 "해당 응용 프로그램은 macOS 28.0 이상이 필요합니다"로 실행이 막혔다.
- `Info.plist`의 `LSMinimumSystemVersion`은 14.0인데, 실행 파일의 `minos`는 28.0이었다(`vtool -show-build`).
- `Makefile`의 `swiftc` 호출에 `-target`이 없어, 툴체인 기본값(Swift 6.3.3 → `arm64-apple-macosx28.0`)이 그대로 찍혔다.

## 변경
- `Makefile`: `MACOS_MIN = 14.0`, `SWIFT_TARGET = -target $(uname -m)-apple-macos$(MACOS_MIN)` 추가.
- 앱 빌드와 테스트 빌드 두 곳, `swiftc` 세 군데에 `$(SWIFT_TARGET)` 적용.

## 결정
- 최소 버전은 `Info.plist`와 같은 14.0으로 맞췄다. 올릴 때는 `MACOS_MIN`과 `LSMinimumSystemVersion`을 함께 바꾼다.
- 아키텍처는 빌드하는 맥의 것을 그대로 쓴다(지금은 arm64 단일). 유니버설 빌드는 이번 범위가 아니다.

## 검증
- `make build` 성공, 14.0 대상으로도 컴파일 오류 없음.
- `vtool -show-build` 결과 `minos 14.0`, 번들 서명 검증 통과.
- [ ] macOS 27.2.1에서 앱이 실제로 열리는지 수동 확인.
- [ ] 이미 배포한 2.1.0 `pkg`/`dmg`가 28.0으로 찍혔는지 확인하고, 그렇다면 다시 만들어 올리기.
