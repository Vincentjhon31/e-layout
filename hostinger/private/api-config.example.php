<?php
// Settings for the e-Layout site API (pio.bongabong.gov.ph).
//
// On Hostinger, copy this file to   private/api-config.php   (same folder),
// then check the web addresses below match your site. Nothing in here is
// secret. The release upload secret is NOT in this file: it is the one line in
// private/release-upload-secret.txt (see README.md, "App downloads").
//
// Layout (the subdomain's own folder, "pio"):
//   pio/
//     index.html, landing/, download/, api/, app/ ...
//     private/    <- this file, release-upload-secret.txt, download-counts.json
//
// private/ is inside the website, so it is protected by its .htaccess file.
// After uploading, open the API's address (.../api/) and check that
// "private_protected" says true.

// Where the folders are reachable from the internet.
const API_PUBLIC_URL = 'https://pio.bongabong.gov.ph/api';
// Used only by the health check, to confirm private/ can NOT be opened.
const PRIVATE_PUBLIC_URL = 'https://pio.bongabong.gov.ph/private';

// Folders on this server (normally left as they are).
const PRIVATE_DIR = __DIR__;
const DATA_DIR = __DIR__ . '/data';

// Websites allowed to read the API from a browser.
const ALLOWED_ORIGINS = ['https://pio.bongabong.gov.ph'];
