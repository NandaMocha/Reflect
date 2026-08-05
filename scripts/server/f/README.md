# `/f/<token>` web landing page

Ticket: AC-016 (see `docs/features/app-clip-tasks.md`). Web fallback + Smart
App Banner trigger for a Reflect feedback-request link.

## What this is

`https://nandamochammad.xyz/f/<token>` is the link shared for a feedback
request (minted by the full app — AC-010/AC-015). On an iPhone with
Associated Domains verified, iOS intercepts the link before it ever reaches
this page and launches the App Clip (or the full app if installed) directly,
per the AASA at `scripts/appclip-aasa.json` (`/f/*` under both `applinks`
and `appclips`).

This page (`index.php`) only actually renders for:

- Desktop / Android visitors — no App Clip support, so they land on a plain
  explainer page with a Smart App Banner (iOS Safari shows the banner if the
  visitor is on iPhone but Associated Domains hasn't kicked in yet, or the
  link was opened outside a context that triggers the universal-link
  handoff, e.g. pasted into Notes).
- Link-preview crawlers (Messages, Mail, social apps) — served the Open
  Graph tags.

**Deliberately out of scope here** (this page does none of it):

- No CloudKit calls of any kind.
- No token validation. The token is treated as an opaque string; the Clip
  and the full app are the only things that ever resolve it against
  `TokenIndex`. A malformed/garbage token still renders the same generic
  explainer, no 500s.
- The token is **never rendered into the page body** — the only place it
  appears in the HTML is the `app-argument` value inside the
  `apple-itunes-app` meta tag (used verbatim by iOS to construct the
  universal link it launches the app/Clip with).

## Files

- `index.php` — the landing page. Rewritten to from `/f/<token>` by
  `.htaccess`.
- `.htaccess` — rewrites `/f/<token>` → `index.php?t=<token>`. LiteSpeed
  honours `.htaccess` on this host (see `docs/features/app-clip-plan.md`,
  "Hosting: cPanel is sufficient").

## Deploy notes (for AC-H2)

1. Upload the `f/` directory as-is to the web root:
   `/home/sesirkel/nandamochammad.xyz/nandamochammad/f/` (NOT `public_html`
   — this account uses an addon-domain layout; see Ground truth #4 in
   `docs/features/app-clip-tasks.md`).
2. **Before shipping to the App Store**, fill in `APPLE_ITUNES_APP_ID` in
   `index.php` (currently empty — the full app has no App Store numeric ID
   yet). Until then the Smart App Banner still deep-links correctly via
   `app-clip-bundle-id` alone, which is sufficient for Local Experiences /
   TestFlight-invocation testing (AC-H4/AC-H5).
3. Sanity checks after upload:
   - `curl -I https://nandamochammad.xyz/f/sometoken123` → `200`.
   - `curl -s https://nandamochammad.xyz/f/sometoken123 | grep apple-itunes-app`
     → confirms the meta tag renders with `app-clip-bundle-id=xyz.nandamochammad.Reflect.Clip`
     and `app-argument=https://nandamochammad.xyz/f/sometoken123`.
   - `curl -I https://nandamochammad.xyz/f/` (no token) → `404` (intentional
     — bare `/f/` has nothing to explain).
   - Confirm no redirect is introduced anywhere on `/f/*` — Apple's AASA
     fetcher and the App Clip invocation path both fail closed on redirects.
4. This page has no dependency on `scripts/server/clip-feedback.php`
   (AC-015) or its `config.php` — it needs no CloudKit credentials and can
   be deployed independently.

## Local verification

```bash
php -l scripts/server/f/index.php
```
