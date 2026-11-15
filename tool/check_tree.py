"""Scan the files that git would track for things that must never be published.

    python tool/check_tree.py [--root DIR]

Prints "Tree is clean: <n> files checked." and exits 0, or one line per problem
    PROBLEM <path>[:<line>]: <kind>
and exits 1. A matched value is never printed, only "[redacted, <n> characters]".

Before a .git folder exists the list of files comes from git too (a throwaway
repository is used only to read the .gitignore rules); if git is not available
a plain walk skips the usual build folders.
"""
import argparse
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

MAX_BYTES = 10 * 1024 * 1024
SKIP_DIRS_NO_GIT = {'build', '.dart_tool', 'dist', '.release', 'installer_output', '.idea', '.git'}

# Files whose email addresses are public and allowed (the PIO's own footer layout, its copy in
# the landing page's demo, and the font licences).
EMAIL_ALLOWED_FILES = {
    'assets/layouts/pio-footer.layout.json',
    'hostinger/public_html/landing/demo/layouts.js',
}
EMAIL_ALLOWED_PREFIXES = ('assets/fonts/licenses/', 'hostinger/public_html/landing/demo/fonts/licenses/')
EMAIL_ALLOWED_DOMAINS = ('example.com', 'example.org', 'users.noreply.github.com')

# Files that legitimately mention key-like words and are checked by name only.
TEXT_SKIP_SUFFIXES = {
    '.png', '.jpg', '.jpeg', '.webp', '.gif', '.ico', '.ttf', '.otf', '.woff', '.woff2', '.zip',
    '.jar', '.so', '.dll', '.exe', '.apk', '.aab', '.heic', '.heif', '.bin', '.pdf', '.jks',
    '.keystore', '.p12', '.class', '.dex', '.bmp', '.mp4', '.mov',
}

KEY_FILE_SUFFIXES = {'.jks', '.keystore', '.p12', '.pfx'}
BUILD_SUFFIXES = {'.apk', '.aab', '.exe', '.msi'}
PHONE_PHOTO_SUFFIXES = {'.heic', '.heif'}

RE_PRIVATE_KEY = re.compile(r'-----BEGIN (?:[A-Z]+ )?PRIVATE KEY(?: BLOCK)?-----')
RE_GITHUB = re.compile(r'\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{50,})')
RE_GOOGLE = re.compile(r'\bAIza[0-9A-Za-z_\-]{35}\b')
RE_PASSWORD = re.compile(r'\b(?:storePassword|keyPassword)\s*=\s*([A-Za-z0-9_\-+/=.]{6,})\s*$', re.M)
RE_EMAIL = re.compile(r'[A-Za-z0-9._%+\-]+@([A-Za-z][A-Za-z0-9\-]*(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,})')
RE_USER_PATH = re.compile(r'\b[A-Za-z]:[\\/]+Users[\\/]+([^\\/\s"\'`<>%$*{}()\[\]|]+)')
RE_CAMERA_NAME = re.compile(
    r'^(?:IMG|DSC|DSCN|DSCF|PXL|MVIMG|VID)[_\-]?\d{4,}.*\.(?:jpe?g|png|heic|heif|webp)$', re.I)
RE_FACEBOOK_NAME = re.compile(r'^\d+_\d+_\d+_[a-z]\.(?:jpe?g|png|webp)$', re.I)

USER_PATH_OK = {'public', 'default', 'all users', 'user', 'username', 'you', 'name', 'yourname'}


class Problem:
    def __init__(self, path, kind, line=None, redacted=None):
        self.path = path
        self.kind = kind
        self.line = line
        self.redacted = redacted

    def __str__(self):
        where = str(self.path) + (':' + str(self.line) if self.line else '')
        text = 'PROBLEM %s: %s' % (where, self.kind)
        if self.redacted is not None:
            text += ' [redacted, %d characters]' % self.redacted
        return text


def _git(args, root, git_dir=None):
    cmd = ['git']
    if git_dir:
        cmd += ['--git-dir=' + str(git_dir), '--work-tree=' + str(root)]
    cmd += args
    return subprocess.run(cmd, cwd=str(root), capture_output=True, check=True).stdout


def list_files(root):
    """Relative posix paths of the files git would track."""
    root = Path(root)
    try:
        if (root / '.git').exists():
            out = _git(['ls-files', '-z', '--cached', '--others', '--exclude-standard'], root)
        else:
            with tempfile.TemporaryDirectory() as tmp:
                git_dir = Path(tmp) / 'repo.git'
                subprocess.run(['git', 'init', '-q', '--bare', str(git_dir)], check=True, capture_output=True)
                out = _git(['ls-files', '-z', '--others', '--exclude-standard'], root, git_dir)
        names = [n for n in out.decode('utf-8', 'surrogateescape').split('\0') if n]
        return sorted(n for n in names if (root / n).is_file())
    except (OSError, subprocess.CalledProcessError):
        found = []
        for dirpath, dirnames, filenames in os.walk(root):
            rel_dir = Path(dirpath).relative_to(root)
            if rel_dir == Path('.'):
                dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS_NO_GIT]
            for f in filenames:
                found.append((rel_dir / f).as_posix())
        return sorted(found)


def _email_allowed(rel, domain):
    if rel in EMAIL_ALLOWED_FILES or rel.startswith(EMAIL_ALLOWED_PREFIXES):
        return True
    d = domain.lower()
    return any(d == a or d.endswith('.' + a) for a in EMAIL_ALLOWED_DOMAINS)


def _line_of(text, index):
    return text.count('\n', 0, index) + 1


def _check_text(rel, text, problems):
    for regex, kind in ((RE_PRIVATE_KEY, 'private key'), (RE_GITHUB, 'GitHub token'),
                        (RE_GOOGLE, 'Google API key')):
        for m in regex.finditer(text):
            problems.append(Problem(rel, kind, _line_of(text, m.start()), len(m.group(0))))
    for m in RE_PASSWORD.finditer(text):
        problems.append(Problem(rel, 'password value', _line_of(text, m.start()), len(m.group(1))))
    for m in RE_EMAIL.finditer(text):
        if not _email_allowed(rel, m.group(1)):
            problems.append(Problem(rel, 'email address', _line_of(text, m.start()), len(m.group(0))))
    for m in RE_USER_PATH.finditer(text):
        if m.group(1).lower() not in USER_PATH_OK:
            problems.append(Problem(rel, 'local user path', _line_of(text, m.start()), len(m.group(0))))


def _check_jpeg(rel, path, problems):
    try:
        from PIL import Image
        with Image.open(path) as img:
            exif = img.getexif()
            tags = set(exif.keys())
            gps = bool(exif.get_ifd(34853)) if 34853 in tags else False
            if 271 in tags or 272 in tags or gps:
                problems.append(Problem(rel, 'photo with camera details'))
    except Exception:
        # Not a readable picture: leave it to the other rules.
        return


def scan(root):
    """Returns (number of files checked, [Problem])."""
    root = Path(root)
    problems = []
    files = list_files(root)
    for rel in files:
        path = root / rel
        name = path.name
        suffix = path.suffix.lower()
        if name == 'key.properties' or suffix in KEY_FILE_SUFFIXES:
            problems.append(Problem(rel, 'key file'))
        if suffix in BUILD_SUFFIXES:
            problems.append(Problem(rel, 'build output'))
        if suffix in PHONE_PHOTO_SUFFIXES:
            problems.append(Problem(rel, 'photo format from a phone'))
        if RE_CAMERA_NAME.match(name) or RE_FACEBOOK_NAME.match(name):
            problems.append(Problem(rel, 'camera file name'))
        try:
            size = path.stat().st_size
        except OSError:
            continue
        if size > MAX_BYTES:
            problems.append(Problem(rel, 'file over 10 MB'))
            continue
        if suffix in ('.jpg', '.jpeg'):
            _check_jpeg(rel, path, problems)
        if suffix in TEXT_SKIP_SUFFIXES:
            continue
        data = path.read_bytes()
        if b'\0' in data[:4096]:
            continue
        _check_text(rel, data.decode('utf-8', 'replace'), problems)
    return len(files), problems


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--root', default=str(Path(__file__).resolve().parent.parent))
    args = ap.parse_args(argv)
    count, problems = scan(args.root)
    if problems:
        for p in problems:
            print(p)
        return 1
    print('Tree is clean: %d files checked.' % count)
    return 0


if __name__ == '__main__':
    sys.exit(main())
