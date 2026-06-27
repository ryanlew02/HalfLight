-- User reports of feed posts and comments. Lets any signed-in dreamer flag a
-- dream or comment for review (App Store UGC requirement). One row per report;
-- exactly one of post_id / comment_id is set. Reporters can only see and create
-- their own rows — moderation reads happen out of band with the service role.

create table if not exists public.feed_reports (
    id          uuid primary key default gen_random_uuid(),
    reporter_id uuid not null references auth.users (id) on delete cascade,
    post_id     uuid references public.feed_posts (id)    on delete cascade,
    comment_id  uuid references public.feed_comments (id) on delete cascade,
    reason      text not null,
    created_at  timestamptz not null default now(),
    -- A report targets a post xor a comment, never both / neither.
    constraint feed_reports_one_target check (num_nonnulls(post_id, comment_id) = 1),
    -- Don't let the same dreamer pile up duplicate reports on the same target.
    -- `nulls not distinct` so the unset target column (null) still collides, and
    -- the client's onConflict upsert can re-point at the existing row.
    constraint feed_reports_unique unique nulls not distinct (reporter_id, post_id, comment_id)
);
create index if not exists feed_reports_post_idx    on public.feed_reports (post_id);
create index if not exists feed_reports_comment_idx on public.feed_reports (comment_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- Row-level security: each dreamer manages only their own reports.
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.feed_reports enable row level security;

drop policy if exists "feed_reports own" on public.feed_reports;
create policy "feed_reports own" on public.feed_reports for all to authenticated
    using (reporter_id = auth.uid()) with check (reporter_id = auth.uid());

grant select, insert, delete on public.feed_reports to authenticated;
