## data/melee.json 的数据校验：这是唯一需要手改的数值文件，改错了不该静默降级。
##
## 之前的问题是「远程角色」根本没有这个概念，弓手和法师播着拉弓/施法的动作，
## 判定却走近战扇形。现在形态由这份数据声明，所以必须校验它的字段。
extends GdUnitTestSuite

const MELEE_PATH: String = "res://data/melee.json"
const MANIFEST_PATH: String = "res://assets/sprites/characters/manifest.json"
const KNOWN_ATTACKS: Array[String] = ["melee", "aoe", "projectile"]

func before(_do_skip := not FileAccess.file_exists(MELEE_PATH),
		_skip_reason := "需要本地 data/，见 README「数据与素材」") -> void:
	pass

func test_every_character_reference_exists_in_the_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not (manifest is Dictionary):
		return
	var known: Dictionary = (manifest as Dictionary).get("characters", {})
	for character_id: String in _characters().keys():
		assert_bool(known.has(character_id)).override_failure_message(
				"melee.json 里的 %s 在素材清单里不存在，这份配置永远不会生效" % character_id).is_true()

func test_attack_kind_is_known() -> void:
	var characters: Dictionary = _characters()
	for character_id: String in characters.keys():
		var entry: Dictionary = characters[character_id]
		if not entry.has("attack"):
			continue
		var kind: String = str(entry["attack"])
		assert_bool(KNOWN_ATTACKS.has(kind)).override_failure_message(
				"%s 的 attack = %s 不认识，只支持 %s" % [character_id, kind, KNOWN_ATTACKS]).is_true()

func test_projectile_entries_are_usable() -> void:
	var characters: Dictionary = _characters()
	for character_id: String in characters.keys():
		var entry: Dictionary = characters[character_id]
		if str(entry.get("attack", "")) != "projectile":
			continue
		var raw: Variant = entry.get("projectile", {})
		assert_bool(raw is Dictionary).override_failure_message(
				"%s 声明了远程却没有 projectile 段" % character_id).is_true()
		var cfg: Dictionary = raw if raw is Dictionary else {}
		assert_float(float(cfg.get("speed", 0.0))).override_failure_message(
				"%s 的弹体速度必须大于 0，否则永远飞不到目标" % character_id).is_greater(0.0)
		assert_float(float(cfg.get("range", 0.0))).override_failure_message(
				"%s 的弹体射程必须大于 0" % character_id).is_greater(0.0)

## 弓手和法师必须是远程 —— 它们的动作就是拉弓和施法，走近战等于动作和判定分家。
func test_ranged_characters_are_marked_as_projectile() -> void:
	var expected: Array[String] = ["archer", "skeleton_archer", "wizard", "priest"]
	var characters: Dictionary = _characters()
	for character_id: String in expected:
		var entry: Dictionary = characters.get(character_id, {})
		assert_str(str(entry.get("attack", "melee"))).override_failure_message(
				"%s 应该是远程角色" % character_id).is_equal("projectile")

## sprite 必须是 manifest 里登记过的弹体贴图，否则表现层只会画白方块。
func test_projectile_sprite_slugs_exist() -> void:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not (raw is Dictionary):
		return
	var known: Variant = (raw as Dictionary).get("projectiles", {})
	var characters: Dictionary = _characters()
	for character_id: String in characters.keys():
		var projectile: Variant = (characters[character_id] as Dictionary).get("projectile", {})
		if not (projectile is Dictionary):
			continue
		var slug: String = str((projectile as Dictionary).get("sprite", ""))
		if slug.is_empty():
			continue
		assert_bool(known is Dictionary and (known as Dictionary).has(slug)).override_failure_message(
				"%s 的弹体贴图 %s 在 manifest 里不存在" % [character_id, slug]).is_true()

## 逐段覆盖：kind 必须认识，范围攻击必须给 radius。
func test_attack_step_overrides_are_valid() -> void:
	var characters: Dictionary = _characters()
	for character_id: String in characters.keys():
		var attacks: Variant = (characters[character_id] as Dictionary).get("attacks", {})
		if not (attacks is Dictionary):
			continue
		for step: String in (attacks as Dictionary).keys():
			var entry: Variant = (attacks as Dictionary)[step]
			assert_bool(entry is Dictionary).override_failure_message(
					"%s 的第 %s 段不是字典" % [character_id, step]).is_true()
			var data: Dictionary = entry
			if data.has("kind"):
				var kind: String = str(data["kind"])
				assert_bool(KNOWN_ATTACKS.has(kind)).override_failure_message(
						"%s 第 %s 段的 kind = %s 不认识" % [character_id, step, kind]).is_true()
			if str(data.get("kind", "")) == "aoe":
				assert_float(float(data.get("radius", 0.0))).override_failure_message(
						"%s 第 %s 段是范围攻击却没有 radius" % [character_id, step]).is_greater(0.0)

func _characters() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(MELEE_PATH))
	if not (raw is Dictionary):
		return {}
	var characters: Variant = (raw as Dictionary).get("characters", {})
	return characters if characters is Dictionary else {}
