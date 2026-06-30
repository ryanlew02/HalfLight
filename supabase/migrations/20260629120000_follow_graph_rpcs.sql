-- Follower / following social graph for profile screens.
--
-- The `follows` table's RLS only lets a dreamer read their OWN follow rows
-- (`using (follower_id = auth.uid())`), so there's no way to ask "who follows
-- @handle?" through a plain SELECT. These SECURITY DEFINER functions run as the
-- owner and bypass that restriction, exposing only public identity already shown
-- on feed cards — username, display name, and avatar.

-- Follower + following counts for a profile header, in one round-trip.
create or replace function public.follow_counts(p_username text)
returns table (followers integer, following integer)
language sql
security definer
set search_path = public
as $$
    select
        (select count(*)
            from public.follows f
            where lower(f.followee_username) = lower(p_username))::int as followers,
        (select count(*)
            from public.follows f
            join public.profiles p on p.id = f.follower_id
            where lower(p.username) = lower(p_username))::int as following
$$;

-- The dreamers who follow p_username.
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
    order by lower(p.username)
$$;

-- The dreamers p_username follows. Joins the stored followee handle back to a
-- profile so a renamed account simply drops out rather than showing a dead row.
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
    order by lower(p2.username)
$$;

grant execute on function public.follow_counts(text) to authenticated;
grant execute on function public.followers_of(text)  to authenticated;
grant execute on function public.following_of(text)  to authenticated;
