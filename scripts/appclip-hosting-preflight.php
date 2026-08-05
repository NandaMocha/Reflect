<?php
/**
 * App Clip hosting preflight — Reflect
 *
 * Answers one question: can this cPanel host run the App Clip feedback
 * write endpoint described in docs/features/app-clip-plan.md?
 *
 * USAGE
 *   1. Upload this file to public_html/ on your domain.
 *   2. Open https://yourdomain.com/appclip-hosting-preflight.php in a browser.
 *   3. Read the verdict at the bottom.
 *   4. DELETE IT. It reports server paths and config; do not leave it public.
 *
 * It is read-only: it writes nothing, sends no data anywhere, and only makes
 * one harmless outbound request to Apple's public CloudKit endpoint.
 */

header('Content-Type: text/plain; charset=utf-8');

$checks = [];

/** Record a check result. $status: 'pass' | 'fail' | 'warn' */
function check(string $name, string $status, string $detail, string $why = ''): void {
    global $checks;
    $checks[] = compact('name', 'status', 'detail', 'why');
}

echo "App Clip hosting preflight — Reflect\n";
echo str_repeat('=', 60) . "\n\n";

// ---------------------------------------------------------------- 1. PHP
$phpOk = version_compare(PHP_VERSION, '7.4', '>=');
check(
    'PHP version',
    $phpOk ? 'pass' : 'fail',
    PHP_VERSION,
    $phpOk ? '' : 'Need 7.4+. Raise it in cPanel > Select PHP Version.'
);

// ------------------------------------------------------------ 2. openssl
if (!extension_loaded('openssl')) {
    check('openssl extension', 'fail', 'not loaded',
        'Required to sign CloudKit requests. Enable in cPanel > Select PHP Version > Extensions.');
} else {
    check('openssl extension', 'pass', OPENSSL_VERSION_TEXT);

    // CloudKit server-to-server keys are ECDSA on prime256v1, signed SHA-256.
    // Generate a throwaway key and round-trip a signature to prove the whole
    // path works — extension present is not the same as curve supported.
    $curves = openssl_get_curve_names() ?: [];
    $hasCurve = in_array('prime256v1', $curves, true);
    check(
        'prime256v1 (P-256) curve',
        $hasCurve ? 'pass' : 'fail',
        $hasCurve ? 'available' : 'NOT available',
        $hasCurve ? '' : 'CloudKit server-to-server keys require this curve.'
    );

    if ($hasCurve) {
        $key = openssl_pkey_new([
            'private_key_type' => OPENSSL_KEYTYPE_EC,
            'curve_name'       => 'prime256v1',
        ]);

        if ($key === false) {
            check('ECDSA sign/verify round-trip', 'fail', 'key generation failed',
                'openssl is present but cannot create EC keys on this host.');
        } else {
            $payload = 'reflect-appclip-preflight';
            $sig = '';
            $signed = openssl_sign($payload, $sig, $key, OPENSSL_ALGO_SHA256);
            $verified = $signed && openssl_verify($payload, $sig, openssl_pkey_get_details($key)['key'], OPENSSL_ALGO_SHA256) === 1;

            check(
                'ECDSA sign/verify round-trip',
                $verified ? 'pass' : 'fail',
                $verified ? 'signed and verified with SHA-256' : 'FAILED',
                $verified ? '' : 'This is exactly what signing a CloudKit request does.'
            );
        }
    }
}

// -------------------------------------------------------------- 3. HTTPS
$isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
    || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https')
    || (($_SERVER['SERVER_PORT'] ?? '') === '443');
check(
    'This page served over HTTPS',
    $isHttps ? 'pass' : 'warn',
    $isHttps ? 'yes' : 'no — you loaded it over plain HTTP',
    $isHttps ? '' : 'Apple requires HTTPS for AASA and universal links. Retry over https:// before trusting this result.'
);

// ---------------------------------------------- 4. Outbound HTTPS to Apple
// The make-or-break check on cheap shared hosting: many plans block PHP
// from opening outbound connections, which makes a CloudKit proxy impossible.
$outboundDetail = '';
$outboundStatus = 'fail';

if (function_exists('curl_init')) {
    $ch = curl_init('https://api.apple-cloudkit.com/');
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 10,
        CURLOPT_CONNECTTIMEOUT => 5,
        CURLOPT_NOBODY         => true,
        CURLOPT_SSL_VERIFYPEER => true,
    ]);
    $body = curl_exec($ch);
    $errno = curl_errno($ch);
    $err = curl_error($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($errno === 0) {
        // Any HTTP status proves we reached Apple. 400/404 here is a PASS —
        // we only care that the connection was allowed and TLS verified.
        $outboundStatus = 'pass';
        $outboundDetail = "reached Apple (HTTP $code)";
    } else {
        $outboundDetail = "curl error $errno: $err";
    }
    check('cURL extension', 'pass', 'loaded');
} else {
    check('cURL extension', 'fail', 'not loaded',
        'Needed to call CloudKit Web Services. Enable it in cPanel > Select PHP Version.');
    $outboundDetail = 'cURL unavailable, could not test';
}

check(
    'Outbound HTTPS to api.apple-cloudkit.com',
    $outboundStatus,
    $outboundDetail,
    $outboundStatus === 'pass' ? '' : 'THE DEALBREAKER: if your host blocks outbound PHP connections, the write endpoint cannot work here at any price. Ask support to allow outbound HTTPS, or host the endpoint elsewhere (Cloudflare Worker / Vercel).'
);

// ------------------------------------- 5. A private dir outside public_html
$docRoot = rtrim($_SERVER['DOCUMENT_ROOT'] ?? '', '/');
$parent  = dirname($docRoot);
$looksLikePublicHtml = basename($docRoot) === 'public_html';
$parentWritable = $parent && is_dir($parent) && is_writable($parent);

check(
    'Directory above public_html for the private key',
    $parentWritable ? 'pass' : 'warn',
    "document root: $docRoot\n           parent:        $parent\n           parent writable: " . ($parentWritable ? 'yes' : 'no'),
    $parentWritable
        ? "Store the CloudKit .pem here, NOT under $docRoot."
        : 'Could not confirm a writable dir above the web root. You can still use cPanel File Manager to place the key there, or block it with .htaccess as a fallback.'
);

if (!$looksLikePublicHtml) {
    check('Document root layout', 'warn', basename($docRoot),
        'Document root is not named public_html — confirm which directory is web-reachable before choosing where the key lives.');
}

// ------------------------------------------------- 6. AASA path reachability
// Checked from outside via curl, but flag the common cPanel cause early.
$wellKnown = $docRoot . '/.well-known';
check(
    '.well-known directory',
    is_dir($wellKnown) ? 'pass' : 'warn',
    is_dir($wellKnown) ? 'exists' : 'does not exist yet',
    is_dir($wellKnown)
        ? ''
        : 'Expected — you have not created it yet. Create it at ' . $wellKnown . ' and put the AASA file inside, then run the curl check in the notes below.'
);

check(
    'allow_url_fopen',
    ini_get('allow_url_fopen') ? 'pass' : 'warn',
    ini_get('allow_url_fopen') ? 'on' : 'off',
    ini_get('allow_url_fopen') ? '' : 'Not required — cURL is the preferred path anyway.'
);

// ------------------------------------------------------------- Report
$pad = 0;
foreach ($checks as $c) { $pad = max($pad, strlen($c['name'])); }

$fails = 0;
$warns = 0;
foreach ($checks as $c) {
    $icon = ['pass' => '[ OK ]', 'fail' => '[FAIL]', 'warn' => '[WARN]'][$c['status']];
    if ($c['status'] === 'fail') { $fails++; }
    if ($c['status'] === 'warn') { $warns++; }

    printf("%s %-{$pad}s  %s\n", $icon, $c['name'], $c['detail']);
    if ($c['why'] !== '') {
        echo str_repeat(' ', 8) . '-> ' . wordwrap($c['why'], 68, "\n" . str_repeat(' ', 11), false) . "\n";
    }
    echo "\n";
}

echo str_repeat('=', 60) . "\n";
if ($fails === 0) {
    echo "VERDICT: This host can run the App Clip write endpoint.\n";
    if ($warns > 0) {
        echo "         ($warns warning(s) above — read them, none are blocking.)\n";
    }
} else {
    echo "VERDICT: $fails blocking problem(s). See [FAIL] lines above.\n";
    echo "         If the only failure is outbound HTTPS, the fix is to host\n";
    echo "         the endpoint on Cloudflare Workers or Vercel instead and\n";
    echo "         keep this domain purely for the AASA file.\n";
}
echo str_repeat('=', 60) . "\n\n";

echo "STILL TO CHECK FROM YOUR MAC (not testable from inside PHP):\n\n";
echo "  # AASA must return 200, no redirect, JSON content-type.\n";
echo "  # Apple's fetcher does NOT follow redirects.\n";
echo "  curl -sSI https://yourdomain.com/.well-known/apple-app-site-association\n\n";
echo "  # Confirm no forced www/https redirect on that exact path:\n";
echo "  curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\\n' \\\n";
echo "    https://yourdomain.com/.well-known/apple-app-site-association\n\n";
echo "NOW DELETE THIS FILE FROM THE SERVER.\n";
