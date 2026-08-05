<?php
/**
 * AC-016 — /f/<token> web landing page (fallback + Smart App Banner).
 *
 * This page is the human-facing fallback for a Reflect feedback-request link
 * (https://nandamochammad.xyz/f/<token>). On an iPhone with Associated
 * Domains configured, iOS intercepts the link before this page ever loads
 * and launches the App Clip / full app directly (see the AASA at
 * scripts/appclip-aasa.json). This page only renders for:
 *   - Desktop / Android visitors (no App Clip support)
 *   - iPhones where the Clip hasn't been "seen" by iOS yet (first tap, or
 *     Associated Domains verification still pending)
 *   - Link-preview crawlers (Open Graph tags below)
 *
 * Deliberately out of scope (per docs/features/app-clip-tasks.md AC-016):
 *   - No CloudKit calls of any kind.
 *   - No token validation — the Clip/full app own that; this page treats the
 *     token as an opaque string.
 *   - The token is never rendered into the HTML body, only into the meta
 *     "app-argument" URL used for the Smart App Banner deep link.
 */

declare(strict_types=1);

// Token comes from the .htaccess rewrite (?t=<token>) or the query string
// directly. Treat as opaque and untrusted: allow only the same charset the
// app mints (see AC-010/AC-015 — url-safe token), strip everything else.
$rawToken = isset($_GET['t']) && is_string($_GET['t']) ? $_GET['t'] : '';
$token = preg_replace('/[^A-Za-z0-9_-]/', '', $rawToken);

$hasToken = $token !== '';

// --- Config -----------------------------------------------------------
// App Store numeric id is not yet known (app not published) — AC-H2/human
// fills this in once App Store Connect assigns one. `app-id` is a required
// attribute of the apple-itunes-app meta tag: with it empty, Safari renders
// no Smart App Banner at all, so app-clip-bundle-id / app-clip-display=card /
// app-argument below are inert until the ID is filled in. (Local Experiences
// and TestFlight Clip invocation are driven by AASA/universal links, not the
// Smart App Banner, so they don't exercise this path either.)
const APPLE_ITUNES_APP_ID = ''; // TODO(AC-H2): set once published, e.g. "id1234567890"
const APP_CLIP_BUNDLE_ID = 'xyz.nandamochammad.Reflect.Clip';
const CANONICAL_HOST = 'https://nandamochammad.xyz';

$path = '/f/' . $token;
$canonicalUrl = CANONICAL_HOST . $path;

// Smart App Banner "app-argument" — the URL iOS hands to the app/Clip on
// launch from the banner. Must be the same universal-link shape as the AASA
// path so it round-trips through NSUserActivityTypeBrowsingWeb parsing.
$appArgument = $canonicalUrl;

$itunesAppContentParts = [];
if (APPLE_ITUNES_APP_ID !== '') {
    $itunesAppContentParts[] = 'app-id=' . APPLE_ITUNES_APP_ID;
}
$itunesAppContentParts[] = 'app-clip-bundle-id=' . APP_CLIP_BUNDLE_ID;
$itunesAppContentParts[] = 'app-clip-display=card';
$itunesAppContentParts[] = 'app-argument=' . $appArgument;
$itunesAppContent = implode(', ', $itunesAppContentParts);

$pageTitle = 'Reflect — Feedback Request';
$pageDescription = 'Open this link on an iPhone to leave feedback in Reflect.';

header('Content-Type: text/html; charset=utf-8');
if (!$hasToken) {
    // Bare /f/ with no token: still a valid explainer page, just a 404-ish
    // status so crawlers / monitoring don't treat it as a real link.
    http_response_code(404);
}
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= htmlspecialchars($pageTitle, ENT_QUOTES, 'UTF-8') ?></title>

<!-- Smart App Banner: launches the ReflectClip App Clip (or the full app if
     installed) straight into this feedback request. -->
<meta name="apple-itunes-app" content="<?= htmlspecialchars($itunesAppContent, ENT_QUOTES, 'UTF-8') ?>">

<!-- Open Graph, for link-preview cards in Messages/Mail/social apps. -->
<meta property="og:title" content="<?= htmlspecialchars($pageTitle, ENT_QUOTES, 'UTF-8') ?>">
<meta property="og:description" content="<?= htmlspecialchars($pageDescription, ENT_QUOTES, 'UTF-8') ?>">
<meta property="og:type" content="website">
<meta property="og:url" content="<?= htmlspecialchars($canonicalUrl, ENT_QUOTES, 'UTF-8') ?>">
<meta name="description" content="<?= htmlspecialchars($pageDescription, ENT_QUOTES, 'UTF-8') ?>">

<link rel="canonical" href="<?= htmlspecialchars($canonicalUrl, ENT_QUOTES, 'UTF-8') ?>">

<style>
  :root {
    color-scheme: light dark;
  }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    max-width: 32rem;
    margin: 4rem auto;
    padding: 0 1.5rem;
    line-height: 1.5;
    text-align: center;
    color: #1c1c1e;
    background: #ffffff;
  }
  @media (prefers-color-scheme: dark) {
    body { color: #f2f2f7; background: #000000; }
  }
  h1 { font-size: 1.5rem; margin-bottom: 0.5rem; }
  p { opacity: 0.8; }
</style>
</head>
<body>
  <h1>Reflect</h1>
  <?php if ($hasToken): ?>
    <p>Open this link on an iPhone to leave feedback in Reflect.</p>
  <?php else: ?>
    <p>This feedback link is missing or incomplete.</p>
  <?php endif; ?>
</body>
</html>
