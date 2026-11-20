const S = require("./sim2.js");
const N = S.P.REALM_NAMES;
const profs = process.argv.slice(2).length ? process.argv.slice(2) : ["casual", "normal", "hardcore"];
for (const k of profs) {
  const m = S.mc(k, 200, 400);
  const tot = m.src.kill + m.src.pill + m.src.med;
  console.log("\n" + m.prof.name, "| 心得", (100*m.src.kill/tot).toFixed(0)+"%", "丹", (100*m.src.pill/tot).toFixed(0)+"%", "打坐", (100*m.src.med/tot).toFixed(0)+"%", "浪费", (100*m.src.waste/(tot+m.src.waste)).toFixed(0)+"%", "| 卡丹", m.stuckKey.toFixed(1), "卡灵石", m.stuckCoin.toFixed(1));
  console.log(m.per.map(p => `${N[p.realm]} 第${p.d50??"-"}天(${p.d10??"-"}-${p.d90??"-"}) ${p.r50??"-"}局`).join(" | "));
  for (let r = 0; r < 7; r++) { const b = m.byR[r]; const t = b.kill + b.pill + b.med || 1; console.log(`  ${N[r]} 局${b.raids.toFixed(1)} 心得${(100*b.kill/t).toFixed(0)}% 丹${(100*b.pill/t).toFixed(0)}% 坐${(100*b.med/t).toFixed(0)}% 废${(b.waste/t).toFixed(1)}x 灵石入${Math.round(b.coin)} 卡丹${b.stuckKey.toFixed(1)} 卡钱${b.stuckCoin.toFixed(1)}`); }
}
