create schema if not exists private;

alter table public.portfolio_versions alter column created_by drop not null;

create table if not exists public.suitability_questions (
  id uuid primary key default gen_random_uuid(),
  position int not null unique,
  prompt text not null,
  min_label text not null,
  max_label text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.suitability_answers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  question_id uuid not null references public.suitability_questions(id),
  answer_value int not null check (answer_value between 1 and 5),
  created_at timestamptz not null default now(),
  unique(user_id, question_id)
);

create table if not exists public.preference_assessments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  score int not null check (score between 0 and 100),
  band text not null check (band in ('Conservative','Balanced','Aggressive')),
  answers jsonb not null,
  created_at timestamptz not null default now()
);

create table if not exists public.portfolio_holdings (
  id uuid primary key default gen_random_uuid(),
  portfolio_version_id uuid not null references public.portfolio_versions(id) on delete cascade,
  symbol text not null,
  name text not null,
  asset_class text not null,
  allocation numeric not null check (allocation >= 0 and allocation <= 100),
  created_at timestamptz not null default now()
);

create table if not exists public.portfolio_benchmarks (
  id uuid primary key default gen_random_uuid(),
  portfolio_version_id uuid not null references public.portfolio_versions(id) on delete cascade,
  name text not null,
  code text,
  created_at timestamptz not null default now()
);

create table if not exists public.recommendations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  portfolio_version_id uuid not null references public.portfolio_versions(id),
  assessment_id uuid references public.preference_assessments(id),
  consent_required boolean not null default false,
  consent_id uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.investment_consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  portfolio_version_id uuid not null references public.portfolio_versions(id),
  reason text not null,
  accepted_at timestamptz not null default now(),
  ip_hash text,
  user_agent text
);

alter table public.recommendations
  add constraint recommendations_consent_fk
  foreign key (consent_id) references public.investment_consents(id);

create table if not exists public.investment_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  portfolio_version_id uuid not null references public.portfolio_versions(id),
  amount numeric not null check (amount > 0),
  monthly_contribution numeric not null default 0 check (monthly_contribution >= 0),
  status text not null default 'submitted' check (status in ('submitted','under_review','approved','rejected','cancelled')),
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.account_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  request_id uuid references public.investment_requests(id),
  transaction_type text not null,
  amount numeric not null,
  currency text not null default 'AED',
  status text not null default 'pending',
  occurred_at timestamptz not null default now(),
  reference text
);

create table if not exists public.statements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  storage_path text,
  generated_at timestamptz not null default now(),
  unique(user_id, period_start, period_end)
);

create index if not exists suitability_answers_user_idx on public.suitability_answers(user_id);
create index if not exists assessments_user_idx on public.preference_assessments(user_id, created_at desc);
create index if not exists holdings_version_idx on public.portfolio_holdings(portfolio_version_id);
create index if not exists recommendations_user_idx on public.recommendations(user_id, created_at desc);
create index if not exists requests_user_idx on public.investment_requests(user_id, submitted_at desc);
create index if not exists transactions_user_idx on public.account_transactions(user_id, occurred_at desc);

insert into public.suitability_questions(position,prompt,min_label,max_label)
values
(1,'How comfortable are you with temporary investment losses?','Very uncomfortable','Very comfortable'),
(2,'How important is capital preservation for your goal?','Very important','Less important'),
(3,'How long can you remain invested without needing the money?','Less than 1 year','10+ years'),
(4,'How would you react to a 15% portfolio decline?','Sell/reduce','Stay invested/increase'),
(5,'How much return variability can you accept for higher potential growth?','Very little','A lot')
on conflict(position) do nothing;

insert into public.portfolios(slug,name,active)
values
('capital-preserve','EmCoin Capital Preserve',true),
('balanced-growth','EmCoin Balanced Growth',true),
('momentum-growth','EmCoin Momentum Growth',true),
('sharia-growth','EmCoin Sharia Growth',true),
('income-ladder','EmCoin Income Ladder',true)
on conflict(slug) do update set name=excluded.name,active=true;

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles(id, display_name, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name',''), 'investor')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure private.handle_new_user();

create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid()
      and role in ('portfolio_manager','investment_reviewer','compliance_officer','admin')
  );
$$;

revoke execute on function public.is_staff() from public, anon;
grant execute on function public.is_staff() to authenticated;

create or replace function public.get_my_role()
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$
  select role from public.profiles where id = auth.uid();
$$;

revoke execute on function public.get_my_role() from public, anon;
grant execute on function public.get_my_role() to authenticated;

create or replace function public.submit_portfolio_for_review(p_version_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v record;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v from public.portfolio_versions where id=p_version_id for update;
  if v.id is null then raise exception 'Portfolio version not found'; end if;
  if not exists(select 1 from public.profiles where id=auth.uid() and role in ('portfolio_manager','admin')) then
    raise exception 'Portfolio manager permission required';
  end if;
  if v.workflow_state <> 'draft' then raise exception 'Only draft versions can be submitted'; end if;
  if v.created_by is null then
    update public.portfolio_versions set created_by=auth.uid(), workflow_state='investment_review' where id=p_version_id;
  elsif v.created_by <> auth.uid() then
    raise exception 'Only the creator can submit this version';
  else
    update public.portfolio_versions set workflow_state='investment_review' where id=p_version_id;
  end if;
  insert into public.governance_events(entity_type,entity_id,action,actor_id)
  values('portfolio_version',p_version_id,'submitted_for_investment_review',auth.uid());
end;
$$;

create or replace function public.review_portfolio_version(p_version_id uuid, p_approve boolean, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v record;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v from public.portfolio_versions where id=p_version_id for update;
  if v.workflow_state <> 'investment_review' then raise exception 'Version is not awaiting investment review'; end if;
  if v.created_by = auth.uid() then raise exception 'Maker-checker violation'; end if;
  if not exists(select 1 from public.profiles where id=auth.uid() and role in ('investment_reviewer','admin')) then
    raise exception 'Investment reviewer permission required';
  end if;
  update public.portfolio_versions
    set reviewed_by=auth.uid(), workflow_state=case when p_approve then 'compliance_approval'::public.workflow_state else 'rejected'::public.workflow_state end
  where id=p_version_id;
  insert into public.governance_events(entity_type,entity_id,action,actor_id,metadata)
  values('portfolio_version',p_version_id,case when p_approve then 'investment_review_approved' else 'investment_review_rejected' end,auth.uid(),jsonb_build_object('note',p_note));
end;
$$;

create or replace function public.compliance_approve_portfolio_version(p_version_id uuid, p_approve boolean, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v record;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v from public.portfolio_versions where id=p_version_id for update;
  if v.workflow_state <> 'compliance_approval' then raise exception 'Version is not awaiting compliance approval'; end if;
  if v.created_by = auth.uid() or v.reviewed_by = auth.uid() then raise exception 'Segregation of duties violation'; end if;
  if not exists(select 1 from public.profiles where id=auth.uid() and role in ('compliance_officer','admin')) then
    raise exception 'Compliance permission required';
  end if;
  update public.portfolio_versions
    set approved_by=auth.uid(), workflow_state=case when p_approve then 'published'::public.workflow_state else 'rejected'::public.workflow_state end,
        published_at=case when p_approve then now() else null end
  where id=p_version_id;
  insert into public.governance_events(entity_type,entity_id,action,actor_id,metadata)
  values('portfolio_version',p_version_id,case when p_approve then 'compliance_approved_published' else 'compliance_rejected' end,auth.uid(),jsonb_build_object('note',p_note));
end;
$$;

revoke execute on function public.submit_portfolio_for_review(uuid) from public, anon;
revoke execute on function public.review_portfolio_version(uuid,boolean,text) from public, anon;
revoke execute on function public.compliance_approve_portfolio_version(uuid,boolean,text) from public, anon;
grant execute on function public.submit_portfolio_for_review(uuid) to authenticated;
grant execute on function public.review_portfolio_version(uuid,boolean,text) to authenticated;
grant execute on function public.compliance_approve_portfolio_version(uuid,boolean,text) to authenticated;

alter table public.suitability_questions enable row level security;
alter table public.suitability_answers enable row level security;
alter table public.preference_assessments enable row level security;
alter table public.portfolio_holdings enable row level security;
alter table public.portfolio_benchmarks enable row level security;
alter table public.recommendations enable row level security;
alter table public.investment_consents enable row level security;
alter table public.investment_requests enable row level security;
alter table public.account_transactions enable row level security;
alter table public.statements enable row level security;

create policy "authenticated active questions" on public.suitability_questions for select to authenticated using(active=true);
create policy "own answers" on public.suitability_answers for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy "own assessments" on public.preference_assessments for select to authenticated using(user_id=auth.uid());
create policy "published holdings" on public.portfolio_holdings for select to authenticated using(exists(select 1 from public.portfolio_versions v where v.id=portfolio_version_id and v.workflow_state='published'));
create policy "published benchmarks" on public.portfolio_benchmarks for select to authenticated using(exists(select 1 from public.portfolio_versions v where v.id=portfolio_version_id and v.workflow_state='published'));
create policy "own recommendations" on public.recommendations for select to authenticated using(user_id=auth.uid());
create policy "own consents" on public.investment_consents for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy "own requests" on public.investment_requests for select to authenticated using(user_id=auth.uid());
create policy "own request insert" on public.investment_requests for insert to authenticated with check(user_id=auth.uid());
create policy "own transactions" on public.account_transactions for select to authenticated using(user_id=auth.uid());
create policy "own statements" on public.statements for select to authenticated using(user_id=auth.uid());

drop policy if exists "own profile" on public.profiles;
create policy "own profile" on public.profiles for select to authenticated using(id=auth.uid());
drop policy if exists "own suitability" on public.suitability_profiles;
create policy "own suitability" on public.suitability_profiles for select to authenticated using(user_id=auth.uid());

insert into public.portfolio_versions(portfolio_id,version,band,target_return,volatility,risk_score,definition,workflow_state)
select p.id,1,'Conservative',.052,.041,1,jsonb_build_object('description','Capital preservation focused portfolio'),'published'
from public.portfolios p where p.slug='capital-preserve'
and not exists(select 1 from public.portfolio_versions v where v.portfolio_id=p.id and v.version=1);

insert into public.portfolio_versions(portfolio_id,version,band,target_return,volatility,risk_score,definition,workflow_state)
select p.id,1,'Balanced',.084,.098,2,jsonb_build_object('description','Balanced growth portfolio'),'published'
from public.portfolios p where p.slug='balanced-growth'
and not exists(select 1 from public.portfolio_versions v where v.portfolio_id=p.id and v.version=1);

insert into public.portfolio_versions(portfolio_id,version,band,target_return,volatility,risk_score,definition,workflow_state)
select p.id,1,'Aggressive',.135,.196,5,jsonb_build_object('description','Growth oriented portfolio'),'published'
from public.portfolios p where p.slug='momentum-growth'
and not exists(select 1 from public.portfolio_versions v where v.portfolio_id=p.id and v.version=1);

insert into public.portfolio_versions(portfolio_id,version,band,target_return,volatility,risk_score,definition,workflow_state)
select p.id,1,'Balanced',.076,.087,2,jsonb_build_object('description','Sharia aligned growth portfolio'),'published'
from public.portfolios p where p.slug='sharia-growth'
and not exists(select 1 from public.portfolio_versions v where v.portfolio_id=p.id and v.version=1);

insert into public.portfolio_versions(portfolio_id,version,band,target_return,volatility,risk_score,definition,workflow_state)
select p.id,1,'Conservative',.059,.034,1,jsonb_build_object('description','Income ladder portfolio'),'published'
from public.portfolios p where p.slug='income-ladder'
and not exists(select 1 from public.portfolio_versions v where v.portfolio_id=p.id and v.version=1);

insert into public.portfolio_holdings(portfolio_version_id,symbol,name,asset_class,allocation)
select v.id,x.symbol,x.name,x.asset_class,x.allocation
from public.portfolio_versions v
cross join lateral (values
('CASH','Cash & equivalents','Cash',10::numeric),
('BOND','Investment grade bonds','Fixed Income',50::numeric),
('EQUITY','Global equities','Equity',40::numeric)
) x(symbol,name,asset_class,allocation)
where v.version=1 and v.band='Conservative'
and not exists(select 1 from public.portfolio_holdings h where h.portfolio_version_id=v.id);

insert into public.portfolio_holdings(portfolio_version_id,symbol,name,asset_class,allocation)
select v.id,x.symbol,x.name,x.asset_class,x.allocation
from public.portfolio_versions v
cross join lateral (values
('BOND','Investment grade bonds','Fixed Income',40::numeric),
('EQUITY','Global equities','Equity',55::numeric),
('CASH','Cash & equivalents','Cash',5::numeric)
) x(symbol,name,asset_class,allocation)
where v.version=1 and v.band='Balanced'
and not exists(select 1 from public.portfolio_holdings h where h.portfolio_version_id=v.id);

insert into public.portfolio_holdings(portfolio_version_id,symbol,name,asset_class,allocation)
select v.id,x.symbol,x.name,x.asset_class,x.allocation
from public.portfolio_versions v
cross join lateral (values
('EQUITY','Global equities','Equity',80::numeric),
('ALT','Alternatives','Alternative',15::numeric),
('CASH','Cash & equivalents','Cash',5::numeric)
) x(symbol,name,asset_class,allocation)
where v.version=1 and v.band='Aggressive'
and not exists(select 1 from public.portfolio_holdings h where h.portfolio_version_id=v.id);

insert into public.portfolio_benchmarks(portfolio_version_id,name,code)
select v.id,case v.band when 'Conservative' then 'Conservative Composite' when 'Balanced' then 'Balanced Composite' else 'Growth Composite' end,
case v.band when 'Conservative' then 'CONS' when 'Balanced' then 'BAL' else 'GROWTH' end
from public.portfolio_versions v
where not exists(select 1 from public.portfolio_benchmarks b where b.portfolio_version_id=v.id);

create or replace function public.create_preference_assessment(p_answers jsonb)
returns public.preference_assessments
language plpgsql
security definer
set search_path = ''
as $$
declare
  result public.preference_assessments;
  score int;
  band text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if jsonb_array_length(p_answers) <> 5 then raise exception 'Five answers are required'; end if;
  score := round(((select avg((value::int)) from jsonb_array_elements(p_answers) value) / 5.0) * 100);
  band := case when score < 35 then 'Conservative' when score < 70 then 'Balanced' else 'Aggressive' end;
  insert into public.preference_assessments(user_id,score,band,answers)
  values(auth.uid(),score,band,p_answers)
  returning * into result;
  return result;
end;
$$;

revoke execute on function public.create_preference_assessment(jsonb) from public, anon;
grant execute on function public.create_preference_assessment(jsonb) to authenticated;
