-- Create the profile row at sign-up time, server-side. With email confirmation
-- enabled, signUp() no longer returns a session, so the app can't insert the
-- profile itself (RLS requires auth.uid() = id). The app already passes the
-- chosen username and name as user metadata; this trigger turns that metadata
-- into the profiles row the moment the auth user is created — which also
-- reserves the username immediately, before the email is confirmed.
--
-- Sign in with Apple sends no username metadata, so the trigger skips those
-- users; they still create their profile in-app via the username-setup screen.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.raw_user_meta_data ? 'username' then
        -- If the username was snatched between the app's availability check and
        -- this insert, skip silently: the user then lands on the in-app
        -- username-setup screen after confirming, and picks another.
        insert into public.profiles (id, username, first_name, last_name)
        values (
            new.id,
            lower(new.raw_user_meta_data ->> 'username'),
            coalesce(new.raw_user_meta_data ->> 'first_name', ''),
            coalesce(new.raw_user_meta_data ->> 'last_name', '')
        )
        on conflict do nothing;
    end if;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();
