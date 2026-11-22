#!/bin/zsh
# 웹 패널 스크린샷 2장과 데모 영상 1편을 만든다.
#   docs/media/09-web-panel.png   웹에서 끌어온 이미지가 폴더에 저장된 화면
#   docs/media/10-web-save.png    이미지 우클릭 메뉴의 "'폴더'에 저장"
#   .build/media-raw/web.mp4      열기 → 끌어다 놓기 → 우클릭 저장 → 탭 전환 (encode_videos.sh web 으로 변환)
# 실행 중에는 마우스·키보드를 만지지 않는다. 인터넷 연결이 필요하다(picsum.photos).
#
# 다른 장면과 섞이지 않게 데모 라이브러리에 "Web Finds" 폴더를 만들어 쓰고 끝나면 지운다.
# 웹 페이지 안의 좌표는 창을 (80,60) 1400×880으로 두었을 때의 화면 좌표다 — 사이드바 220pt,
# 웹 패널 480pt(x 300~780), 목록은 그 오른쪽. Lorem Picsum의 배치가 바뀌면 다시 잰다.
set -euo pipefail
ROOT=${0:A:h:h:h}
source "$ROOT/scripts/media/lib.sh"
DEMO_LIB=${DEMO_LIB:-$HOME/Pictures/JenaImage Demo}
WEB_DIR="$DEMO_LIB/Web Finds"

# 한 줄이 실패해도(녹화가 이미 끝난 경우 등) 나머지 정리는 끝까지 한다 — set -e는 trap 안에서도 적용된다.
cleanup() {
  [[ -n ${REC_PID:-} ]] && kill -TERM $REC_PID 2>/dev/null || true
  osascript -e "tell application id \"$DEMO_ID\" to quit" 2>/dev/null || true
  sleep 1
  rm -rf "$WEB_DIR" || true
}
trap cleanup EXIT

rm -rf "$WEB_DIR"; mkdir -p "$WEB_DIR"
"$ROOT/scripts/media/make_demo_app.sh" >/dev/null
open "$ROOT/.build/demo/JenaImage.app"
sleep 5
activate
frame_window 80 60 1400 880
sleep 1

# 빈 "Web Finds" 폴더를 연다(목록의 폴더 타일을 두 번 누른다).
tile=($(center_of "Web Finds"))
$MOUSE dclick ${tile[1]} ${tile[2]} 0.5
sleep 2.5

# 웹 패널을 열어 페이지를 불러온다. 탭 둘은 make_demo_app.sh가 심어 둔다.
globe=($(center_of "웹 브라우저"))
$MOUSE click ${globe[1]} ${globe[2]} 0.5
sleep 8
# 쿠키 안내가 떠 있으면 닫는다(데모 앱의 웹 저장소에 한 번 기억되면 다시 뜨지 않는다).
if reject=($(center_of "Reject" 2>/dev/null)); then
  $MOUSE click ${reject[1]} ${reject[2]} 0.5
  sleep 1.5
fi

IMG=(540 400)        # 사진 목록까지 내렸을 때 첫 사진의 가운데
DROP=(1130 480)      # 목록(빈 폴더)의 가운데
TAB1=(398 154) TAB2=(570 154)
MENU_DX=62 MENU_DY=11   # 우클릭 지점에서 메뉴 첫 항목("'폴더'에 저장")까지

$MOUSE move 540 500 0.4
$MOUSE scroll -1160 40   # 머리말을 지나 사진 목록으로
sleep 2

# --- 스크린샷 ---
$MOUSE drag $IMG $DROP 1.2
sleep 3.5
$MOUSE move 1560 700 0.3
shot 09-web-panel.png
$MOUSE move 540 500 0.4
$MOUSE scroll -300 30    # 둘째 사진을 메뉴가 창 안에 다 보이는 높이로
sleep 1
$MOUSE rclick 520 440 0.5
sleep 1.2
shot_region 10-web-save.png
$MOUSE click $((520 + MENU_DX)) $((440 + MENU_DY)) 0.4
sleep 3
for f in "$OUT"/09-web-panel.png "$OUT"/10-web-save.png; do
  long=$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{print $2}' | sort -n | tail -1)
  if (( long > 1800 )); then sips -Z 1800 "$f" >/dev/null; fi
done

# --- 영상: 처음 상태로 되돌린 뒤 패널을 닫고 시작한다 ---
find "$WEB_DIR" -type f -delete
sleep 2
$MOUSE move 540 500 0.3
$MOUSE scroll 300 30
sleep 1
$MOUSE click ${globe[1]} ${globe[2]} 0.4   # 패널 접기(페이지와 스크롤 위치는 유지된다)
sleep 1.5
$MOUSE move 1100 620 0.3

rec_start web
$MOUSE click ${globe[1]} ${globe[2]} 0.8; sleep 1.8        # 웹 패널 열기
$MOUSE drag $IMG $DROP 1.4; sleep 2.8                      # 사진을 목록으로 끌어다 놓기
$MOUSE move 540 500 0.5
$MOUSE scroll -300 30; sleep 0.9
$MOUSE rclick 520 440 0.7; sleep 1.0                       # 둘째 사진 우클릭
$MOUSE move $((520 + MENU_DX)) $((440 + MENU_DY)) 0.5; sleep 0.4
$MOUSE click $((520 + MENU_DX)) $((440 + MENU_DY)) 0.1; sleep 2.8   # "'Web Finds'에 저장"
$MOUSE click $TAB2 0.7; sleep 2.2                          # 둘째 탭
$MOUSE click $TAB1 0.6; sleep 1.4                          # 첫 탭으로
rec_stop web
echo "done -> $OUT/09-web-panel.png $OUT/10-web-save.png $RAW/web.mp4"
