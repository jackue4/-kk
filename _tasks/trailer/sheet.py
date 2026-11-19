"""从 _shots/trailer 帧里取一段做验收拼板：python sheet.py <起始秒> <结束秒> <步长帧> <输出名>"""
import sys, glob, os, cv2, numpy as np
a, b, step, name = float(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
fr = sorted(glob.glob("_shots/trailer/f_*.jpg"))
ims = []
for i in range(int(a * 30), min(int(b * 30), len(fr)), step):
    im = cv2.imdecode(np.fromfile(fr[i], dtype=np.uint8), cv2.IMREAD_COLOR)
    im = cv2.resize(im, (640, 360), interpolation=cv2.INTER_AREA)
    cv2.putText(im, "%.2fs" % (i / 30), (8, 26), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
    ims.append(im)
while len(ims) % 2:
    ims.append(np.zeros_like(ims[0]))
rows = [np.hstack(ims[r:r + 2]) for r in range(0, len(ims), 2)]
ok, buf = cv2.imencode(".jpg", np.vstack(rows), [cv2.IMWRITE_JPEG_QUALITY, 85])
buf.tofile("_shots/preview/%s.jpg" % name)
