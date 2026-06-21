-- Username changes are rate-limited to once every 30 days. We track the last
-- change time and enforce the cooldown in a trigger so the rule holds even if a
-- client skips the check.

alter table public.profiles
    add column if not exists username_changed_at timestamptz;

-- Let signed-in users read the timestamp so the app can show the cooldown.
grant select (username_changed_at) on public.profiles to authenticated;

-- On any username change: reject if it was changed within the last 30 days,
-- otherwise stamp the change time. The trigger sets the column itself, so the
-- client never needs (or gets) a direct grant to write it.
create or replace function public.enforce_username_cooldown()
returns trigger
language plpgsql
as $$
begin
    if new.username is distinct from old.username then
        if old.username_changed_at is not null
           and old.username_changed_at > now() - interval '30 days' then
            raise exception 'Username can only be changed once every 30 days';
        end if;
        new.username_changed_at := now();
    end if;
    return new;
end;
$$;

drop trigger if exists username_cooldown on public.profiles;
create trigger username_cooldown
    before update on public.profiles
    for each row
    execute function public.enforce_username_cooldown();
