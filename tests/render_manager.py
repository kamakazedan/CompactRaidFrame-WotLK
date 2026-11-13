#!/usr/bin/env python3
"""Wireframe of the expanded raid manager from run.lua's dump-manager output.
usage: render_manager.py out.png title tsv [title tsv ...]"""
import sys
from PIL import Image, ImageDraw, ImageFont

S = 2
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONTB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
GOLD, WHITE, GREY = (255, 209, 0), (235, 235, 235), (120, 120, 120)

def font(px, bold=False):
    return ImageFont.truetype(FONTB if bold else FONT, int(px * S))

def load(path):
    rows = []
    for line in open(path, encoding="utf-8"):
        p = line.rstrip("\n").split("\t")
        if len(p) >= 9:
            rows.append(dict(kind=p[0], name=p[1], text=p[2], l=float(p[3]), t=float(p[4]), r=float(p[5]), b=float(p[6]),
                             extra=p[7].split(",") if p[7] else []))
    return rows

def render(rows, title):
    mgr = next(r for r in rows if r["name"] == "CompactRaidFrameManager")
    W, H = 260, max(300, mgr["b"] + 70)
    im = Image.new("RGB", (W * S, int(H * S)), (18, 18, 22))
    d = ImageDraw.Draw(im)
    ox, oy = 24, 40
    X = lambda v: int((ox + v) * S)
    Y = lambda v: int((oy + v) * S)
    d.text((X(-14), 10 * S), title, font=font(11, True), fill=WHITE)
    # panel body + border (the rock texture and stone border, simplified)
    d.rounded_rectangle([X(0), Y(0), X(mgr["r"] - 6), Y(mgr["b"])], radius=6 * S, fill=(52, 48, 44), outline=(150, 150, 150), width=2 * S)
    for r in rows:
        n, k, l, t, rr, b = r["name"], r["kind"], r["l"], r["t"], r["r"], r["b"]
        dis = "disabled" in r["extra"]
        if n.endswith("HeaderBackground"):
            d.rectangle([X(l), Y(t), X(rr), Y(b)], fill=(5, 5, 5))
        elif n.endswith("HeaderDelineator"):
            d.line([X(l + 4), Y((t + b) / 2 + 2), X(rr), Y((t + b) / 2 + 2)], fill=(110, 110, 110), width=S)
        elif k == "DropDown":
            d.rounded_rectangle([X(l + 17), Y(t + 6), X(rr - 17), Y(b - 8)], radius=3 * S, fill=(20, 20, 20), outline=(110, 110, 110), width=S)
            d.rectangle([X(rr - 40), Y(t + 8), X(rr - 22), Y(b - 10)], fill=(60, 50, 10), outline=(170, 140, 60), width=S)
            d.polygon([(X(rr - 36), Y(t + 13)), (X(rr - 26), Y(t + 13)), (X(rr - 31), Y(t + 19))], fill=GOLD)
        elif n.endswith("ToggleButton"):
            # the visible part of the toggle art is a narrow tab on the right border
            d.rounded_rectangle([X(rr - 7), Y(t), X(rr + 3), Y(b)], radius=3 * S, fill=(40, 36, 32), outline=(150, 150, 150), width=S)
            cx, cy = rr - 2, (t + b) / 2
            d.polygon([(X(cx + 3), Y(cy - 5)), (X(cx + 3), Y(cy + 5)), (X(cx - 3), Y(cy))], fill=GOLD)
        elif n.endswith("OptionsButton"):
            d.ellipse([X(l), Y(t), X(rr), Y(b)], fill=(30, 30, 120), outline=GOLD, width=S)
            d.text((X((l + rr) / 2 - 2), Y(t + 1)), "i", font=font(10, True), fill=WHITE)
        elif "RaidMarker" in n and k == "Button":
            col = (95, 95, 95) if "alpha=0.7" in r["extra"] or dis else (200, 200, 200)
            if n.endswith("Remove"):
                d.ellipse([X(l + 4), Y(t + 4), X(rr - 4), Y(b - 4)], outline=col, width=2 * S)
                d.line([X(l + 7), Y(b - 7), X(rr - 7), Y(t + 7)], fill=col, width=2 * S)
            else:
                d.regular_polygon((X((l + rr) / 2), Y((t + b) / 2), 10 * S), 4 + (hash(n[-1]) % 3), fill=col)
        elif k == "Slider":
            ex = dict(e.split("=", 1) for e in ";".join(r["extra"]).split(";") if "=" in e)
            cy = (t + b) / 2
            d.rounded_rectangle([X(l + 2), Y(cy - 3), X(rr - 2), Y(cy + 3)], radius=3 * S, fill=(15, 15, 15), outline=(120, 120, 120), width=S)
            try:
                frac = (float(ex["value"]) - float(ex["min"])) / (float(ex["max"]) - float(ex["min"]))
            except Exception:
                frac = 0
            tx = l + 8 + frac * (rr - l - 16)
            d.rectangle([X(tx - 4), Y(cy - 7), X(tx + 4), Y(cy + 7)], fill=(200, 200, 200), outline=(90, 90, 90), width=S)
        elif k == "Button" and (rr - l) >= 80:
            fill = (32, 30, 30)
            d.rounded_rectangle([X(l), Y(t), X(rr), Y(b)], radius=3 * S, fill=fill, outline=(150, 150, 150), width=S)
    for r in rows:
        if r["kind"] != "FontString" or not r["text"]:
            continue
        n, l, t, rr, b = r["name"], r["l"], r["t"], r["r"], r["b"]
        if "RaidMember" in n:
            f, col = font(11, True), GOLD
        elif "FrameSize" in n and n.endswith("Value"):
            f, col = font(9), GOLD
        elif "FrameSize" in n and n.endswith("Label"):
            f, col = font(9), WHITE
        else:
            f, col = font(9.5), WHITE
        parent_dis = any(p["kind"] == "Button" and n.startswith(p["name"]) and ("disabled" in p["extra"] or "alpha=0.5" in p["extra"]) for p in rows)
        if parent_dis:
            col = GREY
        w = d.textlength(r["text"], font=f) / S
        if n.endswith("CountLabel") or n.endswith("SelectorText") or ("FrameSize" in n and n.endswith("Value")):
            x = rr - w
        elif n.endswith("Text"):
            x = (l + rr) / 2 - w / 2
        else:
            x = l
        d.text((X(x), Y((t + b) / 2 - 7)), r["text"], font=f, fill=col)
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
