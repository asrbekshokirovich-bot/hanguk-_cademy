-- The live room stops pretending.
--
-- Three things the room showed but did not do: the chat was `DemoData.chat()`,
-- the participant list was four fixed names, and a lesson stayed `live` until
-- somebody remembered to press "Tugatish" — which, for a school, means until
-- the next morning.
--
-- Media (camera and microphone) is deliberately NOT here. That needs an SFU;
-- no amount of SQL produces one. What is here is everything around it, which
-- is what makes a room usable even before the video lands: who is in it, what
-- they are typing, and a lesson that ends on its own.

-- ---------------------------------------------------------------- chat ---

create table if not exists ol_chat_messages (
  id          uuid primary key default gen_random_uuid(),
  lesson_id   uuid not null references ol_lessons(id) on delete cascade,
  author_id   uuid not null references auth.users(id) on delete cascade,
  -- Denormalised on purpose. Supabase's realtime stream delivers the changed
  -- ROW and cannot join, so a normalised chat would arrive as a wall of uuids
  -- and need a second query per message to become readable. The name at the
  -- time of sending is also the more honest record.
  author_name text not null default '',
  body        text not null,
  sent_at     timestamptz not null default now(),
  constraint ol_chat_body_length
    check (length(btrim(body)) between 1 and 2000)
);

create index if not exists ol_chat_messages_lesson_idx
  on ol_chat_messages (lesson_id, sent_at);

-- Fills author_name from the sender's profile. Done in a trigger rather than
-- trusted from the client: the client may send whatever it likes, and a chat
-- where the display name is client-supplied is a chat where anyone can post
-- as the teacher.
create or replace function ol_chat_stamp_author()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.author_id := auth.uid();
  select coalesce(p.full_name, 'Foydalanuvchi')
    into new.author_name
    from ol_profiles p
   where p.user_id = auth.uid();
  new.author_name := coalesce(new.author_name, 'Foydalanuvchi');
  new.sent_at := now();
  return new;
end;
$$;

drop trigger if exists ol_chat_stamp_author on ol_chat_messages;
create trigger ol_chat_stamp_author
  before insert on ol_chat_messages
  for each row execute function ol_chat_stamp_author();

alter table ol_chat_messages enable row level security;

-- Reading is open to any signed-in account. A stricter rule would have to be
-- "enrolled in this lesson", and the room is reachable by staff who are not
-- enrolled in anything — the teacher covering a colleague, the admin checking
-- a complaint. The lesson list itself is already gated.
drop policy if exists ol_chat_select on ol_chat_messages;
create policy ol_chat_select on ol_chat_messages
  for select to authenticated
  using (true);

-- Writing is yours alone, and only into a room that is actually on air.
-- Without the status check a student could keep typing into last week's
-- lesson, which nobody would ever read.
drop policy if exists ol_chat_insert on ol_chat_messages;
create policy ol_chat_insert on ol_chat_messages
  for insert to authenticated
  with check (
    author_id = auth.uid()
    and exists (
      select 1 from ol_lessons l
       where l.id = lesson_id
         and l.status = 'live'
    )
  );

-- Deleting your own slip of the keyboard. No update: an edited chat message
-- with no edit marker is worse than a wrong one.
drop policy if exists ol_chat_delete_own on ol_chat_messages;
create policy ol_chat_delete_own on ol_chat_messages
  for delete to authenticated
  using (author_id = auth.uid());

-- ------------------------------------------------------------ presence ---

-- Who is in the room right now.
--
-- Presence is a heartbeat, not a pair of join/leave events. A laptop lid
-- closed mid-lesson sends no "leave", and a room that believes it still has
-- thirty people in it is worse than one that is a minute behind.
create table if not exists ol_room_presence (
  lesson_id    uuid not null references ol_lessons(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  display_name text not null default '',
  initials     text not null default '?',
  is_host      boolean not null default false,
  mic_on       boolean not null default false,
  hand_raised  boolean not null default false,
  joined_at    timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (lesson_id, user_id)
);

create index if not exists ol_room_presence_seen_idx
  on ol_room_presence (lesson_id, last_seen_at desc);

-- Same reasoning as the chat's author trigger: name, initials and "is this
-- the teacher" are facts the server owns, not claims the client makes.
create or replace function ol_presence_stamp()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.user_id := auth.uid();
  select coalesce(p.full_name, 'Foydalanuvchi'), coalesce(p.initials, '?')
    into new.display_name, new.initials
    from ol_profiles p
   where p.user_id = auth.uid();
  new.display_name := coalesce(new.display_name, 'Foydalanuvchi');
  new.initials := coalesce(new.initials, '?');

  new.is_host := exists (
    select 1
      from ol_lessons l
      join ol_teachers t on t.id = l.teacher_id
     where l.id = new.lesson_id
       and t.user_id = auth.uid()
  );

  new.last_seen_at := now();
  return new;
end;
$$;

drop trigger if exists ol_presence_stamp on ol_room_presence;
create trigger ol_presence_stamp
  before insert or update on ol_room_presence
  for each row execute function ol_presence_stamp();

alter table ol_room_presence enable row level security;

drop policy if exists ol_presence_select on ol_room_presence;
create policy ol_presence_select on ol_room_presence
  for select to authenticated
  using (true);

drop policy if exists ol_presence_upsert on ol_room_presence;
create policy ol_presence_upsert on ol_room_presence
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists ol_presence_update_own on ol_room_presence;
create policy ol_presence_update_own on ol_room_presence
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists ol_presence_delete_own on ol_room_presence;
create policy ol_presence_delete_own on ol_room_presence
  for delete to authenticated
  using (user_id = auth.uid());

-- ------------------------------------------------- lessons that end ---

-- Ends any lesson that is still on air well past its own end time.
--
-- The grace period is deliberate: lessons run over, and yanking a class off
-- air at minute sixty-one because the timetable said sixty is a worse failure
-- than leaving it up for another quarter of an hour.
create or replace function ol_end_stale_lessons(p_grace_minutes integer default 15)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  with ended as (
    update ol_lessons l
       set status = 'ended'
     where l.status = 'live'
       and l.starts_at
           + make_interval(mins => l.duration_minutes + p_grace_minutes)
           < now()
    returning l.id
  )
  select count(*) into v_count from ended;

  -- Nobody is left in a room that is off air.
  delete from ol_room_presence pr
   using ol_lessons l
   where pr.lesson_id = l.id
     and l.status <> 'live';

  return v_count;
end;
$$;

revoke execute on function ol_end_stale_lessons(integer) from public, anon;
grant execute on function ol_end_stale_lessons(integer) to authenticated;

-- Runs it every five minutes, if pg_cron is available on this project.
-- Wrapped because pg_cron is an extension a project may not have enabled, and
-- a migration that fails on that leaves everything above unapplied — the
-- chat, which does not need cron at all, would go down with it.
do $$
begin
  create extension if not exists pg_cron;
  perform cron.unschedule('ol-end-stale-lessons')
    where exists (
      select 1 from cron.job where jobname = 'ol-end-stale-lessons'
    );
  perform cron.schedule(
    'ol-end-stale-lessons',
    '*/5 * * * *',
    $cron$select ol_end_stale_lessons();$cron$
  );
exception when others then
  raise notice
    'pg_cron unavailable (%). Lessons will still end when a client calls '
    'ol_end_stale_lessons(); the app does this on every live-room open.',
    sqlerrm;
end;
$$;

-- --------------------------------------------------------- realtime ---

-- Without this the tables exist but nothing is pushed, and the chat would
-- only update when the screen happened to re-query.
do $$
begin
  alter publication supabase_realtime add table ol_chat_messages;
exception when duplicate_object then null;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table ol_room_presence;
exception when duplicate_object then null;
end;
$$;
