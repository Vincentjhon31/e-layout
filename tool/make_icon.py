"""Draws the e-Layout icon and writes every export.

Idea: a photo (white card with two mountains) whose bottom third is the layout
band (deep navy with a yellow line on top), in front of a second card, on the
PIO blue. No letters, no sun, no sky.

Run: python tool/make_icon.py
Needs Pillow. Writes (all relative to the project folder):
  tool/icon_1024.png, tool/icon_foreground_1024.png    masters
  android/app/src/main/res/mipmap-*/ic_launcher*.png   legacy, foreground, monochrome
  android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
  android/app/src/main/res/values/ic_launcher_background.xml
  windows/runner/resources/app_icon.ico                16..256
  web/favicon.png, web/icons/Icon-192/512 and Icon-maskable-192/512
  assets/img/app_icon.png                              256, shown in About
  build/icon_check.png                                 contact sheet to judge by eye
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
S = 4096  # draw at 4x4 and reduce for smooth edges
U = S / 1024  # one design unit in pixels

BLUE = (0x1A, 0x6F, 0xB3)
NAVY = (0x0F, 0x35, 0x56)
YELLOW = (0xF2, 0xC2, 0x30)
MOUNT_BACK = (0xA9, 0xCB, 0xEA)
MOUNT_FRONT = (0x6F, 0xA3, 0xD6)

FRONT = (248, 300, 776, 748)
BACK = (296, 252, 824, 700)
RADIUS = 48
BAND_TOP = FRONT[3] - round((FRONT[3] - FRONT[1]) * 0.34)  # 596
LINE = 24
GROUP_CENTER = ((BACK[0] + FRONT[0]) / 2 + (BACK[2] - BACK[0]) / 2 - 0, (BACK[1] + FRONT[3]) / 2)
# centre of the box that holds both cards
GROUP_CENTER = ((FRONT[0] + BACK[2]) / 2, (BACK[1] + FRONT[3]) / 2)


def mapper(scale: float, recenter: bool):
    cx, cy = GROUP_CENTER

    def f(x, y):
        if recenter:
            x, y = (x - cx) * scale + 512, (y - cy) * scale + 512
        else:
            x, y = x * scale, y * scale
        return x * U, y * U

    return f


def rbox(draw, box, radius, fill, m):
    (x0, y0), (x1, y1) = m(box[0], box[1]), m(box[2], box[3])
    # radius scales with the mapping (scale is the same in x and y)
    r = radius * (m(1, 0)[0] - m(0, 0)[0])
    draw.rounded_rectangle((x0, y0, x1, y1), r, fill=fill)


def cards(scale=1.0, recenter=False, mode="color") -> Image.Image:
    """The two cards on a transparent 4096 canvas. mode: color or mono."""
    m = mapper(scale, recenter)
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mono = mode == "mono"
    # back card
    back = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rbox(ImageDraw.Draw(back), BACK, RADIUS, (255, 255, 255, 115 if not mono else 130), m)
    img = Image.alpha_composite(img, back)
    # front card
    front_mask = Image.new("L", (S, S), 0)
    rbox(ImageDraw.Draw(front_mask), FRONT, RADIUS, 255, m)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rectangle((0, 0, S, S), fill=(255, 255, 255, 255))
    # mountains (above the band)
    def poly(points, color):
        d.polygon([m(x, y) for x, y in points], fill=color)

    poly([(200, BAND_TOP), (420, 392), (650, BAND_TOP)], MOUNT_BACK + (255,) if not mono else (255, 255, 255, 110))
    poly([(380, BAND_TOP), (580, 440), (820, BAND_TOP)], MOUNT_FRONT + (255,) if not mono else (255, 255, 255, 190))
    # the layout band and its yellow line
    x0, y0 = m(0, BAND_TOP)
    x1, y1 = m(0, BAND_TOP + LINE)
    x2, y2 = m(0, FRONT[3] + 10)
    d.rectangle((0, y0, S, y2), fill=NAVY + (255,) if not mono else (0, 0, 0, 0))
    d.rectangle((0, y0, S, y1), fill=YELLOW + (255,) if not mono else (255, 255, 255, 255))
    if mono:
        # the card itself stays solid white except the cut-out band
        pass
    clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    clipped.paste(layer, (0, 0), front_mask)
    if mono:
        # make the band a real hole: clear alpha under the band, keep the line
        pix = clipped.load()
        ys = int(y1)
        ye = int(y2)
        for y in range(ys, min(ye, S)):
            for x in range(S):
                r, g, b, a = pix[x, y]
                if a:
                    pix[x, y] = (255, 255, 255, 0)
    return Image.alpha_composite(img, clipped)


def squircle_bg(radius=224, color=BLUE) -> Image.Image:
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle((0, 0, S - 1, S - 1), radius * U, fill=color + (255,))
    return img


def full_icon() -> Image.Image:
    return Image.alpha_composite(squircle_bg(), cards())


def foreground() -> Image.Image:
    # the cards' far corner must stay inside the 61% safe circle of the adaptive icon
    return cards(scale=0.78, recenter=True)


def monochrome() -> Image.Image:
    return cards(scale=0.78, recenter=True, mode="mono")


def maskable() -> Image.Image:
    bg = Image.new("RGBA", (S, S), BLUE + (255,))
    return Image.alpha_composite(bg, cards(scale=1.0, recenter=True))


def shrink(img: Image.Image, px: int) -> Image.Image:
    return img.resize((px, px), Image.LANCZOS)


def save(img: Image.Image, path: Path, px: int | None = None):
    path.parent.mkdir(parents=True, exist_ok=True)
    (shrink(img, px) if px else img).save(path)


def main():
    full, fg, mono, mask = full_icon(), foreground(), monochrome(), maskable()
    save(full, ROOT / "tool" / "icon_1024.png", 1024)
    save(fg, ROOT / "tool" / "icon_foreground_1024.png", 1024)

    res = ROOT / "android" / "app" / "src" / "main" / "res"
    for folder, legacy, layer in [("mdpi", 48, 108), ("hdpi", 72, 162), ("xhdpi", 96, 216), ("xxhdpi", 144, 324), ("xxxhdpi", 192, 432)]:
        save(full, res / f"mipmap-{folder}" / "ic_launcher.png", legacy)
        save(fg, res / f"mipmap-{folder}" / "ic_launcher_foreground.png", layer)
        save(mono, res / f"mipmap-{folder}" / "ic_launcher_monochrome.png", layer)
    (res / "mipmap-anydpi-v26").mkdir(parents=True, exist_ok=True)
    (res / "mipmap-anydpi-v26" / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        '</adaptive-icon>\n',
        encoding="utf-8",
    )
    (res / "values" / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        '    <color name="ic_launcher_background">#1A6FB3</color>\n'
        '</resources>\n',
        encoding="utf-8",
    )

    ico_dir = ROOT / "windows" / "runner" / "resources"
    big = shrink(full, 256)
    big.save(ico_dir / "app_icon.ico", sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])

    web = ROOT / "web"
    save(full, web / "favicon.png", 32)
    for px in (192, 512):
        save(full, web / "icons" / f"Icon-{px}.png", px)
        save(mask, web / "icons" / f"Icon-maskable-{px}.png", px)
    save(full, ROOT / "assets" / "img" / "app_icon.png", 256)
    contact_sheet(full, fg)
    print("icons written")


def contact_sheet(full: Image.Image, fg: Image.Image):
    sizes = [16, 24, 32, 48, 64, 128, 192]
    row_h = 210
    W = 60 + sum(sizes) + 20 * len(sizes) + 520
    sheet = Image.new("RGB", (W, row_h * 3 + 330), "white")
    for r, bg in enumerate([(255, 255, 255), (0xF2, 0xF2, 0xF7), (0, 0, 0)]):
        ImageDraw.Draw(sheet).rectangle((0, r * row_h, W, (r + 1) * row_h), fill=bg)
        x = 30
        for s in sizes:
            ic = shrink(full, s)
            sheet.paste(ic, (x, r * row_h + (row_h - s) // 2), ic)
            x += s + 20
    # the adaptive foreground under a circle and a squircle mask, on the blue
    y = row_h * 3 + 20
    base = Image.new("RGBA", (S, S), BLUE + (255,))
    ad = Image.alpha_composite(base, fg)
    for i, kind in enumerate(["circle", "squircle"]):
        mask = Image.new("L", (S, S), 0)
        dm = ImageDraw.Draw(mask)
        if kind == "circle":
            dm.ellipse((0, 0, S - 1, S - 1), fill=255)
        else:
            dm.rounded_rectangle((0, 0, S - 1, S - 1), S * 0.3, fill=255)
        shown = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        shown.paste(ad, (0, 0), mask)
        small = shrink(shown, 280)
        sheet.paste(small, (30 + i * 310, y), small)
    # beside them: the calendar's icon, for comparison (read only)
    cal = Path("C:/Windows_Applications/barangay_events/web/icons/Icon-192.png")
    if cal.exists():
        c = Image.open(cal).convert("RGBA").resize((192, 192), Image.LANCZOS)
        sheet.paste(c, (700, y), c)
        e = shrink(full, 192)
        sheet.paste(e, (930, y), e)
    out = ROOT / "build" / "icon_check.png"
    out.parent.mkdir(exist_ok=True)
    sheet.save(out)


if __name__ == "__main__":
    main()
