<?php
// Health check: open https://pio.bongabong.gov.ph/api/ in a browser after
// uploading. "ok" true means the API is ready. "private_protected" must be
// true: it confirms the private folder (settings, the upload secret, the
// counters) can't be opened from the web.

declare(strict_types=1);
require __DIR__ . '/_lib.php';
cors();

$downloadDir = download_dir();
$downloadWritable = is_dir($downloadDir) ? is_writable($downloadDir) : is_writable(dirname($downloadDir));
$secretFile = PRIVATE_DIR . '/release-upload-secret.txt';
$releaseUploads = is_file($secretFile) && strlen(trim((string) file_get_contents($secretFile))) >= 32;

/**
 * Tries to download a marker file from private/ over the web, the way a
 * stranger would. true = blocked (good), false = readable (NOT protected),
 * null = couldn't tell (e.g. the server can't reach its own address).
 */
function private_folder_protected(): ?bool
{
    if (!defined('PRIVATE_PUBLIC_URL') || !function_exists('curl_init')) {
        return null;
    }
    $marker = 'If you can read this from a browser, the private folder is NOT protected.';
    $file = PRIVATE_DIR . '/protected-check.txt';
    if (!is_file($file)) {
        @file_put_contents($file, $marker);
    }
    $ch = curl_init(rtrim((string) constant('PRIVATE_PUBLIC_URL'), '/') . '/protected-check.txt');
    curl_setopt_array($ch, [CURLOPT_RETURNTRANSFER => true, CURLOPT_CONNECTTIMEOUT => 5, CURLOPT_TIMEOUT => 8]);
    $body = curl_exec($ch);
    $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);
    if ($body === false || $status === 0) {
        return null;
    }
    return !($status === 200 && strpos((string) $body, $marker) !== false);
}

$protected = private_folder_protected();
$result = [
    'ok' => true,
    'service' => 'e-Layout site API',
    'php' => PHP_VERSION,
    'gd' => extension_loaded('gd'),
    'curl' => extension_loaded('curl'),
    'fileinfo' => extension_loaded('fileinfo'),
    'download_writable' => $downloadWritable,
    'release_uploads' => $releaseUploads,
    'private_protected' => $protected,
    'max_upload' => ini_get('upload_max_filesize'),
    'max_post' => ini_get('post_max_size'),
];
if ($protected === false) {
    $result['ok'] = false;
    $result['warning'] = 'The private folder can be opened from the web. Upload private/.htaccess (a hidden file) before anything else.';
} elseif ($protected === null) {
    $result['note'] = 'Could not check the private folder automatically. Open PRIVATE_PUBLIC_URL/protected-check.txt in a browser: it must show "403 Forbidden".';
}
json_out($result);
