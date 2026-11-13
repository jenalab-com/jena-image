#!/bin/zsh
# 캡처 전용 JenaImage 사본을 만든다.
# 번들 ID를 바꿔 UserDefaults(등록 폴더·카테고리·북마크·AI 설정)를 실제 앱과 분리하고,
# 데모 라이브러리만 등록된 상태로 시작한다. 썸네일·유사도 캐시 경로는 실제 앱과 공유한다.
set -euo pipefail

ROOT=${0:A:h:h:h}
DEMO_LIB=${DEMO_LIB:-$HOME/Pictures/JenaImage Demo}
DEMO_ID=com.jenalab.jenaimage.demo
DEMO_APP=$ROOT/.build/demo/JenaImage.app

make -C "$ROOT" build >/dev/null
osascript -e "tell application id \"$DEMO_ID\" to quit" 2>/dev/null || true
sleep 1

rm -rf "$DEMO_APP"
mkdir -p "${DEMO_APP:h}"
cp -R "$ROOT/.build/JenaImage.app" "$DEMO_APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $DEMO_ID" "$DEMO_APP/Contents/Info.plist"
codesign --force --deep --sign - "$DEMO_APP" 2>/dev/null

# 이전 데모 상태(창 위치 포함)를 지우고 다시 심는다.
defaults delete "$DEMO_ID" 2>/dev/null || true
rm -rf "$HOME/Library/Saved Application State/$DEMO_ID.savedState"

defaults write "$DEMO_ID" appLanguage -string "${DEMO_LANG:-ko}"
defaults write "$DEMO_ID" rootFolderPaths -array "$DEMO_LIB"
defaults write "$DEMO_ID" browserLayout -string masonry
defaults write "$DEMO_ID" recursiveBrowsing -bool true
defaults write "$DEMO_ID" imageBookmarks -array \
  "$DEMO_LIB/Landscapes/landscape-09.jpg" \
  "$DEMO_LIB/Sea & Coast/coast-08.jpg" \
  "$DEMO_LIB/City/city-04.jpg"

categories=$(DEMO_LIB=$DEMO_LIB python3 - <<'EOF'
import json, os, uuid
lib = os.environ["DEMO_LIB"]
cats = [
    ("Wallpapers", ["Landscapes/landscape-04.jpg", "Landscapes/landscape-10.jpg", "Sea & Coast/coast-01.jpg",
                    "Sea & Coast/coast-12.jpg", "City/city-04.jpg", "Landscapes/landscape-20.jpg"]),
    ("Moodboard", ["Still Life/still-11.jpg", "Still Life/still-13.jpg", "City/city-09.jpg",
                   "Landscapes/landscape-07.jpg", "Still Life/still-16.jpg"]),
]
data = [{"id": str(uuid.uuid4()).upper(), "name": n, "paths": [os.path.join(lib, p) for p in ps]} for n, ps in cats]
print(json.dumps(data).encode().hex())
EOF
)
defaults write "$DEMO_ID" imageCategories.v1 -data "$categories"

echo "$DEMO_APP"
