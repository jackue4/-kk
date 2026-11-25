extends RefCounted
## 老局内循环（raid_manager / raid_camps / raid_search）问「世界几何」的转接层——大世界（木兰草原，循环世界）这一份。
## 2026-11-25 主干解耦（W2a，_tasks/decouple/CONTRACT.md 第 4 节）：同一套 raid_manager 也要跑新两关（沙海古墟 / 天工秘所），
## 两边的几何不一样（循环 / 有边界、按扇区分区 / 按图和层分档、按地形摆 / 按点表摆），差别都收进 geo：
##   · 这一份（大世界）原样转调 raid_data.gd（Data）和 progression.gd（Prog），行为一字不变；
##   · 新图那份在 scripts/ex/ex_geo.gd，数据由 ex_level.gd + map_def.gd 提供。
## raid_manager 里凡是 `if geo.fixed:` 的分支都是新图专用，大世界走原来的代码（不经过 geo 的那几处也保持原样）。
## 故意不写 class_name：用 preload 引用。

const Data := preload("res://scripts/raid_data.gd")
const Prog := preload("res://scripts/progression.gd")

## 大世界：循环世界（要换像）、天色由 raid_manager._blend_atmosphere 管、按 32 米网格布刷怪点 / 按扇区撒搜点
var loop := true
var fixed := false
var own_atmo := false
var map_id := "mulan"
const ZONE_ONE := {"hp": 1.0, "atk": 1.0, "bonus": 0.0, "xp": 1.0}


func near(base: Vector3, ref: Vector3) -> Vector3:
	return Data.near(base, ref)


func near2(base: Vector2, ref: Vector2) -> Vector2:
	return Data.near2(base, ref)


## 在陆地上（不是外海）
func on_land(x: float, z: float) -> bool:
	return Data.land_r(x, z) < Data.PLAY_R


func region_of(p: Vector3) -> int:
	return Data.region_at(p.x, p.z)


func depth_of(ri: int, p: Vector3) -> float:
	return Prog.depth_at(clampi(ri, 0, 4), p.x, p.z)


## 难度 / 回报倍率（第 3 节的表）：大世界恒为 1（不乘）
func zone_k(_p: Vector3) -> Dictionary:
	return ZONE_ONE


## 每轮亮几座免费的古传送阵（再加一座灵石阵）
func gates_free() -> int:
	return 2


func where_name(ri: int, _p: Vector3) -> String:
	return str(Data.REGIONS[clampi(ri, 0, Data.REGIONS.size() - 1)]["name"])
