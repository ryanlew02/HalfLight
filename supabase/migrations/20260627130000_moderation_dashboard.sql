-- Backing for the moderation dashboard. Gives reports a review lifecycle and
-- lets a moderator hide content without deleting it. The dashboard talks to
-- these columns with the service role (bypassing RLS); the app filters hidden
-- content out of the feed/comment queries.

-- Report review state.
alter table public.feed_reports
    add column if not exists status      text not null default 'pending',  -- pending | reviewed
    add column if not exists reviewed_at timestamptz;

-- Fast lookup of the work queue (only the pending rows are indexed).
create index if not exists feed_reports_pending_idx
    on public.feed_reports (created_at) where status = 'pending';

-- Soft-hide flags. Hidden content stays in the table (and in its author's own
-- journal) but is filtered out of everyone else's feed and comment threads.
alter table public.feed_posts    add column if not exists hidden boolean not null default false;
alter table public.feed_comments add column if not exists hidden boolean not null default false;
