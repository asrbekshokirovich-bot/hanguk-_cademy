-- Recording: what testing the first two migrations on a real Postgres found.
--
-- They were written without ever being run. Loaded into a throwaway database
-- with the LiveKit call stubbed, they turned out to have one unauthenticated
-- credential leak, one way to double a recording, and four ways to lose one
-- silently. This is the repair, and every item below was reproduced and then
-- re-tested against the same harness.

-- ------------------------------------------------ the leak, first of all ---

-- A function carries an implicit EXECUTE grant to PUBLIC, and `ol_egress_ping`
-- was the one place that never revoked it. `anon` is a real role with the key
-- compiled into the app, so the diagnostic was callable by anybody on the
-- internet — and it returned LiveKit's reply verbatim, which echoes the
-- request, which carries the bucket's access key and secret.
--
-- The guard did not help: it waved a null `auth.uid()` through on the
-- argument that `anon` has no grant. It had one.
revoke execute on function ol_egress_ping() from public, anon;

create or replace function ol_egress_ping()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_cfg  ol_egress_config%rowtype;
  v_live jsonb;
begin
  -- By role now, not by the absence of a JWT: the SQL Editor connects as the
  -- database owner, and that is what it means to be entitled here.
  if not (ol_is_admin() or session_user in ('postgres', 'supabase_admin')) then
    raise exception 'Faqat administrator' using errcode = '42501';
  end if;

  select * into v_cfg from ol_egress_config where id;
  v_live := ol_livekit_egress('ListEgress', '{}'::jsonb);

  -- A summary, never the reply. Whether it worked is the whole question; the
  -- body is where the credentials are.
  return jsonb_build_object(
    'livekit_url', ol_livekit_base(),
    'livekit_ok', (v_live ->> 'status') = '200',
    'livekit_status', v_live -> 'status',
    'livekit_msg', coalesce(v_live #>> '{body,msg}', v_live ->> 'error'),
    'recording_now', jsonb_array_length(
      coalesce(v_live #> '{body,items}', '[]'::jsonb)
    ),
    'storage_set', v_cfg.id is not null,
    'storage_bucket', v_cfg.s3_bucket
  );
end;
$$;

-- ------------------------------------------------------- start, and again ---

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
  v_msg   text;
begin
  select * into v_s3 from ol_egress_config where id;
  if not found then
    raise exception 'ol_egress_config bo''sh — R2 kalitlari kiritilmagan'
      using errcode = '42704';
  end if;

  -- Claim, or re-claim. A start that failed cleanly used to leave a row
  -- behind for ever, and the tick's "has no row yet" test then skipped that
  -- lesson forgetting the reason — one 503 from LiveKit and the class was
  -- un-recordable for the rest of the hour.
  insert into ol_lesson_egress (lesson_id, status)
  values (p_lesson_id, 'starting')
  on conflict (lesson_id) do update
     set status = 'starting', error = null, egress_id = null,
         updated_at = now()
   where ol_lesson_egress.status = 'failed'
     and ol_lesson_egress.egress_id is null;

  if not found then
    return jsonb_build_object('skipped', 'already claimed');
  end if;

  v_path := 'lessons/' || to_char(now(), 'YYYY/MM/DD') || '/'
            || p_lesson_id::text || '.mp4';

  v_res := ol_livekit_egress(
    'StartRoomCompositeEgress',
    jsonb_build_object(
      'room_name', 'lesson_' || p_lesson_id::text,
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
            'force_path_style', true
          )
        )
      )
    )
  );

  v_id := v_res #>> '{body,egress_id}';
  -- A transport failure has no body at all, and `status 0` told nobody
  -- whether it was DNS, TLS or a ten-second timeout.
  v_msg := left(coalesce(v_res #>> '{body,msg}',
                         v_res ->> 'error',
                         'status ' || (v_res ->> 'status')), 300);

  update ol_lesson_egress
     set egress_id  = v_id,
         filepath   = v_path,
         status     = case when v_id is null then 'failed' else 'active' end,
         error      = case when v_id is null then v_msg end,
         updated_at = now()
   where lesson_id = p_lesson_id;

  -- Never the reply: it echoes the request, and the request carries the key.
  return jsonb_build_object(
    'ok', v_id is not null,
    'egress_id', v_id,
    'msg', case when v_id is null then v_msg end
  );
end;
$$;

-- --------------------------------------------------------- stop, honestly ---

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
  v_ok  boolean;
begin
  select * into v_row from ol_lesson_egress where lesson_id = p_lesson_id;
  if not found or v_row.egress_id is null then
    return jsonb_build_object('skipped', 'no egress');
  end if;

  v_res := ol_livekit_egress(
    'StopEgress',
    jsonb_build_object('egress_id', v_row.egress_id)
  );
  v_ok := (v_res ->> 'status') = '200';

  -- A refused stop used to be filed as a granted one, with nothing in the
  -- error column, and the next tick never tried again.
  if v_ok then
    update ol_lesson_egress
       set status = 'stopping', error = null, updated_at = now()
     where lesson_id = p_lesson_id;
  else
    update ol_lesson_egress
       set error = left(coalesce(v_res #>> '{body,msg}',
                                 v_res ->> 'error',
                                 'stop: status ' || (v_res ->> 'status')), 300),
           updated_at = now()
     where lesson_id = p_lesson_id;
  end if;

  return jsonb_build_object('ok', v_ok);
end;
$$;

-- ------------------------------------------------------- harvest, exactly ---

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
  -- Locked, and terminal states refused. Without both, a second call — a
  -- hand-run tick overlapping the minute job — listed the same finished
  -- egress and inserted the recording a second time. `ol_recordings` has no
  -- unique key on the lesson, so the library simply showed it twice.
  select * into v_row from ol_lesson_egress
   where lesson_id = p_lesson_id for update;
  if not found or v_row.egress_id is null then
    return jsonb_build_object('skipped', 'no egress');
  end if;
  if v_row.status in ('complete', 'failed') then
    return jsonb_build_object('skipped', 'already ' || v_row.status);
  end if;

  v_res := ol_livekit_egress(
    'ListEgress',
    jsonb_build_object('egress_id', v_row.egress_id)
  );
  v_info := v_res #> '{body,items,0}';

  if v_info is null then
    -- LiveKit does not keep finished egress info for ever. Left alone, the
    -- job sat at 'stopping' re-listing once a minute with nothing written
    -- anywhere, and the lesson was lost in silence.
    if v_row.updated_at < now() - interval '30 minutes' then
      update ol_lesson_egress
         set status = 'failed',
             error = 'LiveKit bu yozuvni endi ko''rsatmayapti',
             updated_at = now()
       where lesson_id = p_lesson_id;
    end if;
    return jsonb_build_object('skipped', 'not listed');
  end if;

  v_status := v_info ->> 'status';
  if v_status in ('EGRESS_STARTING', 'EGRESS_ACTIVE', 'EGRESS_ENDING') then
    return jsonb_build_object('waiting', v_status);
  end if;

  if v_status <> 'EGRESS_COMPLETE' then
    update ol_lesson_egress
       set status = 'failed',
           error = left(coalesce(v_info ->> 'error', v_status), 300),
           updated_at = now()
     where lesson_id = p_lesson_id;
    return jsonb_build_object('failed', v_status);
  end if;

  v_file := v_info #> '{file_results,0}';
  select * into v_lesson from ol_lessons where id = p_lesson_id;

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
    greatest(v_secs, 0),
    'r2://' || coalesce(v_file ->> 'filename', v_row.filepath),
    -- Who was actually there. It counted enrolments, which is the register
    -- rather than the room.
    (select count(*)::int from ol_attendance a where a.lesson_id = p_lesson_id),
    true
  );

  update ol_lesson_egress
     set status = 'complete',
         filepath = coalesce(v_file ->> 'filename', v_row.filepath),
         updated_at = now()
   where lesson_id = p_lesson_id;

  return jsonb_build_object('complete', true);
end;
$$;

-- --------------------------------------------------------------- the tick ---

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
  for r in
    select l.id
      from ol_lessons l
     where l.status = 'live'
       and l.auto_record
       and exists (
         select 1 from ol_room_presence p
          where p.lesson_id = l.id
            and p.last_seen_at > now() - interval '2 minutes'
       )
       -- A clean failure ages out and is tried again. Anything that got as
       -- far as an egress id stays claimed for good.
       and not exists (
         select 1 from ol_lesson_egress e
          where e.lesson_id = l.id
            and not (e.status = 'failed'
                     and e.egress_id is null
                     and e.updated_at < now() - interval '3 minutes')
       )
  loop
    begin
      perform ol_egress_start(r.id);
    exception when others then
      insert into ol_lesson_egress (lesson_id, status, error)
      values (r.id, 'failed', left(sqlerrm, 300))
      on conflict (lesson_id) do update
        set status = 'failed', error = left(sqlerrm, 300), updated_at = now();
    end;
  end loop;

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
         set error = left(sqlerrm, 300), updated_at = now()
       where lesson_id = r.lesson_id;
    end;
  end loop;

  for r in
    select e.lesson_id
      from ol_lesson_egress e
     where e.status in ('stopping', 'active')
       and e.egress_id is not null
       -- Not one that started seconds ago in this very tick: it can only be
       -- EGRESS_STARTING, and the call costs the transaction ten seconds of
       -- somebody else's latency.
       and e.started_at < now() - interval '30 seconds'
  loop
    begin
      perform ol_egress_harvest(r.lesson_id);
    exception when others then
      update ol_lesson_egress
         set error = left(sqlerrm, 300), updated_at = now()
       where lesson_id = r.lesson_id;
    end;
  end loop;
end;
$$;

-- ------------------------------------------------------ signing, robustly ---

-- Percent-encoding, the S3 way: unreserved characters stand, everything else
-- becomes %XX of its UTF-8 bytes. A filename with a space or an ampersand
-- would otherwise cut the query string in half and could never verify.
create or replace function ol_uri_escape(p_text text)
returns text
language sql
immutable
set search_path = public
as $$
  select coalesce(string_agg(
    case
      when ch ~ '^[A-Za-z0-9._~-]$' then ch
      else (
        select string_agg('%' || upper(substring(hex from i for 2)), '')
          from (select encode(convert_to(ch, 'UTF8'), 'hex') as hex) h,
               generate_series(1, length(h.hex), 2) as i
      )
    end, '' order by ord), '')
    from regexp_split_to_table(p_text, '') with ordinality as s(ch, ord);
$$;

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
  v_secs   integer;
begin
  select * into v_s3 from ol_egress_config where id;
  if not found then
    raise exception 'ol_egress_config bo''sh' using errcode = '42704';
  end if;

  -- S3 will not sign for longer than a week, and a pasted endpoint with a
  -- trailing slash produced a doubled path and a host that never matched.
  v_secs := least(greatest(coalesce(p_seconds, 3600), 1), 604800);
  v_host := regexp_replace(v_s3.s3_endpoint, '^https?://|/+$', '', 'g');
  v_scope := v_date || '/' || v_s3.s3_region || '/s3/aws4_request';
  v_path := '/' || ol_uri_escape(v_s3.s3_bucket) || '/' || (
    select string_agg(ol_uri_escape(part), '/' order by ord)
      from regexp_split_to_table(p_key, '/') with ordinality as t(part, ord)
  );

  v_query :=
    'X-Amz-Algorithm=AWS4-HMAC-SHA256'
    || '&X-Amz-Credential='
    || replace(v_s3.s3_access_key || '/' || v_scope, '/', '%2F')
    || '&X-Amz-Date=' || v_stamp
    || '&X-Amz-Expires=' || v_secs::text
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

  v_key := extensions.hmac(
    convert_to(v_date, 'UTF8'),
    convert_to('AWS4' || v_s3.s3_secret, 'UTF8'),
    'sha256'
  );
  v_key := extensions.hmac(convert_to(v_s3.s3_region, 'UTF8'), v_key, 'sha256');
  v_key := extensions.hmac(convert_to('s3', 'UTF8'), v_key, 'sha256');
  v_key := extensions.hmac(convert_to('aws4_request', 'UTF8'), v_key, 'sha256');
  v_sig := encode(
    extensions.hmac(convert_to(v_sts, 'UTF8'), v_key, 'sha256'),
    'hex'
  );

  return 'https://' || v_host || v_path || '?' || v_query
         || '&X-Amz-Signature=' || v_sig;
end;
$$;

-- --------------------------------------------------------- who may look ---

-- Was every lesson in the school, to every signed-in account. The comment
-- said "for anybody in the room"; the view had no notion of a room.
create or replace view ol_v_lesson_recording
with (security_invoker = false)
as
select e.lesson_id, e.status
  from ol_lesson_egress e
 where ol_is_staff()
    or exists (
      select 1 from ol_enrollments en
       where en.lesson_id = e.lesson_id
         and en.student_id = auth.uid()
    );

grant select on ol_v_lesson_recording to authenticated;

revoke execute on function ol_egress_start(uuid) from public, anon, authenticated;
revoke execute on function ol_egress_stop(uuid) from public, anon, authenticated;
revoke execute on function ol_egress_harvest(uuid) from public, anon, authenticated;
revoke execute on function ol_egress_tick() from public, anon, authenticated;
revoke execute on function ol_s3_presign(text, integer) from public, anon, authenticated;
revoke execute on function ol_uri_escape(text) from public, anon;
