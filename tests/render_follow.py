#!/usr/bin/env python3
"""Menu closed / open with the raid frames (run.lua dump-follow). usage: render_follow.py out.png closed.tsv open.tsv"""
import sys
from PIL import Image, ImageDraw, ImageFont
S = 2
F = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"; FB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
def font(px, bold=False): return ImageFont.truetype(FB if bold else F, int(px * S))
def load(p):
    return [(k, n, float(l), float(t), float(r), float(b)) for k, n, l, t, r, b in (line.rstrip("\n").split("\t") for line in open(p, encoding="utf-8"))]
def tile(rows, title):
    W = 470
    H = int(max(r[5] for r in rows) - 120 + 60)
    im = Image.new("RGB", (W * S, H * S), (18, 18, 22)); d = ImageDraw.Draw(im)
    oy = 120   # screen y of the tile's top edge (menu sits at 140 from the top)
    X = lambda v: int((v + 10) * S); Y = lambda v: int((v - oy + 40) * S)
    d.text((10 * S, 8 * S), title, font=font(11, True), fill=(235, 235, 235))
    d.rectangle([X(-10), Y(oy - 10), X(0), Y(oy + H)], fill=(60, 60, 60))     # beyond the left screen edge
    for k, n, l, t, r, b in rows:
        if k == "menu":
            d.rounded_rectangle([X(max(l, -2)), Y(t), X(r), Y(b)], radius=5 * S, fill=(52, 48, 44), outline=(150, 150, 150), width=2 * S)
            if r - l > 0 and l > -100:
                d.text((X(l + 14), Y(t + 10)), "side menu (open)", font=font(9, True), fill=(255, 209, 0))
            d.rounded_rectangle([X(r - 9), Y((t + b) / 2 - 25), X(r + 1), Y((t + b) / 2 + 25)], radius=3 * S, fill=(40, 36, 32), outline=(150, 150, 150), width=S)
    for k, n, l, t, r, b in rows:
        if k == "unit":
            d.rectangle([X(l), Y(t), X(r), Y(b)], fill=(40, 40, 40), outline=(90, 90, 90), width=S)
            d.rectangle([X(l + 1), Y(t + 1), X(r - 1), Y(b - 1)], fill=(245, 140, 186))
            d.text((X(l + 4), Y(t + 2)), n, font=font(8), fill=(255, 255, 255))
    return im
closed, opened = load(sys.argv[2]), load(sys.argv[3])
a, b = tile(closed, "Menu closed"), tile(opened, "Menu open: the frames slide over")
sheet = Image.new("RGB", (a.width + b.width, a.height), (18, 18, 22)); sheet.paste(a, (0, 0)); sheet.paste(b, (a.width, 0)); sheet.save(sys.argv[1])
