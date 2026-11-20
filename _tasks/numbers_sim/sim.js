// 修仙搜打撤 · 数值成长模拟（2026-11-20）
// 公式照搬游戏代码：raid_data.gd（经验曲线、难度系数、掉落品阶）、raid_items.gd（丹药、掉落表、坊市、丹方）、
// raid_manager.gd（击杀经验、瓶颈、渡劫）、raid_search.gd（搜点）、hall_pills.gd（大厅服丹）。
// 「玩家怎么玩」是假设（每分钟杀几只、搜几个点、多久撤、死亡率……），都在 DEFAULTS 里，可调。
// 浏览器里挂到 window.XiuSim；node 里 require 进来。
(function (root) {
  "use strict";

  // ---------- 游戏里的公式 ----------
  const LV_PER_REALM = 3;
  const REALM_NAMES = ["炼气", "筑基", "结丹", "元婴", "化神", "炼虚", "合体", "大乘"];
  const REGION_NAMES = ["木兰草原", "黄枫谷", "血色禁地", "云梦山", "坠魔谷"];
  const REGION_LV = [1, 6, 10, 13, 16];
  const REGION_REALM = [0, 2, 3, 4, 5];
  // 每个区域两种怪的经验系数（SHAPE_BASE[3]）：beast 1.0 / floater 0.9 / brute 2.4
  const REGION_MOB_K = [[1.0, 0.9], [2.4, 0.9], [1.0, 2.4], [1.0, 0.9], [1.0, 2.4]];
  const TIER_NAMES = ["凡品", "灵器", "法宝", "古宝", "通天灵宝"];
  const TIER_VALUE = [30, 120, 480, 1800, 7500];
  const TIER_W = [1.0, 0.2, 0.04, 0.008, 0.0015];
  const PILLS = [["黄龙丹", 2], ["聚灵丹", 5], ["养元丹", 9], ["凝魂丹", 13], ["培婴丹", 17]];
  const KEYS = ["", "筑基丹", "降尘丹", "定灵丹", "化神丹", "炼虚丹", "合体丹", "大乘丹"];
  const HERB_COST = [20, 60, 160, 400, 900];
  const KEY_PLAN = [[0, 2, 1, 60], [1, 2, 1, 200], [2, 2, 1, 600], [3, 2, 1, 1500], [4, 2, 1, 3500], [4, 3, 2, 7000], [4, 4, 3, 14000]];
  const SITE = {
    jar: { n: [1, 2], bonus: 0.0 },
    herb: { n: [2, 3], bonus: 0.0 },
    grave: { n: [2, 3], bonus: 0.5 },
    vault: { n: [4, 5], bonus: 1.4 },
    urn: { n: [3, 4], bonus: 1.0 },
  };
  const SITE_COUNTS = [[9, 6, 3, 1], [4, 6, 5, 3], [4, 6, 5, 3], [4, 6, 5, 3], [4, 6, 5, 3]]; // jar herb grave vault

  const xpTotal = (lv) => Math.floor(20 * (Math.pow(1.55, lv - 1) - 1) / 0.55);
  const xpNeed = (lv) => xpTotal(lv + 1) - xpTotal(lv);
  const xpReward = (lv, k) => xpNeed(lv) / 8 * k;
  const coeff = (sec, clears, whole = true) => {
    const m = whole ? Math.floor(sec / 60) : sec / 60;
    return (1 + 0.0506 * 2.0 * m) * Math.pow(1.15, clears);
  };
  const ambient = (sec, clears) => Math.min(1 + (coeff(sec, clears, false) - 1) / 0.33, 99);
  const enemyLevel = (ri, sec, clears) => REGION_LV[ri] + Math.floor(ambient(sec, clears)) - 1;
  const realmOf = (lv) => Math.min(Math.floor((lv - 1) / LV_PER_REALM), 7);
  const capLv = (realm) => realm * 3 + 3;
  const pillExp = (t) => xpNeed(PILLS[t][1]) * 0.5;
  const keyValue = (r) => Math.floor(160 * Math.pow(2.1, r - 1));
  const keyShopPrice = (r) => (r >= 1 && r <= 4 ? Math.floor(420 * Math.pow(2.6, r - 1)) : Infinity);
  const killExp = (playerLv, mobLv, k) => Math.max(xpReward(mobLv, k), xpNeed(playerLv) * Math.min(0.015 * k, 0.2));
  const statLine = (base, perK, lv) => base + base * perK * (lv - 1);

  function tierWeights(level, bonus) {
    const luck = level + bonus;
    const ws = [];
    for (let t = 0; t < 5; t++) ws.push(TIER_W[t] * 4 * Math.pow(1.6, luck * t));
    const s = ws.reduce((a, b) => a + b, 0);
    return ws.map((w) => w / s);
  }

  // ---------- 随机数 ----------
  function rng(seed) {
    let a = seed >>> 0;
    const f = () => {
      a = (a + 0x6d2b79f5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
    f.int = (lo, hi) => lo + Math.floor(f() * (hi - lo + 1));
    f.round = (x) => Math.floor(x) + (f() < x - Math.floor(x) ? 1 : 0);
    return f;
  }

  function rollTier(level, r, bonus) {
    const ws = tierWeights(level, bonus);
    let x = r();
    for (let t = 0; t < 5; t++) {
      x -= ws[t];
      if (x <= 0) return t;
    }
    return 0;
  }

  // ---------- 物品 ----------
  const mkPill = (t) => ({ kind: "pill", tier: t, exp: pillExp(t), value: Math.floor(TIER_VALUE[t] * 0.4), slots: 1 });
  const mkHeal = () => ({ kind: "heal", tier: 0, exp: 0, value: 24, slots: 1 });
  const mkKey = (to) => {
    const r = Math.max(1, Math.min(7, to));
    return { kind: "key", to: r, tier: Math.min(r - 1, 4), value: keyValue(r), slots: 1 };
  };
  const mkGear = (t, r) => ({ kind: "gear", tier: t, value: Math.floor(TIER_VALUE[t] * (0.8 + 0.5 * r())), slots: 1 });
  const mkMat = (ri) => ({ kind: "mat", tier: ri, region: ri, value: Math.floor(TIER_VALUE[ri] * 0.6), slots: 2 });
  const mkHerb = (ri) => ({ kind: "herb", tier: ri, region: ri, value: Math.floor(TIER_VALUE[ri] * 0.35), slots: 1 });
  const mkTool = (r) => (r() < 0.35 ? { kind: "tool", value: 220, slots: 1 } : { kind: "tool", value: 70, slots: 1 });

  // raid_items.gd 的 roll
  function roll(level, n, r, bonus) {
    const out = [];
    const keyP = 0.035 + 0.03 * bonus;
    for (let i = 0; i < n; i++) {
      const k = r();
      if (k < keyP) out.push(mkKey(Math.max(1, Math.min(7, level + 1 + (r() < 0.25 ? 1 : 0)))));
      else if (k < keyP + 0.07) out.push(mkTool(r));
      else if (k < 0.34) out.push(r() < 0.3 ? mkHeal() : mkPill(rollTier(level, r, bonus)));
      else if (k < 0.66) out.push(mkGear(rollTier(level, r, bonus), r));
      else if (k < 0.84) out.push(mkMat(level));
      else out.push(mkHerb(level));
    }
    return out;
  }

  // raid_search.gd 的 _finish
  function searchSite(kind, ri, r) {
    const info = SITE[kind];
    const n = r.int(info.n[0], info.n[1]);
    let items = [];
    if (kind === "herb") {
      for (let i = 0; i < n; i++) items.push(mkHerb(r() > 0.12 || ri >= 4 ? ri : ri + 1));
      if (r() < 0.2) items.push(mkPill(rollTier(ri, r, 0)));
    } else if (kind === "vault") {
      items = roll(ri, n, r, info.bonus);
      if (r() < 0.45) items.push(mkKey(Math.max(1, Math.min(7, ri + 1 + (r() < 0.3 ? 1 : 0)))));
    } else {
      items = roll(ri, n, r, info.bonus);
    }
    return items;
  }

  // ---------- 玩家打法的假设 ----------
  const DEFAULTS = {
    raidMin: 14,          // 每局待多少分钟再撤（第 10 分钟开裂隙、15 分钟起熄阵）
    lobbyMin: 1.5,        // 每局之间在大厅 / 洞府花的分钟数
    killsPerMin: 4,       // 每分钟杀几只怪（含搜点守卫）
    eliteShare: 0.08,     // 击杀里精英的占比
    bruteShare: 0.3,      // 有巨汉体型的区域里，巨汉占击杀的比例
    bossKill: 0.6,        // 游荡首领（第 2 分钟左右、之后每 5 分钟一头）打得掉的概率
    lairKill: 0.35,       // 每局打掉本区域巢穴首领的概率（打掉了顺带开宗门宝罐）
    jar: 3, herb: 2, grave: 2, vault: 0.4,   // 每局搜几个点（小数 = 概率）
    deathRate: 0.15,      // 每局陨落的概率（在建议区域）
    pushDeath: 0.12,      // 每越一阶区域，陨落概率再加多少
    pushRegion: false,    // true：去建议修为比自己高一阶的区域
    tribOk: 0.85,         // 渡劫成功率
    perfect: 0.5,         // 渡劫完美格挡的比例（成功后多给 30% × 它 的修为）
    ringCap: 1,           // 储物戒格数（死了也保住，破境丹放这）
    bag: 12,              // 背包格数
    craftPills: true,     // 用多余的灵草炼修为丹
    maxRaids: 400,
    seed: 1,
  };

  function pickRegion(realm, cfg) {
    const lim = realm + (cfg.pushRegion ? 1 : 0);
    let best = 0;
    for (let i = 0; i < 5; i++) if (REGION_REALM[i] <= lim) best = i;
    return best;
  }

  // ---------- 一个存档从零玩到大乘 ----------
  function simulate(cfgIn) {
    const cfg = Object.assign({}, DEFAULTS, cfgIn || {});
    const r = rng(cfg.seed * 2654435761 + 12345);
    const P = {
      realm: 0, lv: 1, xp: 0, lingshi: 300,
      stash: [],          // 洞府仓库
      keys: [],           // 身上 / 仓库的破境丹（to）
      herbs: [0, 0, 0, 0, 0], mats: [0, 0, 0, 0, 0],
    };
    const src = { kill: 0, boss: 0, pill: 0, trib: 0, waste: 0 };
    const keySrc = { drop: 0, vault: 0, shop: 0, craft: 0 };
    const realmAt = [{ raid: 0, min: 0, lingshi: 300 }];   // 到达每个境界时的局数 / 分钟
    const timeline = [];
    let minutes = 0, stuckRaids = 0, deaths = 0;
    const srcByRealm = [];
    for (let i = 0; i < 8; i++) srcByRealm.push({ kill: 0, boss: 0, pill: 0, trib: 0, waste: 0, raids: 0, stuck: 0, deaths: 0, min: 0 });

    const atCap = () => realmOf(P.lv + 1) > P.realm && P.xp >= xpNeed(P.lv) - 0.01;
    const hasKey = (to) => P.keys.indexOf(to) >= 0;
    const takeKey = (to) => { P.keys.splice(P.keys.indexOf(to), 1); };

    // raid_manager.gd 的 add_exp（溢出的记为浪费）
    function addExp(v, tag) {
      const R = srcByRealm[P.realm];
      let used = 0;
      let left = v;
      while (left > 0) {
        if (P.lv >= 99) break;
        const need = xpNeed(P.lv);
        if (realmOf(P.lv + 1) > P.realm) {
          const room = Math.max(0, need - P.xp);
          const take = Math.min(room, left);
          P.xp += take; used += take; left -= take;
          break;
        }
        if (P.xp + left >= need) {
          const take = need - P.xp;
          used += take; left -= take; P.xp = 0; P.lv += 1;
        } else {
          P.xp += left; used += left; left = 0;
        }
      }
      src[tag] += used; R[tag] += used;
      src.waste += left; R.waste += left;
      return used;
    }

    function tribulation() {
      const to = P.realm + 1;
      if (r() < cfg.tribOk) {
        P.lv = Math.max(P.lv + 1, to * 3 + 1);
        P.realm = to;
        takeKey(to);
        const bonus = xpNeed(P.lv) * 0.3 * cfg.perfect;
        P.xp = 0;
        P.xp = Math.min(bonus, xpNeed(P.lv));
        src.trib += P.xp; srcByRealm[P.realm].trib += P.xp;
        return true;
      }
      P.xp = xpNeed(P.lv) * 0.5;
      return false;
    }

    // 大厅：一键服丹（hall_pills.gd：服到瓶颈就停，剩下的放回仓库）
    function eatPills() {
      const pills = P.stash.filter((it) => it.kind === "pill");
      P.stash = P.stash.filter((it) => it.kind !== "pill");
      const left = [];
      for (const it of pills) {
        if (atCap() || P.realm >= 7 && P.lv >= 99) { left.push(it); continue; }
        addExp(it.exp, "pill");
      }
      P.stash.push(...left);
    }

    function keyRecipeOk(to) {
      const p = KEY_PLAN[to - 1];
      return P.herbs[p[0]] >= p[1] && P.mats[p[0]] >= p[2] && P.lingshi >= p[3];
    }

    function hall() {
      // 仓库里的东西：法宝、符箓、回春丹全卖；灵材 / 灵草先记下（炼丹用），丹药留着吃
      const keep = [];
      for (const it of P.stash) {
        if (it.kind === "pill") keep.push(it);
        else if (it.kind === "herb") P.herbs[it.region] += 1;
        else if (it.kind === "mat") P.mats[it.region] += 1;
        else if (it.kind === "key") P.keys.push(it.to);
        else P.lingshi += it.value;
      }
      P.stash = keep;
      // 下一颗破境丹：没有就先炼、炼不了就买
      const to = P.realm + 1;
      if (to <= 7 && !hasKey(to)) {
        if (keyRecipeOk(to)) {
          const p = KEY_PLAN[to - 1];
          P.herbs[p[0]] -= p[1]; P.mats[p[0]] -= p[2]; P.lingshi -= p[3];
          P.keys.push(to); keySrc.craft += 1;
        } else if (P.lingshi >= keyShopPrice(to)) {
          P.lingshi -= keyShopPrice(to);
          P.keys.push(to); keySrc.shop += 1;
        }
      }
      // 卖掉用不上的灵材（留够下一颗破境丹的）
      const needPlan = to <= 7 && !hasKey(to) ? KEY_PLAN[to - 1] : null;
      for (let t = 0; t < 5; t++) {
        const reserve = needPlan && needPlan[0] === t ? needPlan[2] : 0;
        while (P.mats[t] > reserve) { P.mats[t] -= 1; P.lingshi += Math.floor(TIER_VALUE[t] * 0.6); }
      }
      // 多的灵草炼成修为丹（灵石够才炼；留够下一颗破境丹的灵草）
      if (cfg.craftPills) {
        for (let t = 4; t >= 0; t--) {
          const reserve = needPlan && needPlan[0] === t ? needPlan[1] : 0;
          while (P.herbs[t] > reserve && P.lingshi >= HERB_COST[t] + (needPlan ? needPlan[3] * 0.0 : 0)) {
            P.herbs[t] -= 1; P.lingshi -= HERB_COST[t];
            P.stash.push(mkPill(t));
          }
        }
      }
      eatPills();
    }

    // 背包：到撤离时按「每格价值」取前 bag 格；破境丹进储物戒（保命），修为丹按价值 ×2 算（这套玩法就是吃丹）
    //（下一颗破境丹要是坊市买不到、得自己炼，炼它缺的灵草 / 灵材排在最前面）
    function packBag(items) {
      const keys = items.filter((it) => it.kind === "key" && it.to > P.realm);
      const rest = items.filter((it) => it.kind !== "key");
      const to = P.realm + 1;
      const want = { herb: -1, mat: -1, nh: 0, nm: 0 };
      if (to <= 7 && !hasKey(to) && keyShopPrice(to) === Infinity) {
        const p = KEY_PLAN[to - 1];
        want.herb = p[0]; want.nh = Math.max(0, p[1] - P.herbs[p[0]]); want.nm = Math.max(0, p[2] - P.mats[p[0]]);
      }
      const score = (it) => {
        if (it.kind === "herb" && it.region === want.herb && want.nh > 0) { want.nh -= 1; return 1e12; }
        if (it.kind === "mat" && it.region === want.herb && want.nm > 0) { want.nm -= 1; return 1e12; }
        return (it.kind === "pill" ? it.value * 2 : it.value) / it.slots;
      };
      for (const it of rest) it._s = score(it);
      rest.sort((a, b) => b._s - a._s);
      const ring = [], bag = [];
      let ringUsed = 0, used = 0;
      for (const k of keys) {
        if (ringUsed < cfg.ringCap) { ring.push(k); ringUsed += 1; }
        else if (used + 1 <= cfg.bag) { bag.push(k); used += 1; }
      }
      for (const it of rest) {
        if (used + it.slots <= cfg.bag) { bag.push(it); used += it.slots; }
      }
      return { ring, bag };
    }

    function oneRaid(raidNo) {
      const ri = pickRegion(P.realm, cfg);
      const R0 = srcByRealm[P.realm];
      R0.raids += 1;
      const startRealm = P.realm;
      const over = Math.max(0, REGION_REALM[ri] - P.realm);
      const dies = r() < Math.min(0.9, cfg.deathRate + cfg.pushDeath * over);
      const T = cfg.raidMin;
      const deathMin = dies ? 2 + r() * (T - 2) : Infinity;
      let clears = 0;
      const picked = [];
      // 搜点：随机分到各分钟
      const sites = [];
      const add = (kind, x) => { const n = r.round(x); for (let i = 0; i < n; i++) sites.push({ kind, at: r() * T }); };
      add("jar", cfg.jar); add("herb", cfg.herb); add("grave", cfg.grave); add("vault", cfg.vault);
      const lairAt = r() < cfg.lairKill ? 4 + r() * (T - 5) : Infinity;
      const bossTimes = [];
      for (let t = 2.2; t < T; t += 5) bossTimes.push(t);
      const mobK = REGION_MOB_K[ri];
      const hasBrute = mobK.indexOf(2.4) >= 0;
      for (let m = 0; m < T; m++) {
        if (m >= deathMin) break;
        const sec = m * 60 + 30;
        const lvM = enemyLevel(ri, sec, clears);
        const C = coeff(sec, clears);
        const vmul = Math.pow(C, 1.25);
        const got = [];
        const kills = r.round(cfg.killsPerMin);
        for (let i = 0; i < kills; i++) {
          const elite = r() < cfg.eliteShare;
          let k;
          if (hasBrute) k = r() < cfg.bruteShare ? 2.4 : mobK.find((x) => x !== 2.4);
          else k = mobK[r() < 0.5 ? 0 : 1];
          if (elite) k *= 3;
          addExp(killExp(P.lv, lvM, k), "kill");
          if (elite) got.push(...roll(ri, 2, r, 0.5));
          else if (r() < 0.55) got.push(...roll(ri, 1, r, 0.0));
        }
        for (const bt of bossTimes) {
          if (bt >= m && bt < m + 1 && r() < cfg.bossKill) {
            addExp(killExp(P.lv, lvM, 14), "boss");
            got.push(...roll(ri, 3, r, 0.8));
          }
        }
        if (lairAt >= m && lairAt < m + 1) {
          addExp(killExp(P.lv, lvM, 14), "boss");
          got.push(...roll(ri, 5, r, 1.3));
          clears += 1;
          got.push(...searchSite("urn", ri, r));
        }
        for (const s of sites) if (s.at >= m && s.at < m + 1) got.push(...searchSite(s.kind, ri, r));
        for (const it of got) {
          it.value = Math.floor(it.value * vmul);
          picked.push(it);
        }
        // 身上（背包 / 储物戒 / 带进来的）有破境丹、修为到瓶颈：起雷劫
        const pickedKeys = picked.filter((it) => it.kind === "key").map((it) => it.to);
        if (atCap() && P.realm < 7) {
          const to = P.realm + 1;
          const fromPicked = pickedKeys.indexOf(to) >= 0;
          if (fromPicked) {
            const idx = picked.findIndex((it) => it.kind === "key" && it.to === to);
            P.keys.push(to);
            picked.splice(idx, 1);
            keySrc.drop += 1;
          }
          if (hasKey(to)) tribulation();
        }
      }
      minutes += Math.min(T, deathMin) + cfg.lobbyMin;
      R0.min += Math.min(T, deathMin) + cfg.lobbyMin;
      if (dies) {
        deaths += 1; R0.deaths += 1;
        // 死了：背包清空，储物戒里的破境丹保住
        const keys = picked.filter((it) => it.kind === "key").slice(0, cfg.ringCap);
        for (const k of keys) { P.keys.push(k.to); keySrc.drop += 1; }
      } else {
        const { ring, bag } = packBag(picked);
        for (const k of ring) { P.keys.push(k.to); keySrc.drop += 1; }
        for (const it of bag) {
          if (it.kind === "key") { P.keys.push(it.to); keySrc.drop += 1; }
          else P.stash.push(it);
        }
      }
      if (atCap() && P.realm < 7 && !hasKey(P.realm + 1)) { stuckRaids += 1; R0.stuck += 1; }
      hall();
      if (P.realm > startRealm) {
        for (let k = startRealm + 1; k <= P.realm; k++) realmAt[k] = { raid: raidNo + 1, min: minutes, lingshi: P.lingshi };
      }
      timeline.push({ raid: raidNo + 1, min: minutes, realm: P.realm, lv: P.lv, prog: P.lv + P.xp / xpNeed(P.lv), lingshi: P.lingshi, region: ri, dead: dies });
    }

    for (let i = 0; i < cfg.maxRaids && P.realm < 7; i++) oneRaid(i);
    return { cfg, realmAt, timeline, src, srcByRealm, keySrc, stuckRaids, deaths, raids: timeline.length, minutes, final: { realm: P.realm, lv: P.lv, lingshi: P.lingshi } };
  }

  // 跑 n 个存档，给每个境界的局数 / 小时的分位数
  function monteCarlo(cfg, n) {
    const runs = [];
    for (let i = 0; i < n; i++) runs.push(simulate(Object.assign({}, cfg, { seed: (cfg && cfg.seed || 1) * 1000 + i })));
    const q = (arr, p) => {
      if (!arr.length) return null;
      const s = arr.slice().sort((a, b) => a - b);
      return s[Math.min(s.length - 1, Math.floor(p * s.length))];
    };
    const perRealm = [];
    for (let k = 0; k < 8; k++) {
      const hrs = runs.filter((x) => x.realmAt[k]).map((x) => x.realmAt[k].min / 60);
      const raids = runs.filter((x) => x.realmAt[k]).map((x) => x.realmAt[k].raid);
      perRealm.push({ realm: k, reached: hrs.length / n, h10: q(hrs, 0.1), h50: q(hrs, 0.5), h90: q(hrs, 0.9), r10: q(raids, 0.1), r50: q(raids, 0.5), r90: q(raids, 0.9) });
    }
    // 每个境界里的修为来源（平均）
    const share = [];
    for (let k = 0; k < 8; k++) {
      const s = { kill: 0, boss: 0, pill: 0, trib: 0, waste: 0, raids: 0, stuck: 0, deaths: 0, min: 0 };
      for (const x of runs) for (const key in s) s[key] += x.srcByRealm[k][key];
      for (const key in s) s[key] /= n;
      share.push(s);
    }
    const keySrc = { drop: 0, vault: 0, shop: 0, craft: 0 };
    for (const x of runs) for (const key in keySrc) keySrc[key] += x.keySrc[key] / n;
    return { runs, perRealm, share, keySrc, median: runs.slice().sort((a, b) => a.minutes - b.minutes)[Math.floor(n / 2)] };
  }

  const api = {
    DEFAULTS, REALM_NAMES, REGION_NAMES, REGION_LV, REGION_REALM, REGION_MOB_K, PILLS, KEYS, KEY_PLAN, TIER_NAMES, TIER_VALUE, SITE_COUNTS,
    xpTotal, xpNeed, xpReward, coeff, ambient, enemyLevel, realmOf, capLv, pillExp, keyShopPrice, killExp, statLine, tierWeights,
    simulate, monteCarlo,
  };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.XiuSim = api;
})(typeof window !== "undefined" ? window : this);
