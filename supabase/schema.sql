-- ================================================================
-- REDLINE — PRODUCTION DATABASE SCHEMA
-- ================================================================
-- Run this once in Supabase: Dashboard → SQL Editor → New query → paste → Run.
-- Safe to re-run — every statement uses IF NOT EXISTS / OR REPLACE.
--
-- Tables:
--   profiles   one row per signed-in user (plan, Stripe IDs)
--   projects   a repo/app the user has connected
--   scans      one row per scan run
--   findings   one row per vulnerability found in a scan
--
-- Security model: every table has Row Level Security ON. A signed-in
-- user can only ever read/write their own rows — enforced by Postgres
-- itself, not by application code. The only exception is the Stripe
-- webhook, which uses the SERVICE ROLE key (never exposed to the
-- browser) to update a user's plan after a payment event.
-- ================================================================

-- ---------- PROFILES ----------
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  plan text not null default 'free',              -- 'free' | 'pro'
  stripe_customer_id text,
  stripe_subscription_id text,
  stripe_subscription_status text,                -- 'active' | 'canceled' | 'past_due' | ...
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table profiles enable row level security;

drop policy if exists "profiles: read own" on profiles;
create policy "profiles: read own" on profiles
  for select using (auth.uid() = id);

drop policy if exists "profiles: update own" on profiles;
create policy "profiles: update own" on profiles
  for update using (auth.uid() = id);

-- Auto-create a profile row the moment someone signs up (GitHub or email).
create or replace function handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();

-- ---------- PROJECTS ----------
create table if not exists projects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  name text not null,
  repo_url text,
  platform text,                                    -- 'GitHub' | 'Lovable' | 'Bolt' | 'Replit' | 'v0' | 'Cursor' | null
  public_opt_in boolean not null default false,      -- shows on the public leaderboard/badge if true
  created_at timestamptz not null default now()
);

alter table projects enable row level security;

drop policy if exists "projects: owner full access" on projects;
create policy "projects: owner full access" on projects
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "projects: public can read opted-in rows" on projects;
create policy "projects: public can read opted-in rows" on projects
  for select using (public_opt_in = true);

-- ---------- SCANS ----------
create table if not exists scans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  project_id uuid references projects(id) on delete set null,
  target text,                          -- repo URL / pasted-code label shown in history
  score int,
  grade text,
  summary jsonb,                        -- { critical, warning, info }
  created_at timestamptz not null default now()
);

alter table scans enable row level security;

drop policy if exists "scans: owner full access" on scans;
create policy "scans: owner full access" on scans
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------- FINDINGS ----------
create table if not exists findings (
  id uuid primary key default gen_random_uuid(),
  scan_id uuid not null references scans(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  rule_id text,
  severity text,                        -- 'critical' | 'warning' | 'info'
  title text,
  message text,
  file text,
  line int,
  snippet text,
  status text not null default 'open',  -- 'open' | 'fixed' | 'accepted'
  created_at timestamptz not null default now()
);

alter table findings enable row level security;

drop policy if exists "findings: owner full access" on findings;
create policy "findings: owner full access" on findings
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------- Helpful indexes ----------
create index if not exists idx_projects_user on projects(user_id);
create index if not exists idx_scans_user on scans(user_id);
create index if not exists idx_scans_project on scans(project_id);
create index if not exists idx_findings_scan on findings(scan_id);
create index if not exists idx_findings_user on findings(user_id);

-- ================================================================
-- AI USAGE QUOTAS
-- ================================================================
-- Protects your Hive/LLM budget once real users are signed in. Each
-- AI endpoint (chat, explain, report) calls the RPC below before
-- spending a token. Anonymous (signed-out) requests are NOT covered
-- here — they still go through the existing per-minute IP limiter in
-- each api/*.js file. This only applies once someone is signed in,
-- which is also when we can tell free vs. pro apart.

create table if not exists ai_usage_daily (
  user_id uuid not null references profiles(id) on delete cascade,
  usage_date date not null default current_date,
  count int not null default 0,
  primary key (user_id, usage_date)
);

alter table ai_usage_daily enable row level security;

drop policy if exists "ai_usage: owner read" on ai_usage_daily;
create policy "ai_usage: owner read" on ai_usage_daily
  for select using (auth.uid() = user_id);

-- Atomically increments today's counter for the CALLER ONLY (auth.uid(),
-- never a client-supplied id) and returns false once they're over p_limit
-- for the day, rolling the increment back so it doesn't keep counting
-- rejected requests.
create or replace function check_and_increment_ai_usage(p_limit int)
returns boolean as $$
declare
  uid uuid := auth.uid();
  current_count int;
begin
  if uid is null then
    return false;
  end if;

  insert into ai_usage_daily (user_id, usage_date, count)
  values (uid, current_date, 1)
  on conflict (user_id, usage_date) do update set count = ai_usage_daily.count + 1
  returning count into current_count;

  if current_count > p_limit then
    update ai_usage_daily set count = count - 1 where user_id = uid and usage_date = current_date;
    return false;
  end if;

  return true;
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function check_and_increment_ai_usage(int) to authenticated;

