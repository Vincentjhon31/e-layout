"""Tests for tool/check_tree.py. Run directly: python tool/test_check_tree.py

Every fake secret is built from pieces at run time, so this file itself contains
nothing that the scanner would match.
"""
import io
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_tree  # noqa: E402

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent


def make_tree(files):
    tmp = tempfile.TemporaryDirectory()
    root = Path(tmp.name)
    for rel, data in files.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data if isinstance(data, bytes) else data.encode('utf-8'))
    return tmp, root


def problems_for(files):
    tmp, root = make_tree(files)
    try:
        count, problems = check_tree.scan(root)
        return count, problems
    finally:
        tmp.cleanup()


def kinds(problems):
    return sorted({p.kind for p in problems})


def jpeg_with_exif(tag_values=None, gps=False):
    from PIL import Image
    img = Image.new('RGB', (8, 8), (10, 120, 200))
    exif = Image.Exif()
    for tag, value in (tag_values or {}).items():
        exif[tag] = value
    if gps:
        exif[34853] = {1: 'N', 2: (13.0, 0.0, 0.0), 3: 'E', 4: (121.0, 0.0, 0.0)}
    buf = io.BytesIO()
    img.save(buf, 'JPEG', exif=exif)
    return buf.getvalue()


def png_bytes():
    from PIL import Image
    buf = io.BytesIO()
    Image.new('RGB', (8, 8), (200, 30, 30)).save(buf, 'PNG')
    return buf.getvalue()


class CheckTreeTest(unittest.TestCase):
    def test_clean_tree_passes(self):
        count, problems = problems_for({
            'lib/main.dart': 'void main() {}\n',
            'test/a_golden.png': png_bytes(),
            'README.md': 'Hello\n',
        })
        self.assertEqual(problems, [])
        self.assertEqual(count, 3)

    def test_private_key_header(self):
        header = '-----' + 'BEGIN ' + 'RSA PRIVATE' + ' KEY' + '-----'
        _, problems = problems_for({'a.txt': header + '\nabc\n'})
        self.assertEqual(kinds(problems), ['private key'])

    def test_github_token(self):
        token = 'gh' + 'p_' + 'a1B2c3D4e5' * 4
        _, problems = problems_for({'a.txt': 'x = ' + token + '\n'})
        self.assertEqual(kinds(problems), ['GitHub token'])
        self.assertNotIn(token, str(problems[0]))
        self.assertIn('[redacted, ', str(problems[0]))

    def test_google_api_key(self):
        key = 'AI' + 'za' + 'Sy' + 'A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q'[:33]
        self.assertEqual(len(key), 39)
        _, problems = problems_for({'a.txt': key + '\n'})
        self.assertEqual(kinds(problems), ['Google API key'])

    def test_store_password_value(self):
        line = 'store' + 'Password' + '=' + 'abcd1234efgh5678'
        _, problems = problems_for({'a.txt': line + '\n'})
        self.assertEqual(kinds(problems), ['password value'])

    def test_gradle_reading_the_properties_is_fine(self):
        text = 'signingConfigs { storePassword = keystoreProperties["storePassword"] as String }\n'
        _, problems = problems_for({'build.gradle.kts': text})
        self.assertEqual(problems, [])

    def test_key_properties_file(self):
        _, problems = problems_for({'android/key.properties': 'x\n'})
        self.assertIn('key file', kinds(problems))

    def test_keystore_files(self):
        _, problems = problems_for({'a.jks': b'\x00', 'b.keystore': b'\x00', 'c.p12': b'\x00'})
        self.assertEqual(kinds(problems), ['key file'])
        self.assertEqual(len(problems), 3)

    def test_apk_and_exe(self):
        _, problems = problems_for({'a.apk': b'\x00', 'b.exe': b'\x00'})
        self.assertEqual(kinds(problems), ['build output'])

    def test_big_file(self):
        _, problems = problems_for({'big.bin': b'\x00' * (10 * 1024 * 1024 + 1)})
        self.assertEqual(kinds(problems), ['file over 10 MB'])

    def test_email_outside_allow_list(self):
        email = 'someone' + '@' + 'example-office' + '.gov.ph'
        _, problems = problems_for({'a.md': 'write to ' + email + '\n'})
        self.assertEqual(kinds(problems), ['email address'])
        self.assertNotIn(email, str(problems[0]))

    def test_email_allow_list(self):
        email = 'someone' + '@' + 'office.gov.ph'
        _, problems = problems_for({
            'assets/layouts/pio-footer.layout.json': email,
            'assets/fonts/licenses/OFL.txt': 'Copyright ' + email,
            'a.md': 'a' + '@' + 'example.com and b' + '@' + 'example.org and 12345+me' + '@' + 'users.noreply.github.com',
            'ios/Contents.json': '"Icon-App-20x20' + '@' + '2x.png"',
        })
        self.assertEqual(problems, [])

    def test_local_user_path(self):
        path = 'C:' + '\\' + 'Users' + '\\' + 'some person' + '\\' + 'Desktop'
        path = 'C:' + '/' + 'Users' + '/' + 'somebody' + '/x'
        _, problems = problems_for({'a.md': 'see ' + path + '\n'})
        self.assertEqual(kinds(problems), ['local user path'])

    def test_user_path_placeholders_are_fine(self):
        text = 'C:' + '\\Users\\<you>\\x and C:' + '/Users/%USERNAME%/y and C:' + '/Users/Public/z\n'
        _, problems = problems_for({'a.md': text})
        self.assertEqual(problems, [])

    def test_jpeg_with_camera_exif(self):
        _, problems = problems_for({'a.jpg': jpeg_with_exif({271: 'Acme', 272: 'Phone 1'})})
        self.assertEqual(kinds(problems), ['photo with camera details'])

    def test_jpeg_with_gps(self):
        _, problems = problems_for({'a.jpeg': jpeg_with_exif(gps=True)})
        self.assertEqual(kinds(problems), ['photo with camera details'])

    def test_jpeg_without_exif_is_fine(self):
        _, problems = problems_for({'a.jpg': jpeg_with_exif()})
        self.assertEqual(problems, [])

    def test_heic(self):
        _, problems = problems_for({'a.heic': b'\x00', 'b.HEIF': b'\x00'})
        self.assertEqual(kinds(problems), ['photo format from a phone'])

    def test_camera_file_names(self):
        _, problems = problems_for({
            'x/IMG_1234.JPG': png_bytes(),
            'x/DSC00012.jpg': png_bytes(),
            'x/PXL_20260101_123456789.jpg': png_bytes(),
        })
        self.assertEqual(kinds(problems), ['camera file name'])
        self.assertEqual(len(problems), 3)

    def test_facebook_download_name(self):
        _, problems = problems_for({'x/123456789_987654321_55555555_n.jpg': png_bytes()})
        self.assertEqual(kinds(problems), ['camera file name'])

    def test_line_number_is_reported(self):
        header = '-----' + 'BEGIN ' + 'PRIVATE' + ' KEY' + '-----'
        _, problems = problems_for({'a.txt': 'one\ntwo\n' + header + '\n'})
        self.assertEqual(problems[0].line, 3)
        self.assertTrue(str(problems[0]).startswith('PROBLEM a.txt:3: private key'))

    def test_cli_exit_codes(self):
        tmp, root = make_tree({'a.txt': 'fine\n'})
        try:
            r = subprocess.run([sys.executable, str(HERE / 'check_tree.py'), '--root', str(root)],
                               capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertEqual(r.stdout.strip(), 'Tree is clean: 1 files checked.')
        finally:
            tmp.cleanup()
        tmp, root = make_tree({'android/key.properties': 'x\n'})
        try:
            r = subprocess.run([sys.executable, str(HERE / 'check_tree.py'), '--root', str(root)],
                               capture_output=True, text=True)
            self.assertEqual(r.returncode, 1)
            self.assertTrue(r.stdout.startswith('PROBLEM android/key.properties'))
        finally:
            tmp.cleanup()

    def test_gitignore_is_honoured_without_a_repository(self):
        _, problems = problems_for({
            '.gitignore': '/.release/\nkey.properties\n',
            '.release/secrets.txt': 'store' + 'Password' + '=abcdefgh12345678\n',
            'android/key.properties': 'x\n',
            'lib/a.dart': 'x\n',
        })
        self.assertEqual(problems, [])

    def test_the_plans_and_the_project_pass_the_text_rules(self):
        plans = PROJECT / 'docs' / 'superpowers' / 'plans'
        count, problems = check_tree.scan(PROJECT)
        bad = [p for p in problems if str(p.path).startswith('docs/')]
        self.assertEqual(bad, [], [str(p) for p in bad])
        self.assertTrue(plans.exists())


if __name__ == '__main__':
    unittest.main()
