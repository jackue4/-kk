# 大世界固定刷怪点（2026-11-21 ~ 22）

线上 `gh-pages` **dbdffe4**（以 690f4bc 为底，只换 / 加下面 6 个脚本，其余 669 项与线上字节一致）。**源码没有提交、正式工作区没动**：改动在 `camps_20261121.patch`。

## 改了什么
- 新 `scripts/raid_camps.gd`：世界里的固定刷怪点（32 米网格、固定种子、各区概率；避开主城 75 米 / 巢穴 110 米 / 撤离点 60 米 / 搜点 30 米 / 水面）。
  每点的怪是定的，只记哪只死了，世界时钟 75 秒复活（精英 150，单机对手修士杀的 12）。离人 100 米内、没在御剑急飞（水平 > 30 米/秒）才建，每帧限量、镜头前先建；150 米外闲着就收。
  联机：一个点一个人建（编号小、没急飞），木偶带点编号，死亡编进 send_mob_dead 的 lair 字段（负数，net.gd 不用改），交接接着血量。
- `raid_manager.gd`：几处钩子（导演里刷怪点开着就不再一拨拨刷；收远处怪 / _trim_far 跳过刷怪点的怪；木偶批次第 11 项；死亡同步；联机里离我 100 米外死的刷怪点怪不算我的）。
- `raid_mob.gd`：`anchor`（追丢了走回点上，回去路上不认人）。
- `main.gd`：`--net=camp_*` 分派到新的 `camp_net_selftest.gd`（4 行）。
- `raid_pace_test.gd`：`--pace-spawn` 探针、`--pace-face` / `--pace-home=R` 选项（只影响自检）。
- 开关：正常游玩开；`--spawn-old` 老导演；自检模式默认老导演，`--camps` 才开（别的自检都是按老导演写的）。

## 整合到正式工作区
`git apply --check _tasks/spawn_density_20261121/camps_20261121.patch` 在 2026-11-22 00:3x 的正式工作区（含测试专项的修复）上能干净打上（raid_manager 有 6 行偏移）。
打之前再看一眼这几个文件有没有被别的会话改过；打完跑 `-- --raid-shot --raid-pace --pace-spawn --spawn-reps=1` 和 `--net=camp_host` / `--net=camp_mate` 双开。

## 测量（logs/ 里是原始输出）
- 杀怪节奏：`--raid-pace --pace-face [--pace-home=200]`，老 `--spawn-old` 和新 `--camps` 同机同时跑，五对（b ~ f）：五区合计 83.0 → 81.6 只/分钟，各区 ±8% 内；
  life_sim（pace_old4.json / pace_camp4.json）到大乘：休闲 16.8 → 16.9、普通 15.9 → 15.7、肝 14.7 → 14.8 小时。
- 落地看得见 / 够得着、身边只数、帧耗时：fin_desk_out.txt（桌面）、fin_phone_table.txt（手机画质档，原生）、web_table.txt / web_perf.log（网页包，无界面 Edge）。
- 联机：campnet_host_out.txt / campnet_mate_out.txt（两边 PASS）。
- 回归：reg_econ_out.txt、reg_insight_{old,camps}_out.txt、web_boot.log（0 个 SCRIPT ERROR）、web_hub.log。
- 没在真机（手机）上测过；联机只在同一台机器双开测过。
