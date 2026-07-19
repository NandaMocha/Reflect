# Spaces — App Review notes (UGC compliance)

Reflect's **Spaces** feature lets a user create a private, invite-only group and share
learning reflections + comment-style responses with people they invite. Content is
user-generated, so this doc records the moderation mechanisms Apple requires for UGC
(Guideline 1.2), for the reviewer and for our own reference.

## Content model

- A **Space** is a private CloudKit share (`CKShare`, invite-only, no public link). Only
  people the owner explicitly invites can see or contribute.
- Members post **reflections** (title + prompt) and **responses** (comment-style). No
  public feed, no discovery, no anonymous access.

## Required UGC mechanisms (all implemented)

1. **Terms acknowledgment before first use** — `SpaceTermsSheet` is shown once before a
   user first uses Spaces (gated by the `spaceHasAcceptedTerms` UserDefault). It states a
   no-tolerance policy for objectionable content and points to the report + leave/remove
   controls.
2. **Report content** — every feedback request and every piece of feedback exposes a
   **Report** action (`ReportContentButton`) that opens a pre-filled email to the developer
   with the space name and the offending content's record ID.
3. **Owner moderation** — the space owner can **remove a member** (via the standard
   CloudKit sharing controller's participant management) and **delete the entire space**
   (destroys all content for everyone).
4. **Member self-service** — any member can **leave** a space at any time; authors can
   **delete their own** feedback requests / feedback.

> Vocabulary note: in the UI a space's seed post is a **feedback request** ("Ask for
> Feedback") and replies are **feedback**. The CloudKit record types remain
> `SpaceReflection` / `Response` internally — the rename is user-facing copy only.

## How to demo during review

1. Open the app → **Spaces** tab → accept the one-time terms sheet.
2. Create a space, **Ask for Feedback** (a request), then give **feedback** on it.
3. On any feedback request / feedback, use the **Report…** action → a pre-filled report
   email opens.
4. Owner: swipe a space → **Delete** ("deletes for every member"); or use the share sheet's
   participant list to remove a member. Member: swipe a joined space → **Leave**.

## Notes

- There is **no moderation backend** by design — reports are delivered by email to the
  developer, who acts manually. This matches the private, small-group nature of the feature.
- Report destination address is configured in `ReportContentButton.reportEmail`.
