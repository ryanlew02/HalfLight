-- Public profile per auth user: a unique username plus the dreamer's name.
-- The username must be checkable by signed-out users (the app verifies
-- availability mid-signup, before the account exists), so SELECT on the
-- username column is public — but names stay private.

create table if not exists public.profiles (
    id          uuid primary key references auth.users (id) on delete cascade,
    username    text not null unique,
    first_name  text not null,
    last_name   text not null,
    created_at  timestamptz not null default now()
);

-- Enforce case-insensitive uniqueness (the app lowercases, this is the backstop).
create unique index if not exists profiles_username_lower_idx
    on public.profiles (lower(username));

alter table public.profiles enable row level security;

-- Anyone (including anon, mid-signup) may check whether a username is taken.
drop policy if exists "Usernames are checkable" on public.profiles;
create policy "Usernames are checkable"
    on public.profiles
    for select
    using (true);

-- A user may create their own profile row, once.
drop policy if exists "Users insert their own profile" on public.profiles;
create policy "Users insert their own profile"
    on public.profiles
    for insert
    with check (auth.uid() = id);

-- A user may update only their own profile row.
drop policy if exists "Users update their own profile" on public.profiles;
create policy "Users update their own profile"
    on public.profiles
    for update
    using (auth.uid() = id)
    with check (auth.uid() = id);

-- Column-level grants: the public can read only the username (for availability
-- checks); names are never exposed via the API. Users write their own row.
grant select (username) on public.profiles to anon, authenticated;
grant insert (id, username, first_name, last_name) on public.profiles to authenticated;
grant update (username, first_name, last_name) on public.profiles to authenticated;
