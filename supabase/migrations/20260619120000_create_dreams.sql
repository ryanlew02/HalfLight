-- Per-user dream storage with Row Level Security.
-- Each row belongs to one auth user; policies ensure a user can only ever
-- read or write their own dreams.

create table if not exists public.dreams (
    id          uuid primary key,
    user_id     uuid not null references auth.users (id) on delete cascade,
    title       text not null,
    entry       text not null,
    date        timestamptz not null,
    mood        text not null,
    tags        text[] not null default '{}',
    ai_category text,
    ai_meaning  text,
    updated_at  timestamptz not null default now()
);

create index if not exists dreams_user_id_idx on public.dreams (user_id);

alter table public.dreams enable row level security;

-- One policy covering select / insert / update / delete: the row's user_id
-- must match the caller's auth.uid().
drop policy if exists "Users manage their own dreams" on public.dreams;
create policy "Users manage their own dreams"
    on public.dreams
    for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Signed-in users get table access; RLS still restricts to their own rows.
-- (anon / signed-out users are intentionally not granted access.)
grant select, insert, update, delete on public.dreams to authenticated;
