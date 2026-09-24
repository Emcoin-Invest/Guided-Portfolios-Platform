create or replace function public.record_investment_consent(p_version_id uuid, p_reason text)
returns public.investment_consents language plpgsql security definer set search_path = ''
as $$
declare r public.investment_consents;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.portfolio_versions where id=p_version_id and workflow_state='published') then raise exception 'Published portfolio version required'; end if;
  insert into public.investment_consents(user_id,portfolio_version_id,reason)
  values(auth.uid(),p_version_id,coalesce(nullif(trim(p_reason),''),'Investor accepted additional risk disclosure'))
  returning * into r;
  return r;
end;
$$;

create or replace function public.submit_investment_request(p_version_id uuid,p_amount numeric,p_monthly_contribution numeric,p_consent_id uuid default null)
returns public.investment_requests language plpgsql security definer set search_path = ''
as $$
declare v_version record; v_profile record; v_consent public.investment_consents; r public.investment_requests;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_amount <= 0 then raise exception 'Investment amount must be positive'; end if;
  if p_monthly_contribution < 0 then raise exception 'Monthly contribution cannot be negative'; end if;
  select * into v_version from public.portfolio_versions where id=p_version_id and workflow_state='published';
  if v_version.id is null then raise exception 'Published portfolio version required'; end if;
  select * into v_profile from public.suitability_profiles where user_id=auth.uid() order by effective_at desc limit 1;
  if v_profile.id is not null and
     (case v_version.band when 'Conservative' then 1 when 'Balanced' then 2 when 'Aggressive' then 3 end) >
     (case v_profile.approved_band when 'Conservative' then 1 when 'Balanced' then 2 when 'Aggressive' then 3 end) then
    if p_consent_id is null then raise exception 'Additional risk consent is required'; end if;
    select * into v_consent from public.investment_consents where id=p_consent_id and user_id=auth.uid() and portfolio_version_id=p_version_id;
    if v_consent.id is null then raise exception 'Valid additional risk consent is required'; end if;
  end if;
  insert into public.investment_requests(user_id,portfolio_version_id,amount,monthly_contribution)
  values(auth.uid(),p_version_id,p_amount,p_monthly_contribution) returning * into r;
  insert into public.governance_events(entity_type,entity_id,action,actor_id,metadata)
  values('investment_request',r.id,'submitted',auth.uid(),jsonb_build_object('portfolio_version_id',p_version_id,'amount',p_amount,'monthly_contribution',p_monthly_contribution));
  return r;
end;
$$;

revoke execute on function public.record_investment_consent(uuid,text) from public, anon;
revoke execute on function public.submit_investment_request(uuid,numeric,numeric,uuid) from public, anon;
grant execute on function public.record_investment_consent(uuid,text) to authenticated;
grant execute on function public.submit_investment_request(uuid,numeric,numeric,uuid) to authenticated;
create index if not exists portfolio_versions_state_idx on public.portfolio_versions(workflow_state);
create index if not exists suitability_profiles_user_effective_idx on public.suitability_profiles(user_id,effective_at desc);
create index if not exists governance_events_entity_idx on public.governance_events(entity_type,entity_id,created_at desc);