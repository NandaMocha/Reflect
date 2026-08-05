# App Clip server scripts

Server-side pieces for the App Clip guest-feedback flow (ticket AC-015). App
Clips cannot write to CloudKit directly, so this PHP endpoint — hosted on
existing cPanel hosting — signs and calls CloudKit Web Services with a
server-to-server key on the guest's behalf. See
[docs/features/app-clip-plan.md](../../docs/features/app-clip-plan.md)
("Write path — PHP endpoint on existing cPanel hosting") and
[docs/features/app-clip-tasks.md](../../docs/features/app-clip-tasks.md)
(AC-015) for the full design.

## Files

- `clip-feedback.php` — the write endpoint. Validates a guest's submission,
  checks the link token, and writes `PendingClipFeedback` records that the
  owner's full app ingests during its next sync.
- `config.example.php` — template for the server-only config
  (`config.php`, **not** committed) that `clip-feedback.php` requires: the
  CloudKit Key ID, private-key path, container/environment, and rate-limit
  storage directory.

## Deploy (AC-H2)

Reuses the layout verified by `scripts/appclip-hosting-preflight.php` and
`scripts/appclip-cloudkit-write-test.php` — see
docs/features/app-clip-tasks.md "Ground truth" #4.

1. Web root is `/home/sesirkel/nandamochammad.xyz/nandamochammad`
   (**not** `public_html` — this is an addon-domain layout; uploading to
   `public_html` silently targets a different domain on the account).
2. Upload `clip-feedback.php` into the web root (e.g. under a `clip/` or
   `api/` folder — any path is fine as long as the Clip's `ClipFeedbackSubmitter`
   is pointed at the same URL).
3. Copy `config.example.php` to `config.php` **next to `clip-feedback.php`
   on the server only** — never commit `config.php` to this repo. Fill in:
   - `key_id` — from CloudKit Console > Tokens & Keys > Server-to-Server Keys.
   - `key_path` — `/home/sesirkel/nandamochammad.xyz/cloudkit-key.pem`
     (already deployed there by the write-path spike; outside the web root).
   - `container` — `iCloud.xyz.nandamochammad.Reflect`.
   - `environment` — `development` while `MirroredRequest`/`MirroredAnswer`/
     `TokenIndex` only exist in Dev (AC-H1); flip to `production` after the
     AC-H3 schema deploy.
   - `rate_limit_dir` — a writable directory outside the web root, e.g.
     `/home/sesirkel/nandamochammad.xyz/clip-feedback-ratelimit`. The script
     creates it on first run if missing (mode `0700`).
4. Confirm the endpoint answers `405 Method Not Allowed` on a plain `GET`
   (proves it deployed and PHP is executing it, without needing a real
   token yet).
5. Run the `php -l` lint and the curl checks below against **Dev** before
   calling AC-H2 done; live behavior is verified there, not by this ticket.

## Testing (clip-feedback.php)

Requires `TokenIndex`, `MirroredRequest`, `MirroredAnswer`, and
`PendingClipFeedback` to exist in the target CloudKit environment (AC-H1),
and at least one tokenized `SpaceReflection` published by the full app
(AC-010/AC-011) so a real `requestToken` and `questionId` are available.
Replace `https://nandamochammad.xyz/PATH/clip-feedback.php` with the actual
deployed URL, `<token>` with a real published token, and `<qid>` with one of
its `questionId`s.

**Happy path** — one answer, valid token and question:

```bash
curl -i -X POST https://nandamochammad.xyz/PATH/clip-feedback.php \
  -H 'Content-Type: application/json' \
  -d '{
    "requestToken": "<token>",
    "guestId": "test-guest-1",
    "guestName": "Test Guest",
    "answers": [
      {"questionId": "<qid>", "submissionId": "sub-001", "body": "First reply"}
    ]
  }'
# Expect: HTTP 200, {"ok":true,"submitted":["sub-001"]}
```

**Unknown token** — a token that was never minted or has been revoked:

```bash
curl -i -X POST https://nandamochammad.xyz/PATH/clip-feedback.php \
  -H 'Content-Type: application/json' \
  -d '{
    "requestToken": "not-a-real-token",
    "guestId": "test-guest-1",
    "guestName": "Test Guest",
    "answers": [
      {"questionId": "<qid>", "submissionId": "sub-002", "body": "First reply"}
    ]
  }'
# Expect: HTTP 404, {"ok":false,"error":"token_not_found",...}
```

**Bad questionId** — valid token, question not in this request's `questionsJSON`:

```bash
curl -i -X POST https://nandamochammad.xyz/PATH/clip-feedback.php \
  -H 'Content-Type: application/json' \
  -d '{
    "requestToken": "<token>",
    "guestId": "test-guest-1",
    "guestName": "Test Guest",
    "answers": [
      {"questionId": "not-a-real-question-id", "submissionId": "sub-003", "body": "First reply"}
    ]
  }'
# Expect: HTTP 400, {"ok":false,"error":"invalid_question",...}
```

**Oversize body** — over the 5000-character cap (`Constants.Limits.spaceResponseMaxLength`):

```bash
BODY=$(python3 -c "print('a' * 5001)")
curl -i -X POST https://nandamochammad.xyz/PATH/clip-feedback.php \
  -H 'Content-Type: application/json' \
  -d "{\"requestToken\":\"<token>\",\"guestId\":\"test-guest-1\",\"guestName\":\"Test Guest\",\"answers\":[{\"questionId\":\"<qid>\",\"submissionId\":\"sub-004\",\"body\":\"$BODY\"}]}"
# Expect: HTTP 400, {"ok":false,"error":"answer_too_long",...}
```

**Retry idempotency** — same `submissionId` posted twice must yield one record:

```bash
for i in 1 2; do
  curl -s -o /dev/null -w '%{http_code}\n' -X POST https://nandamochammad.xyz/PATH/clip-feedback.php \
    -H 'Content-Type: application/json' \
    -d '{
      "requestToken": "<token>",
      "guestId": "test-guest-1",
      "guestName": "Test Guest",
      "answers": [
        {"questionId": "<qid>", "submissionId": "sub-retry-001", "body": "Retried reply"}
      ]
    }'
done
# Expect: 200 twice; in CloudKit Console, exactly one PendingClipFeedback
# record with recordName "pcf-sub-retry-001" — the second call force-updates
# instead of creating a duplicate.
```

After each test run, delete the throwaway `PendingClipFeedback` records
(`pcf-sub-001`, `pcf-sub-retry-001`, etc.) from CloudKit Console so they
don't get ingested as real feedback by the owner's app.
