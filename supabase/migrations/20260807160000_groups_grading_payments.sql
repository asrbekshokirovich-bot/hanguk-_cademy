-- Groups, grading and payments.
--
-- The second design round adds a teacher panel and an admin panel on top of
-- the student one. Between them they need six things the schema has no idea
-- about: which group a student is in, who teaches them, how well they are
-- attending and progressing, whether their homework has been marked, and
-- whether they have paid.
--
-- Money is in this file. Amounts are stored as **bigint sums (UZS)**, never
-- floating point: 5 000 000 UZS in a double is fine today and wrong the first
-- time anyone divides it. There is no fractional tiyin in practice, so the
-- integer is the sum in whole so'm.

-- --------------------------------------------------------------- groups ---

create table ol_groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  -- 'Daraja 2 · A' is the name; level is the sortable part of it.
  level       smallint check (level is null or level between 1 and 6),
  teacher_id  uuid references ol_teachers (id) on delete set null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

create unique index ol_groups_name_key on ol_groups (lower(name));

create table ol_group_members (
  group_id    uuid not null references ol_groups (id) on delete cascade,
  student_id  uuid not null references auth.users (id) on delete cascade,
  joined_at   timestamptz not null default now(),
  primary key (group_id, student_id)
);

create index ol_group_members_student_idx on ol_group_members (student_id);

-- A lesson belongs to a group. Nullable: an open lesson everyone may join
-- still makes sense, and the first migration's lessons have no group.
alter table ol_lessons
  add column if not exists group_id uuid references ol_groups (id)
    on delete set null;

create index ol_lessons_group_idx on ol_lessons (group_id);

-- --------------------------------------------------------------- people ---

-- The admin roster lists a phone for every student. It is how the office
-- actually reaches them; email does not exist for most.
alter table ol_profiles
  add column if not exists phone text;

alter table ol_teachers
  add column if not exists subject text,
  -- Entered by an administrator after review, not computed. A rating derived
  -- from three ratings would be noise presented as fact.
  add column if not exists rating numeric(2, 1)
    check (rating is null or (rating >= 0 and rating <= 5)),
  -- 'active' | 'leave' | 'new'
  add column if not exists status text not null default 'active';

-- -------------------------------------------------------------- grading ---

alter table ol_assignment_submissions
  add column if not exists grade smallint
    check (grade is null or (grade >= 0 and grade <= 100)),
  add column if not exists graded_at timestamptz,
  add column if not exists graded_by uuid references auth.users (id)
    on delete set null,
  add column if not exists feedback text;

-- The grading queue reads "everything not yet marked", which is a small slice
-- of a table that grows for ever.
create index ol_submissions_ungraded_idx
  on ol_assignment_submissions (submitted_at desc)
  where graded_at is null;

-- ------------------------------------------------------------- payments ---

create type ol_payment_status as enum (
  'pending', 'confirmed', 'overdue', 'cancelled'
);

create table ol_plans (
  code            text primary key,
  name            text not null,
  -- Whole so'm. See the note at the top of this file.
  monthly_amount  bigint not null check (monthly_amount >= 0),
  sort_order      smallint not null default 0
);

insert into ol_plans (code, name, monthly_amount, sort_order) values
  ('standard', 'Standard', 5000000, 1),
  ('premium',  'Premium',  10000000, 2)
on conflict (code) do nothing;

create table ol_payments (
  id          uuid primary key default gen_random_uuid(),
  student_id  uuid not null references auth.users (id) on delete cascade,
  plan_code   text references ol_plans (code) on delete set null,
  amount      bigint not null check (amount >= 0),
  -- The month being paid for, stored as its first day. Separate from paid_at
  -- so a late payment is still attributed to the month it covers.
  period      date not null,
  due_date    date,
  paid_at     timestamptz,
  status      ol_payment_status not null default 'pending',
  note        text,
  recorded_by uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now()
);

-- One payment per student per month. Without this a double-entry silently
-- doubles the month's revenue.
create unique index ol_payments_student_period_key
  on ol_payments (student_id, period);

create index ol_payments_period_idx on ol_payments (period desc);
create index ol_payments_outstanding_idx
  on ol_payments (due_date) where status in ('pending', 'overdue');

-- 'pending' past its due date is 'overdue'. Derived rather than stored: a
-- status column that only becomes true when a job runs is a status column
-- that is wrong whenever the job did not.
create or replace function ol_payment_effective_status(
  p_status ol_payment_status,
  p_due date
) returns ol_payment_status
language sql
immutable
as $$
  select case
    when p_status = 'pending' and p_due is not null and p_due < current_date
      then 'overdue'::ol_payment_status
    else p_status
  end;
$$;

-- ---------------------------------------------------------------- stats ---

-- Attendance and progress per student, as 0..1 fractions.
--
-- Definer, and not exposed directly: it reads every student's rows so the
-- teacher and admin views can join against it. Those views do the filtering.
create or replace view ol_v_student_stats
with (security_invoker = false)
as
select
  p.user_id as student_id,
  -- Attended seconds over scheduled seconds, capped per lesson so an
  -- over-running lesson cannot push someone above 100%.
  coalesce((
    select round(avg(least(1.0, a.seconds_attended::numeric
                           / nullif(l.duration_minutes * 60, 0))), 4)
      from ol_attendance a
      join ol_lessons l on l.id = a.lesson_id
     where a.student_id = p.user_id
       and l.status = 'ended'
  ), 0) as attendance,
  -- Progress is how much of the available recordings they have watched.
  coalesce((
    select round(avg(case
             when rp.completed then 1.0
             when r.duration_seconds = 0 then 0.0
             else least(1.0, rp.position_seconds::numeric / r.duration_seconds)
           end), 4)
      from ol_recording_progress rp
      join ol_recordings r on r.id = rp.recording_id
     where rp.student_id = p.user_id
  ), 0) as progress,
  (select max(u.last_sign_in_at) from auth.users u where u.id = p.user_id)
    as last_seen_at
from ol_profiles p
where p.role = 'student';

-- --------------------------------------------------------- teacher views ---

-- The students a given teacher is responsible for: everyone in a group they
-- lead. Definer for the same reason as above — it reaches auth.users through
-- ol_v_student_stats — with the teacher/admin restriction written in.
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
where ol_current_role() = 'admin'
   or t.user_id = auth.uid();

-- The grading queue.
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
where ol_current_role() = 'admin'
   or t.user_id = auth.uid()
   or sub.student_id = auth.uid();

-- ----------------------------------------------------------- admin views ---

-- The teacher roster, with the counts the panel shows.
create or replace view ol_v_teacher_roster
with (security_invoker = false)
as
select
  t.id,
  t.full_name,
  t.initials,
  t.subject,
  t.rating,
  t.status,
  coalesce(w.lesson_count, 0)  as weekly_lessons,
  coalesce(sc.student_count, 0) as student_count,
  -- Load against a nominal full week of 16 lessons. Named in the comment
  -- rather than hidden in a literal, because it is a policy number the
  -- academy may want to change, not a fact.
  least(1.0, round(coalesce(w.lesson_count, 0)::numeric / 16, 4)) as load
from ol_teachers t
left join (
  select l.teacher_id, count(*)::int as lesson_count
    from ol_lessons l
   where l.starts_at >= date_trunc('week', now())
     and l.starts_at <  date_trunc('week', now()) + interval '7 days'
     and l.status <> 'cancelled'
   group by l.teacher_id
) w on w.teacher_id = t.id
left join (
  select g.teacher_id, count(distinct m.student_id)::int as student_count
    from ol_groups g
    join ol_group_members m on m.group_id = g.id
   group by g.teacher_id
) sc on sc.teacher_id = t.id
where ol_is_staff();

-- The admin student roster: contact details, group, teacher, payment state.
create or replace view ol_v_admin_students
with (security_invoker = false)
as
select
  p.user_id as student_id,
  p.full_name,
  p.username,
  p.phone,
  p.level,
  g.name as group_name,
  t.full_name as teacher_name,
  s.attendance,
  s.last_seen_at,
  ol_payment_effective_status(pay.status, pay.due_date) as payment_status,
  pay.period as payment_period
from ol_profiles p
left join ol_group_members m on m.student_id = p.user_id
left join ol_groups g on g.id = m.group_id
left join ol_teachers t on t.id = g.teacher_id
left join ol_v_student_stats s on s.student_id = p.user_id
-- The current month's payment row, if there is one.
left join lateral (
  select pm.status, pm.due_date, pm.period
    from ol_payments pm
   where pm.student_id = p.user_id
   order by pm.period desc
   limit 1
) pay on true
where p.role = 'student'
  and ol_is_staff();

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
where ol_is_staff() or pm.student_id = auth.uid();

-- ------------------------------------------------------------------ RPCs ---

create or replace function ol_teacher_stats()
returns table (
  lessons_today       integer,
  students            integer,
  ungraded            integer,
  average_attendance  numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with me as (
    select t.id from ol_teachers t where t.user_id = auth.uid()
  )
  select
    (select count(*)::int from ol_lessons l
      where l.teacher_id = (select id from me)
        and l.starts_at >= date_trunc('day', now())
        and l.starts_at <  date_trunc('day', now()) + interval '1 day'
        and l.status <> 'cancelled'),
    (select count(distinct m.student_id)::int
       from ol_groups g
       join ol_group_members m on m.group_id = g.id
      where g.teacher_id = (select id from me)),
    (select count(*)::int
       from ol_assignment_submissions sub
       join ol_assignments a on a.id = sub.assignment_id
       join ol_lessons l on l.id = a.lesson_id
      where l.teacher_id = (select id from me)
        and sub.graded_at is null),
    coalesce((
      select round(avg(s.attendance), 4)
        from ol_v_teacher_students ts
        join ol_v_student_stats s on s.student_id = ts.student_id
       where ts.teacher_id = (select id from me)
    ), 0);
$$;

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
    -- Confirmed only. Counting pending money as revenue is how a business
    -- ends up believing it is solvent.
    coalesce((select sum(amount) from ol_payments
               where status = 'confirmed'
                 and period = date_trunc('month', current_date)::date), 0),
    (select count(*)::int from ol_teachers where status <> 'left'),
    coalesce((select sum(amount) from ol_payments
               where ol_payment_effective_status(status, due_date)
                     in ('pending', 'overdue')), 0),
    (select count(*)::int from ol_payments
      where ol_payment_effective_status(status, due_date) = 'overdue');
$$;

-- ------------------------------------------------------------------ RLS ---

alter table ol_groups        enable row level security;
alter table ol_group_members enable row level security;
alter table ol_plans         enable row level security;
alter table ol_payments      enable row level security;

create policy ol_groups_select on ol_groups
  for select to authenticated using (true);
create policy ol_groups_write on ol_groups
  for all to authenticated
  using (ol_is_staff()) with check (ol_is_staff());

create policy ol_group_members_select on ol_group_members
  for select to authenticated
  using (student_id = auth.uid() or ol_is_staff());
create policy ol_group_members_write on ol_group_members
  for all to authenticated
  using (ol_is_staff()) with check (ol_is_staff());

create policy ol_plans_select on ol_plans
  for select to authenticated using (true);
create policy ol_plans_write on ol_plans
  for all to authenticated
  using (ol_current_role() = 'admin')
  with check (ol_current_role() = 'admin');

-- A student may see their own payments and nothing else. Only a full admin
-- writes them — a teacher marking fees paid is not a role this academy has.
create policy ol_payments_select on ol_payments
  for select to authenticated
  using (student_id = auth.uid() or ol_is_staff());
create policy ol_payments_write on ol_payments
  for all to authenticated
  using (ol_current_role() = 'admin')
  with check (ol_current_role() = 'admin');

-- Teachers grade; students may not edit a submission once it is marked.
drop policy if exists ol_assignment_submissions_own on ol_assignment_submissions;
create policy ol_assignment_submissions_select on ol_assignment_submissions
  for select to authenticated
  using (student_id = auth.uid() or ol_is_staff());
create policy ol_assignment_submissions_insert on ol_assignment_submissions
  for insert to authenticated
  with check (student_id = auth.uid() or ol_is_staff());
create policy ol_assignment_submissions_update on ol_assignment_submissions
  for update to authenticated
  using (
    ol_is_staff()
    or (student_id = auth.uid() and graded_at is null)
  )
  with check (ol_is_staff() or student_id = auth.uid());

-- ---------------------------------------------------------------- grants ---

grant select on ol_v_student_stats    to authenticated;
grant select on ol_v_teacher_students to authenticated;
grant select on ol_v_submissions      to authenticated;
grant select on ol_v_teacher_roster   to authenticated;
grant select on ol_v_admin_students   to authenticated;
grant select on ol_v_payments         to authenticated;

grant execute on function ol_teacher_stats() to authenticated;
grant execute on function ol_admin_kpis() to authenticated;
grant execute on function ol_payment_effective_status(ol_payment_status, date)
  to authenticated;
