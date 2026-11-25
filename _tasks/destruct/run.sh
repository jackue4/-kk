#!/bin/bash
# 场景破坏自检：bash _tasks/destruct/run.sh <desert|lab> [gl] [sliced]   （gl = 手机档：兼容渲染器 + --touch；sliced = 单线程分帧，同网页版）
# 输出 _tasks/destruct/logs/<图>[_gl]_out.txt / _err.txt，截图 _shots/preview/destruct_<图>_*[_gl].jpg
cd "$(dirname "$0")/../.."
map=${1:-desert}
tag=$map
gargs=""
uargs=""
if [ "$2" = "gl" ]; then tag=${map}_gl; gargs="--rendering-method gl_compatibility"; uargs="--touch"; fi
# 第三个参数 sliced：再加 --sliced（地块在主线程上分帧算，同网页版），截图不另存一套（--no-shots）
if [ "$3" = "sliced" ]; then tag=${tag}_sliced; uargs="$uargs --sliced --no-shots"; fi
mkdir -p _tasks/destruct/logs
python -I _tasks/trailer/run_hidden.py . _tasks/destruct/logs/$tag --resolution 1280x720 $gargs -s res://_tasks/destruct/destruct_selftest.gd -- --qa-destruct --map=$map $uargs
grep "\[destruct\]" _tasks/destruct/logs/${tag}_out.txt | cut -c1-520
echo "--- stderr: $(grep -c . _tasks/destruct/logs/${tag}_err.txt) 行，SCRIPT ERROR $(grep -c 'SCRIPT ERROR' _tasks/destruct/logs/${tag}_err.txt)，ERROR $(grep -c 'ERROR' _tasks/destruct/logs/${tag}_err.txt)"
grep -m12 "ERROR\|at: " _tasks/destruct/logs/${tag}_err.txt | cut -c1-260
