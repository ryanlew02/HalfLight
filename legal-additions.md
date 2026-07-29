# Terms of Use — proposed additions

Drafted 2026-07-28 to cover reporting, blocking, and moderation, which the live
terms at halflightdream.com/terms.html don't currently mention. Written to match
the existing document's voice and numbering (Acceptable Use is §7, Termination
is §11).

**Not legal advice.** A lawyer should read this before it goes live, particularly
the termination and liability wording.

---

## 1. Add to §7 (Acceptable Use), at the top of the section

> **Zero tolerance for objectionable content and abusive behavior.** There is no
> tolerance for objectionable content or abusive users on the HalfLight feed.
> Content that harasses, threatens, or demeans another person, that sexualizes
> minors, that encourages self-harm, or that is hateful toward a person or group
> will be removed, and the accounts responsible may lose access to the feed or be
> terminated. Dreams themselves may be strange, dark, frightening, or sad — that
> is what dreams are, and it is not a violation. This section is about how you
> treat other people.

*Why: Apple's App Review guidance for user-generated content expects the terms to
state this plainly. The existing §7 prohibits the content but never says there is
no tolerance for it, and never mentions consequences for the account.*

---

## 2. New section, to sit between §7 (Acceptable Use) and §8 (Intellectual Property)

> **8. Reporting, Blocking, and Moderation**
>
> **Reporting.** Any dream or comment on the feed can be reported from inside the
> app by pressing and holding it and choosing Report. Reports are reviewed, and
> content that breaks these Terms may be hidden or removed. We aim to review
> reports within 24 hours. You will not always be told the outcome of a report you
> file.
>
> **Blocking.** You can block another dreamer from their profile, or by pressing
> and holding one of their dreams or comments. Once you block someone, you will
> not see their dreams or comments and they will not see yours, and any follow
> between you is removed. Blocking is not announced to the person blocked. You can
> see and undo your blocks at any time in Settings › Account › Blocked Accounts.
>
> **Moderation.** We review reported content using a combination of automated
> screening and human review. We may remove or hide content, and may restrict,
> suspend, or terminate access to the feed or to your account, where we believe
> these Terms have been broken. A restriction may apply only to the shared feed —
> leaving your private dream journal fully intact and available to you — or, for
> serious or repeated violations, to your account as a whole. We may act without
> prior notice where the content is clearly harmful.
>
> **Appeals.** If you believe a moderation decision was wrong, contact us at
> support@thelanternhours.com and we will review it.

*Why: the app has had reporting since June and blocking as of today, and neither
appears anywhere in the terms. The feed-only restriction is described explicitly
because that is what the app actually does — it is narrower and more favorable to
the user than an account termination, and the terms should say so rather than
leaving it to the broader §11.*

---

## 3. Revise §11 (Termination)

Existing wording gives the right to "remove content, restrict features, or suspend
or terminate accounts." Add after it:

> A restriction may be limited to community features such as the dream feed,
> comments, and other dreamers' profiles. Where it is, your account remains
> active, your dream journal remains private and available to you, and you may
> continue to use HalfLight's journaling, AI, and Lucid Path features.

*Why: accuracy. The current clause reads as account-level only, but a feed ban
leaves everything else working.*

---

## 4. Privacy Policy — moderation records

Add to whichever section covers what is collected:

> **Moderation records.** When you report content, we store the report, what it
> referred to, and the reason you selected. When you block another dreamer, we
> store that block so it can be enforced. If your access is restricted, we store
> the restriction, its reason, and when it ends. These records are kept for as
> long as your account exists and for a reasonable period afterwards, so that
> repeat behavior can be recognized and appeals can be reviewed.

*Why: `feed_reports`, `user_blocks`, and `user_bans` all hold data tied to an
identifiable person, and the privacy policy doesn't currently account for any of
them.*

---

## Also worth updating outside the terms

**App Store Connect › App Privacy** should reflect these same records if it
doesn't already.

**App Review notes:** it's worth telling the reviewer where the UGC controls are,
since they're not on the first screen — reporting is a press-and-hold on a feed
dream or comment, blocking is on a profile or the same press-and-hold menu, and
the block list is Settings › Account › Blocked Accounts. Reviewers have been known
to reject UGC apps for "missing" controls they simply didn't find.
