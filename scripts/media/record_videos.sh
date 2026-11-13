#!/bin/zsh
# 주요 기능 데모 영상을 녹화한다. 원본은 .build/media-raw/, 편집본은 scripts/media/encode_videos.sh로 만든다.
# usage: record_videos.sh [browse|similar|compare|ai ...]   (인자가 없으면 전부)
# 실행 중에는 마우스·키보드를 만지지 않는다. ai는 연결된 Codex 계정으로 실제 이미지를 1장 생성한다.
#
# 접근성 트리 탐색은 한 번에 몇 초씩 걸리므로, 녹화 전에 좌표를 미리 재 두고(P[...])
# 녹화 중에는 마우스 이동과 키 입력만 한다.
set -euo pipefail
ROOT=${0:A:h:h:h}
source "$ROOT/scripts/media/lib.sh"
DEMO_LIB=${DEMO_LIB:-$HOME/Pictures/JenaImage Demo}
scenes=(${@:-browse similar compare ai})
# 시나리오가 중간에 실패해도 녹화 프로세스를 남기지 않는다.
trap '[[ -n ${REC_PID:-} ]] && kill -TERM $REC_PID 2>/dev/null; true' EXIT

typeset -A P
# 좌표를 재서 P[이름]="x y"로 기억한다. $2=역할(선택)
measure() { P[$1]=$(center_of "$1" "${2:-}"); }
# 기억한 좌표로 마우스 동작. $1=이름 $2=동작 $3=이동 시간
go() { local c=(${=P[$1]}); $MOUSE ${2:-click} ${c[1]} ${c[2]} ${3:-0.7}; }

# 이전 녹화에서 생성된 AI 결과가 목록에 섞이지 않게 지운다.
find "$DEMO_LIB" -name '*_AI*.png' -delete

"$ROOT/scripts/media/make_demo_app.sh" >/dev/null
open "$ROOT/.build/demo/JenaImage.app"
sleep 4
activate
frame_window 80 60 1400 880
press "하위 폴더 이미지 포함" click AXCheckBox
press "JenaImage Demo" click AXImage
sleep 4   # 썸네일 캐시 워밍업

# 사이드바·툴바 좌표는 화면 상태와 무관하게 고정이다.
measure "JenaImage Demo" AXImage
measure "Landscapes" AXImage
measure "일반 격자"
measure "Masonry"
measure "비교" AXButton
measure "AI 모드" AXButton

# 라이브러리 루트(전체 81장, 맨 위)로 돌아간다.
reset_root() {
  activate
  # 이미 선택된 루트를 다시 누르면 트리가 접혀 사이드바 좌표가 틀어진다. 다른 행을 거쳐 선택한다.
  go "Landscapes" click 0.2; sleep 1
  go "JenaImage Demo" click 0.2
  sleep 2
  $MOUSE move 900 500 0.2
  $MOUSE scroll 6000 10
  sleep 1
}
open_landscapes() {
  activate
  go "Landscapes" click 0.2
  sleep 2
}

scene_browse() {
  open_landscapes; measure "landscape-08.jpg"
  reset_root
  rec_start browse
  $MOUSE move 900 520 0.8
  $MOUSE scroll -1400 70; sleep 0.8
  $MOUSE scroll 1400 40; sleep 0.8
  go "일반 격자"; sleep 1.6
  go "Masonry" click 0.4; sleep 1.2
  go "Landscapes" click 0.8; sleep 1.5
  go "landscape-08.jpg" dclick 0.8; sleep 2
  for _ in 1 2 3; do keycode 125; sleep 1.2; done   # ↓ 다음 이미지
  keycode 126; sleep 1.2                            # ↑ 이전 이미지
  key "[" "command down"; sleep 1.5                 # 목록으로
  rec_stop browse
}

scene_similar() {
  reset_root
  $MOUSE scroll -2400 30; sleep 1
  local c=($(center_of "still-01.jpg"))
  rec_start similar
  $MOUSE move ${c[1]} ${c[2]} 0.9; sleep 0.3
  $MOUSE rclick ${c[1]} ${c[2]} 0.1; sleep 0.9
  # 단일 이미지 컨텍스트 메뉴에서 '비슷한 이미지 찾기'는 클릭 지점 아래 329pt에 있다.
  $MOUSE move $((c[1] + 90)) $((c[2] + 329)) 0.7; sleep 0.3
  $MOUSE click $((c[1] + 90)) $((c[2] + 329)) 0.1
  sleep 3.5
  $MOUSE move 900 600 0.6
  $MOUSE scroll -500 40; sleep 1.2
  $MOUSE scroll 500 30; sleep 1
  rec_stop similar
}

scene_compare() {
  open_landscapes
  for f in landscape-08.jpg landscape-05.jpg landscape-12.jpg; do measure $f; done
  rec_start compare
  go landscape-08.jpg click 0.7; sleep 0.3
  go landscape-05.jpg cmdclick 0.6; sleep 0.3
  go landscape-12.jpg cmdclick 0.6; sleep 0.5
  go "비교" click 0.8
  sleep 0.6
  as_app 'set position of window "비교" to {80, 60}'
  as_app 'set size of window "비교" to {1400, 880}'
  sleep 1.5
  $MOUSE move 300 420 0.8
  $MOUSE scroll 400 25; sleep 1     # 한 칸을 확대하면 나머지도 함께 확대된다
  $MOUSE scroll -400 25; sleep 0.8
  # 후보 스트립에서 다른 사진을 골라 활성 칸을 바꾼다.
  $MOUSE click 560 905 0.8; sleep 1.6
  rec_stop compare
  close_front
}

scene_ai() {
  local prompt="이 사진을 해 질 녘의 따뜻한 수채화 풍경화로 다시 그려 줘"
  open_landscapes
  measure landscape-08.jpg
  # 입력창 좌표를 재기 위해 패널을 한 번 열었다 닫는다.
  go "AI 모드" click 0.2; sleep 2
  measure "이미지 생성 요청" AXTextArea
  go "AI 모드" click 0.2; sleep 1
  go landscape-08.jpg click 0.2; sleep 0.5
  rec_start ai
  go "AI 모드" click 0.8; sleep 1.5
  go "이미지 생성 요청" click 0.6; sleep 0.3
  # 한글은 IME 조합 문제로 붙여넣기로 입력한다. 한글 입력 상태에서는 keystroke ⌘V가
  # 단축키로 잡히지 않으므로 메뉴를 누른다.
  print -rn -- "$prompt" | pbcopy
  menu "편집" "붙여넣기" >/dev/null; sleep 1.2
  keycode 36                                       # Enter = 전송
  local sent=$(rec_elapsed)
  $MOUSE move 1500 500 0.4
  local deadline=$((EPOCHSECONDS + ${AI_TIMEOUT:-420}))
  until [[ -n $(find "$DEMO_LIB/Landscapes" -name '*_AI*.png' 2>/dev/null) ]]; do
    (( EPOCHSECONDS > deadline )) && { echo "AI 생성 시간 초과"; break; }
    sleep 1
  done
  local done_at=$(rec_elapsed)
  sleep 4
  rec_stop ai
  # 대기 구간 표시(편집에서 빨리 감기에 사용)
  print "$sent $done_at" > "$RAW/ai.marks"
}

for s in $scenes; do scene_$s; done
echo "done -> $RAW"
