"""以线上 pck 为底，只换 / 追加 / 删掉指定的几项，其余每一项都是线上原字节。
在 C:/Users/chenyahan/xian_scene_art/tools/pck_overlay.py（2026-11-23 灵田种植部署用的）基础上加了「删」：
境界光环从贴图版换成特效版时，要把线上包里那八张贴图和旧着色器拿掉（不拿掉也能跑，只是每个人白下载一兆多）。

用法：python -I pck_overlay_del.py <底.pck> <新导出.pck> <输出.pck> <规则文件>
规则文件每行一个：
  前缀匹配的包内路径（带不带 res:// 都行）  新导出里匹配到的项都用新的（底里有就替换，没有就追加）
  -包内完整路径                            从底里删掉这一项（必须一字不差；底里没有就报错，免得删错）
  uid_cache                                合并 .godot/uid_cache.bin：底的全留、新导出里多出来的追加，被删掉的那几项对应的 uid 一并去掉
读写格式和 _tasks/touch_cam/pck_diff.py 一样（pck 格式 3，目录在文件尾、偏移相对 file_base）。
"""
import hashlib
import struct
import sys

ALIGN = 32


def read_pck(path):
    f = open(path, "rb")
    head = f.read(104)
    assert head[:4] == b"GDPC", path
    fmt, major, minor, patch, flags = struct.unpack("<IIIII", head[4:24])
    base, diroff = struct.unpack("<QQ", head[24:40])
    f.seek(diroff)
    n = struct.unpack("<I", f.read(4))[0]
    ents = []
    for _ in range(n):
        ln = struct.unpack("<I", f.read(4))[0]
        p = f.read(ln).rstrip(b"\0").decode("utf-8")
        off, size = struct.unpack("<QQ", f.read(16))
        md5 = f.read(16)
        fl = struct.unpack("<I", f.read(4))[0]
        ents.append([p, off + (base if flags & 2 else 0), size, md5, fl])
    return {"f": f, "head": head, "hdr": (fmt, major, minor, patch, flags), "ents": ents}


def data_of(pk, e):
    pk["f"].seek(e[1])
    return pk["f"].read(e[2])


def parse_uid(buf):
    """uid_cache.bin：u32 个数，每项 u64 id + u32 路径长 + 路径字节"""
    n = struct.unpack("<I", buf[:4])[0]
    o = 4
    out = []
    for _ in range(n):
        uid = struct.unpack("<Q", buf[o:o + 8])[0]
        ln = struct.unpack("<I", buf[o + 8:o + 12])[0]
        out.append((uid, buf[o + 12:o + 12 + ln]))
        o += 12 + ln
    return out


def merge_uid(a, b, drop):
    """drop：包内路径（不带 res://）的集合；这些文件的 uid 不留。.import 对应的是去掉 .import 后的原文件"""
    gone = set()
    for p in drop:
        gone.add(("res://" + p).encode("utf-8"))
        if p.endswith(".import"):
            gone.add(("res://" + p[:-7]).encode("utf-8"))
    ea = [(u, p) for u, p in parse_uid(a) if p.rstrip(b"\0") not in gone]
    removed = len(parse_uid(a)) - len(ea)
    have = {u for u, _ in ea}
    add = [(u, p) for u, p in parse_uid(b) if u not in have and p.rstrip(b"\0") not in gone]
    out = struct.pack("<I", len(ea) + len(add))
    for u, p in ea + add:
        out += struct.pack("<QI", u, len(p)) + p
    return out, len(add), removed


def main():
    base_p, new_p, out_p, rules_p = sys.argv[1:5]
    rules = [l.strip() for l in open(rules_p, encoding="utf-8") if l.strip() and not l.startswith("#")]
    norm = lambda x: x[6:] if x.startswith("res://") else x      # 4.4 起包里的路径不带 res://
    drop = {norm(r[1:].strip()) for r in rules if r.startswith("-")}
    pre = [norm(r) for r in rules if r != "uid_cache" and not r.startswith("-")]
    A = read_pck(base_p)
    B = read_pck(new_p)
    bmap = {e[0]: e for e in B["ents"]}
    anames = {norm(e[0]) for e in A["ents"]}
    missing = sorted(drop - anames)
    assert not missing, "要删的项底包里没有：%s" % missing
    take = {}
    for p, e in bmap.items():
        if any(norm(p).startswith(r) for r in pre):
            assert norm(p) not in drop, "又要换又要删：" + p
            take[p] = e
    fmt, major, minor, patch, flags = A["hdr"]
    assert not (flags & 1), "加密的 pck 不认"
    items = []      # [路径, 字节, md5, fl]
    replaced = added = deleted = 0
    names = set()
    for e in A["ents"]:
        p = e[0]
        names.add(p)
        if norm(p) in drop:
            deleted += 1
        elif p in take:
            d = data_of(B, take[p])
            items.append([p, d, take[p][3], take[p][4]])
            replaced += 1
        elif norm(p) == ".godot/uid_cache.bin" and "uid_cache" in rules:
            d, n_add, n_rm = merge_uid(data_of(A, e), data_of(B, bmap[p]), drop)
            items.append([p, d, hashlib.md5(d).digest(), e[4]])
            print("uid_cache 追加 %d 项、去掉 %d 项" % (n_add, n_rm))
        else:
            items.append([p, data_of(A, e), e[3], e[4]])
    for p, e in take.items():
        if p not in names:
            d = data_of(B, e)
            items.append([p, d, e[3], e[4]])
            added += 1
    out = open(out_p, "wb")
    file_base = 104
    body = bytearray()
    offs = []
    for it in items:
        while len(body) % ALIGN:
            body.append(0)
        offs.append(len(body))
        body += it[1]
    while (file_base + len(body)) % ALIGN:
        body.append(0)
    diroff = file_base + len(body)
    d = struct.pack("<I", len(items))
    for it, o in zip(items, offs):
        pb = it[0].encode("utf-8")
        pad = (4 - len(pb) % 4) % 4
        pb += b"\0" * pad
        d += struct.pack("<I", len(pb)) + pb + struct.pack("<QQ", o if flags & 2 else o + file_base, len(it[1])) + it[2] + struct.pack("<I", it[3])
    head = bytearray(A["head"])
    head[24:40] = struct.pack("<QQ", file_base, diroff)
    out.write(bytes(head))
    out.write(bytes(body))
    out.write(d)
    out.close()
    print("底 %d 项，替换 %d 项，追加 %d 项，删掉 %d 项 → %s（%d 字节）" % (len(A["ents"]), replaced, added, deleted, out_p, diroff + len(d)))
    for p in sorted(take):
        print("  %s %s" % ("*" if p in names else "+", p))
    for p in sorted(drop):
        print("  - %s" % p)


if __name__ == "__main__":
    main()
