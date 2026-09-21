-- Recording the room, part two: start it, stop it, and file what came back.
--
-- Part one proved the pipe: `select ol_livekit_egress('ListEgress','{}')`
-- answered 200 from this database. This is the part that records.
--
-- Nothing here is driven by a person pressing anything. A minute-by-minute
-- job starts a recording once a live lesson actually has somebody in the
-- room, stops it when the lesson ends, and writes the `ol_recordings` row
-- when LiveKit says the file is finished. Three separate steps on purpose:
-- each one can fail on its own and be retried on the next minute without
-- the other two noticing.
--
-- Why a job rather than a trigger on `ol_lessons.status`: a room-composite
-- egress needs a room that exists, and a room exists when somebody has
-- joined it — which is strictly after the lesson was marked live. A trigger
-- would fire into an empty room and get "room not found", every time. It
-- would also hold the teacher's "start lesson" open for the length of an
-- HTTP call to another continent.

-- --------------------------------------------------------- the bookkeeping ---

create table if not exists ol_lesson_egress (
  lesson_id   uuid primary key references ol_lessons (id) on delete cascade,
  egress_id   text,
  filepath    text,
  -- starting | active | stopping | complete | failed
  status      text not null default 'starting',
  error       text,
  started_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table ol_lesson_egress enable row level security;

-- Staff may look; nobody may write by hand. The job owns this table.
drop policy if exists ol_lesson_egress_select on ol_lesson_egress;
create policy ol_lesson_egress_select on ol_lesson_egress
  for select to authenticated using (ol_is_staff());

-- ------------------------------------------------------------------ start ---

-- Asks LiveKit to record one lesson's room into the configured bucket.
--
-- Idempotent through `ol_lesson_egress`: the row is claimed first, and a
-- lesson that already has one is left alone. Called only by the job below.
create or replace function ol_egress_start(p_lesson_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_s3    ol_egress_config%rowtype;
  v_path  text;
  v_res   jsonb;
  v_id    text;
begin
  select * into v_s3 from ol_egress_config where id;
  if not found then
    raise exception 'ol_egress_config bo''sh — R2 kalitlari kiritilmagan'
      using errcode = '42704';
  end if;

  -- Claim it. A unique violation means another tick got there first, which
  -- is a success from this one's point of view.
  begin
    insert into ol_lesson_egress (lesson_id, status)
    values (p_lesson_id, 'starting');
  exception when unique_violation then
    return jsonb_build_object('skipped', 'already claimed');
  end;

  -- Date first so a term of recordings is browsable in the bucket, and the
  -- lesson id so two lessons in the same minute cannot collide.
  v_path := 'lessons/' || to_char(now(), 'YYYY/MM/DD') || '/'
            || p_lesson_id::text || '.mp4';

  v_res := ol_livekit_egress(
    'StartRoomCompositeEgress',
    jsonb_build_object(
      'room_name', 'lesson_' || p_lesson_id::text,
      -- The speaker-focused layout, which is what a lesson is: one person
      -- talking with the class around them.
      'layout', 'speaker',
      'audio_only', false,
      'file_outputs', jsonb_build_array(
        jsonb_build_object(
          'file_type', 'MP4',
          'filepath', v_path,
          's3', jsonb_build_object(
            'access_key', v_s3.s3_access_key,
            'secret', v_s3.s3_secret,
            'region', v_s3.s3_region,
            'bucket', v_s3.s3_bucket,
            'endpoint', v_s3.s3_endpoint,
            -- R2, B2 and Supabase all address buckets by path rather than
            -- by subdomain. Virtual-host style is an AWS-only assumption.
            'force_path_style', true
          )
        )
      )
    )
  );

  v_id := v_res #>> '{body,egress_id}';

  update ol_lesson_egress
     set egress_id  = v_id,
         filepath   = v_path,
         status     = case when v_id is null then 'failed' else 'active' end,
         error      = case when v_id is null then v_res::text end,
         updated_at = now()
   where lesson_id = p_lesson_id;

  return v_res;
end;
$$;

-- ------------------------------------------------------------------- stop ---

create or replace function ol_egress_stop(p_lesson_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_row ol_lesson_egress%rowtype;
  v_res jsonb;
begin
  select * into v_row from ol_lesson_egress where lesson_id = p_lesson_id;
  if not found or v_row.egress_id is null then
    return jsonb_build_object('skipped', 'no egress');
  end if;

  v_res := ol_livekit_egress(
    'StopEgress',
    jsonb_build_object('egress_id', v_row.egress_id)
  );

  -- Not 'complete': stopping is a request, and the file is written after it
  -- is granted. The harvest below decides when it is really finished.
  update ol_lesson_egress
     set status = 'stopping', updated_at = now()
   where lesson_id = p_lesson_id;

  return v_res;
end;
$$;

-- ---------------------------------------------------------------- harvest ---

-- Turns a finished egress into a row in the library.
--
-- LiveKit reports `EGRESS_COMPLETE` and hands back the file's real size and
-- duration, which is why this waits for it rather than writing the row when
-- the recording was asked for: a row that claims a video before the video
-- exists is the same defect as every other thing in this app that claimed
-- something it did not have.
create or replace function ol_egress_harvest(p_lesson_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_row    ol_lesson_egress%rowtype;
  v_res    jsonb;
  v_info   jsonb;
  v_status text;
  v_file   jsonb;
  v_lesson ol_lessons%rowtype;
  v_secs   integer;
begin
  select * into v_row from ol_lesson_egress where lesson_id = p_lesson_id;
  if not found or v_row.egress_id is null then
    return jsonb_build_object('skipped', 'no egress');
  end if;

  v_res := ol_livekit_egress(
    'ListEgress',
    jsonb_build_object('egress_id', v_row.egress_id)
  );
  v_info := v_res #> '{body,items,0}';
  if v_info is null then
    return jsonb_build_object('skipped', 'not listed', 'call', v_res);
  end if;

  v_status := v_info ->> 'status';
  if v_status in ('EGRESS_STARTING', 'EGRESS_ACTIVE', 'EGRESS_ENDING') then
    return jsonb_build_object('waiting', v_status);
  end if;

  if v_status <> 'EGRESS_COMPLETE' then
    update ol_lesson_egress
       set status = 'failed', error = v_info::text, updated_at = now()
     where lesson_id = p_lesson_id;
    return jsonb_build_object('failed', v_status, 'info', v_info);
  end if;

  v_file := v_info #> '{file_results,0}';
  select * into v_lesson from ol_lessons where id = p_lesson_id;

  -- Nanoseconds, because that is what LiveKit reports.
  v_secs := coalesce(
    ((v_file ->> 'duration')::bigint / 1000000000)::integer,
    coalesce(v_lesson.duration_minutes, 0) * 60
  );

  insert into ol_recordings (
    lesson_id, title, category, teacher_id, recorded_at,
    duration_seconds, video_url, attendee_count, published
  )
  values (
    p_lesson_id,
    coalesce(v_lesson.title, 'Dars yozuvi'),
    coalesce(v_lesson.category, 'Koreys tili'),
    v_lesson.teacher_id,
    coalesce(v_lesson.starts_at, now()),
    v_secs,
    -- Marked as living in the bucket rather than in Supabase Storage, so the
    -- app knows to ask for a signed link instead of treating it as a path.
    'r2://' || coalesce(v_file ->> 'filename', v_row.filepath),
    (select count(*)::int from ol_enrollments e where e.lesson_id = p_lesson_id),
    true
  );

  update ol_lesson_egress
     set status = 'complete',
         filepath = coalesce(v_file ->> 'filename', v_row.filepath),
         updated_at = now()
   where lesson_id = p_lesson_id;

  return jsonb_build_object('complete', true, 'file', v_file);
end;
$$;

-- ------------------------------------------------------------- the minute ---

-- One job, three jobs' worth of work, deliberately: start, stop, harvest.
--
-- Each lesson is wrapped in its own exception block. One room LiveKit cannot
-- reach must not stop the other two from being recorded, and a failure that
-- kills the whole tick is a failure that repeats for ever.
create or replace function ol_egress_tick()
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  r record;
begin
  -- Start: live, wants recording, somebody is actually in the room, and
  -- nothing has been claimed for it yet.
  for r in
    select l.id
      from ol_lessons l
     where l.status = 'live'
       and l.auto_record
       and not exists (select 1 from ol_lesson_egress e where e.lesson_id = l.id)
       and exists (
         select 1 from ol_room_presence p
          where p.lesson_id = l.id
            and p.last_seen_at > now() - interval '2 minutes'
       )
  loop
    begin
      perform ol_egress_start(r.id);
    exception when others then
      insert into ol_lesson_egress (lesson_id, status, error)
      values (r.id, 'failed', sqlerrm)
      on conflict (lesson_id) do update
        set status = 'failed', error = sqlerrm, updated_at = now();
    end;
  end loop;

  -- Stop: the lesson is over and the recorder has not been told.
  for r in
    select e.lesson_id
      from ol_lesson_egress e
      join ol_lessons l on l.id = e.lesson_id
     where e.status = 'active'
       and l.status <> 'live'
  loop
    begin
      perform ol_egress_stop(r.lesson_id);
    exception when others then
      update ol_lesson_egress
         set error = sqlerrm, updated_at = now()
       where lesson_id = r.lesson_id;
    end;
  end loop;

  -- Harvest: anything asked to stop, and anything still running that may
  -- have ended on its own when the room emptied.
  for r in
    select e.lesson_id
      from ol_lesson_egress e
     where e.status in ('stopping', 'active')
       and e.egress_id is not null
       and not exists (
         select 1 from ol_recordings rec where rec.lesson_id = e.lesson_id
       )
  loop
    begin
      perform ol_egress_harvest(r.lesson_id);
    exception when others then
      update ol_lesson_egress
         set error = sqlerrm, updated_at = now()
       where lesson_id = r.lesson_id;
    end;
  end loop;
end;
$$;

do $$
begin
  create extension if not exists pg_cron;
  perform cron.unschedule('ol-egress-tick')
    where exists (select 1 from cron.job where jobname = 'ol-egress-tick');
  perform cron.schedule(
    'ol-egress-tick',
    '* * * * *',
    $cron$select ol_egress_tick();$cron$
  );
exception when others then
  raise notice
    'pg_cron unavailable (%). Recording will not start by itself; '
    'call ol_egress_tick() by hand to test.', sqlerrm;
end;
$$;

-- ----------------------------------------------------------- watching it ---

-- A link to a recorded file, good for an hour.
--
-- The bucket is private and stays private: R2 can be made world-readable
-- with one toggle, and a lesson full of named children is not a thing to
-- leave on an unlisted URL. So the link is signed here, with the same AWS
-- SigV4 every S3 client uses — the algorithm is public, the secret never
-- leaves this database, and the link expires.
create or replace function ol_s3_presign(
  p_key     text,
  p_seconds integer default 3600
)
returns text
language plpgsql
volatile
security definer
set search_path = public, extensions
as $$
declare
  v_s3     ol_egress_config%rowtype;
  v_host   text;
  v_date   text := to_char(now() at time zone 'utc', 'YYYYMMDD');
  v_stamp  text := to_char(now() at time zone 'utc', 'YYYYMMDD"T"HH24MISS"Z"');
  v_scope  text;
  v_query  text;
  v_canon  text;
  v_sts    text;
  v_key    bytea;
  v_sig    text;
  v_path   text;
begin
  select * into v_s3 from ol_egress_config where id;
  if not found then
    raise exception 'ol_egress_config bo''sh' using errcode = '42704';
  end if;

  v_host  := regexp_replace(v_s3.s3_endpoint, '^https?://', '');
  v_scope := v_date || '/' || v_s3.s3_region || '/s3/aws4_request';
  -- Path style: the bucket is part of the path, not of the hostname.
  v_path  := '/' || v_s3.s3_bucket || '/' || p_key;

  -- Already in alphabetical order, which the signature requires.
  v_query :=
    'X-Amz-Algorithm=AWS4-HMAC-SHA256'
    || '&X-Amz-Credential='
    || replace(v_s3.s3_access_key || '/' || v_scope, '/', '%2F')
    || '&X-Amz-Date=' || v_stamp
    || '&X-Amz-Expires=' || p_seconds::text
    || '&X-Amz-SignedHeaders=host';

  v_canon := 'GET' || E'\n'
          || v_path || E'\n'
          || v_query || E'\n'
          || 'host:' || v_host || E'\n'
          || E'\n'
          || 'host' || E'\n'
          || 'UNSIGNED-PAYLOAD';

  v_sts := 'AWS4-HMAC-SHA256' || E'\n'
        || v_stamp || E'\n'
        || v_scope || E'\n'
        || encode(extensions.digest(v_canon, 'sha256'), 'hex');

  v_key := extensions.hmac(v_date, ('AWS4' || v_s3.s3_secret)::bytea, 'sha256');
  v_key := extensions.hmac(v_s3.s3_region, v_key, 'sha256');
  v_key := extensions.hmac('s3', v_key, 'sha256');
  v_key := extensions.hmac('aws4_request', v_key, 'sha256');
  v_sig := encode(extensions.hmac(v_sts, v_key, 'sha256'), 'hex');

  return 'https://' || v_host || v_path || '?' || v_query
         || '&X-Amz-Signature=' || v_sig;
end;
$$;

-- What the app calls. Takes a recording, checks the caller may watch it,
-- and hands back a link that works for an hour.
create or replace function ol_recording_url(p_recording_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_url text;
begin
  if auth.uid() is null then
    raise exception 'Tizimga kirilmagan' using errcode = '42501';
  end if;

  select video_url into v_url
    from ol_recordings
   where id = p_recording_id
     and (published or ol_is_staff());
  if v_url is null then
    raise exception 'Yozuv topilmadi' using errcode = '42704';
  end if;

  -- Only the bucket's own rows are signed here. A row whose video_url is an
  -- ordinary link, or a path in Supabase Storage, is handled by the app.
  if v_url like 'r2://%' then
    return ol_s3_presign(substring(v_url from 6));
  end if;
  return v_url;
end;
$$;

revoke execute on function ol_egress_start(uuid) from public, anon, authenticated;
revoke execute on function ol_egress_stop(uuid) from public, anon, authenticated;
revoke execute on function ol_egress_harvest(uuid) from public, anon, authenticated;
revoke execute on function ol_egress_tick() from public, anon, authenticated;
revoke execute on function ol_s3_presign(text, integer) from public, anon, authenticated;
grant execute on function ol_recording_url(uuid) to authenticated;
