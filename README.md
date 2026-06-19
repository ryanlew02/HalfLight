# HalfLight

An AI-assisted lucid dreaming and dream journal app for iOS, built with SwiftUI.

Capture dreams the moment you wake, get AI-generated interpretations and theme
tags, track your journaling streak, and work through a lucid-dreaming lesson
path — all backed up to the cloud when you sign in.

## Features

- **Dream journal** — record dreams with a title, free-text entry, mood, and
  tags. Dictate entries with on-device speech-to-text.
- **AI analysis** — "Analyze with AI" returns a category and a short
  interpretation; "Auto-tag" suggests theme/symbol tags. Both run through
  Supabase Edge Functions that proxy to Claude (the API key stays server-side).
- **Lucid path** — a Duolingo-style lesson map covering foundations plus the
  MILD, WBTB, and WILD induction methods.
- **Progress** — XP, levels, named ranks, a per-year activity grid, plus mood
  and top-theme breakdowns.
- **Profile & themes** — your most-repeated dream themes, drillable to the
  dreams that carry each one.
- **Accounts** — email/password or Sign in with Apple via Supabase Auth.
  Dreams sync to a per-user, row-level-secured Postgres table.

## Tech stack

- SwiftUI + SwiftData (local persistence and the source of truth)
- Supabase: Auth, Postgres (with Row Level Security), and Edge Functions
- Anthropic Claude (called only from the Edge Functions)
- Speech / AVFoundation for dictation

## Project layout

```
HalfLight/
  HalfLightApp.swift      App entry point; builds the DreamStore and injects auth
  MainTabView.swift       Root tab shell + custom tab bar
  Dream.swift             The @Model dream entry and its Mood enum
  DreamStore.swift        Write/sync service over SwiftData (all mutations go here)
  DreamSync.swift         DreamRecord wire type + Supabase sync backend
  DreamAnalyzer.swift     Client for the analyze-dream / suggest-tags functions
  DreamTranscriber.swift  Speech-to-text dictation
  DreamProgression.swift  XP / level / rank model
  *View.swift             The screens (Home, Journal, Lucid, Stats, Profile, ...)
  DesignSystem.swift,     Shared visual language: spacing, type, cards, buttons,
  DreamBackground.swift,    color palette, and backdrops
  NightSkyBackground.swift
  Auth/                   AuthService + backends, AuthView, SupabaseConfig
supabase/
  migrations/             dreams table + RLS policies
  functions/              analyze-dream and suggest-tags Edge Functions
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

There is currently no test target.

## Backend setup

`HalfLight/Auth/SupabaseConfig.swift` holds the Supabase project URL and the
public anon/publishable key (safe to ship in a client; never commit the
`service_role` key). Point these at your own project to use a different backend.

Database — apply the migration to create the `dreams` table and its RLS policies:

```sh
supabase db push
```

Edge Functions — set the Anthropic key once, then deploy both functions:

```sh
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
supabase functions deploy analyze-dream --no-verify-jwt
supabase functions deploy suggest-tags  --no-verify-jwt
```

`--no-verify-jwt` lets the app call the functions with the project's publishable
key. The model used by both functions is set near the top of each
`index.ts` (`claude-haiku-4-5` by default).
