#!/bin/zsh
# 녹화 원본(.build/media-raw)을 배포용으로 변환한다.
#   MP4  → .build/media/<이름>.mp4   (1600px, H.264, 릴리스 첨부·README 업로드용)
#   GIF  → docs/media/<이름>.gif     (720px, 10fps, 저장소에 넣어 README에 바로 표시)
#          사진 위주 화면은 GIF 압축이 나빠 해상도·프레임·색 수를 낮춰 편당 수 MB로 맞춘다.
# ai는 ai.marks(전송 시각, 완료 시각)를 읽어 생성 대기 구간을 약 3초로 빨리 감는다.
set -euo pipefail
ROOT=${0:A:h:h:h}
RAW=$ROOT/.build/media-raw
MP4_OUT=$ROOT/.build/media
GIF_OUT=$ROOT/docs/media
mkdir -p "$MP4_OUT" "$GIF_OUT"
names=(${@:-browse similar compare ai web})

for name in $names; do
  src=$RAW/$name.mp4
  [[ -f $src ]] || { echo "skip $name (no raw)"; continue; }
  edited=$src
  if [[ $name == ai && -f $RAW/ai.marks ]]; then
    # ai.marks: "<전송 시각> <완료 시각> [<가릴 시작> <가릴 끝>]"
    # 가릴 구간은 녹화 중 끼어든 시스템 대화상자 등을 잘라낼 때 손으로 덧붙인다.
    read sent done_at hide_from hide_to < "$RAW/ai.marks"
    a=$(( sent + 1.5 )) b=$(( done_at - 0.5 ))
    head_end=$a fast_start=$a
    if [[ -n ${hide_from:-} ]]; then
      (( hide_from < head_end )) && head_end=$hide_from
      (( hide_to > fast_start )) && fast_start=$hide_to
    fi
    if (( b - fast_start > 4 )); then
      factor=$(( 3.0 / (b - fast_start) ))
      edited=$RAW/ai-edited.mp4
      ffmpeg -v error -y -i "$src" -filter_complex "\
        [0:v]trim=0:${head_end},setpts=PTS-STARTPTS[v1];\
        [0:v]trim=${fast_start}:${b},setpts=(PTS-STARTPTS)*${factor}[v2];\
        [0:v]trim=${b},setpts=PTS-STARTPTS[v3];\
        [v1][v2][v3]concat=n=3:v=1[v]" -map "[v]" -c:v libx264 -preset fast -crf 14 "$edited"
    fi
  fi
  ffmpeg -v error -y -i "$edited" -vf "fps=30,scale=1600:-2:flags=lanczos" \
    -c:v libx264 -preset slow -crf 22 -pix_fmt yuv420p -movflags +faststart -an "$MP4_OUT/$name.mp4"
  ffmpeg -v error -y -i "$edited" -vf "fps=10,scale=720:-1:flags=lanczos,split[a][b];\
[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    -loop 0 "$GIF_OUT/$name.gif"
  printf '%-8s mp4 %6s  gif %6s  %ss\n' $name \
    "$(du -h "$MP4_OUT/$name.mp4" | cut -f1)" "$(du -h "$GIF_OUT/$name.gif" | cut -f1)" \
    "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$MP4_OUT/$name.mp4" | cut -d. -f1)"
done
