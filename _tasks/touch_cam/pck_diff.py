"""比两个 Godot pck 的文件表（路径 + 每个文件的 md5，pck 目录里自带），列出只在一边有的、内容不同的文件。只读。
用法：python -I pck_diff.py <A.pck> <B.pck> [--extract <路径> <输出文件> 取 A 里某个文件的原始字节]
"""
import struct
import sys


def read_dir(path):
    with open(path, "rb") as f:
        head = f.read(40 + 64)
        assert head[:4] == b"GDPC", "不是 pck"
        fmt, major, minor, patch, flags = struct.unpack("<IIIII", head[4:24])
        base, diroff = struct.unpack("<QQ", head[24:40])
        if fmt < 3:
            raise SystemExit("只认 pck 格式 3 以上（4.x 新版）")
        f.seek(diroff)
        n = struct.unpack("<I", f.read(4))[0]
        out = {}
        for _ in range(n):
            ln = struct.unpack("<I", f.read(4))[0]
            p = f.read(ln).rstrip(b"\0").decode("utf-8")
            off, size = struct.unpack("<QQ", f.read(16))
            md5 = f.read(16).hex()
            fl = struct.unpack("<I", f.read(4))[0]
            out[p] = (off + (base if flags & 2 else 0), size, md5, fl)
        return (fmt, major, minor, patch, flags), out


def main():
    a, b = sys.argv[1], sys.argv[2]
    ha, da = read_dir(a)
    if len(sys.argv) > 3 and sys.argv[3] == "--extract":
        off, size, _, _ = da[sys.argv[4]]
        with open(a, "rb") as f:
            f.seek(off)
            open(sys.argv[5], "wb").write(f.read(size))
        return
    hb, db = read_dir(b)
    print("A", ha, len(da), "个文件；B", hb, len(db), "个文件")
    only_a = sorted(set(da) - set(db))
    only_b = sorted(set(db) - set(da))
    diff = sorted(p for p in set(da) & set(db) if da[p][2] != db[p][2])
    print("只在 A：%d" % len(only_a))
    for p in only_a:
        print("  -", p)
    print("只在 B：%d" % len(only_b))
    for p in only_b:
        print("  +", p)
    print("内容不同：%d" % len(diff))
    for p in diff:
        print("  *", p, da[p][1], "→", db[p][1])


if __name__ == "__main__":
    main()
