-- Block self-follows. The follow button is hidden on your own profile, so the
-- app never does this, but a direct API call was accepted (stress-tested
-- 2026-07-16) and inflates both your follower and following counts. Fold the
-- check into the existing followee validation.

create or replace function public.validate_followee()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if not exists (
        select 1 from public.profiles where lower(username) = lower(new.followee_username)
    ) then
        raise exception 'That account does not exist.'
            using errcode = '23503'; -- foreign_key_violation
    end if;
    -- You can't follow yourself: reject when the followee handle is the
    -- follower's own username.
    if exists (
        select 1 from public.profiles
        where id = new.follower_id
          and lower(username) = lower(new.followee_username)
    ) then
        raise exception 'You cannot follow yourself.'
            using errcode = '23514'; -- check_violation
    end if;
    return new;
end;
$$;
