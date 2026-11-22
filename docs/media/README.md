# README·릴리스 미디어 만들기

README의 스크린샷(`0*.png`)과 데모 GIF(`*.gif`)는 `scripts/media/`로 다시 만든다. 실제 앱을 접근성 API와 합성 마우스 이벤트로 조작하므로 **실행 중에는 Mac을 만지지 않는다.**

## 준비

- 터미널(또는 실행하는 앱)에 **손쉬운 사용**과 **화면 기록** 권한이 필요하다.
- `ffmpeg`(Homebrew), `python3`
- AI 영상은 Codex CLI 로그인이 필요하며 실제 이미지를 1장 생성한다(계정 사용량 소모).

## 순서

```bash
scripts/media/fetch_demo_library.py      # ~/Pictures/JenaImage Demo 에 Unsplash 사진 81장, CREDITS.md 갱신
scripts/media/capture_screens.sh         # docs/media/01~08.png
scripts/media/record_videos.sh           # .build/media-raw/*.mp4 (browse similar compare ai)
scripts/media/web_scene.sh               # docs/media/09-web-panel.png, 10-web-save.png + .build/media-raw/web.mp4 (인터넷 필요)
scripts/media/encode_videos.sh           # docs/media/*.gif + .build/media/*.mp4(릴리스 첨부용)
```

장면 하나만 다시 찍으려면 `record_videos.sh compare`, `encode_videos.sh compare`처럼 이름을 넘긴다.

## 동작 방식

- `make_demo_app.sh`가 번들 ID를 `com.jenalab.jenaimage.demo`로 바꾼 사본을 만든다. 등록 폴더·카테고리·북마크·AI 설정이 실제 앱과 분리되어 개인 폴더가 화면에 나오지 않는다. 썸네일·유사도 캐시 폴더는 공유한다.
- UI는 한국어로 캡처한다. 영어 모드는 하드코딩된 한국어 문자열이 섞인다.
- 녹화 중 접근성 트리 탐색은 몇 초씩 걸리므로 좌표를 미리 재 두고 마우스만 움직인다.
- 컨텍스트 메뉴는 접근성 트리에 노출되지 않아 클릭 지점 기준 상대 좌표로 고른다. 메뉴 항목이 바뀌면 `record_videos.sh`·`capture_screens.sh`의 오프셋(329pt)을 다시 잰다.
- 한글 입력 상태에서는 AppleScript `keystroke "v"`가 ⌘V로 잡히지 않아 편집 메뉴로 붙여넣는다.

## 웹 패널 장면

`web_scene.sh`는 스크린샷 2장과 영상 1편을 한 번에 만든다. 다른 장면과 섞이지 않게 데모 라이브러리에 `Web Finds` 폴더를 만들어 쓰고 끝나면 지운다.

- 웹 패널에는 [Lorem Picsum 사진 모음](https://picsum.photos/images)을 띄운다(`make_demo_app.sh`가 탭 둘을 심어 둔다). 데모 앱은 번들 ID가 달라 웹 로그인·쿠키도 실제 앱과 분리된다.
- 웹 페이지 안의 요소는 접근성 트리에서 찾기에 느리고 불안정해서 **창 기준 고정 좌표**를 쓴다(창 (80,60) 1400×880, 사이드바 220pt, 웹 패널 480pt). 사이트 배치가 바뀌면 스크립트 위쪽의 `IMG`·`DROP`·`TAB1`·`TAB2`·`MENU_DX/DY`를 다시 잰다.
- 끌어다 놓기는 `mouse drag`로 실제 마우스 이벤트를 보낸다 — 누른 뒤 조금 움직여 끌기를 시작시키고, 목적지에서 잠깐 머물렀다 놓는다.
- 우클릭 메뉴는 창과 별개의 창이라 `shot`(창 캡처)에 담기지 않는다. 메뉴가 뜬 화면은 `shot_region`(화면 영역 캡처)으로 찍는다.
- 처음 실행하면 사이트의 쿠키 안내가 뜬다. 스크립트가 "Reject"를 찾아 누르고, 그 뒤로는 데모 앱의 웹 저장소에 기억된다.

## AI 영상 편집

`record_videos.sh ai`는 `.build/media-raw/ai.marks`에 `전송 시각 완료 시각`(초)을 남기고, `encode_videos.sh`가 대기 구간을 약 3초로 빨리 감는다. 녹화 중 시스템 대화상자 등이 끼어들면 marks에 `가릴 시작 가릴 끝`을 덧붙여 그 구간을 잘라낸다.

예: `7.27 116.09 7.9 34.5`. 데모 앱으로 처음 생성할 때 "문서 폴더 접근" 권한 요청이 8~34초에 떠서 잘라냈다.
