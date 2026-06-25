-- Comment likes: one row per (user, comment), mirroring feed_likes for posts.
-- A like_count column on feed_comments is kept current by a trigger so the
-- client can read it straight off each comment row (see FeedSync.swift).

-- ─────────────────────────────────────────────────────────────────────────────
-- Schema
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.feed_comments
    add column if not exists like_count integer not null default 0;

create table if not exists public.feed_comment_likes (
    user_id    uuid not null references auth.users (id) on delete cascade,
    comment_id uuid not null references public.feed_comments (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (user_id, comment_id)
);
create index if not exists feed_comment_likes_comment_idx
    on public.feed_comment_likes (comment_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- Counter trigger: keep feed_comments.like_count current. SECURITY DEFINER so the
-- update bypasses RLS — otherwise liking someone else's comment would be blocked.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.feed_comment_likes_count()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    if (tg_op = 'INSERT') then
        update public.feed_comments
            set like_count = greatest(0, like_count + 1) where id = new.comment_id;
    elsif (tg_op = 'DELETE') then
        update public.feed_comments
            set like_count = greatest(0, like_count - 1) where id = old.comment_id;
    end if;
    return null;
end $$;

drop trigger if exists feed_comment_likes_count_t on public.feed_comment_likes;
create trigger feed_comment_likes_count_t after insert or delete on public.feed_comment_likes
    for each row execute function public.feed_comment_likes_count();

-- ─────────────────────────────────────────────────────────────────────────────
-- Row-level security: each user manages only their own like rows; anyone signed
-- in may read (to compute who liked what).
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.feed_comment_likes enable row level security;

drop policy if exists "feed_comment_likes own" on public.feed_comment_likes;
create policy "feed_comment_likes own" on public.feed_comment_likes for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, update, delete on public.feed_comment_likes to authenticated;
