# 2026-11-03 — 로컬 설치 경로 통일

- 원인: DMG의 Applications 링크는 `/Applications`였으나 `make install`은 `~/Applications`로 복사했다. 공용·개인 응용 프로그램 폴더가 달라 중복 설치가 발생할 수 있었다.
- 변경: `INSTALL_DIR ?= /Applications`를 추가해 기본 경로를 DMG와 통일했다. 개인 설치는 `make install INSTALL_DIR="$HOME/Applications"`로 선택할 수 있다. 경로 인용으로 공백도 처리한다.
- 공개/pro 양쪽 Makefile과 README를 갱신했다.
- 검증: 기본 및 개인 경로의 `make -n install`, 양쪽 `git diff --check` 통과. 실제 설치·기존 개인 폴더 앱 삭제는 수행하지 않았다. 소스 변경이 없어 빌드·테스트는 재실행하지 않았다.
- 커밋·푸시는 하지 않았다.
