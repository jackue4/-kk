#!/bin/sh
# 带锁的 --import：import.lock 存在且不到 10 分钟就等，超过 10 分钟当作残留；用法 sh locked_import.sh
L="D:/GodotProjects/修仙游戏/_tasks/extraction_refactor/import.lock"
G="D:/ugc-ai/tools/godot/Godot_v4.7.2-stable_win64_console.exe"
n=0
while [ -e "$L" ]; do
  age=$(( $(date +%s) - $(stat -c %Y "$L") ))
  if [ $age -gt 600 ]; then echo "stale lock ($age s), taking it"; break; fi
  n=$((n+1)); if [ $n -gt 60 ]; then echo "lock still held after 10 min"; exit 1; fi
  echo "lock held ($age s), waiting"; sleep 10
done
echo "B_mobs $(date)" > "$L"
"$G" --headless --path "D:/GodotProjects/修仙游戏" --import > "D:/GodotProjects/修仙游戏/_tasks/extraction_refactor/logs/import_bmobs.txt" 2>&1
rc=$?
rm -f "$L"
echo "import rc=$rc"
grep -i "error" "D:/GodotProjects/修仙游戏/_tasks/extraction_refactor/logs/import_bmobs.txt" | head -20
