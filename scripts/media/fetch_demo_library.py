#!/usr/bin/env python3
"""README·릴리스 캡처용 데모 이미지 라이브러리를 내려받는다.

사진은 picsum.photos가 중계하는 Unsplash 사진(Unsplash License)이다.
출처 목록은 docs/media/CREDITS.md로 함께 생성한다.

usage: scripts/media/fetch_demo_library.py [target_dir]
"""
import concurrent.futures as cf
import json
import os
import subprocess
import sys

ROOT = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/Pictures/JenaImage Demo")
CREDITS = os.path.join(os.path.dirname(__file__), "../../docs/media/CREDITS.md")
LONG_EDGE = 2400

# picsum id 목록. 유사 이미지 검색 시연을 위해 Still Life에는 비슷한 노트북 사진을 몰아 둔다.
GROUPS = {
    "Landscapes": ("landscape", [10, 11, 15, 16, 17, 18, 28, 29, 46, 62, 66, 67, 69, 79, 93, 128,
                                 143, 155, 165, 170, 177, 191, 197, 199, 204, 206]),
    "Sea & Coast": ("coast", [12, 13, 14, 37, 47, 52, 74, 77, 124, 144, 147, 154, 178, 179, 196, 203]),
    "City": ("city", [42, 43, 49, 57, 58, 78, 84, 88, 122, 133, 134, 163, 164, 183, 188, 192, 193, 195]),
    "Still Life": ("still", [0, 1, 2, 3, 5, 6, 8, 9, 48, 30, 39, 60, 63, 113, 119, 152, 159, 160, 175,
                             180, 200]),
}


def photo_index():
    photos = {}
    for page in (1, 2):
        # python.org 배포판은 시스템 인증서를 쓰지 않으므로 curl로 받는다.
        out = subprocess.run(["curl", "-sfL", f"https://picsum.photos/v2/list?page={page}&limit=100"],
                             check=True, capture_output=True).stdout
        for p in json.loads(out):
            photos[int(p["id"])] = p
    return photos


def main():
    photos = photo_index()
    jobs, rows = [], []
    for folder, (slug, ids) in GROUPS.items():
        os.makedirs(os.path.join(ROOT, folder), exist_ok=True)
        for n, pid in enumerate(ids, 1):
            p = photos[pid]
            w, h = p["width"], p["height"]
            size = (LONG_EDGE, round(LONG_EDGE * h / w)) if w >= h else (round(LONG_EDGE * w / h), LONG_EDGE)
            name = f"{slug}-{n:02d}.jpg"
            jobs.append((f"https://picsum.photos/id/{pid}/{size[0]}/{size[1]}", os.path.join(ROOT, folder, name)))
            rows.append(f"| {folder}/{name} | {p['author']} | {p['url']} |")

    def download(job):
        url, out = job
        if not os.path.exists(out):
            subprocess.run(["curl", "-sfL", "-o", out, url], check=True)

    with cf.ThreadPoolExecutor(12) as ex:
        list(ex.map(download, jobs))

    os.makedirs(os.path.dirname(CREDITS), exist_ok=True)
    with open(CREDITS, "w") as f:
        f.write("# Demo Image Credits\n\n")
        f.write("Screenshots and demo videos use photos from [Unsplash](https://unsplash.com) "
                "(via [Lorem Picsum](https://picsum.photos)) under the "
                "[Unsplash License](https://unsplash.com/license).\n\n")
        f.write("| File | Photographer | Source |\n|---|---|---|\n")
        f.write("\n".join(rows) + "\n")
    print(f"{len(jobs)} images -> {ROOT}")


if __name__ == "__main__":
    main()
