-- Sync a dream's public/lucid flags across devices. Earlier versions stored these
-- only locally, so a dream made public on one device looked private on another
-- after signing in. The existing table-level grants and the per-user RLS policy
-- already cover these new columns.
alter table public.dreams
    add column if not exists is_public boolean not null default false;
alter table public.dreams
    add column if not exists is_lucid boolean not null default false;
