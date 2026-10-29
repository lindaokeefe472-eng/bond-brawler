# -*- coding: utf-8 -*-
"""把 Tiny RPG 的 100x100 大留白图集归一化成「紧贴内容」的图集。

为什么需要这一步：
  原始素材的角色只占 100x100 画布中央的 20~30 像素，其余全是透明。
  直接用 pixel_size = 1/55 渲染，角色只有 0.4 米高；把整张画布当 1.8 米又会
  得到一个 9 米宽的四边形，透明面积大、排序开销高。

做法：
  1. 每个动作各自裁到自己的内容包围盒（四边形尽量小）。
  2. 比例统一：所有动作共用一个 pixel_size，由 idle 的内容高度反推，
     保证换动作时角色不会忽大忽小。
  3. 锚点统一：所有动作都把「idle 的脚底中心」对齐到节点原点，
     每个动作因此在 manifest 里带自己的 offset。

用法: python -I tools/normalize_sprites.py
"""
import io
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHARS = os.path.join(ROOT, "assets", "sprites", "characters")
MANIFEST = os.path.join(CHARS, "manifest.json")
TARGET_HEIGHT_M = 1.8
SOURCE_FRAME = 100


def union_bbox(frames):
    box = None
    for f in frames:
        b = f.getbbox()
        if b is None:
            continue
        box = list(b) if box is None else [min(box[0], b[0]), min(box[1], b[1]),
                                           max(box[2], b[2]), max(box[3], b[3])]
    return box


def load_frames(path, count):
    sheet = Image.open(path).convert("RGBA")
    out = []
    for i in range(count):
        out.append(sheet.crop((i * SOURCE_FRAME, 0, i * SOURCE_FRAME + SOURCE_FRAME, SOURCE_FRAME)))
    return out


ALPHA_MIN = 8


def body_anchor_x(frames):
    """水平锚点取「躯干中轴」，不是包围盒中心。

    这套素材的角色几乎都单手持械，刀剑/长枪横向伸出去会把包围盒中心拽到武器上：
    knight 的 idle 包围盒中心在 12.5 px，躯干实际在 8 px —— 折合 0.43 m。
    画面上就是「角色整个人偏到判定盒左后方半个身位」，判定盒看起来往右错开半格。

    躯干 = 不透明像素高度 >= 最高列一半的那些列。武器列又细又矮，会被这个阈值滤掉；
    披风、头盔羽饰同理。取首尾列的中点，对单侧伸出的武器不敏感。
    """
    if not frames:
        return 0.0
    width, height = frames[0].width, frames[0].height
    columns = [0] * width
    for frame in frames:
        px = frame.load()
        for x in range(width):
            n = sum(1 for y in range(height) if px[x, y][3] > ALPHA_MIN)
            if n > columns[x]:
                columns[x] = n
    tallest = max(columns) if columns else 0
    if tallest <= 0:
        return width * 0.5
    threshold = tallest * 0.5
    body = [x for x in range(width) if columns[x] >= threshold]
    if not body:
        return width * 0.5
    return (body[0] + body[-1] + 1) * 0.5


def melee_reach(frames, anchor_x, pixel_size):
    """普攻前伸：attack1 里武器伸得最远的那一帧，相对身体锚点的米数。

    判定盒前沿就用它。各角色武器长短差一倍（orc 2.14 m、armored_orc 1.98 m），
    共用一个常量必然对不上 —— 剑长的角色盒子偏短，斧子短的角色盒子偏长。
    """
    far = 0
    for frame in frames:
        box = frame.getbbox()
        if box is not None:
            far = max(far, box[2])
    return round(max(far - anchor_x, 0.0) * pixel_size, 3)


SPRITE_FPS = 12.0


def melee_window(frames, anchor_x, pixel_size, ratio=0.9):
    """普攻判定窗口：武器真正挥出去的那几帧，返回 (windup 秒, active 秒)。

    判定盒只在 ACTIVE 段亮，而 ACTIVE 段原来写死 0.17~0.27 秒 —— 各角色动画
    长度不同，这一段经常落在「武器还收着」的帧上，看起来就是盒子比武器大一圈。
    这里直接按图集算：前伸 >= 峰值 90% 的帧算判定帧。
    """
    extents = []
    for frame in frames:
        box = frame.getbbox()
        extents.append((box[2] - anchor_x) * pixel_size if box is not None else 0.0)
    peak = max(extents) if extents else 0.0
    if peak <= 0.0:
        return 0.0, 0.0
    active = [i for i, e in enumerate(extents) if e >= peak * ratio]
    if not active:
        return 0.0, 0.0
    first, last = active[0], active[-1]
    return round(first / SPRITE_FPS, 3), round((last - first + 1) / SPRITE_FPS, 3)


def main():
    with io.open(MANIFEST, encoding="utf-8") as f:
        manifest = json.load(f)

    for slug, entry in sorted(manifest["characters"].items()):
        char_dir = os.path.join(CHARS, slug)
        anims = entry["animations"]
        boxes = {}
        for name, data in anims.items():
            frames = load_frames(os.path.join(char_dir, data["file"]), data["frames"])
            boxes[name] = union_bbox(frames)
        ref_name = next((n for n in ("idle", "walk") if n in boxes), next(iter(boxes)))
        ref = boxes[ref_name]
        ref_h = max(ref[3] - ref[1], 1)
        pixel_size = TARGET_HEIGHT_M / float(ref_h)
        anchor_x = body_anchor_x(
            load_frames(os.path.join(char_dir, anims[ref_name]["file"]), anims[ref_name]["frames"]))
        anchor_y = ref[3]                      # 脚底
        # 必须在裁剪循环之前算 —— 裁剪会把图集覆盖成紧贴内容的版本，
        # 之后再 load_frames 就按 100px 切不开了。
        if "attack1" in anims:
            attack_frames = load_frames(
                os.path.join(char_dir, anims["attack1"]["file"]), anims["attack1"]["frames"])
            entry["melee_reach"] = melee_reach(attack_frames, anchor_x, pixel_size)
            windup, active = melee_window(attack_frames, anchor_x, pixel_size)
            if windup > 0.0 and active > 0.0:
                entry["melee_windup"] = windup
                entry["melee_active"] = active

        for name, data in anims.items():
            box = boxes[name]
            if box is None:
                continue
            x0, y0, x1, y1 = box
            w, h = x1 - x0, y1 - y0
            frames = load_frames(os.path.join(char_dir, data["file"]), data["frames"])
            sheet = Image.new("RGBA", (w * data["frames"], h), (0, 0, 0, 0))
            for i, fr in enumerate(frames):
                sheet.paste(fr.crop((x0, y0, x1, y1)), (i * w, 0))
            sheet.save(os.path.join(char_dir, data["file"]))

            # offset 单位是像素，+y 向上：把锚点 (anchor_x, anchor_y) 移到节点原点。
            offset_x = -((anchor_x - x0) - w * 0.5)
            offset_y = (anchor_y - y0) - h * 0.5
            data["frame_size"] = [w, h]
            data["offset"] = [round(offset_x, 2), round(offset_y, 2)]

        entry["pixel_size"] = round(pixel_size, 6)
        entry["animations"] = anims
        print("%-18s ref_h=%2d pixel_size=%.4f  quad≈%.2fm" % (
            slug, ref_h, pixel_size, SOURCE_FRAME * pixel_size))

    manifest["target_height_m"] = TARGET_HEIGHT_M
    manifest["normalized"] = True
    with io.open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    print("manifest updated:", MANIFEST)
    return 0


if __name__ == "__main__":
    sys.exit(main())
