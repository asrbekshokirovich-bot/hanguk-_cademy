-- Hanguk Academy — Onlayn ta'lim (online lessons) schema.
--
-- Everything lives under the `ol_` prefix so this product can share a
-- Supabase project with the existing student app / CRM without any chance of
-- a name collision.
--
-- Roles come from `ol_profiles.role`:
--   student — sees lessons they are enrolled in, their own progress
--   teacher — the above, plus manages lessons they teach
--   admin   — full read/write across the product
--
-- Live video is deliberately absent. `ol_lessons.live_room` is reserved for
-- the LiveKit room name so the media layer can land later without a schema
-- change; nothing writes it yet.

-- ---------------------------------------------------------------- enums ---

create type ol_lesson_status as enum ('scheduled', 'live', 'ended', 'cancelled');
create type ol_material_kind as enum ('pdf', 'doc', 'link', 'audio');
create type ol_role as enum ('student', 'teacher', 'admin');

-- ------------------------------------------------------------- profiles ---

create table ol_profiles (
  user_id     uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null,
  -- Denormalised on purpose: the design puts initials on avatars in lists
  -- that would otherwise need the full name only to throw it away.
  initials    text,
  role        ol_role not null default 'student',
  -- Korean level 1..6, null for staff.
  level       smallint check (level is null or level between 1 and 6),
  created_at  timestamptz not null default now()
);

comment on table ol_profiles is
  'Per-user record for the online lessons product. Role drives every RLS policy below.';

-- Used by every policy; a plain function keeps the policies readable and lets
-- Postgres inline it. SECURITY DEFINER so a student may check their own role
-- without holding select on the whole table.
create or replace function ol_current_role()
returns ol_role
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role from ol_profiles where user_id = auth.uid()),
    'student'::ol_role
  );
$$;

create or replace function ol_is_staff()
returns boolean
language sql
stable
as $$
  select ol_current_role() in ('teacher', 'admin');
$$;

-- ------------------------------------------------------------- teachers ---

create table ol_teachers (
  id          uuid primary key default gen_random_uuid(),
  -- Nullable: a teacher can be listed on the schedule before they have an
  -- account (and guest teachers may never get one).
  user_id     uuid unique references auth.users (id) on delete set null,
  full_name   text not null,
  initials    text,
  avatar_url  text,
  created_at  timestamptz not null default now()
);

-- -------------------------------------------------------------- lessons ---

create table ol_lessons (
  id                uuid primary key default gen_random_uuid(),
  title             text not null,
  category          text not null default 'Koreys tili',
  description       text,
  teacher_id        uuid references ol_teachers (id) on delete set null,
  starts_at         timestamptz not null,
  duration_minutes  integer not null default 60 check (duration_minutes > 0),
  status            ol_lesson_status not null default 'scheduled',
  auto_record       boolean not null default true,
  -- Reserved for LiveKit. See the header note.
  live_room         text,
  created_by        uuid references auth.users (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- The schedule view and the dashboard both order by start time inside a
-- window, and the dashboard filters "today" on every load.
create index ol_lessons_starts_at_idx on ol_lessons (starts_at desc);
-- Partial: 'live' is one row out of thousands, and both the dock's live dot
-- and the dashboard hero look it up on every poll.
create index ol_lessons_live_idx on ol_lessons (starts_at) where status = 'live';

create table ol_enrollments (
  lesson_id   uuid not null references ol_lessons (id) on delete cascade,
  student_id  uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (lesson_id, student_id)
);

create index ol_enrollments_student_idx on ol_enrollments (student_id);

create table ol_attendance (
  lesson_id         uuid not null references ol_lessons (id) on delete cascade,
  student_id        uuid not null references auth.users (id) on delete cascade,
  joined_at         timestamptz not null default now(),
  left_at           timestamptz,
  -- Accumulated across rejoins, so a dropped connection doesn't zero a
  -- student's attendance for the lesson.
  seconds_attended  integer not null default 0,
  primary key (lesson_id, student_id)
);

-- ----------------------------------------------------------- recordings ---

create table ol_recordings (
  id                uuid primary key default gen_random_uuid(),
  lesson_id         uuid references ol_lessons (id) on delete set null,
  title             text not null,
  category          text not null default 'Koreys tili',
  description       text,
  teacher_id        uuid references ol_teachers (id) on delete set null,
  recorded_at       timestamptz not null,
  duration_seconds  integer not null default 0 check (duration_seconds >= 0),
  video_url         text,
  thumbnail_url     text,
  attendee_count    integer not null default 0,
  -- Hidden from students until the teacher publishes; auto-recordings land
  -- unpublished so a mis-started room never shows up in the library.
  published         boolean not null default true,
  created_at        timestamptz not null default now()
);

create index ol_recordings_recorded_at_idx on ol_recordings (recorded_at desc);
create index ol_recordings_category_idx on ol_recordings (category);

create table ol_recording_progress (
  recording_id      uuid not null references ol_recordings (id) on delete cascade,
  student_id        uuid not null references auth.users (id) on delete cascade,
  position_seconds  integer not null default 0 check (position_seconds >= 0),
  completed         boolean not null default false,
  updated_at        timestamptz not null default now(),
  primary key (recording_id, student_id)
);

-- ------------------------------------------- materials / quiz / homework ---

create table ol_materials (
  id          uuid primary key default gen_random_uuid(),
  lesson_id   uuid not null references ol_lessons (id) on delete cascade,
  name        text not null,
  kind        ol_material_kind not null default 'link',
  url         text not null,
  size_bytes  bigint,
  created_at  timestamptz not null default now()
);

create index ol_materials_lesson_idx on ol_materials (lesson_id);

create table ol_quizzes (
  id              uuid primary key default gen_random_uuid(),
  lesson_id       uuid not null references ol_lessons (id) on delete cascade,
  title           text not null default 'Dars testi',
  question_count  integer not null default 0 check (question_count >= 0),
  created_at      timestamptz not null default now()
);

create index ol_quizzes_lesson_idx on ol_quizzes (lesson_id);

create table ol_quiz_attempts (
  quiz_id       uuid not null references ol_quizzes (id) on delete cascade,
  student_id    uuid not null references auth.users (id) on delete cascade,
  score         integer,
  completed_at  timestamptz,
  primary key (quiz_id, student_id)
);

create table ol_assignments (
  id          uuid primary key default gen_random_uuid(),
  lesson_id   uuid not null references ol_lessons (id) on delete cascade,
  title       text not null default 'Uy vazifasi',
  body        text,
  due_at      timestamptz,
  created_at  timestamptz not null default now()
);

create index ol_assignments_lesson_idx on ol_assignments (lesson_id);

create table ol_assignment_submissions (
  assignment_id  uuid not null references ol_assignments (id) on delete cascade,
  student_id     uuid not null references auth.users (id) on delete cascade,
  submitted_at   timestamptz not null default now(),
  file_url       text,
  note           text,
  primary key (assignment_id, student_id)
);

-- ----------------------------------------------------------- updated_at ---

create or replace function ol_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger ol_lessons_touch
  before update on ol_lessons
  for each row execute function ol_touch_updated_at();

-- ---------------------------------------------------------------- views ---

-- Lessons with the teacher inlined and the enrolment count folded in. Both
-- the schedule table and the dashboard read this instead of issuing a
-- separate count query per row.
create or replace view ol_v_lessons
with (security_invoker = true)
as
select
  l.id,
  l.title,
  l.category,
  l.description,
  l.starts_at,
  l.duration_minutes,
  l.status,
  l.auto_record,
  l.live_room,
  coalesce(e.enrolled_count, 0) as enrolled_count,
  case
    when t.id is null then null
    else jsonb_build_object(
      'id', t.id,
      'full_name', t.full_name,
      'initials', t.initials,
      'avatar_url', t.avatar_url
    )
  end as teacher,
  -- Flat copy of the teacher's name purely so search can ilike it; the jsonb
  -- object above is what the app actually reads.
  t.full_name as teacher_name
from ol_lessons l
left join ol_teachers t on t.id = l.teacher_id
left join (
  select lesson_id, count(*)::int as enrolled_count
  from ol_enrollments
  group by lesson_id
) e on e.lesson_id = l.id;

-- Recordings with the teacher inlined and *the caller's own* watch progress
-- as a 0..1 fraction. Doing this in SQL keeps the library one round trip.
create or replace view ol_v_recordings
with (security_invoker = true)
as
select
  r.id,
  r.lesson_id,
  r.title,
  r.category,
  r.description,
  r.recorded_at,
  r.duration_seconds,
  r.video_url,
  r.thumbnail_url,
  r.attendee_count,
  case
    when p.completed then 1.0::numeric
    when r.duration_seconds = 0 then 0.0::numeric
    else least(1.0, round(p.position_seconds::numeric / r.duration_seconds, 4))
  end as progress,
  case
    when t.id is null then null
    else jsonb_build_object(
      'id', t.id,
      'full_name', t.full_name,
      'initials', t.initials,
      'avatar_url', t.avatar_url
    )
  end as teacher,
  t.full_name as teacher_name
from ol_recordings r
left join ol_teachers t on t.id = r.teacher_id
left join ol_recording_progress p
  on p.recording_id = r.id and p.student_id = auth.uid()
where r.published or ol_is_staff();

-- ------------------------------------------------------- dashboard stats ---

-- One round trip for the four stat cards. SECURITY DEFINER because the
-- student-facing counts ("faol talabalar", "o'rtacha davomat") are aggregates
-- over rows a student may not read individually.
create or replace function ol_dashboard_stats()
returns table (
  lessons_today       integer,
  active_students     integer,
  average_attendance  numeric,
  recording_count     integer
)
language sql
stable
security definer
set search_path = public
as $$
  select
    (select count(*)::int from ol_lessons
      where starts_at >= date_trunc('day', now())
        and starts_at <  date_trunc('day', now()) + interval '1 day'
        and status <> 'cancelled'),
    (select count(distinct student_id)::int from ol_enrollments e
      join ol_lessons l on l.id = e.lesson_id
      where l.starts_at >= now() - interval '30 days'),
    -- Attended seconds over scheduled seconds, across the last 30 days of
    -- finished lessons. Capped at 1 per row so an over-running lesson can't
    -- push the average above 100%.
    coalesce((
      select round(avg(least(1.0, a.seconds_attended::numeric
                             / nullif(l.duration_minutes * 60, 0))), 4)
      from ol_attendance a
      join ol_lessons l on l.id = a.lesson_id
      where l.status = 'ended'
        and l.starts_at >= now() - interval '30 days'
    ), 0),
    (select count(*)::int from ol_recordings where published);
$$;

-- ------------------------------------------------------------------ RLS ---

alter table ol_profiles               enable row level security;
alter table ol_teachers               enable row level security;
alter table ol_lessons                enable row level security;
alter table ol_enrollments            enable row level security;
alter table ol_attendance             enable row level security;
alter table ol_recordings             enable row level security;
alter table ol_recording_progress     enable row level security;
alter table ol_materials              enable row level security;
alter table ol_quizzes                enable row level security;
alter table ol_quiz_attempts          enable row level security;
alter table ol_assignments            enable row level security;
alter table ol_assignment_submissions enable row level security;

-- profiles: read your own, staff read all, nobody self-promotes.
create policy ol_profiles_select_own on ol_profiles
  for select to authenticated
  using (user_id = auth.uid() or ol_is_staff());

create policy ol_profiles_update_own on ol_profiles
  for update to authenticated
  using (user_id = auth.uid())
  -- `role` is intentionally not writable here: the USING clause lets a user
  -- reach their row, so without this a student could set role='admin'.
  with check (user_id = auth.uid() and role = ol_current_role());

create policy ol_profiles_admin_all on ol_profiles
  for all to authenticated
  using (ol_current_role() = 'admin')
  with check (ol_current_role() = 'admin');

-- teachers: readable by everyone signed in; staff maintain the roster.
create policy ol_teachers_select on ol_teachers
  for select to authenticated using (true);

create policy ol_teachers_write on ol_teachers
  for all to authenticated
  using (ol_is_staff()) with check (ol_is_staff());

-- lessons: every signed-in student sees the catalogue (they need to browse
-- the schedule to enrol); staff write.
create policy ol_lessons_select on ol_lessons
  for select to authenticated using (true);

create policy ol_lessons_write on ol_lessons
  for all to authenticated
  using (ol_is_staff()) with check (ol_is_staff());

-- enrolments: students manage their own; staff see and manage all.
create policy ol_enrollments_select on ol_enrollments
  for select to authenticated
  using (student_id = auth.uid() or ol_is_staff());

create policy ol_enrollments_insert_self on ol_enrollments
  for insert to authenticated
  with check (student_id = auth.uid() or ol_is_staff());

create policy ol_enrollments_delete_self on ol_enrollments
  for delete to authenticated
  using (student_id = auth.uid() or ol_is_staff());

-- attendance: a student writes only their own row.
create policy ol_attendance_select on ol_attendance
  for select to authenticated
  using (student_id = auth.uid() or ol_is_staff());

create policy ol_attendance_upsert on ol_attendance
  for all to authenticated
  using (student_id = auth.uid() or ol_is_staff())
  with check (student_id = auth.uid() or ol_is_staff());

-- recordings: published ones are readable by all; staff manage.
create policy ol_recordings_select on ol_recordings
  for select to authenticated
  using (published or ol_is_staff());

create policy ol_recordings_write on ol_recordings
  for all to authenticated
  using (ol_is_staff()) with check (ol_is_staff());

create policy ol_recording_progress_own on ol_recording_progress
  for all to authenticated
  using (student_id = auth.uid() or ol_is_staff())
  with check (student_id = auth.uid());

-- materials / quizzes / assignments follow their lesson: readable to all
-- signed-in users, writable by staff.
create policy ol_materials_select on ol_materials
  for select to authenticated using (true);
create policy ol_materials_write on ol_materials
  for all to authenticated
  using (ol_is_staff()) with check (ol_is_staff());

create policy ol_quizzes_select on ol_quizzes
  for select to authenticated using (true);
create policy ol_quizzes_write on ol_quizzes
  for all to authenticated
  using (ol_is_staff()) with check (ol_is_staff());

create policy ol_quiz_attempts_own on ol_quiz_attempts
  for all to authenticated
  using (student_id = auth.uid() or ol_is_staff())
  with check (student_id = auth.uid());

create policy ol_assignments_select on ol_assignments
  for select to authenticated using (true);
create policy ol_assignments_write on ol_assignments
  for all to authenticated
  using (ol_is_staff()) with check (ol_is_staff());

create policy ol_assignment_submissions_own on ol_assignment_submissions
  for all to authenticated
  using (student_id = auth.uid() or ol_is_staff())
  with check (student_id = auth.uid());


-- ------------------------------------------------------ notifications ---

create table ol_notifications (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  title         text not null,
  body          text,
  -- 'lesson_starting' | 'new_recording' | 'homework' | 'info'. Free text
  -- rather than an enum so a new notification type does not need a migration
  -- and an app deploy in lockstep.
  kind          text not null default 'info',
  -- Optional deep link targets. Both nullable: an 'info' notice points at
  -- nothing.
  lesson_id     uuid references ol_lessons (id) on delete cascade,
  recording_id  uuid references ol_recordings (id) on delete cascade,
  read_at       timestamptz,
  created_at    timestamptz not null default now()
);

create index ol_notifications_user_idx
  on ol_notifications (user_id, created_at desc);

-- The bell's unread dot is read on every screen; this keeps that a count over
-- a handful of rows rather than a scan of the user's whole history.
create index ol_notifications_unread_idx
  on ol_notifications (user_id) where read_at is null;

alter table ol_notifications enable row level security;

-- A user reads and dismisses only their own. Staff may create notifications
-- for anyone (that is how "dars boshlanmoqda" gets delivered) but cannot read
-- another person's inbox back.
create policy ol_notifications_select_own on ol_notifications
  for select to authenticated
  using (user_id = auth.uid());

create policy ol_notifications_update_own on ol_notifications
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy ol_notifications_insert on ol_notifications
  for insert to authenticated
  with check (user_id = auth.uid() or ol_is_staff());

create policy ol_notifications_delete_own on ol_notifications
  for delete to authenticated
  using (user_id = auth.uid() or ol_is_staff());

-- Marking the panel read is one statement rather than one update per row.
create or replace function ol_mark_notifications_read()
returns void
language sql
volatile
security definer
set search_path = public
as $$
  update ol_notifications
     set read_at = now()
   where user_id = auth.uid()
     and read_at is null;
$$;

-- ---------------------------------------------------------- auto-profile ---

-- Everyone who signs up gets a student profile; without this the app's first
-- query returns nothing and the user sees an empty shell.
create or replace function ol_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into ol_profiles (user_id, full_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1))
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create trigger ol_on_auth_user_created
  after insert on auth.users
  for each row execute function ol_handle_new_user();

grant execute on function ol_dashboard_stats() to authenticated;
grant execute on function ol_current_role() to authenticated;
grant execute on function ol_is_staff() to authenticated;
grant execute on function ol_mark_notifications_read() to authenticated;
