-- Removes the demonstration content added by 001_starter_data.sql.
--
-- Run once, from the SQL Editor, when the academy is ready to enter its own
-- lessons and teachers.
--
-- Every delete is keyed on the fixed uuid prefixes 001 used. Nothing here
-- touches real rows: accounts created through the admin panel get random
-- uuids, and lessons entered by hand do too. There is deliberately no
-- `delete from ol_lessons` without a where clause anywhere in this file —
-- one careless run of that would take the academy's real schedule with it.
--
-- Safe to run twice; the second run deletes nothing.

begin;

-- Children first where the foreign key does not cascade. ol_materials,
-- ol_quizzes and ol_assignments cascade from ol_lessons, but ol_recordings
-- only nulls its lesson_id, so it has to go explicitly.
delete from ol_recordings
 where id::text like 'b0000000-0000-4000-8000-%';

delete from ol_materials
 where id::text like 'c0000000-0000-4000-8000-%';

delete from ol_quizzes
 where id::text like 'd0000000-0000-4000-8000-%';

delete from ol_assignments
 where id::text like 'e0000000-0000-4000-8000-%';

delete from ol_lessons
 where id::text like 'a0000000-0000-4000-8000-%';

delete from ol_teachers
 where id::text like '10000000-0000-4000-8000-%';

commit;

-- What is left. Expect zeros on the first four; ol_profiles keeps whatever
-- real accounts exist.
select
  (select count(*) from ol_teachers)   as teachers,
  (select count(*) from ol_lessons)    as lessons,
  (select count(*) from ol_recordings) as recordings,
  (select count(*) from ol_materials)  as materials,
  (select count(*) from ol_profiles)   as profiles;
