"""Checks that a release tag, pubspec.yaml and lib/app_info.dart all name the same version.

    python3 scripts/check_version.py v1.0.0+1

The tag must be v<x.y.z>+<build>. Exits non-zero and names the places that disagree.
"""
import os
import re
import sys
from pathlib import Path

ROOT = Path(os.environ.get('ELAYOUT_ROOT') or Path(__file__).resolve().parent.parent)


def read_pubspec():
    text = (ROOT / 'pubspec.yaml').read_text(encoding='utf-8')
    m = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$', text, re.M)
    if not m:
        sys.exit('pubspec.yaml has no "version: x.y.z+build" line.')
    return m.group(1), int(m.group(2))


def read_app_info():
    text = (ROOT / 'lib' / 'app_info.dart').read_text(encoding='utf-8')
    v = re.search(r"const String kAppVersion = '(\d+\.\d+\.\d+)';", text)
    b = re.search(r'const int kAppBuild = (\d+);', text)
    if not v or not b:
        sys.exit('lib/app_info.dart must have "const String kAppVersion = \'x.y.z\';" and '
                 '"const int kAppBuild = n;".')
    return v.group(1), int(b.group(1))


def main():
    if len(sys.argv) != 2:
        sys.exit('usage: check_version.py <tag, e.g. v1.0.0+1>')
    tag = sys.argv[1]
    m = re.match(r'^v(\d+\.\d+\.\d+)\+(\d+)$', tag)
    if not m:
        sys.exit('The tag "%s" must look like v1.0.0+1 (version, then +build).' % tag)
    want = (m.group(1), int(m.group(2)))
    places = {'pubspec.yaml': read_pubspec(), 'lib/app_info.dart': read_app_info()}
    bad = ['%s says %s+%d' % (name, found[0], found[1]) for name, found in places.items() if found != want]
    if bad:
        sys.exit('The tag %s (%s+%d) does not match: %s. Run python scripts/bump_version.py %s, '
                 'commit, and tag again.' % (tag, want[0], want[1], '; '.join(bad), want[0]))
    print('Version %s+%d matches the tag, pubspec.yaml and lib/app_info.dart.' % want)


if __name__ == '__main__':
    main()
