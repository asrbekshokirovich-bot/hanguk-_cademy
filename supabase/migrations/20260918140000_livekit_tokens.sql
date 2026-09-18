-- Camera and microphone: the server half.
--
-- LiveKit authenticates every participant with a short-lived JWT signed by the
-- project's API secret. The secret therefore decides who may join which room
-- and as whom — it is exactly as dangerous as `service_role`, and it must
-- never reach a client. Anyone who opens the .exe with a hex editor finds
-- every string compiled into it.
--
-- The conventional place to sign these is an Edge Function. This project has
-- tried to deploy one five times and got a 404 every time (see HANDOFF.md
-- §7), so the token is minted here instead — the same choice, for the same
-- reason, as `ol_admin_create_user`. The secret lives in a table no client
-- can read; a SECURITY DEFINER function reads it, checks that the caller
-- actually belongs in the room, and hands back a token that is good for one
-- lesson and six hours.

-- ----------------------------------------------------------- the secret ---

create table if not exists ol_livekit_config (
  -- One row, enforced. A second row would be a second answer to "which
  -- project are we on", and the function would have to guess.
  id         boolean primary key default true check (id),
  ws_url     text not null,
  api_key    text not null,
  api_secret text not null,
  updated_at timestamptz not null default now()
);

alter table ol_livekit_config enable row level security;

-- No policies, deliberately. RLS with zero policies denies everything to
-- everyone except the table owner and SECURITY DEFINER functions — which is
-- precisely the intent. An empty policy list here is not an oversight; it is
-- the mechanism.
revoke all on ol_livekit_config from anon, authenticated;

-- ------------------------------------------------------- JWT, by hand ---

-- base64url, the JWT variant: '+' and '/' become '-' and '_', and the '='
-- padding goes. Postgres has no builtin for this, and pgjwt is an extension
-- Supabase no longer ships on every project — writing the twelve characters
-- of translation here costs less than a dependency that may not exist.
create or replace function ol_b64url(p_data bytea)
returns text
language sql
immutable
set search_path = public
as $$
  select translate(
    replace(encode(p_data, 'base64'), E'\n', ''),
    '+/=', '-_'
  );
$$;

-- Signs a payload as a compact HS256 JWT.
--
-- Not exposed to anyone: it takes the secret as an argument, so a caller who
-- could reach it could sign whatever they liked.
create or replace function ol_jwt_hs256(p_payload jsonb, p_secret text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v_header text := ol_b64url(convert_to('{"alg":"HS256","typ":"JWT"}', 'utf8'));
  v_body   text := ol_b64url(convert_to(p_payload::text, 'utf8'));
  v_signed text;
begin
  v_signed := v_header || '.' || v_body;
  return v_signed || '.' || ol_b64url(
    extensions.hmac(convert_to(v_signed, 'utf8'),
                    convert_to(p_secret, 'utf8'),
                    'sha256')
  );
end;
$$;

revoke execute on function ol_jwt_hs256(jsonb, text) from public, anon,
  authenticated;
revoke execute on function ol_b64url(bytea) from public, anon, authenticated;

-- ------------------------------------------------------------- the grant ---

-- What the app calls before connecting.
--
-- Returns nothing useful unless the lesson is genuinely on air. A token for a
-- lesson that has not started is a token someone can sit on until it has.
create or replace function ol_livekit_join(p_lesson_id uuid)
returns table (url text, token text, room text, can_publish boolean)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_cfg      ol_livekit_config%rowtype;
  v_uid      uuid := auth.uid();
  v_name     text;
  v_is_host  boolean;
  v_now      bigint := extract(epoch from now())::bigint;
  v_room     text;
begin
  if v_uid is null then
    raise exception 'Tizimga kirilmagan' using errcode = '42501';
  end if;

  select * into v_cfg from ol_livekit_config where id;
  if not found then
    raise exception
      'LiveKit sozlanmagan. ol_livekit_config jadvaliga qiymat kiriting.'
      using errcode = '42704';
  end if;

  if not exists (
    select 1 from ol_lessons l
     where l.id = p_lesson_id and l.status = 'live'
  ) then
    raise exception 'Bu dars hozir efirda emas' using errcode = '42501';
  end if;

  select coalesce(p.full_name, 'Foydalanuvchi')
    into v_name
    from ol_profiles p
   where p.user_id = v_uid;
  v_name := coalesce(v_name, 'Foydalanuvchi');

  -- The teacher of this lesson, or either administrator tier. Only they may
  -- close the room behind them; everyone else is a guest in it.
  v_is_host := ol_is_admin() or exists (
    select 1
      from ol_lessons l
      join ol_teachers t on t.id = l.teacher_id
     where l.id = p_lesson_id and t.user_id = v_uid
  );

  -- Derived, not stored. A room name that lives in a column is a room name
  -- that can disagree with the lesson it belongs to.
  v_room := 'lesson_' || p_lesson_id::text;

  return query
  select
    v_cfg.ws_url,
    ol_jwt_hs256(
      jsonb_build_object(
        'iss', v_cfg.api_key,
        'sub', v_uid::text,
        'name', v_name,
        'nbf', v_now - 10,
        -- Six hours: longer than any lesson, short enough that a leaked
        -- token is not a standing invitation.
        'exp', v_now + 21600,
        'video', jsonb_build_object(
          'room', v_room,
          'roomJoin', true,
          -- Everyone may turn their own camera and microphone on: this is a
          -- classroom, and a student who cannot answer out loud is watching
          -- television. Whether they *do* is the button on their screen.
          'canPublish', true,
          'canSubscribe', true,
          'canPublishData', true,
          -- Ending the room for everybody is the teacher's alone.
          'roomAdmin', v_is_host
        )
      ),
      v_cfg.api_secret
    ),
    v_room,
    true;
end;
$$;

revoke execute on function ol_livekit_join(uuid) from public, anon;
grant execute on function ol_livekit_join(uuid) to authenticated;

-- Whether the app should offer media at all. Called before the room opens so
-- the screen can say "video sozlanmagan" instead of failing to connect.
create or replace function ol_livekit_ready()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from ol_livekit_config where id);
$$;

revoke execute on function ol_livekit_ready() from public, anon;
grant execute on function ol_livekit_ready() to authenticated;
