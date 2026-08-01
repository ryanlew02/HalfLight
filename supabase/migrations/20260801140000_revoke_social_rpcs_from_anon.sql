-- Completes 20260801120000, which only half-closed the social RPCs.
--
-- That migration revoked EXECUTE from PUBLIC and granted it back to
-- authenticated/service_role, on the assumption that anon reached these
-- functions only through its PUBLIC membership. It doesn't: Supabase's default
-- privileges grant EXECUTE on new functions in `public` to anon directly, so the
-- direct grant survived the PUBLIC revoke and `search_profiles` kept serving the
-- user directory — username, real name and avatar — to unauthenticated callers
-- (verified: HTTP 200 as anon after that migration).
--
-- Both grants have to go. The functions revoked `from public, anon, authenticated`
-- in that same migration (`bump_count`, the `moderation_*` helpers) were closed
-- correctly for exactly this reason. This is also why 20260728140000 (anon only)
-- and 20260728150000 (PUBLIC only) each looked like no-ops on their own.
--
-- Anything added later that must not be anon-callable needs BOTH revokes.

revoke execute on function public.search_profiles(text, int) from anon;
revoke execute on function public.follow_counts(text)        from anon;
revoke execute on function public.followers_of(text)         from anon;
revoke execute on function public.following_of(text)         from anon;
revoke execute on function public.my_profile()               from anon;

-- Re-assert the intended end state, so this migration fully describes it.
grant execute on function public.search_profiles(text, int) to authenticated, service_role;
grant execute on function public.follow_counts(text)        to authenticated, service_role;
grant execute on function public.followers_of(text)         to authenticated, service_role;
grant execute on function public.following_of(text)         to authenticated, service_role;
grant execute on function public.my_profile()               to authenticated, service_role;

-- `username_available` stays anon-callable on purpose: the signup screen checks a
-- handle before the account exists. It returns a single boolean and reads no
-- profile columns.
grant execute on function public.username_available(text) to anon, authenticated, service_role;
