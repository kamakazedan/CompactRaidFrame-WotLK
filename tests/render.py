#!/usr/bin/env python3
"""Render a wireframe preview of the options panel from the harness's layout dump.
usage: render.py out.png title tsv [tsv...]   (one column per tsv)"""
import sys, re
from PIL import Image, ImageDraw, ImageFont

S = 2                      # scale
PANEL_W, PANEL_H = 413, 428
CANVAS_W, CANVAS_H = 570, 560
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONTB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
GOLD = (255, 209, 0)
WHITE = (235, 235, 235)
GREY = (140, 140, 140)

def font(px, bold=False):
    return ImageFont.truetype(FONTB if bold else FONT, int(px * S))

def load(path):
    rows = []
    for line in open(path, encoding="utf-8"):
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 9:
            continue
        kind, name, text, l, t, r, b, extra, depth = parts
        rows.append(dict(kind=kind, name=name, text=text, l=float(l), t=float(t), r=float(r), b=float(b),
                         extra=extra.split(",") if extra else [], depth=int(depth)))
    return rows

def render(rows, title):
    im = Image.new("RGB", (CANVAS_W * S, (CANVAS_H + 24) * S), (18, 18, 22))
    d = ImageDraw.Draw(im)
    ox, oy = 20, 44
    X = lambda v: int((ox + v) * S)
    Y = lambda v: int((oy + v) * S)
    d.text((X(0), 8 * S), title, font=font(12, True), fill=WHITE)
    # the 3.3.5a panel container
    d.rectangle([X(0), Y(0), X(PANEL_W), Y(PANEL_H)], fill=(10, 10, 12), outline=(150, 150, 150), width=S)
    d.text((X(PANEL_W) - 120 * S, Y(PANEL_H) + 4 * S), "panel edge 413 x 428", font=font(8), fill=GREY)
    dropdown_children = set()
    for r in rows:
        if r["kind"] == "DropDown":
            dropdown_children.add(r["name"])
    for r in rows:
        k, n, l, t, rr, b = r["kind"], r["name"], r["l"], r["t"], r["r"], r["b"]
        parent_dd = any(n.startswith(dd) and n != dd for dd in dropdown_children)
        if k == "Frame" and "backdrop" in r["extra"]:
            d.rounded_rectangle([X(l), Y(t), X(rr), Y(b)], radius=5 * S, fill=(24, 24, 28), outline=(120, 120, 120), width=S)
        elif k == "Texture" and n.endswith(("Separator", "Divider")):
            d.line([X(l), Y(t), X(rr), Y(t)], fill=(70, 70, 70), width=S)
        elif k == "DropDown":
            d.rounded_rectangle([X(l + 17), Y(t + 6), X(rr - 17), Y(b - 4)], radius=3 * S, fill=(30, 30, 30), outline=(110, 110, 110), width=S)
            d.polygon([(X(rr - 31), Y(t + 13)), (X(rr - 23), Y(t + 13)), (X(rr - 27), Y(t + 19))], fill=GOLD)
        elif k == "CheckButton":
            cx, cy = (l + rr) / 2, (t + b) / 2
            dis = "disabled" in r["extra"]
            d.rectangle([X(cx - 8), Y(cy - 8), X(cx + 8), Y(cy + 8)], fill=(25, 25, 25), outline=(90, 90, 90) if dis else (190, 190, 190), width=S)
            if "checked" in r["extra"]:
                col = (120, 120, 120) if dis else GOLD
                d.line([X(cx - 5), Y(cy), X(cx - 1), Y(cy + 4), X(cx + 6), Y(cy - 5)], fill=col, width=2 * S)
        elif k == "Button" and re.search(r"Tab\d+$", n):
            active = "disabled" in r["extra"]
            fill = (60, 60, 64) if active else (34, 34, 38)
            d.rounded_rectangle([X(l + 4), Y(t), X(rr - 4), Y(b + (3 if active else 0))], radius=4 * S, fill=fill, outline=(150, 150, 150), width=S)
        elif k == "Button" and not parent_dd and (rr - l) > 40:
            dis = "disabled" in r["extra"]
            d.rounded_rectangle([X(l), Y(t), X(rr), Y(b)], radius=3 * S, fill=(70, 18, 14) if not dis else (45, 30, 28), outline=(170, 140, 60), width=S)
        elif k == "Slider":
            cy = (t + b) / 2
            d.rounded_rectangle([X(l + 3), Y(cy - 3), X(rr - 3), Y(cy + 3)], radius=2 * S, fill=(40, 40, 40), outline=(120, 120, 120), width=S)
            ex = dict(e.split("=", 1) for e in r["extra"] if "=" in e)
            try:
                v, mn, mx = float(ex["value"]), float(ex["min"]), float(ex["max"])
                px = l + 8 + (rr - l - 16) * (v - mn) / (mx - mn)
            except Exception:
                px = l + 8
            d.rectangle([X(px - 4), Y(cy - 7), X(px + 4), Y(cy + 7)], fill=(200, 200, 200))
    for r in rows:
        if r["kind"] != "FontString" or not r["text"]:
            continue
        n, l, t, rr, b, text = r["name"], r["l"], r["t"], r["r"], r["b"], r["text"]
        size = 10
        col = WHITE
        if n.endswith("Title"):
            size, col = 15, GOLD
        elif re.search(r"Tab\d+Text$", n):
            size, col = 9, GOLD
        elif n.endswith("Label") and ("Dropdown" in n or n.endswith("OptionsAutoActivateLabel")):
            size, col = 9.5 if "Dropdown" in n else 11, GOLD
        elif n.endswith(("Low", "High")):
            size = 8.5
        elif n.endswith("SliderValue"):
            size, col = 8.5, GOLD
        elif "red" in r["extra"]:
            col = (255, 40, 40)
        elif n.endswith("ButtonText"):
            col, size = GOLD, 10
        if "disabled" in r["extra"]:
            col = GREY
        f = font(size)
        w = d.textlength(text, font=f) / S
        if n.endswith(("Text",)) and "Selector" in n or "Dropdown" in n and n.endswith("Text"):
            x = rr - w            # dropdown text is right aligned
        elif n.endswith("ButtonText") or re.search(r"Tab\d+Text$", n) or (n.endswith("Label") and "Slider" in n) or n.endswith("SliderValue"):
            x = (l + rr) / 2 - w / 2
        else:
            x = l
        if "DisabledLabel" in n:
            # wrap inside its width
            words, line, yy = text.split(" "), "", t
            for wd in words:
                trial = (line + " " + wd).strip()
                if d.textlength(trial, font=f) / S > (rr - l):
                    d.text((X(x), Y(yy)), line, font=f, fill=(255, 40, 40)); yy += size + 3; line = wd
                else:
                    line = trial
            d.text((X(x), Y(yy)), line, font=f, fill=(255, 40, 40))
            continue
        d.text((X(x), Y((t + b) / 2 - size * 0.62)), text, font=f, fill=col)
    return im

def main():
    out, title, files = sys.argv[1], sys.argv[2], sys.argv[3:]
    tiles = [render(load(p), t) for p, t in zip(files[0::2], files[1::2])]
    W = sum(t.width for t in tiles)
    H = max(t.height for t in tiles)
    sheet = Image.new("RGB", (W, H), (18, 18, 22))
    x = 0
    for t in tiles:
        sheet.paste(t, (x, 0)); x += t.width
    sheet.save(out)

if __name__ == "__main__":
    main()
