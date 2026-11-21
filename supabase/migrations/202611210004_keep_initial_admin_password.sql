-- The initial Super Admin password remains valid until changed by an administrator.
update public.users
set password_change_required = false
where email = 'sansaibajajhr@gmail.com';
