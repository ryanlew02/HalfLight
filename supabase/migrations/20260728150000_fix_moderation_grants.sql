-- Corrects 20260728140000, which was a no-op.
--
-- That migration revoked EXECUTE from the `anon` role, but these functions still
-- carried the default grant to PUBLIC that `create function` hands out, and anon
-- is a member of PUBLIC — so nothing actually changed. Revoking from PUBLIC is
-- the only thing that removes it; the explicit grants below then hand it back to
-- the roles that genuinely need it.
--
-- `is_banned` is deliberately NOT revoked. The "Usernames are checkable" policy
-- on `profiles` has no TO clause, so it applies to PUBLIC — including the
-- signed-out `anon` role during sign-up, when the app checks whether a username
-- is taken. RLS policy expressions run as the querying role, so taking EXECUTE
-- away from PUBLIC would make that check fail and break account creation. The
-- residual exposure is small: an anon caller could learn whether a given user id
-- is banned, but user ids aren't reachable by anon anywhere in the schema, so
-- getting one already requires being signed in.

revoke execute on function public.blocked_with(uuid)  from public;
revoke execute on function public.block_user(text)    from public;
revoke execute on function public.unblock_user(text)  from public;
revoke execute on function public.blocked_accounts()  from public;

grant execute on function public.blocked_with(uuid)  to authenticated, service_role;
grant execute on function public.block_user(text)    to authenticated, service_role;
grant execute on function public.unblock_user(text)  to authenticated, service_role;
grant execute on function public.blocked_accounts()  to authenticated, service_role;
