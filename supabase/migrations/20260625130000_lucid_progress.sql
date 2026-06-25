-- Tie Lucid Path progress to the account, mirroring how dreams sync: the set of
-- completed lesson IDs lives on the profile so it survives sign-out and follows
-- the dreamer across devices. The local UserDefaults copy (LucidProgress.swift)
-- stays the working store; this column is the backed-up source of truth.

alter table public.profiles
    add column if not exists lucid_completed_lessons text[] not null default '{}';

-- Progress is the dreamer's own data: a user reads and writes only their own row
-- (the existing "Users update their own profile" RLS policy scopes the write).
grant select (lucid_completed_lessons) on public.profiles to authenticated;
grant update (lucid_completed_lessons) on public.profiles to authenticated;
