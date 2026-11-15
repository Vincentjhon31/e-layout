import re, glob, os
fam = {'barlow': 'Barlow', 'barlow-condensed': 'Barlow Condensed', 'montserrat': 'Montserrat', 'poppins': 'Poppins',
       'open-sans': 'Open Sans', 'fira-sans-condensed': 'Fira Sans Condensed', 'nunito': 'Nunito', 'oswald': 'Oswald',
       'anton': 'Anton', 'bebas-neue': 'Bebas Neue', 'playfair-display': 'Playfair Display',
       'libre-baskerville': 'Libre Baskerville', 'cinzel': 'Cinzel', 'dancing-script': 'Dancing Script',
       'great-vibes': 'Great Vibes', 'pacifico': 'Pacifico'}
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
groups = {}
for p in sorted(glob.glob('assets/fonts/*.ttf')):
    s = os.path.basename(p)[:-4]
    m = re.match(r'(.+)-(\d+)$', s)
    groups.setdefault(m.group(1), []).append((int(m.group(2)), p.replace(chr(92), '/')))
assert set(groups) == set(fam)
out = "flutter:\n  assets:\n    - assets/layouts/\n    - assets/img/\n    - assets/fonts/licenses/\n  fonts:\n"
for k, v in groups.items():
    out += "    - family: %s\n      fonts:\n" % fam[k]
    for w, p in sorted(v):
        out += "        - asset: %s\n          weight: %d\n" % (p, w)
t = open('pubspec.yaml').read()
i = t.index('\nflutter:')
open('pubspec.yaml', 'w').write(t[:i] + '\n' + out)
