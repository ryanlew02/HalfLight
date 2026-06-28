-- Per-user daily caps on the feed write actions that are cheap to spam and
-- annoying in bulk: publishing dreams, commenting, and reporting. Enforced by
-- BEFORE INSERT triggers so the limits hold server-side no matter what the
-- client does (mirroring the AI daily limit in consume_ai_credit / ai-guard.ts).
--
-- Daily caps (per calendar day, server time):
--   • feed_posts   — 3   dreams published
--   • feed_comments— 20  comments written
--   • feed_reports — 5   posts/comments reported
--
-- Each trigger raises with SQLSTATE 'P0429' and a "RATE_LIMIT" marker so the app
-- can recognise the rejection and show a friendly "come back tomorrow" message
-- instead of a generic error. Counts are taken in a BEFORE INSERT trigger, so the
-- row being inserted isn't yet counted and the Nth insert is the last allowed.

-- ─────────────────────────────────────────────────────────────────────────────
-- feed_posts: 3 published dreams per day.
-- publish() upserts on the post id (editing a shared dream re-pushes the same
-- row), so an existing id is an edit, not a new post — those never count.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.enforce_post_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
    daily_limit constant integer := 3;
    used integer;
begin
    -- An edit of an already-published dream (upsert → UPDATE) doesn't add a post.
    if exists (select 1 from public.feed_posts where id = new.id) then
        return new;
    end if;

    select count(*) into used from public.feed_posts
        where author_id = new.author_id and created_at >= current_date;

    if used >= daily_limit then
        raise exception 'RATE_LIMIT: daily post limit reached'
            using errcode = 'P0429';
    end if;
    return new;
end $$;

drop trigger if exists enforce_post_limit_t on public.feed_posts;
create trigger enforce_post_limit_t before insert on public.feed_posts
    for each row execute function public.enforce_post_limit();

-- ─────────────────────────────────────────────────────────────────────────────
-- feed_comments: 20 comments per day.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.enforce_comment_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
    daily_limit constant integer := 20;
    used integer;
begin
    select count(*) into used from public.feed_comments
        where author_id = new.author_id and created_at >= current_date;

    if used >= daily_limit then
        raise exception 'RATE_LIMIT: daily comment limit reached'
            using errcode = 'P0429';
    end if;
    return new;
end $$;

drop trigger if exists enforce_comment_limit_t on public.feed_comments;
create trigger enforce_comment_limit_t before insert on public.feed_comments
    for each row execute function public.enforce_comment_limit();

-- ─────────────────────────────────────────────────────────────────────────────
-- feed_reports: 5 reports per day.
-- reportPost()/reportComment() upsert on (reporter_id, post_id, comment_id), so
-- re-reporting the same target updates the existing row — that isn't a new
-- report and must not count against the cap.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.enforce_report_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
    daily_limit constant integer := 5;
    used integer;
begin
    if exists (
        select 1 from public.feed_reports
        where reporter_id = new.reporter_id
          and post_id is not distinct from new.post_id
          and comment_id is not distinct from new.comment_id
    ) then
        return new;
    end if;

    select count(*) into used from public.feed_reports
        where reporter_id = new.reporter_id and created_at >= current_date;

    if used >= daily_limit then
        raise exception 'RATE_LIMIT: daily report limit reached'
            using errcode = 'P0429';
    end if;
    return new;
end $$;

drop trigger if exists enforce_report_limit_t on public.feed_reports;
create trigger enforce_report_limit_t before insert on public.feed_reports
    for each row execute function public.enforce_report_limit();
