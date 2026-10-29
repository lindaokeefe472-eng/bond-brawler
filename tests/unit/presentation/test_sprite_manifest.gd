## 素材清单完整性：每个角色都必须有核心动作，且每张图集的实际宽度等于帧表。
##
## 回归：tools/build_asset_manifest.py 的后缀表原来只精确匹配 Attack01/02/03，
## 而且区分大小写。这套素材包并不统一 —— Priest / Skeleton Archer 的攻击叫
## "Attack"（没有编号）、Wizard 的死亡叫 "DEATH"、Lancer / Knight Templar 的
## 步态叫 "Walk01"、Swordsman 的第三段叫 "Attack3"，这些文件被整段丢掉。
## 表现就是「牧师和骷髅弓手攻击时站着不动、枪兵走路时滑行、法师死亡直接弹受击帧」。
extends GdUnitTestSuite

const MANIFEST_PATH: String = "res://assets/sprites/characters/manifest.json"
const CHAR_DIR: String = "res://assets/sprites/characters"
## 核心动作：少了任何一个，某个状态就会退化成 idle，看起来就是「动作错了」。
const REQUIRED: Array[String] = ["idle", "walk", "attack1", "hurt", "death"]

func before(_do_skip := not FileAccess.file_exists(MANIFEST_PATH),
		_skip_reason := "需要本地 assets/sprites/，见 README「数据与素材」") -> void:
	pass

func test_every_character_has_the_core_animations() -> void:
	var characters: Dictionary = _characters()
	assert_int(characters.size()).is_greater_equal(20)
	for slug: String in characters.keys():
		var anims: Dictionary = (characters[slug] as Dictionary).get("animations", {})
		for required: String in REQUIRED:
			assert_bool(anims.has(required)).override_failure_message(
					"%s 缺少 %s 动画，该状态下会退化成 idle" % [slug, required]).is_true()

func test_every_atlas_matches_its_frame_table() -> void:
	var characters: Dictionary = _characters()
	for slug: String in characters.keys():
		var anims: Dictionary = (characters[slug] as Dictionary).get("animations", {})
		for name: String in anims.keys():
			var data: Dictionary = anims[name]
			var path: String = CHAR_DIR.path_join(slug).path_join(str(data.get("file", "")))
			assert_bool(FileAccess.file_exists(path)).override_failure_message(
					"%s/%s 的图集文件不存在：%s" % [slug, name, path]).is_true()
			var img: Image = Image.load_from_file(path)
			assert_object(img).override_failure_message("%s/%s 读不出来" % [slug, name]).is_not_null()
			var frames: int = int(data.get("frames", 0))
			var size: Array = data.get("frame_size", [0, 0])
			assert_int(frames).override_failure_message("%s/%s 帧数不合法" % [slug, name]).is_greater(0)
			assert_int(img.get_width()).override_failure_message(
					"%s/%s 宽度 %d 不等于 %d 帧 × %d px —— 播放时会被均分错位"
					% [slug, name, img.get_width(), frames, int(size[0])]
				).is_equal(frames * int(size[0]))
			assert_int(img.get_height()).override_failure_message(
					"%s/%s 高度和图集帧高不一致" % [slug, name]).is_equal(int(size[1]))

## 每个角色都得能量出普攻前伸，否则判定盒会退回全局默认值，和武器对不上。
func test_every_character_has_a_measured_melee_reach() -> void:
	var characters: Dictionary = _characters()
	for slug: String in characters.keys():
		var reach: float = float((characters[slug] as Dictionary).get("melee_reach", 0.0))
		assert_float(reach).override_failure_message(
				"%s 没有算出 melee_reach，判定盒会用默认值" % slug).is_greater(0.0)

## 弹体图也要登记：素材包里明明有 Arrow(Projectile) / Magic(Projectile)，
## 之前完全没用，表现层只能画白方块。
func test_projectile_atlases_match_their_frame_table() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	assert_bool(raw is Dictionary).is_true()
	var projectiles: Variant = (raw as Dictionary).get("projectiles", {})
	assert_bool(projectiles is Dictionary).override_failure_message(
			"manifest 里没有 projectiles 段").is_true()
	assert_int((projectiles as Dictionary).size()).override_failure_message(
			"弹体图一张都没登记").is_greater(0)
	for slug: String in (projectiles as Dictionary).keys():
		var data: Dictionary = (projectiles as Dictionary)[slug]
		var path: String = "res://assets/sprites/projectiles".path_join(str(data.get("file", "")))
		assert_bool(FileAccess.file_exists(path)).override_failure_message(
				"%s 的弹体贴图不存在：%s" % [slug, path]).is_true()
		var img: Image = Image.load_from_file(path)
		assert_object(img).is_not_null()
		var frames: int = int(data.get("frames", 0))
		var size: Array = data.get("frame_size", [0, 0])
		assert_int(frames).override_failure_message("%s 帧数不合法" % slug).is_greater(0)
		assert_int(img.get_width()).override_failure_message(
				"%s 宽度 %d 不等于 %d 帧 × %d px" % [slug, img.get_width(), frames, int(size[0])]
			).is_equal(frames * int(size[0]))
		assert_int(img.get_height()).is_equal(int(size[1]))
		assert_float(float(data.get("pixel_size", 0.0))).override_failure_message(
				"%s 没有 pixel_size，渲染时会变成一个小点" % slug).is_greater(0.0)

func _characters() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not (raw is Dictionary):
		return {}
	var characters: Variant = (raw as Dictionary).get("characters", {})
	return characters if characters is Dictionary else {}
