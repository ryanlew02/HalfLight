-- Let a signed-in user read their OWN profile in full — including their first/
-- last name, which stay private from everyone else (the table's column grants
-- only expose `username` publicly). Scoped to auth.uid(), so it can never return
-- another user's name. Used to restore the dreamer's first name on a new device
-- so the app greets them by name instead of the "Dreamer" default.
create or replace function public.my_profile()
returns table (
    username text,
    first_name text,
    last_name text,
    bio text,
    username_changed_at timestamptz
)
language sql
security definer
set search_path = public
as $$
    select username, first_name, last_name, bio, username_changed_at
    from public.profiles
    where id = auth.uid()
$$;

grant execute on function public.my_profile() to authenticated;
