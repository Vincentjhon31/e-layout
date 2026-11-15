"""End-to-end tests for the e-Layout site (pio.bongabong.gov.ph), run locally:

    python hostinger/tests/run_tests.py

Copies the site into a temporary folder laid out like the subdomain's own
folder on Hostinger (pio/ with api/, download/ and private/ inside it), starts
PHP's built-in web server, and exercises the release API, the download counter,
the health check and the two static pages. Needs PHP 8 (gd, curl, fileinfo) on
PATH. Does not touch Hostinger, GitHub or anything outside a temporary folder.

Note: PHP's built-in server ignores .htaccess files, so those rules (no
directory listings, private/ closed, no scripts in download/) are only active
on Hostinger. That is why the health check reports private/ as readable here.
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from html.parser import HTMLParser

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(HERE)
ROOT = os.path.dirname(SRC)
PHP_PORT = 8799
# A second copy of the site server, so the health check can try to read
# private/ over HTTP (PHP's built-in server handles one request at a time, so
# it cannot call itself).
PROBE_PORT = 8800
API = f'http://127.0.0.1:{PHP_PORT}/api'
PHP_OPTIONS = ['-d', 'post_max_size=13M', '-d', 'upload_max_filesize=12M', '-d', 'memory_limit=256M']
MB = 1024 * 1024

failures = []
total = [0]


def check(name, condition, detail=''):
    total[0] += 1
    print(('PASS ' if condition else 'FAIL ') + name + ('' if condition else f'  -> {detail}'))
    if not condition:
        failures.append(name)


def raw(method, url, data=b'', headers=None):
    req = urllib.request.Request(url, data=data if method != 'GET' else None, method=method, headers=dict(headers or {}))
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            return res.status, res.read(), dict(res.headers)
    except urllib.error.HTTPError as e:
        return e.code, e.read(), dict(e.headers)


def jbody(body):
    try:
        return json.loads(body)
    except Exception:
        return {'raw': body[:200]}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


no_redirect = urllib.request.build_opener(NoRedirect)


def location(url):
    try:
        no_redirect.open(url, timeout=10)
        return None
    except urllib.error.HTTPError as e:
        return e.code, e.headers.get('Location', ''), e.headers.get('Cache-Control', '')


# ---------- static page checks ----------

# Places that live on the server but not in this tree.
SERVER_SIDE = ('/app/', '/app.html', '/css/', '/js/', '/fonts/', '/img/', '/layouts/', '/api/',
               '/download/latest.json', '/download/releases.json', '/download/files/', '/private/')
OWN_SITE = 'https://pio.bongabong.gov.ph'


class PageScan(HTMLParser):
    def __init__(self):
        super().__init__()
        self.lang = None
        self.viewport = False
        self.csp = None
        self.inline_scripts = 0
        self.external = []
        self.local = []
        self.images_without_alt = []
        self.inline_style_attrs = 0
        self.in_script = False
        self.script_src = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == 'html':
            self.lang = a.get('lang')
        if tag == 'meta' and a.get('name') == 'viewport':
            self.viewport = True
        if tag == 'meta' and (a.get('http-equiv') or '').lower() == 'content-security-policy':
            self.csp = a.get('content')
        if tag == 'script':
            self.in_script = True
            self.script_src = 'src' in a
            if 'src' not in a:
                self.inline_scripts += 1
        if tag == 'img' and 'alt' not in a:
            self.images_without_alt.append(a.get('src'))
        if 'style' in a:
            self.inline_style_attrs += 1
        for key in ('href', 'src', 'action', 'poster'):
            value = a.get(key)
            if value is None:
                continue
            if re.match(r'^(https?:)?//', value):
                if not value.startswith(OWN_SITE + '/') and value != OWN_SITE:
                    self.external.append(value)
                elif key != 'href' or tag == 'link':
                    self.local.append(value[len(OWN_SITE):])
            elif not re.match(r'^(#|mailto:|tel:|data:|javascript:)', value):
                self.local.append(value)
        if tag == 'meta' and a.get('content', '').startswith(('http://', '//')):
            self.external.append(a['content'])

    def handle_endtag(self, tag):
        if tag == 'script':
            self.in_script = False


def scan_page(path):
    with open(path, encoding='utf-8') as f:
        text = f.read()
    scan = PageScan()
    scan.feed(text)
    return scan, text


def page_checks(site, label, rel_path):
    path = os.path.join(site, *rel_path.split('/'))
    if not os.path.isfile(path):
        check(f'{label} exists', False, path)
        return
    scan, text = scan_page(path)
    check(f'{label}: lang="en"', scan.lang == 'en', scan.lang)
    check(f'{label}: has a viewport meta', scan.viewport)
    check(f'{label}: has a Content-Security-Policy meta',
          bool(scan.csp) and "default-src 'self'" in scan.csp and "script-src 'self'" in scan.csp, scan.csp)
    check(f'{label}: no inline script', scan.inline_scripts == 0, scan.inline_scripts)
    check(f'{label}: no style attribute (CSP would ignore it)', scan.inline_style_attrs == 0, scan.inline_style_attrs)
    check(f'{label}: nothing from another site and no http:// address', not scan.external and 'http://' not in text, scan.external)
    check(f'{label}: every image has alt text', not scan.images_without_alt, scan.images_without_alt)
    base = os.path.dirname(path)
    missing = []
    for ref in scan.local:
        ref = re.split(r'[?#]', ref)[0]
        if ref == '':
            continue
        if ref.startswith('/'):
            if ref == '/' or any(ref == s or ref.startswith(s) for s in SERVER_SIDE):
                continue
            target = os.path.join(site, *ref.lstrip('/').split('/'))
        else:
            if any(('/' + os.path.relpath(os.path.join(base, ref), site).replace(os.sep, '/')).startswith(s) for s in SERVER_SIDE):
                continue
            target = os.path.normpath(os.path.join(base, ref))
        if ref.endswith('/'):
            target = os.path.join(target, 'index.html')
        if not os.path.exists(target):
            missing.append(ref)
    check(f'{label}: every local link and file exists', not missing, missing)
    return text


def main():
    root = tempfile.mkdtemp(prefix='elayout-site-test-')
    site = os.path.join(root, 'pio')
    shutil.copytree(os.path.join(SRC, 'public_html'), site)
    shutil.copytree(os.path.join(SRC, 'private'), os.path.join(site, 'private'))
    with open(os.path.join(SRC, 'private', 'api-config.example.php'), encoding='utf-8') as f:
        config = f.read()
    config = config.replace('https://pio.bongabong.gov.ph/api', API)
    config = config.replace('https://pio.bongabong.gov.ph/private', f'http://127.0.0.1:{PROBE_PORT}/private')
    config = config.replace("['https://pio.bongabong.gov.ph']", "['https://pio.bongabong.gov.ph', 'http://127.0.0.1:8799']")
    with open(os.path.join(site, 'private', 'api-config.php'), 'w', encoding='utf-8') as f:
        f.write(config)
    download = os.path.join(site, 'download')
    files_dir = os.path.join(download, 'files')

    servers = []
    try:
        for port in (PHP_PORT, PROBE_PORT):
            servers.append(subprocess.Popen(['php', '-S', f'127.0.0.1:{port}', '-t', site] + PHP_OPTIONS,
                                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        time.sleep(1.5)
        run_api_checks(site, download, files_dir)
        run_page_checks(site)
    finally:
        for server in servers:
            server.terminate()
        for server in servers:
            try:
                server.wait(timeout=10)
            except Exception:
                server.kill()
        shutil.rmtree(root, ignore_errors=True)

    if failures:
        print(f'FAILED: {len(failures)} of {total[0]}')
        for name in failures:
            print('  - ' + name)
        sys.exit(1)
    print(f'ALL PASSED ({total[0]} checks)')


def run_api_checks(site, download, files_dir):
    rel = API + '/releases.php'

    # ---------- the pages the server answers before anything is set up ----------
    s, b, h = raw('GET', API + '/')
    health = jbody(b)
    check('health check says it is the e-Layout site API', s == 200 and health.get('service') == 'e-Layout site API', b)
    check('health check reports release uploads off before the secret exists', health.get('release_uploads') is False, b)
    check('health check reports the download folder writable', health.get('download_writable') is True, b)
    # PHP's test server ignores .htaccess, so private/ IS readable here: the
    # health check must notice and say so (on Hostinger it says true).
    check('health check detects an unprotected private folder',
          health.get('private_protected') is False and health.get('ok') is False and 'warning' in health, b)
    check('health check does not show the exact PHP version',
          'php' not in health or health.get('php') in (True, False), b)
    check('health check says whether PHP is 8.1 or newer', health.get('php_8_1_or_newer') is True, b)
    check('health check tells how big uploads may be', 'max_upload' in health and 'max_post' in health, b)
    s, b, h = raw('GET', f'http://127.0.0.1:{PHP_PORT}/private/index.php')
    check('private/index.php answers 403', s == 403, s)

    s, b, _ = raw('POST', rel + '?action=publish', b'{}', {'X-Release-Secret': 'x' * 40})
    check('release uploads are off until the secret file exists', s == 503 and 'not set up' in jbody(b).get('error', ''), (s, b))
    secret = 'release-test-secret-' + uuid.uuid4().hex
    php_secret = os.path.join(site, 'private', 'release-upload-secret.php')
    txt_secret = os.path.join(site, 'private', 'release-upload-secret.txt')
    htaccess = os.path.join(site, 'private', '.htaccess')

    def write_php_secret(value):
        with open(php_secret, 'w') as f:
            f.write("<?php return '" + value + "';" + chr(10))

    write_php_secret(secret)
    auth = {'X-Release-Secret': secret}
    started = time.time()
    s, b, _ = raw('POST', rel + '?action=publish', b'{}', {'X-Release-Secret': 'wrong' * 10})
    check('a wrong release secret is refused at once (no sleep that ties up a PHP worker)', s == 403 and time.time() - started < 0.4, (s, b))
    s, b, _ = raw('POST', rel + '?action=publish', b'{}')
    check('a missing release secret is refused', s == 403, (s, b))
    s, b, _ = raw('GET', rel)
    check('releases.php only takes POST', s == 404 and jbody(b) == {'error': 'Not found.'}, (s, b))
    write_php_secret('short')
    s, b, _ = raw('POST', rel + '?action=publish', b'{}', {'X-Release-Secret': 'short'})
    check('a secret shorter than 32 characters switches uploads off', s == 503, (s, b))
    write_php_secret(secret)
    s, b, _ = raw('GET', API + '/')
    check('health check reports release uploads on once the secret exists', jbody(b).get('release_uploads') is True, b)
    s, b, _ = raw('GET', f'http://127.0.0.1:{PHP_PORT}/private/release-upload-secret.php')
    check('requesting the secret .php file shows no secret', secret not in b.decode('utf-8', 'replace'), (s, b))

    # The old plain-text file still works as a fallback.
    os.remove(php_secret)
    with open(txt_secret, 'w') as f:
        f.write(secret + chr(10))
    s, b, _ = raw('POST', rel + '?action=publish', b'{}', auth)
    check('the old .txt secret is still read as a fallback', s != 503 and s != 403, (s, b))
    os.remove(txt_secret)
    write_php_secret(secret)

    # Without private/.htaccess the secret could be read from the web: uploads must be off.
    saved = open(htaccess, 'rb').read()
    os.remove(htaccess)
    s, b, _ = raw('POST', rel + '?action=publish', b'{}', auth)
    check('uploads are off (503) when private/.htaccess is missing, even with the right secret',
          s == 503 and 'uploads are off' in jbody(b).get('error', ''), (s, b))
    s, b, _ = raw('GET', API + '/')
    check('health check reports uploads off when private/.htaccess is missing', jbody(b).get('release_uploads') is False, b)
    with open(htaccess, 'wb') as f:
        f.write(saved)
    s, b, _ = raw('POST', rel + '?action=publish', b'{}', auth)
    check('uploads work again once private/.htaccess is back', s not in (503, 403), (s, b))

    # ---------- chunked upload ----------
    def upload(name, data, chunk=8 * MB, start=0):
        s, b = 200, b''
        for offset in range(start, len(data), chunk):
            s, b, _ = raw('POST', f'{rel}?action=chunk&name={name}&offset={offset}&total={len(data)}',
                          data[offset:offset + chunk], dict(auth, **{'Content-Type': 'application/octet-stream'}))
            if s != 200:
                return s, b
        return s, b

    big = os.urandom(20 * MB)
    s, b = upload('e-layout-1.0.0.apk', big)
    arrived = os.path.join(files_dir, 'e-layout-1.0.0.apk')
    same = os.path.isfile(arrived) and hashlib.sha256(open(arrived, 'rb').read()).digest() == hashlib.sha256(big).digest()
    check('a 20 MB file sent in 8 MB pieces arrives complete and identical',
          s == 200 and jbody(b).get('complete') is True and same, (s, b))
    check('no .part file is left after a complete upload', not os.path.exists(arrived + '.part'))

    for bad in ['evil.php', '..%2Fapi%2Fx.apk', '../x.apk', 'e-layout-1.0.apk', 'e-calendar-1.0.0.apk', 'e-layout-1.0.0.php',
                'e-layout-1.0.0.apk.php', 'e-layout-1.0.0.apk%0A', 'e-layout-1.0.0.apk%00.php', 'E-Layout-1.0.0.apk',
                'e-layout-1000.0.0.apk', 'e-layout-1.0.0-setup.apk']:
        s, b, _ = raw('POST', f'{rel}?action=chunk&name={bad}&offset=0&total=5', b'12345', auth)
        check(f'only release file names are accepted ({bad})', s == 400 and 'release file name' in jbody(b).get('error', ''), (s, b))
    leftovers = sorted(os.listdir(files_dir))
    check('rejected names leave nothing behind', leftovers == ['e-layout-1.0.0.apk'], leftovers)

    s, b, _ = raw('POST', f'{rel}?action=chunk&name=e-layout-1.0.0-setup.exe&offset=0&total=20', b'0123456789', auth)
    check('a first piece is accepted', s == 200 and jbody(b) == {'received': 10, 'complete': False}, (s, b))
    s, b, _ = raw('POST', f'{rel}?action=chunk&name=e-layout-1.0.0-setup.exe&offset=5&total=20', b'0123456789', auth)
    check('a piece out of order is refused and says where to resume', s == 409 and jbody(b).get('received') == 10, (s, b))
    s, b, _ = raw('POST', f'{rel}?action=chunk&name=e-layout-1.0.0-setup.exe&offset=0&total=20', b'abcdefghij', auth)
    check('offset 0 starts over', s == 200 and jbody(b).get('received') == 10
          and open(os.path.join(files_dir, 'e-layout-1.0.0-setup.exe.part'), 'rb').read() == b'abcdefghij', (s, b))
    s, b, _ = raw('POST', f'{rel}?action=chunk&name=e-layout-1.0.0-setup.exe&offset=10&total=15', b'0123456789', auth)
    check('a piece past the stated size is refused and the unfinished file is deleted',
          s == 400 and not os.path.exists(os.path.join(files_dir, 'e-layout-1.0.0-setup.exe.part')), (s, b))
    s, b, _ = raw('POST', f'{rel}?action=chunk&name=e-layout-1.0.0-setup.exe&offset=0&total=20', b'0123456789', auth)
    s, b, _ = raw('POST', f'{rel}?action=chunk&name=e-layout-1.0.0-setup.exe&offset=10&total=20', b'0123456789', auth)
    check('the second piece completes the file', s == 200 and jbody(b).get('complete') is True
          and open(os.path.join(files_dir, 'e-layout-1.0.0-setup.exe'), 'rb').read() == b'01234567890123456789', (s, b))
    s, b, _ = raw('POST', f'{rel}?action=chunk&name=e-layout-1.0.1.apk&offset=0&total={9 * MB + 1}', os.urandom(9 * MB), dict(auth, **{'Content-Type': 'application/octet-stream'}))
    check('a piece over 8 MB is refused', s == 400 and 'between 1 byte and 8 MB' in jbody(b).get('error', ''), (s, b))
    s, b, _ = raw('POST', f'{rel}?action=chunk&name=e-layout-1.0.1.apk&offset=0&total=5', b'', auth)
    check('an empty piece is refused', s == 400, (s, b))
    s, b, _ = raw('POST', f'{rel}?action=chunk&name=e-layout-1.0.1.apk&offset=x&total=5', b'12345', auth)
    check('a bad offset is refused', s == 400 and 'offset' in jbody(b).get('error', ''), (s, b))
    s, b, _ = raw('POST', f'{rel}?action=chunk&name=e-layout-1.0.1.apk&offset=0&total=0', b'12345', auth)
    check('a bad total is refused', s == 400, (s, b))
    s, b, _ = raw('POST', f'{rel}?action=chunk&name=e-layout-1.0.1.apk&offset=0&total={401 * MB}', b'12345', auth)
    check('a file over 400 MB is refused', s == 400, (s, b))
    s, b, _ = raw('POST', rel + '?action=nothing', b'', auth)
    check('an unknown action is refused', s == 400, (s, b))

    # ---------- publishing ----------
    def publish(version, build, platform, data, changelog=None, date='2026-11-15', override=None):
        name = f'e-layout-{version}' + ('.apk' if platform == 'android' else '-setup.exe')
        body = {'version': version, 'build': build, 'date': date, 'platform': platform, 'file': name,
                'size': len(data), 'sha256': hashlib.sha256(data).hexdigest(), 'changelog': changelog or {}}
        body.update(override or {})
        return raw('POST', rel + '?action=publish', json.dumps(body).encode(), dict(auth, **{'Content-Type': 'application/json'}))

    def read_json(name):
        with open(os.path.join(download, name), encoding='utf-8') as f:
            return json.load(f)

    s, b, _ = publish('1.0.0', 1, 'android', b'not the uploaded bytes')
    check('publishing checks the file against its size and checksum', s == 409 and 'does not match' in jbody(b).get('error', ''), (s, b))
    s, b, _ = raw('POST', rel + '?action=publish', b'not json', auth)
    check('publishing needs a JSON body', s == 400, (s, b))
    for label, change in [('a bad version', {'version': '1.0'}), ('a negative build', {'build': -1}), ('a bad date', {'date': '15/11/2026'}),
                          ('an unknown platform', {'platform': 'ios'}), ('a short checksum', {'sha256': 'abc'}), ('a zero size', {'size': 0})]:
        s, b, _ = publish('1.0.0', 1, 'android', big, override=change)
        check(f'publishing refuses {label}', s == 400 and 'invalid release details' in jbody(b).get('error', ''), (s, b))
    s, b, _ = publish('1.0.0', 1, 'windows', big, override={'file': 'e-layout-1.0.0.apk'})
    check('publishing refuses a file name that does not match the platform', s == 400 and 'does not match the version' in jbody(b).get('error', ''), (s, b))
    s, b, _ = publish('1.0.1', 1, 'android', big, override={'file': 'e-layout-1.0.0.apk'})
    check('publishing refuses a file name that does not match the version', s == 400, (s, b))
    s, b, _ = publish('1.0.0', 1, 'android', big, override={'file': '../private/api-config.php'})
    check('publishing refuses a path as the file name', s == 400, (s, b))
    check('nothing is published by the refused attempts', not os.path.exists(os.path.join(download, 'latest.json')))

    changelog = {'1.0.0': ['Put a layout on every photo', '<b>bold</b>\x07', 'x' * 600, '   '], '0.9.0': ['Early preview']}
    s, b, _ = publish('1.0.0', 1, 'android', big, changelog)
    latest = read_json('latest.json') if s == 200 else {}
    android = latest.get('android') or {}
    expected_keys = ['version', 'build', 'date', 'whats_new', 'download', 'name', 'size', 'sha256', 'url']
    check('publishing Android writes latest.json with the shape the apps read',
          s == 200 and list(android.keys()) == expected_keys and android['version'] == '1.0.0' and android['build'] == 1
          and android['date'] == '2026-11-15' and android['name'] == 'e-layout-1.0.0.apk' and android['size'] == len(big)
          and android['sha256'] == hashlib.sha256(big).hexdigest()
          and android['url'].endswith('/download/files/e-layout-1.0.0.apk')
          and android['download'] == API + '/download.php?file=e-layout-1.0.0.apk'
          and latest.get('windows') is None and latest.get('page', '').endswith('/download/')
          and 'updated_at' in latest, (s, b, latest))
    check('the answer carries the platform entry', jbody(b).get('ok') is True and jbody(b).get('latest') == android, b)
    releases = read_json('releases.json')['releases'] if s == 200 else []
    check("the version list keeps every version's notes, newest first, with files as an object",
          [r['version'] for r in releases] == ['1.0.0', '0.9.0'] and releases[1]['files'] == {}
          and set(releases[0]['files']) == {'android'}, releases)
    with open(os.path.join(download, 'releases.json'), encoding='utf-8') as f:
        text = f.read()
    check('a version without files is {} in the JSON, never []', re.search(r'"files":\s*\{\s*\}', text) is not None and '"files": []' not in text, text[:300])
    notes = releases[0]['whats_new'] if releases else []
    check('notes are cleaned: control characters gone, cut to 500, empty ones dropped',
          notes[:2] == ['Put a layout on every photo', '<b>bold</b>'] and len(notes) == 3 and len(notes[2]) == 500, notes and [len(n) for n in notes])
    check('no temporary or lock files break the folder', not [n for n in os.listdir(download) if n.endswith('.tmp')], os.listdir(download))

    exe = b'0123456789' * 2
    s, b, _ = publish('1.0.0', 1, 'windows', exe)
    latest = read_json('latest.json')
    check('publishing Windows adds it to the same version and keeps Android',
          s == 200 and latest['windows']['version'] == '1.0.0' and latest['android']['version'] == '1.0.0'
          and latest['windows']['name'] == 'e-layout-1.0.0-setup.exe'
          and set(read_json('releases.json')['releases'][0]['files']) == {'android', 'windows'}, (s, b))

    for i, version in enumerate(['1.0.1', '1.1.0', '1.2.0']):
        data = os.urandom(12)
        upload(f'e-layout-{version}.apk', data)
        s, b, _ = publish(version, 2 + i, 'android', data, {version: [f'Notes for {version}']})
    releases = read_json('releases.json')['releases']
    old = [r for r in releases if r['version'] == '1.0.0'][0]
    check('only the newest 3 versions keep their files; older notes stay',
          read_json('latest.json')['android']['version'] == '1.2.0'
          and not os.path.isfile(os.path.join(files_dir, 'e-layout-1.0.0.apk'))
          and 'android' not in old['files'] and 'windows' in old['files'] and old['whats_new'], releases)
    check('the version list is sorted newest first',
          [r['version'] for r in releases] == ['1.2.0', '1.1.0', '1.0.1', '1.0.0', '0.9.0'], [r['version'] for r in releases])
    check('a later version without a Windows file leaves Windows on its newest one',
          read_json('latest.json')['windows']['version'] == '1.0.0')

    # ---------- the counter ----------
    got = location(API + '/download.php?file=e-layout-1.2.0.apk')
    location(API + '/download.php?file=e-layout-1.0.0-setup.exe')
    check('a download is counted and sent to the file',
          got and got[0] == 302 and got[1].endswith('/download/files/e-layout-1.2.0.apk') and 'no-store' in got[2], got)
    got = location(API + '/download.php?file=e-layout-1.0.0.apk')
    check('a download that no longer exists goes to the page', got and got[0] == 302 and got[1].endswith('/download/'), got)
    got = location(API + '/download.php?file=../private/api-config.php')
    check('the counter only sends release files', got and got[1].endswith('/download/'), got)
    got = location(API + '/download.php?file=e-layout-1.2.0.apk%0A')
    check('a file name with a trailing newline is not a release file', got and got[1].endswith('/download/'), got)
    got = location(API + '/download.php')
    check('no file name goes to the page', got and got[1].endswith('/download/'), got)
    s, b, h = raw('GET', API + '/download.php?action=stats')
    low = {k.lower(): v for k, v in h.items()}
    check('download stats count each platform', s == 200 and jbody(b) == {'android': 1, 'windows': 1, 'total': 2}, (s, b))
    check('download stats are public and not cached',
          low.get('access-control-allow-origin') == '*' and 'no-cache' in low.get('cache-control', ''), h)
    counts_file = os.path.join(site, 'private', 'download-counts.json')
    check('counts are kept in private/', os.path.isfile(counts_file))

    # ---------- errors never leak a path ----------
    s, b, h = raw('GET', API + '/releases.php')
    check('JSON answers are not cached', 'no-store' in {k.lower(): v for k, v in h.items()}.get('cache-control', ''), h)
    config = os.path.join(site, 'private', 'api-config.php')
    os.rename(config, config + '.off')
    s, b, _ = raw('GET', API + '/')
    check('a missing config answers 500 without a path', s == 500 and jbody(b) == {'error': 'Server not configured: private/api-config.php is missing.'}, (s, b))
    os.rename(config + '.off', config)


def run_page_checks(site):
    for label, rel_path in [('landing page', 'index.html'), ('download page', 'download/index.html')]:
        page_checks(site, label, rel_path)
    landing = open(os.path.join(site, 'index.html'), encoding='utf-8').read() if os.path.isfile(os.path.join(site, 'index.html')) else ''
    download = open(os.path.join(site, 'download', 'index.html'), encoding='utf-8').read() if os.path.isfile(os.path.join(site, 'download', 'index.html')) else ''
    check('landing page title', '<title>e-Layout: your office' in landing)
    check('download page title', '<title>Download e-Layout</title>' in download)
    check('landing page says e-Layout is the new name', 'e-Layout is the new name of PIO Photo Layout.' in landing)
    check('landing page links to the download page and the browser version', 'href="/download/"' in landing and 'href="/app/"' in landing)
    check('landing page never prints an email address', not re.search(r'[\w.+-]+@[\w-]+\.[\w.]+', landing + download))
    htaccess = os.path.join(site, '.htaccess')
    check('the root .htaccess keeps the classic tool', os.path.isfile(htaccess) and '/app.html' in open(htaccess, encoding='utf-8').read())
    root_ht = open(htaccess, encoding='utf-8').read()
    check('the root .htaccess lists index.php so /api/ runs api/index.php',
          re.search(r'^\s*DirectoryIndex\s+index\.html\s+index\.php\s*$', root_ht, re.M) is not None)
    check('the root .htaccess answers 404 for /private as a second lock',
          re.search(r'^\s*RedirectMatch\s+404\s+\^/private\(/\|\$\)\s*$', root_ht, re.M) is not None)
    # The old project's files were uploaded with the classic tool and can't be deleted with the
    # tools at hand, so the root .htaccess hides them; nothing the sites use may be caught.
    gone = [re.compile(m) for m in re.findall(r'^\s*RedirectMatch\s+404\s+(\S+)\s*$', root_ht, re.M)]
    leftovers = ['/.superpowers', '/.superpowers/', '/.superpowers/brainstorm/1994-1792592554/content/photo.jpg',
                 '/alight_motion/', '/alight_motion/603f8847-eebb-455a-be55-9a133f28fac6.jpg', '/tools/',
                 '/tools/build_layouts.py', '/prompt.md', '/README.md']
    check('the root .htaccess answers 404 for the old project leftovers',
          all(any(g.search(p) for g in gone) for p in leftovers),
          [p for p in leftovers if not any(g.search(p) for g in gone)])
    in_use = ['/', '/index.html', '/favicon.ico', '/app.html', '/css/app.css', '/css/landing.css', '/js/app.js',
              '/js/landing.js', '/fonts/barlow-400.woff2', '/fonts/licenses/barlow.txt', '/img/seal-96.png',
              '/layouts/layouts.js', '/layouts/pio-footer.layout.json', '/landing/landing.js', '/landing/demo/render.js',
              '/download/', '/download/latest.json', '/download/files/e-layout-1.0.0.apk', '/app/', '/app/main.dart.js',
              '/app/assets/AssetManifest.bin.json', '/api/', '/api/releases.php', '/api/download.php', '/admin/']
    check('the root .htaccess 404 rules leave every page and file the sites use alone',
          not any(g.search(p) for g in gone for p in in_use),
          [p for p in in_use if any(g.search(p) for g in gone)])
    for rel_path in ['api/.htaccess', 'download/.htaccess', 'private/.htaccess']:
        check(f'{rel_path} exists', os.path.isfile(os.path.join(site, *rel_path.split('/'))))
    demo = subprocess.run([sys.executable, os.path.join(ROOT, 'tool', 'site_copy_demo.py'), '--check'], capture_output=True, text=True)
    check('landing/demo matches its sources', demo.returncode == 0, demo.stdout + demo.stderr)


if __name__ == '__main__':
    main()
