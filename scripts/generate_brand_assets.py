#!/usr/bin/env python3
"""Render the pixel-"t" Trace.Pay mark for web, iOS and Android from one source of truth.

    python scripts/generate_brand_assets.py
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
VIOLET, LIME, WHITE = (91, 46, 255), (198, 255, 61), (255, 255, 255)
# 9 x 8 grid from the design file; (x, y, colour)
PIXELS = [(3, 1), (4, 1), (3, 2), (4, 2), (1, 3), (2, 3), (3, 3), (4, 3), (5, 3), (6, 3),
          (3, 4), (4, 4), (3, 5), (4, 5), (6, 5), (7, 5), (4, 6), (5, 6), (6, 6)]
LIME_PIXEL = (7, 6)


def render(size: int, *, rounded: bool, bg=VIOLET, inset=0.12) -> Image.Image:
    scale = 4  # supersample for clean rounded corners
    S = size * scale
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if rounded:
        d.rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.24), fill=bg)
    else:
        d.rectangle([0, 0, S, S], fill=bg)
    area = S * (1 - 2 * inset)
    cell = area / 9
    ox = (S - cell * 9) / 2
    oy = (S - cell * 8) / 2 + cell * 0.1
    for x, y in PIXELS + [LIME_PIXEL]:
        colour = LIME if (x, y) == LIME_PIXEL else WHITE
        d.rectangle([ox + x * cell, oy + y * cell, ox + (x + 1) * cell + 1, oy + (y + 1) * cell + 1], fill=colour)
    return img.resize((size, size), Image.LANCZOS)


def svg(rounded=True) -> str:
    rects = "".join(f'<rect x="{x}" y="{y}" width="1.03" height="1.03" fill="#fff"/>' for x, y in PIXELS)
    rects += f'<rect x="{LIME_PIXEL[0]}" y="{LIME_PIXEL[1]}" width="1.03" height="1.03" fill="#C6FF3D"/>'
    bg = '<rect x="-1.5" y="-2" width="12" height="12" rx="2.9" fill="#5B2EFF"/>' if rounded else ''
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="-1.5 -2 12 12" shape-rendering="crispEdges">'
            f'<title>trace.pay</title>{bg}{rects}</svg>\n')


def save(img, *paths):
    for p in paths:
        p = ROOT / p
        p.parent.mkdir(parents=True, exist_ok=True)
        img.save(p)
        print("wrote", p.relative_to(ROOT))


mark512 = render(512, rounded=True)
icon1024 = render(1024, rounded=False)  # iOS rounds app icons itself; must be opaque and full-bleed
save(mark512, "shared-brand/tracepay-mark.png", "web-console/public/tracepay-mark.png", "web-console/src/assets/tracepay-mark.png",
     "ios-app/TracePay/Assets.xcassets/TracePayMark.imageset/TracePayMark.png",
     "ios-app/TracePay/Assets.xcassets/TracePayLogo.imageset/TracePayLogo.png",
     "android-app/app/src/main/res/drawable-nodpi/tracepay_mark.png")
save(icon1024.convert("RGB"), "shared-brand/tracepay-app-icon.png", "web-console/public/tracepay-app-icon.png",
     "ios-app/TracePay/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
for folder, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    save(render(px, rounded=True), f"android-app/app/src/main/res/mipmap-{folder}/ic_launcher.png")
for path in ("shared-brand/tracepay-mark.svg", "web-console/public/tracepay-mark.svg"):
    (ROOT / path).write_text(svg()); print("wrote", path)
# Lighter chip for use on violet backgrounds (sign-in panel), matching the design's #8F6BFF tile.
for path in ("shared-brand/tracepay-mark-on-violet.svg", "web-console/public/tracepay-mark-on-violet.svg"):
    (ROOT / path).write_text(svg().replace('fill="#5B2EFF"', 'fill="#8F6BFF"')); print("wrote", path)
