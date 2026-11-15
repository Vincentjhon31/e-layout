"""Prints the user-facing "What's new" bullets for one release, taken from
assets/whats_new.md, for the release workflow to put in the GitHub release
(the app shows ONLY these, see lib/features/about/whats_new.dart).

    python3 scripts/whats_new_for_release.py v1.0.0+1

Exits with an error (stopping the release before anything is built) when:
  * there is no "## 1.0.0" section, or it has no bullets: every release
    needs notes for the people who use the app; or
  * a bullet contains an internal term: the notes are public and shown in
    the app, so they must describe what people notice, never how the system
    works behind the scenes. This list is a safety net, not a guarantee.
"""
import os
import re
import sys
from pathlib import Path

ROOT = Path(os.environ.get('ELAYOUT_ROOT') or Path(__file__).resolve().parent.parent)
NOTES_FILE = 'assets/whats_new.md'

# Whole words, matched case-insensitively.
BLOCKED = [
    'hostinger', 'github', 'php', 'htaccess', 'api', 'endpoint', 'server', 'backend', 'database',
    'sql', 'token', 'secret', 'secrets', 'credential', 'credentials', 'password', 'keystore',
    'checksum', 'sha256', 'sha-256', 'admin', 'webhook', 'cron', 'commit', 'refactor',
    'stack trace', 'flutter', 'dart', 'gradle', 'inno setup',
]


def all_notes():
    """Every version's bullets in NOTES_FILE, newest section first:
    {"1.0.0": ["...", ...], ...}."""
    text = (ROOT / NOTES_FILE).read_text(encoding='utf-8')
    text = re.sub(r'<!--.*?-->', '', text, flags=re.S)

    items, current = {}, None
    for raw in text.splitlines():
        line = raw.strip()
        heading = re.match(r'^##\s+v?(\d+\.\d+\.\d+)', line)
        if heading:
            current = heading.group(1)
            items.setdefault(current, [])
        elif current and line.startswith('- ') and line[2:].strip():
            items[current].append(line[2:].strip())
    return items


def checked_notes(version):
    """The bullets of one version; exits with an explanation if there are none
    or one mentions an internal detail (see the module docstring)."""
    notes = all_notes().get(version) or []
    if not notes:
        sys.exit('No "What\'s new" notes for %s. Add a "## %s" section with "- " bullets at the top of %s '
                 '(plain words for the people who use the app), then tag again.' % (version, version, NOTES_FILE))

    problems = []
    for note in notes:
        for word in BLOCKED:
            if re.search(r'(?<![\w-])' + re.escape(word) + r'(?![\w-])', note, flags=re.I):
                problems.append('  "%s"  ->  mentions "%s"' % (note, word))
    if problems:
        sys.exit('The "What\'s new" notes for %s mention internal details. They are shown to every user, '
                 'so describe what people notice instead:\n%s' % (version, '\n'.join(problems)))
    return notes


def version_of(tag):
    """"v1.0.0+1" -> "1.0.0"."""
    return re.sub(r'^v', '', tag).split('+')[0]


def main():
    if len(sys.argv) != 2:
        sys.exit('usage: whats_new_for_release.py <tag, e.g. v1.0.0+1>')
    for note in checked_notes(version_of(sys.argv[1])):
        print('- ' + note)


if __name__ == '__main__':
    main()
