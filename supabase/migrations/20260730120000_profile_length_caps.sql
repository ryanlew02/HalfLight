-- Bound the free-text columns on profiles.
--
-- `username` was already bounded by the validate_username regex (3–20), and the
-- moderate_profile_t trigger blocks slurs and profanity in all three name
-- fields — but nothing bounded their SIZE. RLS lets an authenticated user PATCH
-- their own profile row directly, so a 100 KB display name was insertable via a
-- raw PostgREST call (verified against this project on 2026-07-30) and would
-- then render in the feed, follow lists, search results and comment threads.
--
-- feed_posts / feed_comments already got this treatment in the
-- feed_author_integrity migration; profiles never did.
--
-- Caps are deliberately generous next to what the UI allows (the bio editor
-- stops at 200) so a legitimate name is never rejected: the point is to stop
-- payloads, not to police length.

alter table public.profiles
    drop constraint if exists profiles_first_name_length;
alter table public.profiles
    add constraint profiles_first_name_length
    check (char_length(first_name) <= 100);

alter table public.profiles
    drop constraint if exists profiles_last_name_length;
alter table public.profiles
    add constraint profiles_last_name_length
    check (char_length(last_name) <= 100);

alter table public.profiles
    drop constraint if exists profiles_bio_length;
alter table public.profiles
    add constraint profiles_bio_length
    check (bio is null or char_length(bio) <= 500);

-- The sign-up trigger must never raise — an exception here would abort the
-- auth.users insert and cost the dreamer their account. It already skips
-- invalid handles; make it skip over-long names the same way, so a crafted
-- sign-up metadata payload can't break account creation. The dreamer still
-- gets an account and sets a name on the in-app profile screen, where the
-- check constraints above apply.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_handle text := lower(new.raw_user_meta_data ->> 'username');
    v_first  text := coalesce(new.raw_user_meta_data ->> 'first_name', '');
    v_last   text := coalesce(new.raw_user_meta_data ->> 'last_name', '');
begin
    if v_handle ~ '^[a-z0-9_]{3,20}$'
       and char_length(v_first) <= 100
       and char_length(v_last) <= 100
       and public.moderation_offense(v_handle, true) is null
       and public.moderation_offense(v_first, true) is null
       and public.moderation_offense(v_last, true) is null
    then
        -- If the username was snatched between the app's availability check
        -- and this insert, skip silently: the user then lands on the in-app
        -- username-setup screen after confirming, and picks another.
        insert into public.profiles (id, username, first_name, last_name)
        values (new.id, v_handle, v_first, v_last)
        on conflict do nothing;
    end if;
    return new;
end;
$$;
