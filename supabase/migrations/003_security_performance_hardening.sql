create or replace function public.prevent_governance_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Governance events are append-only';
end;
$$;

create index if not exists account_transactions_request_idx on public.account_transactions(request_id);
create index if not exists governance_events_actor_idx on public.governance_events(actor_id);
create index if not exists investment_consents_user_idx on public.investment_consents(user_id);
create index if not exists investment_consents_version_idx on public.investment_consents(portfolio_version_id);
create index if not exists requests_version_idx on public.investment_requests(portfolio_version_id);
create index if not exists benchmarks_version_idx on public.portfolio_benchmarks(portfolio_version_id);
create index if not exists versions_created_by_idx on public.portfolio_versions(created_by);
create index if not exists versions_reviewed_by_idx on public.portfolio_versions(reviewed_by);
create index if not exists versions_approved_by_idx on public.portfolio_versions(approved_by);
create index if not exists recommendations_assessment_idx on public.recommendations(assessment_id);
create index if not exists recommendations_consent_idx on public.recommendations(consent_id);
create index if not exists recommendations_version_idx on public.recommendations(portfolio_version_id);
create index if not exists simulations_version_idx on public.simulation_runs(portfolio_version_id);
create index if not exists simulations_user_idx on public.simulation_runs(user_id);
create index if not exists suitability_answers_question_idx on public.suitability_answers(question_id);
create index if not exists suitability_profiles_user_idx on public.suitability_profiles(user_id);

drop policy if exists "own profile" on public.profiles;
create policy "own profile" on public.profiles for select to authenticated using((select auth.uid())=id);
drop policy if exists "own suitability" on public.suitability_profiles;
create policy "own suitability" on public.suitability_profiles for select to authenticated using((select auth.uid())=user_id);
drop policy if exists "own simulations" on public.simulation_runs;
create policy "own simulations" on public.simulation_runs for select to authenticated using((select auth.uid())=user_id);
drop policy if exists "own answers" on public.suitability_answers;
create policy "own answers" on public.suitability_answers for all to authenticated using((select auth.uid())=user_id) with check((select auth.uid())=user_id);
drop policy if exists "own assessments" on public.preference_assessments;
create policy "own assessments" on public.preference_assessments for select to authenticated using((select auth.uid())=user_id);
drop policy if exists "own recommendations" on public.recommendations;
create policy "own recommendations" on public.recommendations for select to authenticated using((select auth.uid())=user_id);
drop policy if exists "own consents" on public.investment_consents;
create policy "own consents" on public.investment_consents for all to authenticated using((select auth.uid())=user_id) with check((select auth.uid())=user_id);
drop policy if exists "own requests" on public.investment_requests;
create policy "own requests" on public.investment_requests for select to authenticated using((select auth.uid())=user_id);
drop policy if exists "own request insert" on public.investment_requests;
create policy "own request insert" on public.investment_requests for insert to authenticated with check((select auth.uid())=user_id);
drop policy if exists "own transactions" on public.account_transactions;
create policy "own transactions" on public.account_transactions for select to authenticated using((select auth.uid())=user_id);
drop policy if exists "own statements" on public.statements;
create policy "own statements" on public.statements for select to authenticated using((select auth.uid())=user_id);

revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
