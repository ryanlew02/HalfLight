-- Activity notifications: one row per like/comment on a dreamer's post, written
-- by triggers when the engagement happens. Mirrors FeedSync.swift's
-- FeedNotificationRecord and the local SwiftData AppNotification cache.
--
-- The row is denormalized (actor name/username, post title, comment text are
-- snapshotted) so the client renders without joins — and so the actor's name,
-- which RLS keeps private on `profiles`, is captured by the SECURITY DEFINER
-- trigger rather than read by the recipient. Reads are scoped to the recipient.

-- ─────────────────────────────────────────────────────────────────────────────
-- Schema
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.notifications (
    id             uuid primary key default gen_random_uuid(),
    recipient_id   uuid not null references auth.users (id) on delete cascade,
    actor_id       uuid not null references auth.users (id) on delete cascade,
    type           text not null check (type in ('like', 'comment')),
    post_id        uuid references public.feed_posts (id) on delete cascade,
    comment_id     uuid references public.feed_comments (id) on delete cascade,
    actor_username text not null,
    actor_name     text not null,
    post_title     text not null default '',
    comment_text   text,
    created_at     timestamptz not null default now(),
    read_at        timestamptz
);

create index if not exists notifications_recipient_idx
    on public.notifications (recipient_id, created_at desc);

-- One like-notification per (recipient, actor, post): re-liking after an unlike
-- won't pile up duplicates. Comments are always distinct rows.
create unique index if not exists notifications_like_unique
    on public.notifications (recipient_id, actor_id, post_id)
    where type = 'like';

-- ─────────────────────────────────────────────────────────────────────────────
-- Triggers: create (and, for likes, remove) notifications as engagement lands.
-- SECURITY DEFINER so the function may read the actor's private name from
-- `profiles` and insert a row owned by the recipient. Never notify yourself.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.notify_on_like()
returns trigger language plpgsql security definer set search_path = public as $$
declare
    v_author_id uuid;
    v_title     text;
    v_username  text;
    v_name      text;
begin
    if (tg_op = 'INSERT') then
        select author_id, title into v_author_id, v_title
            from public.feed_posts where id = new.post_id;
        if v_author_id is null or v_author_id = new.user_id then
            return null;  -- post gone, or liking your own post
        end if;
        select username, trim(first_name || ' ' || last_name)
            into v_username, v_name
            from public.profiles where id = new.user_id;
        insert into public.notifications
            (recipient_id, actor_id, type, post_id, actor_username, actor_name, post_title)
        values
            (v_author_id, new.user_id, 'like', new.post_id,
             coalesce(v_username, ''), coalesce(v_name, ''), coalesce(v_title, ''))
        on conflict (recipient_id, actor_id, post_id) where type = 'like'
            do update set created_at = now(), read_at = null;
    elsif (tg_op = 'DELETE') then
        delete from public.notifications
            where type = 'like' and actor_id = old.user_id and post_id = old.post_id;
    end if;
    return null;
end $$;

create or replace function public.notify_on_comment()
returns trigger language plpgsql security definer set search_path = public as $$
declare
    v_author_id uuid;
    v_title     text;
begin
    select author_id, title into v_author_id, v_title
        from public.feed_posts where id = new.post_id;
    if v_author_id is null or v_author_id = new.author_id then
        return null;  -- post gone, or commenting on your own post
    end if;
    insert into public.notifications
        (recipient_id, actor_id, type, post_id, comment_id,
         actor_username, actor_name, post_title, comment_text)
    values
        (v_author_id, new.author_id, 'comment', new.post_id, new.id,
         new.author_username, new.author_name, coalesce(v_title, ''), new.text);
    return null;
end $$;

drop trigger if exists notify_on_like_t on public.feed_likes;
create trigger notify_on_like_t after insert or delete on public.feed_likes
    for each row execute function public.notify_on_like();

drop trigger if exists notify_on_comment_t on public.feed_comments;
create trigger notify_on_comment_t after insert on public.feed_comments
    for each row execute function public.notify_on_comment();

-- ─────────────────────────────────────────────────────────────────────────────
-- Row-level security: a dreamer reads and marks read only their own notifications.
-- Rows are created solely by the SECURITY DEFINER triggers, so there is no client
-- insert path (and no insert grant).
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.notifications enable row level security;

drop policy if exists "notifications read"   on public.notifications;
drop policy if exists "notifications update" on public.notifications;
create policy "notifications read"   on public.notifications for select to authenticated
    using (recipient_id = auth.uid());
create policy "notifications update" on public.notifications for update to authenticated
    using (recipient_id = auth.uid()) with check (recipient_id = auth.uid());

-- Recipients may read every column and update only the read flag.
grant select on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;
