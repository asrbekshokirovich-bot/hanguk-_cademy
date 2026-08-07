-- Username accounts, issued by an administrator.
--
-- There is no public sign-up. An admin creates every student and teacher
-- account and hands over a login and a password.
--
-- Supabase Auth identifies users by email or phone, and most students here
-- have neither in a form they actually use. So each account gets a synthetic
-- address derived from its username:
--
--     aziza.k  ->  aziza.k@users.hanguk-academy.uz
--
-- The domain is never sent mail and does not need to exist. The derivation is
-- pure string concatenation performed on the client, deliberately *not* a
-- lookup: an endpoint that answers "does this username exist?" before login
-- lets anyone enumerate the whole roster.
--
-- Keep the domain in step with `HkAuthNaming.internalEmailDomain` in
-- lib/features/auth/data/username.dart.

-- --------------------------------------------------------- profile shape ---

alter table ol_profiles
  add column if not exists username text,
  -- Set when an admin issues or resets a password. The app forces a change
  -- before it will show anything else, so an admin-known password never stays
  -- valid for long.
  add column if not exists must_change_password boolean not null default false;

-- Lowercase only, and the character set a person can retype from a scrap of
-- paper without ambiguity. No uppercase (so 'Aziza' and 'aziza' cannot both
-- exist), no spaces, no leading or trailing punctuation.
alter table ol_profiles
  drop constraint if exists ol_profiles_username_format;
alter table ol_profiles
  add constraint ol_profiles_username_format
  check (
    username is null
    or username ~ '^[a-z0-9]([a-z0-9._-]{1,30})[a-z0-9]$'
  );

create unique index if not exists ol_profiles_username_key
  on ol_profiles (username);

comment on column ol_profiles.username is
  'Login handle issued by an admin. The auth identity is username@users.hanguk-academy.uz.';

-- ------------------------------------------------------- signup trigger ---

-- Replaces the version in the first migration. Accounts are now created by
-- the admin Edge Function, which passes username, role and level through
-- user metadata; this copies them onto the profile row.
create or replace function ol_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into ol_profiles (
    user_id, full_name, username, role, level, must_change_password
  )
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'username',
      split_part(new.email, '@', 1)
    ),
    nullif(new.raw_user_meta_data ->> 'username', ''),
    coalesce(
      (new.raw_user_meta_data ->> 'role')::ol_role,
      'student'::ol_role
    ),
    (new.raw_user_meta_data ->> 'level')::smallint,
    coalesce((new.raw_user_meta_data ->> 'must_change_password')::boolean, true)
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

-- ------------------------------------------------------------- own row ---

-- The first migration let a user update their own row as long as `role` was
-- unchanged. That still holds, but they must also be able to clear
-- `must_change_password` once they have picked a new one, and must not be
-- able to rename themselves into another person's login.
drop policy if exists ol_profiles_update_own on ol_profiles;
create policy ol_profiles_update_own on ol_profiles
  for update to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and role = ol_current_role()
    and username is not distinct from (
      select p.username from ol_profiles p where p.user_id = auth.uid()
    )
  );

-- ------------------------------------------------------------ roster ---

-- What the admin panel lists. A plain select on ol_profiles would give staff
-- the rows but not the sign-in dates, which are the useful signal for "has
-- this student ever actually logged in?".
create or replace view ol_v_users
with (security_invoker = true)
as
select
  p.user_id,
  p.username,
  p.full_name,
  p.role,
  p.level,
  p.must_change_password,
  p.created_at,
  u.last_sign_in_at
from ol_profiles p
join auth.users u on u.id = p.user_id;

comment on view ol_v_users is
  'Admin roster. security_invoker keeps RLS on ol_profiles in force, so a student sees only themselves.';

grant select on ol_v_users to authenticated;
