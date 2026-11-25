#!/bin/sh
# 隔离副本里的回归：存档目录指到副本自己的 appdata，不碰正式存档。日志在 _shots/touchcam/reg_*
cd "/d/GodotProjects/修仙游戏_iso_touchcam"
export APPDATA='D:\GodotProjects\修仙游戏_iso_touchcam_appdata'
O=_shots/touchcam
run() { name=$1; shift; t0=$(date +%s); python _tasks/trailer/run_hidden.py . $O/reg_$name "$@" > /dev/null 2>&1; echo "$name $(( $(date +%s) - t0 ))s" >> $O/reg_times.txt; }
: > $O/reg_times.txt
run behave_touch --resolution 1280x720 --rendering-method gl_compatibility -s res://_tasks/touch_cam/touch_behave_probe.gd -- --touch
run behave_desk --resolution 1280x720 -s res://_tasks/touch_cam/touch_behave_probe.gd
run touchtest --resolution 1280x720 -- --duel-shot --touch-test --touch
run zoom --resolution 1280x720 --rendering-method gl_compatibility -s res://_tasks/qa_20261121/qa_touch_zoom.gd -- --qa-touch-zoom --touch
run swipe_desk --resolution 1280x720 --fixed-fps 60 -s res://_tasks/touch_cam/touch_look_probe.gd -- --touch --tl-fixed 60 --tl-tag desk_f60 --tl-csv "D:/GodotProjects/修仙游戏_iso_touchcam/$O/desk_f60.csv"
run feat_desk --resolution 1280x720 -- --duel-shot --spark --spark-feat
run feat_touch --resolution 1280x720 --rendering-method gl_compatibility -- --duel-shot --spark --spark-feat --touch
run cam_desk --resolution 1280x720 -- --duel-shot --spark --spark-cam
run cam_touch --resolution 1280x720 --rendering-method gl_compatibility -- --duel-shot --spark --spark-cam --touch
echo ALLDONE >> $O/reg_times.txt
