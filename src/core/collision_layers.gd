## 3D 碰撞层分配表 —— 唯一权威来源，场景与代码都引用这里，禁止写字面量。
## 位掩码 = 1 << (layer_number - 1)
class_name CollisionLayers
extends RefCounted

const ENVIRONMENT: int = 1 << 0        # 1  地形、墙、地面
const PLAYER_BODY: int = 1 << 1        # 2  玩家角色胶囊
const ENEMY_BODY: int = 1 << 2         # 3  敌人角色胶囊
const PLAYER_HITBOX: int = 1 << 3      # 4  玩家攻击判定
const ENEMY_HITBOX: int = 1 << 4       # 5  敌人攻击判定
const PLAYER_HURTBOX: int = 1 << 5     # 6  玩家受击盒
const ENEMY_HURTBOX: int = 1 << 6      # 7  敌人受击盒
const PROJECTILE: int = 1 << 7         # 8  投射物
const TRIGGER: int = 1 << 8            # 9  关卡触发器 / 刷怪区
const CAMERA_BLOCK: int = 1 << 9       # 10 相机遮挡体

## 人类可读的层名，调试面板与文档生成共用。
const LAYER_NAMES: Dictionary = {
	1: "environment",
	2: "player_body",
	3: "enemy_body",
	4: "player_hitbox",
	5: "enemy_hitbox",
	6: "player_hurtbox",
	7: "enemy_hurtbox",
	8: "projectile",
	9: "trigger",
	10: "camera_block",
}

## 某个受击盒应该被哪些攻击判定命中。
static func hitbox_mask_for(faction: StringName) -> int:
	if faction == GameConstants.FACTION_PLAYER:
		return ENEMY_HURTBOX
	return PLAYER_HURTBOX

static func hurtbox_layer_for(faction: StringName) -> int:
	if faction == GameConstants.FACTION_PLAYER:
		return PLAYER_HURTBOX
	return ENEMY_HURTBOX

static func body_layer_for(faction: StringName) -> int:
	if faction == GameConstants.FACTION_PLAYER:
		return PLAYER_BODY
	return ENEMY_BODY

## 角色胶囊与地形、以及对方本体发生碰撞（软推挤），不与任何判定盒碰撞。
static func body_mask_for(faction: StringName) -> int:
	if faction == GameConstants.FACTION_PLAYER:
		return ENVIRONMENT | ENEMY_BODY
	return ENVIRONMENT | PLAYER_BODY

static func hitbox_layer_for(faction: StringName) -> int:
	if faction == GameConstants.FACTION_PLAYER:
		return PLAYER_HITBOX
	return ENEMY_HITBOX

static func describe(mask: int) -> String:
	var parts: Array[String] = []
	for n: int in LAYER_NAMES.keys():
		if mask & (1 << (n - 1)):
			parts.append(LAYER_NAMES[n])
	return ",".join(parts)
