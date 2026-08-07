-- Fix: ol_v_users was unreadable by the very people it exists for.
--
-- The view joins auth.users to pick up last_sign_in_at, and was declared
-- `security_invoker = true` so that RLS on ol_profiles kept a student to
-- their own row. But security_invoker means the query runs with the caller's
-- privileges, and in Supabase the `authenticated` role has no SELECT on
-- auth.users. So every read failed:
--
--   42501: permission denied for table users
--
-- ...including for an admin, which would have made the account panel show an
-- error instead of the roster.
--
-- Switching to a definer view fixes the privilege problem but drops the RLS
-- that was doing the filtering, so the restriction is written into the view
-- body instead: staff see everyone, everyone else sees only themselves. That
-- is the same rule ol_profiles' policy expresses, stated once more here
-- because the view no longer inherits it.

drop view if exists ol_v_users;

create view ol_v_users
-- Definer on purpose. See the note above; this is the only way to expose
-- last_sign_in_at without granting the whole auth.users table.
with (security_invoker = false)
as
select
  p.user_id,
  p.username,
  p.full_name,
  p.role,
  p.level,
  p.must_change_password,
  p.created_at,
  u.last_sign_in_at,
  u.email
from ol_profiles p
join auth.users u on u.id = p.user_id
where ol_is_staff() or p.user_id = auth.uid();

comment on view ol_v_users is
  'Admin roster. SECURITY DEFINER because last_sign_in_at lives in auth.users, '
  'which authenticated has no grant on; the staff/self restriction is in the '
  'WHERE clause instead of borrowed from RLS.';

revoke all on ol_v_users from anon;
grant select on ol_v_users to authenticated;
