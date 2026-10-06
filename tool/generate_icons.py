"""Draws Hearth's launcher icon, adaptive-icon foreground, TV banner and the Settings logo.

A fire burning on a hearthstone, on a dark ember background; the banner adds the name under the stone. Everything is drawn at 4x and downsampled,
so edges stay smooth at every density. Re-run after changing the design:

    py -3 tool/generate_icons.py

Needs Pillow (py -3 -m pip install pillow).
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android" / "app" / "src" / "main" / "res"
SS = 4  # supersampling factor

BG_TOP = (52, 26, 18)
BG_BOTTOM = (18, 10, 8)
STONE_TOP = (226, 204, 176)
STONE_FRONT = (170, 144, 118)
STONE_JOINT = (132, 108, 88)
FLAME_OUTER = (255, 112, 26)
FLAME_MID = (255, 170, 48)
FLAME_CORE = (255, 236, 170)
LOG = (122, 66, 38)
LOG_END = (196, 140, 96)
TEXT = (246, 228, 200)

# Adaptive-icon background colour (also written to values/colors.xml).
ADAPTIVE_BG = "#1E110C"


def vertical_gradient(size, top, bottom):
    w, h = size
    img = Image.new("RGB", size, top)
    draw = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        draw.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img


def teardrop(cx, cy, w, h, lean=0.0, steps=240):
    """Flame outline: round at the bottom, pointed at the top, the tip pushed sideways by `lean`."""
    points = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        x = math.sin(t) * math.sin(t / 2) ** 1.6
        y = -math.cos(t)
        top = max(0.0, -y)  # 0 at the bottom half, up to 1 at the tip
        points.append((cx + w * x + lean * w * top ** 2, cy + h * y))
    return points


def emblem(size):
    """Fire burning on a hearthstone, on a transparent square canvas of `size` px (drawn at SS x)."""
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    # Firelight around the flame.
    glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([s * 0.24, s * 0.22, s * 0.76, s * 0.76], fill=FLAME_OUTER + (120,))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(s * 0.07)))

    draw = ImageDraw.Draw(img)
    # Hearthstone: a lit top face and a darker front face split into three blocks.
    draw.polygon([(s * 0.16, s * 0.68), (s * 0.84, s * 0.68), (s * 0.92, s * 0.74), (s * 0.08, s * 0.74)],
                 fill=STONE_TOP + (255,))
    draw.rounded_rectangle([s * 0.08, s * 0.74, s * 0.92, s * 0.86], radius=s * 0.02, fill=STONE_FRONT + (255,))
    for x in (0.36, 0.64):
        draw.line([(s * x, s * 0.745), (s * x, s * 0.855)], fill=STONE_JOINT + (255,), width=round(s * 0.012))

    # Crossed logs resting on the stone, with cut ends.
    log_w = round(s * 0.065)
    for (x0, y0), (x1, y1) in (((0.30, 0.71), (0.66, 0.63)), ((0.34, 0.63), (0.70, 0.71))):
        draw.line([(s * x0, s * y0), (s * x1, s * y1)], fill=LOG + (255,), width=log_w)
    for x, y in ((0.30, 0.71), (0.70, 0.71)):
        r = log_w / 2
        draw.ellipse([s * x - r, s * y - r, s * x + r, s * y + r], fill=LOG_END + (255,))

    # Flame: three nested teardrops.
    draw.polygon(teardrop(s * 0.50, s * 0.44, s * 0.20, s * 0.28, lean=0.25), fill=FLAME_OUTER + (255,))
    draw.polygon(teardrop(s * 0.505, s * 0.50, s * 0.135, s * 0.21, lean=-0.2), fill=FLAME_MID + (255,))
    draw.polygon(teardrop(s * 0.50, s * 0.56, s * 0.07, s * 0.13, lean=0.15), fill=FLAME_CORE + (255,))

    return img.resize((size, size), Image.LANCZOS)


def legacy_icon(px):
    """Square launcher icon for pre-Oreo devices and the About dialog: emblem on a rounded ember tile."""
    s = px * SS
    tile = vertical_gradient((s, s), BG_TOP, BG_BOTTOM).convert("RGBA")
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=s * 0.22, fill=255)
    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    out.paste(tile, (0, 0), mask)
    out = out.resize((px, px), Image.LANCZOS)
    mark = emblem(round(px * 0.80))
    off = (px - mark.width) // 2
    out.alpha_composite(mark, (off, off))
    return out


def adaptive_foreground(px):
    """108dp foreground: the emblem fits the 66dp safe zone so any mask shape keeps it whole."""
    out = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    mark = emblem(round(px * 0.58))
    off = (px - mark.width) // 2
    out.alpha_composite(mark, (off, off))
    return out


def banner(w, h):
    """TV banner (320x180 dp): fire on the hearthstone, the name under the stone."""
    s_w, s_h = w * SS, h * SS
    img = vertical_gradient((s_w, s_h), BG_TOP, BG_BOTTOM).convert("RGBA")
    # Soft firelight behind the fire.
    glow = Image.new("RGBA", (s_w, s_h), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([s_w * 0.30, -s_h * 0.10, s_w * 0.70, s_h * 0.80], fill=FLAME_OUTER + (60,))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(s_h * 0.12)))
    img = img.resize((w, h), Image.LANCZOS)

    # Trim the emblem to what is actually drawn so the stone sits right above the name.
    mark = emblem(h * 2)
    mark = mark.crop(mark.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox())
    mark_h = round(h * 0.58)
    mark = mark.resize((round(mark.width * mark_h / mark.height), mark_h), Image.LANCZOS)
    top = round(h * 0.07)
    img.alpha_composite(mark, ((w - mark.width) // 2, top))

    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype("C:/Windows/Fonts/georgiab.ttf", round(h * 0.19))
    text = "Hearth"
    l, t, r, b = draw.textbbox((0, 0), text, font=font)
    draw.text(((w - (r - l)) // 2 - l, top + mark_h + round(h * 0.05) - t), text, font=font, fill=TEXT)
    return img.convert("RGB")


def wordmark(h):
    """Settings header: the emblem with the name beside it, on a transparent background, `h` px tall."""
    mark = emblem(h * 2)
    mark = mark.crop(mark.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox())
    mark = mark.resize((round(mark.width * h / mark.height), h), Image.LANCZOS)

    font = ImageFont.truetype("C:/Windows/Fonts/georgiab.ttf", round(h * 0.62))
    text = "Hearth"
    probe = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    l, t, r, b = probe.textbbox((0, 0), text, font=font)
    gap = round(h * 0.18)
    img = Image.new("RGBA", (mark.width + gap + (r - l), h), (0, 0, 0, 0))
    img.alpha_composite(mark, (0, 0))
    # Text baseline sits level with the bottom of the stone.
    ImageDraw.Draw(img).text((mark.width + gap - l, h - b - round(h * 0.06)), text, font=font, fill=TEXT)
    return img


def main():
    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for name, scale in densities.items():
        legacy_icon(round(48 * scale)).save(RES / f"mipmap-{name}" / "ic_launcher.png")
        adaptive_foreground(round(108 * scale)).save(RES / f"drawable-{name}" / "ic_launcher_foreground.png")

    tv_banner = banner(640, 360)  # xhdpi, the density Android TV uses
    tv_banner.save(RES / "drawable-xhdpi" / "banner.png")
    banner(320, 180).save(RES / "drawable" / "banner.png")
    tv_banner.save(ROOT / "assets" / "banner.png")
    legacy_icon(256).save(ROOT / "assets" / "icon.png")
    wordmark(168).save(ROOT / "assets" / "logo.png")  # shown 56 dp tall in Settings

    colors = RES / "values" / "colors.xml"
    text = colors.read_text(encoding="utf-8")
    import re

    colors.write_text(
        re.sub(r'(<color name="ic_launcher_background">)[^<]*(</color>)', rf"\g<1>{ADAPTIVE_BG}\g<2>", text),
        encoding="utf-8",
    )
    print("icons written")


if __name__ == "__main__":
    main()
