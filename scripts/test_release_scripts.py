"""Tests for the release scripts. Run directly: python scripts/test_release_scripts.py

Uses temporary copies of the project files and, for the upload test, a copy of the site
served by PHP's built-in server on port 8801. Nothing outside temporary folders is touched
and nothing is sent anywhere but 127.0.0.1.
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
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
PORT = 8801
MB = 1024 * 1024


def run(script, *args, root=None, env=None, cwd=None):
    e = dict(os.environ)
    e.pop('RELEASE_UPLOAD_SECRET', None)
    e.pop('GITHUB_REF_NAME', None)
    e.pop('RELEASE_UPLOAD_URL', None)
    if root is not None:
        e['ELAYOUT_ROOT'] = str(root)
    e.update(env or {})
    return subprocess.run([sys.executable, str(HERE / script), *args], capture_output=True, text=True,
                          env=e, cwd=cwd or str(PROJECT))


def project_copy(whats_new=None, pubspec=None, app_info=None):
    tmp = tempfile.TemporaryDirectory()
    root = Path(tmp.name)
    (root / 'assets').mkdir()
    (root / 'lib').mkdir()
    shutil.copy(PROJECT / 'assets' / 'whats_new.md', root / 'assets' / 'whats_new.md')
    shutil.copy(PROJECT / 'pubspec.yaml', root / 'pubspec.yaml')
    shutil.copy(PROJECT / 'lib' / 'app_info.dart', root / 'lib' / 'app_info.dart')
    if whats_new is not None:
        (root / 'assets' / 'whats_new.md').write_text(whats_new, encoding='utf-8')
    if pubspec is not None:
        (root / 'pubspec.yaml').write_text(pubspec, encoding='utf-8')
    if app_info is not None:
        (root / 'lib' / 'app_info.dart').write_text(app_info, encoding='utf-8')
    return tmp, root


class WhatsNewTest(unittest.TestCase):
    def test_prints_the_bullets_for_a_tag(self):
        r = run('whats_new_for_release.py', 'v1.0.0+1')
        self.assertEqual(r.returncode, 0, r.stderr)
        lines = r.stdout.strip().splitlines()
        self.assertTrue(len(lines) >= 3)
        self.assertTrue(all(line.startswith('- ') for line in lines))
        self.assertIn('e-Layout', r.stdout)

    def test_missing_version_stops_with_a_message(self):
        r = run('whats_new_for_release.py', 'v9.9.9+1')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('No "What\'s new" notes for 9.9.9', r.stderr)

    def test_blocked_word_is_named(self):
        tmp, root = project_copy(whats_new='# What\'s new\n\n## 1.0.0\n\n- Faster saving on the server.\n- Fine bullet.\n')
        try:
            r = run('whats_new_for_release.py', 'v1.0.0+1', root=root)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn('mentions "server"', r.stderr)
        finally:
            tmp.cleanup()

    def test_blocked_words_only_match_whole_words(self):
        tmp, root = project_copy(whats_new='# What\'s new\n\n## 1.0.0\n\n- Pick a rapid layout, then save the escape-friendly photos.\n')
        try:
            r = run('whats_new_for_release.py', 'v1.0.0+1', root=root)
            self.assertEqual(r.returncode, 0, r.stderr)
        finally:
            tmp.cleanup()


def current_version():
    """(version, build) from the project's pubspec.yaml."""
    text = (PROJECT / 'pubspec.yaml').read_text(encoding='utf-8')
    m = re.search(r'^version: (\d+\.\d+\.\d+)\+(\d+)', text, re.M)
    return m.group(1), int(m.group(2))


class VersionTest(unittest.TestCase):
    def test_matching_tag_passes(self):
        version, build = current_version()
        r = run('check_version.py', f'v{version}+{build}')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_wrong_version_names_both_places(self):
        r = run('check_version.py', 'v1.0.1+1')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('pubspec.yaml', r.stderr)
        self.assertIn('lib/app_info.dart', r.stderr)

    def test_wrong_build_fails(self):
        r = run('check_version.py', 'v1.0.0+2')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('pubspec.yaml', r.stderr)
        self.assertIn('lib/app_info.dart', r.stderr)

    def test_a_tag_without_a_build_fails(self):
        r = run('check_version.py', 'v1.0.0')
        self.assertNotEqual(r.returncode, 0)

    def test_pubspec_and_app_info_must_agree(self):
        tmp, root = project_copy()
        try:
            text = (root / 'lib' / 'app_info.dart').read_text(encoding='utf-8')
            (root / 'lib' / 'app_info.dart').write_text(text.replace("'1.0.0'", "'1.0.5'"), encoding='utf-8')
            r = run('check_version.py', 'v1.0.0+1', root=root)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn('lib/app_info.dart', r.stderr)
        finally:
            tmp.cleanup()

    def test_bump_changes_both_places(self):
        tmp, root = project_copy()
        try:
            nxt = current_version()[1] + 1
            r = run('bump_version.py', '9.9.9', root=root)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertIn(f'version: 9.9.9+{nxt}', (root / 'pubspec.yaml').read_text(encoding='utf-8'))
            info = (root / 'lib' / 'app_info.dart').read_text(encoding='utf-8')
            self.assertIn("kAppVersion = '9.9.9';", info)
            self.assertIn(f'kAppBuild = {nxt};', info)
            r = run('check_version.py', f'v9.9.9+{nxt}', root=root)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        finally:
            tmp.cleanup()

    def test_bump_rejects_a_bad_version(self):
        tmp, root = project_copy()
        try:
            r = run('bump_version.py', '1.0', root=root)
            self.assertNotEqual(r.returncode, 0)
        finally:
            tmp.cleanup()


class PublishTest(unittest.TestCase):
    server = None
    site = None
    secret = 'test-secret-' + 'x' * 40

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.site = Path(cls.tmp.name) / 'pio'
        src = PROJECT / 'hostinger'
        shutil.copytree(src / 'public_html', cls.site)
        shutil.copytree(src / 'private', cls.site / 'private')
        config = (src / 'private' / 'api-config.example.php').read_text(encoding='utf-8')
        config = config.replace('https://pio.bongabong.gov.ph/api', 'http://127.0.0.1:%d/api' % PORT)
        (cls.site / 'private' / 'api-config.php').write_text(config, encoding='utf-8')
        (cls.site / 'private' / 'release-upload-secret.php').write_text("<?php return '" + cls.secret + "';" + chr(10), encoding='utf-8')
        cls.server = subprocess.Popen(
            ['php', '-S', '127.0.0.1:%d' % PORT, '-t', str(cls.site), '-d', 'post_max_size=13M',
             '-d', 'upload_max_filesize=12M', '-d', 'memory_limit=256M'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(1.5)

    @classmethod
    def tearDownClass(cls):
        if cls.server:
            cls.server.terminate()
            try:
                cls.server.wait(timeout=10)
            except Exception:
                cls.server.kill()
        cls.tmp.cleanup()

    def test_without_a_secret_it_warns_and_exits_zero(self):
        r = run('publish_release.py', 'android', 'whatever.apk', env={'GITHUB_REF_NAME': 'v1.0.0+1'})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('::warning::RELEASE_UPLOAD_SECRET is not set: the download page was not updated. '
                      'The files are on the GitHub release.', r.stdout)

    def test_wrongly_named_file_fails(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'calendar-1.0.0.apk'
            p.write_bytes(b'x')
            r = run('publish_release.py', 'android', str(p),
                    env={'RELEASE_UPLOAD_SECRET': self.secret, 'GITHUB_REF_NAME': 'v1.0.0+1',
                         'RELEASE_UPLOAD_URL': 'http://127.0.0.1:%d/api/releases.php' % PORT})
            self.assertNotEqual(r.returncode, 0)
            self.assertIn('e-layout-1.0.0.apk', r.stderr)

    def test_a_nine_megabyte_apk_goes_up_in_two_pieces(self):
        with tempfile.TemporaryDirectory() as d:
            data = os.urandom(9 * MB)
            p = Path(d) / 'e-layout-1.0.0.apk'
            p.write_bytes(data)
            r = run('publish_release.py', 'android', str(p),
                    env={'RELEASE_UPLOAD_SECRET': self.secret, 'GITHUB_REF_NAME': 'v1.0.0+1',
                         'RELEASE_UPLOAD_URL': 'http://127.0.0.1:%d/api/releases.php' % PORT})
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertIn('e-layout-1.0.0.apk: 88%', r.stdout)
            self.assertIn('e-layout-1.0.0.apk: 100%', r.stdout)
            latest = json.loads((self.site / 'download' / 'latest.json').read_text(encoding='utf-8'))
            entry = latest['android']
            self.assertEqual(entry['size'], len(data))
            self.assertEqual(entry['sha256'], hashlib.sha256(data).hexdigest())
            self.assertEqual(entry['version'], '1.0.0')
            self.assertEqual(entry['build'], 1)
            self.assertTrue(entry['whats_new'])
            self.assertIsNone(latest['windows'])
            self.assertEqual((self.site / 'download' / 'files' / 'e-layout-1.0.0.apk').read_bytes(), data)

    def test_a_wrong_secret_fails(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'e-layout-1.0.0.apk'
            p.write_bytes(b'x' * 1000)
            r = run('publish_release.py', 'android', str(p),
                    env={'RELEASE_UPLOAD_SECRET': 'y' * 40, 'GITHUB_REF_NAME': 'v1.0.0+1',
                         'RELEASE_UPLOAD_URL': 'http://127.0.0.1:%d/api/releases.php' % PORT})
            self.assertNotEqual(r.returncode, 0)


if __name__ == '__main__':
    unittest.main()
