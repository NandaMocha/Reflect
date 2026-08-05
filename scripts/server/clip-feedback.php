<?php
/**
 * Clip guest-feedback write endpoint — Reflect App Clip (ticket AC-015).
 *
 * Production version of the proven spike at
 * scripts/appclip-cloudkit-write-test.php: signs and calls CloudKit Web
 * Services with a server-to-server key to create/update `PendingClipFeedback`
 * public records on the guest's behalf, since the App Clip itself cannot
 * write to CloudKit. See docs/features/app-clip-plan.md ("Write path") and
 * docs/features/app-clip-tasks.md (ticket AC-015).
 *
 * Request:
 *   POST / (JSON body)
 *   {
 *     "requestToken": "...",
 *     "guestId": "...",
 *     "guestName": "...",
 *     "answers": [
 *       {"questionId": "...", "submissionId": "...", "body": "..."},
 *       ...
 *     ]
 *   }
 *
 * Response (success): HTTP 200
 *   {"ok": true, "submitted": ["<submissionId>", ...]}
 *
 * Response (error): structured JSON, see `fail()` below. Never echoes the
 * Key ID, key path, or any other server-only config.
 *
 * Server-verified against Development in AC-H2, not here.
 */

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');

// ---------------------------------------------------------------- HELPERS

/** Emit a structured JSON error and stop. Never include server-only config. */
function fail(int $httpCode, string $code, string $message): never {
    http_response_code($httpCode);
    echo json_encode(['ok' => false, 'error' => $code, 'message' => $message], JSON_UNESCAPED_SLASHES);
    exit;
}

/**
 * Sign and send one CloudKit Web Services request.
 *
 * Same scheme as scripts/appclip-cloudkit-write-test.php: sign
 * "<ISO8601 date>:<base64(sha256(body))>:<subpath>" with ECDSA/SHA-256,
 * send the signature/date/key-id as headers. See "Authenticate Web Service
 * Requests" in Apple's CloudKit Web Services docs.
 */
function cloudkit_request(string $subpathOp, array $payload, $pkey, array $config): array {
    $subpath = '/database/1/' . $config['container'] . '/' . $config['environment'] . '/public/' . $subpathOp;
    $url     = 'https://api.apple-cloudkit.com' . $subpath;

    $body       = json_encode($payload, JSON_UNESCAPED_SLASHES);
    $date       = gmdate('Y-m-d\TH:i:s\Z');
    $hashedBody = base64_encode(hash('sha256', $body, true));
    $message    = $date . ':' . $hashedBody . ':' . $subpath;

    $signature = '';
    if (!openssl_sign($message, $signature, $pkey, OPENSSL_ALGO_SHA256)) {
        return ['error' => 'signing_failed'];
    }

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => $body,
        CURLOPT_TIMEOUT        => 20,
        CURLOPT_HTTPHEADER     => [
            'Content-Type: application/json',
            'X-Apple-CloudKit-Request-KeyID: ' . $config['key_id'],
            'X-Apple-CloudKit-Request-ISO8601Date: ' . $date,
            'X-Apple-CloudKit-Request-SignatureV1: ' . base64_encode($signature),
        ],
    ]);
    $response = curl_exec($ch);
    $errno    = curl_errno($ch);
    $code     = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($errno !== 0) {
        return ['error' => 'network_error'];
    }
    return ['code' => $code, 'decoded' => json_decode($response, true)];
}

/**
 * Per-key sliding-window rate limit backed by a flat file (shared-hosting
 * friendly — no APCu dependency required, though APCu would also work).
 * Returns true if the request is within budget (and records it), false if
 * the caller should be rejected with 429.
 */
function rate_limit_ok(string $key, string $dir, int $max, int $windowSeconds): bool {
    if (!is_dir($dir)) {
        @mkdir($dir, 0700, true);
    }
    $path = $dir . '/' . preg_replace('/[^a-zA-Z0-9_-]/', '_', $key) . '.json';

    $fh = @fopen($path, 'c+');
    if ($fh === false) {
        // Fail open rather than 500ing every request if the rate-limit
        // directory is misconfigured; CloudKit's own limits are the backstop.
        return true;
    }
    flock($fh, LOCK_EX);

    $raw = stream_get_contents($fh);
    $now = time();
    $hits = $raw !== false && $raw !== '' ? (json_decode($raw, true) ?: []) : [];
    // Keep only hits inside the current window.
    $hits = array_values(array_filter($hits, static fn($t) => $t > $now - $windowSeconds));

    $ok = count($hits) < $max;
    if ($ok) {
        $hits[] = $now;
    }

    ftruncate($fh, 0);
    rewind($fh);
    fwrite($fh, json_encode($hits));
    fflush($fh);
    flock($fh, LOCK_UN);
    fclose($fh);

    return $ok;
}

// ------------------------------------------------------------------ CONFIG

$configPath = __DIR__ . '/config.php';
if (!is_readable($configPath)) {
    fail(500, 'server_misconfigured', 'Server is not configured.');
}
/** @var array $config */
$config = require $configPath;

// -------------------------------------------------------------- VALIDATE HTTP

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    fail(405, 'method_not_allowed', 'Use POST.');
}

$rawBody = file_get_contents('php://input');
$input   = json_decode($rawBody ?: '', true);
if (!is_array($input)) {
    fail(400, 'invalid_json', 'Request body must be valid JSON.');
}

// ---------------------------------------------------------- RATE LIMITING

// Constants.Limits caps sourced from Reflect/Core/Utilities/Constants.swift.
const MAX_ANSWERS_PER_CALL   = 5;    // Constants.Limits.spaceMaxQuestions
const GUEST_NAME_MAX_LENGTH  = 50;
const ANSWER_BODY_MAX_LENGTH = 5000; // Constants.Limits.spaceResponseMaxLength

const RATE_LIMIT_PER_IP_MAX      = 20;   // requests
const RATE_LIMIT_PER_IP_WINDOW   = 60;   // seconds
const RATE_LIMIT_PER_TOKEN_MAX   = 10;   // requests
const RATE_LIMIT_PER_TOKEN_WINDOW = 60;  // seconds

$clientIp = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'] ?? 'unknown';
$clientIp = trim(explode(',', $clientIp)[0]);

$rateLimitDir = $config['rate_limit_dir'] ?? sys_get_temp_dir() . '/clip-feedback-ratelimit';

if (!rate_limit_ok('ip-' . $clientIp, $rateLimitDir, RATE_LIMIT_PER_IP_MAX, RATE_LIMIT_PER_IP_WINDOW)) {
    fail(429, 'rate_limited', 'Too many requests from this address. Try again shortly.');
}

// --------------------------------------------------------- VALIDATE PAYLOAD

$requestToken = $input['requestToken'] ?? null;
$guestId      = $input['guestId'] ?? null;
$guestName    = $input['guestName'] ?? null;
$answers      = $input['answers'] ?? null;

if (!is_string($requestToken) || $requestToken === '') {
    fail(400, 'missing_request_token', 'requestToken is required.');
}
if (!is_string($guestId) || $guestId === '') {
    fail(400, 'missing_guest_id', 'guestId is required.');
}
if (!is_string($guestName) || trim($guestName) === '') {
    fail(400, 'missing_guest_name', 'guestName is required.');
}
if (mb_strlen($guestName) > GUEST_NAME_MAX_LENGTH) {
    fail(400, 'guest_name_too_long', 'guestName must be at most ' . GUEST_NAME_MAX_LENGTH . ' characters.');
}
if (!is_array($answers) || count($answers) === 0) {
    fail(400, 'missing_answers', 'answers must be a non-empty array.');
}
if (count($answers) > MAX_ANSWERS_PER_CALL) {
    fail(400, 'too_many_answers', 'At most ' . MAX_ANSWERS_PER_CALL . ' answers are allowed per call.');
}

foreach ($answers as $i => $answer) {
    if (!is_array($answer)
        || !is_string($answer['questionId'] ?? null) || $answer['questionId'] === ''
        || !is_string($answer['submissionId'] ?? null) || $answer['submissionId'] === ''
        || !is_string($answer['body'] ?? null) || $answer['body'] === '') {
        fail(400, 'invalid_answer', "answers[$i] must have non-empty questionId, submissionId, and body.");
    }
    if (mb_strlen($answer['body']) > ANSWER_BODY_MAX_LENGTH) {
        fail(400, 'answer_too_long', "answers[$i].body must be at most " . ANSWER_BODY_MAX_LENGTH . ' characters.');
    }
}

if (!rate_limit_ok('token-' . $requestToken, $rateLimitDir, RATE_LIMIT_PER_TOKEN_MAX, RATE_LIMIT_PER_TOKEN_WINDOW)) {
    fail(429, 'rate_limited', 'Too many requests for this link. Try again shortly.');
}

// -------------------------------------------------------------- LOAD KEY

$pkey = openssl_pkey_get_private((string) file_get_contents($config['key_path']));
if ($pkey === false) {
    fail(500, 'server_misconfigured', 'Server is not configured.');
}

// ------------------------------------------------------- VALIDATE TOKEN

// TokenIndex.recordName is exactly "tok-" . $token (AC-010 mints it this way),
// so this is a cheap records/lookup, not a query — see AC-015 watch-outs.
$tokenLookup = cloudkit_request('records/lookup', [
    'records' => [['recordName' => 'tok-' . $requestToken]],
], $pkey, $config);

if (isset($tokenLookup['error'])) {
    fail(502, 'cloudkit_unreachable', 'Could not reach CloudKit. Try again shortly.');
}

$tokenRecord = $tokenLookup['decoded']['records'][0] ?? null;
$tokenServerErrorCode = $tokenRecord['serverErrorCode'] ?? null;

if ($tokenRecord === null || $tokenServerErrorCode === 'NOT_FOUND' || $tokenServerErrorCode === 'BAD_REQUEST') {
    // Absent TokenIndex record means the link was never valid or has since
    // been revoked (AC-011 deletes TokenIndex on revoke) — same response
    // either way, since the client can't tell (and shouldn't be told) apart.
    fail(404, 'token_not_found', 'This feedback link is no longer valid.');
}
if ($tokenServerErrorCode !== null) {
    fail(502, 'cloudkit_error', 'Could not validate this feedback link. Try again shortly.');
}

// ------------------------------------------------------ VALIDATE QUESTIONS

// requestToken is a Queryable field on MirroredRequest (AC-H1), so this is a
// records/query filtered by that field.
$mirrorQuery = cloudkit_request('records/query', [
    'query' => [
        'recordType' => 'MirroredRequest',
        'filterBy'   => [[
            'fieldName'  => 'requestToken',
            'comparator' => 'EQUALS',
            'fieldValue' => ['value' => $requestToken, 'type' => 'STRING'],
        ]],
    ],
], $pkey, $config);

if (isset($mirrorQuery['error'])) {
    fail(502, 'cloudkit_unreachable', 'Could not reach CloudKit. Try again shortly.');
}

$mirrorRecord = $mirrorQuery['decoded']['records'][0] ?? null;
if ($mirrorRecord === null) {
    fail(404, 'token_not_found', 'This feedback link is no longer valid.');
}

$questionsJSON = $mirrorRecord['fields']['questionsJSON']['value'] ?? '[]';
$questions = json_decode((string) $questionsJSON, true);
$validQuestionIds = [];
if (is_array($questions)) {
    foreach ($questions as $question) {
        if (isset($question['id']) && is_string($question['id'])) {
            $validQuestionIds[$question['id']] = true;
        }
    }
}

foreach ($answers as $i => $answer) {
    if (!isset($validQuestionIds[$answer['questionId']])) {
        fail(400, 'invalid_question', "answers[$i].questionId is not part of this request.");
    }
}

// --------------------------------------------------------- WRITE FEEDBACK

$submitted = [];

foreach ($answers as $answer) {
    $recordName = 'pcf-' . $answer['submissionId'];
    $fields = [
        'requestToken' => ['value' => $requestToken],
        'questionId'   => ['value' => $answer['questionId']],
        'guestId'      => ['value' => $guestId],
        'guestName'    => ['value' => $guestName],
        'body'         => ['value' => $answer['body']],
    ];

    // Update-or-create: try create first (the common case — first submit of
    // this submissionId). If the record already exists (a retry of the same
    // submissionId), force-update it in place instead of erroring, so a
    // retried submission always resolves to exactly one record.
    $create = cloudkit_request('records/modify', [
        'operations' => [[
            'operationType' => 'create',
            'record' => ['recordType' => 'PendingClipFeedback', 'recordName' => $recordName, 'fields' => $fields],
        ]],
    ], $pkey, $config);

    if (isset($create['error'])) {
        fail(502, 'cloudkit_unreachable', 'Could not reach CloudKit. Try again shortly.');
    }

    $createResult = $create['decoded']['records'][0] ?? null;
    $createErrorCode = $createResult['serverErrorCode'] ?? null;

    $wroteOk = $create['code'] === 200 && $createErrorCode === null;

    if (!$wroteOk && in_array($createErrorCode, ['UNIQUE_FIELD_ERROR', 'RECORD_EXISTS', 'BAD_REQUEST'], true)) {
        // Already exists — this is the retry-idempotency path.
        $update = cloudkit_request('records/modify', [
            'operations' => [[
                'operationType' => 'forceUpdate',
                'record' => ['recordType' => 'PendingClipFeedback', 'recordName' => $recordName, 'fields' => $fields],
            ]],
        ], $pkey, $config);

        if (isset($update['error'])) {
            fail(502, 'cloudkit_unreachable', 'Could not reach CloudKit. Try again shortly.');
        }
        $updateResult = $update['decoded']['records'][0] ?? null;
        $wroteOk = $update['code'] === 200 && ($updateResult['serverErrorCode'] ?? null) === null;
    }

    if (!$wroteOk) {
        fail(502, 'cloudkit_error', 'Could not save your feedback. Try again shortly.');
    }

    $submitted[] = $answer['submissionId'];
}

// ------------------------------------------------------------- RESPONSE

http_response_code(200);
echo json_encode(['ok' => true, 'submitted' => $submitted], JSON_UNESCAPED_SLASHES);
