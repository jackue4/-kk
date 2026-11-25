#!/bin/sh
# 隔离副本里跑滑屏量测：存档目录指到副本自己的 appdata，不碰正式存档
cd "/d/GodotProjects/修仙游戏_iso_touchcam"
export APPDATA='D:\GodotProjects\修仙游戏_iso_touchcam_appdata'
OUT=_shots/touchcam
R=${REND:-gl_compatibility}
for F in ${FPSLIST:-60 120 30}; do
  python _tasks/trailer/run_hidden.py . $OUT/p_${PFX}f$F --resolution 1280x720 --rendering-method $R --fixed-fps $F -s res://_tasks/touch_cam/touch_look_probe.gd -- --touch --tl-fixed $F --tl-tag ${PFX}f$F --tl-csv "D:/GodotProjects/修仙游戏_iso_touchcam/$OUT/${PFX}f$F.csv"
done
python _tasks/trailer/run_hidden.py . $OUT/p_${PFX}rt --resolution 1280x720 --rendering-method $R -s res://_tasks/touch_cam/touch_look_probe.gd -- --touch --tl-uneven --tl-tag ${PFX}rt --tl-csv "D:/GodotProjects/修仙游戏_iso_touchcam/$OUT/${PFX}rt.csv"
echo ALLDONE
