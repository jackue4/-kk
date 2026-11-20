"""AI 道友联机同步对账：房主那边的本体（_shots/net_ally_host.txt）对队友那边的木偶（_shots/net_ally_mate.txt）。
两个文件都是 ally_selftest.gd 的 net() 按房间时钟每 0.2 秒记的一行：时刻 第几个 x y z 血量比例 状态 喊话数 招式序号 名字。
用法：python -I _tasks/ally_net/compare.py [房主文件] [队友文件]
"""
import sys, math

def load(p):
    rows = []
    for line in open(p, encoding="utf-8"):
        a = line.split()
        if len(a) >= 10:
            rows.append((float(a[0]), int(a[1]), float(a[2]), float(a[3]), float(a[4]), float(a[5]), int(a[6]), int(a[7]), int(a[8]), a[9]))
    return rows

def pct(v, q):
    v = sorted(v)
    return v[min(int(len(v) * q), len(v) - 1)] if v else float("nan")

def main():
    hp = sys.argv[1] if len(sys.argv) > 1 else "_shots/net_ally_host.txt"
    mp = sys.argv[2] if len(sys.argv) > 2 else "_shots/net_ally_mate.txt"
    H, M = load(hp), load(mp)
    print("房主记了 %d 行（%s 位道友），队友记了 %d 行（%s 个木偶）" % (len(H), sorted({r[1] for r in H}), len(M), sorted({r[1] for r in M})))
    if not H or not M:
        print("有一边没记到，没法对账")
        return
    names_h = {r[1]: r[9] for r in H}
    names_m = {r[1]: r[9] for r in M}
    print("名字：房主 %s ｜队友看到 %s ｜一致=%s" % (names_h, names_m, all(names_h.get(k) == v for k, v in names_m.items())))
    by = {}
    for r in H:
        by.setdefault(r[1], []).append(r)
    errs, errs_still, errs_move, hpd, mode_ok, n = [], [], [], [], 0, 0
    for r in M:
        hs = by.get(r[1])
        if not hs:
            continue
        # 房主那边同一时刻的位置：前后两行线性插值
        j = next((i for i in range(len(hs) - 1) if hs[i][0] <= r[0] <= hs[i + 1][0]), None)
        if j is None or hs[j + 1][0] - hs[j][0] > 0.4:
            continue
        a, b2 = hs[j], hs[j + 1]
        k = (r[0] - a[0]) / max(b2[0] - a[0], 1e-6)
        hp_pos = [a[2 + i] + (b2[2 + i] - a[2 + i]) * k for i in range(3)]
        spd = math.dist(a[2:5], b2[2:5]) / max(b2[0] - a[0], 1e-3)
        if spd > 40.0:
            continue          # 这一段是瞬移（重伤归队 / 被拉回队友身边），不算
        n += 1
        e = math.dist(hp_pos, r[2:5])
        errs.append(e)
        (errs_move if spd > 3.0 else errs_still).append(e)
        hpd.append(abs(a[5] - r[5]))
        mode_ok += 1 if a[6] == r[6] else 0
    if not n:
        print("两边的时刻对不上")
        return
    print("对上 %d 个时刻（两边都按同一个系统时钟记，房主的位置按前后两行插值）" % n)
    print("位置误差：平均 %.2f 米、中位 %.2f、95 分位 %.2f、最大 %.2f" % (sum(errs) / n, pct(errs, 0.5), pct(errs, 0.95), max(errs)))
    if errs_still:
        print("  道友基本不动时（%d 个时刻）：平均 %.2f 米、最大 %.2f" % (len(errs_still), sum(errs_still) / len(errs_still), max(errs_still)))
    if errs_move:
        print("  道友在飞时（%d 个时刻，每秒 3 米以上）：平均 %.2f 米、95 分位 %.2f、最大 %.2f" % (len(errs_move), sum(errs_move) / len(errs_move), pct(errs_move, 0.95), max(errs_move)))
    print("血量比例差：平均 %.3f、最大 %.3f；状态一致的时刻 %d%%" % (sum(hpd) / n, max(hpd), round(100 * mode_ok / n)))
    print("喊话数：房主最后 %d 句，队友那边木偶收到的计数最后 %d；招式序号：房主最后 %d，木偶最后 %d" % (H[-1][7], M[-1][7], H[-1][8], M[-1][8]))

main()
