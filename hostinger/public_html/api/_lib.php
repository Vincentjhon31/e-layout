<?php
// Shared helpers for the e-Layout site API (pio.bongabong.gov.ph/api/).
// Not a page: every endpoint in this folder requires it, and api/.htaccess
// refuses to serve it.
//
// The API keeps no database. It stores the app's release files and two JSON
// lists in download/, and a few counters in private/. Its settings live in
// private/api-config.php, inside the site's own folder (a subdomain's folder
// cannot have anything outside it).

declare(strict_types=1);

$configPath = __DIR__ . '/../private/api-config.php';
if (!is_file($configPath)) {
    http_response_code(500);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode(['error' => 'Server not configured: private/api-config.php is missing.']);
    exit;
}
require $configPath;

/** Whether a browser page at [$origin] may read the API's public answers. */
function origin_allowed(string $origin): bool
{
    if ($origin === '') {
        return false;
    }
    if (defined('ALLOWED_ORIGINS') && in_array($origin, (array) constant('ALLOWED_ORIGINS'), true)) {
        return true;
    }
    return false;
}

/** CORS for the browser-based callers (the website version of the app). */
function cors(): void
{
    $origin = $_SERVER['HTTP_ORIGIN'] ?? '';
    if (is_string($origin) && origin_allowed($origin)) {
        header('Access-Control-Allow-Origin: ' . $origin);
        header('Vary: Origin');
        header('Access-Control-Allow-Headers: Content-Type');
        header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
        header('Access-Control-Max-Age: 86400');
    }
    if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
        http_response_code(204);
        exit;
    }
}

function json_out($data, int $status = 200): void
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    header('X-Content-Type-Options: nosniff');
    echo json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

function fail(string $message, int $status = 400): void
{
    json_out(['error' => $message], $status);
}

function ensure_dir(string $dir): void
{
    if (!is_dir($dir) && !mkdir($dir, 0755, true) && !is_dir($dir)) {
        fail('The server could not create a storage folder.', 500);
    }
}

/** Writes [$data] as JSON to [$path] without a half-written moment. */
function write_json_atomically(string $path, array $data): void
{
    $temp = $path . '.tmp';
    $json = json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
    if ($json === false || file_put_contents($temp, $json) === false || !rename($temp, $path)) {
        @unlink($temp);
        fail('The server could not save the release list.', 500);
    }
}

// ---------- App downloads (download/ folder, see releases.php) ----------

// e-layout-X.Y.Z.apk (Android) or e-layout-X.Y.Z-setup.exe (Windows): the
// only files the download folder ever holds. The D modifier matters: without
// it "$" also matches before a trailing newline.
const RELEASE_FILE_PATTERN = '/^e-layout-(\d{1,3}\.\d{1,3}\.\d{1,4})(\.apk|-setup\.exe)$/D';
const RELEASE_PLATFORMS = ['android' => '.apk', 'windows' => '-setup.exe'];

function download_dir(): string
{
    return defined('DOWNLOAD_DIR') ? (string) constant('DOWNLOAD_DIR') : __DIR__ . '/../download';
}

function download_public_url(): string
{
    if (defined('DOWNLOAD_PUBLIC_URL')) {
        return rtrim((string) constant('DOWNLOAD_PUBLIC_URL'), '/');
    }
    return (string) preg_replace('#/api/?$#', '/download', rtrim(API_PUBLIC_URL, '/'));
}

/** [version, platform] for a valid release file name, else stops. */
function parse_file_name(string $name): array
{
    if (!preg_match(RELEASE_FILE_PATTERN, $name, $m)) {
        fail('Not a release file name.', 400);
    }
    return [$m[1], $m[2] === '.apk' ? 'android' : 'windows'];
}

/**
 * The upload secret: private/release-upload-secret.php ("<?php return '...';",
 * so a web request shows nothing), or the older private/release-upload-secret.txt
 * as a fallback. '' when there is none.
 */
function read_release_secret(): string
{
    $php = PRIVATE_DIR . '/release-upload-secret.php';
    if (is_file($php)) {
        $value = (static fn () => include $php)();
        return is_string($value) ? trim($value) : '';
    }
    $txt = PRIVATE_DIR . '/release-upload-secret.txt';
    return is_file($txt) ? trim((string) file_get_contents($txt)) : '';
}
