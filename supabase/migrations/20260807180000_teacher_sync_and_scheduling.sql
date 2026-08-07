-- Keeps ol_teachers in step with ol_profiles, and lets an admin schedule.
--
-- Two things were missing once accounts started being created through the app.
--
-- 1. A teacher account produced an ol_profiles row and nothing else. The
--    teacher roster, group assignment and lesson scheduling all read
--    ol_teachers, so a newly created teacher was invisible to every one of
--    them. The account existed and could sign in; it just could not be given
--    anything to teach.
--
-- 2. Nothing could create a lesson or a group except SQL.

-- ------------------------------------------------- teacher row, in step ---

-- Maintains the ol_teachers row whenever a profile becomes, or stops being, a
-- teacher. A trigger rather than a step inside ol_admin_create_user, because
-- role also changes through the roster's "O'qituvchi qilish" action, which
-- updates ol_profiles directly.
create or replace function ol_sync_teacher_row()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role in ('teacher', 'admin') then
    insert into ol_teachers (user_id, full_name, initials)
    values (new.user_id, new.full_name, new.initials)
    on conflict (user_id) do update
      set full_name = excluded.full_name,
          initials  = coalesce(excluded.initials, ol_teachers.initials);
  else
    -- Demoted. The row is kept when it still has lessons or groups attached:
    -- deleting it would null the teacher off historical lessons and lose who
    -- actually taught them. Marked instead.
    if exists (select 1 from ol_lessons l
                join ol_teachers t on t.id = l.teacher_id
               where t.user_id = new.user_id)
       or exists (select 1 from ol_groups g
                   join ol_teachers t on t.id = g.teacher_id
                  where t.user_id = new.user_id) then
      update ol_teachers set status = 'left' where user_id = new.user_id;
    else
      delete from ol_teachers where user_id = new.user_id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists ol_profiles_teacher_sync on ol_profiles;
create trigger ol_profiles_teacher_sync
  after insert or update of role, full_name on ol_profiles
  for each row execute function ol_sync_teacher_row();

-- Backfill anyone who already has the role but no roster row.
insert into ol_teachers (user_id, full_name, initials)
select p.user_id, p.full_name, p.initials
  from ol_profiles p
 where p.role in ('teacher', 'admin')
   and not exists (select 1 from ol_teachers t where t.user_id = p.user_id)
on conflict (user_id) do nothing;

-- --------------------------------------------------------- group roster ---

-- Groups with their teacher and a head count, for the assignment picker.
create or replace view ol_v_groups
with (security_invoker = false)
as
select
  g.id,
  g.name,
  g.level,
  g.is_active,
  g.teacher_id,
  t.full_name as teacher_name,
  coalesce(m.member_count, 0) as member_count
from ol_groups g
left join ol_teachers t on t.id = g.teacher_id
left join (
  select group_id, count(*)::int as member_count
    from ol_group_members
   group by group_id
) m on m.group_id = g.id
where ol_is_staff();

grant select on ol_v_groups to authenticated;

-- --------------------------------------------------- assign to a group ---

-- Moves a student into a group, or out of every group when p_group_id is
-- null.
--
-- A student belongs to one group at a time here. The table allows several —
-- and might one day need to — but "which teacher is this student's" has to
-- have a single answer for the roster and the attendance figures to mean
-- anything, so the current rule is enforced in one place rather than assumed
-- in five.
create or replace function ol_assign_student_group(
  p_student_id uuid,
  p_group_id   uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if not ol_is_staff() then
    raise exception 'Bu amal uchun o''qituvchi yoki administrator huquqi kerak'
      using errcode = '42501';
  end if;

  if not exists (
    select 1 from ol_profiles where user_id = p_student_id and role = 'student'
  ) then
    raise exception 'Talaba topilmadi';
  end if;

  delete from ol_group_members where student_id = p_student_id;

  if p_group_id is not null then
    if not exists (select 1 from ol_groups where id = p_group_id) then
      raise exception 'Guruh topilmadi';
    end if;
    insert into ol_group_members (group_id, student_id)
    values (p_group_id, p_student_id);
  end if;
end;
$$;

grant execute on function ol_assign_student_group(uuid, uuid) to authenticated;

-- ------------------------------------------------------------ enrolment ---

-- When a lesson is attached to a group, everyone in that group is enrolled.
-- Without this the roster shows students under a teacher while the lesson's
-- "18 ta talaba" stays at zero, because enrolment lived only in
-- ol_enrollments and nothing wrote it.
create or replace function ol_sync_lesson_enrolments()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.group_id is null then
    return new;
  end if;

  insert into ol_enrollments (lesson_id, student_id)
  select new.id, m.student_id
    from ol_group_members m
   where m.group_id = new.group_id
  on conflict do nothing;

  -- Moved to a different group: drop anyone who is no longer in it. Only on
  -- update, and only for students whose enrolment came from the old group.
  if tg_op = 'UPDATE'
     and old.group_id is not null
     and old.group_id <> new.group_id then
    delete from ol_enrollments e
     where e.lesson_id = new.id
       and e.student_id in (
         select m.student_id from ol_group_members m
          where m.group_id = old.group_id
       )
       and e.student_id not in (
         select m.student_id from ol_group_members m
          where m.group_id = new.group_id
       );
  end if;

  return new;
end;
$$;

drop trigger if exists ol_lessons_enrolment_sync on ol_lessons;
create trigger ol_lessons_enrolment_sync
  after insert or update of group_id on ol_lessons
  for each row execute function ol_sync_lesson_enrolments();

-- A student joining a group is enrolled in that group's future lessons.
-- Past lessons are left alone: they did not attend them.
create or replace function ol_sync_member_enrolments()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into ol_enrollments (lesson_id, student_id)
  select l.id, new.student_id
    from ol_lessons l
   where l.group_id = new.group_id
     and l.starts_at >= now()
  on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists ol_group_members_enrolment_sync on ol_group_members;
create trigger ol_group_members_enrolment_sync
  after insert on ol_group_members
  for each row execute function ol_sync_member_enrolments();

-- ------------------------------------------------------- lesson's group ---

-- The schedule's edit dialog needs to know which group a lesson belongs to,
-- otherwise saving any other field would write group_id back as null and
-- quietly detach the class. Appended to the end of the select list so
-- `create or replace view` accepts it.
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
  t.full_name as teacher_name,
  l.group_id
from ol_lessons l
left join ol_teachers t on t.id = l.teacher_id
left join (
  select lesson_id, count(*)::int as enrolled_count
  from ol_enrollments
  group by lesson_id
) e on e.lesson_id = l.id;

-- ------------------------------------------------------ student's group ---

-- The roster shows the group's *name*; the assignment dialog needs its id to
-- preselect the current one. Appended at the end of the select list.
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
  pay.period as payment_period,
  m.group_id
from ol_profiles p
left join ol_group_members m on m.student_id = p.user_id
left join ol_groups g on g.id = m.group_id
left join ol_teachers t on t.id = g.teacher_id
left join ol_v_student_stats s on s.student_id = p.user_id
left join lateral (
  select pm.status, pm.due_date, pm.period
    from ol_payments pm
   where pm.student_id = p.user_id
   order by pm.period desc
   limit 1
) pay on true
where p.role = 'student'
  and ol_is_staff();
