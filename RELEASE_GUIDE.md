# Releasing a new version of e-Layout

A release is made by GitHub Actions when you push a tag such as `v1.0.1+2`. It builds the Android app, the Windows installer and the website zip, puts them on a GitHub Release, and puts the Android and Windows files on the download page, where the apps look for updates.

## Every release

1. **Write the notes.** Add a `## x.y.z` section at the top of `assets/whats_new.md` (the same version as below, without the `+build`) with short plain bullets that start with `- `. They are shown to everyone in the app and on the download page, so say what people will notice, and never mention servers, hosting, keys or other inner workings. The release stops with a message if a section is missing or uses such words.
2. **Set the version.** `python scripts/bump_version.py x.y.z` changes `pubspec.yaml` and `lib/app_info.dart` and raises the build number by one. It prints the tag to use.
3. **Test.** `flutter analyze` and `flutter test` must both be clean. Also run `python tool/check_tree.py`, `python hostinger/tests/run_tests.py`, `python scripts/test_release_scripts.py`.
4. **Commit and push.** `git add -A`, `git commit -m "e-Layout x.y.z"`, `git push origin main`.
5. **Tag.** `git tag -a vX.Y.Z+N -m "e-Layout x.y.z"` then `git push origin vX.Y.Z+N`, using the tag from step 2.
6. **Watch.** `gh run watch` (or the Actions tab on GitHub). It takes about 15 to 25 minutes.
7. **Check.** The release has three files: `e-layout-x.y.z.apk`, `e-layout-x.y.z-setup.exe` and `e-layout-x.y.z-web.zip`. Open https://pio.bongabong.gov.ph/download/ and check the new version and its notes are listed.
8. **The website version.** Upload the contents of `e-layout-x.y.z-web.zip` into the site's `app/` folder (see `hostinger/README.md`). The workflow never changes the site's code by itself.

## One-time setup (already done once)

The workflow needs these in the repository settings (Settings, Secrets and variables, Actions):

| Name | Kind | What it is |
|---|---|---|
| `KEYSTORE_FILE` | secret | The Android upload key, as base64 text |
| `KEYSTORE_PASSWORD` | secret | Its password |
| `KEY_ALIAS` | secret | The key's name inside it (`upload`) |
| `KEY_PASSWORD` | secret | The key's password (the same as the store password) |
| `RELEASE_UPLOAD_SECRET` | secret | A long random value; the same text is in `private/release-upload-secret.txt` on the website. It lets the workflow put files on the download page. |
| `PUBLISH_TO_SITE` | variable | `true` once the website is set up; until then the release still succeeds, with its files on GitHub only |

Make the key and the values once with `python scripts/make_upload_key.py` (it writes `.release/upload-keystore.jks`, `.release/secrets.txt` and `android/key.properties`, none of which is ever committed), then set the secrets with `python scripts/set_github_secrets.py --repo Vincentjhon31/e-layout`. Turn publishing on with `gh variable set PUBLISH_TO_SITE --body true --repo Vincentjhon31/e-layout`.

**Back up the whole `.release` folder somewhere safe** (a USB drive kept in the office). Every release must be signed with the same key. If the key is lost, installed apps can never be updated again and everyone would have to uninstall and install fresh.

## When a step fails

| Message or step | What to do |
|---|---|
| "No What's new notes for x.y.z" or "mention internal details" | Fix `assets/whats_new.md` (step 1), commit, move the tag (below). |
| "The tag ... does not match" | Run step 2 again, commit, move the tag. |
| "Missing Android signing secrets" | Set the secrets (one-time setup). Never let CI sign with another key. |
| The tree check reports a problem | It names the file and kind (a key, a private photo, an email address); remove it, commit, move the tag. |
| Publishing fails with 403 | `RELEASE_UPLOAD_SECRET` differs from the website's `private/release-upload-secret.txt`. |
| Publishing fails with 503 | The website has no upload secret yet (`hostinger/README.md`). |
| Windows job fails | Android users still get their update; fix and run the Windows job again from the Actions tab. |

To move a tag after a fix: `gh release delete "vX.Y.Z+N" --yes --cleanup-tag` (if a release was made) or `git push --delete origin "vX.Y.Z+N"`, then `git tag -d "vX.Y.Z+N"` and tag again on the fixed commit.

The CI run does not run `flutter test` (the golden pictures were made on Windows and differ a little on the Linux runners), so run the tests yourself before tagging.
