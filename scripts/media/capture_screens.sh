#!/bin/zsh
# README·릴리스용 스크린샷을 docs/media/에 만든다.
# 전제: scripts/media/fetch_demo_library.py로 데모 라이브러리를 받아 둔 상태.
# 실행 중에는 마우스·키보드를 만지지 않는다(커서를 직접 움직여 조작한다).
set -euo pipefail
ROOT=${0:A:h:h:h}
source "$ROOT/scripts/media/lib.sh"

# 영상 녹화에서 생성된 AI 결과가 목록에 섞이지 않게 지운다.
find "${DEMO_LIB:-$HOME/Pictures/JenaImage Demo}" -name '*_AI*.png' -delete
"$ROOT/scripts/media/make_demo_app.sh" >/dev/null
open "$ROOT/.build/demo/JenaImage.app"
sleep 4
activate
frame_window 80 60 1400 880
sleep 1

# 0. 하위 폴더 포함 보기로 라이브러리 전체를 연다.
press "하위 폴더 이미지 포함" click AXCheckBox
press "JenaImage Demo" click AXImage
sleep 4
$MOUSE move 1500 500 0.2   # 커서를 창 밖으로
shot 01-browser.png

# 1. 일반 격자
press "일반 격자"
sleep 2
$MOUSE move 1500 500 0.2
shot 02-grid.png
press "Masonry"
sleep 1

# 2. 상세 뷰어 + 정보 창
press "Landscapes" click AXImage
sleep 2
press "landscape-08.jpg" dclick
sleep 3
$MOUSE move 1500 500 0.2
shot 03-viewer.png
menu "파일" "정보 보기"
sleep 2
shot 04-info.png "landscape-08"
close_front
sleep 1

# 3. 비교: 세 장을 골라 ⌘\
press "Landscapes" click AXImage
sleep 2
press "landscape-08.jpg" click
press "landscape-05.jpg" cmdclick
press "landscape-12.jpg" cmdclick
menu "보기" "비교"
as_app 'set size of window "비교" to {1400, 880}'
sleep 6
shot 05-compare.png "비교"
close_front
sleep 1

# 4. 카테고리
press "카테고리 보기" click AXCheckBox
sleep 1
press "Wallpapers"
sleep 3
$MOUSE move 1500 500 0.2
shot 06-categories.png
press "폴더로 보기" click AXCheckBox
sleep 1

# 5. 유사 이미지: 전체 81장 중 still-01과 닮은 사진
press "JenaImage Demo" click AXImage
sleep 3
$MOUSE move 900 500 0.4
$MOUSE scroll -2400 30   # 이름순 마지막 폴더(Still Life)까지 내린다
sleep 1
c=($(center_of "still-01.jpg"))
$MOUSE rclick ${c[1]} ${c[2]}
sleep 1
# 단일 이미지 컨텍스트 메뉴에서 '비슷한 이미지 찾기'는 클릭 지점 기준 아래 329pt에 있다.
$MOUSE click $((c[1] + 90)) $((c[2] + 329)) 0.5
sleep 5
$MOUSE move 1500 500 0.2
shot 07-similar.png

# 6. AI 채팅 패널: 참조 이미지 하나를 첨부한 상태
press "Landscapes" click AXImage
sleep 2
press "landscape-08.jpg" click
press "AI 모드" click AXButton
sleep 4
$MOUSE move 1500 500 0.2
shot 08-ai-chat.png

# Retina 원본(약 3000px)은 README에 과하므로 긴 변 1800px로 줄인다(그림자 투명도 유지).
# sips -Z는 작은 이미지를 키우기도 하므로 긴 변이 1800px을 넘을 때만 줄인다.
for f in "$OUT"/0*.png; do
  long=$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{print $2}' | sort -n | tail -1)
  if (( long > 1800 )); then sips -Z 1800 "$f" >/dev/null; fi   # && 꼴은 set -e에서 루프 종료 코드를 1로 남긴다
done
echo "done -> $OUT"
