-- Per-user daily cap on following accounts: 50 follows/day. Continues the
-- pattern in 20260628130000_rate_limits.sql — a BEFORE INSERT trigger raising
-- SQLSTATE 'P0429' with a "RATE_LIMIT" marker so the app shows a friendly notice.
--
-- follow() upserts on (follower_id, followee_username), so re-following an
-- account you already follow updates the existing row rather than adding a new
-- follow — those don't count against the cap.

create or replace function public.enforce_follow_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
    daily_limit constant integer := 50;
    used integer;
begin
    if exists (
        select 1 from public.follows
        where follower_id = new.follower_id
          and followee_username = new.followee_username
    ) then
        return new;
    end if;

    select count(*) into used from public.follows
        where follower_id = new.follower_id and created_at >= current_date;

    if used >= daily_limit then
        raise exception 'RATE_LIMIT: daily follow limit reached'
            using errcode = 'P0429';
    end if;
    return new;
end $$;

drop trigger if exists enforce_follow_limit_t on public.follows;
create trigger enforce_follow_limit_t before insert on public.follows
    for each row execute function public.enforce_follow_limit();
