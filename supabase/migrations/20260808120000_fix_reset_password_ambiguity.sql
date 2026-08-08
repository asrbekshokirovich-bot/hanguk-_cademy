-- Fix: "column reference \"user_id\" is ambiguous" on Parolni tiklash.
--
-- `ol_admin_reset_password` is declared `returns table (user_id uuid, password
-- text)`, and in PL/pgSQL those output columns are ordinary variables inside
-- the body. So the lookup added by the last migration —
--
--   select role into v_target from ol_profiles where user_id = p_user_id;
--
-- had two candidates for `user_id`: the table's column and the function's own
-- output. Postgres will not guess, and the whole call failed before it ever
-- reached the password.
--
-- Qualifying the column fixes it. The delete function below has the same
-- unqualified reference and no conflict to trip over — it returns void — but
-- it is qualified too, because "correct only because of what this function
-- happens to return" is not a property worth relying on.

create or replace function ol_admin_reset_password(p_user_id uuid)
returns table (user_id uuid, password text)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_password text;
  v_target ol_role;
begin
  if not ol_is_admin() then
    raise exception 'Bu amal uchun administrator huquqi kerak'
      using errcode = '42501';
  end if;

  select p.role into v_target
    from ol_profiles p
   where p.user_id = p_user_id;

  if v_target is null then
    raise exception 'Foydalanuvchi topilmadi';
  end if;

  -- Resetting a password is impersonation with an extra step: whoever reads
  -- the new one can sign in as that person. A plain admin may do it for a
  -- student or a teacher, and for nobody carrying administrator rights.
  if v_target in ('admin', 'superadmin') and not ol_is_super() then
    raise exception 'Administrator parolini faqat super admin tiklay oladi'
      using errcode = '42501';
  end if;

  v_password := ol_generate_password();

  update auth.users u
     set encrypted_password = extensions.crypt(
           v_password, extensions.gen_salt('bf')
         ),
         updated_at = now()
   where u.id = p_user_id;

  -- A password the admin has seen must not stay the account's password.
  update ol_profiles p
     set must_change_password = true
   where p.user_id = p_user_id;

  return query select p_user_id, v_password;
end;
$$;

create or replace function ol_admin_delete_user(p_user_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_target ol_role;
begin
  if not ol_is_admin() then
    raise exception 'Bu amal uchun administrator huquqi kerak'
      using errcode = '42501';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'O''z hisobingizni o''chira olmaysiz';
  end if;

  select p.role into v_target
    from ol_profiles p
   where p.user_id = p_user_id;

  if v_target in ('admin', 'superadmin') and not ol_is_super() then
    raise exception 'Administrator hisobini faqat super admin ochira oladi'
      using errcode = '42501';
  end if;

  -- The last superadmin cannot be removed. Recovering from an academy with no
  -- top-tier account means editing the database by hand.
  if v_target = 'superadmin'
     and (select count(*) from ol_profiles where role = 'superadmin') <= 1 then
    raise exception 'Oxirgi super adminni ochirib bolmaydi';
  end if;

  -- ol_profiles cascades from auth.users.
  delete from auth.users where id = p_user_id;
end;
$$;
