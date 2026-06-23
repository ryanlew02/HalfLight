-- HalfLight Pro entitlements. One row per dreamer, holding the current state of
-- their App Store auto-renewable subscription. Written only by the service role
-- (the `sync-subscription` and `app-store-notifications` edge functions, which
-- verify Apple's signed payloads); the AI functions read it through
-- `has_active_subscription` before spending on Claude.
create table if not exists public.subscriptions (
    user_id                  uuid primary key references auth.users (id) on delete cascade,
    original_transaction_id  text not null,
    product_id               text not null,
    -- active | expired | refunded | revoked
    status                   text not null default 'active',
    -- When the current period ends; the entitlement is live while this is in the future.
    expires_at               timestamptz,
    -- Sandbox | Production — so test purchases can't grant access in production.
    environment              text not null default 'Production',
    updated_at               timestamptz not null default now()
);

-- The webhook keys updates by Apple's stable original transaction id.
create unique index if not exists subscriptions_original_txn_idx
    on public.subscriptions (original_transaction_id);

alter table public.subscriptions enable row level security;

-- A dreamer may read their own entitlement (used by the app as a backup signal);
-- nobody but the service role may write it.
create policy "read own subscription"
    on public.subscriptions
    for select
    using (auth.uid() = user_id);

-- True when the dreamer has a live, non-refunded entitlement right now. Used by
-- the AI edge functions (via the service role) to gate Claude calls. SECURITY
-- DEFINER so it can read the RLS-protected table regardless of caller.
create or replace function public.has_active_subscription(p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.subscriptions
        where user_id = p_user_id
          and status = 'active'
          and (expires_at is null or expires_at > now())
    );
$$;

-- Only the edge functions (service role) gate on this.
revoke all on function public.has_active_subscription(uuid) from public, anon, authenticated;
grant execute on function public.has_active_subscription(uuid) to service_role;
