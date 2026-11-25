"""以线上 pck 为底做一个只差几项的包（2026-11-24 查手机内存时用；读写格式同 _tasks/touch_cam/pck_diff.py、别的会话的 pck_overlay.py）。
用法：python -I _tasks/web_mem/pck_patch.py <底.pck> <输出.pck> [--from <小工程导出的.pck> <包内路径>...] [--raw <包内路径>=<本地文件>...] [--setting <项目设置名>=<整数>...]
  --from     从另一个 pck 里取这几项换进来（脚本的 .gdc：只跟脚本自己的源码有关，用一行 project.godot 的小工程 --export-pack 就能出）
  --raw      直接拿本地文件的字节换某一项
  --setting  在底包的 project.binary 里加 / 改一个整数项目设置（ECFG：u32 项数，每项 u32 名字长 + 名字 + u32 值长 + 值；整数的值 = u32 类型 2 + i32）
其余每一项都是底包的原字节。
"""
import hashlib, struct, sys

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
    return {"f": f, "head": head, "flags": flags, "ents": ents}


def data_of(pk, e):
    pk["f"].seek(e[1])
    return pk["f"].read(e[2])


def patch_settings(buf, sets):
    assert buf[:4] == b"ECFG"
    n = struct.unpack_from("<I", buf, 4)[0]
    o = 8
    items = []
    for _ in range(n):
        kl = struct.unpack_from("<I", buf, o)[0]; o += 4
        k = buf[o:o + kl]; o += kl
        vl = struct.unpack_from("<I", buf, o)[0]; o += 4
        v = buf[o:o + vl]; o += vl
        items.append([k, v])
    assert o == len(buf)
    for name, val in sets:
        kb = name.encode("utf-8")
        vb = struct.pack("<Ii", 2, val)
        hit = [it for it in items if it[0].rstrip(b"\0") == kb]
        if hit:
            hit[0][1] = vb
            print("  设置 %s：改成 %d" % (name, val))
        else:
            items.append([kb, vb])
            print("  设置 %s：新加 = %d" % (name, val))
    out = b"ECFG" + struct.pack("<I", len(items))
    for k, v in items:
        out += struct.pack("<I", len(k)) + k + struct.pack("<I", len(v)) + v
    return out


def main():
    base_p, out_p = sys.argv[1], sys.argv[2]
    rest = sys.argv[3:]
    from_p, from_paths, raws, sets = None, [], [], []
    i = 0
    mode = ""
    while i < len(rest):
        a = rest[i]
        if a in ("--from", "--raw", "--setting"):
            mode = a
            if a == "--from":
                i += 1
                from_p = rest[i]
        elif mode == "--from":
            from_paths.append(a)
        elif mode == "--raw":
            k, v = a.split("=", 1)
            raws.append((k, v))
        elif mode == "--setting":
            k, v = a.split("=", 1)
            sets.append((k, int(v)))
        i += 1
    A = read_pck(base_p)
    assert not (A["flags"] & 1), "加密的 pck 不认"
    B = read_pck(from_p) if from_p else None
    bmap = {e[0]: e for e in B["ents"]} if B else {}
    for p in from_paths:
        assert p in bmap, "小工程的包里没有 " + p
    rawmap = {k: open(v, "rb").read() for k, v in raws}
    items = []
    changed = []
    names = {e[0] for e in A["ents"]}
    for p in list(from_paths) + list(rawmap):
        assert p in names, "底包里没有 %s（这个工具只换已有的项）" % p
    for e in A["ents"]:
        p = e[0]
        if p in from_paths:
            items.append([p, data_of(B, bmap[p]), bmap[p][3], bmap[p][4]])
            changed.append(p)
        elif p in rawmap:
            items.append([p, rawmap[p], hashlib.md5(rawmap[p]).digest(), e[4]])
            changed.append(p)
        elif p == "project.binary" and sets:
            d = patch_settings(data_of(A, e), sets)
            items.append([p, d, hashlib.md5(d).digest(), e[4]])
            changed.append(p)
        else:
            items.append([p, data_of(A, e), e[3], e[4]])
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
        pb += b"\0" * ((4 - len(pb) % 4) % 4)
        d += struct.pack("<I", len(pb)) + pb + struct.pack("<QQ", o if A["flags"] & 2 else o + file_base, len(it[1])) + it[2] + struct.pack("<I", it[3])
    head = bytearray(A["head"])
    head[24:40] = struct.pack("<QQ", file_base, diroff)
    with open(out_p, "wb") as out:
        out.write(bytes(head)); out.write(bytes(body)); out.write(d)
    print("底 %d 项，换了 %d 项：%s → %s（%d 字节）" % (len(A["ents"]), len(changed), "、".join(changed), out_p, diroff + len(d)))


main()
