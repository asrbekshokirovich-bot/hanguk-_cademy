-- Deleting an account respects the two administrator tiers.
--
-- `ol_admin_delete_user` predates the superadmin role and tests
-- `ol_current_role() <> 'admin'`, which gets both halves wrong:
--
--   * a superadmin — the tier that exists to issue and revoke administrator
--     accounts — is refused, so the bin button on the Adminlar screen fails
--     for the only person meant to press it;
--   * an ordinary admin may delete another admin, which is the one thing the
--     split between the tiers was drawn to prevent.
--
-- Same rule as ol_admin_reset_password: staff accounts may be removed by an
-- admin, administrator accounts only by a superadmin.

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

  select p.role into v_target from ol_profiles p where p.user_id = p_user_id;
  if v_target is null then
    raise exception 'Foydalanuvchi topilmadi';
  end if;

  if v_target in ('admin', 'superadmin') and not ol_is_super() then
    raise exception 'Administrator hisobini faqat super admin o''chira oladi'
      using errcode = '42501';
  end if;

  -- ol_profiles cascades from auth.users.
  delete from auth.users where id = p_user_id;
end;
$$;

grant execute on function ol_admin_delete_user(uuid) to authenticated;
