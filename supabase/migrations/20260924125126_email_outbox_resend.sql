create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;
create extension if not exists supabase_vault with schema vault;

create table if not exists public.notification_email_outbox (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notifications(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  to_email text not null,
  subject text not null,
  body_text text not null,
  status text not null default 'pending' check (status in ('pending','processing','sent','failed')),
  attempts integer not null default 0,
  last_error text,
  provider_message_id text,
  idempotency_key text not null unique,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

create index if not exists idx_notification_email_outbox_pending
  on public.notification_email_outbox(status, created_at);

alter table public.notification_email_outbox enable row level security;

drop policy if exists "staff can read email outbox" on public.notification_email_outbox;
create policy "staff can read email outbox"
  on public.notification_email_outbox
  for select to authenticated
  using (public.is_staff());

create or replace function public.enqueue_notification_email()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipient text;
begin
  select email into recipient from auth.users where id = new.user_id;
  if recipient is null or recipient = '' then
    return new;
  end if;

  insert into public.notification_email_outbox (
    notification_id, user_id, to_email, subject, body_text, idempotency_key
  )
  values (
    new.id,
    new.user_id,
    recipient,
    coalesce(new.title, 'EmCoin Notification'),
    coalesce(new.body, ''),
    'notification:' || new.id::text
  )
  on conflict (idempotency_key) do nothing;

  return new;
end;
$$;

drop trigger if exists trg_enqueue_notification_email on public.notifications;
create trigger trg_enqueue_notification_email
after insert on public.notifications
for each row execute function public.enqueue_notification_email();

create or replace function public.get_email_runtime_secrets(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  expected_token text;
  resend_key text;
  from_email text;
begin
  select decrypted_secret into expected_token
    from vault.decrypted_secrets
    where name = 'email_internal_token'
    limit 1;

  if expected_token is null or p_token is null or p_token <> expected_token then
    return null;
  end if;

  select decrypted_secret into resend_key
    from vault.decrypted_secrets
    where name = 'resend_api_key'
    limit 1;

  select decrypted_secret into from_email
    from vault.decrypted_secrets
    where name = 'resend_from_email'
    limit 1;

  return jsonb_build_object(
    'resend_api_key', resend_key,
    'from_email', coalesce(from_email, 'onboarding@resend.dev')
  );
end;
$$;

revoke execute on function public.get_email_runtime_secrets(text) from public, anon, authenticated, service_role;
grant execute on function public.get_email_runtime_secrets(text) to anon;

create or replace function public.claim_email_outbox(p_limit integer default 20)
returns setof public.notification_email_outbox
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  update public.notification_email_outbox
  set status = 'processing',
      attempts = attempts + 1
  where id in (
    select id
    from public.notification_email_outbox
    where status = 'pending'
      and attempts < 5
    order by created_at
    for update skip locked
    limit greatest(1, least(p_limit, 100))
  )
  returning *;
end;
$$;

revoke execute on function public.claim_email_outbox(integer) from public, anon, authenticated;
grant execute on function public.claim_email_outbox(integer) to service_role;

create or replace function public.complete_email_outbox(
  p_id uuid,
  p_status text,
  p_provider_message_id text default null,
  p_error text default null
)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.notification_email_outbox
  set status = p_status,
      provider_message_id = coalesce(p_provider_message_id, provider_message_id),
      last_error = p_error,
      sent_at = case when p_status = 'sent' then now() else sent_at end
  where id = p_id;
$$;

revoke execute on function public.complete_email_outbox(uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.complete_email_outbox(uuid,text,text,text) to service_role;

select cron.unschedule('emcoin-email-outbox')
where exists (select 1 from cron.job where jobname = 'emcoin-email-outbox');

select cron.schedule(
  'emcoin-email-outbox',
  '* * * * *',
  $job$
    select net.http_post(
      url := 'https://cpzsciqyrhgbczveqxyp.supabase.co/functions/v1/process-email-outbox',
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body := jsonb_build_object(
        'internal_token',
        (select decrypted_secret from vault.decrypted_secrets where name = 'email_internal_token' limit 1)
      )
    );
  $job$
);