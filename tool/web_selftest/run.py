"""Runs the web self-test in headless Chrome, twice with the same profile folder.

  flutter build web --release --target tool/web_selftest/main.dart --output build/selftest --base-href /selftest/
  python tool/web_selftest/run.py

It serves build/selftest at http://localhost:8765/selftest/ , opens
?phase=save and then ?phase=load in a headless Chrome that keeps one
--user-data-dir, and prints the "RESULT ..." line each page puts in its title.
The second run only sees the layout and the font if IndexedDB kept them
between two Chrome processes. Needs Chrome (or Edge) installed.
"""
import http.server
import json
import os
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
BUILD = os.path.join(ROOT, 'build', 'selftest')
PORT = 8765
DEBUG_PORT = 9333


def find_browser():
    for base in (os.environ.get('ProgramFiles'), os.environ.get('ProgramFiles(x86)'), os.environ.get('LOCALAPPDATA')):
        if not base:
            continue
        for rel in (('Google', 'Chrome', 'Application', 'chrome.exe'), ('Microsoft', 'Edge', 'Application', 'msedge.exe')):
            path = os.path.join(base, *rel)
            if os.path.exists(path):
                return path
    return shutil.which('chrome') or shutil.which('msedge')


def serve():
    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *a, **k):
            super().__init__(*a, directory=os.path.dirname(BUILD), **k)

        def log_message(self, *a):
            pass

    server = socketserver.TCPServer(('127.0.0.1', PORT), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def run_once(browser, profile, phase, wait=180):
    proc = subprocess.Popen([
        browser, '--headless=new', '--disable-gpu', f'--user-data-dir={profile}',
        f'--remote-debugging-port={DEBUG_PORT}', '--window-size=1280,800',
        f'http://localhost:{PORT}/selftest/?phase={phase}',
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    result = None
    try:
        end = time.time() + wait
        while time.time() < end and result is None:
            time.sleep(1)
            try:
                pages = json.load(urllib.request.urlopen(f'http://127.0.0.1:{DEBUG_PORT}/json', timeout=3))
            except Exception:
                continue
            for page in pages:
                title = page.get('title', '')
                if title.startswith('RESULT') and '...)' not in title:
                    result = title
    finally:
        subprocess.run(['taskkill', '/F', '/T', '/PID', str(proc.pid)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        proc.wait()
    return result


def main():
    browser = find_browser()
    if not browser or not os.path.isdir(BUILD):
        print('Need Chrome or Edge and build/selftest (see this file).', file=sys.stderr)
        return 2
    server = serve()
    profile = tempfile.mkdtemp(prefix='elayout-selftest-')
    ok = True
    try:
        for phase in ('save', 'load'):
            result = run_once(browser, profile, phase)
            print(result or f'RESULT phase={phase} no answer')
            ok = ok and bool(result) and ' FAIL' not in result and 'OK' in result
            time.sleep(1)
    finally:
        server.shutdown()
        shutil.rmtree(profile, ignore_errors=True)
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
