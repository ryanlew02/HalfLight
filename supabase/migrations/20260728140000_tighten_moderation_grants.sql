-- Tighten the ban/block helpers so the `anon` role can't reach them.
--
-- `create function` grants EXECUTE to PUBLIC by default, which the ban migration
-- revoked for the moderator-only functions but not for these. None of them leak
-- anything today — every one keys off `auth.uid()`, which is null for an
-- unauthenticated caller, so `block_user` raises and the rest return nothing.
--
-- The one real (if small) edge: `is_banned(uuid)` takes an explicit id, so anyone
-- holding the anon key and a user's uuid could probe whether that account is
-- banned. Signed-in callers still need EXECUTE — RLS policy expressions run as
-- the querying role — so the fix is to drop `anon`, not to lock it down further.

revoke execute on function public.is_banned(uuid)      from anon;
revoke execute on function public.blocked_with(uuid)   from anon;
revoke execute on function public.block_user(text)     from anon;
revoke execute on function public.unblock_user(text)   from anon;
revoke execute on function public.blocked_accounts()   from anon;

-- Re-assert the intended grants, so this migration fully describes the end state
-- rather than depending on what the earlier ones happened to leave behind.
grant execute on function public.is_banned(uuid)      to authenticated;
grant execute on function public.blocked_with(uuid)   to authenticated;
grant execute on function public.block_user(text)     to authenticated;
grant execute on function public.unblock_user(text)   to authenticated;
grant execute on function public.blocked_accounts()   to authenticated;
