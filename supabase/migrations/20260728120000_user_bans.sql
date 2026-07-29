-- Banning a dreamer from the social side of the app.
--
-- A ban takes away everything an account unlocks on the feed: the banned dreamer
-- can't read the feed or anyone's comments, can't find or look at other dreamers,
-- can't post / comment / like / follow, and their own posts and comments drop out
-- of everyone else's feed. Their private journal is untouched — the ban is about
-- the shared space, not their dreams.
--
-- Enforced here in RLS rather than in the app, so a hand-rolled API call is
-- refused too. The app reads its own ban (see `user_bans read own`) purely to
-- explain what happened; it is never the thing standing in the way.
--
-- To ban someone (Supabase SQL editor / any service-role client):
--     select * from public.ban_user('handle', 'repeatedly posting slurs');
--     select * from public.ban_user('handle', 'spam', 7);   -- 7-day ban
--     select * from public.unban_user('handle');
--     select * from public.banned_users();                  -- who's banned now
-- `ban_user` / `unban_user` / `banned_users` are service-role only: an ordinary
-- signed-in dreamer cannot call them.

-- ─────────────────────────────────────────────────────────────────────────────
-- Schema
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.user_bans (
    user_id    uuid primary key references auth.users (id) on delete cascade,
    -- Shown to the banned dreamer, so keep it plain and factual.
    reason     text,
    -- Moderator-only context (which reports drove this, etc). Never sent to the app.
    note       text,
    banned_at  timestamptz not null default now(),
    -- null = permanent. A past timestamp is simply an expired (inactive) ban.
    expires_at timestamptz
);

alter table public.user_bans enable row level security;

-- A banned dreamer may read their own ban row (to be told why, and until when).
-- Nobody can read anyone else's, and nobody can write one: bans are inserted with
-- the service role through `ban_user` below.
drop policy if exists "user_bans read own" on public.user_bans;
create policy "user_bans read own" on public.user_bans for select to authenticated
    using (user_id = auth.uid());

grant select on public.user_bans to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- The predicate every policy below hangs off.
--
-- SECURITY DEFINER so it can see the whole table (the RLS policy above only
-- exposes your own row) — the feed policies need to ask about *authors*, not just
-- the caller. `stable` so Postgres evaluates it once per statement where it can.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.is_banned(p_user uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.user_bans b
        where b.user_id = p_user
          and (b.expires_at is null or b.expires_at > now())
    )
$$;

-- Callable by signed-in users because RLS policy expressions run as the caller.
grant execute on function public.is_banned(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Feed access
--
-- Reads are refused two ways: a banned reader sees nothing, and everyone else
-- stops seeing content from a banned author. The `(select ...)` wrapper on the
-- caller check makes it an InitPlan — evaluated once per statement, not per row.
-- ─────────────────────────────────────────────────────────────────────────────

drop policy if exists "feed_posts read"   on public.feed_posts;
drop policy if exists "feed_posts insert" on public.feed_posts;
drop policy if exists "feed_posts update" on public.feed_posts;
create policy "feed_posts read" on public.feed_posts for select to authenticated
    using ((select not public.is_banned()) and not public.is_banned(author_id));
create policy "feed_posts insert" on public.feed_posts for insert to authenticated
    with check (author_id = auth.uid() and (select not public.is_banned()));
create policy "feed_posts update" on public.feed_posts for update to authenticated
    using (author_id = auth.uid() and (select not public.is_banned()));
-- "feed_posts delete" is deliberately left alone: taking your own content down is
-- always allowed, ban or no ban.

drop policy if exists "feed_comments read"   on public.feed_comments;
drop policy if exists "feed_comments insert" on public.feed_comments;
create policy "feed_comments read" on public.feed_comments for select to authenticated
    using ((select not public.is_banned()) and not public.is_banned(author_id));
create policy "feed_comments insert" on public.feed_comments for insert to authenticated
    with check (author_id = auth.uid() and (select not public.is_banned()));
-- "feed_comments delete" likewise stays open.

-- Engagement: no liking, no impression counting, no following while banned.
drop policy if exists "feed_likes own" on public.feed_likes;
create policy "feed_likes own" on public.feed_likes for all to authenticated
    using (user_id = auth.uid() and (select not public.is_banned()))
    with check (user_id = auth.uid() and (select not public.is_banned()));

drop policy if exists "feed_views own" on public.feed_views;
create policy "feed_views own" on public.feed_views for all to authenticated
    using (user_id = auth.uid() and (select not public.is_banned()))
    with check (user_id = auth.uid() and (select not public.is_banned()));

drop policy if exists "feed_comment_likes own" on public.feed_comment_likes;
create policy "feed_comment_likes own" on public.feed_comment_likes for all to authenticated
    using (user_id = auth.uid() and (select not public.is_banned()))
    with check (user_id = auth.uid() and (select not public.is_banned()));

drop policy if exists "follows own" on public.follows;
create policy "follows own" on public.follows for all to authenticated
    using (follower_id = auth.uid() and (select not public.is_banned()))
    with check (follower_id = auth.uid() and (select not public.is_banned()));

-- ─────────────────────────────────────────────────────────────────────────────
-- Seeing other dreamers
--
-- `profiles` reads are open to everyone (including anon, mid-signup) so a
-- username-availability check works before you have an account. Narrow that to
-- exclude banned callers — a banned account is signed in, so `auth.uid()` is set
-- and the anon signup path is unaffected. Your own row stays readable either way,
-- so a banned dreamer's own profile screen (avatar and all) still works.
-- ─────────────────────────────────────────────────────────────────────────────

drop policy if exists "Usernames are checkable" on public.profiles;
create policy "Usernames are checkable"
    on public.profiles
    for select
    using (id = auth.uid() or (select not public.is_banned()));

-- Activity is feed activity, so it stops too — no new likes/comments/follows land
-- while banned, and the existing ones aren't readable.
drop policy if exists "notifications read" on public.notifications;
create policy "notifications read" on public.notifications for select to authenticated
    using (recipient_id = auth.uid() and (select not public.is_banned()));

-- The social RPCs are SECURITY DEFINER, so RLS doesn't apply to them — each needs
-- its own guard. They also stop listing banned dreamers, so a banned account
-- disappears from search and from follower / following lists.

create or replace function public.search_profiles(p_query text, p_limit int default 20)
returns table (username text, name text, avatar text)
language sql
security definer
set search_path = public
as $$
    select p.username,
           btrim(p.first_name || ' ' || p.last_name) as name,
           p.avatar
    from public.profiles p
    where not public.is_banned()          -- the caller
      and not public.is_banned(p.id)      -- the dreamer being listed
      and btrim(coalesce(p_query, '')) <> ''
      and (
        p.username ilike '%' || p_query || '%'
        or btrim(p.first_name || ' ' || p.last_name) ilike '%' || p_query || '%'
      )
    order by
        (lower(p.username) = lower(p_query)) desc,
        (p.username ilike p_query || '%') desc,
        lower(p.username)
    limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;

create or replace function public.follow_counts(p_username text)
returns table (followers integer, following integer)
language sql
security definer
set search_path = public
as $$
    select
        (select count(*)
            from public.follows f
            join public.profiles p on p.id = f.follower_id
            where lower(f.followee_username) = lower(p_username)
              and not public.is_banned(p.id))::int as followers,
        (select count(*)
            from public.follows f
            join public.profiles p on p.id = f.follower_id
            where lower(p.username) = lower(p_username))::int as following
    where not public.is_banned()
$$;

create or replace function public.followers_of(p_username text)
returns table (username text, name text, avatar text)
language sql
security definer
set search_path = public
as $$
    select p.username,
           btrim(p.first_name || ' ' || p.last_name) as name,
           p.avatar
    from public.follows f
    join public.profiles p on p.id = f.follower_id
    where lower(f.followee_username) = lower(p_username)
      and not public.is_banned()
      and not public.is_banned(p.id)
    order by lower(p.username)
$$;

create or replace function public.following_of(p_username text)
returns table (username text, name text, avatar text)
language sql
security definer
set search_path = public
as $$
    select p2.username,
           btrim(p2.first_name || ' ' || p2.last_name) as name,
           p2.avatar
    from public.follows f
    join public.profiles p1 on p1.id = f.follower_id
    join public.profiles p2 on lower(p2.username) = lower(f.followee_username)
    where lower(p1.username) = lower(p_username)
      and not public.is_banned()
      and not public.is_banned(p2.id)
    order by lower(p2.username)
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Moderator tools (service role only)
-- ─────────────────────────────────────────────────────────────────────────────

-- Ban by @handle, so a moderator never has to look up a uuid. `p_days` null bans
-- permanently; re-banning someone already banned updates the reason and length.
create or replace function public.ban_user(
    p_username text,
    p_reason   text default null,
    p_days     int  default null,
    p_note     text default null
)
returns table (username text, reason text, banned_at timestamptz, expires_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_id uuid;
begin
    select p.id into v_id from public.profiles p
    where lower(p.username) = lower(btrim(p_username));

    if v_id is null then
        raise exception 'No dreamer with the handle @%', p_username;
    end if;

    insert into public.user_bans (user_id, reason, note, expires_at)
    values (
        v_id,
        nullif(btrim(coalesce(p_reason, '')), ''),
        nullif(btrim(coalesce(p_note, '')), ''),
        case when p_days is null then null else now() + make_interval(days => p_days) end
    )
    on conflict (user_id) do update
        set reason     = excluded.reason,
            note       = excluded.note,
            expires_at = excluded.expires_at,
            banned_at  = now();

    return query
        select p.username, b.reason, b.banned_at, b.expires_at
        from public.user_bans b
        join public.profiles p on p.id = b.user_id
        where b.user_id = v_id;
end;
$$;

create or replace function public.unban_user(p_username text)
returns table (username text, unbanned boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_id      uuid;
    v_removed boolean;
begin
    select p.id into v_id from public.profiles p
    where lower(p.username) = lower(btrim(p_username));

    if v_id is null then
        raise exception 'No dreamer with the handle @%', p_username;
    end if;

    delete from public.user_bans b where b.user_id = v_id;
    -- Read FOUND into a local before returning: false means they weren't banned.
    v_removed := found;
    return query select btrim(p_username), v_removed;
end;
$$;

-- Everyone currently serving a ban, newest first — the moderator's overview.
create or replace function public.banned_users()
returns table (username text, reason text, note text, banned_at timestamptz, expires_at timestamptz)
language sql
security definer
set search_path = public
as $$
    select p.username, b.reason, b.note, b.banned_at, b.expires_at
    from public.user_bans b
    join public.profiles p on p.id = b.user_id
    where b.expires_at is null or b.expires_at > now()
    order by b.banned_at desc
$$;

-- `create function` grants EXECUTE to PUBLIC by default, which would let any
-- signed-in dreamer ban anyone. Revoke that and hand it to the service role only.
revoke execute on function public.ban_user(text, text, int, text) from public, anon, authenticated;
revoke execute on function public.unban_user(text)                from public, anon, authenticated;
revoke execute on function public.banned_users()                  from public, anon, authenticated;
grant  execute on function public.ban_user(text, text, int, text) to service_role;
grant  execute on function public.unban_user(text)                to service_role;
grant  execute on function public.banned_users()                  to service_role;
