-- Vaionyx Payroll: organisation-aware core data model.
-- Authentication identities remain in auth.users; this schema never stores passwords.

create schema if not exists private;

create type public.app_role as enum ('SUPER_ADMIN', 'HR_ADMIN', 'PAYROLL_OFFICER');
create type public.employee_status as enum ('ACTIVE', 'ON_LEAVE', 'INACTIVE', 'TERMINATED');
create type public.pay_frequency as enum ('WEEKLY', 'BIWEEKLY', 'SEMIMONTHLY', 'MONTHLY');
create type public.payroll_run_status as enum ('DRAFT', 'CALCULATING', 'READY_FOR_REVIEW', 'APPROVED', 'PAID', 'CANCELLED');

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  legal_name text not null,
  display_name text not null,
  registration_number text,
  tax_identifier text,
  email text,
  phone text,
  address_line_1 text,
  address_line_2 text,
  city text,
  state_or_province text,
  postal_code text,
  country_code char(2),
  currency_code char(3) not null default 'INR',
  timezone text not null default 'Asia/Kolkata',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid references public.organizations(id) on delete set null,
  email text not null,
  full_name text,
  role public.app_role not null default 'HR_ADMIN',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.pay_schedules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  frequency public.pay_frequency not null,
  next_pay_date date,
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, name)
);

create table public.tax_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  country_code char(2) not null,
  effective_from date not null,
  effective_to date,
  configuration jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, name, effective_from),
  check (effective_to is null or effective_to >= effective_from)
);

create table public.employees (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_number text not null,
  first_name text not null,
  last_name text,
  work_email text,
  department text,
  job_title text,
  status public.employee_status not null default 'ACTIVE',
  hire_date date,
  termination_date date,
  pay_schedule_id uuid references public.pay_schedules(id) on delete set null,
  annual_salary numeric(14,2),
  currency_code char(3) not null default 'INR',
  tax_identifier text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, employee_number),
  check (annual_salary is null or annual_salary >= 0)
);

create table public.payroll_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  pay_schedule_id uuid references public.pay_schedules(id) on delete set null,
  tax_profile_id uuid references public.tax_profiles(id) on delete set null,
  name text not null,
  period_start date not null,
  period_end date not null,
  pay_date date not null,
  status public.payroll_run_status not null default 'DRAFT',
  gross_total numeric(14,2) not null default 0,
  deductions_total numeric(14,2) not null default 0,
  net_total numeric(14,2) not null default 0,
  created_by uuid references public.profiles(id) on delete set null,
  approved_by uuid references public.profiles(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (period_end >= period_start)
);

create table public.payroll_run_items (
  id uuid primary key default gen_random_uuid(),
  payroll_run_id uuid not null references public.payroll_runs(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete restrict,
  gross_pay numeric(14,2) not null default 0,
  deductions jsonb not null default '[]'::jsonb,
  deductions_total numeric(14,2) not null default 0,
  net_pay numeric(14,2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (payroll_run_id, employee_id),
  check (gross_pay >= 0 and deductions_total >= 0 and net_pay >= 0)
);

create table public.audit_events (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  entity_type text not null,
  entity_id uuid,
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index employees_organization_status_idx on public.employees (organization_id, status);
create index payroll_runs_organization_pay_date_idx on public.payroll_runs (organization_id, pay_date desc);
create index payroll_run_items_payroll_run_idx on public.payroll_run_items (payroll_run_id);
create index audit_events_organization_created_idx on public.audit_events (organization_id, created_at desc);

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create or replace function private.current_organization_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select organization_id from public.profiles where id = auth.uid()
$$;

revoke all on function private.current_organization_id() from public;
grant usage on schema private to authenticated;
grant execute on function private.current_organization_id() to authenticated;

-- Apply updated_at consistently to mutable records.
create trigger organizations_set_updated_at before update on public.organizations for each row execute procedure private.set_updated_at();
create trigger profiles_set_updated_at before update on public.profiles for each row execute procedure private.set_updated_at();
create trigger pay_schedules_set_updated_at before update on public.pay_schedules for each row execute procedure private.set_updated_at();
create trigger tax_profiles_set_updated_at before update on public.tax_profiles for each row execute procedure private.set_updated_at();
create trigger employees_set_updated_at before update on public.employees for each row execute procedure private.set_updated_at();
create trigger payroll_runs_set_updated_at before update on public.payroll_runs for each row execute procedure private.set_updated_at();
create trigger payroll_run_items_set_updated_at before update on public.payroll_run_items for each row execute procedure private.set_updated_at();

alter table public.organizations enable row level security;
alter table public.profiles enable row level security;
alter table public.pay_schedules enable row level security;
alter table public.tax_profiles enable row level security;
alter table public.employees enable row level security;
alter table public.payroll_runs enable row level security;
alter table public.payroll_run_items enable row level security;
alter table public.audit_events enable row level security;

-- A signed-in user sees only their organisation. Mutations are handled by the API.
create policy organizations_select_own on public.organizations for select to authenticated
  using (id = (select private.current_organization_id()));
create policy profiles_select_own on public.profiles for select to authenticated
  using (id = auth.uid());
create policy pay_schedules_select_org on public.pay_schedules for select to authenticated
  using (organization_id = (select private.current_organization_id()));
create policy tax_profiles_select_org on public.tax_profiles for select to authenticated
  using (organization_id = (select private.current_organization_id()));
create policy employees_select_org on public.employees for select to authenticated
  using (organization_id = (select private.current_organization_id()));
create policy payroll_runs_select_org on public.payroll_runs for select to authenticated
  using (organization_id = (select private.current_organization_id()));
create policy payroll_run_items_select_org on public.payroll_run_items for select to authenticated
  using (payroll_run_id in (select id from public.payroll_runs where organization_id = (select private.current_organization_id())));
create policy audit_events_select_org on public.audit_events for select to authenticated
  using (organization_id = (select private.current_organization_id()));

revoke all on all tables in schema public from anon;
grant select on public.organizations, public.profiles, public.pay_schedules, public.tax_profiles,
  public.employees, public.payroll_runs, public.payroll_run_items, public.audit_events to authenticated;
