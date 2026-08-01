-- Closes two holes reachable with nothing but the publishable key that ships
-- inside the app binary — no account required.
--
-- 1. `bump_count` was SECURITY DEFINER with the default EXECUTE grant to PUBLIC,
--    so `POST /rest/v1/rpc/bump_count` let anyone set any post's like_count,
--    view_count or comment_count to anything (verified: HTTP 204 as anon). Since
--    FeedRanker sorts on those counters, that's arbitrary control of the feed.
--    It's only ever called from the counter triggers, which are themselves
--    SECURITY DEFINER and run as the owner, so no role needs EXECUTE at all.
--
-- 2. The "Usernames are checkable" policy on `profiles` had no TO clause, so it
--    applied to PUBLIC — including anon. The column-level `grant select
--    (username) ... to anon` was assumed to narrow that to one column, but
--    Supabase's default privileges already grant ALL on new public tables to
--    anon, so the column grant constrained nothing: a signed-out caller could
--    read every profile's id, first_name, last_name, bio and avatar. Every other
--    table escapes this because its policies are all scoped `to authenticated`.
--
-- The only thing anon legitimately needs is the mid-signup "is this username
-- taken?" check, which happens before the account exists. That moves to a
-- SECURITY DEFINER function returning one boolean, so the table itself no longer
-- has to be readable while signed out.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Counter manipulation
-- ─────────────────────────────────────────────────────────────────────────────

revoke execute on function public.bump_count(uuid, text, int) from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Username availability, without exposing the table
-- ─────────────────────────────────────────────────────────────────────────────

-- Case-insensitive to match `profiles_username_lower_idx`, which is what
-- actually enforces uniqueness — a case variant is taken, not available.
-- Deliberately ignores bans and blocks: a banned dreamer's handle is still spoken
-- for, and reporting it as free would just fail the insert.
create or replace function public.username_available(p_username text)
returns boolean
language sql
security definer
set search_path = public
as $$
    select not exists (
        select 1 from public.profiles
        where lower(username) = lower(btrim(coalesce(p_username, '')))
    );
$$;

revoke execute on function public.username_available(text) from public;
grant execute on function public.username_available(text) to anon, authenticated, service_role;

-- Now that signed-out callers have a purpose-built check, profile rows are for
-- signed-in dreamers only. Same row logic as before, just no longer open to anon.
drop policy if exists "Usernames are checkable" on public.profiles;
drop policy if exists "Profiles readable when signed in" on public.profiles;
create policy "Profiles readable when signed in"
    on public.profiles
    for select
    to authenticated
    using (id = auth.uid() or (select not public.is_banned()));

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Social RPCs: signed-in only
-- ─────────────────────────────────────────────────────────────────────────────
-- These were all callable by anon, handing out the user directory and the
-- follow graph to anyone holding the publishable key. Nothing calls them before
-- sign-in.

revoke execute on function public.search_profiles(text, int) from public;
revoke execute on function public.follow_counts(text)        from public;
revoke execute on function public.followers_of(text)         from public;
revoke execute on function public.following_of(text)         from public;
revoke execute on function public.my_profile()               from public;

grant execute on function public.search_profiles(text, int) to authenticated, service_role;
grant execute on function public.follow_counts(text)        to authenticated, service_role;
grant execute on function public.followers_of(text)         to authenticated, service_role;
grant execute on function public.following_of(text)         to authenticated, service_role;
grant execute on function public.my_profile()               to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Moderation helpers stop being a public oracle
-- ─────────────────────────────────────────────────────────────────────────────
-- Both were anon-callable, which let anyone probe the slur lists interactively
-- until they found a spelling that passes. They're only used inside the
-- moderation triggers and `handle_new_user`, all SECURITY DEFINER, so they run
-- as the owner and need no role grants.

revoke execute on function public.moderation_normalize(text)          from public, anon, authenticated;
revoke execute on function public.moderation_offense(text, boolean)   from public, anon, authenticated;

-- `is_banned` keeps its PUBLIC grant on purpose. 20260728150000 kept it because
-- the anon signup path evaluated it through the profiles policy; that reason is
-- gone now, but it is still reached from policies on other tables and the
-- residual exposure is one boolean about a user id anon can no longer obtain.
-- Revoking it is safe to try once sign-up has been smoke-tested end to end.
