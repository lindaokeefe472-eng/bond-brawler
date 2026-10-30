# -*- coding: utf-8 -*-
"""由 assets/sprites/characters/manifest.json 自动生成 ASSET_SPEC.md。

用法: python -I tools/gen_asset_spec.py
"""
import io
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "assets", "sprites", "characters", "manifest.json")
OUT = os.path.join(ROOT, "ASSET_SPEC.md")

HEADER = """# 素材规范（ASSET_SPEC）

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
"""


def main():
    if not os.path.exists(MANIFEST):
        print("找不到 manifest.json，先运行 build_asset_manifest.py")
        return 1
    with io.open(MANIFEST, encoding="utf-8") as f:
        m = json.load(f)

    rows = []
    step_rows = []
    for slug in sorted(m["characters"]):
        e = m["characters"][slug]
        a = e["animations"]
        cells = []
        for key in ("idle", "walk", "attack1", "attack2", "attack3", "block", "hurt", "death"):
            if key in a:
                fs = a[key].get("frame_size", ["?", "?"])
                cells.append("%dx%d/%d帧" % (fs[0], fs[1], a[key]["frames"]))
            else:
                cells.append("-")
        idle_fs = a.get("idle", {}).get("frame_size", ["?", "?"])
        reach = float(e.get("melee_reach", 0.0))
        windup = float(e.get("melee_windup", 0.0))
        active = float(e.get("melee_active", 0.0))
        window = "%.2f~%.2f s" % (windup, windup + active) if active > 0.0 else "-"
        rows.append("| %s `%s` | %sx%s | %.4f | %s | %.2f m | %s |" % (
            e["display_name"], slug, idle_fs[0], idle_fs[1],
            float(e.get("pixel_size", 0.0)), " | ".join(cells), reach, window))
        # 逐段普攻：三段连击各有各的前伸和判定窗口，缺字段的段退回角色级值。
        for step in sorted(e.get("attacks", {}), key=lambda s: int(s)):
            d = e["attacks"][step]
            w = float(d.get("windup", windup))
            ac = float(d.get("active", active))
            win = "%.2f~%.2f s" % (w, w + ac) if ac > 0.0 else "-"
            step_rows.append("| `%s` | %s | %.2f m | %s | %s |" % (
                slug, step, float(d.get("reach", reach)), win,
                "绕身" if bool(d.get("sweep", False)) else "近战"))

    tail = """
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
"""
    body = "\n".join(rows) + "\n"
    if step_rows:
        body += ("\n### 3.0 逐段普攻（自动生成）\n\n"
                 "`ActorRuntime.attack_config(step)` 按段取用；没写 reach 的段退回上表角色级值。\n"
                 "「绕身」= 挥击峰之后武器仍扫到身后（`sweep`），运行时默认按范围攻击结算，\n"
                 "`data/melee.json` 的 `attacks[step].kind` 可以推翻。\n\n"
                 "| 角色 | 段 | 前伸 | 判定窗口 | 形态 |\n"
                 "|---|---|---|---|---|\n" + "\n".join(step_rows) + "\n")
    projectiles = m.get("projectiles", {})
    if projectiles:
        proj_rows = []
        for slug in sorted(projectiles):
            p = projectiles[slug]
            fs = p.get("frame_size", ["?", "?"])
            ps = float(p.get("pixel_size", 0.0))
            try:
                longest = max(int(fs[0]), int(fs[1]))
            except (TypeError, ValueError):
                longest = 0
            proj_rows.append("| `%s` | %sx%s | %d | %.4f | %.2f m |" % (
                slug, fs[0], fs[1], int(p.get("frames", 0)), ps, longest * ps))
        body += ("\n### 3.1 弹体图（自动生成）\n\n"
                 "| slug | 帧尺寸 | 帧数 | pixel_size | 最长边 |\n"
                 "|---|---|---|---|---|\n" + "\n".join(proj_rows) + "\n")
    body += tail
    with io.open(OUT, "w", encoding="utf-8") as f:
        f.write(HEADER + body)
    print("generated", OUT, len(rows), "characters")
    return 0


if __name__ == "__main__":
    sys.exit(main())
