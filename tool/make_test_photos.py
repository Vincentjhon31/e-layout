"""Makes small generated test photos under test/assets/ (no real photos).

exif_rotated_6.jpg: 120x80 pixels stored sideways with EXIF orientation 6
(rotate 90 degrees clockwise to show). Shown upright it is 80x120 with four
quadrants: top-left red, top-right green, bottom-left blue, bottom-right white.

Run from the project folder: python tool/make_test_photos.py
"""
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'test', 'assets')


def main():
    os.makedirs(OUT, exist_ok=True)
    shown = Image.new('RGB', (80, 120))
    px = shown.load()
    for y in range(120):
        for x in range(80):
            left, top = x < 40, y < 60
            if top and left:
                px[x, y] = (230, 20, 20)
            elif top:
                px[x, y] = (20, 200, 40)
            elif left:
                px[x, y] = (20, 40, 220)
            else:
                px[x, y] = (255, 255, 255)
    # Orientation 6 means "rotate 90 clockwise to show", so store it turned the other way.
    stored = shown.transpose(Image.Transpose.ROTATE_90)
    assert stored.size == (120, 80)
    exif = Image.Exif()
    exif[0x0112] = 6
    path = os.path.join(OUT, 'exif_rotated_6.jpg')
    stored.save(path, 'JPEG', quality=95, exif=exif.tobytes())
    print('wrote', os.path.normpath(path), stored.size)


if __name__ == '__main__':
    main()
