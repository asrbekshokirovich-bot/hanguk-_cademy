-- The lesson's whiteboard.
--
-- A Korean teacher writes. Hangul is drawn stroke by stroke and a lesson
-- without something to write on is a lesson spent describing shapes out loud.
--
-- Strokes travel as rows on Supabase's realtime stream rather than as a video
-- track, for three reasons: a line stays sharp on a 1440pt desktop and on a
-- 390pt phone because each side draws it at its own resolution; a lesson's
-- worth of handwriting is a few hundred small rows rather than an hour of
-- video; and because the rows persist, a student who joins twenty minutes
-- late sees the whole board, and can open it again after the lesson.
--
-- Points are stored in 0..1 of the board's own square-ish space, not in
-- pixels: the teacher's window and the student's are never the same size, and
-- pixels would put the writing somewhere else on every screen.

create table if not exists ol_board_strokes (
  id         uuid primary key default gen_random_uuid(),
  lesson_id  uuid not null references ol_lessons(id) on delete cascade,
  author_id  uuid not null references auth.users(id) on delete cascade,

  -- Insertion order, and the only order the board may be replayed in. Two
  -- strokes can share a millisecond; a timestamp is not an ordering.
  seq        bigint generated always as identity,

  -- 'stroke' is ink. The other three are markers, so that the board's whole
  -- state is one table and one stream:
  --   'clear' — everything before it is not drawn
  --   'open'  — the board is on screen for everybody in the room
  --   'close' — it is not
  -- Visibility lives here rather than on `ol_lessons` because the lesson row
  -- is polled every twenty seconds and a board that appears twenty seconds
  -- after the teacher opens it is a board nobody uses.
  kind       text not null default 'stroke'
             check (kind in ('stroke', 'clear', 'open', 'close')),

  -- ARGB, as Flutter's Color carries it. Null for the markers.
  color      integer,
  width      real,

  -- [[x, y], [x, y], …] with x and y in 0..1.
  points     jsonb,

  created_at timestamptz not null default now(),

  -- `points is not null` is doing real work here, not decoration. Without it
  -- a stroke sent with no points at all passed: `jsonb_typeof(null)` is null,
  -- `null and …` is null, and a CHECK constraint *accepts* null — so the one
  -- row the constraint exists to refuse was the one row it let through. Found
  -- by testing it rather than by reading it.
  constraint ol_board_stroke_shape check (
    kind <> 'stroke' or (
      color is not null
      and width is not null
      and points is not null
      and jsonb_typeof(points) = 'array'
      -- One point is a dot, which is a legitimate mark. The ceiling is there
      -- so a stuck pointer cannot post a megabyte of coordinates.
      and jsonb_array_length(points) between 1 and 4000
    )
  )
);

create index if not exists ol_board_strokes_lesson_idx
  on ol_board_strokes (lesson_id, seq);

-- Deletes have to carry the row, not just its id: the client's subscription
-- is filtered by lesson, and a delete that arrives as a bare primary key
-- cannot be matched against that filter — so an undone stroke would stay on
-- everybody else's board until they reloaded.
alter table ol_board_strokes replica identity full;

-- Stamped here rather than trusted from the client, like the chat's author.
create or replace function ol_board_stamp_author()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.author_id := auth.uid();
  new.created_at := now();
  return new;
end;
$$;

drop trigger if exists ol_board_stamp_author on ol_board_strokes;
create trigger ol_board_stamp_author
  before insert on ol_board_strokes
  for each row execute function ol_board_stamp_author();

-- Whose board is it to write on: the teacher taking the lesson, and the
-- administrator tier — the owner does drop into a room to end a class a
-- teacher left on air, and a board he cannot clear is a board stuck with
-- yesterday's writing.
create or replace function ol_board_may_write(p_lesson_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select ol_is_admin()
      or exists (
        select 1
          from ol_lessons l
          join ol_teachers t on t.id = l.teacher_id
         where l.id = p_lesson_id
           and t.user_id = auth.uid()
      );
$$;

-- Explicitly, rather than on Supabase's default privileges for new tables in
-- `public`. Those defaults do apply when this is pasted into the SQL editor,
-- but a policy only filters rows a role is already allowed to touch — with no
-- GRANT behind it, RLS refuses everything with "permission denied", and the
-- board would be blank for everyone with nothing in the app to explain it.
grant select, insert, delete on ol_board_strokes to authenticated;

alter table ol_board_strokes enable row level security;

-- Reading is open to any signed-in account, for the same reason the chat is:
-- a stricter rule would have to be "enrolled in this lesson", and the room is
-- reachable by staff who are enrolled in nothing.
drop policy if exists ol_board_select on ol_board_strokes;
create policy ol_board_select on ol_board_strokes
  for select to authenticated
  using (true);

-- Writing is the teacher's alone. Students watch.
drop policy if exists ol_board_insert on ol_board_strokes;
create policy ol_board_insert on ol_board_strokes
  for insert to authenticated
  with check (author_id = auth.uid() and ol_board_may_write(lesson_id));

-- Undo. No update: a stroke is either drawn or taken back.
drop policy if exists ol_board_delete on ol_board_strokes;
create policy ol_board_delete on ol_board_strokes
  for delete to authenticated
  using (author_id = auth.uid() and ol_board_may_write(lesson_id));

do $$
begin
  alter publication supabase_realtime add table ol_board_strokes;
exception when duplicate_object then null;
end;
$$;

-- And a check that it is actually published, because the do-block above
-- swallows everything: without the publication the board is a private
-- notebook that nobody else can see, and nothing would have said so.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'ol_board_strokes'
  ) then
    raise exception
      'ol_board_strokes realtime nashriga qo''shilmadi — doska boshqalarga ko''rinmaydi'
      using errcode = '0A000';
  end if;
  raise notice 'doska tayyor: ol_board_strokes realtime orqali uzatiladi';
end;
$$;
