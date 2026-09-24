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

export async function recordInvestmentConsent(portfolioVersionId:string, reason:string) {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { data, error } = await supabase.rpc('record_investment_consent', { p_version_id: portfolioVersionId, p_reason: reason });
  if (error) throw error;
  return data;
}

export async function submitInvestment(payload:{portfolioVersionId:string;amount:number;monthlyContribution:number;consentId?:string|null}) {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { data, error } = await supabase.rpc('submit_investment_request', {
    p_version_id: payload.portfolioVersionId,
    p_amount: payload.amount,
    p_monthly_contribution: payload.monthlyContribution,
    p_consent_id: payload.consentId ?? null
  });
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


export async function getAdminData() {
  if (!supabase) throw new Error('Supabase is not configured.');
  const [assets, actions, portfolios, requests, profiles] = await Promise.all([
    supabase.from('assets').select('*').order('name'),
    supabase.from('corporate_actions').select('*,assets(symbol,name)').order('ex_date',{ascending:true}),
    supabase.from('portfolios').select('id,slug,name,active,portfolio_versions(id,version,band,target_return,volatility,risk_score,workflow_state,published_at,portfolio_holdings(id,symbol,name,asset_class,allocation,asset_id),portfolio_benchmarks(name,code))').order('name'),
    supabase.from('investment_requests').select('id,user_id,amount,monthly_contribution,status,submitted_at,updated_at,portfolio_versions(version,band,portfolios(name))').order('submitted_at',{ascending:false}).limit(100),
    supabase.from('profiles').select('id,display_name,role,created_at').order('created_at',{ascending:false}).limit(200)
  ]);
  for (const x of [assets,actions,portfolios,requests,profiles]) if (x.error) throw x.error;
  return {assets:assets.data??[], actions:actions.data??[], portfolios:portfolios.data??[], requests:requests.data??[], profiles:profiles.data??[]};
}

export async function upsertAsset(v:any) {
  const {data,error}=await supabase.rpc('admin_upsert_asset',{p_id:v.id??null,p_symbol:v.symbol,p_name:v.name,p_asset_class:v.asset_class,p_currency:v.currency,p_exchange:v.exchange||null,p_isin:v.isin||null,p_active:v.active,p_metadata:v.metadata||{}});
  if(error) throw error; return data;
}
export async function deleteAsset(id:string) { const {error}=await supabase.rpc('admin_delete_asset',{p_id:id}); if(error) throw error; }
export async function upsertCorporateAction(v:any) {
  const {data,error}=await supabase.rpc('admin_upsert_corporate_action',{p_id:v.id??null,p_asset_id:v.asset_id,p_action_type:v.action_type,p_announcement_date:v.announcement_date||null,p_ex_date:v.ex_date||null,p_record_date:v.record_date||null,p_payment_date:v.payment_date||null,p_ratio:v.ratio?Number(v.ratio):null,p_cash_amount:v.cash_amount?Number(v.cash_amount):null,p_currency:v.currency||null,p_details:v.details||{}});
  if(error) throw error; return data;
}
export async function setCorporateActionStatus(id:string,status:string) { const {error}=await supabase.rpc('admin_set_corporate_action_status',{p_id:id,p_status:status}); if(error) throw error; }
export async function deleteCorporateAction(id:string) { const {error}=await supabase.rpc('admin_delete_corporate_action',{p_id:id}); if(error) throw error; }
