<?php
/**
 * CloudKit write-path test — Reflect App Clip
 *
 * Proves the server can sign a CloudKit Web Services request and create a
 * record in the PUBLIC database. This is the exact mechanism the real
 * feedback endpoint (task 2.5) uses, so a pass here de-risks that task
 * before any Clip code exists.
 *
 * Why this is needed at all: App Clips cannot write to CloudKit, so guest
 * feedback must be written by a server holding a server-to-server key.
 * See docs/features/app-clip-plan.md.
 *
 * SETUP
 *   1. Generate the key pair and register the PUBLIC half in CloudKit
 *      Console > your container > Tokens & Keys > Server-to-Server Keys.
 *   2. Put the PRIVATE key outside the web root (see KEY_PATH below).
 *   3. Fill in KEY_ID below with the Key ID the Console gave you.
 *   4. Upload this file to the web root, open it in a browser, read the
 *      verdict, then DELETE IT.
 *
 * It creates one throwaway record and then deletes it again, leaving the
 * database as it found it.
 */

// ------------------------------------------------------------------ CONFIG

/** Key ID from CloudKit Console > Tokens & Keys > Server-to-Server Keys. */
const KEY_ID = 'PASTE_YOUR_KEY_ID_HERE';

/** Private key path. MUST be outside the web root. */
const KEY_PATH = '/home/sesirkel/nandamochammad.xyz/cloudkit-key.pem';

/** CloudKit container and environment. */
const CONTAINER   = 'iCloud.xyz.nandamochammad.Reflect';
const ENVIRONMENT = 'development';   // 'development' | 'production'

/** Record type to write. Auto-created in development on first write. */
const RECORD_TYPE = 'PendingClipFeedback';

// ------------------------------------------------------------------ OUTPUT

header('Content-Type: text/plain; charset=utf-8');
echo "CloudKit write-path test — Reflect App Clip\n";
echo str_repeat('=', 62) . "\n\n";

$failed = false;
function step(string $label, bool $ok, string $detail = '', string $fix = ''): bool {
    global $failed;
    printf("%s %s\n", $ok ? '[ OK ]' : '[FAIL]', $label);
    if ($detail !== '') {
        echo '        ' . str_replace("\n", "\n        ", trim($detail)) . "\n";
    }
    if (!$ok) {
        $failed = true;
        if ($fix !== '') {
            echo '        -> ' . wordwrap($fix, 66, "\n           ", false) . "\n";
        }
    }
    echo "\n";
    return $ok;
}

// ------------------------------------------------------------- PRECHECKS

if (KEY_ID === 'PASTE_YOUR_KEY_ID_HERE') {
    step('Key ID configured', false, '',
        'Edit this file and set KEY_ID to the value from CloudKit Console > Tokens & Keys.');
    exit;
}
// A Key ID is 64 hex characters. The public key is base64 and contains
// /, + or = — pasting that instead is an easy and costly mix-up, since
// CloudKit answers it with a generic AUTHENTICATION_FAILED.
$looksLikePublicKey = str_starts_with(KEY_ID, 'MF') || strpbrk(KEY_ID, '/+=') !== false;
$looksLikeKeyID     = (bool) preg_match('/^[0-9a-fA-F]{64}$/', KEY_ID);

if ($looksLikePublicKey) {
    step('Key ID configured', false, 'KEY_ID = ' . substr(KEY_ID, 0, 40) . '...',
        'That is your PUBLIC KEY, not the Key ID. The public key is what you paste INTO CloudKit Console; the Key ID is what the Console gives back afterwards. Find it in CloudKit Console > Tokens & Keys > Server-to-Server Keys - it is 64 hex characters with no /, + or =.');
    exit;
}
if (!$looksLikeKeyID) {
    step('Key ID configured', false, 'KEY_ID = ' . KEY_ID,
        'This does not look like a Key ID, which is exactly 64 hex characters. Copy it from CloudKit Console > Tokens & Keys > Server-to-Server Keys.');
    exit;
}
step('Key ID configured', true, 'KEY_ID = ' . KEY_ID);

if (!is_readable(KEY_PATH)) {
    step('Private key readable', false, 'path: ' . KEY_PATH,
        'Check the path and that the file is owned by your cPanel user with 0600 permissions. PHP runs as your user, so 0600 is readable by it.');
    exit;
}
step('Private key readable', true, 'path: ' . KEY_PATH);

// Confirm the key is genuinely outside the web root — a private key inside
// it is one permission change away from being publicly downloadable.
$docRoot = rtrim($_SERVER['DOCUMENT_ROOT'] ?? '', '/');
$keyReal = realpath(KEY_PATH) ?: KEY_PATH;
$insideWebRoot = $docRoot !== '' && str_starts_with($keyReal, $docRoot . '/');
step(
    'Private key is OUTSIDE the web root',
    !$insideWebRoot,
    "key:      $keyReal\nweb root: $docRoot",
    'The key is inside the web-served directory. Move it one level above the web root; only file permissions are protecting it right now.'
);

$pkey = openssl_pkey_get_private(file_get_contents(KEY_PATH));
if (!step('Private key parses as a valid EC key', $pkey !== false, '',
    'openssl could not read the key. Regenerate with: openssl ecparam -name prime256v1 -genkey -noout -out cloudkit-key.pem')) {
    exit;
}

$details = openssl_pkey_get_details($pkey);
$isEC = ($details['type'] ?? null) === OPENSSL_KEYTYPE_EC;
step('Key is EC / prime256v1', $isEC,
    'curve: ' . ($details['ec']['curve_name'] ?? 'unknown'),
    'CloudKit requires an ECDSA prime256v1 key.');

// ------------------------------------------------------- BUILD THE REQUEST

/**
 * Sign and send one CloudKit Web Services request.
 *
 * Apple's scheme: sign "<ISO8601 date>:<base64(sha256(body))>:<subpath>"
 * with ECDSA/SHA-256, then send the base64 signature alongside the date
 * and key ID. See "Authenticate Web Service Requests" in Apple's docs.
 */
function cloudkit_request(string $subpathOp, array $payload, $pkey): array {
    $subpath = '/database/1/' . CONTAINER . '/' . ENVIRONMENT . '/public/' . $subpathOp;
    $url     = 'https://api.apple-cloudkit.com' . $subpath;

    $body = json_encode($payload, JSON_UNESCAPED_SLASHES);
    $date = gmdate('Y-m-d\TH:i:s\Z');
    $hashedBody = base64_encode(hash('sha256', $body, true));

    $message = $date . ':' . $hashedBody . ':' . $subpath;

    $signature = '';
    if (!openssl_sign($message, $signature, $pkey, OPENSSL_ALGO_SHA256)) {
        return ['error' => 'openssl_sign failed'];
    }

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => $body,
        CURLOPT_TIMEOUT        => 20,
        CURLOPT_HTTPHEADER     => [
            'Content-Type: application/json',
            'X-Apple-CloudKit-Request-KeyID: ' . KEY_ID,
            'X-Apple-CloudKit-Request-ISO8601Date: ' . $date,
            'X-Apple-CloudKit-Request-SignatureV1: ' . base64_encode($signature),
        ],
    ]);
    $response = curl_exec($ch);
    $errno    = curl_errno($ch);
    $err      = curl_error($ch);
    $code     = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($errno !== 0) {
        return ['error' => "curl error $errno: $err"];
    }
    return ['code' => $code, 'body' => $response, 'decoded' => json_decode($response, true)];
}

// --------------------------------------------------------- CREATE A RECORD

$testName = 'preflight-' . bin2hex(random_bytes(8));

$create = cloudkit_request('records/modify', [
    'operations' => [[
        'operationType' => 'create',
        'record' => [
            'recordType' => RECORD_TYPE,
            'recordName' => $testName,
            'fields' => [
                'requestToken' => ['value' => 'preflight-token'],
                'questionId'   => ['value' => 'preflight-question'],
                'guestId'      => ['value' => 'preflight-guest'],
                'guestName'    => ['value' => 'Preflight'],
                'body'         => ['value' => 'Written by appclip-cloudkit-write-test.php'],
            ],
        ],
    ]],
], $pkey);

if (isset($create['error'])) {
    step('Create record in public DB', false, $create['error'],
        'The request never reached Apple. Check outbound HTTPS is permitted.');
    exit;
}

$createdOk = $create['code'] === 200
    && empty($create['decoded']['records'][0]['serverErrorCode']);

$detail = 'HTTP ' . $create['code'];
if (!$createdOk) {
    $detail .= "\n" . substr($create['body'], 0, 600);
}

$fix = '';
if ($create['code'] === 401) {
    $fix = 'Authentication rejected. The Key ID may not match the registered public key, or the key was registered on a different container. Re-check CloudKit Console > Tokens & Keys.';
} elseif ($create['code'] === 403) {
    $fix = 'Authorized but forbidden. Confirm the container identifier is correct and the server-to-server key belongs to it.';
} elseif ($create['code'] === 421) {
    $fix = 'Wrong environment. Try switching ENVIRONMENT between development and production.';
} elseif (!$createdOk) {
    $fix = 'See the response body above for the CloudKit error code.';
}

step('Create record in public DB', $createdOk, $detail, $fix);

// ------------------------------------------------------------- CLEAN UP

if ($createdOk) {
    $del = cloudkit_request('records/modify', [
        'operations' => [[
            'operationType' => 'forceDelete',
            'record' => ['recordName' => $testName],
        ]],
    ], $pkey);

    $deletedOk = !isset($del['error']) && $del['code'] === 200;
    step('Delete the test record (cleanup)', $deletedOk,
        isset($del['code']) ? 'HTTP ' . $del['code'] : ($del['error'] ?? ''),
        'The test record could not be removed. Delete "' . $testName . '" manually in CloudKit Console.');
}

// -------------------------------------------------------------- VERDICT

echo str_repeat('=', 62) . "\n";
if (!$failed) {
    echo "VERDICT: The server can sign and write to CloudKit.\n";
    echo "         Task 2.5's write path is proven end to end.\n";
    echo "         Record type '" . RECORD_TYPE . "' now exists in the\n";
    echo "         " . ENVIRONMENT . " schema - it must be deployed to\n";
    echo "         production as part of H4.\n";
} else {
    echo "VERDICT: Not working yet. See the [FAIL] lines above.\n";
}
echo str_repeat('=', 62) . "\n\n";
echo "NOW DELETE THIS FILE FROM THE SERVER (it contains your Key ID).\n";
