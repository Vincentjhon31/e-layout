"""Makes the folder to upload to pio.bongabong.gov.ph.

    python tool/site_bundle.py --app-dir build/web --out build/site_bundle

Writes <out>/pio/ (everything from hostinger/public_html/, private/ from
hostinger/private/ with the example config only, and app/ from --app-dir;
never tests/), <out>/MANIFEST.txt (path, bytes, SHA-256 per file, tab
separated) and <out>/e-layout-site-<yyyy-mm-dd>.zip for hPanel's
upload-and-extract. Nothing is uploaded by this script.
"""
import argparse
import datetime
import hashlib
import os
import shutil
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
SRC = os.path.join(PROJECT, 'hostinger')
SKIP_NAMES = {'.DS_Store', 'Thumbs.db'}
SKIP_SUFFIXES = ('.pyc',)


def copy_tree(src, dest, only=None):
    for base, dirs, names in os.walk(src):
        dirs[:] = [d for d in dirs if d != '__pycache__']
        for name in names:
            if name in SKIP_NAMES or name.endswith(SKIP_SUFFIXES):
                continue
            if only is not None and name not in only:
                continue
            target = os.path.join(dest, os.path.relpath(os.path.join(base, name), src))
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copyfile(os.path.join(base, name), target)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app-dir', required=True, help='the Flutter web build (built with --base-href /app/)')
    parser.add_argument('--out', default=os.path.join(PROJECT, 'build', 'site_bundle'))
    args = parser.parse_args()
    if not os.path.isfile(os.path.join(args.app_dir, 'index.html')):
        print(f'{args.app_dir} has no index.html: build the website version first '
              '(flutter build web --release --base-href /app/)', file=sys.stderr)
        sys.exit(1)

    out = os.path.abspath(args.out)
    if os.path.isdir(out):
        shutil.rmtree(out)
    pio = os.path.join(out, 'pio')
    copy_tree(os.path.join(SRC, 'public_html'), pio)
    # private/: the example config and the files that protect the folder, never a real config.
    copy_tree(os.path.join(SRC, 'private'), os.path.join(pio, 'private'),
              only={'.htaccess', 'index.php', 'api-config.example.php'})
    copy_tree(args.app_dir, os.path.join(pio, 'app'))

    files = []
    for base, _, names in os.walk(pio):
        for name in names:
            files.append(os.path.relpath(os.path.join(base, name), pio).replace(os.sep, '/'))
    files.sort()

    lines = ['# e-Layout site bundle. path<TAB>bytes<TAB>sha256']
    for rel in files:
        with open(os.path.join(pio, *rel.split('/')), 'rb') as f:
            data = f.read()
        lines.append(f'{rel}\t{len(data)}\t{hashlib.sha256(data).hexdigest()}')
    with open(os.path.join(out, 'MANIFEST.txt'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')

    zip_path = os.path.join(out, f'e-layout-site-{datetime.date.today().isoformat()}.zip')
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as z:
        for rel in files:
            z.write(os.path.join(pio, *rel.split('/')), rel)
    print(f'{len(files)} files in {pio}')
    print(f'manifest: {os.path.join(out, "MANIFEST.txt")}')
    print(f'zip: {zip_path}')


if __name__ == '__main__':
    main()
