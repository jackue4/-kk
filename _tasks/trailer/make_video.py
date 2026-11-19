"""把 _shots/trailer/f_*.jpg 拼成 _shots/trailer.mp4（1280x720 / 30fps），并输出验收用的缩略图拼板。
这台机器没有 ffmpeg：用 cv2.VideoWriter，优先 H.264（avc1），不可用时退回 MPEG-4（mp4v）。
用法：python make_video.py [项目目录]
拼板：_shots/preview/trailer_sheet_XX.jpg，每秒取一帧、4x3 一张，左上角标出秒数。
"""
import glob
import os
import sys

import cv2
import numpy as np

proj = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..")
shots = os.path.join(proj, "_shots")
frames = sorted(glob.glob(os.path.join(shots, "trailer", "f_*.jpg")))
if not frames:
    sys.exit("no frames")
FPS = 30
W, H = 1280, 720
out = os.path.join(shots, "trailer.mp4")

writer = None
for cc in ("avc1", "H264", "mp4v"):
    w = cv2.VideoWriter(out, cv2.VideoWriter_fourcc(*cc), FPS, (W, H))
    if w.isOpened():
        writer, codec = w, cc
        break
    w.release()
if writer is None:
    sys.exit("no usable mp4 codec")


def read(p):
    # cv2.imread 不认中文路径：先读字节再解码
    return cv2.imdecode(np.fromfile(p, dtype=np.uint8), cv2.IMREAD_COLOR)


thumbs = []
for i, p in enumerate(frames):
    img = read(p)
    if img.shape[1] != W or img.shape[0] != H:
        img = cv2.resize(img, (W, H), interpolation=cv2.INTER_AREA)
    writer.write(img)
    if i % FPS == 0:
        t = cv2.resize(img, (400, 225), interpolation=cv2.INTER_AREA)
        cv2.putText(t, "%ds" % (i // FPS), (8, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 0), 4)
        cv2.putText(t, "%ds" % (i // FPS), (8, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
        thumbs.append(t)
writer.release()

pv = os.path.join(shots, "preview")
os.makedirs(pv, exist_ok=True)
for old in glob.glob(os.path.join(pv, "trailer_sheet_*.jpg")):
    os.remove(old)
for s in range(0, len(thumbs), 12):
    grid = thumbs[s:s + 12]
    while len(grid) < 12:
        grid.append(np.zeros_like(thumbs[0]))
    rows = [np.hstack(grid[r * 4:(r + 1) * 4]) for r in range(3)]
    ok, buf = cv2.imencode(".jpg", np.vstack(rows), [cv2.IMWRITE_JPEG_QUALITY, 85])
    buf.tofile(os.path.join(pv, "trailer_sheet_%02d.jpg" % (s // 12)))

print("frames %d  duration %.1fs  codec %s  -> %s  (%.1f MB)" % (
    len(frames), len(frames) / FPS, codec, out, os.path.getsize(out) / 1e6))
