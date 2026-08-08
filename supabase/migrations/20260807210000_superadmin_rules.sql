-- Step 2 of 2. Run 20260807200000 first, on its own.
--
-- Splits the admin tier in two.
--
--   superadmin  runs the business: issues administrator accounts, and is the
--               only role that sees money.
--   admin       runs the school day: students, teachers, groups, the
--               timetable. Cannot mint an administrator, cannot open finance.
--
-- The point of the split is that the two jobs carry different risk. Scheduling
-- a lesson wrongly is a bad afternoon; issuing yourself an administrator
-- account, or reading and editing what everyone has paid, is a different
-- category of thing. An academy hires office staff for the first job long
-- before it wants to hand over the second.
--
-- Everything below is enforced in the database, not only in the app. The
-- dock hides what a role cannot do, but a hidden menu item is not access
-- control.

-- ---------------------------------------------------------- role helpers ---

-- Superadmin teaches nothing and is not "staff who see a classroom", but it
-- outranks admin everywhere, so it is included in both.
create or replace function ol_is_staff()
returns boolean
language sql
stable
as $$
  select ol_current_role() in ('teacher', 'admin', 'superadmin');
$$;

-- Either administrator tier. Most admin screens use this.
create or replace function ol_is_admin()
returns boolean
language sql
stable
as $$
  select ol_current_role() in ('admin', 'superadmin');
$$;

-- The top tier only: accounts with admin rights, and money.
create or replace function ol_is_super()
returns boolean
language sql
stable
as $$
  select ol_current_role() = 'superadmin';
$$;

grant execute on function ol_is_admin() to authenticated;
grant execute on function ol_is_super() to authenticated;

-- ------------------------------------------------------ profiles, re-cut ---

-- A plain admin may maintain student and teacher rows and nothing else. Both
-- clauses matter, and for different reasons:
--
--   with check  stops an admin creating or promoting anyone into an
--               administrator — including themselves, which is the obvious
--               attack on a two-tier scheme.
--   using       stops an admin reaching an existing administrator's row at
--               all, so they cannot demote a superadmin to 'teacher' and walk
--               in through the front door instead.
drop policy if exists ol_profiles_admin_all on ol_profiles;
create policy ol_profiles_admin_all on ol_profiles
  for all to authenticated
  using (
    ol_is_super()
    or (ol_is_admin() and role in ('student', 'teacher'))
  )
  with check (
    ol_is_super()
    or (ol_is_admin() and role in ('student', 'teacher'))
  );

-- The account roster hides administrators from a plain admin. They could not
-- act on those rows anyway; listing people you cannot touch only invites the
-- attempt.
drop view if exists ol_v_users;
create view ol_v_users
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
where p.user_id = auth.uid()
   or ol_is_super()
   or (ol_is_staff() and p.role in ('student', 'teacher'));

revoke all on ol_v_users from anon;
grant select on ol_v_users to authenticated;

-- --------------------------------------------- views that said 'admin' ---

-- These two were written before the tier existed and compare to the literal
-- 'admin', which would now lock a superadmin out of the screens it outranks.
--
-- Only the WHERE clause changes. `create or replace view` refuses to drop or
-- rename a column ("42P16: cannot drop columns from view"), so the select
-- list below is the original one character for character — retyping it from
-- memory is what produced that error the first time.

create or replace view ol_v_teacher_students
with (security_invoker = false)
as
select
  p.user_id as student_id,
  p.full_name,
  p.username,
  g.id      as group_id,
  g.name    as group_name,
  t.id      as teacher_id,
  s.attendance,
  s.progress,
  s.last_seen_at
from ol_group_members m
join ol_groups g on g.id = m.group_id
join ol_teachers t on t.id = g.teacher_id
join ol_profiles p on p.user_id = m.student_id
left join ol_v_student_stats s on s.student_id = m.student_id
where ol_is_admin()
   or t.user_id = auth.uid();

create or replace view ol_v_submissions
with (security_invoker = false)
as
select
  sub.assignment_id,
  sub.student_id,
  p.full_name    as student_name,
  a.title        as assignment_title,
  l.title        as lesson_title,
  sub.submitted_at,
  sub.grade,
  sub.graded_at,
  sub.file_url,
  sub.note
from ol_assignment_submissions sub
join ol_assignments a on a.id = sub.assignment_id
join ol_lessons l on l.id = a.lesson_id
join ol_profiles p on p.user_id = sub.student_id
left join ol_teachers t on t.id = l.teacher_id
where ol_is_admin()
   or t.user_id = auth.uid()
   or sub.student_id = auth.uid();

-- ----------------------------------------------------------------- money ---

-- Payments are superadmin-only, in both directions. A student still sees
-- their own — they are entitled to know what they owe — but a plain admin
-- sees no amounts at all.
drop policy if exists ol_payments_select on ol_payments;
create policy ol_payments_select on ol_payments
  for select to authenticated
  using (student_id = auth.uid() or ol_is_super());

drop policy if exists ol_payments_write on ol_payments;
create policy ol_payments_write on ol_payments
  for all to authenticated
  using (ol_is_super()) with check (ol_is_super());

drop policy if exists ol_plans_write on ol_plans;
create policy ol_plans_write on ol_plans
  for all to authenticated
  using (ol_is_super()) with check (ol_is_super());

create or replace view ol_v_payments
with (security_invoker = false)
as
select
  pm.id,
  pm.student_id,
  p.full_name as student_name,
  pm.plan_code,
  pl.name as plan_name,
  pm.amount,
  pm.period,
  pm.due_date,
  pm.paid_at,
  ol_payment_effective_status(pm.status, pm.due_date) as status,
  pm.note
from ol_payments pm
join ol_profiles p on p.user_id = pm.student_id
left join ol_plans pl on pl.code = pm.plan_code
where ol_is_super() or pm.student_id = auth.uid();

-- The dashboard's headline numbers. The two money figures come back as zero
-- for anyone below superadmin — the screen hides those cards, and this makes
-- sure hiding them is not the only thing standing in the way. Whether a
-- student has paid stays visible to an admin; that is a register question,
-- not a finance one, and it carries no amount.
create or replace function ol_admin_kpis()
returns table (
  active_students     integer,
  weekly_lessons      integer,
  average_attendance  numeric,
  month_revenue       bigint,
  teacher_count       integer,
  outstanding_amount  bigint,
  outstanding_count   integer
)
language sql
stable
security definer
set search_path = public
as $$
  select
    (select count(*)::int from ol_profiles where role = 'student'),
    (select count(*)::int from ol_lessons
      where starts_at >= date_trunc('week', now())
        and starts_at <  date_trunc('week', now()) + interval '7 days'
        and status <> 'cancelled'),
    coalesce((select round(avg(attendance), 4) from ol_v_student_stats), 0),
    case when ol_is_super() then
      coalesce((select sum(amount) from ol_payments
                 where status = 'confirmed'
                   and period = date_trunc('month', current_date)::date), 0)
    else 0::bigint end,
    (select count(*)::int from ol_teachers where status <> 'left'),
    case when ol_is_super() then
      coalesce((select sum(amount) from ol_payments
                 where ol_payment_effective_status(status, due_date)
                       in ('pending', 'overdue')), 0)
    else 0::bigint end,
    case when ol_is_super() then
      (select count(*)::int from ol_payments
        where ol_payment_effective_status(status, due_date) = 'overdue')
    else 0 end;
$$;

-- -------------------------------------------------------------- accounts ---

-- Creating an account: both tiers may, but only a superadmin may create one
-- that carries administrator rights. Checked here rather than only in the
-- dialog's role picker, because the RPC is reachable directly.
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
  if not ol_is_admin() then
    raise exception 'Bu amal uchun administrator huquqi kerak'
      using errcode = '42501';
  end if;

  if p_role in ('admin', 'superadmin') and not ol_is_super() then
    raise exception 'Administrator hisobini faqat super admin ocha oladi'
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

  return query
    select v_id, v_username, trim(p_full_name), v_password;
end;
$$;

-- Resetting a password is impersonation with an extra step: whoever reads the
-- new password can sign in as that person. So a plain admin may reset a
-- student or a teacher, and nobody with administrator rights.
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

  select role into v_target from ol_profiles where user_id = p_user_id;
  if v_target is null then
    raise exception 'Foydalanuvchi topilmadi';
  end if;

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

  select role into v_target from ol_profiles where user_id = p_user_id;

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

-- --------------------------------------------------- promote the founder ---

-- The academy's owner. Without this there is no superadmin and nobody can
-- create one, because creating one requires being one.
update ol_profiles set role = 'superadmin' where username = 'admin';

-- Should print one superadmin.
select username, full_name, role from ol_profiles order by role, username;
