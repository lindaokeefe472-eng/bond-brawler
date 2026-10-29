# 素材规范（ASSET_SPEC）

> 本文件由 `tools/gen_asset_spec.py` 自动生成，**不要手改**。
> 修改 `manifest.json` 或生成器后重新运行。

## 1. 画布与像素密度

| 项目 | 规定 |
|---|---|
| 原始画布 | 100 x 100 px（横排，从左到右） |
| **归一化后** | 每帧裁剪到内容包围盒，尺寸见下表；角色身高统一 1.8 m |
| 缩放 | 每个角色一个 `pixel_size` = 1.8 / idle 内容高度，存在 manifest 里 |
| 纹理过滤 | 最近邻（`project.godot` 已设 `default_texture_filter=0`） |
| 导入预设 | 关闭 mipmap；`compress/mode=0`（无损）；`filter=false` |
| 锚点 | 每个动作一个 `offset`（像素，+y 向上），把 idle 的脚底 + 躯干中轴钉在节点原点 |
| 归一化 | `python tools/normalize_sprites.py`（**只对原始素材跑一次**，幂等） |

## 2. 命名规范

```
assets/sprites/characters/<slug>/<slug>_<action>.png
assets/sprites/characters/<slug>/<slug>_shadow.png
```

- `<slug>`：全小写，空格换下划线（`Armored Orc` → `armored_orc`）
- `<action>`：`idle` `walk` `attack1` `attack2` `attack3` `block` `hurt` `death`
- 新角色必须同时更新 `manifest.json`（运行 `tools/build_asset_manifest.py`）

## 3. 动画帧表（自动生成）

| 角色 | 帧尺寸 | pixel_size | idle | walk | atk1 | atk2 | atk3 | block | hurt | death | 普攻前伸 | 判定窗口 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Archer `archer` | 22x18 | 0.1000 | 22x18/6帧 | 22x18/8帧 | 37x22/9帧 | 63x38/12帧 | - | - | 22x17/4帧 | 27x17/4帧 | 2.70 m | 0.50~0.58 s |
| Armored Axeman `armored_axeman` | 19x20 | 0.0900 | 19x20/6帧 | 19x22/8帧 | 42x31/9帧 | 50x32/9帧 | 63x31/12帧 | - | 15x18/4帧 | 34x21/4帧 | 2.34 m | 0.33~0.42 s |
| Armored Orc `armored_orc` | 25x20 | 0.0900 | 25x20/6帧 | 25x21/8帧 | 32x31/7帧 | 38x19/8帧 | 62x23/9帧 | 25x19/4帧 | 26x19/4帧 | 42x21/4帧 | 1.98 m | 0.33~0.50 s |
| Armored Skeleton `armored_skeleton` | 18x24 | 0.1125 | 18x24/6帧 | 18x26/8帧 | 46x26/8帧 | 38x35/9帧 | - | - | 18x23/4帧 | 29x25/4帧 | 3.49 m | 0.33~0.50 s |
| Elite Orc `elite_orc` | 28x24 | 0.0750 | 28x24/6帧 | 28x24/8帧 | 49x37/7帧 | 58x31/11帧 | 52x46/9帧 | - | 29x23/4帧 | 45x25/4帧 | 1.95 m | 0.25~0.33 s |
| Greatsword Skeleton `greatsword_skeleton` | 31x20 | 0.0900 | 31x20/6帧 | 33x20/9帧 | 62x32/9帧 | 68x37/12帧 | 42x25/8帧 | - | 32x20/4帧 | 35x21/4帧 | 3.46 m | 0.42~0.58 s |
| Knight `knight` | 26x19 | 0.0947 | 26x19/6帧 | 26x19/8帧 | 30x26/7帧 | 45x30/10帧 | 58x33/11帧 | 26x18/4帧 | 20x20/4帧 | 26x18/4帧 | 2.04 m | 0.25~0.42 s |
| Knight Templar `knight_templar` | 27x18 | 0.1000 | 27x18/6帧 | 27x18/8帧 | 36x17/7帧 | 36x31/8帧 | 39x31/11帧 | 27x17/4帧 | 28x17/4帧 | 28x19/4帧 | 2.90 m | 0.33~0.58 s |
| Lancer `lancer` | 35x38 | 0.0750 | 35x38/6帧 | 35x38/8帧 | 57x29/6帧 | 57x29/9帧 | 54x30/8帧 | - | 35x34/4帧 | 40x37/4帧 | 2.85 m | 0.25~0.42 s |
| Orc `orc` | 22x16 | 0.1125 | 22x16/6帧 | 22x16/8帧 | 37x29/6帧 | 38x33/6帧 | - | - | 23x15/4帧 | 30x18/4帧 | 2.14 m | 0.25~0.42 s |
| Orc rider `orc_rider` | 32x29 | 0.0621 | 32x29/6帧 | 33x29/8帧 | 43x31/8帧 | 59x63/9帧 | 85x40/11帧 | 32x28/4帧 | 32x27/4帧 | 52x29/4帧 | 1.68 m | 0.33~0.58 s |
| Priest `priest` | 16x21 | 0.0857 | 16x21/6帧 | 16x22/8帧 | 27x26/9帧 | - | - | - | 16x19/4帧 | 23x19/4帧 | 1.59 m | 0.33~0.75 s |
| Skeleton `skeleton` | 26x16 | 0.1125 | 26x16/6帧 | 26x16/8帧 | 35x25/6帧 | 40x18/7帧 | - | 26x15/4帧 | 28x15/4帧 | 34x15/4帧 | 2.19 m | 0.25~0.42 s |
| Skeleton Archer `skeleton_archer` | 21x22 | 0.0818 | 21x22/6帧 | 21x23/8帧 | 35x21/9帧 | - | - | - | 21x21/4帧 | 25x21/4帧 | 2.00 m | 0.50~0.58 s |
| Slime `slime` | 25x17 | 0.1059 | 25x17/6帧 | 28x13/6帧 | 47x16/6帧 | 68x52/12帧 | - | - | 23x13/4帧 | 22x13/4帧 | 3.49 m | 0.25~0.42 s |
| Soldier `soldier` | 15x19 | 0.0947 | 15x19/6帧 | 15x19/8帧 | 34x27/6帧 | 29x28/6帧 | 36x20/9帧 | - | 16x18/4帧 | 26x18/4帧 | 1.90 m | 0.25~0.42 s |
| Swordsman `swordsman` | 24x22 | 0.0818 | 24x22/6帧 | 24x23/8帧 | 40x22/7帧 | 56x31/15帧 | 49x21/12帧 | - | 26x18/5帧 | 37x21/4帧 | 2.46 m | 0.25~0.42 s |
| Werebear `werebear` | 19x18 | 0.1000 | 19x18/6帧 | 21x19/8帧 | 40x23/9帧 | 39x29/13帧 | 62x23/9帧 | - | 20x18/4帧 | 23x17/4帧 | 3.00 m | 0.42~0.58 s |
| Werewolf `werewolf` | 27x17 | 0.1059 | 27x17/6帧 | 28x18/8帧 | 35x26/9帧 | 53x37/13帧 | - | - | 26x17/4帧 | 37x19/4帧 | 2.59 m | 0.42~0.58 s |
| Wizard `wizard` | 17x20 | 0.0900 | 17x20/6帧 | 17x21/8帧 | 21x22/6帧 | 34x26/6帧 | - | - | 17x18/4帧 | 33x19/4帧 | 1.17 m | 0.25~0.42 s |

### 3.0 逐段普攻（自动生成）

`ActorRuntime.attack_config(step)` 按段取用；没写 reach 的段退回上表角色级值。

| 角色 | 段 | 前伸 | 判定窗口 |
|---|---|---|---|
| `archer` | 1 | 2.70 m | 0.50~0.58 s |
| `archer` | 2 | 5.00 m | 0.83~0.92 s |
| `armored_axeman` | 1 | 2.34 m | 0.33~0.42 s |
| `armored_axeman` | 2 | 2.43 m | 0.33~0.75 s |
| `armored_axeman` | 3 | 4.05 m | 0.75~0.92 s |
| `armored_orc` | 1 | 1.98 m | 0.33~0.50 s |
| `armored_orc` | 2 | 2.52 m | 0.42~0.67 s |
| `armored_orc` | 3 | 2.88 m | 0.58~0.67 s |
| `armored_skeleton` | 1 | 3.49 m | 0.33~0.50 s |
| `armored_skeleton` | 2 | 2.25 m | 0.17~0.75 s |
| `elite_orc` | 1 | 1.95 m | 0.25~0.33 s |
| `elite_orc` | 2 | 1.95 m | 0.08~0.83 s |
| `elite_orc` | 3 | 2.17 m | 0.33~0.58 s |
| `greatsword_skeleton` | 1 | 3.46 m | 0.42~0.58 s |
| `greatsword_skeleton` | 2 | 4.00 m | 0.58~0.83 s |
| `greatsword_skeleton` | 3 | 3.19 m | 0.33~0.42 s |
| `knight` | 1 | 2.04 m | 0.25~0.42 s |
| `knight` | 2 | 2.70 m | 0.25~0.75 s |
| `knight` | 3 | 4.03 m | 0.58~0.83 s |
| `knight_templar` | 1 | 2.90 m | 0.33~0.58 s |
| `knight_templar` | 2 | 2.50 m | 0.42~0.58 s |
| `knight_templar` | 3 | 2.70 m | 0.58~0.75 s |
| `lancer` | 1 | 2.85 m | 0.25~0.42 s |
| `lancer` | 2 | 2.85 m | 0.17~0.25 s |
| `lancer` | 3 | 2.62 m | 0.25~0.42 s |
| `orc` | 1 | 2.14 m | 0.25~0.42 s |
| `orc` | 2 | 2.25 m | 0.25~0.33 s |
| `orc_rider` | 1 | 1.68 m | 0.33~0.58 s |
| `orc_rider` | 2 | 2.67 m | 0.42~0.58 s |
| `orc_rider` | 3 | 2.54 m | 0.42~0.83 s |
| `priest` | 1 | 1.59 m | 0.33~0.75 s |
| `skeleton` | 1 | 2.19 m | 0.25~0.42 s |
| `skeleton` | 2 | 2.98 m | 0.25~0.42 s |
| `skeleton_archer` | 1 | 2.00 m | 0.50~0.58 s |
| `slime` | 1 | 3.49 m | 0.25~0.42 s |
| `slime` | 2 | 5.08 m | 0.67~0.83 s |
| `soldier` | 1 | 1.90 m | 0.25~0.42 s |
| `soldier` | 2 | 1.90 m | 0.25~0.50 s |
| `soldier` | 3 | 2.56 m | 0.58~0.67 s |
| `swordsman` | 1 | 2.46 m | 0.25~0.42 s |
| `swordsman` | 2 | 3.68 m | 1.00~1.08 s |
| `swordsman` | 3 | 3.27 m | 0.58~0.92 s |
| `werebear` | 1 | 3.00 m | 0.42~0.58 s |
| `werebear` | 2 | 2.80 m | 0.33~0.92 s |
| `werebear` | 3 | 3.50 m | 0.50~0.67 s |
| `werewolf` | 1 | 2.59 m | 0.42~0.58 s |
| `werewolf` | 2 | 3.65 m | 0.67~1.00 s |
| `wizard` | 1 | 1.17 m | 0.25~0.42 s |
| `wizard` | 2 | 1.89 m | 0.33~0.50 s |

### 3.1 弹体图（自动生成）

| slug | 帧尺寸 | 帧数 | pixel_size | 最长边 |
|---|---|---|---|---|
| `arrow01` | 19x7 | 1 | 0.0474 | 0.90 m |
| `arrow02` | 19x7 | 1 | 0.0474 | 0.90 m |
| `arrow03` | 20x7 | 1 | 0.0450 | 0.90 m |
| `priest_attack` | 30x37 | 5 | 0.0243 | 0.90 m |
| `priest_heal` | 30x38 | 4 | 0.0237 | 0.90 m |
| `wizard_attack01` | 61x73 | 10 | 0.0123 | 0.90 m |
| `wizard_attack02` | 27x22 | 7 | 0.0333 | 0.90 m |

## 4. 多层视差背景

| 层 | 用途 | 视差系数 | 画布尺寸 | 平铺 |
|---|---|---|---|---|
| `bg_far` | 天空、远山 | 0.15 | 1280 x 720 | 无缝横向 |
| `bg_mid` | 建筑、树林 | 0.45 | 1280 x 720 | 无缝横向 |
| `bg_near` | 前景装饰、栅栏 | 0.80 | 1280 x 720 | 无缝横向 |
| `ground` | 可走地面带 | 1.00 | 256 x 128 | 横向重复 |

- 无缝平铺要求：左右边缘像素必须连续，导出前用「偏移 50% 再检查」的方法验证。
- 地面带高度固定 128 px，对应纵深 `LANE_MIN..LANE_MAX` 的投影。

## 5. 归一化说明（重要）

原始素材的角色只占 100x100 画布的中央 20~30 像素，其余是透明留白。
直接按画布缩放会让角色只有 0.4 m 高；按角色缩放又会得到 9 m 宽的透明四边形。

`tools/normalize_sprites.py` 的处理：

1. 每个动作裁到**自己的**内容包围盒（四边形尽量小）。
2. 所有动作共用一个 `pixel_size`，由 idle 的内容高度反推（身高恒为 1.8 m）。
3. 每个动作带自己的 `offset`，把 idle 的脚底与**躯干中轴**对齐到节点原点。
   中轴取「不透明像素高度 ≥ 最高列一半」的列的中点，不是包围盒中心 ——
   角色普遍单手持械，刀剑会把包围盒中心拽到武器上（knight 差 0.43 m）。

因此**新增角色后必须重新运行归一化**，否则新角色的比例会和别人对不上。

## 6. 法线贴图（2.5D 光照）

- 后缀：`<原文件名>_n.png`，与原图同尺寸、同锚点。
- 格式：RGB 切线空间法线，Z 朝外（OpenGL 约定）。
- 角色与背景都可以缺省；缺省时材质自动回退到无光照 Shader。

## 7. AI 绘图提示词模板

```
<sprite sheet>, <角色描述>, side view, facing right, 100x100 per frame,
{FRAMES} frames in a single horizontal strip, transparent background,
crisp pixel art, 1px outline, limited palette, no shadow (shadow is a separate sprite)
```

- 生成后必须：切帧 → 统一到 100x100 → 命名 → 更新 manifest。
- 同一角色的所有动作必须**同一调色板、同一比例、同一脚底基线**。

## 8. 弹体图（`assets/sprites/projectiles/`）

来自素材包的 `Arrow(Projectile)` / `Magic(Projectile)`，由 `build_asset_manifest.py`
拷到项目里、`normalize_sprites.py` 裁到内容包围盒。锚点取内容中心，缩放按
**最长边 = 0.9 m** 换算（箭和火球大小差得远，按高度归一化会失真）。

角色用哪个弹体贴图由 `data/melee.json` 的 `projectile.sprite` 指定，
没有指定或素材缺失时，表现层退回按属性上色的方块。

| 类型 | 尺寸 | 帧数 | 命名 |
|---|---|---|---|
| 箭 | 内容最长边 0.9 m | 1 | `arrow01` / `arrow02` / `arrow03` |
| 法术 | 内容最长边 0.9 m | 4~10 | `wizard_attack01` / `wizard_attack02` / `priest_attack` |
