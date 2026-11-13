#!/usr/bin/env python3
"""Draw raid frame layouts dumped by run.lua's dump-raid scenario.
usage: render_raid.py out.png title tsv [title tsv ...]"""
import sys
from PIL import Image, ImageDraw, ImageFont
S = 2
F = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
def font(px, bold=False): return ImageFont.truetype(FB if bold else F, int(px * S))
def load(p):
    rows = []
    for line in open(p, encoding="utf-8"):
        parts = line.rstrip("\n").split("\t")
        k, name, l, t, r, b = parts[:6]
        rows.append((k, name, float(l), float(t), float(r), float(b), parts[6] if len(parts) > 6 else ""))
    return rows
BG = (18, 18, 22)
def rgb(s): return tuple(float(x) for x in s.split(","))
def mix(c, a, bg=BG): return tuple(int(bg[i] * (1 - a) + c[i] * 255 * a) for i in range(3))
def draw_box(d, X, Y, l, t, r, b, text, extra):
    """A totem / rune box: black edge, dim or bright fill, an 'icon' with its
    reversed cooldown sweep, a rune's charge rising from the bottom, the time."""
    fill, icon, sweep, charge = extra.split("|")
    fr, fg, fb, fa = rgb(fill)
    d.rectangle([X(l), Y(t), X(r), Y(b)], fill=(0, 0, 0))
    il, it, ir, ib = l + 1, t + 1, r - 1, b - 1
    d.rectangle([X(il), Y(it), X(ir), Y(ib)], fill=mix((fr, fg, fb), fa))
    if icon:
        c = rgb(icon)
        d.rectangle([X(il), Y(it), X(ir), Y(ib)], fill=mix(c, 1))
        # a little totem / figure glyph so it reads as an icon
        cx = (il + ir) / 2; w = (ir - il)
        d.rectangle([X(cx - w * 0.12), Y(it + w * 0.18), X(cx + w * 0.12), Y(ib - w * 0.12)], fill=mix(c, 1, (250, 250, 240)))
        d.rectangle([X(cx - w * 0.3), Y(it + w * 0.3), X(cx + w * 0.3), Y(it + w * 0.42)], fill=mix(c, 1, (250, 250, 240)))
        s = float(sweep)
        if s > 0:   # reversed sweep: the elapsed part darkens, clockwise from 12 o'clock
            d.pieslice([X(il), Y(it), X(ir), Y(ib)], -90, -90 + 360 * s, fill=(0, 0, 0, 150))
    ch = float(charge)
    if ch > 0:
        d.rectangle([X(il), Y(ib - (ib - it) * ch), X(ir), Y(ib)], fill=mix((fr, fg, fb), 0.75))
    if text:
        fnt = font(max(6, (b - t) * 0.55), True)
        tw = d.textlength(text, font=fnt) / S
        tx, ty = (l + r) / 2 - tw / 2 + 0.5, (t + b) / 2 - (b - t) * 0.33
        for ox, oy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            d.text((X(tx) + ox * S // 2, Y(ty) + oy * S // 2), text, font=fnt, fill=(0, 0, 0))
        d.text((X(tx), Y(ty)), text, font=fnt, fill=(255, 255, 255))
def render(rows, title):
    w = max(r[4] for r in rows) + 40
    h = max(r[5] for r in rows) + 70
    w = max(w, 200)
    im = Image.new("RGB", (int(w * S), int(h * S)), BG)
    d = ImageDraw.Draw(im, "RGBA")
    ox, oy = 16, 46
    X = lambda v: int((ox + v) * S); Y = lambda v: int((oy + v) * S)
    d.text((X(-6), 10 * S), title, font=font(11, True), fill=(235, 235, 235))
    pink = (245, 140, 186)        # paladin class colour (the preview shows your own frame)
    fills = {"unit": pink, "player": (20, 90, 190), "pet": (20, 170, 30)}
    for k, name, l, t, r, b, extra in rows:
        if k == "box":
            draw_box(d, X, Y, l, t, r, b, name, extra)
            continue
        if k == "bar":
            # four round totem icons with a timer under each
            size = min((r - l) / 4.4, (b - t) * 0.7)
            for i in range(4):
                cx = l + size / 2 + 2 + i * (size + 3); cy = t + size / 2 + 1
                d.ellipse([X(cx - size / 2), Y(cy - size / 2), X(cx + size / 2), Y(cy + size / 2)], fill=(200, 150, 30), outline=(240, 210, 120), width=S)
                d.text((X(cx - 6), Y(cy + size / 2 + 1)), f"{4 - i} m", font=font(9), fill=(255, 210, 0))
            continue
        if k in fills:
            d.rectangle([X(l), Y(t), X(r), Y(b)], fill=(40, 40, 40), outline=(90, 90, 90), width=S)
            d.rectangle([X(l + 1), Y(t + 1), X(r - 1), Y(b - 1)], fill=fills[k])
            d.text((X(l + 4), Y(t + 2)), name, font=font(8), fill=(255, 255, 255))
        elif k == "title":
            tw = d.textlength(name, font=font(8)) / S
            d.text((X((l + r) / 2 - tw / 2), Y(t + 1)), name, font=font(8), fill=(255, 209, 0))
    return im
def main():
    out, args = sys.argv[1], sys.argv[2:]
    tiles = [render(load(p), t) for t, p in zip(args[0::2], args[1::2])]
    sheet = Image.new("RGB", (sum(t.width for t in tiles), max(t.height for t in tiles)), (18, 18, 22))
    x = 0
    for t in tiles:
        sheet.paste(t, (x, 0)); x += t.width
    sheet.save(out)
if __name__ == "__main__":
    main()
