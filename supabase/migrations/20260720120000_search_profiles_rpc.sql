-- Account search for the feed's search screen.
--
-- The `profiles` table's column grants expose only `username` (and `avatar`) to
-- clients — names are never selectable through the API (see create_profiles).
-- So searching dreamers by display name has to run inside a SECURITY DEFINER
-- function, exposing the same public identity already shown on feed cards and in
-- the follower/following lists: username, display name, avatar. Mirrors the
-- followers_of / following_of RPCs (see the follow-graph migration).

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
    where btrim(coalesce(p_query, '')) <> ''
      and (
        p.username ilike '%' || p_query || '%'
        or btrim(p.first_name || ' ' || p.last_name) ilike '%' || p_query || '%'
      )
    -- Best matches first: an exact @handle, then handle-prefix matches, then the
    -- rest alphabetically.
    order by
        (lower(p.username) = lower(p_query)) desc,
        (p.username ilike p_query || '%') desc,
        lower(p.username)
    limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;

grant execute on function public.search_profiles(text, int) to authenticated;
