"""Tests for tool/site_bundle.py (and the shared helpers of the site_* tools).

    python tool/test_site_tools.py
"""
import hashlib
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


class BundleTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.app = os.path.join(self.tmp.name, 'webbuild')
        os.makedirs(os.path.join(self.app, 'assets'))
        with open(os.path.join(self.app, 'index.html'), 'w', encoding='utf-8') as f:
            f.write('<!doctype html><title>dummy</title>')
        with open(os.path.join(self.app, 'assets', 'a.bin'), 'wb') as f:
            f.write(b'\x00\x01\x02')
        self.out = os.path.join(self.tmp.name, 'out')
        result = subprocess.run(
            [sys.executable, os.path.join(HERE, 'site_bundle.py'), '--app-dir', self.app, '--out', self.out],
            capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.pio = os.path.join(self.out, 'pio')

    def files(self):
        found = []
        for base, _, names in os.walk(self.pio):
            for name in names:
                found.append(os.path.relpath(os.path.join(base, name), self.pio).replace(os.sep, '/'))
        return sorted(found)

    def test_app_is_copied_under_app(self):
        self.assertTrue(os.path.isfile(os.path.join(self.pio, 'app', 'index.html')))
        self.assertTrue(os.path.isfile(os.path.join(self.pio, 'app', 'assets', 'a.bin')))

    def test_private_has_only_the_example_config(self):
        private = [f for f in self.files() if f.startswith('private/')]
        self.assertIn('private/api-config.example.php', private)
        self.assertIn('private/.htaccess', private)
        self.assertIn('private/index.php', private)
        self.assertNotIn('private/api-config.php', private)
        self.assertEqual(sorted(private), ['private/.htaccess', 'private/api-config.example.php', 'private/index.php'])

    def test_site_files_are_there_and_tests_are_not(self):
        files = self.files()
        for wanted in ['index.html', '.htaccess', 'api/releases.php', 'api/_lib.php', 'download/index.html', 'download/.htaccess']:
            self.assertIn(wanted, files)
        self.assertFalse([f for f in files if f.startswith('tests/') or '/tests/' in f])
        self.assertFalse([f for f in files if f.endswith('.pyc')])

    def test_manifest_lists_every_file_with_its_hash(self):
        manifest = os.path.join(self.out, 'MANIFEST.txt')
        self.assertTrue(os.path.isfile(manifest))
        listed = {}
        with open(manifest, encoding='utf-8') as f:
            for line in f:
                line = line.rstrip('\n')
                if not line or line.startswith('#'):
                    continue
                path, size, sha = line.split('\t')
                listed[path] = (int(size), sha)
        self.assertEqual(sorted(listed), self.files())
        for path, (size, sha) in listed.items():
            with open(os.path.join(self.pio, *path.split('/')), 'rb') as f:
                data = f.read()
            self.assertEqual(size, len(data), path)
            self.assertEqual(sha, hashlib.sha256(data).hexdigest(), path)

    def test_zip_holds_the_same_files(self):
        zips = [n for n in os.listdir(self.out) if n.startswith('e-layout-site-') and n.endswith('.zip')]
        self.assertEqual(len(zips), 1, os.listdir(self.out))
        with zipfile.ZipFile(os.path.join(self.out, zips[0])) as z:
            names = sorted(n for n in z.namelist() if not n.endswith('/'))
        self.assertEqual(names, self.files())

    def test_missing_app_dir_fails(self):
        result = subprocess.run(
            [sys.executable, os.path.join(HERE, 'site_bundle.py'), '--app-dir', os.path.join(self.tmp.name, 'nope'),
             '--out', os.path.join(self.tmp.name, 'out2')], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
