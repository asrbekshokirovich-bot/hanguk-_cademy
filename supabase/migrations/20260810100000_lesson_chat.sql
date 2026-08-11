-- The in-lesson chat, kept.
--
-- It first shipped as LiveKit data-channel messages and nothing else, on the
-- reasoning that a lesson's chat is disposable. That was wrong twice over: a
-- student who joins ten minutes late arrives to an empty panel with no way to
-- catch up, and a teacher who wants to know what was asked has nothing to
-- look at afterwards.
--
-- Delivery still goes over the data channel — it is instant and costs no
-- round trip — and every line is also written here, so the panel can be
-- filled on join and read again later.

create table if not exists ol_lesson_messages (
  id          uuid primary key default gen_random_uuid(),
  lesson_id   uuid not null references ol_lessons (id) on delete cascade,
  author_id   uuid not null references auth.users (id) on delete cascade,
  -- Denormalised on purpose: a message should still read correctly after the
  -- author's account is renamed, and after it is deleted the row survives
  -- with the name that was on screen at the time.
  author_name text not null,
  body        text not null check (char_length(btrim(body)) between 1 and 2000),
  sent_at     timestamptz not null default now()
);

-- The only query there is: one lesson's messages, oldest first.
create index if not exists ol_lesson_messages_lesson_idx
  on ol_lesson_messages (lesson_id, sent_at);

alter table ol_lesson_messages enable row level security;

-- Readable by anyone signed in, which matches ol_lessons itself: the
-- timetable is open to every student so they can browse it, and a lesson's
-- chat is no more sensitive than the lesson.
drop policy if exists ol_lesson_messages_select on ol_lesson_messages;
create policy ol_lesson_messages_select on ol_lesson_messages
  for select to authenticated using (true);

-- You may only speak as yourself. Without the author_id check a student
-- could post a line under the teacher's name.
drop policy if exists ol_lesson_messages_insert on ol_lesson_messages;
create policy ol_lesson_messages_insert on ol_lesson_messages
  for insert to authenticated with check (author_id = auth.uid());

-- Nobody edits a message. Staff may remove one — that is moderation, and it
-- is the only reason to touch a row after it is written.
drop policy if exists ol_lesson_messages_delete on ol_lesson_messages;
create policy ol_lesson_messages_delete on ol_lesson_messages
  for delete to authenticated using (ol_is_staff());
