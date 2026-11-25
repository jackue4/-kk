"""以 B.pck（线上包）为底，把 A.pck（我导出的）里列出的几项原样搬过来：B 有的替换、B 没有的追加。其余一律是 B 的字节。
用法：python -I pck_overlay.py <A.pck 我的导出> <B.pck 线上> <OUT.pck> 路径1 路径2 ...
"""
import struct, sys, hashlib

def parse(path):
    raw = open(path, "rb").read()
    assert raw[:4] == b"GDPC"
    fmt, major, minor, patch, flags = struct.unpack("<IIIII", raw[4:24])
    base, diroff = struct.unpack("<QQ", raw[24:40])
    assert fmt >= 3 and flags == 2, (fmt, flags)
    i = diroff
    n = struct.unpack("<I", raw[i:i+4])[0]; i += 4
    ents = []
    for _ in range(n):
        ln = struct.unpack("<I", raw[i:i+4])[0]; i += 4
        pb = raw[i:i+ln]; i += ln
        off, size = struct.unpack("<QQ", raw[i:i+16]); i += 16
        md5 = raw[i:i+16]; i += 16
        fl = struct.unpack("<I", raw[i:i+4])[0]; i += 4
        ents.append([pb, off, size, md5, fl])
    assert i == len(raw)
    return raw, base, ents

def name(pb):
    return pb.rstrip(b"\0").decode("utf-8")

A, B, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
want = sys.argv[4:]
ra, basea, ea = parse(A)
rb, baseb, eb = parse(B)
amap = {name(e[0]): e for e in ea}
bnames = [name(e[0]) for e in eb]
for w in want:
    assert w in amap, "A 里没有 " + w
datas = []
for e in eb:
    nm = name(e[0])
    if nm in want:
        ae = amap[nm]
        d = ra[basea + ae[1]: basea + ae[1] + ae[2]]
        assert hashlib.md5(d).digest() == ae[3], nm
        datas.append([e[0], d, ae[3], e[4]])
    else:
        d = rb[baseb + e[1]: baseb + e[1] + e[2]]
        datas.append([e[0], d, e[3], e[4]])
added = [w for w in want if w not in bnames]
for w in added:
    ae = amap[w]
    d = ra[basea + ae[1]: basea + ae[1] + ae[2]]
    assert hashlib.md5(d).digest() == ae[3], w
    datas.append([ae[0], d, ae[3], ae[4]])
out = bytearray(rb[:baseb])
offs = []
for pb, d, md5, fl in datas:
    while len(out) % 16:
        out.append(0)
    offs.append(len(out) - baseb)
    out += d
while len(out) % 16:
    out.append(0)
diroff = len(out)
out += struct.pack("<I", len(datas))
for (pb, d, md5, fl), off in zip(datas, offs):
    out += struct.pack("<I", len(pb)) + pb + struct.pack("<QQ", off, len(d)) + md5 + struct.pack("<I", fl)
out[32:40] = struct.pack("<Q", diroff)
open(OUT, "wb").write(out)
print("replaced", [w for w in want if w in bnames], "added", added, "size", len(out))
