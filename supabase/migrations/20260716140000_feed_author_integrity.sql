-- Stop feed impersonation and cap text lengths.
--
-- The feed_posts / feed_comments RLS only checked `author_id = auth.uid()`; the
-- author_username / author_name columns were trusted from the client. A direct
-- API call could therefore publish a post or comment (owned by the attacker's
-- id) that DISPLAYS as any other dreamer's @handle and name — the app renders
-- that snapshot verbatim and links it to the victim's profile, and the comment
-- notification names the fake actor. Stress-tested 2026-07-16: an attacker
-- successfully posted and commented as "@victim_y".
--
-- Fix: stamp the author snapshot from the caller's own profile in a BEFORE
-- trigger, so whatever the client sends for author_username / author_name is
-- ignored and the true identity always wins. No profile → the write is rejected
-- (you can't post without an identity; the app gates this already).

create or replace function public.stamp_feed_author()
returns trigger
language plpgsql
security definer  -- read first_name, which column grants hide from the API
set search_path = public
as $$
declare
    v_username text;
    v_first    text;
begin
    select username, first_name into v_username, v_first
    from public.profiles
    where id = auth.uid();

    if v_username is null then
        raise exception 'You need a profile before posting to the feed.'
            using errcode = '42501'; -- insufficient_privilege
    end if;

    -- The client snapshot is advisory only; the server sets the truth.
    new.author_username := v_username;
    new.author_name := coalesce(nullif(v_first, ''), v_username);
    return new;
end;
$$;

-- Scoped to the identity columns so the engagement-count triggers (which update
-- only like_count / view_count / comment_count, often with no JWT in scope) never
-- fire this and never hit the "need a profile" guard.
drop trigger if exists stamp_feed_post_author on public.feed_posts;
create trigger stamp_feed_post_author
    before insert or update of author_username, author_name on public.feed_posts
    for each row execute function public.stamp_feed_author();

drop trigger if exists stamp_feed_comment_author on public.feed_comments;
create trigger stamp_feed_comment_author
    before insert on public.feed_comments
    for each row execute function public.stamp_feed_author();

-- Length caps: block abuse (a 20k-char comment was accepted) while staying well
-- clear of real content (longest real dream description in prod is ~200 chars).
alter table public.feed_comments drop constraint if exists feed_comments_text_len;
alter table public.feed_comments add constraint feed_comments_text_len
    check (char_length(text) <= 4000);

alter table public.feed_posts drop constraint if exists feed_posts_title_len;
alter table public.feed_posts add constraint feed_posts_title_len
    check (char_length(title) <= 500);

alter table public.feed_posts drop constraint if exists feed_posts_desc_len;
alter table public.feed_posts add constraint feed_posts_desc_len
    check (char_length(dream_description) <= 50000);

-- Follows: only real, registered dreamers can be followed. A ghost follow
-- (a handle that doesn't exist, or one registered later) was accepted, bloating
-- following lists and pre-claiming follows on not-yet-taken handles.
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
    return new;
end;
$$;

drop trigger if exists validate_followee on public.follows;
create trigger validate_followee
    before insert or update of followee_username on public.follows
    for each row execute function public.validate_followee();
