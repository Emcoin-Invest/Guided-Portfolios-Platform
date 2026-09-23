import { supabase } from './supabase';

export async function getQuestions() {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { data, error } = await supabase.from('suitability_questions').select('*').eq('active', true).order('position');
  if (error) throw error;
  return data ?? [];
}

export async function getPortfolios() {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { data, error } = await supabase.from('portfolios').select('id,slug,name,active,portfolio_versions!inner(id,version,band,target_return,volatility,risk_score,definition,workflow_state,published_at,portfolio_holdings(symbol,name,asset_class,allocation),portfolio_benchmarks(name,code))').eq('active', true).eq('portfolio_versions.workflow_state', 'published');
  if (error) throw error;
  return data ?? [];
}

export async function createAssessment(values: number[]) {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { data, error } = await supabase.rpc('create_preference_assessment', { p_answers: values });
  if (error) throw error;
  return data;
}

export async function getMySuitability() {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { data, error } = await supabase.from('suitability_profiles').select('*').order('effective_at', { ascending: false }).limit(1).maybeSingle();
  if (error) throw error;
  return data;
}

export async function saveSimulation(payload: { portfolioVersionId:string; initialAmount:number; monthlyContribution:number; horizonYears:number; seed:number; paths:number; results:unknown }) {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { data, error } = await supabase.from('simulation_runs').insert({
    user_id: (await supabase.auth.getUser()).data.user?.id,
    portfolio_version_id: payload.portfolioVersionId,
    initial_amount: payload.initialAmount,
    monthly_contribution: payload.monthlyContribution,
    horizon_years: payload.horizonYears,
    seed: payload.seed,
    paths: payload.paths,
    results: payload.results
  }).select().single();
  if (error) throw error;
  return data;
}

export async function submitInvestment(payload:{portfolioVersionId:string;amount:number;monthlyContribution:number}) {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Authentication required');
  const { data, error } = await supabase.from('investment_requests').insert({
    user_id:user.id, portfolio_version_id:payload.portfolioVersionId, amount:payload.amount, monthly_contribution:payload.monthlyContribution
  }).select().single();
  if (error) throw error;
  return data;
}

export async function getMyRequests() {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { data, error } = await supabase.from('investment_requests').select('*, portfolio_versions(version,band,target_return,volatility,portfolios(name,slug))').order('submitted_at',{ascending:false});
  if (error) throw error;
  return data ?? [];
}

export async function getMyTransactions() {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { data, error } = await supabase.from('account_transactions').select('*').order('occurred_at',{ascending:false});
  if (error) throw error;
  return data ?? [];
}

export async function getMyStatements() {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { data, error } = await supabase.from('statements').select('*').order('period_end',{ascending:false});
  if (error) throw error;
  return data ?? [];
}
