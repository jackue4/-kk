// 修仙搜打撤 · 新数值框架的模拟（2026-11-20 第二版）
// 和 sim.js 的区别：怪的等级 / 掉落价值看「地点」（区域 + 深度），不看局内时间；击杀只攒心得、撤离成功才结算；
// 修为丹是固定量（品阶越高越多）+ 丹毒；洞府打坐（含离线）是第三条来源；突破要 修为满 + 破境丹 + 灵石。
// 参数都在 P 里，和 scripts/progression.gd 一一对应（改一边要同步另一边）。
(function (root) {
  "use strict";

  const P = {
    XP_BASE: 2000,                // 升级累计修为 = XP_BASE × (1.55^(L-1) - 1) / 0.55（旧版是 20）
    XP_GROWTH: 1.4,
    LV_PER_REALM: 3,
    REALM_XP_MULT: [0.3, 0.75, 1, 1, 1, 1, 1, 1],   // 炼气、筑基打折：新手第一局就能筑基
    REALM_NAMES: ["炼气", "筑基", "结丹", "元婴", "化神", "炼虚", "合体", "大乘"],
    // 区域：基础等级、建议境界（能去的最低境界）、深度加的等级、修为丹品阶的运气、破境丹表 {通往境界: 权重}
    REGIONS: [
      { name: "木兰草原", lv: 1, realm: 0, depth_lv: 4, luck: 0.0, keys: { 1: 0.6, 2: 0.4 } },
      { name: "黄枫谷", lv: 7, realm: 2, depth_lv: 4, luck: 1.0, keys: { 3: 0.75, 4: 0.25 } },
      { name: "血色禁地", lv: 10, realm: 3, depth_lv: 4, luck: 2.0, keys: { 4: 0.75, 5: 0.25 } },
      { name: "云梦山", lv: 13, realm: 4, depth_lv: 4, luck: 3.0, keys: { 5: 0.75, 6: 0.25 } },
      { name: "坠魔谷", lv: 16, realm: 5, depth_lv: 8, luck: 4.0, keys: { 6: 0.6, 7: 0.4 } },
    ],
    DEPTH_LUCK: 1.0,              // 区域里越深，掉落品阶的运气再加这么多
    DEPTH_VALUE: 0.8,             // 越深东西越值钱：价值 × (1 + DEPTH_VALUE × 深度)
    // 心得：每杀一只 = KILL_BASE × KILL_G^(怪等级-1) × 体型系数（精英 ×3、首领 ×14）；撤离成功才结算，每局封顶 KILL_CAP × 当前一级所需
    KILL_BASE: 16.5,
    KILL_G: 1.14,
    KILL_CAP: 0.4,                // 每局心得最多 = 当前境界总修为 × 0.4
    DEATH_KEEP: 0.0,              // 陨落时心得留下几成
    // 修为丹：五个品阶各给多少（固定量），丹毒：每颗 +1，效果 × 1/(1 + TOX_K × 丹毒)，每分钟消 TOX_DECAY（打坐时 ×3）
    PILL_EXP: [84, 216, 556, 1430, 3678],
    // 修为丹品质：下品 / 中品 / 上品 / 极品，药力倍数 GRADE_MULT；权重 GRADE_W[g] × (1 + GRADE_DEPTH × 深度)^g
    GRADE_NAMES: ["下品", "中品", "上品", "极品"],
    GRADE_MULT: [1, 2, 4, 8],
    GRADE_W: [1, 0.35, 0.1, 0.02],
    GRADE_DEPTH: 4,
    TOX_K: 0.05,
    TOX_DECAY: 0.25,
    // 打坐：每秒修为（按境界），离线按 OFFLINE_RATE 折算，最多 OFFLINE_CAP_H 小时
    MED_RATE: [0.56, 0.9, 1.46, 2.36, 3.81, 6.15, 9.94, 16.05],
    OFFLINE_RATE: 0.5,
    OFFLINE_CAP_H: 8,
    // 破境丹：每件掉落的概率 KEY_P + KEY_PB × 加成；宝库额外 VAULT_KEY；巢穴首领必掉 1 片碎片，FRAG_N 片合 1 颗（丹房，另收灵石）
    KEY_P: 0.006,
    KEY_PB: 0.006,
    VAULT_KEY: 0.15,
    FRAG_N: 3,
    // 突破：灵石（按要去的境界），渡劫成功率
    BREAK_COST: [0, 500, 2000, 6500, 19000, 55000, 110000, 240000],
    KEY_CRAFT_COST: [0, 100, 400, 1500, 5000, 14000, 36000, 90000],
    SHOP_KEY: { 1: 300, 2: 1200 }, // 坊市只卖筑基丹、降尘丹
    TRIB_OK: 0.85,
    PILL_SELL: 0.5,               // 修为丹卖价 ≈ 药力 × 0.5 灵石
    TIER_VALUE: [30, 120, 480, 1800, 7500],
    TIER_W: [1.0, 0.2, 0.04, 0.008, 0.0015],
  };

  const xpTotal = (lv) => Math.floor(P.XP_BASE * (Math.pow(P.XP_GROWTH, lv - 1) - 1) / (P.XP_GROWTH - 1));
  const xpNeed = (lv) => Math.floor((xpTotal(lv + 1) - xpTotal(lv)) * P.REALM_XP_MULT[Math.min(Math.floor((lv - 1) / 3), 7)]);
  const realmOf = (lv) => Math.min(Math.floor((lv - 1) / 3), 7);
  const realmTotal = (r) => { let s = 0; for (let l = r * 3 + 1; l <= r * 3 + 3; l++) s += xpNeed(l); return s; };
  const pickRegion = (realm) => { let b = 0; for (let i = 0; i < 5; i++) if (P.REGIONS[i].realm <= realm) b = i; return b; };
  function tierW(luck) {
    const ws = []; for (let t = 0; t < 5; t++) ws.push(P.TIER_W[t] * 4 * Math.pow(1.6, luck * t));
    const s = ws.reduce((a, b) => a + b, 0); return ws.map((w) => w / s);
  }

  function rng(seed) {
    let a = seed >>> 0;
    const f = () => { a = (a + 0x6d2b79f5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
    f.int = (lo, hi) => lo + Math.floor(f() * (hi - lo + 1));
    f.round = (x) => Math.floor(x) + (f() < x - Math.floor(x) ? 1 : 0);
    f.pick = (tab) => { let s = 0; for (const k in tab) s += tab[k]; let x = f() * s; for (const k in tab) { x -= tab[k]; if (x <= 0) return +k; } return +Object.keys(tab)[0]; };
    return f;
  }

  const PROFILES = {
    casual: { name: "休闲：每天 2 局", raidsPerDay: 2, raidMin: 12, kpm: 3, death: 0.25, sites: 5, bossKill: 0.3, lair: 0.15, depth: 0.2 },
    normal: { name: "普通：每天 4 局", raidsPerDay: 4, raidMin: 14, kpm: 4, death: 0.15, sites: 7, bossKill: 0.6, lair: 0.35, depth: 0.35 },
    hardcore: { name: "肝帝：每天 12 局", raidsPerDay: 12, raidMin: 18, kpm: 5, death: 0.1, sites: 9, bossKill: 0.8, lair: 0.6, depth: 0.5 },
  };

  function simulate(prof, seed, maxDays) {
    const r = rng(seed * 2654435761 + 7);
    const S = { realm: 0, lv: 1, xp: 0, lingshi: 300, tox: 0, keys: [], frags: {}, pills: [] };
    const src = { kill: 0, pill: 0, med: 0, trib: 0, waste: 0 };
    const byR = []; for (let i = 0; i < 8; i++) byR.push({ kill: 0, pill: 0, med: 0, waste: 0, raids: 0, coin: 0, stuckKey: 0, stuckCoin: 0 });
    const at = [{ day: 0, raid: 0 }];
    let raids = 0, stuckKey = 0, stuckCoin = 0;
    const cap = () => realmOf(S.lv + 1) > S.realm && S.xp >= xpNeed(S.lv) - 1e-6;
    function add(v, tag) {
      let left = v;
      while (left > 0 && S.lv < 99) {
        const need = xpNeed(S.lv);
        if (realmOf(S.lv + 1) > S.realm) { const t = Math.min(need - S.xp, left); S.xp += t; src[tag] += t; byR[S.realm][tag] += t; left -= t; break; }
        if (S.xp + left >= need) { const t = need - S.xp; src[tag] += t; byR[S.realm][tag] += t; left -= t; S.xp = 0; S.lv++; }
        else { S.xp += left; src[tag] += left; byR[S.realm][tag] += left; left = 0; }
      }
      src.waste += Math.max(0, left); byR[S.realm].waste += Math.max(0, left);
    }
    function tryBreak(dayNo) {
      while (cap() && S.realm < 7) {
        const to = S.realm + 1;
        const ki = S.keys.indexOf(to);
        if (ki < 0) { // 碎片合成
          if ((S.frags[to] || 0) >= P.FRAG_N && S.lingshi >= P.KEY_CRAFT_COST[to]) { S.frags[to] -= P.FRAG_N; S.lingshi -= P.KEY_CRAFT_COST[to]; S.keys.push(to); continue; }
          if (P.SHOP_KEY[to] && S.lingshi >= P.SHOP_KEY[to]) { S.lingshi -= P.SHOP_KEY[to]; S.keys.push(to); continue; }
          stuckKey++; byR[S.realm].stuckKey++; return;
        }
        if (S.lingshi < P.BREAK_COST[to]) {
          // 卡在瓶颈、灵石不够：把仓库里用不上的修为丹卖掉（药力低的先卖）
          S.pills.sort((a, b) => a - b);
          while (S.lingshi < P.BREAK_COST[to] && S.pills.length) S.lingshi += Math.floor(S.pills.shift() * P.PILL_SELL);
          if (S.lingshi < P.BREAK_COST[to]) { stuckCoin++; byR[S.realm].stuckCoin++; return; }
        }
        S.lingshi -= P.BREAK_COST[to];
        if (r() < P.TRIB_OK) {
          S.keys.splice(ki, 1);
          S.realm = to; S.lv = Math.max(S.lv + 1, to * 3 + 1); S.xp = 0;
          at[to] = { day: dayNo, raid: raids };
        } else { S.xp = xpNeed(S.lv) * 0.5; return; }
      }
    }
    function eatPills() {
      const keep = [];
      S.pills.sort((a, b) => b - a);
      for (const t of S.pills) {
        if (cap()) { keep.push(t); continue; }
        add(t / (1 + P.TOX_K * S.tox), "pill");
        S.tox += 1;
      }
      S.pills = keep;
    }
    function rollItems(ri, depth, n, bonus, out) {
      const reg = P.REGIONS[ri];
      const keyP = P.KEY_P + P.KEY_PB * bonus;
      for (let i = 0; i < n; i++) {
        const k = r();
        if (k < keyP) out.push({ kind: "key", to: r.pick(reg.keys) });
        else if (k < keyP + 0.07) out.push({ kind: "tool", value: 120 });
        else if (k < 0.34) {
          if (r() < 0.3) out.push({ kind: "heal", value: 24 });
          else {
            const w = tierW(reg.luck + depth * P.DEPTH_LUCK + bonus); let x = r(), t = 0; for (; t < 4; t++) { x -= w[t]; if (x <= 0) break; }
            const gw = P.GRADE_W.map((v, g) => v * Math.pow(1 + P.GRADE_DEPTH * depth, g)); const gs = gw.reduce((a2, b2) => a2 + b2, 0);
            let y = r() * gs, g = 0; for (; g < 3; g++) { y -= gw[g]; if (y <= 0) break; }
            out.push({ kind: "pill", tier: t, grade: g, value: P.TIER_VALUE[t] * 0.4 * P.GRADE_MULT[g] });
          }
        } else if (k < 0.66) { const w = tierW(reg.luck + depth * P.DEPTH_LUCK + bonus); let x = r(), t = 0; for (; t < 4; t++) { x -= w[t]; if (x <= 0) break; } out.push({ kind: "gear", value: P.TIER_VALUE[t] * (0.8 + 0.5 * r()) }); }
        else if (k < 0.84) out.push({ kind: "mat", value: P.TIER_VALUE[ri] * 0.6, slots: 2 });
        else out.push({ kind: "herb", value: P.TIER_VALUE[ri] * 0.35 });
      }
    }
    function raid(dayNo) {
      raids++; byR[S.realm].raids++;
      const ri = pickRegion(S.realm);
      const reg = P.REGIONS[ri];
      const depth = Math.max(0, Math.min(1, prof.depth + 0.45 * (S.realm - reg.realm) + (r() - 0.5) * 0.3));
      const mobLv = reg.lv + Math.round(depth * reg.depth_lv);
      const dies = r() < prof.death;
      const T = dies ? 2 + r() * (prof.raidMin - 2) : prof.raidMin;
      const items = [];
      let xin = 0;
      const unit = P.KILL_BASE * Math.pow(P.KILL_G, mobLv - 1);
      const need = xpNeed(S.lv);
      const kills = r.round(prof.kpm * T);
      for (let i = 0; i < kills; i++) {
        const elite = r() < 0.08;
        const k = (r() < 0.3 ? 2.4 : 1.0) * (elite ? 3 : 1);
        xin += unit * k;
        if (elite) rollItems(ri, depth, 2, 0.5, items); else if (r() < 0.55) rollItems(ri, depth, 1, 0, items);
      }
      for (let t = 2.2; t < T; t += 5) if (r() < prof.bossKill) { xin += unit * 14; rollItems(ri, depth, 3, 0.8, items); }
      if (r() < prof.lair && T > 6) {
        xin += unit * 14; rollItems(ri, depth, 5, 1.3, items); rollItems(ri, depth, 3, 1.0, items);
        const to = r.pick(reg.keys); S.frags[to] = (S.frags[to] || 0) + 1;
      }
      const nSites = r.round(prof.sites * T / prof.raidMin);
      for (let i = 0; i < nSites; i++) {
        const kind = r() < 0.06 ? "vault" : r() < 0.35 ? "jar" : r() < 0.6 ? "herb" : "grave";
        const n = kind === "vault" ? 4.5 : kind === "jar" ? 1.5 : 2.5;
        rollItems(ri, depth, r.round(n), kind === "vault" ? 1.4 : kind === "grave" ? 0.5 : 0, items);
        if (kind === "vault" && r() < P.VAULT_KEY) items.push({ kind: "key", to: r.pick(reg.keys) });
      }
      xin = Math.min(xin, realmTotal(S.realm) * P.KILL_CAP);
      const vmul = 1 + P.DEPTH_VALUE * depth;
      if (dies) {
        add(xin * P.DEATH_KEEP, "kill");
        const k = items.find((it) => it.kind === "key" && it.to > S.realm); if (k) S.keys.push(k.to);   // 储物戒保住一颗
      } else {
        add(xin, "kill");
        // 背包 12 格：破境丹、修为丹优先，其余按价值
        const keys = items.filter((it) => it.kind === "key" && it.to > S.realm);
        const rest = items.filter((it) => it.kind !== "key").sort((a, b) => (b.kind === "pill" ? 1e9 : b.value / (b.slots || 1)) - (a.kind === "pill" ? 1e9 : a.value / (a.slots || 1)));
        let used = 0;
        for (const k of keys) { S.keys.push(k.to); }
        for (const it of rest) {
          const s = it.slots || 1; if (used + s > 12) continue; used += s;
          if (it.kind === "pill") S.pills.push(P.PILL_EXP[it.tier] * P.GRADE_MULT[it.grade]); else { const v = Math.floor(it.value * vmul); S.lingshi += v; byR[S.realm].coin += v; }
        }
      }
      // 局间：打坐 1.5 分钟、丹毒消一点；回洞府服丹、突破
      S.tox = Math.max(0, S.tox - P.TOX_DECAY * (T + 1.5));
      eatPills();
      tryBreak(dayNo);
    }
    for (let d = 1; d <= maxDays && S.realm < 7; d++) {
      for (let i = 0; i < prof.raidsPerDay && S.realm < 7; i++) raid(d);
      // 下线：离线打坐 min(剩余时间, 上限) × 折算
      const offH = Math.min(P.OFFLINE_CAP_H, 24 - prof.raidsPerDay * (prof.raidMin + 1.5) / 60);
      add(P.MED_RATE[S.realm] * 3600 * offH * P.OFFLINE_RATE, "med");
      S.tox = Math.max(0, S.tox - P.TOX_DECAY * 60 * offH * 3);
      eatPills();
      tryBreak(d);
    }
    return { at, src, byR, raids, stuckKey, stuckCoin, final: { realm: S.realm, lv: S.lv, lingshi: S.lingshi } };
  }

  function mc(profKey, n, maxDays) {
    const prof = PROFILES[profKey];
    const runs = []; for (let i = 0; i < n; i++) runs.push(simulate(prof, i + 1, maxDays || 400));
    const q = (a, p) => { if (!a.length) return null; const s = a.slice().sort((x, y) => x - y); return s[Math.min(s.length - 1, Math.floor(p * s.length))]; };
    const per = [];
    for (let k = 1; k < 8; k++) {
      const got = runs.filter((x) => x.at[k]);
      per.push({ realm: k, reached: got.length / n, d50: q(got.map((x) => x.at[k].day), 0.5), d10: q(got.map((x) => x.at[k].day), 0.1), d90: q(got.map((x) => x.at[k].day), 0.9), r50: q(got.map((x) => x.at[k].raid), 0.5) });
    }
    const src = { kill: 0, pill: 0, med: 0, trib: 0, waste: 0 };
    for (const x of runs) for (const k in src) src[k] += x.src[k] / n;
    const stuckKey = runs.reduce((a, x) => a + x.stuckKey, 0) / n, stuckCoin = runs.reduce((a, x) => a + x.stuckCoin, 0) / n;
    const byR = []; for (let k = 0; k < 8; k++) { const o = { kill: 0, pill: 0, med: 0, waste: 0, raids: 0, coin: 0, stuckKey: 0, stuckCoin: 0 }; for (const x of runs) for (const f in o) o[f] += x.byR[k][f] / n; byR.push(o); }
    return { prof, per, src, byR, stuckKey, stuckCoin };
  }

  const api = { P, PROFILES, xpTotal, xpNeed, realmTotal, pickRegion, tierW, simulate, mc };
  if (typeof module !== "undefined" && module.exports) module.exports = api; else root.XiuSim2 = api;
})(typeof window !== "undefined" ? window : this);
