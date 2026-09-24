create table if not exists public.portfolio_valuations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  portfolio_version_id uuid not null references public.portfolio_versions(id),
  valuation_date date not null,
  market_value numeric(20,2) not null check (market_value >= 0),
  cash_value numeric(20,2) not null default 0 check (cash_value >= 0),
  net_contributions numeric(20,2) not null default 0,
  net_withdrawals numeric(20,2) not null default 0,
  unrealized_pnl numeric(20,2) not null default 0,
  realized_pnl numeric(20,2) not null default 0,
  time_weighted_return numeric(12,8),
  money_weighted_return numeric(12,8),
  source text not null default 'system',
  created_at timestamptz not null default now(),
  unique(user_id, portfolio_version_id, valuation_date)
);

create table if not exists public.documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  document_type text not null check (document_type in ('investment_certificate','statement','contract_note','risk_disclosure','other')),
  title text not null,
  storage_path text,
  metadata jsonb not null default '{}'::jsonb,
  status text not null default 'generated' check (status in ('draft','generated','archived')),
  created_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null,
  title text not null,
  body text not null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists portfolio_valuations_user_date_idx on public.portfolio_valuations(user_id, valuation_date desc);
create index if not exists documents_user_created_idx on public.documents(user_id, created_at desc);
create index if not exists notifications_user_created_idx on public.notifications(user_id, created_at desc);

alter table public.portfolio_valuations enable row level security;
alter table public.documents enable row level security;
alter table public.notifications enable row level security;

drop policy if exists "portfolio valuations owner read" on public.portfolio_valuations;
create policy "portfolio valuations owner read" on public.portfolio_valuations for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "portfolio valuations staff read" on public.portfolio_valuations;
create policy "portfolio valuations staff read" on public.portfolio_valuations for select to authenticated using (public.is_staff());

drop policy if exists "documents owner read" on public.documents;
create policy "documents owner read" on public.documents for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "documents staff read" on public.documents;
create policy "documents staff read" on public.documents for select to authenticated using (public.is_staff());

drop policy if exists "notifications owner read" on public.notifications;
create policy "notifications owner read" on public.notifications for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "notifications owner update" on public.notifications;
create policy "notifications owner update" on public.notifications for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
drop policy if exists "notifications staff read" on public.notifications;
create policy "notifications staff read" on public.notifications for select to authenticated using (public.is_staff());

create or replace function public.admin_record_valuation(
  p_user_id uuid,
  p_portfolio_version_id uuid,
  p_valuation_date date,
  p_market_value numeric,
  p_cash_value numeric default 0,
  p_net_contributions numeric default 0,
  p_net_withdrawals numeric default 0,
  p_unrealized_pnl numeric default 0,
  p_realized_pnl numeric default 0,
  p_time_weighted_return numeric default null,
  p_money_weighted_return numeric default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not public.is_staff() then raise exception 'Staff role required'; end if;
  insert into public.portfolio_valuations(user_id,portfolio_version_id,valuation_date,market_value,cash_value,net_contributions,net_withdrawals,unrealized_pnl,realized_pnl,time_weighted_return,money_weighted_return)
  values(p_user_id,p_portfolio_version_id,p_valuation_date,p_market_value,p_cash_value,p_net_contributions,p_net_withdrawals,p_unrealized_pnl,p_realized_pnl,p_time_weighted_return,p_money_weighted_return)
  on conflict(user_id,portfolio_version_id,valuation_date) do update set market_value=excluded.market_value,cash_value=excluded.cash_value,net_contributions=excluded.net_contributions,net_withdrawals=excluded.net_withdrawals,unrealized_pnl=excluded.unrealized_pnl,realized_pnl=excluded.realized_pnl,time_weighted_return=excluded.time_weighted_return,money_weighted_return=excluded.money_weighted_return;
  select id into v_id from public.portfolio_valuations where user_id=p_user_id and portfolio_version_id=p_portfolio_version_id and valuation_date=p_valuation_date;
  return v_id;
end $$;

grant execute on function public.admin_record_valuation(uuid,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric) to authenticated;