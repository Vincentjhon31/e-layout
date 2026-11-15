"""Puts one release file on the download page (pio.bongabong.gov.ph/download/),
which is where the apps check for updates. Run by the release workflow:

    python3 scripts/publish_release.py android dist/e-layout-1.0.0.apk
    python  scripts/publish_release.py windows installer_output/e-layout-1.0.0-setup.exe

Needs, from the environment:
  RELEASE_UPLOAD_SECRET  the same value as private/release-upload-secret.txt
                         on the server (see hostinger/README.md)
  GITHUB_REF_NAME        the release tag, e.g. v1.0.0+1 (set by GitHub Actions)
  RELEASE_UPLOAD_URL     optional; defaults to the live site's api/releases.php

Without RELEASE_UPLOAD_SECRET it prints a warning and exits 0 (the release still
succeeds, its files are on GitHub). Otherwise it uploads the file in pieces (the server
takes at most 8 MB per request), resuming where the server says it stopped, then
publishes it with its size, SHA-256 and every version's "What's new" notes.
Exits non-zero on any failure, which fails the step.
"""
import datetime
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from whats_new_for_release import all_notes, checked_notes, version_of  # noqa: E402

DEFAULT_URL = 'https://pio.bongabong.gov.ph/api/releases.php'
CHUNK = 8 * 1024 * 1024
ATTEMPTS = 5
MANILA = datetime.timezone(datetime.timedelta(hours=8))


def call(url, secret, data, content_type='application/octet-stream'):
    """(status, parsed JSON body). Retries network errors and server errors.
    Pieces must go out as application/octet-stream, otherwise PHP reads the
    binary body as a form."""
    for attempt in range(1, ATTEMPTS + 1):
        req = urllib.request.Request(url, data=data, method='POST', headers={
            'X-Release-Secret': secret,
            'Content-Type': content_type,
            'User-Agent': 'elayout-release/1',
        })
        try:
            with urllib.request.urlopen(req, timeout=120) as res:
                return res.status, json.loads(res.read() or b'{}')
        except urllib.error.HTTPError as e:
            body = e.read()
            try:
                parsed = json.loads(body)
            except ValueError:
                parsed = {'error': body[:300].decode('utf-8', 'replace')}
            if e.code < 500 or attempt == ATTEMPTS:
                return e.code, parsed
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            if attempt == ATTEMPTS:
                sys.exit('Could not reach %s: %s' % (url, e))
        time.sleep(3 * attempt)
    raise AssertionError('unreachable')


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ('android', 'windows'):
        sys.exit('usage: publish_release.py <android|windows> <file>')
    platform, path = sys.argv[1], sys.argv[2]
    secret = os.environ.get('RELEASE_UPLOAD_SECRET', '').strip()
    if not secret:
        print('::warning::RELEASE_UPLOAD_SECRET is not set: the download page was not updated. '
              'The files are on the GitHub release.')
        return
    if len(secret) < 32:
        sys.exit('RELEASE_UPLOAD_SECRET is shorter than 32 characters. Set it again in the repository '
                 'settings (Settings > Secrets and variables > Actions). See hostinger/README.md.')
    tag = os.environ.get('GITHUB_REF_NAME', '')
    if not tag:
        sys.exit('GITHUB_REF_NAME is not set (it holds the release tag, for example v1.0.0+1).')
    version = version_of(tag)
    build = int(tag.split('+')[1]) if '+' in tag else 0
    url = os.environ.get('RELEASE_UPLOAD_URL', DEFAULT_URL)

    name = os.path.basename(path)
    expected = 'e-layout-%s' % version + ('.apk' if platform == 'android' else '-setup.exe')
    if name != expected:
        sys.exit('Expected the file to be named %s, got %s.' % (expected, name))

    checked_notes(version)  # stops here if this version has no notes for users
    changelog = all_notes()

    size = os.path.getsize(path)
    digest = hashlib.sha256()
    offset = 0
    resumes = 0
    with open(path, 'rb') as f:
        while offset < size:
            f.seek(offset)
            piece = f.read(CHUNK)
            status, body = call('%s?action=chunk&name=%s&offset=%d&total=%d' % (url, name, offset, size),
                                secret, piece)
            if status == 409 and isinstance(body.get('received'), int) and resumes < 10:
                resumes += 1
                offset = body['received']  # resume where the server stopped
                continue
            if status != 200:
                sys.exit('Upload failed at byte %d (%d): %s' % (offset, status, body.get('error', body)))
            offset = body['received']
            print('  %s: %d%%' % (name, offset * 100 // size))
        f.seek(0)
        for block in iter(lambda: f.read(1024 * 1024), b''):
            digest.update(block)

    status, body = call('%s?action=publish' % url, secret, json.dumps({
        'version': version,
        'build': build,
        'date': datetime.datetime.now(MANILA).date().isoformat(),
        'platform': platform,
        'file': name,
        'size': size,
        'sha256': digest.hexdigest(),
        'changelog': changelog,
    }).encode(), 'application/json')
    if status != 200:
        sys.exit('Publishing failed (%d): %s' % (status, body.get('error', body)))
    print('Published %s (%d bytes) as version %s+%d for %s: %s'
          % (name, size, version, build, platform, body['latest']['url']))


if __name__ == '__main__':
    main()
