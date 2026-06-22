-- Social feed: shared dreams, likes, views, comments, follows.
-- Mirrors FeedSync.swift and the local SwiftData models. Engagement counts live
-- on feed_posts and are kept current by triggers so the client (and FeedRanker)
-- can read them straight off each row.

-- ─────────────────────────────────────────────────────────────────────────────
-- Tables
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.feed_posts (
    id                uuid primary key,
    dream_id          uuid not null unique,                 -- one post per dream
    author_id         uuid not null references auth.users (id) on delete cascade,
    author_username   text not null,
    author_name       text not null,
    title             text not null,
    dream_description text not null default '',
    created_at        timestamptz not null default now(),
    like_count        integer not null default 0,
    view_count        integer not null default 0,
    comment_count     integer not null default 0
);
create index if not exists feed_posts_created_at_idx on public.feed_posts (created_at desc);
create index if not exists feed_posts_author_idx on public.feed_posts (author_id);

create table if not exists public.feed_likes (
    user_id    uuid not null references auth.users (id) on delete cascade,
    post_id    uuid not null references public.feed_posts (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (user_id, post_id)
);

create table if not exists public.feed_views (
    user_id    uuid not null references auth.users (id) on delete cascade,
    post_id    uuid not null references public.feed_posts (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (user_id, post_id)
);

create table if not exists public.feed_comments (
    id              uuid primary key,
    post_id         uuid not null references public.feed_posts (id) on delete cascade,
    author_id       uuid not null references auth.users (id) on delete cascade,
    author_username text not null,
    author_name     text not null,
    text            text not null,
    created_at      timestamptz not null default now()
);
create index if not exists feed_comments_post_idx on public.feed_comments (post_id, created_at);

create table if not exists public.follows (
    follower_id       uuid not null references auth.users (id) on delete cascade,
    followee_username text not null,
    created_at        timestamptz not null default now(),
    primary key (follower_id, followee_username)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Counter triggers: keep feed_posts.{like,view,comment}_count current.
-- SECURITY DEFINER so the count update runs as the function owner and bypasses
-- RLS — otherwise liking/commenting on someone else's post would be blocked when
-- the trigger tries to update that post's row.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.bump_count(p_post uuid, p_col text, p_delta int)
returns void language plpgsql security definer set search_path = public as $$
begin
    execute format('update public.feed_posts set %I = greatest(0, %I + $1) where id = $2', p_col, p_col)
        using p_delta, p_post;
end $$;

create or replace function public.feed_likes_count()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    if (tg_op = 'INSERT') then perform public.bump_count(new.post_id, 'like_count', 1);
    elsif (tg_op = 'DELETE') then perform public.bump_count(old.post_id, 'like_count', -1); end if;
    return null;
end $$;

create or replace function public.feed_views_count()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    if (tg_op = 'INSERT') then perform public.bump_count(new.post_id, 'view_count', 1); end if;
    return null;
end $$;

create or replace function public.feed_comments_count()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    if (tg_op = 'INSERT') then perform public.bump_count(new.post_id, 'comment_count', 1);
    elsif (tg_op = 'DELETE') then perform public.bump_count(old.post_id, 'comment_count', -1); end if;
    return null;
end $$;

drop trigger if exists feed_likes_count_t on public.feed_likes;
create trigger feed_likes_count_t after insert or delete on public.feed_likes
    for each row execute function public.feed_likes_count();

drop trigger if exists feed_views_count_t on public.feed_views;
create trigger feed_views_count_t after insert on public.feed_views
    for each row execute function public.feed_views_count();

drop trigger if exists feed_comments_count_t on public.feed_comments;
create trigger feed_comments_count_t after insert or delete on public.feed_comments
    for each row execute function public.feed_comments_count();

-- ─────────────────────────────────────────────────────────────────────────────
-- Row-level security
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.feed_posts    enable row level security;
alter table public.feed_likes    enable row level security;
alter table public.feed_views    enable row level security;
alter table public.feed_comments enable row level security;
alter table public.follows       enable row level security;

-- Posts: everyone signed in can read the feed; you may only write your own.
drop policy if exists "feed_posts read"   on public.feed_posts;
drop policy if exists "feed_posts insert" on public.feed_posts;
drop policy if exists "feed_posts update" on public.feed_posts;
drop policy if exists "feed_posts delete" on public.feed_posts;
create policy "feed_posts read"   on public.feed_posts for select to authenticated using (true);
create policy "feed_posts insert" on public.feed_posts for insert to authenticated with check (author_id = auth.uid());
create policy "feed_posts update" on public.feed_posts for update to authenticated using (author_id = auth.uid());
create policy "feed_posts delete" on public.feed_posts for delete to authenticated using (author_id = auth.uid());

-- Likes / views: each user manages only their own rows.
drop policy if exists "feed_likes own" on public.feed_likes;
drop policy if exists "feed_views own" on public.feed_views;
create policy "feed_likes own" on public.feed_likes for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "feed_views own" on public.feed_views for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Comments: anyone signed in can read; you may only add/remove your own.
drop policy if exists "feed_comments read"   on public.feed_comments;
drop policy if exists "feed_comments insert" on public.feed_comments;
drop policy if exists "feed_comments delete" on public.feed_comments;
create policy "feed_comments read"   on public.feed_comments for select to authenticated using (true);
create policy "feed_comments insert" on public.feed_comments for insert to authenticated with check (author_id = auth.uid());
create policy "feed_comments delete" on public.feed_comments for delete to authenticated using (author_id = auth.uid());

-- Follows: you manage only your own follow rows.
drop policy if exists "follows own" on public.follows;
create policy "follows own" on public.follows for all to authenticated
    using (follower_id = auth.uid()) with check (follower_id = auth.uid());

-- Signed-in users get table access; RLS still restricts rows.
grant select, insert, update, delete on public.feed_posts    to authenticated;
grant select, insert, update, delete on public.feed_likes    to authenticated;
grant select, insert, update, delete on public.feed_views    to authenticated;
grant select, insert, update, delete on public.feed_comments to authenticated;
grant select, insert, update, delete on public.follows       to authenticated;
