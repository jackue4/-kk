#!/bin/bash
# TSB 式重做后的单机回归：老的空战自检 + 擂台 AI 陪练全流程 + 英雄自检 + 新图自检，每项的脚本 / 着色器报错数汇总到 _tasks/tsb/regress.txt
cd "D:/GodotProjects/修仙游戏"
OUT=_tasks/tsb/regress.txt
: > $OUT
run() { # 标签 [godot 参数...] -- 游戏参数...
  tag=$1; shift
  python -I _tasks/trailer/run_hidden.py . _shots/tsbrg_$tag --resolution 1280x720 --audio-driver Dummy "$@" > /dev/null 2>&1
  e=$(cat _shots/tsbrg_${tag}_out.txt _shots/tsbrg_${tag}_err.txt | grep -c "SCRIPT ERROR\|SHADER ERROR\|Parse Error")
  echo "$tag : 报错 $e 行 | 输出 $(wc -l < _shots/tsbrg_${tag}_out.txt) 行" >> $OUT
  if [ "$e" != "0" ]; then cat _shots/tsbrg_${tag}_out.txt _shots/tsbrg_${tag}_err.txt | grep "SCRIPT ERROR\|SHADER ERROR\|Parse Error" -A 3 | head -16 >> $OUT; fi
}
for t in "$@"; do
  case $t in
    feat) run feat -- --duel-shot --spark --spark-feat ;;
    feat_gl) run feat_gl --rendering-method gl_compatibility -- --duel-shot --spark --spark-feat --touch ;;
    moves) run moves -- --duel-shot --spark --spark-moves ;;
    otg) run otg -- --duel-shot --spark --spark-otg ;;
    arena) run arena -- --hub-shot --arena-duel ;;
    arena_gl) run arena_gl --rendering-method gl_compatibility -- --hub-shot --arena-duel --touch ;;
    hero) run hero -- --hero-test ;;
    desert) run desert -- --level-test=desert ;;
    lab) run lab -- --level-test=lab ;;
    lobby) run lobby -- --lobby-test ;;
    boot) run boot -- --hub-shot ;;
  esac
done
echo "done" >> $OUT
