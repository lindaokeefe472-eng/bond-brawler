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
        ref = boxes.get("idle") or boxes.get("walk") or next(iter(boxes.values()))
        ref_h = max(ref[3] - ref[1], 1)
        pixel_size = TARGET_HEIGHT_M / float(ref_h)
        anchor_x = (ref[0] + ref[2]) * 0.5     # idle 的水平中心
        anchor_y = ref[3]                      # idle 的脚底

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
