"""Makes the site's pictures from the app's own artwork. Re-run it after the
icon or the goldens change:

    python tool/site_images.py

Reads   tool/icon_1024.png, assets/img/seal-96.png and two phone goldens
        (home_photos_light and editor_none_light: generated pictures, never real photos).
Writes  hostinger/public_html/landing/app-icon.png (256), apple-touch-icon.png (180),
        og.png (1200x630), seal-96.png, screens/home.webp, screens/editor.webp;
        hostinger/public_html/favicon.ico (16, 32, 48);
        hostinger/public_html/download/app-icon.png, seal-96.png.
"""
import os
import shutil
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
SITE = os.path.join(PROJECT, 'hostinger', 'public_html')
LANDING = os.path.join(SITE, 'landing')
DOWNLOAD = os.path.join(SITE, 'download')

ICON = os.path.join(HERE, 'icon_1024.png')
SEAL = os.path.join(PROJECT, 'assets', 'img', 'seal-96.png')
GOLDENS = {
    'home.webp': os.path.join(PROJECT, 'test', 'features', 'home', 'goldens', 'home_photos_light.png'),
    'editor.webp': os.path.join(PROJECT, 'test', 'features', 'editor', 'goldens', 'editor_none_light.png'),
}
FONTS = 'C:/Windows/Fonts/'


def font(name, size):
    try:
        return ImageFont.truetype(FONTS + name, size)
    except OSError:
        return ImageFont.load_default()


def resized(image, size):
    return image.resize((size, size), Image.LANCZOS)


def make_og(icon):
    w, h = 1200, 630
    bg = Image.new('RGB', (w, h))
    top, bottom = (14, 58, 95), (21, 92, 148)
    px = bg.load()
    for y in range(h):
        t = y / (h - 1)
        row = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = row
    draw = ImageDraw.Draw(bg)
    size = 300
    ix, iy = 110, (h - size) // 2
    shadow = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((ix, iy + 14, ix + size, iy + size + 14), radius=66, fill=(0, 0, 0, 90))
    bg = Image.alpha_composite(bg.convert('RGBA'), shadow)
    bg.alpha_composite(resized(icon, size), (ix, iy))
    draw = ImageDraw.Draw(bg)
    tx = ix + size + 70
    draw.text((tx, 190), 'e-Layout', font=font('seguibl.ttf', 120), fill=(255, 255, 255))
    draw.text((tx, 330), 'Your office\u2019s layout', font=font('segoeui.ttf', 46), fill=(214, 232, 247))
    draw.text((tx, 388), 'on every photo.', font=font('segoeui.ttf', 46), fill=(214, 232, 247))
    draw.text((tx, 480), 'Bongabong Public Information Office', font=font('seguisb.ttf', 30), fill=(150, 195, 232))
    return bg.convert('RGB')


def main():
    for needed in [ICON, SEAL] + list(GOLDENS.values()):
        if not os.path.isfile(needed):
            print(f'missing: {needed}', file=sys.stderr)
            sys.exit(1)
    os.makedirs(os.path.join(LANDING, 'screens'), exist_ok=True)
    os.makedirs(DOWNLOAD, exist_ok=True)
    icon = Image.open(ICON).convert('RGBA')

    resized(icon, 256).save(os.path.join(LANDING, 'app-icon.png'), optimize=True)
    resized(icon, 256).save(os.path.join(DOWNLOAD, 'app-icon.png'), optimize=True)
    # iOS draws its own corners: a full-bleed square, flattened on the icon's own blue.
    flat = Image.new('RGB', icon.size, icon.convert('RGB').getpixel((icon.width // 2, 24)))
    flat.paste(icon, mask=icon.split()[3])
    flat.resize((180, 180), Image.LANCZOS).save(os.path.join(LANDING, 'apple-touch-icon.png'), optimize=True)
    icon.save(os.path.join(SITE, 'favicon.ico'), sizes=[(16, 16), (32, 32), (48, 48)])
    make_og(icon).save(os.path.join(LANDING, 'og.png'), optimize=True)
    shutil.copyfile(SEAL, os.path.join(LANDING, 'seal-96.png'))
    shutil.copyfile(SEAL, os.path.join(DOWNLOAD, 'seal-96.png'))

    for name, source in GOLDENS.items():
        shot = Image.open(source).convert('RGB')
        width = 390  # shown at up to 260 CSS px, so this is sharp at 1.5x
        shot = shot.resize((width, round(shot.height * width / shot.width)), Image.LANCZOS)
        shot.save(os.path.join(LANDING, 'screens', name), 'WEBP', quality=84, method=6)
    print('site pictures written under', os.path.relpath(SITE, PROJECT))


if __name__ == '__main__':
    main()
