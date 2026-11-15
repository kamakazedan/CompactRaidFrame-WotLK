#!/usr/bin/env python3
"""Close-up of one raid unit frame from run.lua's dump-unit scenario.
usage: render_unit.py out.png title subtitle tsv [title subtitle tsv ...]"""
import os, sys
from PIL import Image, ImageDraw, ImageFont
S = 3
F = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FC = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"   # stands in for the game's narrow number font
def font(px, bold=False): return ImageFont.truetype(FB if bold else F, max(1, int(px * S)))
def numfont(px): return ImageFont.truetype(FC, max(1, int(px * S)))
def load(p):
    rows = []
    for line in open(p, encoding="utf-8"):
        parts = line.rstrip("\n").split("\t")
        k, text, l, t, r, b, size = parts[:7]
        rows.append((k, text, float(l), float(t), float(r), float(b), float(size), parts[7] if len(parts) > 7 else ""))
    return rows
BG = (18, 18, 22)
def rgb(s): return tuple(float(x) for x in s.split(","))
def mix(c, a, bg=BG): return tuple(int(bg[i] * (1 - a) + c[i] * 255 * a) for i in range(3))
def draw_box(d, X, Y, l, t, r, b, text, extra, under=BG):
    """A totem box: black edge, dim fill or an 'icon' with its reversed sweep, the time."""
    fill, icon, sweep, charge = extra.split("|")
    fr, fg, fb, fa = rgb(fill)
    d.rectangle([X(l), Y(t), X(r) - 1, Y(b) - 1], fill=(0, 0, 0))
    il, it, ir, ib = l + 1, t + 1, r - 1, b - 1
    d.rectangle([X(il), Y(it), X(ir) - 1, Y(ib) - 1], fill=mix((fr, fg, fb), fa))
    if icon:
        c = rgb(icon)
        d.rectangle([X(il), Y(it), X(ir) - 1, Y(ib) - 1], fill=mix(c, 1))
        cx = (il + ir) / 2; w = ir - il
        light = mix(c, 0.35, (250, 250, 240))
        d.rectangle([X(cx - w * 0.12), Y(it + w * 0.18), X(cx + w * 0.12), Y(ib - w * 0.12)], fill=light)
        d.rectangle([X(cx - w * 0.3), Y(it + w * 0.3), X(cx + w * 0.3), Y(it + w * 0.42)], fill=light)
        sw = float(sweep)
        if sw > 0:
            d.pieslice([X(il), Y(it), X(ir) - 1, Y(ib) - 1], -90, -90 + 360 * sw, fill=(0, 0, 0, 150))
    ch = float(charge)
    if ch > 0:      # a rune coming back: its colour rising from the bottom
        d.rectangle([X(il), Y(ib - (ib - it) * ch), X(ir) - 1, Y(ib) - 1], fill=mix((fr, fg, fb), 0.75))
    if text:
        f = numfont(max(5, (b - t) * 0.55))
        bbox = d.textbbox((0, 0), text, font=f)
        tw, th = (bbox[2] - bbox[0]) / S, (bbox[3] - bbox[1]) / S
        x = (l + r) / 2 - tw / 2 + 0.3; y = (t + b) / 2 - th / 2 - bbox[1] / S
        for ox, oy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            d.text((X(x) + ox * S // 2, Y(y) + oy * S // 2), text, font=f, fill=(0, 0, 0))
        d.text((X(x), Y(y)), text, font=f, fill=(255, 255, 255))
BUFF = [(40, 160, 220), (60, 180, 90), (150, 110, 220)]
DEBUFF = [(150, 40, 160), (200, 160, 40), (60, 140, 60)]
DISPEL = [(50, 110, 230), (40, 170, 40), (170, 120, 40)]
HIGHLIGHTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "CompactRaidFrame", "Texture", "RAIDFRAME", "Raid-FrameHighlights.blp")
def rest_glow(im, X, Y, l, t, r, b, alpha):
    """The frame's aggro glow art (Raid-FrameHighlights, Raid-AggroFrame coords),
    tinted the player frame's rested gold and faded like the addon does."""
    tex = Image.open(HIGHLIGHTS).convert("RGBA")
    w, h = tex.size
    crop = tex.crop((round(0.0078125 * w), round(0.0078125 * h), round(0.5546875 * w), round(0.2734375 * h)))
    crop = crop.resize((X(r) - X(l), Y(b) - Y(t)), Image.BILINEAR)
    cr, cg, cb, ca = crop.split()
    tint = Image.merge("RGBA", (cr.point(lambda v: int(v * 1.0)), cg.point(lambda v: int(v * 0.88)), cb.point(lambda v: int(v * 0.25)),
                                ca.point(lambda v: int(v * alpha))))
    im.paste(tint, (X(l), Y(t)), tint)
def zzz(d, X, Y, l, t, r, b):
    """A stand-in for Blizzard's rest icon (UI-StateIcon): three gold z's."""
    size = b - t
    for i, (fx, fy, fs) in enumerate(((0.02, 0.38, 0.62), (0.40, 0.14, 0.48), (0.68, -0.04, 0.38))):
        f = ImageFont.truetype(FB, max(1, int(size * fs * S)))
        x, y = X(l + size * fx), Y(t + size * fy)
        for ox, oy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            d.text((x + ox * S // 2, y + oy * S // 2), "z", font=f, fill=(40, 25, 0))
        d.text((x, y), "z", font=f, fill=(255, 215, 70))
def render(rows, title, sub):
    get = lambda k: next((r for r in rows if r[0] == k), None)
    fr = get("frame"); fw, fh = fr[4], fr[5]
    W, H = max(fw + 40, 205), max(r[5] for r in rows) + 64
    im = Image.new("RGB", (int(W * S), int(H * S)), BG)
    d = ImageDraw.Draw(im, "RGBA")
    ox, oy = 20, 50
    X = lambda v: int(round((ox + v) * S)); Y = lambda v: int(round((oy + v) * S))
    d.text((X(-4), 8 * S), title, font=font(9, True), fill=(235, 235, 235))
    d.text((X(-4), 22 * S), sub, font=font(7), fill=(150, 150, 150))
    d.rectangle([X(0), Y(0), X(fw), Y(fh)], fill=(0, 0, 0))
    _, _, l, t, r, b, _, _ = get("health")
    d.rectangle([X(l), Y(t), X(r) - 1, Y(b) - 1], fill=(0, 100, 200))       # shaman blue
    p = get("power")
    if p:
        _, _, l, t, r, b, _, _ = p
        d.rectangle([X(l), Y(t), X(r) - 1, Y(b) - 1], fill=(10, 10, 40))
        pt = get("powertext")
        frac = float(pt[1].rstrip("%")) / 100 if pt and pt[1].endswith("%") else 0.734
        d.rectangle([X(l), Y(t), X(l + (r - l) * frac) - 1, Y(b) - 1], fill=(30, 60, 235))
    def text(row, colour, centre, scale=0.9):
        txt, l, t, r, b, size = row[1:7]
        size = size or 10
        f = font(size * scale)
        bbox = d.textbbox((0, 0), txt, font=f)
        cut = txt
        while not centre and len(cut) > 1 and (bbox[2] - bbox[0]) / S > (r - l):
            cut = cut[:-1]; txt = cut + "..."
            bbox = d.textbbox((0, 0), txt, font=f)
        tw, th = (bbox[2] - bbox[0]) / S, (bbox[3] - bbox[1]) / S
        x = (l + r) / 2 - tw / 2 if centre else l
        y = (t + b) / 2 - th / 2 - bbox[1] / S
        d.text((X(x) + S, Y(y) + S), txt, font=f, fill=(0, 0, 0))
        d.text((X(x), Y(y)), txt, font=f, fill=colour)
    nf = get("nframe")          # the next player, under you (a warlock)
    if nf:
        _, _, l, t, r, b, _, _ = nf
        d.rectangle([X(l), Y(t), X(r), Y(b)], fill=(0, 0, 0))
        _, _, l, t, r, b, _, _ = get("nhealth")
        d.rectangle([X(l), Y(t), X(r) - 1, Y(b) - 1], fill=(148, 130, 201))
        np_ = get("npower")
        if np_:
            _, _, l, t, r, b, _, _ = np_
            d.rectangle([X(l), Y(t), X(r) - 1, Y(b) - 1], fill=(30, 60, 235))
        if get("nname"): text(get("nname"), (255, 255, 255), False, 1.0)
        if get("nstatus"): text(get("nstatus"), (128, 128, 128), True)
        if get("npowertext"): text(get("npowertext"), (255, 255, 255), True)
    for row in [r for r in rows if r[0] == "room"]:   # empty room: a dashed outline
        _, _, l, t, r, b, _, _ = row
        for x in range(int(l), int(r), 6):
            d.line([X(x), Y(t + 0.5), X(min(x + 3, r)), Y(t + 0.5)], fill=(110, 110, 120), width=max(1, S // 2))
            d.line([X(x), Y(b - 0.5), X(min(x + 3, r)), Y(b - 0.5)], fill=(110, 110, 120), width=max(1, S // 2))
    for row in [r for r in rows if r[0] == "box"]:
        _, txt, l, t, r, b, _, extra = row
        draw_box(d, X, Y, l, t, r, b, txt, extra)
    rg = get("restglow")
    if rg:
        _, _, l, t, r, b, _, extra = rg
        rest_glow(im, X, Y, l, t, r, b, float(extra))
    ri = get("resticon")
    if ri:
        _, _, l, t, r, b, _, _ = ri
        zzz(d, X, Y, l, t, r, b)
    role = get("role")
    if role:
        _, _, l, t, r, b, _, _ = role
        d.ellipse([X(l), Y(t), X(r), Y(b)], fill=(90, 60, 30), outline=(200, 170, 90))
    for k, colours in (("buff", BUFF), ("debuff", DEBUFF), ("dispel", DISPEL)):
        for i, row in enumerate([r for r in rows if r[0] == k]):
            _, txt, l, t, r, b, _, _ = row
            c = colours[i % len(colours)]
            d.rectangle([X(l), Y(t), X(r) - 1, Y(b) - 1], fill=c, outline=(230, 60, 60) if k == "debuff" else (20, 20, 20), width=max(1, S // 2) if k == "debuff" else 1)
            if txt:
                f = font(7)
                d.text((X(r) - 5 * S + S // 2, Y(b) - 9 * S + S // 2), txt, font=f, fill=(0, 0, 0))
                d.text((X(r) - 5 * S, Y(b) - 9 * S), txt, font=f, fill=(255, 255, 255))
    if get("name"): text(get("name"), (255, 255, 255), False, 1.0)
    if get("status"): text(get("status"), (128, 128, 128), True)
    if get("powertext"): text(get("powertext"), (255, 255, 255), True)
    return im
def main():
    out, args = sys.argv[1], sys.argv[2:]
    cols = 0
    if args and args[0].startswith("--cols="):
        cols = int(args[0].split("=")[1]); args = args[1:]
    tiles = [render(load(args[i + 2]), args[i], args[i + 1]) for i in range(0, len(args), 3)]
    cols = cols or len(tiles)
    rows_ = [tiles[i:i + cols] for i in range(0, len(tiles), cols)]
    tw = max(t.width for t in tiles); th = [max(t.height for t in r) for r in rows_]
    sheet = Image.new("RGB", (tw * cols, sum(th)), BG)
    y = 0
    for r, h in zip(rows_, th):
        for i, t in enumerate(r):
            sheet.paste(t, (i * tw, y))
        y += h
    sheet.save(out)
if __name__ == "__main__":
    main()
