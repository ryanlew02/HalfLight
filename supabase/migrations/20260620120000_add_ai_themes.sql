-- Add the AI-surfaced themes column to dreams.
-- These are the 2–3 central themes the analyze-dream function returns, used to
-- power the "Top themes" list on the Profile screen (distinct from `tags`).

alter table public.dreams
    add column if not exists ai_themes text[] not null default '{}';
