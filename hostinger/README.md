# e-Layout site: upload guide for pio.bongabong.gov.ph

This folder is the **website for e-Layout**: the landing page, the download page, and a small PHP API that receives each release from GitHub and counts downloads. No database, no XAMPP, no MySQL: Hostinger already runs PHP.

Everything goes **inside the pio subdomain's own folder** (the folder that holds today's `index.html` and `app.html`):

```
hostinger/public_html/index.html       -> pio/index.html          (landing page, replaces the old one)
hostinger/public_html/favicon.ico      -> pio/favicon.ico
hostinger/public_html/.htaccess        -> pio/.htaccess           (see "The old browser tool" first)
hostinger/public_html/landing/         -> pio/landing/
hostinger/public_html/download/        -> pio/download/           (download page; also holds the releases)
hostinger/public_html/api/             -> pio/api/
hostinger/private/                     -> pio/private/            (settings and secrets, closed to the web)
the website version of the app         -> pio/app/                (from a release's e-layout-<version>-web.zip)
hostinger/tests/                       -> do NOT upload (local tests for developers)
```

The site map once everything is up:

| Address | What |
|---|---|
| `/` | Landing page with the live demo and the downloads |
| `/download/` | Download page, every version's "What's new" |
| `/download/latest.json`, `releases.json`, `files/` | Written only by `api/releases.php` (never edit by hand) |
| `/app/` | The website version of e-Layout |
| `/api/` | Health check, `releases.php`, `download.php` |
| `/private/` | Never reachable from the web |
| `/app.html`, `/css/`, `/js/`, `/fonts/`, `/img/`, `/layouts/` | The classic browser tool, left exactly as it is |

## The old browser tool: never delete it

The old PIO Photo Layout is live today at `/app.html`. **Leave `app.html` and the folders `css/`, `js/`, `fonts/`, `img/` and `layouts/` alone**: saved links keep working, and layouts saved in that browser stay reachable (they live in the browser, under this same address). The new landing page only replaces `index.html`.

The landing page explains how to move layouts from the classic version to e-Layout (export in the classic version, import in e-Layout). When the owner decides to retire the classic version, remove the `#` in front of the `RedirectMatch` line in `.htaccess`; until then leave it.

## One-time setup (hPanel File Manager)

1. **Open the subdomain's folder.** hPanel, Files, File Manager, open the folder of `pio.bongabong.gov.ph` (the one with `app.html` in it). Turn on **Show hidden files** (File Manager settings): the `.htaccess` files are hidden and they matter.
2. **Back up first.** Select everything in that folder, **Compress** it into a zip and download the zip. Keep it until the new site has been checked.
3. **Create the private folder.** Create a folder **`private`**. Upload `hostinger/private/.htaccess`, `hostinger/private/index.php` and `hostinger/private/api-config.example.php` into it. Rename `api-config.example.php` to **`api-config.php`**. It is already filled in for `pio.bongabong.gov.ph`; nothing in it is secret.
   **`private/.htaccess` is what keeps the settings and the upload secret from being opened in a browser. Do not skip it.**
4. **Upload the API.** Create a folder **`api`** and upload every file from `hostinger/public_html/api/`, including the hidden **`.htaccess`**.
5. **Upload the download page.** Create a folder **`download`** and upload everything from `hostinger/public_html/download/`, including the hidden **`.htaccess`**.
6. **Upload the landing page.** Upload the `landing/` folder, `favicon.ico`, the root `.htaccess`, and **last** `index.html` (it replaces the old front page). Tip: zip the folders on your computer, upload the zip and use File Manager's **Extract**. `python tool/site_bundle.py --app-dir <web build> --out build/site_bundle` makes exactly this folder (and a zip of it) for you; it never uploads anything.
7. **PHP settings.** hPanel, Advanced, **PHP Configuration**: PHP version **8.1 or newer**; extensions **gd**, **fileinfo** and **curl** on (usually already); **upload_max_filesize** and **post_max_size** at least **16M**.
8. **Check it.** Open **https://pio.bongabong.gov.ph/api/**. You should see something like:
   ```json
   {"ok":true,"service":"e-Layout site API","gd":true,"curl":true,"fileinfo":true,
    "download_writable":true,"release_uploads":false,"private_protected":true,...}
   ```
   - **`private_protected` must be `true`.** The API tries to open a test file in `private/` the way a stranger would; `true` means it was blocked. `false` means `private/.htaccess` is missing: upload it before anything else.
   - `null`: open **https://pio.bongabong.gov.ph/private/protected-check.txt** yourself. It must show **403 Forbidden**, not text.
   - `download_writable` `false`: set the `download` folder's permissions to **755** (right-click, Permissions).
   - `release_uploads` is `false` until you do "App downloads" below.
9. Open **https://pio.bongabong.gov.ph/** and **https://pio.bongabong.gov.ph/download/**. Before the first release the download page says "The first download will appear here soon." Also open **https://pio.bongabong.gov.ph/app.html** to see that the classic tool still works.

## Never delete

- `api/`, `private/` and `download/`. **Deleting `download/` deletes every released app file and the version lists; deleting `private/` deletes the settings, the upload secret and the download counts.**
- The classic tool: `app.html`, `css/`, `js/`, `fonts/`, `img/`, `layouts/`.
- **Never use "delete all and re-upload"** on the folder. If you must clear something, download `download/` and `private/` first and put them back.

## App downloads (`download/`)

**https://pio.bongabong.gov.ph/download/** is where people download the Android and Windows apps, and where the apps check for updates (`download/latest.json`). The release workflow fills it: when a version tag is pushed on GitHub, it uploads the APK and the Windows installer through `api/releases.php` and rewrites `download/releases.json` (every version and its "What's new" notes) and `download/latest.json` (the newest per platform). Only the newest three versions keep their files; every version keeps its notes.

`api/releases.php` has its **own secret**, separate from everything else on the hosting account, and can only write inside `download/`. Without the secret file, uploads are switched off.

1. Make a long random secret (at least 32 characters), for example with `python -c "import secrets; print(secrets.token_urlsafe(48))"`.
2. Put it, alone on one line, in a new file **`pio/private/release-upload-secret.txt`**.
3. Put the **same value** in the GitHub repository: Settings, Secrets and variables, Actions, new repository secret named **`RELEASE_UPLOAD_SECRET`**.
4. Add the repository **variable** `PUBLISH_TO_SITE` with the value `true` (Settings, Secrets and variables, Actions, Variables). Without it the release workflow only prints a warning and the release still succeeds, with its files on GitHub.
5. Open `/api/`: `release_uploads` is now `true`.

To put an existing version on the page without a new release, run from the repository folder with the secret in `RELEASE_UPLOAD_SECRET` and the tag in `GITHUB_REF_NAME` (for example `v1.0.0+1`):

```
python scripts/publish_release.py android e-layout-1.0.0.apk
python scripts/publish_release.py windows e-layout-1.0.0-setup.exe
```

If the secret ever leaks, replace the value in both places; the old one stops working at once.

## Uploading a new website version (`app/`)

The website version of e-Layout is a Flutter web build made with `--base-href /app/`. Each release attaches it as **`e-layout-<version>-web.zip`**. It is not published automatically, so a leaked upload secret can never change the site's code.

1. Download `e-layout-<version>-web.zip` from the GitHub release and unzip it on your computer.
2. In File Manager open `pio/app/` (create it the first time) and upload the unzipped files, replacing the ones that are there. **Keep `app/.htaccess`** if it exists; the web build ships its own.
3. Touch nothing outside `app/`. In particular never delete `api/`, `private/` or `download/`.
4. Open **https://pio.bongabong.gov.ph/app/**. It must start e-Layout. People who already have it open are offered a reload.

## Moving the gallery data outside the website

(Filled in with the online templates feature; nothing to do yet.)

## Troubleshooting

| What you see | Likely cause |
|---|---|
| `api-config.php is missing` | Step 3: the file must be at `pio/private/api-config.php`. |
| `"private_protected": false` | `private/.htaccess` was not uploaded (hidden file). Upload it, then check again. |
| `"release_uploads": false` | `private/release-upload-secret.txt` is missing or shorter than 32 characters. |
| The release fails at "Publish" with 503 | Same: the secret file is missing or too short. |
| ... with 403 | The GitHub secret `RELEASE_UPLOAD_SECRET` does not match the file on the server. |
| ... with 409 "does not match its size and checksum" | The upload was cut off. Run the release's publish step again. |
| `download_writable` is `false`, or a release can't save its files | `download/` permissions (755). |
| The download page says the list couldn't be loaded | `download/releases.json` was deleted. Run the release's publish step again, or publish the current files as shown above. |
| The download page says "The first download will appear here soon." | No release has been published yet. |
| The landing page's buttons go to the download page instead of the file | `download/latest.json` is missing. It appears with the first published release. |
| `/app/` shows a blank page or "not found" | The web build was not uploaded into `app/`, or it was built without `--base-href /app/`. |
| Layouts from the classic tool are gone | Open `/app.html` in the same browser as before: layouts live in the browser, and the classic tool was never changed. |

## Testing locally (developers)

```
python hostinger/tests/run_tests.py       the API, the counter, the health check and the two pages
python tool/test_site_tools.py            the bundle tool
python tool/site_screenshots.py           screenshots in build/site_screens/ (light and dark, phone and desktop)
python tool/site_copy_demo.py --check     the landing page's demo copies match the old tool
python tool/site_images.py                remakes the icons, og image and phone screens from the app's artwork
```

The test run needs PHP 8 with gd, curl and fileinfo on PATH. It copies the site into a temporary folder laid out like the server and starts PHP's built-in server. That server ignores `.htaccess` files, so those rules (no folder listings, `private/` closed, no scripts in `download/`) are only active on Hostinger, and the health check correctly reports `private_protected: false` there. Nothing is uploaded and no real secret is involved.
