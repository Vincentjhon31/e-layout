# e-Layout

e-Layout puts your office's layout (a footer, header or frame made of text, shapes, icons and logos) on a whole batch of photos and saves every photo at its full size. It is made by the Bongabong Public Information Office, Office of the Municipal Mayor, Municipality of Bongabong, Oriental Mindoro. It was called PIO Photo Layout before.

## Where to get it

Download the Android app or the Windows installer, or use the website version, at **https://pio.bongabong.gov.ph/** (downloads at `/download/`, the website version at `/app/`). The apps tell you when a new version is ready and install it for you.

## Privacy

Photos never leave the device. Adding photos, editing layouts and saving photos all work with no internet. Only checking for a new version and the extras that need the PIO website use the internet. Saved copies leave out the camera's hidden details, such as the GPS location.

## Run and build

One Flutter project (Flutter 3.44, Dart 3.12) makes all three versions.

```
flutter pub get
flutter run                                   # a phone, Windows or Chrome, whichever is connected
flutter build apk --release                   # build/app/outputs/flutter-apk/app-release.apk
flutter build windows --release               # build/windows/x64/runner/Release/
flutter build web --release --base-href /app/ # build/web/, the website version served at /app/
```

The Windows installer is made from the Windows build with Inno Setup 6:

```
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DMyAppVersion=1.0.0 windows\installer\e-layout.iss
```

The result is `installer_output/e-layout-1.0.0-setup.exe`. In Git Bash put `MSYS_NO_PATHCONV=1` in front of the web build and ISCC commands, or Git Bash rewrites their `/` options.

### Windows app and website version

- **Windows:** `flutter build windows --release` makes `build/windows/x64/runner/Release/` (run `pio_photo_layout.exe`). The window opens at 1280x800 (smallest 900x620). "Save photos" asks for a folder and never overwrites a file in it (`name (2).jpg`); "Add a folder" adds every photo in a folder and its subfolders. Photos or a folder can be dropped on the window, and a layout file or a picture dropped on the layout row becomes a layout. Editor keys: arrows nudge (Shift for 10), Ctrl+Z / Ctrl+Y (or Ctrl+Shift+Z) undo and redo, Delete removes, Ctrl+D duplicates, Ctrl+A selects all, Ctrl+G / Ctrl+Shift+G group and ungroup, Esc steps out of the selection, Shift+click adds to the selection, Ctrl+scroll zooms and scroll pans.
- **Website:** `flutter build web --release --base-href /app/` (the plain JavaScript build, which is also what the release workflow builds; the `--wasm` build was not tried) makes `build/web/`, which the site serves at `/app/`. Several photos are saved as one ZIP, one photo downloads directly, and layouts and added fonts are kept in the browser's IndexedDB. To look at it locally, copy `build/web` to a folder named `app` inside a folder you serve (`python -m http.server 8765 --directory <that folder>`) and open `http://localhost:8765/app/`.
- **Self-test of the website's storage and saving speed:** `tool/web_selftest/` is a small page, not part of the app. Build and run it (needs Chrome or Edge):

  ```
  flutter build web --release --target tool/web_selftest/main.dart --output build/selftest --base-href /selftest/
  python tool/web_selftest/run.py
  ```

  The first browser run saves a layout and a font in IndexedDB and times one 4000x3000 photo with the PIO footer; a second run of a new browser process with the same profile folder must read both back. On the development computer one photo took about 3.4 seconds. (`flutter test --platform chrome` does not start here, which is why this is a page.)

A release APK is signed with the upload key named in `android/key.properties` (see `RELEASE_GUIDE.md`); without that file the debug key is used, and such an APK cannot be updated by a release.

The app icon is drawn by `python tool/make_icon.py` (needs Pillow), which also writes every Android, Windows and web icon.

## Project layout

| Folder | What is in it |
|---|---|
| `lib/core` | The layout engine: model, rendering, saving. No platform code. |
| `lib/features` | The screens: home, viewer, editor, fonts, About and What's new. |
| `lib/platform` | One file per platform (`*_io.dart`, `*_web.dart`): saving, sharing, picking photos, installing updates. |
| `lib/online` | Everything that uses the internet. The photo path never imports it (tests check). |
| `hostinger/` | The PIO website: landing page, download page, small PHP API. Its own `README.md` says how to put it on the hosting. |
| `scripts/` | Release scripts (versions, What's new, publishing, signing keys). |
| `tool/` | Developer tools (icon, site images and screenshots, the check for private files). |
| `assets/` | Office layouts, fonts, pictures and the What's new notes. |

## Tests

```
flutter analyze
flutter test                                  # long: allow 20 minutes
python hostinger/tests/run_tests.py           # the website's PHP API and pages (needs PHP 8)
python tool/test_site_tools.py
python tool/test_check_tree.py
python scripts/test_release_scripts.py
python tool/check_tree.py                     # no secrets, keys or private photos in the files
```

## Add an office layout

1. Export the layout from the app (Layouts, "Share layout file") as `<name>.layout.json`.
2. Copy it into `assets/layouts/`.
3. Add a line `{ "file": "<name>.layout.json" }` to `assets/layouts/layouts.json`.
4. Run the app again. Office layouts show "Office layout" on their card.

## Releases

See `RELEASE_GUIDE.md`. In short: write the notes in `assets/whats_new.md`, run `python scripts/bump_version.py x.y.z`, test, commit, push a tag such as `v1.0.1+2`, and GitHub Actions builds and publishes everything.

## The website

See `hostinger/README.md`.

## Licence

No licence file has been chosen yet: that is the owner's call for public municipal code. The bundled fonts keep their own open licences (in `assets/fonts/licenses/`).
