-- AI triage for the report queue. The moderation agent (the moderate-reports
-- edge function) sorts pending reports into:
--   closed    — it handled an easy case (kept the content, or hid a clear
--               violation); resolution records which.
--   escalated — needs a human; surfaces in the dashboard's "Issue" column.
-- ai_reason stores the agent's one-line rationale, shown in the dashboard.

alter table public.feed_reports
    add column if not exists ai_reason text;

-- Collapse the old two-state model (pending | reviewed) into the new
-- three-state one (pending | escalated | closed). Anything previously marked
-- "reviewed" was human-resolved, so it becomes "closed".
update public.feed_reports set status = 'closed' where status = 'reviewed';
