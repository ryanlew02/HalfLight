-- Tie the rest of a dreamer's progress to the account, mirroring how dreams and
-- Lucid Path progress sync. This single JSON blob holds the bits that don't ride
-- along with the dreams themselves: the "can't remember" and journaling-XP-credit
-- day logs (so the streak and level follow the account), banked quest XP, and the
-- claimed-quest records (so a claimed weekly quest stays claimed across sign-out
-- and on other devices). The local UserDefaults copies (ProgressState.swift) stay
-- the working store; this column is the backed-up source of truth.

alter table public.profiles
    add column if not exists progress_state jsonb;

-- Progress is the dreamer's own data: a user reads and writes only their own row
-- (the existing "Users update their own profile" RLS policy scopes the write).
grant select (progress_state) on public.profiles to authenticated;
grant update (progress_state) on public.profiles to authenticated;
