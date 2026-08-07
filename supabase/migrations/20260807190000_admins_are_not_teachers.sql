-- An admin is not a teacher.
--
-- The previous migration's sync trigger treated 'admin' as a teaching role, so
-- creating the admin account put it on the teaching roster: Asrbek showed up
-- under "O'qituvchilar" with 0 lessons and 0 students, and could be picked as
-- a group's teacher.
--
-- The reasoning was that an admin might also teach. That is a real case, but
-- it is a second role someone is given, not something to assume — and
-- assuming it puts every office administrator in front of a class on the
-- roster. An admin who does teach gets an ol_teachers row added deliberately;
-- the roster is the list of people who teach, not the list of people with a
-- login.

create or replace function ol_sync_teacher_row()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role = 'teacher' then
    insert into ol_teachers (user_id, full_name, initials)
    values (new.user_id, new.full_name, new.initials)
    on conflict (user_id) do update
      set full_name = excluded.full_name,
          initials  = coalesce(excluded.initials, ol_teachers.initials);
  else
    -- No longer teaching. The row is kept when it still has lessons or groups
    -- attached: deleting it would null the teacher off historical lessons and
    -- lose who actually taught them. Marked instead.
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

-- Undo the rows the earlier version added. Same rule as above: only the ones
-- that never taught anything are removed, so nothing loses its history.
delete from ol_teachers t
 using ol_profiles p
 where p.user_id = t.user_id
   and p.role <> 'teacher'
   and not exists (select 1 from ol_lessons l where l.teacher_id = t.id)
   and not exists (select 1 from ol_groups  g where g.teacher_id = t.id);

-- Anyone left over taught something, so they stay on the roster — marked as
-- no longer teaching rather than pretending they are available.
update ol_teachers t
   set status = 'left'
  from ol_profiles p
 where p.user_id = t.user_id
   and p.role <> 'teacher'
   and t.status <> 'left';

-- Should list teachers only.
select p.full_name, p.role, t.status
  from ol_teachers t
  join ol_profiles p on p.user_id = t.user_id
 order by p.full_name;
