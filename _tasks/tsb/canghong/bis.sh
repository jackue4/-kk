#!/bin/bash
# 用法：bash bis.sh <标签> <函数名列表>   —— 换成空壳后跑一遍 none，打印 stderr 字节数，再把原文件放回去
cd "D:/GodotProjects/修仙游戏"
python _tasks/tsb/canghong/stub.py _tasks/tsb/canghong/kit_keep.gd.txt scripts/heroes/kit_canghong2.gd "$2"
rm -f _tasks/tsb/canghong/b_run.txt
(python -I _tasks/trailer/run_hidden.py . _tasks/tsb/canghong/bis_$1 --resolution 640x360 -- --tsb-show=canghong --tsb-only=none > _tasks/tsb/canghong/b_run.txt 2>&1; echo finished >> _tasks/tsb/canghong/b_run.txt) &
for i in $(seq 1 30); do if grep -q finished _tasks/tsb/canghong/b_run.txt 2>/dev/null; then break; fi; python -c "import time; time.sleep(2)"; done
echo "[$1] ERR bytes $(wc -c < _tasks/tsb/canghong/bis_$1_err.txt) :: $(grep -m1 -i 'error' _tasks/tsb/canghong/bis_$1_err.txt | cut -c1-140)"
cp _tasks/tsb/canghong/kit_keep.gd.txt scripts/heroes/kit_canghong2.gd
