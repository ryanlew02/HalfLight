-- Snapshot a dream's AI analysis onto its feed post, so dreamers who don't have
-- the source dream locally (everyone but the author) still see the interpretation
-- in the feed. Mirrors the ai_* columns on the dreams table.
alter table public.feed_posts
    add column if not exists ai_category text,
    add column if not exists ai_meaning  text,
    add column if not exists ai_themes   text[] not null default '{}';
