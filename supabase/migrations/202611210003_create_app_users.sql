-- Application-managed users. Passwords are stored exclusively as bcrypt hashes.

create extension if not exists pgcrypto;

create table public.users (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  password_hash text not null,
  role public.app_role not null default 'HR_ADMIN',
  organization_id uuid references public.organizations(id) on delete set null,
  employee_id uuid references public.employees(id) on delete set null,
  is_active boolean not null default true,
  password_change_required boolean not null default true,
  last_login_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (email)
);

create unique index users_email_lower_idx on public.users (lower(email));
create index users_organization_idx on public.users (organization_id);
create index users_employee_idx on public.users (employee_id);

create trigger users_set_updated_at
  before update on public.users
  for each row execute procedure private.set_updated_at();

alter table public.users enable row level security;
revoke all on public.users from anon, authenticated;

-- Initial users are provisioned through the protected application admin flow.
-- Never commit user passwords or password hashes to source control.
