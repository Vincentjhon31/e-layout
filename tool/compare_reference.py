import os, sys
from PIL import Image, ImageChops

here = os.path.dirname(os.path.abspath(__file__))
a = Image.open(os.path.join(here, 'web_reference.png')).convert('RGB')
b = Image.open(os.path.join(here, '..', 'test', 'core', 'render', 'goldens', 'pio_footer_landscape.png')).convert('RGB')
print('sizes', a.size, b.size)
d = ImageChops.difference(a, b)
n = a.size[0] * a.size[1]
for i, ch in enumerate('RGB'):
    s = sum(v * c for v, c in enumerate(d.getchannel(i).histogram()))
    print('mean abs diff', ch, round(s / n, 3))
big = d.convert('L').point(lambda v: 255 if v > 40 else 0)
print('pixels > 40:', sum(1 for v in big.getdata() if v), 'bbox', big.getbbox())

# horizontal / vertical shift search on the text region of the footer
box = (300, 700, 800, 785)
ca = a.crop(box)
best = None
for dy in range(-4, 5):
    for dx in range(-4, 5):
        cb = b.crop((box[0] + dx, box[1] + dy, box[2] + dx, box[3] + dy))
        dd = ImageChops.difference(ca, cb).convert('L')
        s = sum(v * c for v, c in enumerate(dd.histogram()))
        if best is None or s < best[0]:
            best = (s, dx, dy)
print('best offset of flutter relative to web (dx, dy):', best[1], best[2])
