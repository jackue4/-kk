// 坐标下降：调 心得 / 丹 / 打坐 参数，让「普通玩家」每个境界待的局数和修为来源比例贴近目标
const S = require("./sim2.js");
const P = S.P;
const TARGET_RAIDS = [1, 2, 5, 8, 12, 20, 32];
const TARGET_SHARE = { kill: 0.25, pill: 0.5, med: 0.25 };
P.SHOP_KEY = { 1: 300, 2: 1200 };
const x = { kb: 12, kg: 1.2, e0: 120, eg: 3.0, m0: 0.8, mg: 1.7 };
function apply(v) {
  P.KILL_BASE = v.kb; P.KILL_G = v.kg; P.PILL_EXP = [0, 1, 2, 3, 4].map((t) => v.e0 * Math.pow(v.eg, t));
  P.MED_RATE = []; for (let r = 0; r < 8; r++) P.MED_RATE.push(v.m0 * Math.pow(v.mg, r));
}
function loss(v, n) {
  apply(v);
  const m = S.mc("normal", n || 60, 200);
  let L = 0;
  for (let r = 0; r < 7; r++) {
    const b = m.byR[r]; const t = b.kill + b.pill + b.med || 1;
    L += 3 * Math.pow(Math.log((b.raids + 0.3) / (TARGET_RAIDS[r] + 0.3)), 2);
    if (r >= 2) for (const k in TARGET_SHARE) L += 2 * Math.pow(b[k] / t - TARGET_SHARE[k], 2);
  }
  return L;
}
let best = loss(x);
for (let it = 0; it < 8; it++) {
  for (const k of Object.keys(x)) {
    for (const f of (k === "kg" || k === "mg" || k === "eg") ? [0.95, 1.05] : [0.7, 1.4]) {
      const y = Object.assign({}, x); y[k] = x[k] * f;
      const l = loss(y);
      if (l < best) { best = l; Object.assign(x, y); }
    }
  }
  console.log("iter", it, best.toFixed(3), JSON.stringify(Object.fromEntries(Object.entries(x).map(([k, v]) => [k, +v.toFixed(3)]))));
}
apply(x);
