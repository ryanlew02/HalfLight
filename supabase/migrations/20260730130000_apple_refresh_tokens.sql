-- Stores the Sign in with Apple refresh token for each Apple-backed account.
--
-- Needed for App Store Review Guideline 5.1.1(v): when a dreamer deletes their
-- account we must call Apple's /auth/revoke, and that endpoint takes a refresh
-- token. Apple only issues one in exchange for the short-lived authorizationCode
-- handed to the app at sign-in, so it has to be captured then and kept until
-- deletion.
--
-- This is a credential. RLS is on and NO policy is ever created, so no client
-- role can read, insert or update it under any circumstances — only the
-- service_role (which bypasses RLS) touches it, from the `apple-link` and
-- `delete-account` edge functions. The grants below are belt-and-braces: revoke
-- the table privileges the `anon`/`authenticated` roles get by default so a
-- future policy added by mistake still can't expose the column.

create table if not exists public.apple_refresh_tokens (
    user_id       uuid primary key references auth.users (id) on delete cascade,
    refresh_token text        not null,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

alter table public.apple_refresh_tokens enable row level security;
-- Deliberately no policies: unreachable from anon/authenticated.

revoke all on public.apple_refresh_tokens from anon, authenticated;
grant all on public.apple_refresh_tokens to service_role;
