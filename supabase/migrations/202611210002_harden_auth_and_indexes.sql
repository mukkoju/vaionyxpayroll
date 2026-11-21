-- Keep auth-trigger helpers off the public API surface and cover foreign keys
-- that are commonly used for joins and deletion checks.

create or replace function private.handle_new_user()
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

drop trigger on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure private.handle_new_user();
drop function public.handle_new_user();

create index profiles_organization_idx on public.profiles (organization_id);
create index employees_pay_schedule_idx on public.employees (pay_schedule_id);
create index payroll_run_items_employee_idx on public.payroll_run_items (employee_id);
create index payroll_runs_created_by_idx on public.payroll_runs (created_by);
create index payroll_runs_approved_by_idx on public.payroll_runs (approved_by);
create index payroll_runs_pay_schedule_idx on public.payroll_runs (pay_schedule_id);
create index payroll_runs_tax_profile_idx on public.payroll_runs (tax_profile_id);
create index audit_events_actor_idx on public.audit_events (actor_id);

drop policy profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles for select to authenticated
  using (id = (select auth.uid()));
