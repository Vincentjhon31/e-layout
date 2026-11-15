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
$releaseUploads = is_file(PRIVATE_DIR . '/.htaccess') && strlen(read_release_secret()) >= 32;

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
    @file_put_contents($file, $marker);
    $ch = curl_init(rtrim((string) constant('PRIVATE_PUBLIC_URL'), '/') . '/protected-check.txt');
    curl_setopt_array($ch, [CURLOPT_RETURNTRANSFER => true, CURLOPT_CONNECTTIMEOUT => 5, CURLOPT_TIMEOUT => 8]);
    $body = curl_exec($ch);
    $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);
    if ($body === false || $status === 0) {
        return null;
    }
    return $status !== 200; // any 200 answer means a stranger can read the folder
}

// The self-check calls this site's own address, so remember the answer for 5 minutes.
$cacheFile = PRIVATE_DIR . '/protected-check-result.json';
$cached = is_file($cacheFile) ? json_decode((string) file_get_contents($cacheFile), true) : null;
if (is_array($cached) && isset($cached['at']) && time() - (int) $cached['at'] < 300 && array_key_exists('value', $cached)) {
    $protected = $cached['value'];
} else {
    $protected = private_folder_protected();
    @file_put_contents($cacheFile, json_encode(['at' => time(), 'value' => $protected]));
}
$result = [
    'ok' => true,
    'service' => 'e-Layout site API',
    'php_8_1_or_newer' => version_compare(PHP_VERSION, '8.1.0', '>='),
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
