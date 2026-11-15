import glob, os, shutil
from fontTools.ttLib import TTFont
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.abspath(os.path.join(here, '..'))
src = os.path.abspath(os.path.join(root, '..', 'fonts'))
dst = os.path.join(root, 'assets', 'fonts')
os.makedirs(os.path.join(dst, 'licenses'), exist_ok=True)
for p in sorted(glob.glob(os.path.join(src, '*.woff2'))):
    f = TTFont(p)
    f.flavor = None
    f.save(os.path.join(dst, os.path.splitext(os.path.basename(p))[0] + '.ttf'))
for p in glob.glob(os.path.join(src, 'licenses', '*.txt')):
    shutil.copy(p, os.path.join(dst, 'licenses'))
print('done')
