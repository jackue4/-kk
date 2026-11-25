#!/bin/bash
# 真人对打改动后的单机回归（约 12 分钟）：每项的脚本报错 / 着色器报错数汇总到 _tasks/pvp_rules/regress.txt
cd "D:/GodotProjects/修仙游戏"
OUT=_tasks/pvp_rules/regress.txt
: > $OUT
run() { # 标签 [godot 参数...] -- 游戏参数...
  tag=$1; shift
  python -I _tasks/trailer/run_hidden.py . _shots/rg_$tag --resolution 1280x720 "$@" > /dev/null 2>&1
  e=$(cat _shots/rg_${tag}_out.txt _shots/rg_${tag}_err.txt | grep -c "SCRIPT ERROR\|SHADER ERROR\|Parse Error")
  echo "$tag : 报错 $e 行 | 输出 $(wc -l < _shots/rg_${tag}_out.txt) 行" >> $OUT
  if [ "$e" != "0" ]; then cat _shots/rg_${tag}_out.txt _shots/rg_${tag}_err.txt | grep "SCRIPT ERROR\|SHADER ERROR\|Parse Error" -A 2 | head -12 >> $OUT; fi
}
run feat -- --duel-shot --spark --spark-feat
run feat_gl --rendering-method gl_compatibility -- --duel-shot --spark --spark-feat --touch
run moves -- --duel-shot --spark --spark-moves
run otg -- --duel-shot --spark --spark-otg
run clip -- --duel-shot --spark --spark-clip --clip-quick
run outline_gl --rendering-method gl_compatibility -- --duel-shot --spark --spark-feat --pvp-outline --touch
run arena -- --hub-shot --arena-duel
run pace -- --raid-shot --raid-pace --pace-combat --pace-realms=2,5
echo "done" >> $OUT
