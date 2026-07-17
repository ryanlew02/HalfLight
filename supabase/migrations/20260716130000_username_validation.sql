-- Enforce the app's username rules (3–20 chars, lowercase letters/numbers/
-- underscores) in the database. The app validates client-side, but both write
-- paths were open to direct API calls with arbitrary strings: the sign-up
-- trigger inserted whatever arrived in the metadata, and RLS lets any
-- authenticated user insert/update their own row (stress test landed
-- "💀admin💀!!", a 200-char handle, and "<script>…" as usernames).

-- Backstop on the table itself: rejects invalid handles from every path —
-- the sign-up trigger, in-app profile creation (Apple flow), and username
-- changes, whether they come from the app or raw PostgREST calls.
create or replace function public.validate_username()
returns trigger
language plpgsql
as $$
begin
    if new.username !~ '^[a-z0-9_]{3,20}$' then
        raise exception 'Usernames must be 3–20 characters using lowercase letters, numbers, or underscores.'
            using errcode = '23514'; -- check_violation
    end if;
    return new;
end;
$$;

drop trigger if exists validate_username on public.profiles;
create trigger validate_username
    before insert or update of username on public.profiles
    for each row execute function public.validate_username();

-- The sign-up trigger must not raise on bad metadata (that would abort the
-- auth user creation itself), so it skips invalid handles instead: the user
-- still gets an account and lands on the in-app username-setup screen after
-- confirming, exactly like a lost username race.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    handle text := lower(new.raw_user_meta_data ->> 'username');
begin
    if handle ~ '^[a-z0-9_]{3,20}$' then
        -- If the username was snatched between the app's availability check
        -- and this insert, skip silently: the user then lands on the in-app
        -- username-setup screen after confirming, and picks another.
        insert into public.profiles (id, username, first_name, last_name)
        values (
            new.id,
            handle,
            coalesce(new.raw_user_meta_data ->> 'first_name', ''),
            coalesce(new.raw_user_meta_data ->> 'last_name', '')
        )
        on conflict do nothing;
    end if;
    return new;
end;
$$;
