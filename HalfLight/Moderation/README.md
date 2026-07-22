# Moderation word lists

This directory contains offensive and discriminatory terms strictly for
automated content detection and moderation in HalfLight. **Their inclusion does
not reflect the views of the project or its contributors.**

The lists are loaded at runtime by `ContentFilter.swift` and bundled into the
app. They are intentionally kept out of the main source code as plain data.

## Files

| File               | Purpose                                                            | Applies to            |
| ------------------ | ----------------------------------------------------------------- | --------------------- |
| `blocked-terms.txt`| Slurs / hate speech. Blocked everywhere.                          | Usernames, names, posts |
| `profanity.txt`    | Ordinary profanity. Swearing is allowed in posts, so posts skip it.| Usernames, names        |
| `allowlist.txt`    | Innocuous words that merely *contain* a banned substring.          | Prevents false positives |

## Format

- One term per line, lowercase.
- Blank lines and lines beginning with `#` are ignored (use them for comments).
- Write terms in their leetspeak-folded form (e.g. `o` not `0`); the filter
  folds input the same way before matching, so a single spelling catches common
  obfuscations.

## Notes

- Matching is **whole-word** on folded text, plus a **compact** (separator-
  stripped) pass for 4+ letter terms, so `s l u r`-style evasion still matches
  while `class` / `assassin` (via `allowlist.txt`) do not.
- This is a **client-side** filter: the terms ship inside the app binary and can
  be recovered from an installed build. It raises the bar against casual abuse;
  it is not a secret. A determined bypass is a server-side concern.
