-- Account administration without an Edge Function.
--
-- `supabase/functions/admin-users` does the same three jobs and is the more
-- conventional place for them, but deploying it needs dashboard access that
-- has repeatedly not worked for this project. These functions run inside the
-- database, where SQL Editor access is enough.
--
-- The trade-off, stated plainly: this writes to `auth.users` directly, which
-- Supabase discourages because the schema belongs to GoTrue and may change
-- between releases. The failure mode is visible and recoverable — a new
-- required column would make `ol_admin_create_user` error rather than create
-- a broken account — but it does mean a GoTrue upgrade is a thing to re-test.
-- If the Edge Function is ever deployed, point the app back at it and drop
-- these.
--
-- Security is the same shape as the Edge Function's: SECURITY DEFINER, with
-- an explicit admin check as the first statement. Without that check these
-- would let any signed-in student mint themselves an admin account.

-- ------------------------------------------------------- password maker ---

-- Ambiguous glyphs are left out on purpose: these passwords get read aloud or
-- copied off a screen onto paper, and 0/O, 1/l/I cost more support time than
-- the extra entropy is worth.
create or replace function ol_generate_password(p_length integer default 12)
returns text
language plpgsql
volatile
as $$
declare
  alphabet constant text :=
    'abcdefghjkmnpqrstuvwxyzACDEFGHJKLMNPQRSTUVWXYZ23456789';
  result text := '';
  i integer;
begin
  for i in 1..p_length loop
    -- gen_random_bytes, not random(): this value is the only thing between a
    -- stranger and a student's account.
    result := result || substr(
      alphabet,
      1 + (get_byte(extensions.gen_random_bytes(1), 0) % length(alphabet)),
      1
    );
  end loop;
  return result;
end;
$$;

revoke execute on function ol_generate_password(integer) from public, anon,
  authenticated;

-- ------------------------------------------------------------- create ---

create or replace function ol_admin_create_user(
  p_username   text,
  p_full_name  text,
  p_role       ol_role default 'student',
  p_level      smallint default null
)
returns table (user_id uuid, username text, full_name text, password text)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_username text := lower(trim(p_username));
  v_password text;
  v_id uuid := gen_random_uuid();
  v_email text;
begin
  if ol_current_role() <> 'admin' then
    raise exception 'Bu amal uchun administrator huquqi kerak'
      using errcode = '42501';
  end if;

  if v_username !~ '^[a-z0-9]([a-z0-9._-]{1,30})[a-z0-9]$' then
    raise exception 'Login 3–32 ta belgidan iborat bo''lsin: kichik harflar, raqamlar, nuqta, tire, pastki chiziq';
  end if;

  if length(trim(p_full_name)) < 2 then
    raise exception 'Ism familiya kiriting';
  end if;

  if exists (select 1 from ol_profiles p where p.username = v_username) then
    raise exception '"%" logini band', v_username;
  end if;

  -- Must match HkAuthNaming.internalEmailDomain in the app.
  v_email := v_username || '@users.hanguk-academy.uz';
  v_password := ol_generate_password();

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    -- These are the columns that bite. GoTrue reads them into Go strings and
    -- cannot scan NULL, so an account created without them authenticates
    -- with "Database error querying schema" and no clue why.
    confirmation_token, recovery_token, email_change,
    email_change_token_new, email_change_token_current,
    phone_change, phone_change_token, reauthentication_token
  ) values (
    '00000000-0000-0000-0000-000000000000',
    v_id, 'authenticated', 'authenticated', v_email,
    extensions.crypt(v_password, extensions.gen_salt('bf')),
    -- Confirmed on creation: no mailbox exists behind that domain, so an
    -- unconfirmed account could never be confirmed.
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object(
      'username', v_username,
      'full_name', trim(p_full_name),
      'role', p_role::text,
      'level', p_level,
      'must_change_password', true
    ),
    '', '', '', '', '', '', '', ''
  );

  -- Password sign-in needs an identity row; without it GoTrue reports the
  -- account has no email provider.
  insert into auth.identities (
    provider_id, user_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) values (
    v_id::text, v_id,
    jsonb_build_object(
      'sub', v_id::text, 'email', v_email,
      'email_verified', true, 'phone_verified', false
    ),
    'email', now(), now(), now()
  );

  -- The signup trigger fills ol_profiles from the metadata above.
  return query
    select v_id, v_username, trim(p_full_name), v_password;
end;
$$;

-- --------------------------------------------------------- reset / delete ---

create or replace function ol_admin_reset_password(p_user_id uuid)
returns table (user_id uuid, password text)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_password text;
begin
  if ol_current_role() <> 'admin' then
    raise exception 'Bu amal uchun administrator huquqi kerak'
      using errcode = '42501';
  end if;

  v_password := ol_generate_password();

  update auth.users u
     set encrypted_password = extensions.crypt(
           v_password, extensions.gen_salt('bf')
         ),
         updated_at = now()
   where u.id = p_user_id;

  if not found then
    raise exception 'Foydalanuvchi topilmadi';
  end if;

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
begin
  if ol_current_role() <> 'admin' then
    raise exception 'Bu amal uchun administrator huquqi kerak'
      using errcode = '42501';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'O''z hisobingizni o''chira olmaysiz';
  end if;

  -- ol_profiles cascades from auth.users.
  delete from auth.users where id = p_user_id;
end;
$$;

grant execute on function ol_admin_create_user(text, text, ol_role, smallint)
  to authenticated;
grant execute on function ol_admin_reset_password(uuid) to authenticated;
grant execute on function ol_admin_delete_user(uuid) to authenticated;
