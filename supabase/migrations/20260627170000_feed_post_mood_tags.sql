-- Snapshot the dream's mood and the dreamer's own tags onto its feed post, so
-- other dreamers (who don't have the source dream locally) see the feeling
-- label, the tag chips, and the corner mood orb on the card.
alter table public.feed_posts
    add column if not exists mood text,
    add column if not exists tags text[] not null default '{}';
