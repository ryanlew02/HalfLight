-- Records the outcome of a report review so the dashboard can sort handled
-- reports into "Issue" (content was hidden) vs "Closed" (dismissed as fine).
-- Null while the report is still pending.
alter table public.feed_reports
    add column if not exists resolution text;  -- null | 'kept' | 'hidden'
