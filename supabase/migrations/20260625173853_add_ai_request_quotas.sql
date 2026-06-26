create table public.ai_request_quotas (
  user_id uuid not null references auth.users(id) on delete cascade,
  function_name text not null,
  quota_date date not null,
  request_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ai_request_quotas_pkey primary key (
    user_id,
    function_name,
    quota_date
  ),
  constraint ai_request_quotas_function_name_check check (
    function_name in ('generate-habit', 'generate-weekly-review')
  ),
  constraint ai_request_quotas_request_count_check check (request_count >= 0)
);

alter table public.ai_request_quotas enable row level security;

revoke all on table public.ai_request_quotas from anon;
revoke all on table public.ai_request_quotas from authenticated;

create or replace function public.consume_ai_quota(
  target_function_name text,
  daily_limit integer
)
returns table (
  allowed boolean,
  used integer,
  "limit" integer,
  resets_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller_id uuid := auth.uid();
  quota_day date := (now() at time zone 'utc')::date;
  used_count integer;
  reset_time timestamptz := ((quota_day + 1)::timestamp at time zone 'utc');
begin
  if caller_id is null then
    raise exception 'Authentication is required.'
      using errcode = '28000';
  end if;

  if target_function_name not in ('generate-habit', 'generate-weekly-review') then
    raise exception 'Unsupported AI function.'
      using errcode = '22023';
  end if;

  if daily_limit is null or daily_limit <= 0 then
    raise exception 'daily_limit must be greater than zero.'
      using errcode = '22023';
  end if;

  insert into public.ai_request_quotas (
    user_id,
    function_name,
    quota_date,
    request_count
  )
  values (
    caller_id,
    target_function_name,
    quota_day,
    1
  )
  on conflict (user_id, function_name, quota_date)
  do update
    set request_count = public.ai_request_quotas.request_count + 1,
        updated_at = now()
  where public.ai_request_quotas.request_count < daily_limit
  returning request_count into used_count;

  if used_count is null then
    select request_count
      into used_count
      from public.ai_request_quotas
      where user_id = caller_id
        and function_name = target_function_name
        and quota_date = quota_day;

    return query select false, used_count, daily_limit, reset_time;
    return;
  end if;

  return query select true, used_count, daily_limit, reset_time;
end;
$$;

revoke all on function public.consume_ai_quota(text, integer) from public;
grant execute on function public.consume_ai_quota(text, integer) to authenticated;

create or replace function public.delete_old_ai_request_quotas()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  deleted_count integer;
begin
  delete from public.ai_request_quotas
  where quota_date < ((now() at time zone 'utc')::date - 90);

  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

revoke all on function public.delete_old_ai_request_quotas() from public;

comment on function public.delete_old_ai_request_quotas()
  is 'Manual cleanup helper for AI quota rows older than 90 UTC days. Run with select public.delete_old_ai_request_quotas();';
