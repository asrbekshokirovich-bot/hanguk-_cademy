-- A lesson may not be put on air hours before its hour.
--
-- "Bugungi darslarim" lists the whole day and every scheduled row in it
-- carried a live "Darsni boshlash", so the evening class was one tap away all
-- morning — directly under the one that was actually next. Starting it is not
-- a harmless mistake: the room goes on air, the recorder starts against the
-- wrong lesson, and the students who do turn up at half past six find a class
-- the system already believes has been taught.
--
-- The app now hides the button until fifteen minutes before, and hiding is
-- not the check: this is.
--
-- Fifteen minutes is the whole rule. To widen or narrow it, change the one
-- interval below and the matching `_opensBefore` in
-- lib/features/staff/presentation/teacher_dashboard_screen.dart — they are
-- deliberately the same number in two places rather than a setting, because a
-- setting nobody can find is worse than a number in two files.

create or replace function ol_lesson_start_window()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- Only the transition into 'live'. Editing a lesson that is already on air,
  -- ending one, or cancelling one is none of this trigger's business.
  if new.status <> 'live' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status = 'live' then
    return new;
  end if;

  if now() < new.starts_at - interval '15 minutes' then
    raise exception
      'Dars % da boshlanadi — 15 daqiqadan erta boshlab bo''lmaydi',
      to_char(new.starts_at at time zone 'Asia/Tashkent', 'HH24:MI')
      using errcode = '22023';
  end if;

  return new;
end;
$$;

drop trigger if exists ol_lesson_start_window on ol_lessons;
create trigger ol_lesson_start_window
  before insert or update on ol_lessons
  for each row
  execute function ol_lesson_start_window();
