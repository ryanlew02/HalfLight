-- Push delivery for activity notifications. Three pieces, all read by the
-- `push-notify` Edge Function (run on a ~15-minute cron):
--   • device_tokens       — where to send (one row per APNs token)
--   • notifications.push_sent_at — marks activity already pushed, so each like /
--                                   comment is delivered at most once
--   • notification_pushes — a log of pushes sent, used to enforce the per-user
--                            hourly cap and to batch overflow into a summary
--
-- The batcher sends one push per user per run: a detailed push for a single new
-- item, or a summary ("You have 36 new likes") for several. Over the hourly cap,
-- activity stays unpushed and collapses into a larger summary on the next run.

-- ─────────────────────────────────────────────────────────────────────────────
-- Schema
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.device_tokens (
    token      text primary key,                         -- APNs device token (hex)
    user_id    uuid not null references auth.users (id) on delete cascade,
    platform   text not null default 'ios',
    updated_at timestamptz not null default now()
);
create index if not exists device_tokens_user_idx on public.device_tokens (user_id);

create table if not exists public.notification_pushes (
    id           uuid primary key default gen_random_uuid(),
    recipient_id uuid not null references auth.users (id) on delete cascade,
    body         text not null,
    sent_at      timestamptz not null default now()
);
create index if not exists notification_pushes_recipient_idx
    on public.notification_pushes (recipient_id, sent_at desc);

alter table public.notifications
    add column if not exists push_sent_at timestamptz;
-- Fast lookup of "what still needs pushing", the batcher's main query.
create index if not exists notifications_unpushed_idx
    on public.notifications (recipient_id) where push_sent_at is null;

-- ─────────────────────────────────────────────────────────────────────────────
-- Row-level security
--   • device_tokens: a dreamer manages only their own tokens.
--   • notification_pushes: server-only — the service role (used by the Edge
--     Function) bypasses RLS, and granting no policy/privilege keeps clients out.
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.device_tokens enable row level security;
drop policy if exists "device_tokens own" on public.device_tokens;
create policy "device_tokens own" on public.device_tokens for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update, delete on public.device_tokens to authenticated;

alter table public.notification_pushes enable row level security;  -- no policy ⇒ no client access
