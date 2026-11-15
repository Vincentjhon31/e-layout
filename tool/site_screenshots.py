"""Screenshots of the landing and download pages with headless Chrome (or Edge),
one page at a time, into build/site_screens/ (gitignored).

    python tool/site_screenshots.py                 serve a temporary copy and shoot every page
    python tool/site_screenshots.py --only landing  only shots whose name contains this text

It copies hostinger/public_html into a temporary folder, adds
hostinger/tests/fixtures/latest.json and releases.json (made-up versions)
under download/, serves it with PHP's built-in server on 127.0.0.1:8770, and
always stops the server and the browser, even when something fails.
Phone shots are 390 wide at device scale 2 (also cut into parts of at most
1500 pixels so each can be looked at), desktop shots 1280 wide at scale 1.
"""
import argparse
import glob
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
SITE = os.path.join(PROJECT, 'hostinger', 'public_html')
FIXTURES = os.path.join(PROJECT, 'hostinger', 'tests', 'fixtures')
OUT = os.path.join(PROJECT, 'build', 'site_screens')
PORT = 8770
TALL = 7000  # window height, trimmed afterwards

# (file name, path, with the made-up version lists?)
PAGES = [
    ('landing-light', '/?theme=light', True),
    ('landing-dark', '/?theme=dark', True),
    ('download-light', '/download/?theme=light', True),
    ('download-dark', '/download/?theme=dark', True),
    ('download-empty-light', '/download/?theme=light', False),
    ('download-empty-dark', '/download/?theme=dark', False),
]
# Phone shots pretend to be an Android phone, so its button comes first; one more
# shows what an iPhone or a Mac sees (the browser button first).
EXTRA = [('landing-light-iphone', '/?theme=light&as=other', True)]


def find_browser():
    candidates = []
    for base in (os.environ.get('ProgramFiles'), os.environ.get('ProgramFiles(x86)'), os.environ.get('LOCALAPPDATA')):
        if base:
            candidates += [os.path.join(base, 'Google', 'Chrome', 'Application', 'chrome.exe'),
                           os.path.join(base, 'Microsoft', 'Edge', 'Application', 'msedge.exe')]
    for path in candidates:
        if os.path.isfile(path):
            return path
    return shutil.which('chrome') or shutil.which('msedge')


def kill_tree(proc):
    if proc.poll() is None:
        subprocess.run(['taskkill', '/F', '/T', '/PID', str(proc.pid)], capture_output=True)


def trim_and_slice(path, scale, slice_height=1500, pad=0):
    image = Image.open(path).convert('RGB')
    background = image.getpixel((image.width - 1, image.height - 1))
    px = image.load()
    bottom = image.height - 1
    while bottom > 0 and all(px[x, bottom] == background for x in range(0, image.width, 7)):
        bottom -= 1
    image = image.crop((0, 0, image.width, min(image.height, bottom + 1 + pad * scale)))
    image.save(path, optimize=True)
    parts = []
    stem = path[:-4]
    for i, top in enumerate(range(0, image.height, slice_height), 1):
        piece = image.crop((0, top, image.width, min(image.height, top + slice_height)))
        part = f'{stem}-part{i}.png'
        piece.save(part, optimize=True)
        parts.append(part)
    return image.size, parts


def shoot(browser, url, file, width, scale, profile, harness):
    # Chrome's headless window is never narrower than about 500 pixels, so a phone-width page is
    # shown inside an iframe of exactly that width (its media queries follow the iframe) and the
    # screenshot is cropped to it afterwards.
    window = max(width, 600)
    height = TALL if width < 700 else 4200
    target = url
    if width < window:
        folder, base, path = harness
        with open(os.path.join(folder, '__frame.html'), 'w', encoding='utf-8') as f:
            f.write(f'<!doctype html><body style="margin:0;background:#888"><iframe src="{path}" width="{width}" '
                    f'height="{height}" style="border:0;display:block"></iframe>')
        target = base + '/__frame.html'
    cmd = [browser, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run',
           '--disable-extensions', '--disable-background-networking', f'--user-data-dir={profile}',
           f'--force-device-scale-factor={scale}', f'--window-size={window},{height}',
           '--virtual-time-budget=8000', f'--screenshot={file}', target]
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        proc.wait(timeout=90)
    except subprocess.TimeoutExpired:
        print('  browser timed out', file=sys.stderr)
    finally:
        kill_tree(proc)
    if os.path.isfile(file) and width < window:
        image = Image.open(file).convert('RGB')
        image.crop((0, 0, width * scale, image.height)).save(file)
    return os.path.isfile(file)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--only', default='')
    args = parser.parse_args()
    browser = find_browser()
    if not browser:
        print('No Chrome or Edge found.', file=sys.stderr)
        sys.exit(1)
    os.makedirs(OUT, exist_ok=True)
    for old in glob.glob(os.path.join(OUT, '*.png')):
        if args.only in os.path.basename(old):
            os.remove(old)

    work = tempfile.mkdtemp(prefix='elayout-shots-')
    profile = os.path.join(work, 'profile')
    servers = []  # (name, folder)
    folders = {}
    try:
        sites = {}
        if True:
            for name, with_lists in (('full', True), ('empty', False)):
                folder = os.path.join(work, name)
                shutil.copytree(SITE, folder)
                if with_lists:
                    for fixture in ('latest.json', 'releases.json'):
                        shutil.copyfile(os.path.join(FIXTURES, fixture), os.path.join(folder, 'download', fixture))
                servers.append((name, folder))
                folders[name] = folder
            ports = {'full': PORT, 'empty': PORT + 1}
            procs = []
            for name, folder in servers:
                procs.append(subprocess.Popen(['php', '-S', f'127.0.0.1:{ports[name]}', '-t', folder],
                                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
                sites[name] = f'http://127.0.0.1:{ports[name]}'
            servers = procs
            time.sleep(1.5)
            urllib.request.urlopen(sites['full'] + '/', timeout=10).read()

        for name, path, with_lists in PAGES + EXTRA:
            if args.only not in name:
                continue
            base = sites['full' if with_lists else 'empty']
            for label, width, scale, add in (('phone', 390, 2, '&as=android'), ('desktop', 1280, 1, '')):
                if name == 'landing-light-iphone' and label == 'desktop':
                    continue
                path_with_query = path + (add if '?' in path else add.replace('&', '?', 1))
                url = base + path_with_query
                file = os.path.join(OUT, f'{name}-{label}.png')
                print(f'{name} {label} ...', flush=True)
                if not shoot(browser, url, file, width, scale, profile, (folders['full' if with_lists else 'empty'], base, path_with_query)):
                    print('  no screenshot made', file=sys.stderr)
                    continue
                size, parts = trim_and_slice(file, scale, pad=0 if name.startswith('landing') else 20)
                print(f'  {size[0]}x{size[1]}, {len(parts)} part(s)')
    finally:
        for proc in servers:
            if hasattr(proc, 'terminate'):
                kill_tree(proc)
        time.sleep(0.5)
        shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    main()
