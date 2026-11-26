-- AgriConnect profile privilege hardening.
-- Apply to an existing database after the current schema migrations.
-- Admin access must be granted manually by a trusted project owner in the SQL editor.

create or replace function public.guard_profile_privileges()
returns trigger
language plpgsql
security definer
set search_path = ''
as $agri$
declare
  v_actor uuid := auth.uid();
  v_existing_role public.account_role;
begin
  if tg_op = 'INSERT' then
    -- Signup metadata and direct client inserts can never create an admin
    -- or a verified account. Trusted service-side provisioning may do so.
    if v_actor is not null and new.id = v_actor then
      if new.role = 'admin' or new.is_verified then
        raise exception 'New accounts cannot assign themselves admin or verified status.';
      end if;
    end if;
    return new;
  end if;

  if v_actor is not null then
    select role into v_existing_role
    from public.profiles
    where id = old.id;

    if v_actor = old.id and v_existing_role <> 'admin' then
      if new.role is distinct from old.role
        or new.is_verified is distinct from old.is_verified then
        raise exception 'Only an administrator can change account roles or verification status.';
      end if;
    elsif v_actor <> old.id and not exists (
      select 1 from public.profiles
      where id = v_actor and role = 'admin'
    ) then
      raise exception 'Only an administrator can update another user profile.';
    end if;
  end if;

  return new;
end;
$agri$;

drop trigger if exists guard_profile_privileges on public.profiles;
create trigger guard_profile_privileges
  before insert or update on public.profiles
  for each row execute function public.guard_profile_privileges();

drop policy if exists "Admins can update profiles" on public.profiles;
create policy "Admins can update profiles"
  on public.profiles for update to authenticated
  using (exists (
    select 1 from public.profiles admin_profile
    where admin_profile.id = auth.uid() and admin_profile.role = 'admin'
  ))
  with check (exists (
    select 1 from public.profiles admin_profile
    where admin_profile.id = auth.uid() and admin_profile.role = 'admin'
  ));

-- Recreate the signup trigger function so metadata cannot request admin.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $agri$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    case
      when new.raw_user_meta_data ->> 'role' in ('farmer','buyer','supplier','logistics')
        then (new.raw_user_meta_data ->> 'role')::public.account_role
      else 'farmer'::public.account_role
    end
  );
  return new;
end;
$agri$;

