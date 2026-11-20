const S = require("./sim2.js"); const P = S.P; const N = P.REALM_NAMES;
const v = JSON.parse(process.argv[2]);
if (v.kb) P.KILL_BASE = v.kb; if (v.kg) P.KILL_G = v.kg;
if (v.e0) P.PILL_EXP = [0,1,2,3,4].map(t => v.e0 * Math.pow(v.eg, t));
if (v.pill) P.PILL_EXP = v.pill;
if (v.m0) { P.MED_RATE = []; for (let r = 0; r < 8; r++) P.MED_RATE.push(v.m0 * Math.pow(v.mg, r)); }
if (v.med) P.MED_RATE = v.med;
P.SHOP_KEY = v.shop || { 1: 300, 2: 1200 };
for (const k in (v.P || {})) P[k] = v.P[k];
for (const k of (v.profs || ["normal"])) {
  const m = S.mc(k, 200, 400);
  const tot = m.src.kill + m.src.pill + m.src.med;
  console.log("\n" + m.prof.name, "| 心得", (100*m.src.kill/tot).toFixed(0)+"%", "丹", (100*m.src.pill/tot).toFixed(0)+"%", "打坐", (100*m.src.med/tot).toFixed(0)+"%", "浪费", (100*m.src.waste/(tot+m.src.waste)).toFixed(0)+"%");
  console.log(m.per.map(p => `${N[p.realm]} 第${p.d50??"-"}天 ${p.r50??"-"}局`).join(" | "));
  for (let r = 0; r < 7; r++) { const b = m.byR[r]; const t = b.kill + b.pill + b.med || 1; console.log(`  ${N[r]} 局${b.raids.toFixed(1)} 心得${(100*b.kill/t).toFixed(0)}% 丹${(100*b.pill/t).toFixed(0)}% 坐${(100*b.med/t).toFixed(0)}% 废${(b.waste/t).toFixed(1)}x 灵石入${Math.round(b.coin)} 卡丹${b.stuckKey.toFixed(1)} 卡钱${b.stuckCoin.toFixed(1)}`); }
}
