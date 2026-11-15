"""Sets the repository secrets the release workflow needs, reading them from .release/.

    python scripts/set_github_secrets.py --repo Vincentjhon31/e-layout [--dry-run]

Sets KEYSTORE_FILE (base64 of .release/upload-keystore.jks), KEYSTORE_PASSWORD, KEY_ALIAS,
KEY_PASSWORD and RELEASE_UPLOAD_SECRET. Each value goes to "gh secret set" on standard input
and is never printed. --dry-run prints only the names and the lengths of the values.
It does not set the repository variable PUBLISH_TO_SITE (see RELEASE_GUIDE.md).
"""
import argparse
import base64
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_upload_key import KEYSTORE, read_secrets  # noqa: E402

NAMES = ['KEYSTORE_PASSWORD', 'KEY_ALIAS', 'KEY_PASSWORD', 'RELEASE_UPLOAD_SECRET']


def collect():
    if not Path(KEYSTORE).exists():
        sys.exit('No key yet: run python scripts/make_upload_key.py first.')
    values = read_secrets()
    missing = [n for n in NAMES if not values.get(n)]
    if missing:
        sys.exit('.release/secrets.txt has no value for: ' + ', '.join(missing))
    out = {'KEYSTORE_FILE': base64.b64encode(Path(KEYSTORE).read_bytes()).decode('ascii')}
    out.update({n: values[n] for n in NAMES})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--repo', required=True)
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()
    values = collect()
    for name, value in values.items():
        if args.dry_run:
            print('%s: %d characters (not set, dry run)' % (name, len(value)))
            continue
        r = subprocess.run(['gh', 'secret', 'set', name, '--repo', args.repo], input=value,
                           capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit('Could not set %s: %s' % (name, r.stderr.replace(value, '[hidden]').strip()[-200:]))
        print('Set %s.' % name)


if __name__ == '__main__':
    main()
