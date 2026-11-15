"""Copies what the landing page's live demo needs from the old browser tool
(the parent folder of this project) into hostinger/public_html/landing/demo/.
The copies are never edited by hand.

    python tool/site_copy_demo.py           copy (replaces the folder's files)
    python tool/site_copy_demo.py --check   exit 1 when the copies differ from the sources
"""
import argparse
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
OLD = os.path.dirname(PROJECT)  # the old browser tool: index.html, js/, css/, fonts/, layouts/
DEST = os.path.join(PROJECT, 'hostinger', 'public_html', 'landing', 'demo')

SCRIPTS = [('js/model.js', 'model.js'), ('js/render.js', 'render.js'), ('js/fonts.js', 'fonts.js'),
           ('js/icons.js', 'icons.js'), ('layouts/layouts.js', 'layouts.js')]


def wanted():
    """{relative path inside demo/: bytes} for everything the demo holds."""
    out = {}
    for src, name in SCRIPTS:
        with open(os.path.join(OLD, *src.split('/')), 'rb') as f:
            out[name] = f.read()
    with open(os.path.join(OLD, 'css', 'fonts.css'), 'rb') as f:
        css = f.read().replace(b'url("../fonts/', b'url("fonts/')
    out['fonts.css'] = css
    fonts = os.path.join(OLD, 'fonts')
    for base, _, names in os.walk(fonts):
        for name in names:
            if name.endswith('.woff2') or os.path.basename(base) == 'licenses':
                rel = os.path.relpath(os.path.join(base, name), fonts).replace(os.sep, '/')
                with open(os.path.join(base, name), 'rb') as f:
                    out['fonts/' + rel] = f.read()
    return out


def existing():
    out = {}
    for base, _, names in os.walk(DEST):
        for name in names:
            rel = os.path.relpath(os.path.join(base, name), DEST).replace(os.sep, '/')
            with open(os.path.join(base, name), 'rb') as f:
                out[rel] = f.read()
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    want = wanted()
    if args.check:
        have = existing()
        problems = [f'missing: {p}' for p in want if p not in have]
        problems += [f'extra: {p}' for p in have if p not in want]
        problems += [f'differs: {p}' for p in want if p in have and have[p] != want[p]]
        if problems:
            print('landing/demo is out of date; run: python tool/site_copy_demo.py')
            print('\n'.join(problems[:20]))
            sys.exit(1)
        print(f'landing/demo matches its sources ({len(want)} files)')
        return
    if os.path.isdir(DEST):
        shutil.rmtree(DEST)
    for rel, data in want.items():
        path = os.path.join(DEST, *rel.split('/'))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'wb') as f:
            f.write(data)
    print(f'copied {len(want)} files into {os.path.relpath(DEST, PROJECT)}')


if __name__ == '__main__':
    main()
