-- Per-user daily counter for AI requests, enforced server-side by the edge
-- functions so a leaked publishable key can't run up the Anthropic bill.
-- Only the SECURITY DEFINER function below and the service role touch this table,
-- so RLS is on with no policies (users can't read or tamper with their count).
create table if not exists public.ai_usage (
    user_id    uuid not null references auth.users (id) on delete cascade,
    usage_date date not null default current_date,
    count      integer not null default 0,
    primary key (user_id, usage_date)
);

alter table public.ai_usage enable row level security;

-- Atomically consume one AI credit for today. Returns true if the call is allowed
-- (and increments the count), false once the daily limit is reached. The row is
-- locked FOR UPDATE so concurrent requests can't slip past the limit.
create or replace function public.consume_ai_credit(p_user_id uuid, p_daily_limit integer)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    used integer;
begin
    insert into public.ai_usage (user_id, usage_date, count)
    values (p_user_id, current_date, 0)
    on conflict (user_id, usage_date) do nothing;

    select count into used
    from public.ai_usage
    where user_id = p_user_id and usage_date = current_date
    for update;

    if used >= p_daily_limit then
        return false;
    end if;

    update public.ai_usage
    set count = used + 1
    where user_id = p_user_id and usage_date = current_date;

    return true;
end;
$$;

-- Only the service role (the edge functions) may call it.
revoke all on function public.consume_ai_credit(uuid, integer) from public, anon, authenticated;
grant execute on function public.consume_ai_credit(uuid, integer) to service_role;
