-- Person-to-person blocking.
--
-- Distinct from a moderator ban (see the user_bans migration): a block is one
-- dreamer protecting themselves, needs no moderator, and is invisible to the
-- person blocked. Apple requires it of any app with user-generated content.
--
-- A block is symmetric in effect, even though only one side chose it: neither
-- dreamer sees the other's dreams, comments, profile, or activity, and neither
-- can follow the other. That keeps a blocked person from simply watching, and
-- keeps the blocker out of their reach. Existing follows in both directions are
-- torn down when the block goes up.
--
-- Enforced in RLS, so it holds against a hand-rolled API call too. Because the
-- policies here re-declare the ones the ban migration wrote, each keeps its ban
-- clause — a block is an additional reason to hide something, never a weaker one.

-- ─────────────────────────────────────────────────────────────────────────────
-- Schema
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.user_blocks (
    blocker_id uuid not null references auth.users (id) on delete cascade,
    blocked_id uuid not null references auth.users (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (blocker_id, blocked_id),
    constraint user_blocks_not_self check (blocker_id <> blocked_id)
);

-- The "who has blocked me?" direction, which the policies below ask on every read.
create index if not exists user_blocks_blocked_idx on public.user_blocks (blocked_id);

alter table public.user_blocks enable row level security;

-- You manage your own blocks and can only see the ones you made. Crucially you
-- cannot read rows where you are the *blocked* party — being blocked is not
-- something the app should ever be able to tell someone.
drop policy if exists "user_blocks own" on public.user_blocks;
create policy "user_blocks own" on public.user_blocks for all to authenticated
    using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());

grant select, insert, delete on public.user_blocks to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- The predicate the policies hang off.
--
-- SECURITY DEFINER because it has to see both directions, and the policy above
-- deliberately hides the direction where the caller is the one blocked.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.blocked_with(p_other uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.user_blocks b
        where (b.blocker_id = auth.uid() and b.blocked_id = p_other)
           or (b.blocker_id = p_other  and b.blocked_id = auth.uid())
    )
$$;

grant execute on function public.blocked_with(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Feed + activity visibility
-- ─────────────────────────────────────────────────────────────────────────────

drop policy if exists "feed_posts read" on public.feed_posts;
create policy "feed_posts read" on public.feed_posts for select to authenticated
    using (
        (select not public.is_banned())
        and not public.is_banned(author_id)
        and not public.blocked_with(author_id)
    );

drop policy if exists "feed_comments read" on public.feed_comments;
create policy "feed_comments read" on public.feed_comments for select to authenticated
    using (
        (select not public.is_banned())
        and not public.is_banned(author_id)
        and not public.blocked_with(author_id)
    );

-- No activity from someone you've blocked (or who blocked you).
drop policy if exists "notifications read" on public.notifications;
create policy "notifications read" on public.notifications for select to authenticated
    using (
        recipient_id = auth.uid()
        and (select not public.is_banned())
        and not public.blocked_with(actor_id)
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- Following
--
-- `follows` stores the followee as a handle, not an id, so the check lives in
-- the existing validate_followee trigger rather than in a policy.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.validate_followee()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_followee uuid;
begin
    select id into v_followee
    from public.profiles
    where lower(username) = lower(new.followee_username);

    if v_followee is null then
        raise exception 'That account does not exist.'
            using errcode = '23503'; -- foreign_key_violation
    end if;

    -- Blocked either way: the follow is refused. The app hides the button, so
    -- this only ever fires against a direct API call or a race.
    if public.blocked_with(v_followee) then
        raise exception 'You can''t follow this account.'
            using errcode = '42501'; -- insufficient_privilege
    end if;

    return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Seeing other dreamers: a blocked dreamer drops out of search and of follower /
-- following lists, in both directions.
-- ─────────────────────────────────────────────────────────────────────────────

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
    where not public.is_banned()
      and not public.is_banned(p.id)
      and not public.blocked_with(p.id)
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
      and not public.blocked_with(p.id)
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
      and not public.blocked_with(p2.id)
    order by lower(p2.username)
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- What the app calls
-- ─────────────────────────────────────────────────────────────────────────────

-- Block by @handle. Also tears down any follow in either direction, so neither
-- shows up in the other's lists. Idempotent — blocking twice is a no-op.
create or replace function public.block_user(p_username text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    v_me    uuid := auth.uid();
    v_other uuid;
    v_my_handle text;
begin
    if v_me is null then
        raise exception 'You need to be signed in to block someone.'
            using errcode = '42501';
    end if;

    select id into v_other from public.profiles
    where lower(username) = lower(btrim(p_username));

    if v_other is null then
        raise exception 'That account does not exist.'
            using errcode = '23503';
    end if;

    if v_other = v_me then
        raise exception 'You can''t block yourself.'
            using errcode = '22023'; -- invalid_parameter_value
    end if;

    insert into public.user_blocks (blocker_id, blocked_id)
    values (v_me, v_other)
    on conflict do nothing;

    select username into v_my_handle from public.profiles where id = v_me;

    -- Unfollow in both directions.
    delete from public.follows
    where (follower_id = v_me    and lower(followee_username) = lower(p_username))
       or (follower_id = v_other and lower(followee_username) = lower(coalesce(v_my_handle, '')));

    return true;
end;
$$;

create or replace function public.unblock_user(p_username text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    v_other uuid;
begin
    select id into v_other from public.profiles
    where lower(username) = lower(btrim(p_username));

    if v_other is null then
        return false;
    end if;

    delete from public.user_blocks
    where blocker_id = auth.uid() and blocked_id = v_other;

    return true;
end;
$$;

-- The caller's own block list, for the "Blocked Accounts" settings screen. Only
-- ever returns blocks *you* made — SECURITY DEFINER solely to read display names,
-- which column grants keep off the API (same pattern as followers_of).
create or replace function public.blocked_accounts()
returns table (username text, name text, avatar text, created_at timestamptz)
language sql
security definer
set search_path = public
as $$
    select p.username,
           btrim(p.first_name || ' ' || p.last_name) as name,
           p.avatar,
           b.created_at
    from public.user_blocks b
    join public.profiles p on p.id = b.blocked_id
    where b.blocker_id = auth.uid()
    order by b.created_at desc
$$;

grant execute on function public.block_user(text)   to authenticated;
grant execute on function public.unblock_user(text) to authenticated;
grant execute on function public.blocked_accounts() to authenticated;
