"""Sets a new version in pubspec.yaml and lib/app_info.dart; the build number goes up by one.

    python scripts/bump_version.py 1.0.1

Prints the tag to use afterwards. Then write the "## 1.0.1" notes in assets/whats_new.md.
"""
import os
import re
import sys
from pathlib import Path

ROOT = Path(os.environ.get('ELAYOUT_ROOT') or Path(__file__).resolve().parent.parent)


def main():
    if len(sys.argv) != 2 or not re.match(r'^\d{1,3}\.\d{1,3}\.\d{1,4}$', sys.argv[1]):
        sys.exit('usage: bump_version.py <x.y.z>   (for example 1.0.1)')
    version = sys.argv[1]
    pubspec = ROOT / 'pubspec.yaml'
    text = pubspec.read_text(encoding='utf-8')
    m = re.search(r'^version:\s*\d+\.\d+\.\d+\+(\d+)\s*$', text, re.M)
    if not m:
        sys.exit('pubspec.yaml has no "version: x.y.z+build" line.')
    build = int(m.group(1)) + 1
    text = text[:m.start()] + 'version: %s+%d' % (version, build) + text[m.end():]
    pubspec.write_text(text, encoding='utf-8', newline='\n')

    info = ROOT / 'lib' / 'app_info.dart'
    text = info.read_text(encoding='utf-8')
    text, n1 = re.subn(r"(const String kAppVersion = ')\d+\.\d+\.\d+(';)", r'\g<1>' + version + r'\g<2>', text)
    text, n2 = re.subn(r'(const int kAppBuild = )\d+(;)', r'\g<1>' + str(build) + r'\g<2>', text)
    if n1 != 1 or n2 != 1:
        sys.exit('lib/app_info.dart must have kAppVersion and kAppBuild lines (see scripts/check_version.py).')
    info.write_text(text, encoding='utf-8', newline='\n')
    print('Version is now %s+%d. Tag it as v%s+%d.' % (version, build, version, build))


if __name__ == '__main__':
    main()
