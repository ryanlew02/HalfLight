-- Add an optional public bio to profiles, editable from the Edit Profile screen.
alter table public.profiles
    add column if not exists bio text;

-- Bios are public-facing (shown on the profile, and on future social surfaces),
-- so signed-in users may read them; a user may write only their own (the existing
-- "Users update their own profile" RLS policy already scopes the write by row).
grant select (bio) on public.profiles to authenticated;
grant update (bio) on public.profiles to authenticated;
