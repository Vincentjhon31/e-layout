# Review 1: findings and outcomes (2026-11-15)

## 1. HIGH: root DirectoryIndex hid api/index.php (403 on /api/)
Outcome: fixed. Root .htaccess now has `DirectoryIndex index.html index.php`.
Test: hostinger/tests/run_tests.py "the root .htaccess lists index.php so /api/ runs api/index.php" (failed first). Confirmed with Apache 2.4 (scratch config, XAMPP config untouched, stopped afterwards): /api/ answers 200 with the fix. README step 8/9 now says to re-open /api/ after the root .htaccess upload; plan Task 26 Step 6 checks /api/ and /admin/ with the root .htaccess in place.

## 2. MEDIUM/HIGH: upload secret readable if private/.htaccess is missed
Outcome: fixed.
(a) require_release_secret answers 503 "uploads are off" unless private/.htaccess exists (test: "uploads are off (503) when private/.htaccess is missing, even with the right secret", plus health check release_uploads false and "works again once back").
(b) Secret now in private/release-upload-secret.php (`<?php return '...';`); old .txt read only as fallback (tests: .php secret, "requesting the secret .php file shows no secret", ".txt fallback"). read_release_secret() is in api/_lib.php.
(c) Root .htaccess: `RedirectMatch 404 ^/private(/|$)` (test on the file text; Apache 2.4 with private/.htaccess removed gave 404 for /private/ and the secret file).
README, RELEASE_GUIDE, api-config example, scripts/test_release_scripts.py and plan (Tasks 22 spec, 26) updated.

## 3. LOW: usleep, health check
Outcome: fixed. usleep removed (test: wrong secret answered under 0.4 s). Health shows `php_8_1_or_newer` instead of the version (test). Marker is rewritten every time; any 200 means not protected; the self-check result is cached 5 minutes in private/protected-check-result.json.

## 4. LOW: windows and web jobs race on the same release
Outcome: fixed. web job `needs: [prepare, android, windows]` with `if: always() && needs.android.result == 'success'` (still runs if Windows failed); publish-site unchanged. YAML parses. Not run on GitHub.
