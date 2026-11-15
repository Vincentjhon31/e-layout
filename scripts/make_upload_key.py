"""Makes the Android upload key that signs every e-Layout release (run once).

    python scripts/make_upload_key.py            make the key
    python scripts/make_upload_key.py --verify   show the key's alias, validity and public fingerprint

Writes, all of them ignored by git:
  .release/upload-keystore.jks   the key (PKCS12)
  .release/secrets.txt           NAME=value lines: KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD,
                                 RELEASE_UPLOAD_SECRET
  android/key.properties         lets "flutter build apk --release" sign with the key

It refuses to overwrite an existing keystore: a new key could never update apps that were
installed with the old one. Passwords are random, are never printed, and reach keytool only
through the child process's environment.
BACK UP THE WHOLE .release FOLDER somewhere safe.
"""
import os
import re
import secrets
import subprocess
import sys
from pathlib import Path

ROOT = Path(os.environ.get('ELAYOUT_ROOT') or Path(__file__).resolve().parent.parent)
RELEASE = ROOT / '.release'
KEYSTORE = RELEASE / 'upload-keystore.jks'
SECRETS = RELEASE / 'secrets.txt'
KEY_PROPERTIES = ROOT / 'android' / 'key.properties'
ALIAS = 'upload'
DNAME = ('CN=e-Layout, OU=Public Information Office, O=Municipality of Bongabong, '
         'L=Bongabong, ST=Oriental Mindoro, C=PH')

HEADER = """# e-Layout release secrets. NEVER commit or share this file.
# Back up this whole .release folder somewhere safe (a USB drive kept in the office, for
# example): without the key in upload-keystore.jks no new version can update the apps that
# are already installed.
"""


def read_secrets():
    values = {}
    if SECRETS.exists():
        for line in SECRETS.read_text(encoding='utf-8').splitlines():
            if line.strip() and not line.startswith('#') and '=' in line:
                k, v = line.split('=', 1)
                values[k.strip()] = v.strip()
    return values


def verify():
    values = read_secrets()
    if not KEYSTORE.exists() or 'KEYSTORE_PASSWORD' not in values:
        sys.exit('No key yet: run python scripts/make_upload_key.py first.')
    env = dict(os.environ, ELAYOUT_STOREPASS=values['KEYSTORE_PASSWORD'])
    r = subprocess.run(['keytool', '-list', '-v', '-keystore', str(KEYSTORE), '-alias', values.get('KEY_ALIAS', ALIAS),
                        '-storepass:env', 'ELAYOUT_STOREPASS'], capture_output=True, text=True, env=env)
    if r.returncode != 0:
        sys.exit('keytool could not read the key (wrong password?).')
    for line in r.stdout.splitlines():
        s = line.strip()
        if re.match(r'^(Alias name|Valid from|Owner|SHA256):', s):
            print(s)


def make():
    if KEYSTORE.exists():
        sys.exit('%s already exists. Not overwriting it: a new key could never update installed apps.' % KEYSTORE)
    if SECRETS.exists():
        sys.exit('%s already exists. Not overwriting it.' % SECRETS)
    RELEASE.mkdir(exist_ok=True)
    store_password = secrets.token_urlsafe(32)
    upload_secret = secrets.token_urlsafe(48)
    SECRETS.write_text(HEADER + 'KEYSTORE_PASSWORD=%s\nKEY_ALIAS=%s\nKEY_PASSWORD=%s\nRELEASE_UPLOAD_SECRET=%s\n'
                       % (store_password, ALIAS, store_password, upload_secret), encoding='utf-8', newline='\n')
    env = dict(os.environ, ELAYOUT_STOREPASS=store_password)
    r = subprocess.run(['keytool', '-genkeypair', '-keystore', str(KEYSTORE), '-storetype', 'PKCS12', '-alias', ALIAS,
                        '-keyalg', 'RSA', '-keysize', '4096', '-validity', '10000', '-dname', DNAME,
                        '-storepass:env', 'ELAYOUT_STOREPASS', '-keypass:env', 'ELAYOUT_STOREPASS'],
                       capture_output=True, text=True, env=env)
    if r.returncode != 0 or not KEYSTORE.exists():
        SECRETS.unlink(missing_ok=True)
        sys.exit('keytool failed: ' + (r.stderr or r.stdout).replace(store_password, '[hidden]')[-300:])
    KEY_PROPERTIES.write_text('storeFile=../../.release/upload-keystore.jks\nstorePassword=%s\nkeyAlias=%s\nkeyPassword=%s\n'
                              % (store_password, ALIAS, store_password), encoding='utf-8', newline='\n')
    print('Made %s, %s and %s (none is committed).' % (KEYSTORE.relative_to(ROOT), SECRETS.relative_to(ROOT),
                                                        KEY_PROPERTIES.relative_to(ROOT)))
    print('Back up the whole .release folder somewhere safe.')
    verify()


if __name__ == '__main__':
    if len(sys.argv) > 2 or (len(sys.argv) == 2 and sys.argv[1] != '--verify'):
        sys.exit('usage: make_upload_key.py [--verify]')
    verify() if len(sys.argv) == 2 else make()
