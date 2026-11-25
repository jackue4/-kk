#!/bin/bash
# 真人对打规则的整套双开对照（约 12 分钟）：结果汇总到 _tasks/pvp_rules/matrix.txt
cd "D:/GodotProjects/修仙游戏"
OUT=_tasks/pvp_rules/matrix.txt
: > $OUT
run() { # 标签 参数...
  tag=$1; shift
  echo "=== $tag : $*" >> $OUT
  python -I _tasks/pvp_rules/run_pair.py $tag "$@" 2>&1 | grep "RESULT\|报错\|中止" >> $OUT
}
for r in 3 5; do
  run mash_new$r --pvp-rules=mash --pvp-realm=$r
  run mash_old$r --pvp-rules=mash --pvp-realm=$r --pvp-legacy
  run def_new$r --pvp-rules=defend --pvp-realm=$r
  run def_old$r --pvp-rules=defend --pvp-realm=$r --pvp-legacy
done
run gl_mash_new3 --gl --pvp-rules=mash --pvp-realm=3 --pvp-shots
run gl_def_new5 --gl --pvp-rules=defend --pvp-realm=5 --pvp-shots
run gl_clash2_new --gl --pvp-rules=clash2 --pvp-realm=3 --pvp-shots
run gl_clash_new --gl --pvp-rules=clash --pvp-realm=4 --pvp-shots
echo "=== done" >> $OUT
