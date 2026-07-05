# HalfLight

An AI-assisted lucid dreaming and dream journal app for iOS, built with SwiftUI.

Capture dreams the moment you wake, get AI-generated interpretations and theme
tags, track your journaling streak, and work through a lucid-dreaming lesson
path — all backed up to the cloud when you sign in.

## Features

- **Dream journal** — record dreams with a title, free-text entry, mood, and
  tags. Dictate entries with on-device speech-to-text.
- **AI assists** — "Analyze with AI" returns a category and a short
  interpretation; "Auto-tag" suggests theme/symbol tags; "Generate title" names
  the dream. All run through Supabase Edge Functions that proxy to Claude (the
  API key stays server-side). AI calls require a signed-in user and are capped
  at a per-user daily limit, enforced server-side.
- **Lucid path** — a Duolingo-style lesson map covering foundations plus the
  MILD, WBTB, and WILD induction methods.
- **Progress** — XP, levels, named ranks, weekly quests, journaling streaks,
  unlockable achievements, and a per-year activity grid. Reached from the
  Profile tab.
- **Profile** — editable username (with a 30-day change cooldown), bio, and
  photo; a rank badge; and your most-repeated dream themes, drillable to the
  dreams that carry each one.
- **Feed** — share dreams publicly, like and comment, follow other dreamers,
  and see followers/following on profiles. Posting, comments, follows, and
  reports are rate-limited server-side; reported content is triaged by an
  AI moderation function.
- **Accounts** — email/password or Sign in with Apple via Supabase Auth.
  Dreams sync to a per-user, row-level-secured Postgres table. Accounts can be
  permanently deleted in-app (App Store Guideline 5.1.1(v)).

## Tech stack

- SwiftUI + SwiftData (local persistence and the source of truth)
- Supabase: Auth, Postgres (with Row Level Security), and Edge Functions
- Anthropic Claude (called only from the Edge Functions)
- Speech / AVFoundation for dictation

## Project layout

```
HalfLight/
  HalfLightApp.swift      App entry point; builds the DreamStore and injects auth
  MainTabView.swift       Root tab shell + custom tab bar (Home/Lucid/Journal/Feed/Profile)
  AppRouter.swift         Shared navigation state and the XP/level-up claim queue
  Dream.swift             The @Model dream entry and its Mood enum
  DreamStore.swift        Write/sync service over SwiftData (all mutations go here)
  DreamSync.swift         DreamRecord wire type + Supabase sync backend
  DreamAnalyzer.swift     Client for the analyze-dream / suggest-tags / suggest-title functions
  DreamTranscriber.swift  Speech-to-text dictation
  DreamProgression.swift  XP / level / rank model
  Quest.swift, Achievement.swift, Streak.swift, LucidProgress.swift
                          The progression economy (quests, badges, streaks, lucid lessons)
  *View.swift             The screens (Home, Journal, Lucid, Stats/Progress, Profile, Feed, ...)
  DesignSystem.swift,     Shared visual language: spacing, type, cards, buttons,
  DreamBackground.swift,    color palette, and backdrops
  NightSkyBackground.swift
  Auth/                   AuthService + backends, AuthView, SupabaseConfig
supabase/
  migrations/             dreams + profiles + ai_usage tables, RLS policies, triggers
  functions/              analyze-dream, suggest-tags, suggest-title, delete-account
                            (+ _shared/ai-guard.ts: JWT check + daily rate limit)
```

## Building

Requires Xcode (full install, not just Command Line Tools) and an iOS Simulator.

1. Open `HalfLight.xcodeproj` in Xcode.
2. The Supabase Swift package is resolved automatically via Swift Package Manager.
3. Select the `HalfLight` scheme and an iOS Simulator, then run.

From the command line:

```sh
xcodebuild build \
  -project HalfLight.xcodeproj \
  -scheme HalfLight \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Unit tests live in `HalfLightTests` (feed and comment ranking); run them with
the same destination via `xcodebuild test -scheme HalfLight`.

## Backend setup

`HalfLight/Auth/SupabaseConfig.swift` holds the Supabase project URL and the
public anon/publishable key (safe to ship in a client; never commit the
`service_role` key). Point these at your own project to use a different backend.

Database — apply the migrations to create the `dreams`, `profiles`, and
`ai_usage` tables along with their RLS policies, triggers, and the
`consume_ai_credit` function:

```sh
supabase db push
```

Edge Functions — set the Anthropic key once, then deploy all four functions:

```sh
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
supabase functions deploy analyze-dream  --no-verify-jwt
supabase functions deploy suggest-tags   --no-verify-jwt
supabase functions deploy suggest-title  --no-verify-jwt
supabase functions deploy delete-account --no-verify-jwt
```

`--no-verify-jwt` only disables the gateway's built-in check; each function still
verifies the caller's user JWT itself (via `_shared/ai-guard.ts` for the AI
functions), so they are not open. The AI functions also enforce a per-user daily
request limit. The Claude model is set near the top of each AI function's
`index.ts` (`claude-haiku-4-5` by default).
